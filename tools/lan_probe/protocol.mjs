import crypto from 'node:crypto';
import net from 'node:net';

export const PROTOCOL = 'liquid-remote.discovery.v1';
export const UDP_PORT = 43827;
export const TCP_PORT = 43828;
const idPattern = /^[0-9a-f]{32}$/;
// Device labels come from unauthenticated UDP advertisements. Reject invisible
// direction overrides and line/control characters before showing a peer in UI.
// This is display-spoofing protection, not authentication or pairing approval.
const unsafeLabel = /[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u206f\ufeff\ufff9-\ufffb]/u;
export function isSafeDiscoveryLabel(value, maxLength) {
  return typeof value === 'string' && value.trim().length > 0 &&
    value.length <= maxLength && !unsafeLabel.test(value);
}

// Local-only IPv4 policy shared by the Node Windows host and manual probes.
// Production defaults to RFC1918 and IPv4 link-local only. Loopback is opt-in
// for isolated test fixtures; it must not silently broaden production pairing.
// This is not proof of a trusted peer; cryptographic pairing + consent remain required.
export function isLanIpv4(value, {allowLoopback = false} = {}) {
  if (typeof value !== 'string' || net.isIP(value) !== 4) return false;
  const [a, b] = value.split('.').map(Number);
  return (allowLoopback && a === 127) || a === 10 ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 169 && b === 254);
}

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
      !isSafeDiscoveryLabel(p.name, 64) ||
      !isSafeDiscoveryLabel(p.platform, 32) ||
      !Number.isInteger(p.tcpPort) || p.tcpPort < 1 || p.tcpPort > 65535) return null;
  return { kind: p.kind, id: p.id, name: p.name, platform: p.platform, tcpPort: p.tcpPort };
}
export function parseEndpoint(text, defaultPort = UDP_PORT, {allowLoopback = false} = {}) {
  const match = /^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$/.exec(text);
  if (!match) throw new Error('Expected IPv4 address[:port]');
  const ip = match[1];
  if (!isLanIpv4(ip, {allowLoopback})) throw new Error('Expected a local LAN IPv4 address');
  const port = match[2] ? Number(match[2]) : defaultPort;
  if (port < 1 || port > 65535) throw new Error('Port out of range');
  return { ip, port };
}
