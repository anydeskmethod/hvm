// ── Auth middleware ───────────────────────────────────────────────
const jwt = require('jsonwebtoken');

const SECRET = process.env.JWT_SECRET || 'insecure_default_change_me';

function requireAuth(req, res, next) {
  const token = req.cookies?.hvm_token || (req.headers.authorization || '').replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Not authenticated' });

  try {
    const payload = jwt.verify(token, SECRET);
    req.user = payload; // { id, username, role }
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired session' });
  }
}

// Only allows through if req.user.role === 'admin'.
// This is the single choke point enforcing "only admin can assign VPS".
function requireAdmin(req, res, next) {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin privileges required' });
  }
  next();
}

function signToken(user) {
  return jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    SECRET,
    { expiresIn: '7d' }
  );
}

module.exports = { requireAuth, requireAdmin, signToken, SECRET };
