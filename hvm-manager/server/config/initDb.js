// ── First-run bootstrap ──────────────────────────────────────────
// Creates the initial admin account from .env if no users exist yet.
// Safe to run every start \u2014 it no-ops once a user table is populated.

require('dotenv').config();
const bcrypt = require('bcryptjs');
const db = require('./db');

function ensureAdmin() {
  const count = db.prepare('SELECT COUNT(*) AS c FROM users').get().c;
  if (count > 0) return;

  const username = process.env.ADMIN_USERNAME || 'admin';
  const password = process.env.ADMIN_PASSWORD || 'admin';
  const hash = bcrypt.hashSync(password, 10);

  db.prepare(
    'INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)'
  ).run(username, hash, 'admin');

  console.log(`[HVM] Initial admin account created: ${username}`);
  console.log('[HVM] Change this password after your first login.');
}

ensureAdmin();
