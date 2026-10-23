import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {h264Arguments,H264Assembler,assertTransportStream,MAX_TS_BYTES} from './h264_transport.mjs';

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
