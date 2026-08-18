#!/usr/bin/env bash
# deploy.sh — create the KV namespace (first run), push both bearer tokens as
# Worker secrets, and deploy pace-metrics.
#
# Needs a Cloudflare API token with exactly:
#   Account -> Workers Scripts     -> Edit
#   Account -> Workers KV Storage  -> Edit
# Export it as CLOUDFLARE_API_TOKEN before running. The account's other token
# (CF_API_TOKEN, DNS Write) cannot do this and is deliberately not reused.
#
# The bearer tokens themselves come from the age-encrypted pace-publish.env, so
# this script never invents or prints a credential.
set -euo pipefail

cd "$(dirname "$0")"
ENV_FILE="${HOME}/.config/analysis/claude-usage/pace-publish.env"

log() { printf '%s deploy: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || {
  echo "CLOUDFLARE_API_TOKEN is unset — mint one with Workers Scripts:Edit + Workers KV Storage:Edit" >&2
  exit 1
}
# wrangler prefers CF_API_TOKEN when both are set, and that one is DNS-only.
unset CF_API_TOKEN

[ -r "$ENV_FILE" ] || { echo "missing $ENV_FILE (chezmoi apply first)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$ENV_FILE"
: "${PACE_READ_TOKEN:?not set in $ENV_FILE}"
: "${PACE_WRITE_TOKEN:?not set in $ENV_FILE}"

# Look the namespace up rather than parsing `create` output: wrangler's success
# message format is not a contract, and looking it up makes a re-run after a
# failed deploy idempotent instead of creating a second namespace.
kv_id() {
  wrangler kv namespace list 2>/dev/null \
    | sed -n '/^[[:space:]]*\[/,$p' \
    | jq -r '.[]? | select(.title | test("METRICS$")) | .id' 2>/dev/null \
    | grep -E '^[0-9a-f]{32}$' | head -1
}

if grep -q REPLACE_WITH_KV_NAMESPACE_ID wrangler.toml; then
  id="$(kv_id)"
  if [ -n "$id" ]; then
    log "reusing existing KV namespace $id"
  else
    log "creating KV namespace METRICS"
    wrangler kv namespace create METRICS || true
    id="$(kv_id)"
  fi
  [ -n "$id" ] || { echo "no KV namespace ending in METRICS found — check 'wrangler kv namespace list'" >&2; exit 1; }
  sed -i '' "s/REPLACE_WITH_KV_NAMESPACE_ID/$id/" wrangler.toml
  log "KV namespace $id written into wrangler.toml"
fi

log "pushing Worker secrets"
printf '%s' "$PACE_READ_TOKEN"  | wrangler secret put READ_TOKEN  >/dev/null
printf '%s' "$PACE_WRITE_TOKEN" | wrangler secret put WRITE_TOKEN >/dev/null

log "deploying"
wrangler deploy
