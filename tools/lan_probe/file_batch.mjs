// Bounded, opt-in nested folder transfer over an already paired AES-GCM channel.
// Node interoperability fixture only: NOT Android SAF or production-grade directory isolation.
// Per-file SHA-256 is verified by file_transfer.mjs. A whole batch is staged
// privately and published only after its manifest and every file verify.
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import {safeTransferName, sendFileOnce, receiveFileOnce, receiveWithCancel,
  MAX_FILE_BYTES, FILE_IDLE_TIMEOUT_MS} from './file_transfer.mjs';

export const MAX_FOLDER_FILES = 64;
export const MAX_FOLDER_DIRECTORIES = 64;
export const MAX_FOLDER_BYTES = 256 * 1024 * 1024;
export const MAX_FOLDER_DEPTH = 8;

function validateLimit(timeout) {
  if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 120000)
    throw new RangeError('Invalid folder transfer idle timeout');
}
export function safeRelativeFile(value) {
  if (typeof value !== 'string' || value.length > 1024 || !value ||
      value.includes('\\') || value.startsWith('/') || value.includes(':'))
    throw new Error('Unsafe relative file path');
  const parts = value.split('/');
  if (parts.length > MAX_FOLDER_DEPTH + 1) throw new Error('Folder nesting limit exceeded');
  for (const part of parts) safeTransferName(part);
  return parts;
}
// Use a conservative cross-platform collision key. Windows and macOS can
// resolve names that differ only in case or Unicode normalization to one file.
const canonicalRelative = parts => parts.join('/').normalize('NFC').toLowerCase();
function validBegin(msg) {
  if (msg?.type !== 'FOLDER_BEGIN' || !Number.isSafeInteger(msg.count) ||
      msg.count < 0 || msg.count > MAX_FOLDER_FILES ||
      !Number.isSafeInteger(msg.bytes) || msg.bytes < 0 || msg.bytes > MAX_FOLDER_BYTES)
    throw new Error('Invalid folder offer');
  safeTransferName(msg.folder);
  // Older peers may omit the optional directory manifest. New peers preserve
  // empty subfolders without granting any extra filesystem permissions.
  const directories = msg.directories === undefined ? [] : msg.directories;
  if (!Array.isArray(directories) || directories.length > MAX_FOLDER_DIRECTORIES)
    throw new Error('Invalid folder directory manifest');
  const seen = new Set();
  return directories.map(relative => {
    const parts = safeRelativeFile(relative);
    if (parts.length > MAX_FOLDER_DEPTH) throw new Error('Folder nesting limit exceeded');
    const canonical = canonicalRelative(parts);
    if (seen.has(canonical)) throw new Error('Duplicate folder directory');
    seen.add(canonical);
    return parts;
  });
}
async function collectFolder(root) {
  const stat = await fs.lstat(root);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Source must be a real directory');
  const realRoot = await fs.realpath(root);
  const files = [];
  const directories = [];
  let bytes = 0;
  async function visit(directory, parts) {
    const entries = (await fs.readdir(directory, {withFileTypes:true}))
      .sort((a,b)=>a.name.localeCompare(b.name,'en'));
    for (const entry of entries) {
      safeTransferName(entry.name);
      const childParts = [...parts,entry.name];
      const relative = childParts.join('/');
      safeRelativeFile(relative);
      const full = path.join(directory,entry.name);
      const info = await fs.lstat(full);
      if (info.isSymbolicLink()) throw new Error('Folder symlinks are not transferable');
      if (info.isDirectory()) {
        if (childParts.length > MAX_FOLDER_DEPTH) throw new Error('Folder nesting limit exceeded');
        if (directories.length >= MAX_FOLDER_DIRECTORIES)
          throw new Error('Folder exceeds bounded directory limits');
        directories.push(relative);
        await visit(full,childParts);
      } else if (info.isFile()) {
        if (info.size > MAX_FILE_BYTES || !Number.isSafeInteger(info.size))
          throw new Error('File exceeds bounded transfer limit');
        bytes += info.size;
        if (bytes > MAX_FOLDER_BYTES || files.length >= MAX_FOLDER_FILES)
          throw new Error('Folder exceeds bounded transfer limits');
        files.push({full,relative,bytes:info.size});
      } else throw new Error('Non-regular folder entry rejected');
    }
  }
  await visit(realRoot,[]);
  return {folder:safeTransferName(path.basename(realRoot)),files,directories,bytes};
}
async function ensureSafeDirectory(root, components) {
  let current = root;
  for (const component of components) {
    safeTransferName(component);
    current = path.join(current,component);
    try { await fs.mkdir(current); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    const info = await fs.lstat(current);
    if (!info.isDirectory() || info.isSymbolicLink())
      throw new Error('Unsafe destination folder component');
    // This checks the resolved location before file creation. Concurrent local
    // directory swaps still require native openat-style protection for production.
    const resolved = await fs.realpath(current);
    if (resolved !== root && !resolved.startsWith(root + path.sep))
      throw new Error('Destination folder escaped selected root');
  }
  return current;
}
export async function sendFolderOnce(channel, folderPath,
    {signal, idleTimeoutMs=FILE_IDLE_TIMEOUT_MS, onProgress=()=>{}}={}) {
  validateLimit(idleTimeoutMs);
  if (signal?.aborted) throw Object.assign(new Error('Folder transfer cancelled'),{name:'AbortError'});
  const {folder,files,directories,bytes}=await collectFolder(folderPath);
  channel.send({type:'FOLDER_BEGIN',folder,count:files.length,bytes,directories});
  const response=await receiveWithCancel(channel,signal,idleTimeoutMs);
  if (response?.type==='FOLDER_DENIED') throw new Error('Receiver denied folder transfer');
  if (response?.type!=='FOLDER_READY') throw new Error('Invalid folder approval');
  let transferred=0;
  for (const [index,file] of files.entries()) {
    if (signal?.aborted) throw Object.assign(new Error('Folder transfer cancelled'),{name:'AbortError'});
    channel.send({type:'FOLDER_ENTRY',path:file.relative,index});
    const result=await sendFileOnce(channel,file.full,{signal,idleTimeoutMs});
    if (result.bytes!==file.bytes) throw new Error('Folder source size changed');
    transferred+=result.bytes;
    onProgress({files:index+1,totalFiles:files.length,bytes:transferred,totalBytes:bytes});
  }
  channel.send({type:'FOLDER_END',count:files.length,bytes:transferred});
  const done=await receiveWithCancel(channel,signal,idleTimeoutMs);
  if (done?.type!=='FOLDER_OK'||done.count!==files.length||done.bytes!==bytes)
    throw new Error('Invalid folder completion acknowledgement');
  return {count:files.length,bytes};
}
export async function receiveFolderOnce(channel, begin,
    {directory,approve,signal,idleTimeoutMs=FILE_IDLE_TIMEOUT_MS,onProgress=()=>{}}={}) {
  validateLimit(idleTimeoutMs);
  const directories=validBegin(begin);
  if (typeof approve!=='function' || typeof directory!=='string')
    throw new Error('Explicit folder receiver approval required');
  const permitted=await receiveWithCancel({receive:()=>approve(begin),lines:channel.lines},
    signal,idleTimeoutMs);
  if (permitted!==true) {
    channel.send({type:'FOLDER_DENIED'});
    return null;
  }
  const root=await fs.realpath(directory);
  if (!(await fs.lstat(root)).isDirectory()) throw new Error('Destination must be a directory');
  // Never place partial files in the user-selected directory. Keep all batch
  // writes in a private sibling and publish only after FOLDER_END validates.
  // A crash can leave a hidden staging directory; startup cleanup is still
  // required before treating this Node fixture as production-ready.
  const staging=await fs.mkdtemp(path.join(root,'.liquidremote-batch-'));
  let published=false;
  try {
  const seen=new Set();
  const fileParents=new Set();
  const reservedDirectories=new Set();
  for (const components of directories) {
    for (let depth=1;depth<=components.length;depth++)
      reservedDirectories.add(canonicalRelative(components.slice(0,depth)));
  }
  let total=0;
  // All directory paths were validated before consent. Never create a folder
  // on a denied request; verify each existing component is not a symlink.
  for (const components of directories) await ensureSafeDirectory(staging,components);
  channel.send({type:'FOLDER_READY'});
  for (let i=0;i<begin.count;i++) {
    const entry=await receiveWithCancel(channel,signal,idleTimeoutMs);
    if (entry?.type!=='FOLDER_ENTRY'||entry.index!==i)
      throw new Error('Invalid folder entry order');
    const parts=safeRelativeFile(entry.path);
    const canonical=canonicalRelative(parts);
    if (seen.has(canonical)) throw new Error('Duplicate folder entry');
    if (reservedDirectories.has(canonical) || fileParents.has(canonical))
      throw new Error('Folder file conflicts with a directory');
    for (let depth=1;depth<parts.length;depth++) {
      const parent=canonicalRelative(parts.slice(0,depth));
      if (seen.has(parent)) throw new Error('Folder file conflicts with a parent file');
      fileParents.add(parent);
    }
    seen.add(canonical);
    const target=await ensureSafeDirectory(staging,parts.slice(0,-1));
    const offer=await receiveWithCancel(channel,signal,idleTimeoutMs);
    if (offer?.name!==parts.at(-1)) throw new Error('Folder entry filename mismatch');
    // Reject a forged offer before writing any bytes. The sender must stay
    // inside the total size approved by the receiving user.
    if (!Number.isSafeInteger(offer.bytes) || offer.bytes<0 ||
        offer.bytes>begin.bytes-total)
      throw new Error('Folder entry exceeds approved remaining byte budget');
    const result=await receiveFileOnce(channel,offer,{
      directory:target,approve:async()=>true,signal,idleTimeoutMs
    });
    if (!result) throw new Error('Approved folder entry unexpectedly denied');
    total+=result.bytes;
    if (total>begin.bytes) throw new Error('Folder exceeded approved byte count');
    onProgress({files:i+1,totalFiles:begin.count,bytes:total,totalBytes:begin.bytes});
  }
  const end=await receiveWithCancel(channel,signal,idleTimeoutMs);
  if (end?.type!=='FOLDER_END'||end.count!==begin.count||
      end.bytes!==total||total!==begin.bytes)
    throw new Error('Folder transfer size mismatch');
  // A UUID destination avoids replacing an existing directory, including an
  // empty one on POSIX where rename() can otherwise silently overwrite it.
  // The original folder label remains visible. No destination overwrite is
  // attempted, and a collision is rejected instead of retried unsafely.
  const destinationName=`${begin.folder} (received ${crypto.randomUUID()})`;
  await fs.rename(staging,path.join(root,destinationName));
  published=true;
  channel.send({type:'FOLDER_OK',count:begin.count,bytes:total});
  return {count:begin.count,bytes:total};
  } finally {
    if (!published) await fs.rm(staging,{recursive:true,force:true});
  }
}
