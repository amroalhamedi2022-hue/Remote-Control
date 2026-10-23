import test from 'node:test';
import assert from 'node:assert/strict';
import { H264LiveViewer } from './h264_live_viewer.mjs';

test('live viewer only launches after explicit start and consumes a bounded stream', async () => {
  const args = ['-e', 'let n=0;process.stdin.on("data",b=>n+=b.length);process.stdin.on("end",()=>process.exit(n===376?0:4));'];
  const viewer = new H264LiveViewer({ executable: process.execPath, args });
  assert.throws(() => viewer.write(Buffer.alloc(188)), /not running/);
  viewer.start();
  viewer.write(Buffer.alloc(188, 0x47));
  viewer.write(Buffer.alloc(188, 0x47));
  const result = await viewer.finish();
  assert.equal(result.code, 0);
  assert.equal(viewer.bytes, 376);
  assert.throws(() => viewer.write(Buffer.alloc(1)), /not running/);
});

test('viewer rejects invalid media chunks and double start', async () => {
  const viewer = new H264LiveViewer({executable: process.execPath, args: ['-e', 'process.stdin.resume()']});
  viewer.start();
  assert.throws(() => viewer.start(), /already started/);
  assert.throws(() => viewer.write(Buffer.alloc(2401)), /Invalid video part/);
  assert.throws(() => viewer.write(Buffer.alloc(0)), /Invalid video part/);
  const exit = await viewer.stop();
  assert.ok(exit.signal || exit.code === 0);
});

test('missing FFplay fails closed (never grants a streaming session)', async () => {
  const viewer = new H264LiveViewer({executable: 'liquidremote-definitely-not-an-app'});
  viewer.start();
  const result = await viewer.ended;
  assert.ok(result.error);
  assert.throws(() => viewer.write(Buffer.alloc(188)), /stopped/);
  await viewer.stop();
});
