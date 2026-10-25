import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const script=fileURLToPath(new URL('./pair_agent.mjs',import.meta.url));
async function freePort(){return await new Promise(resolve=>{
  const s=net.createServer().listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});
});}
function launch(args){
  const p=spawn(process.execPath,[script,...args],{stdio:['pipe','pipe','pipe']});
  let logs='';let approved=false;
  for (const stream of [p.stdout,p.stderr])stream.on('data',bytes=>{
    logs+=bytes.toString('utf8');
    if (!approved&&/SAS:\s*\d{6}/.test(logs)){approved=true;p.stdin.write('YES\n');}
  });
  return {p, get logs(){return logs;},stop(){p.kill('SIGTERM');}};
}
async function until(task,ms=3000){
  const end=Date.now()+ms;
  while(!task()){
    if(Date.now()>end)throw new Error('Agent fixture timed out');
    await new Promise(resolve=>setTimeout(resolve,15));
  }
}
test('pairing agent persists pinned fingerprints only after two manual approvals',async t=>{
  const a=fs.mkdtempSync(path.join(os.tmpdir(),'remote-pair-host-'));
  const b=fs.mkdtempSync(path.join(os.tmpdir(),'remote-pair-client-'));
  t.after(()=>{fs.rmSync(a,{recursive:true,force:true});fs.rmSync(b,{recursive:true,force:true});});
  const port=await freePort();
  const server=launch(['--listen',`--port=${port}`,`--state=${a}`]);
  t.after(()=>server.stop());
  await until(()=>server.logs.includes('PAIR_AGENT_READY'));
  const client=launch([`--connect=127.0.0.1:${port}`,`--state=${b}`]);
  t.after(()=>client.stop());
  await until(()=>client.logs.includes('PAIR_OK')&&server.logs.includes('PAIR_OK'),5000);
  const clientCode=client.logs.match(/SAS:\s*(\d{6})/)[1];
  const serverCode=server.logs.match(/SAS:\s*(\d{6})/)[1];
  assert.equal(clientCode,serverCode);
  const trustA=JSON.parse(fs.readFileSync(path.join(a,'trusted.json'),'utf8'));
  const trustB=JSON.parse(fs.readFileSync(path.join(b,'trusted.json'),'utf8'));
  assert.equal(Object.keys(trustA).length,1);assert.equal(Object.keys(trustB).length,1);
  await until(()=>client.logs.includes('SECURE_PONG')||client.logs.includes('SESSION_REJECTED'));
  assert.match(client.logs,/SECURE_PONG/);
});

test('receive-folder listener reclaims only stale marked batches before accepting LAN peers',async t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'remote-recovery-host-'));
  const state=fs.mkdtempSync(path.join(os.tmpdir(),'remote-recovery-state-'));
  t.after(()=>{fs.rmSync(root,{recursive:true,force:true});fs.rmSync(state,{recursive:true,force:true});});
  const now=Date.now(),old=now-25*60*60*1000;
  const id='orphanRecovery123';
  const staging=path.join(root,'.liquidremote-batch-'+id);
  fs.mkdirSync(path.join(staging,'payload'),{recursive:true});
  fs.writeFileSync(path.join(staging,'payload','partial.bin'),'unverified');
  const marker=path.join(staging,'.liquidremote-batch-recovery.json');
  fs.writeFileSync(marker,JSON.stringify({version:1,id,createdAt:old}));
  fs.utimesSync(marker,new Date(old),new Date(old));
  fs.utimesSync(staging,new Date(old),new Date(old));
  const untouched=path.join(root,'.liquidremote-batch-unmarked123');
  fs.mkdirSync(untouched);
  const port=await freePort();
  const server=launch(['--listen','--no-discovery',`--port=${port}`,
    `--state=${state}`,`--receive-folder=${root}`]);
  t.after(()=>server.stop());
  await until(()=>server.logs.includes('PAIR_AGENT_READY'),5000);
  assert.match(server.logs,/FOLDER_STAGING_RECOVERY removed=1 skipped=1/);
  assert.equal(fs.existsSync(staging),false);
  assert.equal(fs.existsSync(untouched),true);
});
