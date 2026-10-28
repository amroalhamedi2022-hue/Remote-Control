import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {h264Arguments,H264Assembler,sendH264,assertTransportStream,MAX_TS_BYTES} from './h264_transport.mjs';

const tsPacket = Buffer.concat([Buffer.from([0x47]), Buffer.alloc(187)]);
function mkReceiver(){
  const chunks=[];let result;
  const a=new H264Assembler({onChunk: b=>chunks.push(b),onComplete: r=>result=r});
  return {a,chunks,get result(){return result;}};
}

test('H264 args enforce allowlisted codec/capture profiles (no shell interpolation)',()=>{
  const args=h264Arguments({testPattern:true,seconds:2,width:640,fps:12});
  assert.ok(args.includes('libx264')); assert.ok(args.includes('pipe:1'));
  assert.ok(args.includes('testsrc2=size=1280x720:rate=12'));
  assert.throws(()=>h264Arguments({encoder:'evil; rm -rf /'}));
  assert.throws(()=>h264Arguments({seconds:100}));
  assert.throws(()=>h264Arguments({width:639}));
  assert.throws(()=>h264Arguments({fps:0}));
  const win=h264Arguments();assert.ok(win.includes('gdigrab'));
});

test('H.264 assembler reconstructs ordered MPEG-TS packets with SHA-256 and completion',()=>{
  const source=Buffer.concat([tsPacket,tsPacket,tsPacket]);
  assertTransportStream(source);
  const r=mkReceiver();r.a.ingest({type:'H264_BEGIN',codec:'h264',container:'mpegts',maxBytes:MAX_TS_BYTES});
  r.a.ingest({type:'H264_PART',offset:0,data:source.subarray(0,200).toString('base64url')});
  r.a.ingest({type:'H264_PART',offset:200,data:source.subarray(200).toString('base64url')});
  r.a.ingest({type:'H264_END',bytes:source.length,sha256:crypto.createHash('sha256').update(source).digest('hex')});
  assert.equal(r.a.complete,true);
  assert.deepEqual(Buffer.concat(r.chunks),source);
  assert.equal(r.result.bytes,source.length);
});

test('H264 receiver fails closed on offsets, corrupted TS, and unauthorized messages',()=>{
  const r=mkReceiver();
  assert.throws(()=>r.a.ingest({type:'H264_PART',offset:0,data:'AA'}));
  r.a.ingest({type:'H264_BEGIN',codec:'h264',container:'mpegts',maxBytes:MAX_TS_BYTES});
  assert.throws(()=>r.a.ingest({type:'INPUT_MOUSE',x:1,y:2}));
  assert.throws(()=>r.a.ingest({type:'H264_PART',offset:12,data:tsPacket.toString('base64url')}));
  assert.throws(()=>r.a.ingest({type:'H264_PART',offset:0,data:Buffer.alloc(188).toString('base64url')}));
  assert.throws(()=>assertTransportStream(Buffer.concat([tsPacket,Buffer.alloc(1)])));
});

test('H264 receiver rejects wrong digest, missing packets, duplicate chunks',()=>{
  const r=mkReceiver();r.a.ingest({type:'H264_BEGIN',codec:'h264',container:'mpegts',maxBytes:MAX_TS_BYTES});
  r.a.ingest({type:'H264_PART',offset:0,data:tsPacket.toString('base64url')});
  assert.throws(()=>r.a.ingest({type:'H264_PART',offset:0,data:tsPacket.toString('base64url')}));
  assert.throws(()=>r.a.ingest({type:'H264_END',bytes:188,sha256:'0'.repeat(64)}));
  assert.throws(()=>r.a.ingest({type:'H264_END',bytes:187,sha256:crypto.createHash('sha256').update(tsPacket).digest('hex')}));
});

test('H.264 stream stops when peer trust is revoked after a sent chunk', {timeout:25000}, async t => {
  if(spawnSync('ffmpeg',['-version'],{stdio:'ignore'}).status!==0){t.skip('FFmpeg not installed');return;}
  let trusted=true;
  const messages=[];
  const channel={send:msg=>{
    messages.push(msg);
    if(msg.type==='H264_PART') trusted=false;
  }};
  await assert.rejects(
    sendH264(channel,{destroyed:false,writableLength:0},{
      testPattern:true,seconds:2,width:320,fps:6,bitrateKbps:300,
      isSessionActive:()=>trusted
    }),
    /trust revoked/
  );
  assert.ok(messages.some(m=>m.type==='H264_PART'));
  assert.ok(!messages.some(m=>m.type==='H264_END'));
});
test('Revoked peer cannot start H.264 capture',async()=>{
  await assert.rejects(sendH264({send:()=>{throw Error('unexpected send');}},
    {destroyed:false,writableLength:0},{isSessionActive:()=>false}),
    /trust revoked before capture/);
});


test('Revoking trust while FFmpeg is silent terminates H.264 capture', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX executable fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-idle-h264-'));
  try {
    const fake=path.join(dir,'ffmpeg-stall');
    await fs.writeFile(fake, `#!/bin/sh\nexec "${process.execPath}" -e 'setTimeout(() => {}, 10000)'\n`);
    await fs.chmod(fake,0o755);
    let checks=0;
    const messages=[];
    const started=Date.now();
    await assert.rejects(sendH264({send:message=>messages.push(message)},
      {destroyed:false,writableLength:0},{ffmpeg:fake,isSessionActive:()=>++checks===1}),
      /trust revoked/);
    assert.ok(Date.now()-started<3000,'revoked idle capture should terminate promptly');
    assert.ok(messages.some(message=>message.type==='H264_BEGIN'));
    assert.ok(!messages.some(message=>message.type==='H264_PART'||message.type==='H264_END'));
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});


test('Revoked silent H.264 child is force-terminated if it ignores SIGTERM', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX signal-handler fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-hardkill-h264-'));
  try {
    const fake=path.join(dir,'ffmpeg-ignore-term');
    await fs.writeFile(fake, `#!/bin/sh\nexec "${process.execPath}" -e 'process.on("SIGTERM", () => {}); setTimeout(() => {}, 10000)'\n`);
    await fs.chmod(fake,0o755);
    let checks=0;
    const messages=[];
    const started=Date.now();
    await assert.rejects(sendH264({send:message=>messages.push(message)},
      {destroyed:false,writableLength:0},{ffmpeg:fake,isSessionActive:()=>++checks===1}),
      /trust revoked/);
    assert.ok(Date.now()-started<3000,'revoked child that ignores SIGTERM must be force-terminated');
    assert.ok(!messages.some(message=>message.type==='H264_PART'||message.type==='H264_END'));
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('Viewer disconnect while H.264 capture is silent terminates the child', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX silent-process fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-disconnect-h264-'));
  try {
    const fake=path.join(dir,'ffmpeg-silent');
    await fs.writeFile(fake, `#!/bin/sh\nexec "${process.execPath}" -e 'setTimeout(() => {}, 10000)'\n`);
    await fs.chmod(fake,0o755);
    const socket={destroyed:false,writableLength:0};
    const messages=[];
    const started=Date.now();
    const pending=sendH264({send:message=>messages.push(message)},socket,
      {ffmpeg:fake,isSessionActive:()=>true});
    await new Promise(resolve=>setTimeout(resolve,150));
    socket.destroyed=true;
    await assert.rejects(pending,/Viewer disconnected/);
    assert.ok(Date.now()-started<3000,'silent capture should stop promptly after viewer disconnect');
    assert.ok(messages.some(message=>message.type==='H264_BEGIN'));
    assert.ok(!messages.some(message=>message.type==='H264_PART'||message.type==='H264_END'));
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});
