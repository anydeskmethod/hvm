# HVM Manager

**HVM Customize** — a self-hosted VPS/container management panel.
Owner & credit: **@blaze_gazzer**

A dark, Obsidian-inspired dashboard for provisioning real Docker containers as
"VPS" instances, assigning them to users, and giving each user a live
in-browser terminal (SSHX-style) and live log stream straight into their
container — all running on your own VPS.

---

## What this actually is

- **Real containers.** Every "VPS" created from the Admin Panel is a real
  Docker container on the host you run this on, with RAM/CPU limits applied
  at the Docker level.
- **Real terminal.** The in-browser terminal opens a genuine `docker exec`
  session via `node-pty`, piped over a WebSocket to `xterm.js`. Typing in the
  browser is typing in the container.
- **Real logs.** The logs panel streams `docker logs -f` live.
- **Role-gated.** Only admins can create, assign, rename, or delete VPS
  instances and view every VPS on the panel. Regular users only ever see and
  control the VPS assigned to them.

---

## Requirements on your VPS

- Linux with `bash`, `curl`, and `sudo` access (for the auto-installer)
- A free port (default `5000`)
- Node.js and Docker will be auto-installed if missing

---

## Quickest path: automatic installer

If you just cloned or uploaded this project to your VPS, you can skip
everything below and run:

```bash
cd hvm-manager
chmod +x install.sh
./install.sh
```

It will walk you through:

1. Checking/installing **Node.js** and **Docker** if they're missing
2. Asking for your **panel name**, **admin username**, and **admin password**
3. Asking which port to run on (default `5000`)
4. Asking how to expose it to the internet:
   - `1` Cloudflare Tunnel (auto-installs `cloudflared`, gives you an instant
     public `*.trycloudflare.com` URL, no account needed)
   - `2` Ngrok (auto-installs `ngrok`, asks for your free authtoken)
   - `3` GitHub Codespaces port forwarding (prints the manual steps, since
     this only applies inside a Codespace)
   - `4` Skip \u2014 local network only
5. Writing `.env`, installing dependencies, creating the admin account, and
   starting the panel in the background

At the end you'll see your login URL and credentials printed directly in the
terminal. That's the whole setup.

To stop it later:
```bash
./stop.sh
```

Logs while it runs:
```bash
tail -f logs/panel.log
```

---

## Manual setup (if you'd rather do it by hand)

## 1. Get the code onto your VPS

### Option A — Host it on GitHub, then clone it

1. Create a new empty repository on GitHub (e.g. `hvm-manager`).
2. From this project folder:
   ```bash
   git init
   git add .
   git commit -m "Initial commit — HVM Customize"
   git branch -M main
   git remote add origin https://github.com/<your-username>/hvm-manager.git
   git push -u origin main
   ```
3. On your VPS:
   ```bash
   git clone https://github.com/<your-username>/hvm-manager.git
   cd hvm-manager
   ```

### Option B — Copy the folder directly to your VPS (scp/sftp)

Just upload this whole folder to your VPS and `cd` into it.

---

## 2. Install and configure

```bash
npm install
cp .env.example .env
nano .env        # set JWT_SECRET, ADMIN_USERNAME, ADMIN_PASSWORD
```

At minimum, change:
- `JWT_SECRET` — any long random string
- `ADMIN_PASSWORD` — your real admin password (the account is created
  automatically on first run using `ADMIN_USERNAME` / `ADMIN_PASSWORD`)

---

## 3. Run it

```bash
npm start
```

You should see:

```
[HVM] Initial admin account created: admin
[HVM] Panel running on http://localhost:5000
```

Visit `http://<your-vps-ip>:5000` and log in with the admin credentials from
your `.env`. **Change the password immediately** by creating a new admin user
from Users → Add user, or updating the DB directly.

To keep it running after you close your terminal, use a process manager:

```bash
npm install -g pm2
pm2 start server/index.js --name hvm-manager
pm2 save
pm2 startup
```

---

## 4. Exposing the panel to the internet

You don't need to open ports manually if you use a tunnel. Pick whichever you
already use:

### Cloudflare Tunnel
```bash
cloudflared tunnel --url http://localhost:5000
```
Or set up a named tunnel with a real domain via the Cloudflare Zero Trust
dashboard, pointing to `http://localhost:5000`.

### Ngrok
```bash
ngrok http 5000
```
Grab the `https://xxxx.ngrok-free.app` URL it gives you.

### GitHub Codespaces port forwarding
If you're running this inside a Codespace for testing, open the **Ports**
tab, find port `5000`, set visibility to **Public**, and use the generated
URL.

> Whichever method you use, make sure the URL is `https://` before you rely
> on cookies/auth in production — some browsers restrict cookies on plain
> `http://` for non-localhost origins.

---

## 5. Using the panel

- **Admin Panel** → create a VPS (name, Docker image, RAM, CPU, optionally
  assign to a user immediately).
- **Users** → add accounts, set role (`user` / `admin`).
- **My VPS / Dashboard** → regular users see only what's assigned to them:
  start/stop/restart, live terminal, live logs, rename.
- **Settings** → change the panel name, upload your logo, set the owner
  name/credit line, add your Discord/Telegram/any other links, pick an
  accent color, set defaults for new VPS.
- **Charts** → resource allocation and running/stopped breakdown.
- **Database** → full audit log of every admin action.

---

## Notes on limits

- Disk quota per container (`disk_gb`) is stored but not enforced by
  default — enforcing real disk quotas requires a storage driver that
  supports it (e.g. `overlay2` on XFS with `pquota`). If you need this,
  configure Docker's storage driver accordingly and extend
  `server/services/docker.js`.
- This panel controls containers **on the same host it runs on**. Managing
  containers across multiple physical nodes would need an additional layer
  (e.g. Docker Swarm, or an agent process per node) — not included here.

---

**HVM Customize** — crafted by **@blaze_gazzer**
