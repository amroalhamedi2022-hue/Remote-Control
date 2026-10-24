// Explicit, one-shot UTF-8 clipboard transfer over an ALREADY authenticated
// encrypted LAN channel. No background clipboard reading or auto-sync.
import {spawn} from 'node:child_process';

export const MAX_CLIPBOARD_BYTES = 2048;

export function clipboardByteLength(value) {
  if (typeof value !== 'string' || value.length === 0 ||
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\uFFFD]/u.test(value) ||
      /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value) ||
      /[\u00ad\u034f\u061c\u180e\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]|[\u{e0000}-\u{e007f}]/u.test(value)) {
    throw new Error('Invalid clipboard text');
  }
  const bytes = Buffer.byteLength(value, 'utf8');
  if (bytes > MAX_CLIPBOARD_BYTES) throw new Error('Clipboard text exceeds 2048 UTF-8 bytes');
  return bytes;
}

export async function acceptClipboardRequest(channel, request, {approve, writeClipboard}) {
  if (request?.type !== 'CLIPBOARD_PUT' || typeof approve !== 'function' ||
      typeof writeClipboard !== 'function') throw new Error('Clipboard action not permitted');
  const bytes = clipboardByteLength(request.text);
  if (await approve() !== true) {
    channel.send({type:'CLIPBOARD_DENIED'});
    return false;
  }
  await writeClipboard(request.text);
  channel.send({type:'CLIPBOARD_OK', bytes});
  return true;
}

// Windows only: fixed PowerShell command; user text enters via STDIN, never
// as an executable argument or shell interpolation. No clipboard reads.
export async function writeWindowsClipboard(text) {
  clipboardByteLength(text);
  if (process.platform !== 'win32') throw new Error('Windows clipboard host required');
  await new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      '[Console]::InputEncoding = [System.Text.Encoding]::UTF8; Set-Clipboard -Value ([Console]::In.ReadToEnd())'],
      {stdio:['pipe','ignore','pipe'], windowsHide:true});
    let settled = false;
    const timeout = setTimeout(() => {child.kill(); finish(new Error('Clipboard operation timed out'));}, 10_000);
    function finish(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (error) reject(error); else resolve();
    }
    child.on('error', finish);
    child.stderr.resume(); // Never log clipboard content or PowerShell output.
    child.on('close', code => finish(code === 0 ? null : new Error('Clipboard write failed')));
    child.stdin.on('error', () => {}); // child may exit before stdin drains
    child.stdin.end(text, 'utf8');
  });
}
