// ── VPS routes (user-facing) ─────────────────────────────────────
// Regular users can only ever see/act on VPS rows where owner_id = them.
// Creation, deletion, and reassignment are admin-only (see routes/admin.js).

const express = require('express');
const db = require('../config/db');
const { requireAuth } = require('../middleware/auth');
const dockerSvc = require('../services/docker');

const router = express.Router();
router.use(requireAuth);

// List VPS assigned to the logged-in user (admins see all via /admin/vps instead)
router.get('/', (req, res) => {
  const rows = db.prepare('SELECT * FROM vps WHERE owner_id = ?').all(req.user.id);
  res.json(rows);
});

function ownedVpsOrNull(req) {
  return db.prepare('SELECT * FROM vps WHERE id = ? AND owner_id = ?')
    .get(req.params.id, req.user.id);
}

router.get('/:id', (req, res) => {
  const vps = ownedVpsOrNull(req);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });
  res.json(vps);
});

router.get('/:id/stats', async (req, res) => {
  const vps = ownedVpsOrNull(req);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });
  if (!vps.container_id) return res.json({ status: 'unprovisioned' });
  try {
    const stats = await dockerSvc.getStats(vps.container_id);
    res.json(stats);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/:id/start', async (req, res) => {
  const vps = ownedVpsOrNull(req);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });
  await dockerSvc.startVps(vps.container_id);
  db.prepare('UPDATE vps SET status = ? WHERE id = ?').run('running', vps.id);
  res.json({ ok: true });
});

router.post('/:id/stop', async (req, res) => {
  const vps = ownedVpsOrNull(req);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });
  await dockerSvc.stopVps(vps.container_id);
  db.prepare('UPDATE vps SET status = ? WHERE id = ?').run('stopped', vps.id);
  res.json({ ok: true });
});

router.post('/:id/restart', async (req, res) => {
  const vps = ownedVpsOrNull(req);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });
  await dockerSvc.restartVps(vps.container_id);
  res.json({ ok: true });
});

// Users may rename their own VPS (display name only \u2014 not container internals)
router.patch('/:id/rename', (req, res) => {
  const vps = ownedVpsOrNull(req);
  if (!vps) return res.status(404).json({ error: 'VPS not found' });
  const { name } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'Name required' });
  db.prepare('UPDATE vps SET name = ? WHERE id = ?').run(name.trim(), vps.id);
  res.json({ ok: true });
});

module.exports = router;
