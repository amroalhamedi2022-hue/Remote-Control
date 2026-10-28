import test from 'node:test';
import assert from 'node:assert/strict';
import {clipboardByteLength,acceptClipboardRequest,MAX_CLIPBOARD_BYTES,writeWindowsClipboard} from './clipboard_transfer.mjs';

test('Unicode clipboard size uses UTF-8 bytes, not JS code units', () => {
  assert.equal(clipboardByteLength('مرحبًا 👋'), Buffer.byteLength('مرحبًا 👋'));
  const joinerText = 'می\u200cروم 👨‍👩‍👧‍👦';
  assert.equal(clipboardByteLength(joinerText), Buffer.byteLength(joinerText, 'utf8'));
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
  const sent=[], events=[];const text='سطر أول\nsecond line 🫧 family 👨‍👩‍👧‍👦 و می\u200cروم';
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
test('revoked clipboard session rejects before consent or write', async () => {
  let approvals=0, writes=0; const sent=[];
  await assert.rejects(acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'private'},
    {isSessionActive:()=>false,approve:async()=>{approvals++;return true;},
      writeClipboard:async()=>{writes++;}}),{name:'AbortError'});
  assert.equal(approvals,0);assert.equal(writes,0);assert.deepEqual(sent,[]);
});
test('revocation while consent dialog is pending never writes or acknowledges', async () => {
  let active=true,writes=0;const sent=[];
  await assert.rejects(acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'private'},
    {isSessionActive:()=>active,approve:async()=>{active=false;return true;},
      writeClipboard:async()=>{writes++;}}),{name:'AbortError'});
  assert.equal(writes,0);assert.deepEqual(sent,[]);
});
test('trust revocation while consent remains pending aborts promptly and ignores late YES', async () => {
  let active=true,resolveConsent,writes=0;const sent=[];
  const pending=acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'private'},
    {isSessionActive:()=>{if(!active)throw new Error('trust ledger unavailable');return true;},
      approve:()=>new Promise(resolve=>{resolveConsent=resolve;}),
      writeClipboard:async()=>{writes++;},
      consentTimeoutMs:2000});
  await new Promise(resolve=>setImmediate(resolve));
  active=false;
  const started=Date.now();
  await assert.rejects(pending,{name:'AbortError'});
  assert.ok(Date.now()-started<600,'revoked trust must cancel a pending consent prompt promptly');
  resolveConsent(true);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(writes,0);
  assert.deepEqual(sent,[]);
});

test('revocation during OS clipboard write suppresses false success ACK', async () => {
  let active=true,writes=0;const sent=[];
  await assert.rejects(acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'private'},
    {isSessionActive:()=>active,approve:async()=>true,
      writeClipboard:async()=>{writes++;active=false;}}),{name:'AbortError'});
  // A platform write can already have happened; no rollback is claimed.
  assert.equal(writes,1);assert.deepEqual(sent,[]);
});
test('abort cancels a pending consent promptly and ignores a late YES', async () => {
  const controller=new AbortController();
  let resolveConsent,writes=0;const sent=[];
  const pending=acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'private'},
    {signal:controller.signal,
      approve:()=>new Promise(resolve=>{resolveConsent=resolve;}),
      writeClipboard:async()=>{writes++;}});
  await new Promise(resolve=>setImmediate(resolve));
  controller.abort();
  await assert.rejects(pending,{name:'AbortError'});
  resolveConsent(true);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(writes,0);assert.deepEqual(sent,[]);
});
test('consent deadline denies live peer; no delayed approval can publish', async () => {
  let resolveConsent,writes=0;const sent=[];
  const pending=acceptClipboardRequest({send:x=>sent.push(x)},
    {type:'CLIPBOARD_PUT',text:'private'},
    {consentTimeoutMs:15,
      approve:()=>new Promise(resolve=>{resolveConsent=resolve;}),
      writeClipboard:async()=>{writes++;}});
  await assert.rejects(pending,/consent timed out/);
  resolveConsent(true);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(writes,0);assert.deepEqual(sent,[{type:'CLIPBOARD_DENIED'}]);
});
test('invalid clipboard consent deadlines are rejected before prompting', async () => {
  let prompted=false;
  await assert.rejects(acceptClipboardRequest({send(){}},
    {type:'CLIPBOARD_PUT',text:'private'},
    {consentTimeoutMs:0,approve:async()=>{prompted=true;return true;},
      writeClipboard:async()=>{}}),/not permitted/);
  assert.equal(prompted,false);
});
test('Windows clipboard backend is unavailable on non-Windows runners', async t => {
  if(process.platform==='win32'){t.skip('Windows integration requires interactive desktop');return;}
  await assert.rejects(writeWindowsClipboard('test'),/Windows clipboard host required/);
});
