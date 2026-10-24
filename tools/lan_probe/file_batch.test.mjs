import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import {safeRelativeFile,sendFolderOnce,receiveFolderOnce,
  MAX_FOLDER_FILES,MAX_FOLDER_BYTES} from './file_batch.mjs';
function channels() {
  function endpoint() {
    const q=[];let waiting;
    return {push(v){if(waiting){const fn=waiting;waiting=null;fn(v);}else q.push(v);},
      receive(){return q.length?Promise.resolve(q.shift()):new Promise(resolve=>waiting=resolve);}};
  }
  const a=endpoint(),b=endpoint();
  return [{send:v=>b.push(v),receive:()=>a.receive()},
    {send:v=>a.push(v),receive:()=>b.receive()}];
}
async function sandbox(fn) {
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-folder-'));
  try{return await fn(dir);}finally{await fs.rm(dir,{recursive:true,force:true});}
}
test('reject absolute, traversal, reserved and deeply nested relative paths',()=>{
  for(const bad of ['../x','a/../x','a//x','/x','C:/x','a\\x','CON.txt','a/NUL',
    'a/hidden\u202Ename','a/'.repeat(9)+'file']) {
    assert.throws(()=>safeRelativeFile(bad));
  }
  assert.deepEqual(safeRelativeFile('الصور/رحلة 🫧.png'),['الصور','رحلة 🫧.png']);
});
test('nested folder sends all files over encrypted-channel contract with exact hashes',()=>sandbox(async root=>{
  const src=path.join(root,'source'),dest=path.join(root,'destination');
  await fs.mkdir(path.join(src,'الصور'),{recursive:true});await fs.mkdir(dest);
  await fs.writeFile(path.join(src,'hello.txt'),'مرحبا');
  await fs.writeFile(path.join(src,'الصور','photo.bin'),Buffer.alloc(6200,7));
  const [a,b]=channels(),progress=[];
  const receiving=(async()=>receiveFolderOnce(b,await b.receive(),{
    directory:dest,approve:async()=>true,onProgress:p=>progress.push(p)}))();
  const sending=sendFolderOnce(a,src);
  const [sent,received]=await Promise.all([sending,receiving]);
  assert.deepEqual(sent,received);
  assert.equal(sent.count,2);
  assert.deepEqual(await fs.readFile(path.join(dest,'hello.txt')),
    await fs.readFile(path.join(src,'hello.txt')));
  assert.deepEqual(await fs.readFile(path.join(dest,'الصور','photo.bin')),
    await fs.readFile(path.join(src,'الصور','photo.bin')));
  assert.equal(progress.at(-1).bytes,sent.bytes);
  assert.deepEqual((await fs.readdir(dest)).sort(),['hello.txt','الصور'].sort());
}));
test('folder consent denied before any destination files or subfolders exist',()=>sandbox(async root=>{
  const src=path.join(root,'src'),dest=path.join(root,'dest');
  await fs.mkdir(src);await fs.mkdir(dest);await fs.writeFile(path.join(src,'a.txt'),'hello');
  const [a,b]=channels();
  const receiving=(async()=>receiveFolderOnce(b,await b.receive(),{
    directory:dest,approve:async()=>false}))();
  await assert.rejects(sendFolderOnce(a,src),/denied/);
  assert.equal(await receiving,null);
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('sender refuses symlinks and oversized folder before network offer',()=>sandbox(async root=>{
  const src=path.join(root,'src');await fs.mkdir(src);
  await fs.symlink(root,path.join(src,'escape'));
  const [a]=channels();
  await assert.rejects(sendFolderOnce(a,src),/symlink/);
  await fs.rm(path.join(src,'escape'));
  for(let i=0;i<=MAX_FOLDER_FILES;i++)
    await fs.writeFile(path.join(src,'f'+i+'.txt'),'x');
  await assert.rejects(sendFolderOnce(a,src),/limits/);
  assert.ok(MAX_FOLDER_BYTES>0);
}));
test('receiver rejects traversal before writing a file',()=>sandbox(async root=>{
  const [sender,receiver]=channels();
  const incoming=receiveFolderOnce(receiver,{type:'FOLDER_BEGIN',folder:'photos',count:1,bytes:1},
    {directory:root,approve:async()=>true,idleTimeoutMs:100});
  assert.deepEqual(await sender.receive(),{type:'FOLDER_READY'});
  sender.send({type:'FOLDER_ENTRY',index:0,path:'../escape.txt'});
  await assert.rejects(incoming);
  assert.deepEqual(await fs.readdir(root),[]);
}));
test('empty folder is transferred as a valid zero-byte batch',()=>sandbox(async root=>{
  const src=path.join(root,'src'),dest=path.join(root,'dest');
  await fs.mkdir(src);await fs.mkdir(dest);
  const [a,b]=channels();
  const receiving=(async()=>receiveFolderOnce(b,await b.receive(),{
    directory:dest,approve:async()=>true}))();
  assert.deepEqual(await Promise.all([sendFolderOnce(a,src),receiving]),
    [{count:0,bytes:0},{count:0,bytes:0}]);
}));
