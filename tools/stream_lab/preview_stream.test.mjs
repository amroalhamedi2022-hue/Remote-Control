import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
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
