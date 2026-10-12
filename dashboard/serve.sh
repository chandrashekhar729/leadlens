#!/usr/bin/env bash
# Ensures the LeadLens dashboard is running. Called by the SessionStart hook on
# every Claude session (terminal or VS Code) and safe to run by hand.
# Config: LEADLENS_PORT (default 8850) and LEADLENS_PROJECTS, read from
# <plugin>/dashboard/.env then <plugin data dir>/.env (per user, survives updates).
here="$(cd "$(dirname "$0")" && pwd)"
data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/leadlens-leadlens}"
for f in "$here/.env" "$data/.env"; do [ -f "$f" ] && . "$f"; done
export LEADLENS_PORT="${LEADLENS_PORT:-8850}" LEADLENS_PROJECTS="${LEADLENS_PROJECTS:-}"
command -v python3 >/dev/null 2>&1 || exit 0
ip=$(hostname -I 2>/dev/null | awk '{print $1}')
url="http://${ip:-localhost}:$LEADLENS_PORT/"
# ponytail: any listener on the port counts as ours; add a /health probe if that ever misleads
if (exec 3<>"/dev/tcp/127.0.0.1/$LEADLENS_PORT") 2>/dev/null; then
  echo "LeadLens dashboard: $url"; exit 0
fi
mkdir -p "$data"
# own session, no inherited fds: outlives the hook and the Claude process
setsid nohup python3 "$here/serve.py" </dev/null >>"$data/dashboard.log" 2>&1 &
echo "LeadLens dashboard started: $url"
