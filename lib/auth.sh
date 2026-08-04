#!/usr/bin/env bash
# Shared FlakeHub auth helpers for the hooks and the login keepalive.
#
# FlakeHub sessions minted from Buildkite OIDC are short-lived and the netrc
# is shared host-wide (one determinate-nixd identity per host), so renewal is
# deadline-driven off the token's own iat/exp rather than a fixed interval.

NETRC_FILE="${NETRC_FILE:-/nix/var/determinate/netrc}"

b64_decode() {
  # macOS base64 predates -d; GNU has both.
  printf '%s' "$1" | base64 -d 2>/dev/null && return 0
  printf '%s' "$1" | base64 -D 2>/dev/null
}

# Print "iat exp" of the FlakeHub JWT in the netrc. Fails if absent or not a
# decodable JWT — callers treat that as a hard error after a login, never as
# a degraded mode.
token_times() {
  local tok payload pad json iat exp
  tok="$(grep -m1 -oE 'password [^[:space:]]+' "$NETRC_FILE" 2>/dev/null | cut -d' ' -f2)"
  [ -n "${tok:-}" ] || return 1
  payload="$(printf '%s' "$tok" | cut -d. -f2 | tr '_-' '/+')"
  pad=$(( (4 - ${#payload} % 4) % 4 ))
  while [ "$pad" -gt 0 ]; do payload="${payload}="; pad=$((pad - 1)); done
  json="$(b64_decode "$payload")" || return 1
  iat="$(printf '%s' "$json" | grep -oE '"iat":[0-9]+' | head -1 | cut -d: -f2)"
  exp="$(printf '%s' "$json" | grep -oE '"exp":[0-9]+' | head -1 | cut -d: -f2)"
  { [ -n "$iat" ] && [ -n "$exp" ]; } || return 1
  echo "$iat $exp"
}

# Renew inside the final quarter of the token's lifetime, with at least 90s of
# headroom for login latency and one retry.
renew_at() {
  local iat="$1" exp="$2" margin
  margin=$(( (exp - iat) / 4 ))
  [ "$margin" -lt 90 ] && margin=90
  echo $(( exp - margin ))
}

cache_ok() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    --netrc-file "$NETRC_FILE" https://cache.flakehub.com/nix-cache-info || true)"
  case "$code" in 2*) return 0 ;; *) return 1 ;; esac
}

# True when the current token is missing, near expiry, or rejected by the
# cache (catches server-side revocation that exp alone can't).
login_needed() {
  local times iat exp
  times="$(token_times)" || return 0
  read -r iat exp <<<"$times"
  [ "$(date +%s)" -ge "$(renew_at "$iat" "$exp")" ] && return 0
  cache_ok || return 0
  return 1
}

# Log in via this job's Buildkite OIDC identity. Fails if the resulting netrc
# token is not a decodable JWT.
flakehub_login() {
  if ! determinate-nixd auth login buildkite; then
    echo "FlakeHub login failed, trying one more time..."
    determinate-nixd auth login buildkite
  fi
  token_times >/dev/null || {
    echo "FATAL: netrc token after login is not a decodable JWT; refusing to continue" >&2
    return 1
  }
}
