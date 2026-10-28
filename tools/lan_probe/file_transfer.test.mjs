import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import {safeTransferName,sendFileOnce,receiveFileOnce,MAX_FILE_BYTES} from './file_transfer.mjs';

function channels() {
  function endpoint() {
    const q=[];let waiting=null;const state={destroyed:false};
    return {
      push(v){if(waiting){const f=waiting;waiting=null;f(v);}else q.push(v);},
      receive(){return q.length?Promise.resolve(q.shift()):new Promise(resolve=>waiting=resolve);},
      lines:{socket:{destroy(){state.destroyed=true;}}},
      get destroyed(){return state.destroyed;}
    };
  }
  const a=endpoint(),b=endpoint();
  return [
    {send:v=>b.push(v),receive:()=>a.receive(),lines:a.lines,get destroyed(){return a.destroyed;}},
    {send:v=>a.push(v),receive:()=>b.receive(),lines:b.lines,get destroyed(){return b.destroyed;}}
  ];
}
async function sandbox(fn) {
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-file-test-'));
  try {return await fn(dir);} finally {await fs.rm(dir,{recursive:true,force:true});}
}
test('reject spoofed names, paths and reserved Windows filenames',()=>{
  for(const name of ['../secret','a\\b','CON.txt','COM¹.log','NUL','CONIN$.txt','CONOUT$.txt','CONIN$ .txt','CONOUT$ .txt','CON .txt','COM1 .log','report.','report ',
    'invoice\u202Egpj.exe','hidden\u2066name','line\u2028break','line\u2029break','bad\u0000name','x\uFFFD','x\uD800','']) {
    assert.throws(()=>safeTransferName(name),/Unsafe/);
  }
  assert.equal(safeTransferName('ملف 🫧.pdf'),'ملف 🫧.pdf');
  assert.equal(safeTransferName('family 👨‍👩‍👧‍👦.txt'),'family 👨‍👩‍👧‍👦.txt');
  assert.equal(safeTransferName('می\\u200cروم.txt'),'می\\u200cروم.txt');
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
test('receiver reserves case-folded and Unicode-normalized Windows destination names',()=>sandbox(async dir=>{
  const destination=path.join(dir,'dest');await fs.mkdir(destination);
  await fs.writeFile(path.join(destination,'café.txt'),'existing unicode');
  const sendOne=async(name,payload)=>{
    const source=path.join(dir,'source-'+crypto.randomUUID());
    await fs.writeFile(source,payload);
    const [sender,receiver]=channels();
    const receiving=(async()=>receiveFileOnce(receiver,await receiver.receive(),{
      directory:destination,approve:async()=>true}))();
    const sending=sendFileOnce(sender,source);
    const [saved]=await Promise.all([receiving,sending]);
    assert.deepEqual(await fs.readFile(saved.path),payload);
    return saved.path;
  };
  const payloadA=Buffer.from('upper'),payloadB=Buffer.from('lower');
  const [first,second]=await Promise.all([
    sendOne('Report.txt',payloadA),
    sendOne('report.txt',payloadB),
  ]);
  const canonical=name=>name.normalize('NFC').toUpperCase().normalize('NFC');
  assert.notEqual(canonical(path.basename(first)),canonical(path.basename(second)),
    'concurrent transfers must not create Windows case-insensitive aliases');
  assert.deepEqual(await fs.readFile(path.join(destination,'café.txt')),Buffer.from('existing unicode'));
  const normalizedAlias=await sendOne('cafe\u0301.txt',Buffer.from('normalized alias'));
  assert.notEqual(canonical(path.basename(normalizedAlias)),canonical('café.txt'),
    'NFC and NFD spellings must reserve the same portable filename');
  assert.equal((await fs.readdir(destination)).filter(name=>name.endsWith('.part')).length,0);
}));
test('invalid destination is rejected before prompting for file consent',()=>sandbox(async dir=>{
  const notDirectory=path.join(dir,'not-a-directory');
  await fs.writeFile(notDirectory,'plain file');
  const missing=path.join(dir,'missing-destination');
  const emptyHash=crypto.createHash('sha256').update(Buffer.alloc(0)).digest('hex');
  const offer={type:'FILE_OFFER',name:'safe.txt',bytes:0,sha256:emptyHash};
  let approvals=0;
  for(const destination of [missing,notDirectory]) {
    const [sender,receiver]=channels();
    await assert.rejects(receiveFileOnce(receiver,offer,{
      directory:destination,
      approve:async()=>{approvals++;return true;}
    }));
    assert.equal(approvals,0,'invalid destination must fail before asking the user');
    assert.equal(receiver.destroyed,true,'failed destination preflight must revoke the one-shot channel');
    assert.deepEqual((await fs.readdir(dir)).filter(name=>name.endsWith('.part')),[]);
    assert.equal(sender.destroyed,false,'destination preflight must not fabricate a peer response');
  }
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
  assert.equal(a.destroyed,true,'sender must revoke its one-shot channel after denial');
  assert.equal(b.destroyed,true,'explicit denial must revoke the one-shot receiver channel');
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('reject non-canonical base64 aliases before writing or acknowledging a chunk',()=>sandbox(async dir=>{
  const destination=path.join(dir,'dest');await fs.mkdir(destination);
  const payload=Buffer.from([1,2,3,4,5]);
  const alias='AQIDBAV=';
  assert.equal(payload.toString('base64'),'AQIDBAU=');
  assert.deepEqual(Buffer.from(alias,'base64'),payload,'the alias decodes to the same bytes');
  const offer={type:'FILE_OFFER',name:'canonical.bin',bytes:payload.length,
    sha256:crypto.createHash('sha256').update(payload).digest('hex')};
  const [sender,receiver]=channels();
  const receiving=receiveFileOnce(receiver,offer,{directory:destination,approve:async()=>true});
  assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
  sender.send({type:'FILE_CHUNK',seq:0,data:alias});
  await assert.rejects(receiving,/Invalid file chunk/);
  assert.equal(receiver.destroyed,true,'malformed framing must revoke the one-shot channel');
  assert.deepEqual(await fs.readdir(destination),[],'non-canonical bytes must never be staged or published');
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
  assert.equal(b.destroyed,true,'failed receive must revoke its one-shot channel');
  assert.deepEqual(await fs.readdir(dest),[]);
}));
test('invalid offer and oversized offer fail before consent and close the one-shot channel',()=>sandbox(async dir=>{
  let approvals=0;
  for(const offer of [{type:'FILE_OFFER',name:'../bad',bytes:1,sha256:'0'.repeat(64)},
    {type:'FILE_OFFER',name:'CONIN$ .txt',bytes:1,sha256:'0'.repeat(64)},
    {type:'FILE_OFFER',name:'CONOUT$.txt',bytes:1,sha256:'0'.repeat(64)},
    {type:'FILE_OFFER',name:'ok',bytes:MAX_FILE_BYTES+1,sha256:'0'.repeat(64)}]) {
    const [a,b]=channels();
    await assert.rejects(receiveFileOnce(b,offer,{directory:dir,approve:async()=>{approvals++;return true;}}));
    assert.equal(b.destroyed,true);
    assert.deepEqual(await a.receive(),{type:'FILE_DENIED'});
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
  // Destination preflight now performs asynchronous filesystem checks before consent.
  // Wait for the callback itself rather than assuming a single microtask is enough.
  await new Promise((resolve,reject)=>{
    const deadline=Date.now()+1_000;
    const poll=()=>{
      if(typeof release==='function') return resolve();
      if(Date.now()>=deadline) return reject(new Error('Consent callback was not reached'));
      setTimeout(poll,5);
    };
    poll();
  });
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
  assert.equal(sender.destroyed,true,'terminal sender failure must revoke its one-shot channel');
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


test('revocation during Windows hard-link publication removes final and staging files',()=>sandbox(async dir=>{
  const destination=path.join(dir,'received');await fs.mkdir(destination);
  const hash=crypto.createHash('sha256').update('').digest('hex');
  const offer={type:'FILE_OFFER',name:'revoked.txt',bytes:0,sha256:hash};
  const [sender,receiver]=channels(),controller=new AbortController();
  const outgoing=[];
  const channel={
    send:frame=>{outgoing.push(frame.type);receiver.send(frame);},
    receive:()=>receiver.receive()
  };
  const originalLink=fs.link;
  let enterLink,releaseLink;
  const linked=new Promise(resolve=>{enterLink=resolve;});
  const release=new Promise(resolve=>{releaseLink=resolve;});
  fs.link=async (...args)=>{
    await originalLink(...args);
    enterLink();
    await release;
  };
  try {
    const receiving=receiveFileOnce(channel,offer,{
      directory:destination,approve:async()=>true,signal:controller.signal
    });
    assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
    sender.send({type:'FILE_END',bytes:0,sha256:hash});
    await linked;
    controller.abort();
    releaseLink();
    await assert.rejects(receiving,{name:'AbortError'});
    assert.deepEqual(await fs.readdir(destination),[]);
    assert.deepEqual(outgoing,['FILE_READY']);
  } finally {
    releaseLink();
    fs.link=originalLink;
  }
}));

test('Windows receive rolls back newly linked file when staging cleanup fails',()=>sandbox(async dir=>{
  const destination=path.join(dir,'received');await fs.mkdir(destination);
  const hash=crypto.createHash('sha256').update('').digest('hex');
  const offer={type:'FILE_OFFER',name:'cleanup-failed.txt',bytes:0,sha256:hash};
  const [sender,receiver]=channels();
  const outgoing=[];
  const channel={
    send:frame=>{outgoing.push(frame.type);receiver.send(frame);},
    receive:()=>receiver.receive()
  };
  const originalUnlink=fs.unlink;
  let injected=false;
  fs.unlink=async file=>{
    if(!injected && String(file).endsWith('.part')) {
      injected=true;
      const error=new Error('Simulated staging unlink failure');
      error.code='EACCES';
      throw error;
    }
    return originalUnlink(file);
  };
  try {
    const receiving=receiveFileOnce(channel,offer,{directory:destination,approve:async()=>true});
    assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
    sender.send({type:'FILE_END',bytes:0,sha256:hash});
    await assert.rejects(receiving,/Simulated staging unlink failure/);
    assert.equal(injected,true);
    assert.deepEqual(await fs.readdir(destination),[]);
    assert.deepEqual(outgoing,['FILE_READY']);
  } finally {fs.unlink=originalUnlink;}
}));


test('failed Windows final-file rollback is reported instead of silently accepted',()=>sandbox(async dir=>{
  const destination=path.join(dir,'received');await fs.mkdir(destination);
  const hash=crypto.createHash('sha256').update('').digest('hex');
  const offer={type:'FILE_OFFER',name:'rollback-error.txt',bytes:0,sha256:hash};
  const [sender,receiver]=channels(),sent=[];
  const channel={send:frame=>{sent.push(frame.type);receiver.send(frame);},
    receive:()=>receiver.receive()};
  const originalUnlink=fs.unlink;
  let failStaging=true,failFinal=true;
  fs.unlink=async file=>{
    const name=String(file);
    if(failStaging && name.endsWith('.part')) {
      failStaging=false;
      throw Object.assign(new Error('Staging cleanup denied'),{code:'EACCES'});
    }
    if(failFinal && name.endsWith('rollback-error.txt')) {
      failFinal=false;
      throw Object.assign(new Error('Final rollback denied'),{code:'EACCES'});
    }
    return originalUnlink(file);
  };
  try {
    const receiving=receiveFileOnce(channel,offer,{directory:destination,approve:async()=>true});
    assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
    sender.send({type:'FILE_END',bytes:0,sha256:hash});
    await assert.rejects(receiving,error=>
      error instanceof AggregateError &&
      /rollback failed/.test(error.message) &&
      error.errors.length===2);
    assert.deepEqual(sent,['FILE_READY']);
    // The filesystem refused deletion. The error must explicitly surface
    // that a final file could remain; never claim cleanup succeeded.
    assert.deepEqual(await fs.readdir(destination),['rollback-error.txt']);
  } finally {fs.unlink=originalUnlink;}
}));

test('revoked file trust during consent prevents READY and leaves no file',()=>sandbox(async dir=>{
  const dest=path.join(dir,'dest');await fs.mkdir(dest);
  const hash=crypto.createHash('sha256').update('').digest('hex');
  const offer={type:'FILE_OFFER',name:'consent.txt',bytes:0,sha256:hash};
  const [sender,receiver]=channels();
  let trusted=true,approvals=0;
  const receiving=receiveFileOnce(receiver,offer,{
    directory:dest,isSessionActive:()=>trusted,
    approve:async()=>{approvals++;trusted=false;return true;}
  });
  await assert.rejects(receiving,{name:'AbortError'});
  assert.equal(approvals,1);
  assert.deepEqual(await fs.readdir(dest),[]);
}));

test('revoked file trust after chunk ACK rejects END and deletes staged bytes',()=>sandbox(async dir=>{
  const dest=path.join(dir,'dest');await fs.mkdir(dest);
  const data=Buffer.from('never publish after revoke');
  const hash=crypto.createHash('sha256').update(data).digest('hex');
  const offer={type:'FILE_OFFER',name:'revoke.bin',bytes:data.length,sha256:hash};
  const [sender,receiver]=channels();
  let trusted=true;const frames=[];
  const guarded={
    send:frame=>{frames.push(frame.type);receiver.send(frame);
      if(frame.type==='FILE_ACK')trusted=false;},
    receive:()=>receiver.receive()
  };
  const receiving=receiveFileOnce(guarded,offer,{
    directory:dest,approve:async()=>true,isSessionActive:()=>trusted
  });
  assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
  sender.send({type:'FILE_CHUNK',seq:0,data:data.toString('base64')});
  assert.deepEqual(await sender.receive(),{type:'FILE_ACK',seq:0});
  sender.send({type:'FILE_END',bytes:data.length,sha256:hash});
  await assert.rejects(receiving,{name:'AbortError'});
  assert.deepEqual(frames,['FILE_READY','FILE_ACK']);
  assert.deepEqual(await fs.readdir(dest),[]);
}));

test('trust revoke during Windows hard-link publication rolls back final file',()=>sandbox(async dir=>{
  const dest=path.join(dir,'dest');await fs.mkdir(dest);
  const hash=crypto.createHash('sha256').update('').digest('hex');
  const offer={type:'FILE_OFFER',name:'revoked-trust.txt',bytes:0,sha256:hash};
  const [sender,receiver]=channels();let trusted=true;
  const frames=[],channel={send:frame=>{frames.push(frame.type);receiver.send(frame);},
    receive:()=>receiver.receive()};
  const originalLink=fs.link;
  fs.link=async (...args)=>{await originalLink(...args);trusted=false;};
  try {
    const receiving=receiveFileOnce(channel,offer,{
      directory:dest,approve:async()=>true,isSessionActive:()=>trusted
    });
    assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
    sender.send({type:'FILE_END',bytes:0,sha256:hash});
    await assert.rejects(receiving,{name:'AbortError'});
    assert.deepEqual(frames,['FILE_READY']);
    assert.deepEqual(await fs.readdir(dest),[]);
  } finally {fs.link=originalLink;}
}));


test('trust revocation interrupts pending file consent without waiting for idle timeout',()=>sandbox(async dir=>{
  const [sender,receiver]=channels();
  let active=true, consentStarted;
  const started=new Promise(resolve=>{consentStarted=resolve;});
  const offer={type:'FILE_OFFER',name:'consent.txt',bytes:0,
    sha256:crypto.createHash('sha256').update('').digest('hex')};
  const pending=receiveFileOnce(receiver,offer,{directory:dir,idleTimeoutMs:5000,
    isSessionActive:()=>active,approve:async()=>{consentStarted();return new Promise(()=>{});}});
  await started;
  active=false;
  await assert.rejects(pending,{name:'AbortError',message:'File transfer cancelled'});
  assert.deepEqual(await fs.readdir(dir),[]);
}));

test('trust revocation interrupts idle file receiver and deletes staged bytes',()=>sandbox(async dir=>{
  const [sender,receiver]=channels();
  let active=true;
  const payload=Buffer.from('pending data');
  const offer={type:'FILE_OFFER',name:'pending.bin',bytes:payload.length,
    sha256:crypto.createHash('sha256').update(payload).digest('hex')};
  const pending=receiveFileOnce(receiver,offer,{directory:dir,idleTimeoutMs:5000,
    isSessionActive:()=>active,approve:async()=>true});
  assert.deepEqual(await sender.receive(),{type:'FILE_READY'});
  sender.send({type:'FILE_CHUNK',seq:0,data:payload.subarray(0,3).toString('base64')});
  assert.deepEqual(await sender.receive(),{type:'FILE_ACK',seq:0});
  active=false;
  await assert.rejects(pending,{name:'AbortError',message:'File transfer cancelled'});
  assert.deepEqual(await fs.readdir(dir),[]);
}));


// The destination must remain the same real directory from consent through commit.
// A local rename+symlink substitution during the approval dialog must fail closed.
test('receiver rejects destination replaced by a symlink during consent', {
  skip: process.platform === 'win32',
}, () => sandbox(async dir => {
  const destination=path.join(dir,'dest');
  const moved=path.join(dir,'dest-original');
  const outside=path.join(dir,'outside');
  await fs.mkdir(destination);
  await fs.mkdir(outside);
  const payload=Buffer.from('must not escape the selected destination');
  const offer={type:'FILE_OFFER',name:'safe.txt',bytes:payload.length,
    sha256:crypto.createHash('sha256').update(payload).digest('hex')};
  const [sender,receiver]=channels();
  await assert.rejects(receiveFileOnce(receiver,offer,{
    directory:destination,
    approve:async()=>{
      await fs.rename(destination,moved);
      await fs.symlink(outside,destination,'dir');
      return true;
    },
  }),/Receiver destination changed during transfer/);
  assert.equal(receiver.destroyed,true,'destination substitution must revoke the one-shot channel');
  assert.deepEqual(await fs.readdir(outside),[],'no private or final file may be written outside the chosen folder');
  assert.deepEqual(await fs.readdir(moved),[],'the originally selected directory must remain unchanged');
  assert.deepEqual((await fs.readdir(dir)).filter(name=>name.endsWith('.part')),[]);
  assert.equal(sender.destroyed,false,'preflight failure must not fabricate a peer response');
}));
