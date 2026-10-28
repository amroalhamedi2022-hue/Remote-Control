// Explicit, one-shot UTF-8 clipboard transfer over an ALREADY authenticated
// encrypted LAN channel. No background clipboard reading or auto-sync.
import {spawn} from 'node:child_process';

export const MAX_CLIPBOARD_BYTES = 2048;

export function clipboardByteLength(value) {
  if (typeof value !== 'string' || value.length === 0 ||
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\uFFFD]/u.test(value) ||
      /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value) ||
      /[\u00ad\u034f\u061c\u180e\u200b\u200e\u200f\u202a-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]|[\u{e0000}-\u{e007f}]/u.test(value)) {
    throw new Error('Invalid clipboard text');
  }
  const bytes = Buffer.byteLength(value, 'utf8');
  if (bytes > MAX_CLIPBOARD_BYTES) throw new Error('Clipboard text exceeds 2048 UTF-8 bytes');
  return bytes;
}

function clipboardAbortError() {
  const error = new Error('Clipboard session revoked or cancelled');
  error.name = 'AbortError';
  return error;
}

function clipboardSessionActive(isSessionActive) {
  try { return isSessionActive() === true; } catch { return false; }
}

function requireActiveClipboardSession(isSessionActive, signal) {
  if (signal?.aborted || !clipboardSessionActive(isSessionActive)) throw clipboardAbortError();
}

// Consent can be a pending native dialog; expiry/abort must not allow a late
// YES to write the clipboard. Promise.race observes late rejections safely.
async function awaitClipboardConsent(approve, signal, timeoutMs, isSessionActive) {
  let timer;
  let revocationPoll;
  let onAbort;
  try {
    const deadlines = [
      Promise.resolve().then(approve),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('Clipboard consent timed out')), timeoutMs);
      }),
      // Session revocation may be recorded independently of AbortSignal. Poll the
      // trust ledger while the native consent prompt is still open and fail closed.
      new Promise((_, reject) => {
        revocationPoll = setInterval(() => {
          if (!clipboardSessionActive(isSessionActive)) reject(clipboardAbortError());
        }, 100);
      }),
    ];
    if (signal) deadlines.push(new Promise((_, reject) => {
      onAbort = () => reject(clipboardAbortError());
      signal.addEventListener('abort', onAbort, {once: true});
      if (signal.aborted) onAbort();
    }));
    return await Promise.race(deadlines);
  } finally {
    clearTimeout(timer);
    clearInterval(revocationPoll);
    if (onAbort) signal.removeEventListener('abort', onAbort);
  }
}

export async function acceptClipboardRequest(channel, request,
    {approve, writeClipboard, isSessionActive = () => true, signal,
      consentTimeoutMs = 45_000} = {}) {
  if (request?.type !== 'CLIPBOARD_PUT' || typeof approve !== 'function' ||
      typeof writeClipboard !== 'function' || typeof isSessionActive !== 'function' ||
      !Number.isSafeInteger(consentTimeoutMs) || consentTimeoutMs < 1 ||
      consentTimeoutMs > 120_000) throw new Error('Clipboard action not permitted');
  const bytes = clipboardByteLength(request.text);
  requireActiveClipboardSession(isSessionActive, signal);
  let approved;
  try {
    approved = await awaitClipboardConsent(approve, signal, consentTimeoutMs, isSessionActive);
  } catch (error) {
    // A timed-out local prompt can still deny a live peer. A revoked channel
    // must never receive an acknowledgement, even a denial.
    if (!signal?.aborted && clipboardSessionActive(isSessionActive)) {
      try { channel.send({type:'CLIPBOARD_DENIED'}); } catch { /* peer gone */ }
    }
    throw error;
  }
  requireActiveClipboardSession(isSessionActive, signal);
  if (approved !== true) {
    channel.send({type:'CLIPBOARD_DENIED'});
    return false;
  }
  // A backend may finish an OS write after cancellation. This final check
  // prevents a false success ACK, but cannot undo an already committed write.
  await writeClipboard(request.text, {signal});
  requireActiveClipboardSession(isSessionActive, signal);
  channel.send({type:'CLIPBOARD_OK', bytes});
  return true;
}

// Windows only: fixed PowerShell command; user text enters via STDIN, never
// as an executable argument or shell interpolation. No clipboard reads.
export async function writeWindowsClipboard(text, {signal} = {}) {
  clipboardByteLength(text);
  if (process.platform !== 'win32') throw new Error('Windows clipboard host required');
  if (signal?.aborted) throw clipboardAbortError();
  await new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      '[Console]::InputEncoding = [System.Text.Encoding]::UTF8; Set-Clipboard -Value ([Console]::In.ReadToEnd())'],
      {stdio:['pipe','ignore','pipe'], windowsHide:true});
    let settled = false;
    const onAbort = () => {child.kill(); finish(clipboardAbortError());};
    const timeout = setTimeout(() => {
      child.kill();
      finish(new Error('Clipboard operation timed out'));
    }, 10_000);
    function finish(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
      if (error) reject(error); else resolve();
    }
    child.on('error', finish);
    child.stderr.resume(); // Never log clipboard content or PowerShell output.
    child.on('close', code => finish(code === 0 ? null : new Error('Clipboard write failed')));
    child.stdin.on('error', () => {}); // child may exit before stdin drains
    signal?.addEventListener('abort', onAbort, {once: true});
    if (signal?.aborted) {onAbort(); return;}
    child.stdin.end(text, 'utf8');
  });
}
