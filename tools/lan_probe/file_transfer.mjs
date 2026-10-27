// Opt-in, one-shot file transfer over an already authenticated AES-GCM LAN channel.
// This is a Node interoperability fixture, not Android SAF or a production audit.
import {constants} from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

export const MAX_FILE_BYTES = 64 * 1024 * 1024;
export const FILE_CHUNK_BYTES = 3072; // base64 fits the 8 KiB secure frame limit
export const FILE_IDLE_TIMEOUT_MS = 45_000; // bound waits for peer approval and chunk ACKs
function checkIdleTimeout(value) {
  if (!Number.isSafeInteger(value) || value < 1 || value > 120_000)
    throw new RangeError('Invalid file transfer idle timeout');
}
const sha256 = () => crypto.createHash('sha256');
const hex = h => h.digest('hex');

const BASE64_CHUNK_PATTERN = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

// Node's Base64 decoder accepts aliases with non-zero unused padding bits and
// silently normalizes some malformed-but-decodable input. The wire format is
// canonical: the sender emits Buffer.toString('base64'), so reject aliases.
function isCanonicalBase64(value) {
  if (typeof value !== 'string' || !BASE64_CHUNK_PATTERN.test(value)) return false;
  return Buffer.from(value, 'base64').toString('base64') === value;
}

// An explicit local cancel must unblock a peer waiting for a network frame.
// The production SecureEnvelope owns a socket; closing it also cancels its
// outstanding receive. The Promise fallback covers in-memory QA peers.
function cancellationError() {
  const error = new Error('File transfer cancelled');
  error.name = 'AbortError';
  return error;
}
function checkCancelled(signal) {
  if (signal?.aborted) throw cancellationError();
}

// File-intent channels are one-shot. Revoke the transport on any terminal receive
// failure, explicit denial, timeout, or cancellation; socket destruction is idempotent.
function abortFileChannel(channel) {
  try {
    if (typeof channel?.abort === 'function') channel.abort();
    else channel?.lines?.socket?.destroy();
  } catch { /* preserve the primary transfer outcome */ }
}

export async function receiveWithCancel(channel, signal, idleTimeoutMs, isSessionActive) {
  checkCancelled(signal);
  if (isSessionActive !== undefined && typeof isSessionActive !== 'function')
    throw new TypeError('Invalid file session guard');
  if (isSessionActive && !isSessionActive()) throw cancellationError();
  return new Promise((resolve, reject) => {
    let settled = false;
    let timer, revocationPoll;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearInterval(revocationPoll);
      signal?.removeEventListener('abort', onAbort);
      fn(value);
    };
    const terminatePeerWait = () => abortFileChannel(channel);
    const onAbort = () => {
      terminatePeerWait();
      finish(reject, cancellationError());
    };
    const onTimeout = () => {
      terminatePeerWait();
      const error = new Error('File transfer timed out waiting for peer');
      error.name = 'TimeoutError';
      finish(reject, error);
    };
    timer = setTimeout(onTimeout, idleTimeoutMs);
    // A trust revoke can happen while no frames arrive or while a consent
    // dialog is pending. Do not wait for the full network idle deadline.
    if (isSessionActive) revocationPoll = setInterval(() => {
      let active = false;
      try { active = isSessionActive(); } catch { /* fail closed */ }
      if (!active) {terminatePeerWait();finish(reject,cancellationError());}
    }, 100);
    signal?.addEventListener('abort', onAbort, {once: true});
    if (signal?.aborted) {onAbort(); return;}
    Promise.resolve().then(() => channel.receive()).then(
      value => finish(resolve, value),
      error => finish(reject, error),
    );
  });
}

export function safeTransferName(name) {
  if (typeof name !== 'string' || !name || name.length > 180 ||
      name === '.' || name === '..' || name.endsWith('.') || name.endsWith(' ') ||
      /[\\/<>:"|?*\u0000-\u001f\u007f-\u009f\uFFFD]/u.test(name) ||
      /[\u00ad\u034f\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]|[\u{e0000}-\u{e007f}]/u.test(name) ||
      /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(name) ||
      /^\.(?:liquidremote|netkit)-/iu.test(name) ||
      /^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)/iu.test(name)) {
    throw new Error('Unsafe transferred filename');
  }
  return name;
}
function validateOffer(offer) {
  if (offer?.type !== 'FILE_OFFER') throw new Error('Unexpected file transfer request');
  safeTransferName(offer.name);
  if (!Number.isSafeInteger(offer.bytes) || offer.bytes < 0 || offer.bytes > MAX_FILE_BYTES ||
      typeof offer.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(offer.sha256))
    throw new Error('Invalid file offer');
}
async function hashHandle(handle, size, signal) {
  const h=sha256(), buf=Buffer.alloc(FILE_CHUNK_BYTES);
  let pos=0;
  while(pos<size) {
    checkCancelled(signal);
    const {bytesRead}=await handle.read(buf,0,Math.min(buf.length,size-pos),pos);
    if(bytesRead<=0) throw new Error('Source file changed while hashing');
    h.update(buf.subarray(0,bytesRead));pos+=bytesRead;
  }
  return hex(h);
}
export async function sendFileOnce(channel, filePath, {onProgress = () => {}, signal, idleTimeoutMs = FILE_IDLE_TIMEOUT_MS} = {}) {
  if (typeof onProgress !== 'function') throw new TypeError('Progress callback must be a function');
  checkIdleTimeout(idleTimeoutMs);
  checkCancelled(signal);
  // Do not follow symlinks; reject directory, pipe and changing-size sources.
  const handle=await fsp.open(filePath,constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
  try {
    const st=await handle.stat();
    if(!st.isFile() || st.size>MAX_FILE_BYTES)throw new Error('Unsupported source file');
    const name=safeTransferName(path.basename(filePath));
    const digest=await hashHandle(handle,st.size,signal);
    checkCancelled(signal);
    // Once FILE_READY arrives, every local failure before FILE_END must tell
    // the peer to discard its staged bytes rather than wait for idle timeout.
    // FILE_END is the publication boundary: never cancel after it was sent.
    let receiverReady=false, endSent=false;
    try {
    channel.send({type:'FILE_OFFER',name,bytes:st.size,sha256:digest});
    const ready=await receiveWithCancel(channel,signal,idleTimeoutMs);
    if(ready?.type==='FILE_DENIED')throw new Error('Receiver denied file transfer');
    if(ready?.type!=='FILE_READY')throw new Error('Invalid file transfer approval');
    receiverReady=true;
    const buf=Buffer.alloc(FILE_CHUNK_BYTES);
    let offset=0,seq=0;
    while(offset<st.size) {
      checkCancelled(signal);
      const {bytesRead}=await handle.read(buf,0,Math.min(buf.length,st.size-offset),offset);
      if(bytesRead<=0)throw new Error('Source file changed during transfer');
      channel.send({type:'FILE_CHUNK',seq,data:buf.subarray(0,bytesRead).toString('base64')});
      const ack=await receiveWithCancel(channel,signal,idleTimeoutMs);
      if(ack?.type!=='FILE_ACK'||ack.seq!==seq)throw new Error('Invalid file chunk acknowledgement');
      offset+=bytesRead;seq++;
      onProgress({bytes:offset,total:st.size,verified:false});
    }
    // Re-read the source to reject in-place changes even if its length stayed the same.
    if((await handle.stat()).size!==st.size || await hashHandle(handle,st.size,signal)!==digest)
      throw new Error('Source file changed during transfer');
    checkCancelled(signal);
    channel.send({type:'FILE_END',bytes:offset,sha256:digest});
    endSent=true;
    const done=await receiveWithCancel(channel,signal,idleTimeoutMs);
    if(done?.type!=='FILE_OK'||done.bytes!==offset||done.sha256!==digest)
      throw new Error('Invalid file completion acknowledgement');
    onProgress({bytes:offset,total:st.size,verified:true});
    return {bytes:offset,sha256:digest};
    } catch (error) {
      if (receiverReady && !endSent) {
        // Best effort: a revoked/destroyed socket cannot always carry CANCEL.
        // The receiver's idle timeout and private staging cleanup still apply.
        try {channel.send({type:'FILE_CANCEL'});} catch { /* disconnected */ }
      }
      throw error;
    }
  } finally {await handle.close();}
}

async function receiveFileOnceInternal(channel, offer, {approve,directory,onProgress=()=>{},signal,
    isSessionActive=()=>true,idleTimeoutMs=FILE_IDLE_TIMEOUT_MS} = {}) {
  if (typeof onProgress !== 'function') throw new TypeError('Progress callback must be a function');
  checkIdleTimeout(idleTimeoutMs);
  if (typeof isSessionActive !== 'function') throw new TypeError('Invalid file session guard');
  const requireLiveSession = () => {
    checkCancelled(signal);
    if (!isSessionActive()) throw cancellationError();
  };
  requireLiveSession();
  try {
    validateOffer(offer);
  } catch (error) {
    try { channel.send({type:'FILE_DENIED'}); } catch { /* disconnected or malformed peer */ }
    throw error;
  }
  if(typeof approve!=='function'||typeof directory!=='string')
    throw new Error('Explicit file receiver approval required');
  // User consent may be asynchronous (a desktop dialog). Apply the same
  // cancellation and idle deadline as encrypted frame reads so a dismissed or
  // stuck dialog cannot keep a receiver session alive indefinitely.
  const approved=await receiveWithCancel({
    receive:()=>approve(offer), lines:channel.lines
  },signal,idleTimeoutMs,isSessionActive);
  requireLiveSession();
  if(approved!==true) {
    channel.send({type:'FILE_DENIED'});
    return null;
  }
  const destDir=await fsp.realpath(directory);
  if(!(await fsp.stat(destDir)).isDirectory())throw new Error('Destination must be a directory');
  requireLiveSession();
  const tmp=path.join(destDir,`.liquidremote-${crypto.randomUUID()}.part`);
  const file=await fsp.open(tmp,'wx',0o600);
  let saved=false;
  try {
    const h=sha256();let count=0,seq=0;
    requireLiveSession();
    channel.send({type:'FILE_READY'});
    while(true) {
      const packet=await receiveWithCancel(channel,signal,idleTimeoutMs,isSessionActive);
      requireLiveSession();
      // Dart sends FILE_CANCEL after FILE_READY when its source disappears,
      // the user cancels, or a chunk ACK is rejected. Never publish a partial.
      if(packet?.type==='FILE_CANCEL')
        throw cancellationError();
      if(packet?.type==='FILE_END') {
        const digest=hex(h);
        if(count!==offer.bytes||packet.bytes!==count||packet.sha256!==digest||
            digest!==offer.sha256)throw new Error('File size or SHA-256 mismatch');
        await file.sync();await file.close();
        requireLiveSession();
        // Hard-link is atomic and fails if a destination already exists.
        // Never overwrite an existing file, including case-insensitive aliases.
        const ext=path.extname(offer.name),stem=offer.name.slice(0,offer.name.length-ext.length);
        let target;
        try {
          for(let i=1;i<=100;i++) {
            const candidate=path.join(destDir,i===1?offer.name:`${stem} (${i})${ext}`);
            try {
              requireLiveSession();
              await fsp.link(tmp,candidate);
              target=candidate;
              // A revoke can arrive while the filesystem is creating the
              // hard-link. Do not publish a newly linked file after cancellation.
              requireLiveSession();
              break;
            } catch(e) {if(e.code!=='EEXIST')throw e;}
          }
          if(!target)throw new Error('No available destination filename');
          requireLiveSession();
          await fsp.unlink(tmp);
          requireLiveSession();
          // Publication boundary: after this point an ACK may have escaped.
          // Never roll back a file the sender may already believe is saved.
          saved=true;
          channel.send({type:'FILE_OK',bytes:count,sha256:digest});
          onProgress({bytes:count,total:offer.bytes,verified:true});
          return {path:target,bytes:count,sha256:digest};
        } catch(error) {
          // Before the success ACK, a failed unlink or a late revocation
          // must not leave a final file in the approved destination.
          if(!saved && target) {
            try {await fsp.unlink(target);}
            catch(cleanupError) {
              // Do not hide a failed rollback: the final name may still exist.
              throw new AggregateError([error, cleanupError],
                'File receive failed and final-file rollback failed');
            }
          }
          throw error;
        }
      }
      if(packet?.type!=='FILE_CHUNK'||packet.seq!==seq||typeof packet.data!=='string'||
          packet.data.length>Math.ceil(FILE_CHUNK_BYTES*4/3)+4||
          !isCanonicalBase64(packet.data))
        throw new Error('Invalid file chunk');
      const data=Buffer.from(packet.data,'base64');
      if(data.length===0||data.length>FILE_CHUNK_BYTES||count+data.length>offer.bytes)
        throw new Error('File transfer exceeds approved size');
      let written=0;
      while(written<data.length) {
        requireLiveSession();
        const result=await file.write(data,written,data.length-written,count+written);
        if(result.bytesWritten<=0)throw new Error('Destination write stalled');
        written+=result.bytesWritten;
      }
      requireLiveSession();
      h.update(data);count+=data.length;
      onProgress({bytes:count,total:offer.bytes,verified:false});
      channel.send({type:'FILE_ACK',seq});
      seq++;
    }
  } finally {
    await file.close().catch(()=>{});
    if(!saved)await fsp.unlink(tmp).catch(()=>{});
  }
}

// Keep cleanup at the public API boundary so errors before staging (bad offer,
// consent failure, invalid destination) revoke the same one-shot channel too.
export async function receiveFileOnce(channel, offer, options = {}) {
  try {
    const result = await receiveFileOnceInternal(channel, offer, options);
    if (result === null) abortFileChannel(channel); // explicit user denial
    return result;
  } catch (error) {
    abortFileChannel(channel);
    throw error;
  }
}
