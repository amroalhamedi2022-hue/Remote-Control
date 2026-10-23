import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import net from 'node:net';
import {fileURLToPath} from 'node:url';
import {assertTransportStream} from './h264_transport.mjs';

const ffmpegAvailable=spawnSync('ffmpeg',['-version']).status===0;
const ffprobeAvailable=spawnSync('ffprobe',['-version']).status===0;
const agent=resolve(fileURLToPath(new URL('../lan_probe/pair_agent.mjs',import.meta.url)));
function freePort(){return new Promise((yes,no)=>{
  const s=net.createServer();s.on('error',no);s.listen(0,'127.0.0.1',()=>{
    const port=s.address().port;s.close(()=>yes(port));
  });
});}

// Real host/client command-line processes, user approval emulated by test harness.
test('Node CLIs: local consent -> encrypted H.264 MPEG-TS file -> FFprobe',
  {timeout:25000,skip:!ffmpegAvailable||!ffprobeAvailable},async()=>{
  const folder=mkdtempSync(join(tmpdir(),'liquid-h264-cli-'));
  const port=await freePort();
  const output=join(folder,'received.ts');
  const liveSink=join(folder,'watched.ts');
  const bin=join(folder,'bin');mkdirSync(bin);
  // Emulate FFplay in CI to assert decrypted bytes reach the viewer process.
  // This does not prove hardware/video output in a graphical window.
  writeFileSync(join(bin,'ffplay'), `#!/usr/bin/env node\nconst fs=require('fs');process.stdin.pipe(fs.createWriteStream(process.env.LIQUID_WATCH_SINK));\n`, {mode:0o755});
  let host,client;
  try{
    host=spawn(process.execPath,[agent,'--listen','--share-h264','--test-pattern',
      `--port=${port}`,`--state=${join(folder,'host')}`],{stdio:['pipe','pipe','pipe']});
    let hostOutput='',hostErr='',clientOutput='',clientErr='';
    host.stderr.on('data',b=>hostErr+=b);
    let hostApproved=false,clientApproved=false,h264Approved=false;
    let hostSas,clientSas;
    let resolveReady,rejectReady;
    const ready=new Promise((resolve,reject)=>{resolveReady=resolve;rejectReady=reject;});
    host.stdout.on('data',buf=>{
      hostOutput+=buf.toString();
      if(hostOutput.includes('PAIR_AGENT_READY'))resolveReady();
      hostSas??=hostOutput.match(/SAS:\s*(\d{6})/)?.[1];
      maybeConsent();
    });
    host.once('error',rejectReady);
    await ready;
    client=spawn(process.execPath,[agent,`--connect=127.0.0.1:${port}`, '--view-h264', '--watch-h264',
      '--max-seconds=2',`--output=${output}`,`--state=${join(folder,'client')}`],
      {stdio:['pipe','pipe','pipe'], env:{...process.env, PATH:`${bin}:${process.env.PATH}`, LIQUID_WATCH_SINK:liveSink}});
    client.stderr.on('data',b=>clientErr+=b);
    client.stdout.on('data',buf=>{
      clientOutput+=buf.toString();
      clientSas??=clientOutput.match(/SAS:\s*(\d{6})/)?.[1];
      maybeConsent();
    });
    function maybeConsent(){
      if(hostSas&&clientSas&&hostSas===clientSas){
        if(!hostApproved&&hostOutput.includes('type YES:')){host.stdin.write('YES\n');hostApproved=true;}
        if(!clientApproved&&clientOutput.includes('type YES:')){client.stdin.write('YES\n');clientApproved=true;}
      }
      if(hostApproved&&clientApproved&&!h264Approved&&hostOutput.includes('type H264:')){
        host.stdin.write('H264\n');h264Approved=true;
      }
    }
    const exitCode=await new Promise((resolve,reject)=>{
      client.once('error',reject);
      client.once('exit',resolve);
    });
    assert.equal(exitCode,0,`Client failed: ${clientErr}\n${clientOutput}\nHost ${hostErr}\n${hostOutput}`);
    assert.ok(hostSas&&hostSas===clientSas);
    assert.ok(h264Approved);
    assert.match(clientOutput,/ENCRYPTED_H264_RECEIVED/);
    assert.ok(existsSync(output));
    const ts=readFileSync(output);
    assertTransportStream(ts);
    assert.ok(existsSync(liveSink),'Viewer process did not receive the stream');
    assert.deepEqual(readFileSync(liveSink), ts, 'FFplay sink bytes differ from saved authenticated stream');
    const check=spawnSync('ffprobe',['-v','error','-select_streams','v:0',
      '-show_entries','stream=codec_name,width,height','-of','csv=p=0',output],{encoding:'utf8'});
    assert.equal(check.status,0,check.stderr);
    assert.match(check.stdout,/h264,640,360/);
  }finally{
    client?.kill();host?.kill();rmSync(folder,{force:true,recursive:true});
  }
});
