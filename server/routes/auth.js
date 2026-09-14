const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../config/db');
const { signToken, requireAuth } = require('../middleware/auth');

const router = express.Router();

router.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const token = signToken(user);
  res.cookie('hvm_token', token, {
    httpOnly: true,
    sameSite: 'lax',
    maxAge: 7 * 24 * 60 * 60 * 1000
  });
  res.json({ id: user.id, username: user.username, role: user.role });
});

router.post('/logout', (req, res) => {
  res.clearCookie('hvm_token');
  res.json({ ok: true });
});

router.get('/me', requireAuth, (req, res) => {
  res.json(req.user);
});

module.exports = router;
