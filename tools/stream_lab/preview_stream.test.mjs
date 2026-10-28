import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {JpegFrames, jpegMessages, PreviewAssembler, sendPreview, captureArguments} from './preview_stream.mjs';
const mini = Buffer.from([0xff,0xd8,0x31,0x42,0xff,0xd9]);
test('fragmented JPEG stream and two concatenated frames',()=>{
  const frames=[];const parser=new JpegFrames((f)=>frames.push(f));
  const combined=Buffer.concat([Buffer.from([1,2]),mini,mini]);
  parser.push(combined.subarray(0,3));parser.push(combined.subarray(3,8));parser.push(combined.subarray(8));
  assert.equal(frames.length,2);assert.ok(frames[0].equals(mini));
});
test('chunks reconstruct exact JPEG, reject replay & offsets',()=>{
  const got=[];const asm=new PreviewAssembler((f)=>got.push(f));
  for(const m of jpegMessages(mini,5))asm.ingest(m);
  assert.ok(got[0].equals(mini));
  assert.throws(()=>asm.ingest({type:'FRAME_BEGIN',id:5,bytes:8}),/Bad frame header/);
  asm.ingest({type:'FRAME_BEGIN',id:6,bytes:mini.length});
  assert.throws(()=>asm.ingest({type:'FRAME_PART',id:6,offset:1,data:'AA'}),/Bad frame part/);
  assert.throws(()=>asm.ingest({type:'FRAME_END',id:6}),/Incomplete frame/);
});
test('reject malformed capture profiles, oversized JPEG',()=>{
  assert.throws(()=>captureArguments({fps:100}),/Bad fps/);
  assert.throws(()=>captureArguments({width:701}),/Bad width/);
  assert.throws(()=>jpegMessages(Buffer.alloc(512*1024+1),0),/Invalid JPEG/);
});
test('FFmpeg test pattern produces actual encrypted-ready frames (local-only)',{timeout:25000},async t=>{
  if(spawnSync('ffmpeg',['-version'],{stdio:'ignore'}).status!==0){t.skip('FFmpeg not installed');return;}
  const wire=[];const socket={destroyed:false,writableLength:0};
  const channel={send:(msg)=>wire.push(msg)};
  const result=await sendPreview(channel,socket,{testPattern:true,width:320,fps:2,maxFrames:2});
  assert.equal(result.sent,2);
  const got=[];const asm=new PreviewAssembler(jpg=>got.push(jpg));
  wire.forEach(msg=>asm.ingest(msg));
  assert.equal(got.length,2);assert.ok(got.every(j=>j.length>1000));
});

test('Missing FFmpeg fails predictably without an unhandled rejection', async () => {
  const socket = {destroyed:false,writableLength:0};
  const channel = {send:() => { throw Error('No frames should be sent'); }};
  await assert.rejects(
    sendPreview(channel,socket,{testPattern:true,ffmpeg:'__liquid_remote_missing_ffmpeg_test__',maxFrames:1}),
    error => error?.code === 'ENOENT'
  );
});

test('Revoking peer trust during MJPEG preview stops capture before further frames', {timeout:25000}, async t => {
  if(spawnSync('ffmpeg',['-version'],{stdio:'ignore'}).status!==0){t.skip('FFmpeg not installed');return;}
  let trusted=true;
  const sent=[];
  const channel={send:msg=>{
    sent.push(msg);
    if(msg.type==='FRAME_END') trusted=false;
  }};
  await assert.rejects(
    sendPreview(channel,{destroyed:false,writableLength:0},{
      testPattern:true,width:320,fps:4,maxFrames:4,isSessionActive:()=>trusted
    }),
    /trust revoked/
  );
  assert.equal(sent.filter(m=>m.type==='FRAME_END').length,1);
});
test('Revoked peer cannot start MJPEG capture',async()=>{
  await assert.rejects(sendPreview({send:()=>{throw Error('unexpected send');}},
    {destroyed:false,writableLength:0},{isSessionActive:()=>false}),
    /trust revoked before capture/);
});


test('Revoking trust while FFmpeg is silent terminates the capture process', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX executable fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-idle-preview-'));
  try {
    const fake=path.join(dir,'ffmpeg-stall');
    await fs.writeFile(fake, `#!/bin/sh\nexec "${process.execPath}" -e 'setTimeout(() => {}, 10000)'\n`);
    await fs.chmod(fake,0o755);
    let checks=0;
    const started=Date.now();
    await assert.rejects(sendPreview({send:()=>assert.fail('silent capture must not send frames')},
      {destroyed:false,writableLength:0},{ffmpeg:fake,isSessionActive:()=>++checks===1}),
      /trust revoked/);
    assert.ok(Date.now()-started<3000,'revoked idle capture should terminate promptly');
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});


test('Revoked silent MJPEG child is force-terminated if it ignores SIGTERM', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX signal-handler fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-hardkill-preview-'));
  try {
    const fake=path.join(dir,'ffmpeg-ignore-term');
    await fs.writeFile(fake, `#!/bin/sh\nexec "${process.execPath}" -e 'process.on("SIGTERM", () => {}); setTimeout(() => {}, 10000)'\n`);
    await fs.chmod(fake,0o755);
    let checks=0;
    const started=Date.now();
    await assert.rejects(sendPreview({send:()=>assert.fail('silent capture must not send frames')},
      {destroyed:false,writableLength:0},{ffmpeg:fake,isSessionActive:()=>++checks===1}),
      /trust revoked/);
    assert.ok(Date.now()-started<3000,'revoked child that ignores SIGTERM must be force-terminated');
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('Viewer disconnect while MJPEG capture is silent terminates the child', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX silent-process fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-disconnect-preview-'));
  try {
    const fake=path.join(dir,'ffmpeg-silent');
    await fs.writeFile(fake, `#!/bin/sh\nexec "${process.execPath}" -e 'setTimeout(() => {}, 10000)'\n`);
    await fs.chmod(fake,0o755);
    const socket={destroyed:false,writableLength:0};
    const messages=[];
    const started=Date.now();
    const pending=sendPreview({send:message=>messages.push(message)},socket,
      {ffmpeg:fake,isSessionActive:()=>true});
    await new Promise(resolve=>setTimeout(resolve,150));
    socket.destroyed=true;
    await assert.rejects(pending,/Viewer disconnected/);
    assert.ok(Date.now()-started<3000,'silent capture should stop promptly after viewer disconnect');
    assert.deepEqual(messages,[]);
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

test('MJPEG capture reports a nonzero FFmpeg exit even after sending a frame', {timeout:5000}, async t => {
  if(process.platform==='win32'){t.skip('POSIX executable fixture');return;}
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'remote-mjpeg-nonzero-exit-'));
  try {
    const fake=path.join(dir,'ffmpeg-exits-nonzero');
    const payload=mini.toString('base64');
    const node=JSON.stringify(process.execPath);
    await fs.writeFile(fake, `#!/bin/sh\nexec ${node} -e 'process.stdout.write(Buffer.from("${payload}","base64"), () => process.exit(17))'\n`);
    await fs.chmod(fake,0o755);
    const messages=[];
    await assert.rejects(
      sendPreview({send:message=>messages.push(message)},
        {destroyed:false,writableLength:0},
        {ffmpeg:fake,isSessionActive:()=>true}),
      /FFmpeg failed \\(17\\)/
    );
    assert.equal(messages.filter(message=>message.type==='FRAME_END').length,1,
      'the synthetic frame should be observed before the encoder failure is reported');
    assert.ok(!messages.some(message=>message.type==='PREVIEW_COMPLETE'||message.type==='CAPTURE_COMPLETE'),
      'a nonzero encoder exit must not be represented as successful stream completion');
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
});

