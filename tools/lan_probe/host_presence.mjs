// v0.8: Discovery and connectivity-check bridge for an explicitly started
// pairing host. Presence packets are UNAUTHENTICATED. Never authorize access
// from an advertised name/IP alone: only user-verified pairing may do that.
import dgram from 'node:dgram';
import net from 'node:net';
import os from 'node:os';
import {randomId, payload, parsePacket, UDP_PORT, TCP_PORT} from './protocol.mjs';

const waitForUdp = (socket, port) => new Promise((resolve, reject) => {
  const error = e => {socket.off('error', error); reject(e);};
  socket.once('error', error);
  socket.bind(port, '0.0.0.0', () => {socket.off('error', error); resolve();});
});
const waitForTcp = (server, port) => new Promise((resolve, reject) => {
  const error = e => {server.off('error', error); reject(e);};
  server.once('error', error);
  server.listen(port, '0.0.0.0', () => {server.off('error', error); resolve();});
});
const closeTcp = server => new Promise(resolve => server.close(()=>resolve()));

export async function startHostPresence({udpPort=UDP_PORT, tcpPort=TCP_PORT,
    name=os.hostname().slice(0, 64) || 'Windows Host',
    platform=process.platform==='win32' ? 'Windows' : 'Node-Test',
    broadcast=true, intervalMs=5000}={}) {
  for(const p of [udpPort,tcpPort]) if(!Number.isInteger(p)||p<1||p>65535)
    throw new Error('Invalid discovery port');
  if (typeof name!=='string'||name.length<1||name.length>64||
      typeof platform!=='string'||platform.length<1||platform.length>32||
      !Number.isInteger(intervalMs)||intervalMs<100||intervalMs>120000)
    throw new Error('Invalid presence options');
  const node = {id:randomId(),name,platform,tcpPort};
  const udp=dgram.createSocket({type:'udp4',reuseAddr:true});
  const tcp=net.createServer(socket=>{
    // Probe is deliberately incapable of issuing screen/control commands.
    socket.setTimeout(3000,()=>socket.destroy());
    let command='';
    socket.on('data',bytes=>{
      if(command.length+bytes.length>64) {socket.destroy();return;}
      command+=bytes.toString('utf8');
      if(!command.includes('\n'))return;
      if(command==='PING\n'||command==='PING\r\n')socket.end('PONG\n');
      else socket.destroy();
    });
    socket.on('error',()=>socket.destroy());
  });
  let timer;
  try {
    await waitForUdp(udp,udpPort);
    await waitForTcp(tcp,tcpPort);
    udp.setBroadcast(true);
    const send = (kind, address, port) => {
      if(!udp) return;
      try {udp.send(payload(kind,node),port,address,()=>{});} catch {/* Interface unavailable */}
    };
    udp.on('message',(data,remote)=>{
      const peer=parsePacket(data);
      if(!peer || peer.id===node.id)return;
      if(peer.kind==='DISCOVER')send('ANNOUNCE',remote.address,remote.port);
    });
    const announce = () => {
      if (broadcast) {
        send('DISCOVER','255.255.255.255',udpPort);
        send('ANNOUNCE','255.255.255.255',udpPort);
      }
    };
    timer=setInterval(announce,intervalMs);
    announce();
    let stopped=false;
    return {node, udpPort, tcpPort,
      async close(){
        if(stopped)return;
        stopped=true;
        clearInterval(timer);
        await Promise.all([new Promise(resolve=>udp.close(()=>resolve())),closeTcp(tcp)]);
      },
    };
  } catch(e) {
    clearInterval(timer);
    try{udp.close();}catch{/* already closed */}
    if(tcp.listening)await closeTcp(tcp);
    throw e;
  }
}
