// ── Docker service layer ─────────────────────────────────────────
// Wraps dockerode so the rest of the app never touches the Docker API
// directly. This is what makes VPS creation "real" \u2014 it provisions
// actual containers on the host the panel is running on.

const Docker = require('dockerode');

const docker = new Docker({
  socketPath: process.env.DOCKER_SOCKET || '/var/run/docker.sock'
});

// Create + start a container as a "VPS" with RAM/CPU limits.
async function createVps({ name, image, ramMb, cpuCores, diskGb }) {
  const container = await docker.createContainer({
    Image: image || 'ubuntu:22.04',
    name,
    Tty: true,
    OpenStdin: true,
    Cmd: ['/bin/sh', '-c', 'while true; do sleep 1000; done'],
    HostConfig: {
      Memory: Math.max(64, ramMb) * 1024 * 1024,      // bytes
      NanoCpus: Math.max(0.1, cpuCores) * 1e9,          // CPU cores -> NanoCPUs
      // StorageOpt (disk quota) only works with certain storage drivers (e.g. overlay2 + xfs).
      // Left out by default to avoid failing on hosts that don't support it.
      RestartPolicy: { Name: 'unless-stopped' }
    }
  });

  await container.start();
  return container.id;
}

async function startVps(containerId) {
  const c = docker.getContainer(containerId);
  await c.start().catch(ignoreAlreadyStarted);
}

async function stopVps(containerId) {
  const c = docker.getContainer(containerId);
  await c.stop().catch(ignoreAlreadyStopped);
}

async function restartVps(containerId) {
  const c = docker.getContainer(containerId);
  await c.restart();
}

async function deleteVps(containerId) {
  const c = docker.getContainer(containerId);
  await c.stop().catch(() => {});
  await c.remove({ force: true });
}

async function getStats(containerId) {
  const c = docker.getContainer(containerId);
  const info = await c.inspect();
  let stats = null;
  try {
    stats = await c.stats({ stream: false });
  } catch (_) {}

  let cpuPercent = 0;
  let memUsedMb = 0;
  let memLimitMb = 0;

  if (stats) {
    const cpuDelta = stats.cpu_stats.cpu_usage.total_usage - stats.precpu_stats.cpu_usage.total_usage;
    const sysDelta = stats.cpu_stats.system_cpu_usage - stats.precpu_stats.system_cpu_usage;
    const cpuCount = stats.cpu_stats.online_cpus || 1;
    if (sysDelta > 0 && cpuDelta > 0) {
      cpuPercent = (cpuDelta / sysDelta) * cpuCount * 100;
    }
    memUsedMb = (stats.memory_stats.usage || 0) / 1024 / 1024;
    memLimitMb = (stats.memory_stats.limit || 0) / 1024 / 1024;
  }

  return {
    status: info.State.Status,
    running: info.State.Running,
    startedAt: info.State.StartedAt,
    cpuPercent: Math.round(cpuPercent * 10) / 10,
    memUsedMb: Math.round(memUsedMb),
    memLimitMb: Math.round(memLimitMb)
  };
}

function ignoreAlreadyStarted(err) {
  if (err.statusCode !== 304) throw err;
}
function ignoreAlreadyStopped(err) {
  if (err.statusCode !== 304) throw err;
}

module.exports = {
  docker,
  createVps,
  startVps,
  stopVps,
  restartVps,
  deleteVps,
  getStats
};
