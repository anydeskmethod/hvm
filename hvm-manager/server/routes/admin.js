// ── Admin routes ──────────────────────────────────────────────────
// Everything that creates, assigns, or destroys infrastructure lives
// here, gated behind requireAdmin. This is the enforcement point for
// "only admin can assign VPS and they can view it inside the HVM".

const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../config/db');
const { requireAuth, requireAdmin } = require('../middleware/auth');
const dockerSvc = require('../services/docker');

const router = express.Router();
router.use(requireAuth, requireAdmin);

function logAction(actorId, action, detail) {
  db.prepare('INSERT INTO audit_log (actor_id, action, detail) VALUES (?, ?, ?)')
    .run(actorId, action, detail || '');
}

// ── VPS: admin sees every VPS on the panel, not just their own ────
router.get('/vps', (req, res) => {
  const rows = db.prepare(`
    SELECT vps.*, users.username AS owner_username
    FROM vps LEFT JOIN users ON vps.owner_id = users.id
    ORDER BY vps.created_at DESC
  `).all();
  res.json(rows);
});

// Create + provision a real container, optionally assigning it to a user immediately
router.post('/vps', async (req, res) => {
  const { name, image, ramMb, cpuCores, diskGb, ownerId } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name required' });

  const containerName = 'hvm_' + name.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '-') + '_' + Date.now();

  try {
    const containerId = await dockerSvc.createVps({
      name: containerName,
      image: image || 'ubuntu:22.04',
      ramMb: ramMb || 1024,
      cpuCores: cpuCores || 1,
      diskGb: diskGb || 10
    });

    const info = db.prepare(`
      INSERT INTO vps (name, container_id, container_name, image, ram_mb, cpu_cores, disk_gb, owner_id, status, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'running', ?)
    `).run(name.trim(), containerId, containerName, image || 'ubuntu:22.04', ramMb || 1024, cpuCores || 1, diskGb || 10, ownerId || null, req.user.id);

    logAction(req.user.id, 'vps_create', `Created ${name} (${containerName})`);
    res.json({ id: info.lastInsertRowid, containerId });
  } catch (err) {
    res.status(500).json({ error: 'Docker error: ' + err.message });
  }
});

// Assign (or reassign) an existing VPS to a user. Admin-only by router.use above.
router.patch('/vps/:id/assign', (req, res) => {
  const { ownerId } = req.body;
  const vps = db.prepare('SELECT * FROM vps WHERE id = ?').get(req.params.id);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });

  db.prepare('UPDATE vps SET owner_id = ? WHERE id = ?').run(ownerId || null, vps.id);
  logAction(req.user.id, 'vps_assign', `VPS ${vps.name} -> user ${ownerId}`);
  res.json({ ok: true });
});

// Rename a VPS (panel display name) as admin
router.patch('/vps/:id/rename', (req, res) => {
  const { name } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name required' });
  db.prepare('UPDATE vps SET name = ? WHERE id = ?').run(name.trim(), req.params.id);
  res.json({ ok: true });
});

router.delete('/vps/:id', async (req, res) => {
  const vps = db.prepare('SELECT * FROM vps WHERE id = ?').get(req.params.id);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });

  try {
    if (vps.container_id) await dockerSvc.deleteVps(vps.container_id);
  } catch (err) {
    // continue \u2014 still remove the DB row even if the container was already gone
  }
  db.prepare('DELETE FROM vps WHERE id = ?').run(vps.id);
  logAction(req.user.id, 'vps_delete', `Deleted ${vps.name}`);
  res.json({ ok: true });
});

// ── Users ───────────────────────────────────────────────────────
router.get('/users', (req, res) => {
  const rows = db.prepare('SELECT id, username, role, created_at FROM users ORDER BY created_at DESC').all();
  res.json(rows);
});

router.post('/users', (req, res) => {
  const { username, password, role } = req.body;
  if (!username || !password) return res.status(400).json({ error: 'Username and password required' });

  const hash = bcrypt.hashSync(password, 10);
  try {
    const info = db.prepare('INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)')
      .run(username, hash, role === 'admin' ? 'admin' : 'user');
    logAction(req.user.id, 'user_create', username);
    res.json({ id: info.lastInsertRowid });
  } catch (err) {
    res.status(400).json({ error: 'Username already exists' });
  }
});

router.delete('/users/:id', (req, res) => {
  if (Number(req.params.id) === req.user.id) {
    return res.status(400).json({ error: "Can't delete your own account" });
  }
  db.prepare('UPDATE vps SET owner_id = NULL WHERE owner_id = ?').run(req.params.id);
  db.prepare('DELETE FROM users WHERE id = ?').run(req.params.id);
  logAction(req.user.id, 'user_delete', String(req.params.id));
  res.json({ ok: true });
});

// ── Stats overview for admin dashboard/charts ─────────────────────
router.get('/overview', (req, res) => {
  const totalVps = db.prepare('SELECT COUNT(*) c FROM vps').get().c;
  const totalUsers = db.prepare('SELECT COUNT(*) c FROM users').get().c;
  const running = db.prepare("SELECT COUNT(*) c FROM vps WHERE status = 'running'").get().c;
  const unassigned = db.prepare('SELECT COUNT(*) c FROM vps WHERE owner_id IS NULL').get().c;
  res.json({ totalVps, totalUsers, running, unassigned });
});

router.get('/logs', (req, res) => {
  const rows = db.prepare(`
    SELECT audit_log.*, users.username AS actor_username
    FROM audit_log LEFT JOIN users ON audit_log.actor_id = users.id
    ORDER BY audit_log.created_at DESC LIMIT 200
  `).all();
  res.json(rows);
});

module.exports = router;
