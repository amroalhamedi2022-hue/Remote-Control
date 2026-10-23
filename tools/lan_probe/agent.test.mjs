import test from 'node:test';
import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import net from 'node:net';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { parsePacket, parseEndpoint, isLanIpv4, isSafeDiscoveryLabel, payload, randomId } from './protocol.mjs';

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
test('unauthenticated discovery labels reject invisible spoofing and controls', () => {
  const base = {id: randomId(), name: 'Windows Host', platform: 'Windows', tcpPort: 43828};
  for (const unsafe of ['\u202e', '\u2066', '\u206f', '\u061c', '\u200f',
      '\u0085', '\u2028', '\ufeff', '\ufff9', '\n', '\r']) {
    assert.equal(isSafeDiscoveryLabel('Host' + unsafe + 'Fake', 64), false);
    assert.equal(parsePacket(payload('ANNOUNCE', {...base, name: 'Host' + unsafe + 'Fake'})), null);
    assert.equal(parsePacket(payload('ANNOUNCE', {...base, platform: 'Windows' + unsafe})), null);
  }
  for (const label of ['  ', '', '\t']) {
    assert.equal(isSafeDiscoveryLabel(label, 64), false);
    assert.equal(parsePacket(payload('ANNOUNCE', {...base, name: label})), null);
  }
  assert.equal(parsePacket(payload('ANNOUNCE', {...base, platform: ''})), null);
  assert.equal(isSafeDiscoveryLabel('جهاز أندرويد', 64), true);
  assert.equal(parsePacket(payload('ANNOUNCE', {...base, name: 'جهاز أندرويد'})).name,
    'جهاز أندرويد');
});

test('LAN-only Node address policy rejects public/CGNAT and permits private, link-local and loopback',()=>{
  for(const ip of ['10.1.2.3','172.16.0.1','172.31.255.254','192.168.1.20','169.254.12.4','127.0.0.1']){
    assert.equal(isLanIpv4(ip),true,ip);
  }
  for(const ip of ['8.8.8.8','203.0.113.5','172.15.1.1','172.32.0.1','100.64.0.1',
    '0.0.0.0','224.0.0.1','255.255.255.255','fe80::1','localhost','010.1.1.1']){
    assert.equal(isLanIpv4(ip),false,ip);
    assert.throws(()=>parseEndpoint(ip),/IPv4/);
  }
  assert.deepEqual(parseEndpoint('127.0.0.1:43827'),{ip:'127.0.0.1',port:43827});
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
  // TCP can split one valid PING across packets. The host must wait for a
  // complete line rather than rejecting legitimate slow/fragmented clients.
  const fragmented=await new Promise((resolve,reject)=>{
    const socket=net.createConnection({host:'127.0.0.1',port:tcp});
    let data='';
    socket.setTimeout(1500,()=>socket.destroy(new Error('fragmented probe timed out')));
    socket.on('connect',()=>{
      socket.write('PI');
      setTimeout(()=>socket.write('NG\\r\\n'),20);
    });
    socket.on('data',bytes=>data+=bytes.toString());
    socket.on('end',()=>resolve(data));
    socket.on('error',reject);
  });
  assert.equal(fragmented,'PONG\\n');
  const oversized=await new Promise((resolve,reject)=>{
    const socket=net.createConnection({host:'127.0.0.1',port:tcp});
    let data='';
    socket.setTimeout(1500,()=>socket.destroy(new Error('oversized probe timed out')));
    socket.on('connect',()=>socket.write('P'.repeat(65)+'\\n'));
    socket.on('data',bytes=>data+=bytes.toString());
    socket.on('close',()=>resolve(data));
    socket.on('error',reject);
  });
  assert.equal(oversized,'');
});
