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

export function safeTransferName(name) {
  if (typeof name !== 'string' || !name || name.length > 180 ||
      name === '.' || name === '..' || name.endsWith('.') || name.endsWith(' ') ||
      /[\\/<>:"|?*\u0000-\u001f\u007f-\u009f\uFFFD]/u.test(name) ||
      /[\u00ad\u034f\u061c\u180e\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]|[\u{e0000}-\u{e007f}]/u.test(name) ||
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
async function hashHandle(handle, size) {
  const h=sha256(), buf=Buffer.alloc(FILE_CHUNK_BYTES);
  let pos=0;
  while(pos<size) {
    const {bytesRead}=await handle.read(buf,0,Math.min(buf.length,size-pos),pos);
    if(bytesRead<=0) throw new Error('Source file changed while hashing');
    h.update(buf.subarray(0,bytesRead));pos+=bytesRead;
  }
  return hex(h);
}
export async function sendFileOnce(channel, filePath) {
  // Do not follow symlinks; reject directory, pipe and changing-size sources.
  const handle=await fsp.open(filePath,constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
  try {
    const st=await handle.stat();
    if(!st.isFile() || st.size>MAX_FILE_BYTES)throw new Error('Unsupported source file');
    const name=safeTransferName(path.basename(filePath));
    const digest=await hashHandle(handle,st.size);
    channel.send({type:'FILE_OFFER',name,bytes:st.size,sha256:digest});
    const ready=await channel.receive();
    if(ready?.type==='FILE_DENIED')throw new Error('Receiver denied file transfer');
    if(ready?.type!=='FILE_READY')throw new Error('Invalid file transfer approval');
    const buf=Buffer.alloc(FILE_CHUNK_BYTES);
    let offset=0,seq=0;
    while(offset<st.size) {
      const {bytesRead}=await handle.read(buf,0,Math.min(buf.length,st.size-offset),offset);
      if(bytesRead<=0)throw new Error('Source file changed during transfer');
      channel.send({type:'FILE_CHUNK',seq,data:buf.subarray(0,bytesRead).toString('base64')});
      const ack=await channel.receive();
      if(ack?.type!=='FILE_ACK'||ack.seq!==seq)throw new Error('Invalid file chunk acknowledgement');
      offset+=bytesRead;seq++;
    }
    // Re-read the source to reject in-place changes even if its length stayed the same.
    if((await handle.stat()).size!==st.size || await hashHandle(handle,st.size)!==digest)
      throw new Error('Source file changed during transfer');
    channel.send({type:'FILE_END',bytes:offset,sha256:digest});
    const done=await channel.receive();
    if(done?.type!=='FILE_OK'||done.bytes!==offset||done.sha256!==digest)
      throw new Error('Invalid file completion acknowledgement');
    return {bytes:offset,sha256:digest};
  } finally {await handle.close();}
}

export async function receiveFileOnce(channel, offer, {approve,directory}) {
  validateOffer(offer);
  if(typeof approve!=='function'||typeof directory!=='string')
    throw new Error('Explicit file receiver approval required');
  if(await approve(offer)!==true) {
    channel.send({type:'FILE_DENIED'});
    return null;
  }
  const destDir=await fsp.realpath(directory);
  if(!(await fsp.stat(destDir)).isDirectory())throw new Error('Destination must be a directory');
  const tmp=path.join(destDir,`.liquidremote-${crypto.randomUUID()}.part`);
  const file=await fsp.open(tmp,'wx',0o600);
  let saved=false;
  try {
    const h=sha256();let count=0,seq=0;
    channel.send({type:'FILE_READY'});
    while(true) {
      const packet=await channel.receive();
      if(packet?.type==='FILE_END') {
        const digest=hex(h);
        if(count!==offer.bytes||packet.bytes!==count||packet.sha256!==digest||
            digest!==offer.sha256)throw new Error('File size or SHA-256 mismatch');
        await file.sync();await file.close();
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
        const result=await file.write(data,written,data.length-written,count+written);
        if(result.bytesWritten<=0)throw new Error('Destination write stalled');
        written+=result.bytesWritten;
      }
      h.update(data);count+=data.length;
      channel.send({type:'FILE_ACK',seq});
      seq++;
    }
  } finally {
    await file.close().catch(()=>{});
    if(!saved)await fsp.unlink(tmp).catch(()=>{});
  }
}
