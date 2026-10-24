import test from 'node:test';
import assert from 'node:assert/strict';
import {clipboardByteLength,acceptClipboardRequest,MAX_CLIPBOARD_BYTES,writeWindowsClipboard} from './clipboard_transfer.mjs';

test('Unicode clipboard size uses UTF-8 bytes, not JS code units', () => {
  assert.equal(clipboardByteLength('مرحبًا 👋'), Buffer.byteLength('مرحبًا 👋'));
  assert.equal(clipboardByteLength('😀'.repeat(512)), MAX_CLIPBOARD_BYTES);
  assert.throws(() => clipboardByteLength('😀'.repeat(513)), /exceeds/);
});
test('reject unsafe clipboard payloads before prompting or writing', async () => {
  let prompted=0, written=0;
  const ops={approve:async()=>{prompted++;return true;},writeClipboard:async()=>{written++;}};
  for (const text of ['', '\u0000', 'a\u0007b', 'a\uFFFD', '\uD800', 'x'.repeat(2049), 'invoice\u202Egpj.exe', 'hidden\u2066text',
    'x\u200by', 'a\u061cb', 99]) {
    await assert.rejects(acceptClipboardRequest({send(){}},{type:'CLIPBOARD_PUT',text},ops));
  }
  await assert.rejects(acceptClipboardRequest({send(){}},{type:'INPUT',text:'abc'},ops));
  assert.equal(prompted,0); assert.equal(written,0);
});
test('explicit host denial never writes clipboard', async () => {
  let written=0;const sent=[];
  assert.equal(await acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'secret'},
    {approve:async()=>false,writeClipboard:async()=>{written++;}}),false);
  assert.equal(written,0);assert.deepEqual(sent,[{type:'CLIPBOARD_DENIED'}]);
});
test('host writes exact UTF-8 text once and acknowledges only after success', async () => {
  const sent=[], events=[];const text='سطر أول\nsecond line 🫧';
  assert.equal(await acceptClipboardRequest({send:x=>{events.push('ack');sent.push(x);}},
    {type:'CLIPBOARD_PUT',text},
    {approve:async()=>{events.push('approved');return true;},
      writeClipboard:async x=>{assert.equal(x,text);events.push('written');}}),true);
  assert.deepEqual(events,['approved','written','ack']);
  assert.deepEqual(sent,[{type:'CLIPBOARD_OK',bytes:Buffer.byteLength(text)}]);
});
test('failed host clipboard write never returns success', async () => {
  const sent=[];
  await assert.rejects(acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'safe'},
    {approve:async()=>true,writeClipboard:async()=>{throw Error('clipboard unavailable');}}),/unavailable/);
  assert.deepEqual(sent,[]);
});
test('Windows clipboard backend is unavailable on non-Windows runners', async t => {
  if(process.platform==='win32'){t.skip('Windows integration requires interactive desktop');return;}
  await assert.rejects(writeWindowsClipboard('test'),/Windows clipboard host required/);
});
