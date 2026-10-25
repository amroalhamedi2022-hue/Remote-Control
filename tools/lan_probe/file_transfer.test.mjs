import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import {safeTransferName,sendFileOnce,receiveFileOnce,MAX_FILE_BYTES} from './file_transfer.mjs';

function channels() {
  function endpoint() {
    const q=[];let waiting=null;
    return {
      push(v){if(waiting){const f=waiting;waiting=null;f(v);}else q.push(v);},
      receive(){return q.length?Promise.resolve(q.shift()):new Promise(resolve=>waiting=resolve);}
    };
  }
  const a=endpoint(),b=endpoint();
  return [
    {send:v=>b.push(v),receive:()=>a.receive()},
    {send:v=>a.push(v),receive:()=>b.receive()}
  ];
}
async function sandbox(fn) {
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-file-test-'));
  try {return await fn(dir);} finally {await fs.rm(dir,{recursive:true,force:true});}
}
test('reject spoofed names, paths and reserved Windows filenames',()=>{
  for(const name of ['../secret','a\\b','CON.txt','COM¹.log','NUL','report.','report ',
    'invoice\u202Egpj.exe','hidden\u2066name','line\u2028break','line\u2029break','bad\u0000name','x\uFFFD','x\uD800','']) {
    assert.throws(()=>safeTransferName(name),/Unsafe/);
  }
  assert.equal(safeTransferName('ملف 🫧.pdf'),'ملف 🫧.pdf');
});
test('transfer encrypted-channel payload in bounded chunks with exact hash and no overwrite',()=>sandbox(async dir=>{
  const input=path.join(dir,'ملف 🫧.bin');
  const data=crypto.randomBytes(160_007);
  await fs.writeFile(input,data);
  const target=path.join(dir,'received');await fs.mkdir(target);
  await fs.writeFile(path.join(target,'ملف 🫧.bin'),Buffer.from('existing'));
  const [sender,receiver]=channels();
  const recv=(async()=>receiveFileOnce(receiver,await receiver.receive(),{
    directory:target,approve:async()=>true}))();
  const sent=await sendFileOnce(sender,input),saved=await recv;
  assert.equal(sent.bytes,data.length);
  assert.equal(saved.bytes,data.length);
  assert.equal(saved.sha256,crypto.createHash('sha256').update(data).digest('hex'));
  assert.equal(path.basename(saved.path),'ملف 🫧 (2).bin');
  assert.deepEqual(await fs.readFile(saved.path),data);
  assert.equal((await fs.readFile(path.join(target,'ملف 🫧.bin'))).toString(),'existing');
  assert.deepEqual((await fs.readdir(target)).filter(x=>x.endsWith('.part')),[]);
}));
test('empty file is valid and is never silently omitted',()=>sandbox(async dir=>{
  const source=path.join(dir,'empty.txt');await fs.writeFile(source,'');
  const dest=path.join(dir,'dest');await fs.mkdir(dest);
  const [a,b]=channels();
  const receiver=(async()=>receiveFileOnce(b,await b.receive(),{directory:dest,approve:async()=>true}))();
  const sent=sendFileOnce(a,source);
  const [received,result]=await Promise.all([receiver,sent]);
  assert.equal(result.bytes,0);assert.equal(received.bytes,0);
  assert.deepEqual(await fs.readFile(received.path),Buffer.alloc(0));
}));
test('denied offer writes no temporary or final files',()=>sandbox(async dir=>{
  const source=path.join(dir,'hello.txt');await fs.writeFile(source,'private');
  const dest=path.join(dir,'dest');await fs.mkdir(dest);
  const [a,b]=channels();
  const recv=(async()=>receiveFileOnce(b,await b.receive(),{directory:dest,approve:async()=>false}))();
  await assert.rejects(sendFileOnce(a,source),/denied/);
  assert.equal(await recv,null);
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('corrupt payload is rejected and partial file is deleted',()=>sandbox(async dir=>{
  const [a,b]=channels(),dest=path.join(dir,'dest');await fs.mkdir(dest);
  const offer={type:'FILE_OFFER',name:'safe.bin',bytes:3,sha256:'0'.repeat(64)};
  const recv=receiveFileOnce(b,offer,{directory:dest,approve:async()=>true});
  assert.deepEqual(await a.receive(),{type:'FILE_READY'});
  a.send({type:'FILE_CHUNK',seq:0,data:Buffer.from('abc').toString('base64')});
  assert.deepEqual(await a.receive(),{type:'FILE_ACK',seq:0});
  a.send({type:'FILE_END',bytes:3,sha256:'0'.repeat(64)});
  await assert.rejects(recv,/SHA-256 mismatch/);
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('invalid offer and oversized offer fail before consent',()=>sandbox(async dir=>{
  let approvals=0;
  const [a,b]=channels();
  for(const offer of [{type:'FILE_OFFER',name:'../bad',bytes:1,sha256:'0'.repeat(64)},
    {type:'FILE_OFFER',name:'ok',bytes:MAX_FILE_BYTES+1,sha256:'0'.repeat(64)}]) {
    await assert.rejects(receiveFileOnce(b,offer,{directory:dir,approve:async()=>{approvals++;return true;}}));
  }
  assert.equal(approvals,0);
}));

test('transfer progress is monotonic, bounded and verified only after hash acknowledgement',()=>sandbox(async dir=>{
  const source=path.join(dir,'progress.bin'),dest=path.join(dir,'dest');
  const payload=crypto.randomBytes(15_001);
  await fs.writeFile(source,payload);await fs.mkdir(dest);
  const [a,b]=channels(),sent=[],received=[];
  const receiving=(async()=>receiveFileOnce(b,await b.receive(),{
    directory:dest,approve:async()=>true,onProgress:p=>received.push(p)}))();
  const sending=sendFileOnce(a,source,{onProgress:p=>sent.push(p)});
  await Promise.all([sending,receiving]);
  for(const progress of [sent,received]) {
    assert.ok(progress.length>=2);
    let previous=0;
    for(const event of progress) {
      assert.equal(event.total,payload.length);
      assert.ok(event.bytes>=previous && event.bytes<=event.total);
      previous=event.bytes;
    }
    assert.equal(progress.filter(p=>p.verified).length,1);
    assert.equal(progress.at(-1).bytes,payload.length);
    assert.equal(progress.at(-1).verified,true);
    assert.ok(progress.slice(0,-1).every(p=>p.verified===false));
  }
}));
test('zero-length transfer emits a verified zero-byte completion event',()=>sandbox(async dir=>{
  const source=path.join(dir,'zero'),dest=path.join(dir,'dest');
  await fs.writeFile(source,'');await fs.mkdir(dest);
  const [a,b]=channels(),sent=[],received=[];
  const recv=(async()=>receiveFileOnce(b,await b.receive(),{
    directory:dest,approve:async()=>true,onProgress:p=>received.push(p)}))();
  await Promise.all([sendFileOnce(a,source,{onProgress:p=>sent.push(p)}),recv]);
  assert.deepEqual(sent,[{bytes:0,total:0,verified:true}]);
  assert.deepEqual(received,[{bytes:0,total:0,verified:true}]);
}));


test('sender cancellation interrupts a pending file approval without reporting success',()=>sandbox(async dir=>{
  const input=path.join(dir,'cancel-send.bin');
  await fs.writeFile(input,crypto.randomBytes(4096));
  const [sender,receiver]=channels(),controller=new AbortController();
  const sending=sendFileOnce(sender,input,{signal:controller.signal});
  const offer=await receiver.receive();
  assert.equal(offer.type,'FILE_OFFER');
  controller.abort();
  await assert.rejects(sending,{name:'AbortError',message:'File transfer cancelled'});
}));

test('receiver cancellation discards partial file while waiting for next chunk',()=>sandbox(async dir=>{
  const dest=path.join(dir,'received');await fs.mkdir(dest);
  const [sender,receiver]=channels(),controller=new AbortController();
  const bytes=Buffer.from('partial payload');
  const offer={type:'FILE_OFFER',name:'partial.txt',bytes:bytes.length,
    sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
  const receiving=receiveFileOnce(receiver,offer,{directory:dest,approve:async()=>true,
    signal:controller.signal});
  assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
  sender.send({type:'FILE_CHUNK',seq:0,data:bytes.subarray(0,3).toString('base64')});
  assert.deepEqual(await sender.receive(),{type:'FILE_ACK',seq:0});
  controller.abort();
  await assert.rejects(receiving,{name:'AbortError',message:'File transfer cancelled'});
  assert.deepEqual(await fs.readdir(dest),[]);
}));

test('pre-cancelled receiver never asks for consent or writes a file',()=>sandbox(async dir=>{
  const controller=new AbortController();controller.abort();
  let asked=0;
  await assert.rejects(receiveFileOnce(channels()[1],{
    type:'FILE_OFFER',name:'ok.txt',bytes:0,sha256:crypto.createHash('sha256').update('').digest('hex')
  },{directory:dir,approve:async()=>{asked++;return true;},signal:controller.signal}),{
    name:'AbortError',message:'File transfer cancelled'
  });
  assert.equal(asked,0);
  assert.deepEqual(await fs.readdir(dir),[]);
}));


test('sender times out when peer never approves the encrypted file offer',()=>sandbox(async dir=>{
  const source=path.join(dir,'idle-send.txt');await fs.writeFile(source,'test');
  const [sender,receiver]=channels();
  const pending=sendFileOnce(sender,source,{idleTimeoutMs:25});
  assert.equal((await receiver.receive()).type,'FILE_OFFER');
  await assert.rejects(pending,{name:'TimeoutError',message:'File transfer timed out waiting for peer'});
}));

test('receiver times out on a stalled sender and removes the partial file',()=>sandbox(async dir=>{
  const destination=path.join(dir,'received');await fs.mkdir(destination);
  const payload=Buffer.from('abcde');
  const offer={type:'FILE_OFFER',name:'idle.txt',bytes:payload.length,
    sha256:crypto.createHash('sha256').update(payload).digest('hex')};
  const [sender,receiver]=channels();
  const pending=receiveFileOnce(receiver,offer,{
    directory:destination,approve:async()=>true,idleTimeoutMs:25
  });
  assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
  sender.send({type:'FILE_CHUNK',seq:0,data:payload.subarray(0,2).toString('base64')});
  assert.deepEqual(await sender.receive(),{type:'FILE_ACK',seq:0});
  await assert.rejects(pending,{name:'TimeoutError',message:'File transfer timed out waiting for peer'});
  assert.deepEqual(await fs.readdir(destination),[]);
}));

test('reject invalid idle timeout before sending or requesting consent',async()=>{
  const [sender,receiver]=channels();
  await assert.rejects(sendFileOnce(sender,'unused',{idleTimeoutMs:0}),/Invalid file transfer idle timeout/);
  await assert.rejects(receiveFileOnce(receiver,{type:'FILE_OFFER'},{
    directory:'unused',approve:async()=>true,idleTimeoutMs:120001
  }),/Invalid file transfer idle timeout/);
});

test('receiver consent dialog is bounded by idle timeout before creating files',()=>sandbox(async dir=>{
  const offer={type:'FILE_OFFER',name:'consent.txt',bytes:0,
    sha256:crypto.createHash('sha256').update('').digest('hex')};
  const [sender,receiver]=channels();
  const waiting=receiveFileOnce(receiver,offer,{directory:dir,
    approve:()=>new Promise(()=>{}),idleTimeoutMs:25});
  await assert.rejects(waiting,{name:'TimeoutError',message:'File transfer timed out waiting for peer'});
  assert.deepEqual(await fs.readdir(dir),[]);
}));

test('cancelling pending receiver consent does not create or acknowledge a file',()=>sandbox(async dir=>{
  const offer={type:'FILE_OFFER',name:'consent.txt',bytes:0,
    sha256:crypto.createHash('sha256').update('').digest('hex')};
  const [sender,receiver]=channels(),controller=new AbortController();
  let release;
  const waiting=receiveFileOnce(receiver,offer,{directory:dir,signal:controller.signal,
    approve:()=>new Promise(resolve=>{release=resolve;})});
  // Await the microtask that enters the consent callback.
  await new Promise(resolve=>setImmediate(resolve));
  controller.abort();
  await assert.rejects(waiting,{name:'AbortError',message:'File transfer cancelled'});
  release(true); // Late UI approval must not resurrect the cancelled transfer.
  await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(await fs.readdir(dir),[]);
}));


test('signed sender FILE_CANCEL promptly deletes partial receiver staging',()=>sandbox(async dir=>{
  const destination=path.join(dir,'received');await fs.mkdir(destination);
  const payload=Buffer.from('cancelled payload');
  const offer={type:'FILE_OFFER',name:'cancelled.txt',bytes:payload.length,
    sha256:crypto.createHash('sha256').update(payload).digest('hex')};
  const [sender,receiver]=channels();
  const receiving=receiveFileOnce(receiver,offer,{
    directory:destination,approve:async()=>true,idleTimeoutMs:1000
  });
  assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
  sender.send({type:'FILE_CHUNK',seq:0,data:payload.subarray(0,4).toString('base64')});
  assert.deepEqual(await sender.receive(),{type:'FILE_ACK',seq:0});
  sender.send({type:'FILE_CANCEL'});
  await assert.rejects(receiving,{name:'AbortError',message:'File transfer cancelled'});
  assert.deepEqual(await fs.readdir(destination),[]);
}));


test('Node sender sends FILE_CANCEL on local failure after FILE_READY; receiver removes partial bytes',()=>sandbox(async dir=>{
  const source=path.join(dir,'cancel-midstream.bin'),dest=path.join(dir,'dest');
  await fs.writeFile(source,crypto.randomBytes(9000));await fs.mkdir(dest);
  const [sender,receiver]=channels();
  const receiving=(async()=>receiveFileOnce(receiver,await receiver.receive(),{
    directory:dest,approve:async()=>true,idleTimeoutMs:1000
  }))();
  const sending=sendFileOnce(sender,source,{
    onProgress:()=>{throw new Error('Local sender stopped after first ACK');}
  });
  await assert.rejects(sending,/Local sender stopped after first ACK/);
  await assert.rejects(receiving,{name:'AbortError',message:'File transfer cancelled'});
  assert.deepEqual(await fs.readdir(dest),[]);
}));

test('Node sender rejects bad FILE_ACK and cancels without sending FILE_END',()=>sandbox(async dir=>{
  const source=path.join(dir,'bad-ack.bin');await fs.writeFile(source,Buffer.from('payload'));
  const [sender,receiver]=channels();
  const sending=sendFileOnce(sender,source,{idleTimeoutMs:1000});
  assert.equal((await receiver.receive()).type,'FILE_OFFER');
  receiver.send({type:'FILE_READY'});
  assert.equal((await receiver.receive()).type,'FILE_CHUNK');
  receiver.send({type:'FILE_ACK',seq:999});
  await assert.rejects(sending,/Invalid file chunk acknowledgement/);
  assert.deepEqual(await receiver.receive(),{type:'FILE_CANCEL'});
}));

test('Node sender never cancels after FILE_END when final ACK is invalid',()=>sandbox(async dir=>{
  const source=path.join(dir,'after-end.bin'),dest=path.join(dir,'dest');
  await fs.writeFile(source,Buffer.from('verified but ACK corrupted'));await fs.mkdir(dest);
  const [originalSender,receiver]=channels(),types=[];
  const sender={
    send:(frame)=>{types.push(frame.type);originalSender.send(frame);},
    receive:async()=>{
      const frame=await originalSender.receive();
      return frame.type==='FILE_OK'?{...frame,sha256:'0'.repeat(64)}:frame;
    }
  };
  const receiving=(async()=>receiveFileOnce(receiver,await receiver.receive(),{
    directory:dest,approve:async()=>true
  }))();
  await assert.rejects(sendFileOnce(sender,source),/Invalid file completion acknowledgement/);
  const saved=await receiving;
  assert.equal(saved.bytes,(await fs.readFile(source)).length);
  assert.equal(types.at(-1),'FILE_END');
  assert.equal(types.includes('FILE_CANCEL'),false);
}));
