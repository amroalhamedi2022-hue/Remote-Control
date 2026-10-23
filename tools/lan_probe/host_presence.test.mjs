import test from 'node:test';
import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {startHostPresence} from './host_presence.mjs';
import {payload, parsePacket, randomId} from './protocol.mjs';

async function findFreePort(type) {
  if(type==='udp')return await new Promise(resolve=>{
    const s=dgram.createSocket('udp4');s.bind(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});
  });
  return await new Promise(resolve=>{
    const s=net.createServer();s.listen(0,'127.0.0.1',()=>{const p=s.address().port;s.close(()=>resolve(p));});
  });
}
async function sendUdpProbe(port) {
  const socket=dgram.createSocket('udp4');
  try {
    await new Promise((resolve,reject)=>{socket.once('error',reject);socket.bind(0,'127.0.0.1',resolve);});
    return await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('No host announcement')),1500);
      socket.on('message',(raw,remote)=>{
        const packet=parsePacket(raw);
        if(packet?.kind==='ANNOUNCE' && remote.address==='127.0.0.1') {
          clearTimeout(timeout);resolve(packet);
        }
      });
      socket.send(payload('DISCOVER',{id:randomId(),name:'Pad 5',platform:'Android',tcpPort:43998}),port,'127.0.0.1');
    });
  } finally {socket.close();}
}
async function pingTcp(port,message='PING\n') {
  return await new Promise((resolve,reject)=>{
    const client=net.connect(port,'127.0.0.1');
    let buf='';
    client.setTimeout(1500,()=>client.destroy(new Error('probe timed out')));
    client.on('connect',()=>client.write(message));
    client.on('data',b=>buf+=b.toString());
    client.on('end',()=>resolve(buf));
    client.on('error',reject);
  });
}
test('Windows host presence replies to Flutter-compatible discovery and safe PING',async t=>{
  const udpPort=await findFreePort('udp'),tcpPort=await findFreePort('tcp');
  const host=await startHostPresence({udpPort,tcpPort,name:'MSI Sword 15',platform:'Windows',broadcast:false});
  t.after(()=>host.close());
  const found=await sendUdpProbe(udpPort);
  assert.equal(found.name,'MSI Sword 15');
  assert.equal(found.platform,'Windows');
  assert.equal(found.tcpPort,tcpPort);
  assert.match(found.id,/^[0-9a-f]{32}$/);
  assert.equal(await pingTcp(tcpPort),'PONG\n');
  assert.equal(await pingTcp(tcpPort,'FORBIDDEN\n'),'');
});
test('host presence refuses malformed parameters and does not silently swallow port collisions',async t=>{
  await assert.rejects(startHostPresence({udpPort:0}),/port/);
  await assert.rejects(startHostPresence({name:'A'.repeat(65)}),/options/);
  const udpPort=await findFreePort('udp'),tcpPort=await findFreePort('tcp');
  const host=await startHostPresence({udpPort,tcpPort,broadcast:false});
  t.after(()=>host.close());
  await assert.rejects(startHostPresence({udpPort:await findFreePort('udp'),tcpPort,broadcast:false}),/EADDRINUSE/);
});
test('full Node pairing host exposes the same presence and TCP-probe services', async t=>{
  const udpPort=await findFreePort('udp'),tcpPort=await findFreePort('tcp'),pairPort=await findFreePort('tcp');
  const file=fileURLToPath(new URL('./pair_agent.mjs',import.meta.url));
  const {mkdtempSync,rmSync}=await import('node:fs');
  const {tmpdir}=await import('node:os');
  const {join}=await import('node:path');
  const state=mkdtempSync(join(tmpdir(),'liquid-discovery-test-'));
  const child=spawn(process.execPath,[file,'--listen',`--port=${pairPort}`,`--state=${state}`,`--discovery-port=${udpPort}`,`--probe-port=${tcpPort}`],{stdio:['pipe','pipe','pipe']});
  t.after(()=>{child.kill('SIGTERM');child.stdin.end();rmSync(state,{recursive:true,force:true});});
  await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('pair host did not start discovery')),4500);
    child.stdout.on('data',bytes=>{if(bytes.toString().includes('DISCOVERY_READY')){clearTimeout(timer);resolve();}});
    child.once('exit',code=>{clearTimeout(timer);reject(new Error('pair host exited '+code));});
  });
  const found=await sendUdpProbe(udpPort);
  assert.equal(found.tcpPort,tcpPort);
  assert.equal(await pingTcp(tcpPort),'PONG\n');
});
