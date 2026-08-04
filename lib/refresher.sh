#!/usr/bin/env bash
# FlakeHub login keepalive: renews the shared netrc token just before expiry
# so jobs of any duration keep cache reads and private-flake access.
# Usage: refresher.sh <job-process-pid>
set -uo pipefail

job_pid="${1:?job process pid required}"
lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/auth.sh
source "${lib_dir}/auth.sh"

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"; }

renew() {
  # De-herd: concurrent jobs on one host share the netrc and hit the same
  # deadline; jitter + re-check lets the first winner renew for everyone.
  sleep $(( RANDOM % 20 ))
  login_needed || { log "another job renewed the token; nothing to do"; return 0; }
  local attempt
  for attempt in 1 2 3; do
    if flakehub_login; then
      log "renewed FlakeHub token (attempt ${attempt})"
      return 0
    fi
    log "renewal attempt ${attempt} failed"
    sleep 30
  done
  return 1
}

log "keepalive started (job pid ${job_pid})"
while kill -0 "$job_pid" 2>/dev/null; do
  if login_needed; then
    renew || { log "ERROR: could not renew FlakeHub token; exiting"; exit 1; }
  fi
  times="$(token_times)" || { log "ERROR: netrc token undecodable; exiting"; exit 1; }
  read -r iat exp <<<"$times"
  sleep_for=$(( $(renew_at "$iat" "$exp") - $(date +%s) ))
  # Cap so renewals by other jobs (which move the deadline out) are noticed;
  # floor so a pathological token can't busy-loop us.
  [ "$sleep_for" -gt 600 ] && sleep_for=600
  [ "$sleep_for" -lt 15 ] && sleep_for=15
  sleep "$sleep_for"
done
log "job process gone; exiting"
