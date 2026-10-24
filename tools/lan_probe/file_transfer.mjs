// Opt-in, one-shot file transfer over an already authenticated AES-GCM LAN channel.
// This is a Node interoperability fixture, not Android SAF or a production audit.
import {constants} from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

export const MAX_FILE_BYTES = 64 * 1024 * 1024;
export const FILE_CHUNK_BYTES = 3072; // base64 fits the 8 KiB secure frame limit
const sha256 = () => crypto.createHash('sha256');
const hex = h => h.digest('hex');

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
async function receiveWithCancel(channel, signal) {
  checkCancelled(signal);
  if (!signal) return channel.receive();
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener('abort', onAbort);
      fn(value);
    };
    const onAbort = () => {
      channel.lines?.socket?.destroy();
      finish(reject, cancellationError());
    };
    signal.addEventListener('abort', onAbort, {once: true});
    if (signal.aborted) {onAbort(); return;}
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
export async function sendFileOnce(channel, filePath, {onProgress = () => {}, signal} = {}) {
  if (typeof onProgress !== 'function') throw new TypeError('Progress callback must be a function');
  checkCancelled(signal);
  // Do not follow symlinks; reject directory, pipe and changing-size sources.
  const handle=await fsp.open(filePath,constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
  try {
    const st=await handle.stat();
    if(!st.isFile() || st.size>MAX_FILE_BYTES)throw new Error('Unsupported source file');
    const name=safeTransferName(path.basename(filePath));
    const digest=await hashHandle(handle,st.size,signal);
    checkCancelled(signal);
    channel.send({type:'FILE_OFFER',name,bytes:st.size,sha256:digest});
    const ready=await receiveWithCancel(channel,signal);
    if(ready?.type==='FILE_DENIED')throw new Error('Receiver denied file transfer');
    if(ready?.type!=='FILE_READY')throw new Error('Invalid file transfer approval');
    const buf=Buffer.alloc(FILE_CHUNK_BYTES);
    let offset=0,seq=0;
    while(offset<st.size) {
      checkCancelled(signal);
      const {bytesRead}=await handle.read(buf,0,Math.min(buf.length,st.size-offset),offset);
      if(bytesRead<=0)throw new Error('Source file changed during transfer');
      channel.send({type:'FILE_CHUNK',seq,data:buf.subarray(0,bytesRead).toString('base64')});
      const ack=await receiveWithCancel(channel,signal);
      if(ack?.type!=='FILE_ACK'||ack.seq!==seq)throw new Error('Invalid file chunk acknowledgement');
      offset+=bytesRead;seq++;
      onProgress({bytes:offset,total:st.size,verified:false});
    }
    // Re-read the source to reject in-place changes even if its length stayed the same.
    if((await handle.stat()).size!==st.size || await hashHandle(handle,st.size,signal)!==digest)
      throw new Error('Source file changed during transfer');
    checkCancelled(signal);
    channel.send({type:'FILE_END',bytes:offset,sha256:digest});
    const done=await receiveWithCancel(channel,signal);
    if(done?.type!=='FILE_OK'||done.bytes!==offset||done.sha256!==digest)
      throw new Error('Invalid file completion acknowledgement');
    onProgress({bytes:offset,total:st.size,verified:true});
    return {bytes:offset,sha256:digest};
  } finally {await handle.close();}
}

export async function receiveFileOnce(channel, offer, {approve,directory,onProgress=()=>{},signal}) {
  if (typeof onProgress !== 'function') throw new TypeError('Progress callback must be a function');
  checkCancelled(signal);
  validateOffer(offer);
  if(typeof approve!=='function'||typeof directory!=='string')
    throw new Error('Explicit file receiver approval required');
  const approved=await approve(offer);
  checkCancelled(signal);
  if(approved!==true) {
    channel.send({type:'FILE_DENIED'});
    return null;
  }
  const destDir=await fsp.realpath(directory);
  if(!(await fsp.stat(destDir)).isDirectory())throw new Error('Destination must be a directory');
  checkCancelled(signal);
  const tmp=path.join(destDir,`.liquidremote-${crypto.randomUUID()}.part`);
  const file=await fsp.open(tmp,'wx',0o600);
  let saved=false;
  try {
    const h=sha256();let count=0,seq=0;
    channel.send({type:'FILE_READY'});
    while(true) {
      const packet=await receiveWithCancel(channel,signal);
      checkCancelled(signal);
      if(packet?.type==='FILE_END') {
        const digest=hex(h);
        if(count!==offer.bytes||packet.bytes!==count||packet.sha256!==digest||
            digest!==offer.sha256)throw new Error('File size or SHA-256 mismatch');
        await file.sync();await file.close();
        checkCancelled(signal);
        // Hard-link is atomic and fails if a destination already exists.
        // Never overwrite an existing file, including case-insensitive aliases.
        const ext=path.extname(offer.name),stem=offer.name.slice(0,offer.name.length-ext.length);
        let target;
        for(let i=1;i<=100;i++) {
          const candidate=path.join(destDir,i===1?offer.name:`${stem} (${i})${ext}`);
          try {await fsp.link(tmp,candidate);target=candidate;break;}
          catch(e){if(e.code!=='EEXIST')throw e;}
        }
        if(!target)throw new Error('No available destination filename');
        saved=true;
        await fsp.unlink(tmp);
        channel.send({type:'FILE_OK',bytes:count,sha256:digest});
        onProgress({bytes:count,total:offer.bytes,verified:true});
        return {path:target,bytes:count,sha256:digest};
      }
      if(packet?.type!=='FILE_CHUNK'||packet.seq!==seq||typeof packet.data!=='string'||
          packet.data.length>Math.ceil(FILE_CHUNK_BYTES*4/3)+4||
          !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(packet.data))
        throw new Error('Invalid file chunk');
      const data=Buffer.from(packet.data,'base64');
      if(data.length===0||data.length>FILE_CHUNK_BYTES||count+data.length>offer.bytes)
        throw new Error('File transfer exceeds approved size');
      let written=0;
      while(written<data.length) {
        checkCancelled(signal);
        const result=await file.write(data,written,data.length-written,count+written);
        if(result.bytesWritten<=0)throw new Error('Destination write stalled');
        written+=result.bytesWritten;
      }
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
