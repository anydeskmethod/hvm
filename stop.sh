#!/usr/bin/env bash
# ── Stop HVM Manager and any tunnel it started ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

stop_pid_file() {
  if [ -f "$1" ]; then
    PID=$(cat "$1")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID"
      echo "Stopped $2 (PID $PID)"
    fi
    rm -f "$1"
  fi
}

stop_pid_file .panel.pid "HVM Manager"
stop_pid_file .cloudflared.pid "Cloudflare Tunnel"
stop_pid_file .ngrok.pid "Ngrok"

echo "Done."
