import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import crypto from 'node:crypto';
import {pairSocket, generateIdentity, identityFingerprint} from './secure_pairing.mjs';

async function fixture(clientOpts={},serverOpts={}) {
  const clientIdentity=clientOpts.identity??generateIdentity();
  const serverIdentity=serverOpts.identity??generateIdentity();
  const clientTrust=clientOpts.trust??new Map();
  const serverTrust=serverOpts.trust??new Map();
  let serverSide;
  const listener=net.createServer(socket=>{
    serverSide=pairSocket(socket,{role:'server',identity:serverIdentity,trustStore:serverTrust,
      onCode:serverOpts.approve??(async()=>true),debugHooks:serverOpts.debugHooks,
      consentTimeoutMs:serverOpts.consentTimeoutMs});
    serverSide.catch(()=>{});
  });
  await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));
  const port=listener.address().port;
  const clientSocket=net.createConnection({port,host:'127.0.0.1'});
  const clientSide=pairSocket(clientSocket,{role:'client',identity:clientIdentity,trustStore:clientTrust,
    onCode:clientOpts.approve??(async()=>true),debugHooks:clientOpts.debugHooks,
    consentTimeoutMs:clientOpts.consentTimeoutMs,intent:clientOpts.intent});
  clientSide.catch(()=>{});
  while(!serverSide)await new Promise(resolve=>setImmediate(resolve));
  return {clientSide,serverSide,clientSocket,listener,clientTrust,serverTrust,
    close:()=>new Promise(resolve=>listener.close(()=>resolve()))};
}

test('mutual consent, matching SAS, pinned key identity and authenticated encryption',async t=>{
  let leftCode,rightCode;
  const f=await fixture({approve:async d=>{leftCode=d.sas;return true;}},
    {approve:async d=>{rightCode=d.sas;return true;}});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  assert.match(leftCode,/^\d{6}$/);assert.equal(leftCode,rightCode);
  assert.equal(client.fingerprint,identityFingerprint([...f.clientTrust.values()][0]));
  assert.equal(f.clientTrust.size,1);assert.equal(f.serverTrust.size,1);
  client.channel.send({type:'PING',value:'local only'});
  assert.deepEqual(await server.channel.receive(),{type:'PING',value:'local only'});
  server.channel.send({type:'PONG'});
  assert.deepEqual(await client.channel.receive(),{type:'PONG'});
});

test('a user rejection prevents trust creation and an encrypted session',async t=>{
  const f=await fixture({approve:async()=>false},{approve:async()=>true});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const out=await Promise.allSettled([f.clientSide,f.serverSide]);
  assert.ok(out.every(r=>r.status==='rejected'));
  assert.equal(f.clientTrust.size,0);assert.equal(f.serverTrust.size,0);
});

test('stalled local consent times out without trusting or opening a channel',async t=>{
  const f=await fixture({approve:()=>new Promise(()=>{}),consentTimeoutMs:40},
    {approve:async()=>true});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  await assert.rejects(f.clientSide,/Pairing consent timed out/);
  await assert.rejects(f.serverSide);
  assert.equal(f.clientTrust.size,0);
  assert.equal(f.serverTrust.size,0);
  assert.equal(f.clientSocket.destroyed,true);
});

test('tampered server identity signature is rejected before trust',async t=>{
  const f=await fixture({}, {debugHooks:{mutateReply:r=>({...r,nonce:crypto.randomBytes(24).toString('base64url')})}});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const rejection=await assert.rejects(f.clientSide,/Invalid identity signature/);
  assert.equal(f.clientTrust.size,0);
  // Server eventually fails when client terminates the connection.
  await assert.rejects(f.serverSide);
});

test('ciphertext manipulation fails authentication',async t=>{
  const f=await fixture();
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  const rawWrite=f.clientSocket.write.bind(f.clientSocket);
  let changed=false;
  f.clientSocket.write=function(chunk,...args){
    if(!changed && typeof chunk==='string' && chunk.includes('SEALED')){
      const frame=JSON.parse(chunk);
      frame.data=(frame.data[0]==='A'?'B':'A')+frame.data.slice(1);
      changed=true;
      return rawWrite(JSON.stringify(frame)+'\n',...args);
    }
    return rawWrite(chunk,...args);
  };
  client.channel.send({type:'PING'});
  await assert.rejects(server.channel.receive(),/Unauthenticated ciphertext/);
  assert.equal(changed,true);
  // Authentication failure must poison the session and close the socket:
  // a caller must never resume after catching an invalid frame.
  assert.throws(()=>server.channel.send({type:'PONG'}),/Encrypted session closed/);
  await assert.rejects(server.channel.receive(),/Encrypted session closed/);
});

test('replayed encrypted frame rejected by sequence counter',async t=>{
  const f=await fixture();
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  const rawWrite=f.clientSocket.write.bind(f.clientSocket);
  let captured;
  f.clientSocket.write=function(chunk,...args){
    if(typeof chunk==='string' && chunk.includes('SEALED'))captured=chunk;
    return rawWrite(chunk,...args);
  };
  client.channel.send({type:'PING'});
  assert.equal((await server.channel.receive()).type,'PING');
  assert.ok(captured);
  rawWrite(captured);
  await assert.rejects(server.channel.receive(),/Unexpected or replayed/);
  assert.throws(()=>server.channel.send({type:'PONG'}),/Encrypted session closed/);
  await assert.rejects(server.channel.receive(),/Encrypted session closed/);
});

test('trusted identity is recognized on later sessions with the same key',async t=>{
  const a=generateIdentity(),b=generateIdentity();
  const ca=new Map(),cb=new Map();
  const first=await fixture({identity:a,trust:ca},{identity:b,trust:cb});
  await Promise.all([first.clientSide,first.serverSide]);
  first.clientSocket.destroy();first.listener.close();
  let rememberedA,rememberedB;
  const second=await fixture({identity:a,trust:ca,approve:async d=>{rememberedA=d.known;return true;}},
    {identity:b,trust:cb,approve:async d=>{rememberedB=d.known;return true;}});
  t.after(()=>{second.clientSocket.destroy();second.listener.close();});
  const paired=await Promise.all([second.clientSide,second.serverSide]);
  assert.equal(rememberedA,true);assert.equal(rememberedB,true);
  assert.equal(paired[0].known,true);assert.equal(paired[1].known,true);
});

test('concurrent encrypted receives fail closed instead of orphaning a pending waiter',async t=>{
  const f=await fixture();
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [,server]=await Promise.all([f.clientSide,f.serverSide]);
  const pending=server.channel.receive();
  // The second reader must not replace the first JsonLines waiter.
  await assert.rejects(server.channel.receive(),/Concurrent frame reads/);
  await assert.rejects(pending);
  assert.throws(()=>server.channel.send({type:'PING'}),/Encrypted session closed/);
});

test('concurrent reads of already-buffered sealed frames also fail closed',async t=>{
  const f=await fixture();
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  // Both encrypted messages are queued before the server starts receiving.
  // JsonLines' single-waiter guard alone cannot protect this path.
  client.channel.send({type:'FIRST'});
  client.channel.send({type:'SECOND'});
  await new Promise(resolve=>setTimeout(resolve,30));
  const outcomes=await Promise.allSettled([server.channel.receive(),server.channel.receive()]);
  assert.equal(outcomes[0].status,'rejected');
  assert.equal(outcomes[1].status,'rejected');
  assert.match(outcomes[1].reason.message,/Concurrent frame reads/);
  assert.throws(()=>server.channel.send({type:'AFTER'}),/Encrypted session closed/);
  await assert.rejects(server.channel.receive(),/Encrypted session closed/);
});

test('non-object encrypted outbound payload poisons the session before transmission',async t=>{
  const f=await fixture();
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  assert.throws(()=>client.channel.send(['not','a','message']),/Encrypted payload must be an object/);
  assert.throws(()=>client.channel.send({type:'PING'}),/Encrypted session closed/);
  await assert.rejects(server.channel.receive());
});

test('one-shot clipboard intent is authenticated and visible only to receiver', async t => {
  const f=await fixture({intent:'clipboard'});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  assert.equal(server.peerIntent,'clipboard');
  assert.equal(client.peerIntent,null);
  client.channel.send({type:'CLIPBOARD_PUT',text:'مرحبا 🫧'});
  assert.deepEqual(await server.channel.receive(),{type:'CLIPBOARD_PUT',text:'مرحبا 🫧'});
  server.channel.send({type:'CLIPBOARD_OK',bytes:Buffer.byteLength('مرحبا 🫧')});
  assert.equal((await client.channel.receive()).type,'CLIPBOARD_OK');
});

test('file-transfer intent is signed, bound to the peer and not a generic control grant', async t => {
  const f=await fixture({intent:'file'});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [client,server]=await Promise.all([f.clientSide,f.serverSide]);
  assert.equal(server.peerIntent,'file');
  assert.equal(client.peerIntent,null);
  client.channel.send({type:'FILE_OFFER',name:'ملف.txt',bytes:0,sha256:'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'});
  assert.equal((await server.channel.receive()).type,'FILE_OFFER');
});

test('tampering with signed file intent prevents trust creation',async t=>{
  const f=await fixture({intent:'file',debugHooks:{mutateHello:h=>({...h,intent:'clipboard'})}});
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  await assert.rejects(f.serverSide,/Invalid identity signature/);
  await assert.rejects(f.clientSide);
  assert.equal(f.clientTrust.size,0);
  assert.equal(f.serverTrust.size,0);
});

test('ordinary pairing does not request clipboard privileges', async t => {
  const f=await fixture();
  t.after(()=>{f.clientSocket.destroy();f.listener.close();});
  const [,server]=await Promise.all([f.clientSide,f.serverSide]);
  assert.equal(server.peerIntent,null);
});

test('unsupported client intent is rejected before a network connection', async () => {
  const socket=new net.Socket();
  await assert.rejects(pairSocket(socket,{role:'client',identity:generateIdentity(),
    onCode:async()=>true,intent:'remote-input'}),/Unsupported client session intent/);
});
