// v0.6 EXPERIMENT ONLY: MPEG-TS containing H.264, transferred in authenticated
// AES-GCM Node lab messages. Not a real-time player or a reviewed security stack.
// Receiver may save to an explicitly requested private .ts file for FFmpeg playback.
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createChildLifecycle } from '../stream_lab/child_lifecycle.mjs';

export const MAX_TS_BYTES = 10 * 1024 * 1024;
export const TS_CHUNK_BYTES = 2400;
const MAX_QUEUED_SOCKET_BYTES = 768 * 1024;
const SHA256_RE = /^[0-9a-f]{64}$/;

function checkProfile({testPattern = false, seconds = 3, fps = 12, width = 640,
  bitrateKbps = 800, encoder = 'libx264'} = {}) {
  if (typeof testPattern !== 'boolean' || !Number.isInteger(seconds) || seconds < 1 || seconds > 10 ||
    !Number.isInteger(fps) || fps < 1 || fps > 30 ||
    !Number.isInteger(width) || width < 320 || width > 1280 || width % 2 !== 0 ||
    !Number.isInteger(bitrateKbps) || bitrateKbps < 100 || bitrateKbps > 6000 ||
    !['libx264', 'h264_nvenc'].includes(encoder)) throw new Error('Invalid H.264 laboratory capture profile');
  return {testPattern, seconds, fps, width, bitrateKbps, encoder};
}

export function h264Arguments(profile = {}) {
  const p = checkProfile(profile);
  const input = p.testPattern
    ? ['-f', 'lavfi', '-i', `testsrc2=size=1280x720:rate=${p.fps}`]
    : ['-f', 'gdigrab', '-framerate', String(p.fps), '-i', 'desktop'];
  const encoderArgs = p.encoder === 'libx264'
    ? ['-preset', 'ultrafast', '-tune', 'zerolatency', '-profile:v', 'baseline']
    : ['-preset', 'p1', '-tune', 'll'];
  return ['-hide_banner', '-loglevel', 'error', '-nostdin', ...input,
    '-t', String(p.seconds), '-vf', `scale=${p.width}:-2:flags=fast_bilinear`,
    '-an', '-c:v', p.encoder, ...encoderArgs, '-pix_fmt', 'yuv420p',
    '-g', String(p.fps), '-bf', '0', '-b:v', `${p.bitrateKbps}k`,
    '-f', 'mpegts', 'pipe:1'];
}

// A full transport-stream segment must start at offset zero and contain TS
// packets, each exactly 188 bytes with 0x47 synchronization marker.
export function assertTransportStream(data) {
  if (!Buffer.isBuffer(data) || data.length < 188 || data.length % 188 !== 0 || data.length > MAX_TS_BYTES)
    throw new Error('Invalid transport-stream size');
  for (let i = 0; i < data.length; i += 188) {
    if (data[i] !== 0x47) throw new Error('Transport-stream sync lost');
  }
}

/** On arrival of H264_BEGIN, chunks must be strictly ordered and within bound. */
export class H264Assembler {
  constructor({onChunk, onComplete}) {
    if (typeof onChunk !== 'function' || typeof onComplete !== 'function') throw new Error('Missing receiver callbacks');
    this.onChunk = onChunk;
    this.onComplete = onComplete;
    this.started = false;
    this.complete = false;
    this.size = 0;
    this.hash = crypto.createHash('sha256');
    this.pending = Buffer.alloc(0);
    this.syncCount = 0;
  }
  ingest(msg) {
    if (!msg || typeof msg !== 'object' || Array.isArray(msg) || this.complete) throw new Error('Unexpected H.264 message');
    if (msg.type === 'H264_BEGIN') {
      if (this.started || msg.codec !== 'h264' || msg.container !== 'mpegts' ||
        !Number.isInteger(msg.maxBytes) || msg.maxBytes !== MAX_TS_BYTES)
        throw new Error('Invalid H.264 header');
      this.started = true;
      return;
    }
    if (!this.started) throw new Error('H.264 stream not started');
    if (msg.type === 'H264_PART') {
      if (!Number.isSafeInteger(msg.offset) || msg.offset !== this.size ||
        typeof msg.data !== 'string' || msg.data.length > 3500 || !/^[A-Za-z0-9_-]+$/.test(msg.data))
        throw new Error('Invalid H.264 chunk');
      const data = Buffer.from(msg.data, 'base64url');
      if (!data.length || data.length > TS_CHUNK_BYTES || this.size + data.length > MAX_TS_BYTES)
        throw new Error('H.264 stream exceeds bounds');
      // Packet boundaries may cross network chunks; validate the sync every 188 bytes.
      const joined = Buffer.concat([this.pending, data]);
      let cursor = 0;
      while (joined.length - cursor >= 188) {
        if (joined[cursor] !== 0x47) throw new Error('H.264 TS sync error');
        cursor += 188;
        this.syncCount++;
      }
      this.pending = joined.subarray(cursor);
      this.size += data.length;
      this.hash.update(data);
      this.onChunk(data);
      return;
    }
    if (msg.type === 'H264_END') {
      if (!Number.isSafeInteger(msg.bytes) || msg.bytes !== this.size ||
        !SHA256_RE.test(msg.sha256) || this.pending.length || !this.syncCount ||
        this.hash.digest('hex') !== msg.sha256) throw new Error('Incomplete or corrupted H.264 stream');
      this.complete = true;
      this.onComplete({bytes: this.size, sha256: msg.sha256});
      return;
    }
    throw new Error('Remote input and unrelated actions prohibited by H.264 view-only receiver');
  }
}

/** Source read from FFmpeg stdout; never spawn a shell, only allow listed codecs. */
export async function sendH264(channel, socket, options = {}) {
  const {ffmpeg = 'ffmpeg', isSessionActive = () => true, ...rawProfile} = options;
  const profile = checkProfile(rawProfile);
  if (!isSessionActive()) throw new Error('H.264 screen trust revoked before capture');
  const child = spawn(ffmpeg, h264Arguments(profile), {stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true});
  let stderr = '';
  let size = 0;
  let status;
  const ended = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', code => resolve(code));
  });
  // Attach immediately: spawn('missing-ffmpeg') may reject before stdout iteration awaits ended.
  void ended.catch(() => {});
  child.stderr.on('data', b => {stderr = (stderr + b.toString()).slice(-1200);});
  const hash = crypto.createHash('sha256');
  let pending = Buffer.alloc(0);
  let trustRevoked = false;
  let viewerDisconnected = false;
  const lifecycle = createChildLifecycle(child);
  const requestStop = (revoked = false) => {
    if (revoked) trustRevoked = true;
    lifecycle.requestStop();
  };
  // A quiet FFmpeg stdout must not keep desktop capture alive after viewer
  // disconnect; trust revocation remains fail-closed on the same watcher.
  const trustWatch = setInterval(() => {
    if (socket.destroyed) {
      viewerDisconnected = true;
      requestStop(false);
      return;
    }
    let active = false;
    try { active = isSessionActive(); } catch { /* fail closed */ }
    if (!active) requestStop(true);
  }, 100);
  trustWatch.unref?.();
  try {
    channel.send({type: 'H264_BEGIN', codec: 'h264', container: 'mpegts', maxBytes: MAX_TS_BYTES,
      fps: profile.fps, width: profile.width, encoder: profile.encoder});
    for await (const bytes of child.stdout) {
      if (socket.destroyed) throw new Error('Viewer disconnected');
      if (!isSessionActive()) throw new Error('H.264 screen trust revoked during capture');
      pending = Buffer.concat([pending, bytes]);
      // Send only a full number of MPEG-TS packets (188 bytes). Every chunk <=2400 bytes.
      while (pending.length >= 188) {
        if (!isSessionActive()) throw new Error('H.264 screen trust revoked during capture');
        const length = Math.floor(Math.min(TS_CHUNK_BYTES, pending.length) / 188) * 188;
        const packet = pending.subarray(0, length);
        pending = pending.subarray(length);
        size += packet.length;
        if (size > MAX_TS_BYTES) throw new Error('H.264 limit exceeded');
        for (let i = 0; i < packet.length; i += 188) {
          if (packet[i] !== 0x47) throw new Error('FFmpeg did not produce MPEG-TS');
        }
        hash.update(packet);
        channel.send({type: 'H264_PART', offset: size - packet.length, data: packet.toString('base64url')});
        if (socket.writableLength > MAX_QUEUED_SOCKET_BYTES) {
          // Do not build an unbounded queue for a stalled/slow receiver.
          throw new Error('Viewer too slow; aborting preview instead of buffering sensitive frames');
        }
      }
    }
    if (viewerDisconnected || socket.destroyed) throw new Error('Viewer disconnected during capture');
    if (trustRevoked || !isSessionActive()) throw new Error('H.264 screen trust revoked while capture was idle');
    if (pending.length) throw new Error('Truncated MPEG-TS packet');
    status = await ended;
    if (status !== 0 || !size) throw new Error(`FFmpeg failed (${status}): ${stderr}`);
    const sha256 = hash.digest('hex');
    channel.send({type: 'H264_END', bytes: size, sha256});
    return {bytes: size, sha256, fps: profile.fps, width: profile.width, encoder: profile.encoder};
  } finally {
    clearInterval(trustWatch);
    lifecycle.cleanup();
    // Observe child errors / exits even if receiving client disconnects early.
    try {await Promise.race([ended, new Promise(resolve => setTimeout(resolve, 1500))]);} catch { /* reported above */ }
  }
}
