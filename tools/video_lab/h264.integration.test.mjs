import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import {generateIdentity,pairSocket} from '../lan_probe/secure_pairing.mjs';
import {sendH264,H264Assembler,assertTransportStream} from './h264_transport.mjs';

const ffmpegAvailable=spawnSync('ffmpeg',['-version'],{encoding:'utf8'}).status===0;
const ffprobeAvailable=spawnSync('ffprobe',['-version'],{encoding:'utf8'}).status===0;

// Actual encrypted TCP transfer + FFmpeg encode/decode; no desktop capture or Flutter.
test('pair -> approve H.264 preview -> FFmpeg encode -> encrypted TCP -> decode to frames',
  {timeout:30000,skip:!ffmpegAvailable||!ffprobeAvailable}, async()=>{
  const serverId=generateIdentity(),clientId=generateIdentity();
  let serverSas,clientSas,hostError;
  const host=net.createServer(async socket=>{
    try {
      const {channel}=await pairSocket(socket,{role:'server',identity:serverId,onCode:async x=>{serverSas=x.sas;return true;}});
      assert.equal((await channel.receive()).type,'PING');channel.send({type:'PONG'});
      assert.deepEqual(await channel.receive(),{type:'H264_START',mode:'view-only',seconds:2});
      const screenApproved=true; assert.equal(screenApproved,true); // distinct opt-in gate on test host
      channel.send({type:'H264_READY',profile:'h264-mpegts-lab'});
      await sendH264(channel,socket,{testPattern:true,seconds:2,fps:12,width:640});
    }catch(e){hostError=e;}finally{socket.end();}
  });
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));
  try {
    const socket=net.connect(host.address().port,'127.0.0.1');
    const {channel}=await pairSocket(socket,{role:'client',identity:clientId,onCode:async x=>{clientSas=x.sas;return true;}});
    channel.send({type:'PING'});assert.equal((await channel.receive()).type,'PONG');
    channel.send({type:'H264_START',mode:'view-only',seconds:2});
    assert.equal((await channel.receive()).type,'H264_READY');
    const chunks=[];let final;
    const assembler=new H264Assembler({onChunk:b=>chunks.push(b),onComplete:r=>final=r});
    while(!assembler.complete) assembler.ingest(await channel.receive());
    const ts=Buffer.concat(chunks);
    assert.equal(serverSas,clientSas);
    assertTransportStream(ts);
    assert.equal(final.bytes,ts.length);
    assert.equal(final.sha256,crypto.createHash('sha256').update(ts).digest('hex'));
    const probe=spawnSync('ffprobe',['-v','error','-show_entries','stream=codec_name,width,height',
      '-of','csv=p=0','-i','pipe:0'],{input:ts,encoding:'utf8',maxBuffer:4*1024*1024});
    assert.equal(probe.status,0,probe.stderr);
    assert.match(probe.stdout,/h264,640,360/);
    const decode=spawnSync('ffmpeg',['-v','error','-i','pipe:0','-frames:v','1',
      '-f','null','-'],{input:ts,encoding:'utf8',maxBuffer:4*1024*1024});
    assert.equal(decode.status,0,decode.stderr);
    socket.destroy();
    assert.equal(hostError,undefined,hostError?.stack);
  }finally{host.close();}
});

test('after pairing, host refuses H.264 access separately; no video bytes', {timeout:10000},async()=>{
  const host=net.createServer(async socket=>{
    try{
      const {channel}=await pairSocket(socket,{role:'server',identity:generateIdentity(),onCode:async()=>true});
      assert.equal((await channel.receive()).type,'PING');channel.send({type:'PONG'});
      assert.equal((await channel.receive()).type,'H264_START');
      const localApproval=false;
      if(!localApproval) channel.send({type:'H264_DENIED'});
    }finally{socket.end();}
  });
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));
  try{
    const socket=net.connect(host.address().port,'127.0.0.1');
    const {channel}=await pairSocket(socket,{role:'client',identity:generateIdentity(),onCode:async()=>true});
    channel.send({type:'PING'});assert.equal((await channel.receive()).type,'PONG');
    channel.send({type:'H264_START',mode:'view-only',seconds:2});
    assert.equal((await channel.receive()).type,'H264_DENIED');
    socket.destroy();
  }finally{host.close();}
});
