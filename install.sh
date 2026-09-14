#!/usr/bin/env bash
# ── HVM Customize \u2014 automatic installer ─────────────────────────────
# Owner & credit: @blaze_gazzer
#
# Run this on your VPS:
#   chmod +x install.sh && ./install.sh
#
# It will:
#   1. Check/install Node.js and Docker if missing
#   2. Ask for your admin username, password, and panel name
#   3. Ask which tunnel method you want (Cloudflare / Ngrok / Codespaces)
#   4. Write .env, install dependencies, start the panel
# ─────────────────────────────────────────────────────────────────────

set -e

# ── Colors ──────────────────────────────────────────────────────────
C_ACCENT='\033[0;35m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_DIM='\033[2m'
C_RESET='\033[0m'

banner() {
  echo -e "${C_ACCENT}"
  echo "  _  ___     ____  __"
  echo " | || \\ \\   / /  \\/  |"
  echo " | __ |\\ \\ / /| |\\/| |"
  echo " |_||_| \\_/ |_|  |_|"
  echo -e "${C_RESET}${C_DIM} HVM Customize \u2014 automatic installer${C_RESET}"
  echo -e "${C_DIM} owner: @blaze_gazzer${C_RESET}"
  echo ""
}

step() { echo -e "${C_ACCENT}\u25b8${C_RESET} $1"; }
ok()   { echo -e "${C_GREEN}\u2713${C_RESET} $1"; }
warn() { echo -e "${C_YELLOW}!${C_RESET} $1"; }
err()  { echo -e "${C_RED}\u2717${C_RESET} $1"; }

banner

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 1. Check / install Node.js ───────────────────────────────────────
step "Checking Node.js..."
if command -v node >/dev/null 2>&1 && [ "$(node -v | sed 's/v//' | cut -d. -f1)" -ge 18 ] 2>/dev/null; then
  ok "Node.js $(node -v) found"
else
  warn "Node.js 18+ not found. Installing via NodeSource..."
  if command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif command -v yum >/dev/null 2>&1; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo yum install -y nodejs
  else
    err "Could not detect apt or yum. Install Node.js 18+ manually, then re-run this script."
    exit 1
  fi
  ok "Node.js installed: $(node -v)"
fi

# ── 2. Check / install Docker ────────────────────────────────────────
step "Checking Docker..."
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok "Docker is installed and running"
else
  if command -v docker >/dev/null 2>&1; then
    warn "Docker is installed but not accessible. Trying to start it..."
    sudo systemctl start docker 2>/dev/null || true
    if ! docker info >/dev/null 2>&1; then
      err "Docker still isn't accessible. You may need to add your user to the docker group:"
      echo "    sudo usermod -aG docker \$USER && newgrp docker"
      exit 1
    fi
  else
    warn "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo systemctl enable --now docker
    ok "Docker installed"
    warn "You may need to log out and back in for docker group permissions to apply."
  fi
fi

# ── 3. Gather setup info from the user ───────────────────────────────
echo ""
step "Panel setup"
echo ""

read -rp "$(echo -e "${C_DIM}Name your HVM panel${C_RESET} [HVM Manager]: ")" PANEL_NAME
PANEL_NAME=${PANEL_NAME:-"HVM Manager"}

read -rp "$(echo -e "${C_DIM}Admin username${C_RESET} [admin]: ")" ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

while true; do
  read -rsp "$(echo -e "${C_DIM}Admin password${C_RESET}: ")" ADMIN_PASS
  echo ""
  if [ -z "$ADMIN_PASS" ]; then
    warn "Password can't be empty."
    continue
  fi
  read -rsp "$(echo -e "${C_DIM}Confirm password${C_RESET}: ")" ADMIN_PASS_CONFIRM
  echo ""
  if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
    warn "Passwords don't match, try again."
    continue
  fi
  break
done

read -rp "$(echo -e "${C_DIM}Port to run the panel on${C_RESET} [5000]: ")" PANEL_PORT
PANEL_PORT=${PANEL_PORT:-5000}

# ── 4. Tunnel method choice ──────────────────────────────────────────
echo ""
step "How do you want to expose the panel to the internet?"
echo "  1) Cloudflare Tunnel"
echo "  2) Ngrok"
echo "  3) GitHub Codespaces port forwarding"
echo "  4) Skip \u2014 local network / localhost only"
echo ""
read -rp "$(echo -e "${C_DIM}Choose 1-4${C_RESET} [4]: ")" TUNNEL_CHOICE
TUNNEL_CHOICE=${TUNNEL_CHOICE:-4}

# ── 5. Write .env ─────────────────────────────────────────────────────
step "Writing configuration..."
JWT_SECRET=$(node -e "console.log(require('crypto').randomBytes(48).toString('hex'))" 2>/dev/null || openssl rand -hex 48)

cat > .env <<EOF
PORT=${PANEL_PORT}
JWT_SECRET=${JWT_SECRET}
ADMIN_USERNAME=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASS}
DB_PATH=./data/hvm.db
DOCKER_SOCKET=/var/run/docker.sock
DEFAULT_RAM_MB=1024
DEFAULT_CPU_CORES=1
PANEL_NAME=${PANEL_NAME}
OWNER_NAME=blaze_gazzer
DISCORD_LINK=
TELEGRAM_LINK=
EOF
ok ".env written"

# ── 6. Install dependencies ──────────────────────────────────────────
step "Installing dependencies (this can take a minute)..."
npm install --silent
ok "Dependencies installed"

# ── 7. Initialize database / admin account ───────────────────────────
step "Creating admin account..."
npm run init --silent
ok "Admin account ready: ${ADMIN_USER}"

# ── 8. Start the panel in the background ─────────────────────────────
step "Starting HVM Manager..."
mkdir -p logs
nohup npm start > logs/panel.log 2>&1 &
PANEL_PID=$!
echo $PANEL_PID > .panel.pid
sleep 2

if kill -0 $PANEL_PID 2>/dev/null; then
  ok "Panel running (PID $PANEL_PID) on http://localhost:${PANEL_PORT}"
else
  err "Panel failed to start. Check logs/panel.log for details."
  exit 1
fi

# ── 9. Set up the chosen tunnel ──────────────────────────────────────
echo ""
case $TUNNEL_CHOICE in
  1)
    step "Setting up Cloudflare Tunnel..."
    if ! command -v cloudflared >/dev/null 2>&1; then
      warn "cloudflared not found, installing..."
      if command -v apt-get >/dev/null 2>&1; then
        curl -fsSL https://pkg.cloudflare.com/cloudflared-stable-linux-amd64.deb -o /tmp/cloudflared.deb
        sudo dpkg -i /tmp/cloudflared.deb
      else
        err "Auto-install only supported on apt-based systems. Install cloudflared manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
      fi
    fi
    if command -v cloudflared >/dev/null 2>&1; then
      ok "Launching quick tunnel (no Cloudflare account needed)..."
      nohup cloudflared tunnel --url "http://localhost:${PANEL_PORT}" > logs/cloudflared.log 2>&1 &
      echo $! > .cloudflared.pid
      sleep 4
      TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' logs/cloudflared.log | head -n1)
      if [ -n "$TUNNEL_URL" ]; then
        ok "Public URL: ${TUNNEL_URL}"
      else
        warn "Tunnel starting \u2014 check logs/cloudflared.log for your public URL in a few seconds:"
        echo "    tail -f logs/cloudflared.log"
      fi
      echo -e "${C_DIM}For a permanent tunnel with your own domain, use: cloudflared tunnel login${C_RESET}"
    fi
    ;;
  2)
    step "Setting up Ngrok..."
    if ! command -v ngrok >/dev/null 2>&1; then
      warn "ngrok not found, installing..."
      curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null 2>&1 || true
      if command -v apt-get >/dev/null 2>&1; then
        echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
        sudo apt-get update && sudo apt-get install -y ngrok
      else
        err "Auto-install only supported on apt-based systems. Install ngrok manually: https://ngrok.com/download"
      fi
    fi
    if command -v ngrok >/dev/null 2>&1; then
      warn "Ngrok needs an authtoken (free at https://dashboard.ngrok.com/get-started/your-authtoken)"
      read -rp "$(echo -e "${C_DIM}Paste your ngrok authtoken (or leave blank to skip)${C_RESET}: ")" NGROK_TOKEN
      if [ -n "$NGROK_TOKEN" ]; then
        ngrok config add-authtoken "$NGROK_TOKEN"
        nohup ngrok http "${PANEL_PORT}" --log=stdout > logs/ngrok.log 2>&1 &
        echo $! > .ngrok.pid
        sleep 4
        ok "Ngrok running. Check your public URL at: http://localhost:4040"
      else
        warn "Skipped \u2014 run 'ngrok http ${PANEL_PORT}' manually later."
      fi
    fi
    ;;
  3)
    step "GitHub Codespaces port forwarding"
    echo "    In your Codespace:"
    echo "    1. Open the 'Ports' tab (bottom panel)"
    echo "    2. Find port ${PANEL_PORT}"
    echo "    3. Right-click \u2192 Port Visibility \u2192 Public"
    echo "    4. Use the generated *.app.github.dev URL"
    ;;
  *)
    warn "Skipped tunnel setup. Panel is reachable at http://localhost:${PANEL_PORT} on this machine's network."
    ;;
esac

# ── 10. Done ──────────────────────────────────────────────────────────
echo ""
echo -e "${C_GREEN}\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557${C_RESET}"
echo -e "${C_GREEN}\u2551${C_RESET}  ${PANEL_NAME} is up and running!"
echo -e "${C_GREEN}\u2551${C_RESET}"
echo -e "${C_GREEN}\u2551${C_RESET}  Local:    http://localhost:${PANEL_PORT}"
echo -e "${C_GREEN}\u2551${C_RESET}  Login:    ${ADMIN_USER}"
echo -e "${C_GREEN}\u2551${C_RESET}  Password: (the one you entered)"
echo -e "${C_GREEN}\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d${C_RESET}"
echo ""
echo -e "${C_DIM}To stop the panel:  kill \$(cat .panel.pid)${C_RESET}"
echo -e "${C_DIM}To view logs:       tail -f logs/panel.log${C_RESET}"
echo -e "${C_DIM}HVM Customize \u2014 crafted by @blaze_gazzer${C_RESET}"
echo ""
