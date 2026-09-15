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
echo "  4) Port Buddy (portbuddy.dev)"
echo "  5) Railway (deploy the panel itself, instead of tunneling it)"
echo "  6) Skip \u2014 local network / localhost only"
echo ""
read -rp "$(echo -e "${C_DIM}Choose 1-6${C_RESET} [6]: ")" TUNNEL_CHOICE
TUNNEL_CHOICE=${TUNNEL_CHOICE:-6}

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

# Pre-flight: is the port already occupied (e.g. a previous run still alive,
# or an old process that never got cleaned up)?
port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -i ":$1" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :$1 )" 2>/dev/null | grep -q ":$1"
  else
    (echo > /dev/tcp/127.0.0.1/$1) >/dev/null 2>&1
  fi
}

if port_in_use "$PANEL_PORT"; then
  warn "Port ${PANEL_PORT} is already in use."
  if [ -f .panel.pid ] && kill -0 "$(cat .panel.pid)" 2>/dev/null; then
    warn "It looks like a previous HVM Manager instance (PID $(cat .panel.pid)) is still running."
    read -rp "$(echo -e "${C_DIM}Stop it and continue?${C_RESET} [Y/n]: ")" STOP_OLD
    if [[ ! "$STOP_OLD" =~ ^[Nn]$ ]]; then
      kill "$(cat .panel.pid)" 2>/dev/null || true
      sleep 1
      # Escalate if it's still alive
      if kill -0 "$(cat .panel.pid)" 2>/dev/null; then
        kill -9 "$(cat .panel.pid)" 2>/dev/null || true
        sleep 1
      fi
      rm -f .panel.pid
      ok "Old instance stopped."
    else
      err "Can't start on a port that's already in use. Re-run and choose a different port, or free port ${PANEL_PORT} yourself and try again."
      exit 1
    fi
  else
    err "Something else on this machine is using port ${PANEL_PORT} (not a previous HVM Manager run)."
    echo -e "${C_DIM}  Find out what with:${C_RESET}  sudo lsof -i :${PANEL_PORT}"
    echo -e "${C_DIM}  Or just re-run install.sh and pick a different port.${C_RESET}"
    exit 1
  fi
fi

nohup npm start > logs/panel.log 2>&1 &
PANEL_PID=$!
echo $PANEL_PID > .panel.pid

# Give it a moment, then verify it actually bound the port \u2014 a live PID
# alone isn't proof of success, since `npm start` can stay alive briefly
# even after the underlying `node` process crashes.
sleep 2
PANEL_OK=false
for i in $(seq 1 5); do
  if port_in_use "$PANEL_PORT"; then
    PANEL_OK=true
    break
  fi
  sleep 1
done

if [ "$PANEL_OK" = true ]; then
  ok "Panel running (PID $PANEL_PID) on http://localhost:${PANEL_PORT}"
else
  err "Panel failed to start. Last lines of logs/panel.log:"
  echo ""
  tail -n 15 logs/panel.log 2>/dev/null | sed 's/^/    /'
  echo ""
  err "Fix the issue above, then re-run ./install.sh (or just: npm start)"
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

      echo -ne "${C_DIM}  waiting for public URL"
      TUNNEL_URL=""
      for i in $(seq 1 20); do
        TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' logs/cloudflared.log 2>/dev/null | head -n1)
        if [ -n "$TUNNEL_URL" ]; then break; fi
        echo -ne "."
        sleep 1
      done
      echo -e "${C_RESET}"

      if [ -n "$TUNNEL_URL" ]; then
        ok "Public URL: ${TUNNEL_URL}"
      elif kill -0 "$(cat .cloudflared.pid 2>/dev/null)" 2>/dev/null; then
        warn "cloudflared is running but hasn't printed a URL yet. It may just be slow to connect."
        echo -e "${C_DIM}  Watch for it with:${C_RESET}"
        echo "    tail -f logs/cloudflared.log"
      else
        err "cloudflared process died. Check what went wrong with:"
        echo "    cat logs/cloudflared.log"
        echo -e "${C_DIM}  Or restart just the tunnel with:${C_RESET}"
        echo "    cloudflared tunnel --url http://localhost:${PANEL_PORT}"
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
  4)
    step "Setting up Port Buddy..."
    if ! command -v portbuddy >/dev/null 2>&1; then
      warn "portbuddy not found, installing..."
      # Port Buddy officially ships via Homebrew, Docker, or a manual binary
      # download \u2014 there's no curl-pipe installer, so try Homebrew (works on
      # Linux via Linuxbrew) and fall back to pointing at the manual download.
      if command -v brew >/dev/null 2>&1; then
        brew install amak-tech/tap/portbuddy 2>/dev/null && ok "Port Buddy CLI installed via Homebrew" \
          || warn "Homebrew install failed."
      fi
      if ! command -v portbuddy >/dev/null 2>&1; then
        warn "No supported auto-install path found on this system."
        echo -e "${C_DIM}  Install manually (pick one):${C_RESET}"
        echo "    - Homebrew (Linux/macOS): brew install amak-tech/tap/portbuddy"
        echo "    - Manual binary: https://portbuddy.dev/install"
        echo "    - Docker: docker pull amaktech/portbuddy:latest"
      fi
    fi

    if command -v portbuddy >/dev/null 2>&1; then
      warn "Port Buddy requires a free account and API token."
      echo -e "${C_DIM}  1. Sign up / log in at https://portbuddy.dev/login${C_RESET}"
      echo -e "${C_DIM}  2. Generate a token at https://portbuddy.dev/app/tokens${C_RESET}"
      read -rp "$(echo -e "${C_DIM}Paste your Port Buddy API token (or leave blank to skip)${C_RESET}: ")" PORTBUDDY_TOKEN
      if [ -n "$PORTBUDDY_TOKEN" ]; then
        if portbuddy init "$PORTBUDDY_TOKEN" >/dev/null 2>&1; then
          ok "Authenticated with Port Buddy"
          nohup portbuddy "${PANEL_PORT}" > logs/portbuddy.log 2>&1 &
          echo $! > .portbuddy.pid

          echo -ne "${C_DIM}  waiting for public URL"
          TUNNEL_URL=""
          for i in $(seq 1 20); do
            TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.portbuddy\.dev' logs/portbuddy.log 2>/dev/null | head -n1)
            if [ -n "$TUNNEL_URL" ]; then break; fi
            echo -ne "."
            sleep 1
          done
          echo -e "${C_RESET}"

          if [ -n "$TUNNEL_URL" ]; then
            ok "Public URL: ${TUNNEL_URL}"
          else
            warn "portbuddy is running but hasn't printed a URL yet."
            echo -e "${C_DIM}  Check with:${C_RESET}  tail -f logs/portbuddy.log"
          fi
        else
          err "portbuddy init failed \u2014 check your token and try again manually:"
          echo "    portbuddy init <YOUR_TOKEN>"
          echo "    portbuddy ${PANEL_PORT}"
        fi
      else
        warn "Skipped \u2014 run 'portbuddy init <token>' then 'portbuddy ${PANEL_PORT}' manually later."
      fi
    fi
    ;;
  5)
    step "Deploying to Railway"
    warn "Railway hosts the panel itself on their infrastructure \u2014 it doesn't tunnel your VPS."
    echo -e "${C_DIM}  This only makes sense if you want Railway (not this VPS) running HVM Manager.${C_RESET}"
    if ! command -v railway >/dev/null 2>&1; then
      warn "Railway CLI not found, installing..."
      if command -v npm >/dev/null 2>&1; then
        npm install -g @railway/cli --silent 2>/dev/null && ok "Railway CLI installed" \
          || err "Install failed. Install manually: npm install -g @railway/cli"
      fi
    fi
    if command -v railway >/dev/null 2>&1; then
      echo -e "${C_DIM}  Log in, then deploy from this project folder:${C_RESET}"
      echo "    railway login"
      echo "    railway init"
      echo "    railway up"
      echo -e "${C_DIM}  Railway will assign a public *.up.railway.app URL after deploy.${C_RESET}"
      read -rp "$(echo -e "${C_DIM}Run 'railway login' now?${C_RESET} [y/N]: ")" DO_RAILWAY_LOGIN
      if [[ "$DO_RAILWAY_LOGIN" =~ ^[Yy]$ ]]; then
        railway login || warn "Railway login didn't complete \u2014 run 'railway login' manually when ready."
      fi
    fi
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
if [ -n "${TUNNEL_URL:-}" ]; then
  echo -e "${C_GREEN}\u2551${C_RESET}  Public:   ${TUNNEL_URL}"
fi
echo -e "${C_GREEN}\u2551${C_RESET}  Local:    http://localhost:${PANEL_PORT}"
echo -e "${C_GREEN}\u2551${C_RESET}  Login:    ${ADMIN_USER}"
echo -e "${C_GREEN}\u2551${C_RESET}  Password: (the one you entered)"
echo -e "${C_GREEN}\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d${C_RESET}"
echo ""
echo -e "${C_DIM}To stop the panel:  kill \$(cat .panel.pid)${C_RESET}"
echo -e "${C_DIM}To view logs:       tail -f logs/panel.log${C_RESET}"
echo -e "${C_DIM}HVM Customize \u2014 crafted by @blaze_gazzer${C_RESET}"
echo ""
