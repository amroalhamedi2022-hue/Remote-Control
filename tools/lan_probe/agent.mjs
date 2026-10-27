#!/usr/bin/env node
// Interoperability fixture / LAN discovery test agent. NOT a remote controller.
import dgram from 'node:dgram';
import net from 'node:net';
import os from 'node:os';
import { randomId, payload, parsePacket, parseEndpoint, isLanIpv4, UDP_PORT, TCP_PORT } from './protocol.mjs';

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const token = args.find(x => x.startsWith(`--${name}=`));
  return token ? token.substring(name.length + 3) : fallback;
};
const mode = args.includes('--serve') ? 'serve' : args.some(x=>x.startsWith('--probe=')) ? 'probe' :
  args.some(x=>x.startsWith('--ping=')) ? 'ping' : '';
const allowLoopbackForTests = process.env.NODE_ENV === 'test' && args.includes('--allow-loopback-for-tests');
const timeout = Number(option('timeout', 1500));
const udpPort = Number(option('udp-port', UDP_PORT));
const tcpPort = Number(option('tcp-port', TCP_PORT));
const address = option('probe', '') || option('ping', '');
const node = { id: randomId(), name: os.hostname().slice(0, 64) || 'Node Agent', platform: process.platform === 'win32' ? 'Windows' : 'Node-Test', tcpPort };

function udpBind(port) {
  return new Promise((resolve, reject) => {
    const socket = dgram.createSocket({type:'udp4',reuseAddr:true});
    socket.once('error', reject);
    socket.bind(port, '0.0.0.0', () => { socket.off('error', reject); resolve(socket); });
  });
}

async function serve() {
  const socket = await udpBind(udpPort);
  const server = net.createServer(conn => {
    // The CLI fixture must not expose even its probe endpoint to public IPs.
    // Accept a bounded complete line, not an arbitrary TCP packet boundary.
    if (!isLanIpv4(conn.remoteAddress, {allowLoopback: allowLoopbackForTests})) { conn.destroy(); return; }
    conn.setTimeout(3000, ()=>conn.destroy());
    let command='';
    conn.on('data', chunk=>{
      if (Buffer.byteLength(command, 'utf8') + chunk.length > 64) { conn.destroy(); return; }
      command += chunk.toString('utf8');
      if (!command.includes('\n')) return;
      if (command === 'PING\n' || command === 'PING\r\n') conn.end('PONG\n');
      else conn.destroy();
    });
    conn.on('error',()=>conn.destroy());
  });
  await new Promise((resolve,reject)=>server.once('error',reject).listen(tcpPort,'0.0.0.0',resolve));
  socket.setBroadcast(true);
  const send = (kind, ip, port)=>socket.send(payload(kind,node),port,ip);
  socket.on('message',(data,remote)=>{
    if (!isLanIpv4(remote.address, {allowLoopback: allowLoopbackForTests})) return;
    const peer=parsePacket(data);
    if (!peer || peer.id === node.id) return;
    if (peer.kind === 'DISCOVER') send('ANNOUNCE',remote.address,remote.port);
    if (peer.kind === 'ANNOUNCE') console.log(`PEER ${peer.name} ${remote.address}:${peer.tcpPort} · untrusted`);
  });
  const announce=()=>{
    send('DISCOVER','255.255.255.255',udpPort);
    send('ANNOUNCE','255.255.255.255',udpPort);
  };
  const interval=setInterval(announce,5000);
  announce();
  console.log(`READY UDP=${udpPort} TCP=${tcpPort} ID=${node.id}`);
  const stop=()=>{clearInterval(interval);socket.close();server.close();};
  process.on('SIGTERM',stop);process.on('SIGINT',stop);
}

async function probe() {
  const {ip,port}=parseEndpoint(address,udpPort,{allowLoopback:allowLoopbackForTests});
  const socket=await udpBind(0);
  let complete=false;
  const timer=setTimeout(()=>finish(null),timeout);
  function finish(result){
    if (complete) return;
    complete=true;clearTimeout(timer);socket.close();
    if(result){console.log(JSON.stringify({found:true,address:result.remote.address,peer:result.peer}));process.exitCode=0;}
    else {console.log(JSON.stringify({found:false,address:ip}));process.exitCode=2;}
  }
  socket.on('message',(raw,remote)=>{
    const peer=parsePacket(raw);
    if(peer?.kind==='ANNOUNCE' && remote.address===ip) finish({peer,remote});
  });
  socket.send(payload('DISCOVER',node),port,ip);
}
async function ping() {
  const {ip,port}=parseEndpoint(address,tcpPort,{allowLoopback:allowLoopbackForTests});
  const t0=performance.now();
  const conn=net.createConnection({host:ip,port});
  conn.setTimeout(timeout);
  let done=false;
  const finish=(ok)=>{if(done)return;done=true;conn.destroy();
    console.log(JSON.stringify({reached:ok,address:ip,rttMs:ok?+(performance.now()-t0).toFixed(1):null}));
    process.exitCode=ok?0:2;};
  conn.on('connect',()=>conn.write('PING\n'));
  conn.on('data',buf=>finish(buf.toString('utf8').trim()==='PONG'));
  conn.on('timeout',()=>finish(false));conn.on('error',()=>finish(false));conn.on('end',()=>finish(false));
}
if (!mode) {
  console.error('Usage: node agent.mjs --serve | --probe=192.168.1.10 | --ping=192.168.1.10');
  process.exitCode=1;
} else {
  try { await (mode==='serve'?serve():mode==='probe'?probe():ping()); }
  catch(err) { console.error(err.message); process.exitCode=1; }
}
