// ── Settings routes ───────────────────────────────────────────────
// Panel branding: name, logo, owner credit, Discord/Telegram/extra links.
// Reading settings is open to any logged-in user (the UI needs them to
// render the sidebar/branding); writing is admin-only.

const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../config/db');
const { requireAuth, requireAdmin } = require('../middleware/auth');

const router = express.Router();

const uploadDir = path.join(__dirname, '..', '..', 'public', 'uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: uploadDir,
    filename: (req, file, cb) => {
      const ext = path.extname(file.originalname);
      cb(null, `${file.fieldname}_${Date.now()}${ext}`);
    }
  }),
  limits: { fileSize: 3 * 1024 * 1024 } // 3MB
});

router.get('/', requireAuth, (req, res) => {
  const rows = db.prepare('SELECT key, value FROM settings').all();
  const out = {};
  for (const r of rows) out[r.key] = r.value;
  try { out.extra_links = JSON.parse(out.extra_links || '[]'); } catch (_) { out.extra_links = []; }
  res.json(out);
});

router.put('/', requireAuth, requireAdmin, (req, res) => {
  const allowedKeys = [
    'panel_name', 'owner_name', 'credit_line', 'discord_link', 'telegram_link',
    'extra_links', 'logo_url', 'favicon_url', 'accent_color',
    'default_ram_mb', 'default_cpu_cores', 'max_vps_per_user'
  ];
  const upsert = db.prepare('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value');

  for (const key of allowedKeys) {
    if (req.body[key] !== undefined) {
      const val = key === 'extra_links' ? JSON.stringify(req.body[key]) : String(req.body[key]);
      upsert.run(key, val);
    }
  }
  res.json({ ok: true });
});

router.post('/logo', requireAuth, requireAdmin, upload.single('logo'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  const url = '/uploads/' + req.file.filename;
  db.prepare('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
    .run('logo_url', url);
  res.json({ url });
});

module.exports = router;
