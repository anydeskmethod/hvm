// ── HVM Customize \u2014 main server entry point ───────────────────────
require('dotenv').config();
require('./config/initDb'); // creates first admin on first boot

const path = require('path');
const http = require('http');
const url = require('url');
const express = require('express');
const cookieParser = require('cookie-parser');
const jwt = require('jsonwebtoken');
const { WebSocketServer } = require('ws');

const db = require('./config/db');
const { SECRET } = require('./middleware/auth');
const authRoutes = require('./routes/auth');
const vpsRoutes = require('./routes/vps');
const adminRoutes = require('./routes/admin');
const settingsRoutes = require('./routes/settings');
const { attachTerminal } = require('./services/terminal');
const { attachLogs } = require('./services/logs');

const app = express();
const server = http.createServer(app);

app.use(express.json());
app.use(cookieParser());
app.use(express.static(path.join(__dirname, '..', 'public')));

app.use('/api/auth', authRoutes);
app.use('/api/vps', vpsRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/settings', settingsRoutes);

app.get('/health', (req, res) => res.json({ ok: true }));

// ── WebSocket layer: /ws/terminal/:vpsId and /ws/logs/:vpsId ──────
// Auth is checked from the same JWT cookie the REST API uses, and
// ownership (or admin) is re-verified per connection \u2014 a user can
// never open a socket into a VPS that isn't theirs.
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const { pathname } = url.parse(req.url);
  const cookies = parseCookies(req.headers.cookie || '');
  const token = cookies.hvm_token;

  let user;
  try {
    user = jwt.verify(token, SECRET);
  } catch (_) {
    socket.destroy();
    return;
  }

  const termMatch = pathname.match(/^\/ws\/terminal\/(\d+)$/);
  const logMatch = pathname.match(/^\/ws\/logs\/(\d+)$/);

  if (termMatch) {
    const vps = getVpsForUser(termMatch[1], user);
    if (!vps || !vps.container_name) return socket.destroy();
    wss.handleUpgrade(req, socket, head, (ws) => attachTerminal(ws, vps.container_name));
  } else if (logMatch) {
    const vps = getVpsForUser(logMatch[1], user);
    if (!vps || !vps.container_id) return socket.destroy();
    wss.handleUpgrade(req, socket, head, (ws) => attachLogs(ws, vps.container_id));
  } else {
    socket.destroy();
  }
});

function getVpsForUser(vpsId, user) {
  if (user.role === 'admin') {
    return db.prepare('SELECT * FROM vps WHERE id = ?').get(vpsId);
  }
  return db.prepare('SELECT * FROM vps WHERE id = ? AND owner_id = ?').get(vpsId, user.id);
}

function parseCookies(header) {
  const out = {};
  header.split(';').forEach((pair) => {
    const idx = pair.indexOf('=');
    if (idx === -1) return;
    out[pair.slice(0, idx).trim()] = decodeURIComponent(pair.slice(idx + 1).trim());
  });
  return out;
}

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`[HVM] Panel running on http://localhost:${PORT}`);
});
