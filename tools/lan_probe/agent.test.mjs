import test from 'node:test';
import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import net from 'node:net';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { parsePacket, parseEndpoint, payload, randomId } from './protocol.mjs';

const run=promisify(execFile);
const path=fileURLToPath(new URL('./agent.mjs',import.meta.url));
async function port(kind) {
  if(kind==='tcp')return await new Promise(resolve=>{
    const s=net.createServer().listen(0,'127.0.0.1',()=>{const n=s.address().port;s.close(()=>resolve(n));});
  });
  return await new Promise(resolve=>{
    const s=dgram.createSocket('udp4');s.bind(0,'127.0.0.1',()=>{const n=s.address().port;s.close(()=>resolve(n));});
  });
}
test('parser rejects malformed, forged names and oversized packets',()=>{
  const correct={id:randomId(),name:'Tablet',platform:'Android',tcpPort:43828};
  assert.equal(parsePacket(payload('ANNOUNCE', correct)).name,'Tablet');
  assert.equal(parsePacket(Buffer.from('{')),null);
  assert.equal(parsePacket(Buffer.alloc(1201)),null);
  assert.equal(parsePacket(payload('ANNOUNCE',{...correct,id:'spoof'})),null);
  assert.equal(parsePacket(payload('ANNOUNCE',{...correct,name:'x'.repeat(65)})),null);
  assert.equal(parsePacket(payload('ANNOUNCE',{...correct,tcpPort:0})),null);
  assert.deepEqual(parseEndpoint('192.168.1.10:44000'),{ip:'192.168.1.10',port:44000});
  assert.throws(()=>parseEndpoint('256.1.2.3'));
});
test('actual UDP manual-IP discovery + TCP probe exchange over loopback',async(t)=>{
  const udp=await port('udp'),tcp=await port('tcp');
  const child=spawn(process.execPath,[path,'--serve',`--udp-port=${udp}`,`--tcp-port=${tcp}`],{stdio:['ignore','pipe','pipe']});
  t.after(()=>child.kill('SIGTERM'));
  await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('Agent did not start')),3500);
    child.stdout.on('data',d=>{if(d.toString().includes('READY')){clearTimeout(timer);resolve();}});
    child.once('exit',code=>{clearTimeout(timer);reject(new Error('Agent exited: '+code));});
  });
  const reply=await run(process.execPath,[path,`--probe=127.0.0.1:${udp}`,'--timeout=1200'],{timeout:3000});
  const found=JSON.parse(reply.stdout.trim());
  assert.equal(found.found,true);
  assert.equal(found.peer.tcpPort,tcp);
  assert.equal(found.peer.kind,'ANNOUNCE');
  const ping=await run(process.execPath,[path,`--ping=127.0.0.1:${tcp}`,'--timeout=1200'],{timeout:3000});
  const reached=JSON.parse(ping.stdout.trim());
  assert.equal(reached.reached,true);
  assert.ok(reached.rttMs>=0);
  const conn=net.createConnection({host:'127.0.0.1',port:tcp});
  const closed=await new Promise(resolve=>{conn.on('connect',()=>conn.write('UNAUTHORIZED_COMMAND\n'));
    let data='';conn.on('data',b=>data+=b);conn.on('close',()=>resolve(data));conn.on('error',()=>resolve(data));});
  assert.equal(closed,''); // The probe endpoint never accepts control commands.
});
