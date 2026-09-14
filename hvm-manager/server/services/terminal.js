// ── Live terminal bridge (SSHX-style) ────────────────────────────
// Spawns `docker exec -it <container> sh` as a real pseudo-terminal
// via node-pty, and pipes it directly to a WebSocket. This is what
// gives the xterm.js frontend a genuine live shell into the container,
// not a simulated one.

const pty = require('node-pty');

// One PTY session per WebSocket connection. Sessions are not shared
// between tabs on purpose \u2014 open two tabs, get two independent shells,
// same as opening two SSH sessions.
function attachTerminal(ws, containerName) {
  const shell = pty.spawn('docker', ['exec', '-it', containerName, '/bin/sh'], {
    name: 'xterm-256color',
    cols: 80,
    rows: 24,
    cwd: process.env.HOME,
    env: process.env
  });

  shell.onData((data) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type: 'output', data }));
    }
  });

  shell.onExit(({ exitCode }) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify({ type: 'exit', code: exitCode }));
      ws.close();
    }
  });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (_) {
      return;
    }
    if (msg.type === 'input') {
      shell.write(msg.data);
    } else if (msg.type === 'resize') {
      shell.resize(msg.cols || 80, msg.rows || 24);
    }
  });

  ws.on('close', () => {
    shell.kill();
  });
}

module.exports = { attachTerminal };
