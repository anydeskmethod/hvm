// ── Database layer ───────────────────────────────────────────────
// Uses better-sqlite3: a single file DB, zero external services needed.
// This keeps the panel deployable on any VPS with no MySQL/Postgres setup.

const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');

const DB_PATH = process.env.DB_PATH || './data/hvm.db';
const dir = path.dirname(DB_PATH);
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',      -- 'admin' | 'user'
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,                     -- editable display name
  container_id TEXT,                      -- docker container id (null until provisioned)
  container_name TEXT UNIQUE,             -- docker container name (internal)
  image TEXT NOT NULL DEFAULT 'ubuntu:22.04',
  ram_mb INTEGER NOT NULL DEFAULT 1024,
  cpu_cores REAL NOT NULL DEFAULT 1,
  disk_gb INTEGER NOT NULL DEFAULT 10,
  owner_id INTEGER,                       -- assigned user (admin-controlled)
  status TEXT NOT NULL DEFAULT 'stopped', -- running | stopped | error
  created_by INTEGER,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id INTEGER,
  action TEXT NOT NULL,
  detail TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
`);

// Seed default settings if not present
const defaultSettings = {
  panel_name: process.env.PANEL_NAME || 'HVM Manager',
  owner_name: process.env.OWNER_NAME || 'blaze_gazzer',
  credit_line: 'HVM Customize \u2014 crafted by @blaze_gazzer',
  discord_link: process.env.DISCORD_LINK || '',
  telegram_link: process.env.TELEGRAM_LINK || '',
  extra_links: '[]',              // JSON array of {label, url} for "and more"
  logo_url: '/img/logo.svg',
  favicon_url: '/img/favicon.ico',
  accent_color: '#7c3aed',        // obsidian-purple default
  default_ram_mb: process.env.DEFAULT_RAM_MB || '1024',
  default_cpu_cores: process.env.DEFAULT_CPU_CORES || '1',
  max_vps_per_user: '5'
};

const insertSetting = db.prepare(
  'INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)'
);
for (const [k, v] of Object.entries(defaultSettings)) {
  insertSetting.run(k, String(v));
}

module.exports = db;
