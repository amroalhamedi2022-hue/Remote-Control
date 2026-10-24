import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import {sendFileOnce} from './file_transfer.mjs';
import {safeRelativeFile,sendFolderOnce,receiveFolderOnce,
  cleanupStaleFolderTransfers,STAGING_RECOVERY_MIN_AGE_MS,
  MAX_FOLDER_FILES,MAX_FOLDER_BYTES,MAX_FOLDER_DIRECTORIES} from './file_batch.mjs';
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
  const published=(await fs.readdir(dest)).filter(n=>n.startsWith('source (received '));
  assert.equal(published.length,1);
  const receivedRoot=path.join(dest,published[0]);
  assert.deepEqual(await fs.readFile(path.join(receivedRoot,'hello.txt')),
    await fs.readFile(path.join(src,'hello.txt')));
  assert.deepEqual(await fs.readFile(path.join(receivedRoot,'الصور','photo.bin')),
    await fs.readFile(path.join(src,'الصور','photo.bin')));
  assert.equal(progress.at(-1).bytes,sent.bytes);
  assert.deepEqual((await fs.readdir(receivedRoot)).sort(),['hello.txt','الصور'].sort());
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

test('preserves nested empty folders and mixed content after explicit approval',()=>sandbox(async root=>{
  const src=path.join(root,'src'),dest=path.join(root,'dest');
  await fs.mkdir(path.join(src,'فارغ','متداخل'),{recursive:true});
  await fs.mkdir(path.join(src,'other-empty'),{recursive:true});
  await fs.mkdir(dest);
  await fs.writeFile(path.join(src,'note.txt'),'folder test');
  const [a,b]=channels();
  const receiving=(async()=>receiveFolderOnce(b,await b.receive(),{
    directory:dest,approve:async()=>true}))();
  const [sent,received]=await Promise.all([sendFolderOnce(a,src),receiving]);
  assert.deepEqual(sent,received);
  assert.deepEqual(sent,{count:1,bytes:11});
  const published=(await fs.readdir(dest)).filter(n=>n.startsWith('src (received '));
  assert.equal(published.length,1);
  const receivedRoot=path.join(dest,published[0]);
  assert.ok((await fs.stat(path.join(receivedRoot,'فارغ','متداخل'))).isDirectory());
  assert.ok((await fs.stat(path.join(receivedRoot,'other-empty'))).isDirectory());
  assert.equal(await fs.readFile(path.join(receivedRoot,'note.txt'),'utf8'),'folder test');
}));
test('rejects unsafe, duplicate or oversized directory manifests before approval',()=>sandbox(async root=>{
  const bad=[['../escape'],['a\\b'],['a','A'],Array(MAX_FOLDER_DIRECTORIES+1).fill('x')];
  for(const directories of bad){
    let approved=false;
    await assert.rejects(receiveFolderOnce({send(){}},{
      type:'FOLDER_BEGIN',folder:'photos',count:0,bytes:0,directories
    },{directory:root,approve:async()=>{approved=true;return true;}}));
    assert.equal(approved,false);
    assert.deepEqual(await fs.readdir(root),[]);
  }
}));
test('denying a folder with empty subdirectories creates nothing',()=>sandbox(async root=>{
  const src=path.join(root,'src'),dest=path.join(root,'dest');
  await fs.mkdir(path.join(src,'empty','nested'),{recursive:true});await fs.mkdir(dest);
  const [a,b]=channels();
  const receiving=(async()=>receiveFolderOnce(b,await b.receive(),{
    directory:dest,approve:async()=>false}))();
  await assert.rejects(sendFolderOnce(a,src),/denied/);
  assert.equal(await receiving,null);
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('sender bounds directory count before offering transfer',()=>sandbox(async root=>{
  const src=path.join(root,'src');await fs.mkdir(src);
  for(let i=0;i<=MAX_FOLDER_DIRECTORIES;i++)
    await fs.mkdir(path.join(src,'d'+i));
  const [a]=channels();
  await assert.rejects(sendFolderOnce(a,src),/directory limits/);
}));

test('receiver rejects a file offer larger than approved folder byte budget before writing',()=>sandbox(async root=>{
  const [sender,receiver]=channels();
  const incoming=receiveFolderOnce(receiver,{
    type:'FOLDER_BEGIN',folder:'photos',count:1,bytes:1
  },{directory:root,approve:async()=>true,idleTimeoutMs:200});
  assert.equal((await sender.receive()).type,'FOLDER_READY');
  sender.send({type:'FOLDER_ENTRY',index:0,path:'oversized.txt'});
  sender.send({type:'FILE_OFFER',name:'oversized.txt',bytes:2,sha256:'0'.repeat(64)});
  await assert.rejects(incoming,/remaining byte budget/);
  assert.deepEqual(await fs.readdir(root),[]);
}));
test('receiver rejects file/directory collisions even when casing differs',()=>sandbox(async root=>{
  const [sender,receiver]=channels();
  const incoming=receiveFolderOnce(receiver,{
    type:'FOLDER_BEGIN',folder:'photos',count:1,bytes:1,directories:['Pictures','Pictures/Empty']
  },{directory:root,approve:async()=>true,idleTimeoutMs:200});
  assert.equal((await sender.receive()).type,'FOLDER_READY');
  sender.send({type:'FOLDER_ENTRY',index:0,path:'pictures'});
  await assert.rejects(incoming,/conflicts with a directory/);
  assert.deepEqual(await fs.readdir(root),[]); // no partial directories published
}));

test('transactional folder receive removes verified first file after later forged entry',()=>sandbox(async root=>{
  const source=path.join(root,'ok.txt');
  const dest=path.join(root,'dest');
  await fs.mkdir(dest);
  await fs.writeFile(source,'hello');
  const [sender,receiver]=channels();
  const incoming=receiveFolderOnce(receiver,{
    type:'FOLDER_BEGIN',folder:'safe',count:2,bytes:5
  },{directory:dest,approve:async()=>true,idleTimeoutMs:1000});
  assert.equal((await sender.receive()).type,'FOLDER_READY');
  sender.send({type:'FOLDER_ENTRY',index:0,path:'ok.txt'});
  await sendFileOnce(sender,source,{idleTimeoutMs:1000});
  sender.send({type:'FOLDER_ENTRY',index:1,path:'../forged.txt'});
  await assert.rejects(incoming,/Unsafe transferred filename|Unsafe relative file path/);
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('folder receive never overwrites existing folder of same name',()=>sandbox(async root=>{
  const src=path.join(root,'src'),dest=path.join(root,'dest');
  await fs.mkdir(src);await fs.mkdir(path.join(dest,'src'),{recursive:true});
  await fs.writeFile(path.join(src,'file.txt'),'new');
  await fs.writeFile(path.join(dest,'src','file.txt'),'original');
  const [sender,receiver]=channels();
  const incoming=(async()=>receiveFolderOnce(receiver,await receiver.receive(),{
    directory:dest,approve:async()=>true
  }))();
  await Promise.all([sendFolderOnce(sender,src),incoming]);
  assert.equal(await fs.readFile(path.join(dest,'src','file.txt'),'utf8'),'original');
  const names=await fs.readdir(dest);
  assert.equal(names.length,2);
  const published=names.find(name=>name.startsWith('src (received '));
  assert.ok(published);
  assert.equal(await fs.readFile(path.join(dest,published,'file.txt'),'utf8'),'new');
}));

// Crash-recovery gate: only explicitly marked, stale, private staging folders
// may be removed. Real received folders and unrelated data must be untouched.
test('startup recovery reclaims old interrupted folder batches only',()=>sandbox(async root=>{
  const now=Date.now();
  const old=now-STAGING_RECOVERY_MIN_AGE_MS-120000;
  async function stage(id,{createdAt=old,mark=true,age=old}={}) {
    const dir=path.join(root,'.liquidremote-batch-'+id);
    await fs.mkdir(path.join(dir,'payload'),{recursive:true});
    await fs.writeFile(path.join(dir,'payload','partial.bin'),'not yet verified');
    if (mark) {
      const marker=path.join(dir,'.liquidremote-batch-recovery.json');
      await fs.writeFile(marker,JSON.stringify({version:1,id,createdAt}));
      await fs.utimes(marker,new Date(age),new Date(age));
    }
    await fs.utimes(dir,new Date(age),new Date(age));
    return dir;
  }
  const orphan=await stage('orphanA1234');
  const active=await stage('activeB1234',{createdAt:now,age:now});
  const unmarked=await stage('unmarkedC1234',{mark:false});
  const forged=await stage('forgedD1234');
  await fs.writeFile(path.join(forged,'.liquidremote-batch-recovery.json'),
    JSON.stringify({version:1,id:'wrong-id',createdAt:old}));
  await fs.utimes(forged,new Date(old),new Date(old));
  const published=path.join(root,'photos (received existing)');
  await fs.mkdir(published);
  await fs.writeFile(path.join(published,'verified.txt'),'keep');
  const outside=path.join(root,'outside');
  await fs.mkdir(outside);
  await fs.writeFile(path.join(outside,'keep.txt'),'outside');
  const link=path.join(root,'.liquidremote-batch-linkE1234');
  await fs.symlink(outside,link,'dir');
  const result=await cleanupStaleFolderTransfers(root,{now});
  assert.equal(result.removed,1);
  assert.equal(result.inspected,5);
  assert.equal(result.skipped,4);
  await assert.rejects(fs.lstat(orphan),{code:'ENOENT'});
  for(const dir of [active,unmarked,forged,published,outside,link])
    assert.ok(await fs.lstat(dir));
  assert.equal(await fs.readFile(path.join(outside,'keep.txt'),'utf8'),'outside');
  assert.equal(await fs.readFile(path.join(published,'verified.txt'),'utf8'),'keep');
  assert.equal((await cleanupStaleFolderTransfers(root,{now})).removed,0);
}));
test('startup recovery refuses unsafe thresholds and oversized candidate scans',()=>sandbox(async root=>{
  const candidate=path.join(root,'.liquidremote-batch-notours123');
  await fs.mkdir(candidate);
  await assert.rejects(cleanupStaleFolderTransfers(root,{minAgeMs:0}),/Invalid folder recovery options/);
  await assert.rejects(cleanupStaleFolderTransfers(root,{maxCandidates:0}),/Invalid folder recovery options/);
  await fs.mkdir(path.join(root,'.liquidremote-batch-another123'));
  await assert.rejects(cleanupStaleFolderTransfers(root,{maxCandidates:1}),/scan limit/);
  assert.ok(await fs.lstat(candidate));
}));
