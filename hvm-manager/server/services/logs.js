// ── Live logs bridge ──────────────────────────────────────────────
// Streams `docker logs -f` output straight to the WebSocket so the
// dashboard's log panel updates in real time, same idea as the terminal.

const { docker } = require('./docker');

async function attachLogs(ws, containerId) {
  const container = docker.getContainer(containerId);

  let stream;
  try {
    stream = await container.logs({
      follow: true,
      stdout: true,
      stderr: true,
      tail: 200
    });
  } catch (err) {
    ws.send(JSON.stringify({ type: 'error', message: 'Could not attach to logs: ' + err.message }));
    ws.close();
    return;
  }

  stream.on('data', (chunk) => {
    if (ws.readyState !== ws.OPEN) return;
    // Docker multiplexes stdout/stderr with an 8-byte header per frame;
    // strip it so raw text reaches the browser cleanly.
    const text = stripDockerFrameHeader(chunk);
    ws.send(JSON.stringify({ type: 'log', data: text }));
  });

  ws.on('close', () => {
    stream.destroy();
  });
}

function stripDockerFrameHeader(buf) {
  let out = '';
  let i = 0;
  while (i < buf.length) {
    if (buf.length - i >= 8) {
      const frameSize = buf.readUInt32BE(i + 4);
      const start = i + 8;
      const end = start + frameSize;
      out += buf.slice(start, end).toString('utf8');
      i = end;
    } else {
      out += buf.slice(i).toString('utf8');
      break;
    }
  }
  return out;
}

module.exports = { attachLogs };
