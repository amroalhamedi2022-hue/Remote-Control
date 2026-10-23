import crypto from 'node:crypto';

export const PROTOCOL = 'liquid-remote.discovery.v1';
export const UDP_PORT = 43827;
export const TCP_PORT = 43828;
const idPattern = /^[0-9a-f]{32}$/;

export const randomId = () => crypto.randomBytes(16).toString('hex');
export function payload(kind, { id, name, platform, tcpPort }) {
  if (!['DISCOVER', 'ANNOUNCE'].includes(kind)) throw new Error('Invalid discovery kind');
  return Buffer.from(JSON.stringify({ protocol: PROTOCOL, kind, id, name, platform, tcpPort }), 'utf8');
}
export function parsePacket(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0 || buffer.length > 1200) return null;
  let p;
  try { p = JSON.parse(buffer.toString('utf8')); } catch { return null; }
  if (!p || typeof p !== 'object' || Array.isArray(p) || p.protocol !== PROTOCOL ||
      !['DISCOVER', 'ANNOUNCE'].includes(p.kind) ||
      typeof p.id !== 'string' || !idPattern.test(p.id) ||
      typeof p.name !== 'string' || p.name.length === 0 || p.name.length > 64 ||
      typeof p.platform !== 'string' || p.platform.length > 32 ||
      !Number.isInteger(p.tcpPort) || p.tcpPort < 1 || p.tcpPort > 65535) return null;
  return { kind: p.kind, id: p.id, name: p.name, platform: p.platform, tcpPort: p.tcpPort };
}
export function parseEndpoint(text, defaultPort = UDP_PORT) {
  const match = /^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$/.exec(text);
  if (!match) throw new Error('Expected IPv4 address[:port]');
  const ip = match[1];
  if (ip.split('.').some(x => Number(x) > 255) || ip === '255.255.255.255')
    throw new Error('Invalid IPv4 address');
  const port = match[2] ? Number(match[2]) : defaultPort;
  if (port < 1 || port > 65535) throw new Error('Port out of range');
  return { ip, port };
}
