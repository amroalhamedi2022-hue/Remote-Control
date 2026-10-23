// EXPERIMENTAL, view-only H.264/MPEG-TS desktop viewer. No remote input.
// FFplay is spawned as a fixed executable, never a shell; video is decrypted
// by the caller and pushed through stdin. NOT reviewed for hostile media.
import { spawn } from 'node:child_process';

const MAX_PENDING = 512 * 1024;

export class H264LiveViewer {
  constructor({ executable = 'ffplay', args, spawnProcess = spawn } = {}) {
    this.executable = executable;
    this.args = args ?? [
      '-hide_banner', '-loglevel', 'error', '-nostats', '-fflags', 'nobuffer',
      '-flags', 'low_delay', '-framedrop', '-probesize', '32768',
      '-analyzeduration', '200000', '-f', 'mpegts', '-i', 'pipe:0',
      '-autoexit', '-window_title', 'Liquid Fusion · H.264 view-only lab',
    ];
    this.spawnProcess = spawnProcess;
    this.child = null;
    this.ended = null;
    this.error = null;
    this.closed = false;
    this.bytes = 0;
  }
  start() {
    if (this.child || this.closed) throw Error('Viewer already started/closed');
    const child = this.spawnProcess(this.executable, this.args, {
      windowsHide: false, shell: false, stdio: ['pipe', 'ignore', 'pipe'],
    });
    this.child = child;
    child.stderr.on('data', () => {}); // prevent unbounded buffering
    // No unhandled stream error if player exits while video is being sent.
    child.stdin.on('error', error => { this.error = error; });
    this.ended = new Promise(resolve => {
      child.once('error', error => { this.error = error; resolve({ error }); });
      child.once('exit', (code, signal) => resolve({ code, signal }));
    });
  }
  write(part) {
    if (!this.child || this.closed) throw Error('Viewer not running');
    if (!Buffer.isBuffer(part) || !part.length || part.length > 2400) throw Error('Invalid video part');
    if (this.error || this.child.exitCode !== null || this.child.stdin.destroyed)
      throw Error(`Local video player stopped${this.error ? `: ${this.error.message}` : ''}`);
    if (this.child.stdin.writableLength + part.length > MAX_PENDING)
      throw Error('Local video decoder too slow; refusing unbounded buffering');
    this.child.stdin.write(part);
    this.bytes += part.length;
  }
  async finish({ maxWaitMs = 2000 } = {}) {
    if (!this.child) return null;
    this.closed = true;
    if (!this.child.stdin.destroyed) this.child.stdin.end();
    const result = await Promise.race([this.ended, new Promise(resolve => setTimeout(() => resolve({ timeout: true }), maxWaitMs))]);
    if (result.error) throw new Error(`Local video player failed: ${result.error.message}`);
    if (result.code !== undefined && result.code !== 0) throw new Error(`Local video player exited ${result.code}`);
    return result;
  }
  async stop() {
    if (!this.child) return;
    this.closed = true;
    if (!this.child.stdin.destroyed) this.child.stdin.destroy();
    if (this.child.exitCode === null && !this.child.killed) this.child.kill();
    return Promise.race([this.ended, new Promise(resolve => setTimeout(() => resolve({ timeout: true }), 1500))]);
  }
}
