#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/state/automation/upstream-release"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/pipeline.lock"
CURRENT_LOG="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$LOG_DIR"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "pipeline already running"; exit 0; }
log(){ printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$CURRENT_LOG"; }
phase(){ printf '\n== %s ==\n' "$*" | tee -a "$CURRENT_LOG"; }
trap 'log "failed at line $LINENO"' ERR
phase "preflight"
cd "$ROOT_DIR"
log "workspace=$(git rev-parse --short HEAD) branch=$(git branch --show-current)"
log "upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo none)"
phase "fetch upstream"
git fetch upstream --prune
upstream_head=$(git rev-parse upstream/main)
local_head=$(git rev-parse HEAD)
log "local=$local_head upstream=$upstream_head"
if [ "$local_head" = "$upstream_head" ]; then
  log "already synchronized"
  exit 0
fi
phase "sync dev"
git checkout main
git reset --hard "$upstream_head"
phase "validate"
if command -v pnpm >/dev/null 2>&1; then
  pnpm install --frozen-lockfile
  pnpm build
  pnpm test
else
  npm test
fi
phase "promote prod"
git push origin main
phase "state update"
cat > "$STATE_DIR/last-run.json" <<JSON
{"timestampUtc":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","upstreamHead":"$upstream_head","localHead":"$(git rev-parse HEAD)","status":"promoted"}
JSON
log "done"
