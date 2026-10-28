import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import net from 'node:net';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname,'../lan_probe/pair_agent.mjs');
const wait = ms=>new Promise(r=>setTimeout(r,ms));
async function vacantPort(){
  const srv=net.createServer();await new Promise(ok=>srv.listen(0,'127.0.0.1',ok));
  const p=srv.address().port;await new Promise(ok=>srv.close(ok));return p;
}
function agent(args,onOutput){
  // All localhost pairs here are isolated fixtures, not production LAN peers.
  // Keep the test-only override explicit and impossible to enable by flag alone.
  const child=spawn(process.execPath,[root,'--allow-loopback-for-tests',...args],{
    stdio:['pipe','pipe','pipe'],
    env:{...process.env,NODE_ENV:'test'},
  });
  let stdout='',stderr='';
  child.stdout.on('data',b=>{const txt=b.toString();stdout+=txt;onOutput?.(child,txt,stdout);});
  child.stderr.on('data',b=>stderr+=b.toString());
  return {child,get stdout(){return stdout;},get stderr(){return stderr;}};
}

test('real CLI agent: manual pair consent + screen consent + encrypted JPEG received', {timeout:18000},async t=>{
  if (spawnSync('ffmpeg',['-version'],{stdio:'ignore'}).status !== 0) {
    t.skip('NOT TESTED: FFmpeg executable unavailable on source-only CI runner');
    return;
  }
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'liquidremote-v05-cli-'));
  const port=await vacantPort();
  let hostPairAnswered=false,shareAnswered=false,clientAnswered=false;
  const host=agent(['--listen','--share-screen','--test-pattern',`--port=${port}`,`--state=${path.join(temp,'host')}`],
    (child,txt,full)=>{
      if(!hostPairAnswered&&full.includes('type YES:')){hostPairAnswered=true;child.stdin.write('YES\n');}
      if(!shareAnswered&&full.includes('type SHARE:')){shareAnswered=true;child.stdin.write('SHARE\n');}
    });
  let client;
  try{
    for(let i=0;i<80&&!host.stdout.includes('PAIR_AGENT_READY');i++)await wait(25);
    assert.match(host.stdout,/PAIR_AGENT_READY/);
    client=agent([`--connect=127.0.0.1:${port}`,'--view-screen','--max-frames=2',
      `--output=${path.join(temp,'first-frame.jpg')}`,`--state=${path.join(temp,'client')}`],
      (child,txt,full)=>{
        if(!clientAnswered&&full.includes('type YES:')){clientAnswered=true;child.stdin.write('YES\n');}
      });
    const code=await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(Error('Client timed out: '+client.stdout+' '+client.stderr+' host: '+host.stdout+' '+host.stderr)),13000);
      client.child.once('close',status=>{clearTimeout(timeout);resolve(status);});
    });
    assert.equal(code,0,client.stderr);
    assert.match(client.stdout,/ENCRYPTED_PREVIEW_JPEG 2/);
    assert.ok(hostPairAnswered&&shareAnswered&&clientAnswered);
    const jpeg=fs.readFileSync(path.join(temp,'first-frame.jpg'));
    assert.equal(jpeg[0],0xff);assert.equal(jpeg[1],0xd8);
  } finally {
    host.child.kill();client?.child.kill();
    fs.rmSync(temp,{recursive:true,force:true});
  }
});

test('host refuses screen consent: client receives no preview', {timeout:18000},async()=>{
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'liquidremote-refuse-'));
  const port=await vacantPort();
  let hostPair=false,hostDenied=false,clientPair=false;
  const host=agent(['--listen','--share-screen','--test-pattern',`--port=${port}`,`--state=${path.join(temp,'host')}`],
    (child,txt,full)=>{
      if(!hostPair&&full.includes('type YES:')){hostPair=true;child.stdin.write('YES\n');}
      if(!hostDenied&&full.includes('type SHARE:')){hostDenied=true;child.stdin.write('NO\n');}
    });
  let client;
  try{
    for(let i=0;i<80&&!host.stdout.includes('PAIR_AGENT_READY');i++)await wait(25);
    client=agent([`--connect=127.0.0.1:${port}`,'--view-screen','--max-frames=1',
      `--output=${path.join(temp,'never.jpg')}`,`--state=${path.join(temp,'client')}`],
      (child,txt,full)=>{
        if(!clientPair&&full.includes('type YES:')){clientPair=true;child.stdin.write('YES\n');}
      });
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(Error('Host refusal test stalled')),12000);
      client.child.once('close',()=>{clearTimeout(timer);resolve();});
    });
    assert.equal(hostDenied,true);
    assert.match(client.stderr,/Host has not granted view-only preview/);
    assert.equal(fs.existsSync(path.join(temp,'never.jpg')),false);
  } finally {
    host.child.kill();client?.child.kill();fs.rmSync(temp,{recursive:true,force:true});
  }
});
