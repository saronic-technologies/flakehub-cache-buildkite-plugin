#!/usr/bin/env bash
# Force-upload store paths to a FlakeHub cache, bypassing magic-nix-cache's
# `get-missing-paths` plan. FlakeHub answers that call org-wide ("not
# missing" for any path that exists in any of the org's caches) while narinfo
# reads are scoped to the token's cache, so mnc never (re)registers a path
# the elastic twin built first and the -slurm caches stay empty. A 404 on
# <hash>.narinfo with the job's token means "this cache lacks it": PUT those
# straight to upload-path.
#
# Wire protocol = attic `PUT /_api/v1/upload-path`: JSON `UploadPathNarInfo`
# in `X-Attic-Nar-Info` (or, >= 4 KiB, prepended to the body with
# `X-Attic-Nar-Info-Preamble-Size`), raw NAR as the body, netrc auth.
#
# usage: force-upload.sh [--dry-run] [--diagnose] CACHE < store-paths
#   CACHE   "<org-uuid>:<project-uuid>" (mnc logs it: `Using cache "..."`)
#   stdin   one /nix/store path per line; .drv entries are skipped (mnc
#           uploads those fine, nobody else ever has them)
# env: FLAKEHUB_CACHE_FORCE_UPLOAD=0          skip entirely (kill switch)
#      FLAKEHUB_CACHE_FORCE_UPLOAD_DRY_RUN=1  probe and plan, upload nothing
#      NETRC_FILE (default /nix/var/determinate/netrc)
#      FLAKEHUB_CACHE_SERVER (default https://cache.flakehub.com)
#      FORCE_UPLOAD_PARALLEL (default 4), FORCE_UPLOAD_MAX_TIME (seconds per
#      PUT, default 1800)
#
# Output: one `force-upload:` line per path acted on and one summary line.
# This script never fails the job: every error is a WARNING line and the
# exit status is always 0.
set -uo pipefail

log() { echo "force-upload: $*"; }
warn() { echo "force-upload: WARNING: $*"; }
# shellcheck disable=SC2317  # reached through the EXIT trap
on_exit() {
  (( $1 == 0 )) || warn "aborted with status $1; FlakeHub cache may still lack nsh outputs"
  exit 0
}
trap 'on_exit $?' EXIT

if [[ "${FLAKEHUB_CACHE_FORCE_UPLOAD:-1}" == "0" ]]; then
  log "disabled (FLAKEHUB_CACHE_FORCE_UPLOAD=0); nothing uploaded"
  exit 0
fi

dry_run=0; diagnose=0
[[ "${FLAKEHUB_CACHE_FORCE_UPLOAD_DRY_RUN:-0}" == "1" ]] && dry_run=1
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --diagnose) diagnose=1 ;;
    *) warn "unknown flag $1; nothing uploaded"; exit 0 ;;
  esac
  shift
done
cache="${1:-}"
if [[ -z "$cache" ]]; then
  warn "no cache name (<org>:<project>) given; nothing uploaded"
  exit 0
fi
for tool in nix jq curl python3 xargs; do
  command -v "$tool" >/dev/null || { warn "$tool not on PATH; nothing uploaded"; exit 0; }
done

netrc="${NETRC_FILE:-/nix/var/determinate/netrc}"
server="${FLAKEHUB_CACHE_SERVER:-https://cache.flakehub.com}"
parallel="${FORCE_UPLOAD_PARALLEL:-4}"
max_time="${FORCE_UPLOAD_MAX_TIME:-1800}"

# The cache API (upload-path, get-missing-paths) wants the netrc password as a Bearer token, which is
# how magic-nix-cache's attic client sends it; HTTP Basic from --netrc-file is answered 403 AccessError.
token="$(python3 - "$netrc" "${server#*://}" <<'PY'
import netrc, sys
try:
    auth = netrc.netrc(sys.argv[1]).authenticators(sys.argv[2].split("/")[0])
    print(auth[2] if auth else "")
except (OSError, netrc.NetrcParseError):
    print("")
PY
)"
if [[ -z "$token" ]]; then
  warn "no entry for ${server#*://} in $netrc; using HTTP Basic from it (the API may refuse it)"
  fh() { curl -s --netrc-file "$netrc" "$@"; }
else
  fh() { curl -s -H "Authorization: Bearer $token" "$@"; }
fi

# Paths the cache does not serve to this token, one per line.
missing_in_cache() {
  local p code
  while IFS= read -r p; do
    [[ -n "$p" && "$p" != *.drv ]] || continue
    code="$(fh --max-time 30 -o /dev/null -w '%{http_code}' -I "$server/$(basename "$p" | cut -c1-32).narinfo")" || true
    case "${code:-000}" in
      200) ;;
      404) echo "$p" ;;
      *) warn "narinfo probe HTTP $code for $p; skipping it" >&2 ;;
    esac
  done
}

# attic's Hash serde accepts "sha256:<64 hex>|<52 nix32>", nix emits SRI.
# shellcheck disable=SC2317  # run by the xargs workers below
nar_info_json() {
  local p="$1"
  nix path-info --json --json-format 1 "$p" 2>/dev/null \
    | jq --compact-output --arg cache "$cache" --arg p "$p" '
        .[$p] as $i
        | { cache: $cache,
            store_path_hash: ($p | split("/")[-1] | .[0:32]),
            store_path: $p,
            references: (($i.references // []) | map(sub("^/nix/store/"; ""))),
            system: null,
            deriver: null,
            sigs: ($i.signatures // []),
            ca: $i.ca,
            nar_hash: $i.narHash,
            nar_size: $i.narSize }' \
    | python3 -I -c '
import json, subprocess, sys
d = json.loads(sys.stdin.read())
hexh = subprocess.run(["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "base16", d["nar_hash"]],
                      capture_output=True, text=True, check=True).stdout.strip()
d["nar_hash"] = "sha256:" + hexh
print(json.dumps(d, separators=(",", ":")))'
}

# One line per path: "PUT <path> -> HTTP <code> <body>" or a WARNING.
# shellcheck disable=SC2317  # run by the xargs workers below
upload_one() {
  local p="$1" json body code
  json="$(nar_info_json "$p")" || { warn "no path info for $p; not uploaded"; return 1; }
  if (( dry_run )); then
    log "would PUT $p (${#json} B nar-info, nar $(jq -r .nar_size <<<"$json") B)"
    return 0
  fi
  if (( ${#json} >= 4096 )); then
    body="$({ printf '%s' "$json"; nix nar pack "$p"; } \
      | fh --max-time "$max_time" -w '\n%{http_code}' -X PUT -T - \
          -H "X-Attic-Nar-Info-Preamble-Size: ${#json}" "$server/_api/v1/upload-path")"
  else
    body="$(nix nar pack "$p" \
      | fh --max-time "$max_time" -w '\n%{http_code}' -X PUT -T - \
          -H "X-Attic-Nar-Info: $json" "$server/_api/v1/upload-path")"
  fi
  code="${body##*$'\n'}"
  if [[ "$code" == 2* ]]; then
    log "PUT $p -> HTTP $code ${body%$'\n'*}"
  else
    warn "PUT $p -> HTTP ${code:-000} ${body%$'\n'*}"
    return 1
  fi
}
export -f log warn fh nar_info_json upload_one
export cache netrc server token dry_run max_time

mapfile -t candidates < <(grep -v '\.drv$' | grep '^/nix/store/' || true)
mapfile -t todo < <(printf '%s\n' "${candidates[@]}" | missing_in_cache)
if (( ${#todo[@]} == 0 )); then
  log "nothing to upload (0 of ${#candidates[@]} candidate path(s) missing from cache $cache)"
  exit 0
fi
log "${#todo[@]} path(s) not in cache $cache (of ${#candidates[@]} candidates)"

if (( diagnose )); then
  # Show FlakeHub's inconsistency on the first path: 404 narinfo above, yet
  # get-missing-paths (what mnc trusts) says it is present.
  h="$(basename "${todo[0]}" | cut -c1-32)"
  answer="$(fh --max-time 30 -X POST -H 'Content-Type: application/json' "$server/_api/v1/get-missing-paths" \
    -d "{\"cache\":\"$cache\",\"store_path_hashes\":[\"$h\"]}" || echo "(request failed)")"
  log "diagnose get-missing-paths for $h: $answer"
fi

# shellcheck disable=SC2016  # $1 is expanded by the worker shell, not here
results="$(printf '%s\n' "${todo[@]}" | xargs -P "$parallel" -I{} bash -c 'upload_one "$1"' _ {} 2>&1)"
printf '%s\n' "$results"
ok="$(grep -c '^force-upload: PUT .* -> HTTP 2' <<<"$results" || true)"
would="$(grep -c '^force-upload: would PUT ' <<<"$results" || true)"
failed=$(( ${#todo[@]} - ok - would ))

if (( dry_run )); then
  log "dry run (FLAKEHUB_CACHE_FORCE_UPLOAD_DRY_RUN); would upload $would of ${#todo[@]} path(s) to cache $cache, uploaded nothing"
  exit 0
fi
left="$(printf '%s\n' "${todo[@]}" | missing_in_cache 2>/dev/null | wc -l)"
log "uploaded $ok of ${#todo[@]} path(s) to cache $cache ($failed failed); $left still 404 after upload"
(( failed == 0 && left == 0 )) || warn "FlakeHub cache $cache may still lack $(( left > failed ? left : failed )) nsh output(s)"
exit 0
