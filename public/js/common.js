// ── Shared helpers used by every page ────────────────────────────

const api = {
  async get(url) { return handle(await fetch(url)); },
  async post(url, body) { return handle(await fetch(url, opts('POST', body))); },
  async put(url, body) { return handle(await fetch(url, opts('PUT', body))); },
  async patch(url, body) { return handle(await fetch(url, opts('PATCH', body))); },
  async del(url) { return handle(await fetch(url, opts('DELETE'))); }
};

function opts(method, body) {
  return {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined
  };
}

async function handle(res) {
  if (res.status === 401) {
    window.location.href = '/login.html';
    throw new Error('Not authenticated');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

const SIDEBAR_ITEMS = [
  { section: 'Main' },
  { label: 'Dashboard', href: '/dashboard.html', sym: '#', key: 'dashboard' },
  { label: 'My VPS', href: '/vps.html', sym: '[]', key: 'vps' },
  { label: 'Charts', href: '/charts.html', sym: '~', key: 'charts' },
  { section: 'Admin', adminOnly: true },
  { label: 'Admin Panel', href: '/admin.html', sym: '@', key: 'admin', adminOnly: true },
  { label: 'Users', href: '/users.html', sym: '&', key: 'users', adminOnly: true },
  { label: 'Database', href: '/database.html', sym: '=', key: 'database', adminOnly: true },
  { section: 'System' },
  { label: 'Settings', href: '/settings.html', sym: '*', key: 'settings' }
];

async function renderShell(activeKey) {
  let me, settings;
  try {
    [me, settings] = await Promise.all([api.get('/api/auth/me'), api.get('/api/settings')]);
  } catch (_) {
    return;
  }

  document.title = settings.panel_name || 'HVM Manager';
  const favicon = document.querySelector('link[rel="icon"]');
  if (favicon && settings.favicon_url) favicon.href = settings.favicon_url;

  document.documentElement.style.setProperty('--accent', settings.accent_color || '#7c3aed');
  document.documentElement.style.setProperty('--accent-soft', hexToSoft(settings.accent_color || '#7c3aed'));

  const shell = document.getElementById('app-shell');
  const collapsed = localStorage.getItem('hvm_sidebar_collapsed') === '1';

  let linksHtml = '';
  if (settings.discord_link) linksHtml += `<a href="${escapeAttr(settings.discord_link)}" target="_blank">Discord</a>`;
  if (settings.telegram_link) linksHtml += `<a href="${escapeAttr(settings.telegram_link)}" target="_blank">Telegram</a>`;
  (settings.extra_links || []).forEach(l => {
    linksHtml += `<a href="${escapeAttr(l.url)}" target="_blank">${escapeHtml(l.label)}</a>`;
  });

  const navHtml = SIDEBAR_ITEMS.map(item => {
    if (item.adminOnly && me.role !== 'admin') return '';
    if (item.section) return `<div class="side-section-title">${item.section}</div>`;
    const active = item.key === activeKey ? 'active' : '';
    return `<a class="side-link ${active}" href="${item.href}">
      <span class="sym">${item.sym}</span><span class="side-label">${item.label}</span>
    </a>`;
  }).join('');

  shell.innerHTML = `
    <div class="sidebar ${collapsed ? 'collapsed' : ''}" id="sidebar">
      <div class="brand">
        <img src="${settings.logo_url || '/img/logo.svg'}" onerror="this.style.display='none'" />
        <span class="brand-name">${escapeHtml(settings.panel_name || 'HVM Manager')}</span>
      </div>
      <button class="collapse-btn" id="collapseBtn">&lt;&gt;</button>
      <nav>${navHtml}</nav>
      <div class="sidebar-footer">
        <div class="owner-credit">${escapeHtml(settings.credit_line || 'HVM Customize')}<br/>
          <span style="opacity:0.7">Signed in as ${escapeHtml(me.username)} ${me.role === 'admin' ? '<span class="badge admin">admin</span>' : ''}</span>
        </div>
        <div class="social-links">${linksHtml}</div>
        <div style="padding:10px 8px 0 8px;">
          <button class="btn-sm" style="width:100%" onclick="logout()">Log out</button>
        </div>
      </div>
    </div>
    <div class="main" id="main-content"></div>
  `;

  document.getElementById('collapseBtn').onclick = () => {
    const sb = document.getElementById('sidebar');
    sb.classList.toggle('collapsed');
    localStorage.setItem('hvm_sidebar_collapsed', sb.classList.contains('collapsed') ? '1' : '0');
  };

  return { me, settings };
}

async function logout() {
  await api.post('/api/auth/logout');
  window.location.href = '/login.html';
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function escapeAttr(s) { return escapeHtml(s); }

function hexToSoft(hex) {
  const h = hex.replace('#', '');
  const r = parseInt(h.substring(0, 2), 16);
  const g = parseInt(h.substring(2, 4), 16);
  const b = parseInt(h.substring(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, 0.15)`;
}
