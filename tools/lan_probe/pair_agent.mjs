#!/usr/bin/env node
// Secure pairing laboratory agent. User-facing confirmation is always mandatory.
// Plaintext private key storage in this fixture is NOT approved for product release.
import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { pairSocket, generateIdentity, identityFingerprint } from './secure_pairing.mjs';
import { sendPreview, PreviewAssembler } from '../stream_lab/preview_stream.mjs';
import { sendH264, H264Assembler } from '../video_lab/h264_transport.mjs';
import { H264LiveViewer } from '../video_lab/h264_live_viewer.mjs';
import { startHostPresence } from './host_presence.mjs';

const options=process.argv.slice(2);
const flag = name => options.includes(`--${name}`);
const opt = name => options.find(x=>x.startsWith(`--${name}=`))?.split('=').slice(1).join('=');
const statePath = opt('state') || path.join(os.homedir(),'.liquidremote-lab');
const port=Number(opt('port')||43829);
if(!Number.isInteger(port)||port<1||port>65535){console.error('Bad port');process.exit(1);}

function atomicSave(file,obj) {
  const tmp=file+'.tmp-'+process.pid;
  fs.writeFileSync(tmp,JSON.stringify(obj,null,2),{mode:0o600,flag:'wx'});
  fs.renameSync(tmp,file);
}
function readState() {
  fs.mkdirSync(statePath,{recursive:true,mode:0o700});
  const identityFile=path.join(statePath,'identity.json');
  const trustFile=path.join(statePath,'trusted.json');
  let identity;
  if(fs.existsSync(identityFile)) identity=JSON.parse(fs.readFileSync(identityFile,'utf8'));
  else {identity=generateIdentity();atomicSave(identityFile,identity);}
  const trusted=fs.existsSync(trustFile)?JSON.parse(fs.readFileSync(trustFile,'utf8')):{};
  return {identity,trusted:new Map(Object.entries(trusted)),trustFile};
}
const {identity,trusted,trustFile}=readState();
const saveTrust=()=>atomicSave(trustFile,Object.fromEntries(trusted));
if(flag('list')) {
  console.log('Local identity fingerprint:',identityFingerprint(identity.publicKey));
  console.log('Trusted peer fingerprints:',...trusted.keys());
  process.exit(0);
}
if(opt('revoke')) {
  const prefix=opt('revoke');const matches=[...trusted.keys()].filter(x=>x.startsWith(prefix));
  if(matches.length!==1){console.error('Need exactly one matching fingerprint');process.exit(1);}
  trusted.delete(matches[0]);saveTrust();console.log('REVOKED',matches[0]);process.exit(0);
}
const rl=createInterface({input,output});
async function approve({sas,fingerprint,known}) {
  console.log('\nPairing verification — compare on BOTH devices');
  console.log(`SAS: ${sas}    Peer identity: ${fingerprint.slice(0,20)}…`);
  console.log(known?'Previously trusted identity':'NEW, UNTRUSTED identity');
  const answer=(await rl.question('Only if the 6-digit codes match on both devices, type YES: ')).trim();
  return answer === 'YES';
}
async function interact(socket,role) {
  try {
    const {fingerprint,channel,known}=await pairSocket(socket,{role,identity,trustStore:trusted,onCode:approve});
    saveTrust();
    console.log(`PAIR_OK ${fingerprint.slice(0,20)} (${known?'recognized':'new'}) — encrypted channel active`);
    if(role==='client') {
      channel.send({type:'PING',sentAt:Date.now()});
      const response=await channel.receive();
      if(response?.type!=='PONG')throw new Error('Unexpected secure response');
      console.log('SECURE_PONG received; no remote access permission was granted');
      if(flag('view-h264') || flag('watch-h264')) {
        const seconds = Number(opt('max-seconds') || 3);
        if (!Number.isInteger(seconds) || seconds < 1 || seconds > 10) throw Error('H.264 preview duration must be 1–10 seconds');
        const destination = opt('output');
        if (destination && path.extname(destination).toLowerCase() !== '.ts') throw Error('H.264 output must end in .ts');
        if (!destination && !flag('watch-h264')) throw Error('Specify --output=clip.ts and/or --watch-h264');
        channel.send({type:'H264_START', mode:'view-only', seconds});
        const reply=await channel.receive();
        if(reply?.type!=='H264_READY') throw Error('Host declined H.264 preview');
        let file;let player;let successful=false;
        try {
          if (destination) file=fs.openSync(destination, 'wx', 0o600);
          if (flag('watch-h264')) {
            player=new H264LiveViewer();
            player.start();
            console.log('LIVE_VIEWER_STARTED (FFplay). Ctrl+C to stop.');
          }
          const receiver=new H264Assembler({
            onChunk: bytes => {
              if (file !== undefined) fs.writeSync(file, bytes);
              if (player) player.write(bytes);
            },
            onComplete: result => {successful=true; console.log('ENCRYPTED_H264_RECEIVED', JSON.stringify(result));},
          });
          while(!receiver.complete) receiver.ingest(await channel.receive());
        } finally {
          if(file!==undefined) fs.closeSync(file);
          if (player) {
            if (successful) await player.finish();
            else await player.stop();
          }
          if(!successful && file!==undefined) fs.rmSync(destination,{force:true});
        }
      }
      if(flag('view-screen')) {
        const maxFrames=Number(opt('max-frames')||2);
        if(!Number.isInteger(maxFrames)||maxFrames<1||maxFrames>20)throw Error('Bad --max-frames');
        channel.send({type:'STREAM_START',mode:'view-only'});
        const reply=await channel.receive();
        if(reply?.type!=='STREAM_READY')throw Error('Host has not granted view-only preview');
        let frameCount=0;
        const assembler=new PreviewAssembler(jpeg=>{
          frameCount++;
          if(frameCount===1&&opt('output')){
            // Explicit output option only. This JPEG may show private screen content.
            fs.writeFileSync(opt('output'),jpeg,{flag:'wx',mode:0o600});
          }
          console.log('ENCRYPTED_PREVIEW_JPEG',frameCount,`${jpeg.length} bytes`);
        });
        while(frameCount<maxFrames) assembler.ingest(await channel.receive());
      }
    } else {
      const request=await channel.receive();
      if(request?.type==='PING')channel.send({type:'PONG'});
      else throw new Error('Action prohibited: Only encrypted PING is allowed');
      if(flag('share-screen') || flag('share-h264')) {
        const req=await channel.receive();
        if(req?.type==='H264_START') {
          if(!flag('share-h264') || req.mode!=='view-only' ||
             !Number.isInteger(req.seconds) || req.seconds<1 || req.seconds>10) {
            channel.send({type:'H264_DENIED'});
            throw Error('H.264 view-only access denied by host policy');
          }
          console.log(`\nH.264 VIEW-ONLY request from ${fingerprint.slice(0,20)}... (${req.seconds}s)`);
          const consent=(await rl.question('To share THIS session only, type H264: ')).trim();
          if(consent!=='H264') {
            channel.send({type:'H264_DENIED'});
            throw Error('Host denied H.264 screen sharing');
          }
          const selectedEncoder=opt('encoder')||'libx264';
          channel.send({type:'H264_READY', profile:'h264-mpegts-lab', seconds:req.seconds});
          const result=await sendH264(channel, socket, {testPattern:flag('test-pattern'),
            seconds:req.seconds, fps:12, width:640, encoder:selectedEncoder});
          console.log('H264_SHARE_CLOSED', result);
          return;
        }
        if(!flag('share-screen')||req?.type!=='STREAM_START'||req?.mode!=='view-only')
          throw new Error('Only an explicit view-only preview request is allowed');
        console.log(`\nVIEW-ONLY screen request from ${fingerprint.slice(0,20)}...`);
        const answer=(await rl.question('To allow your screen to be shared THIS SESSION, type SHARE: ')).trim();
        if(answer!=='SHARE'){
          channel.send({type:'STREAM_DENIED'});
          throw Error('Host denied screen access');
        }
        channel.send({type:'STREAM_READY',profile:'mjpeg-lab',fps:4,width:640});
        const result=await sendPreview(channel,socket,{testPattern:flag('test-pattern'),fps:4,width:640});
        console.log('PREVIEW_CLOSED',result);
      }
    }
  } catch(e){console.error('SESSION_REJECTED',e.message); if (role === 'client') process.exitCode = 1;} finally{
    if(!socket.destroyed){socket.end();socket.setTimeout(500,()=>socket.destroy());}
  }
}
if(flag('listen')) {
  const server=net.createServer();
  let busy=false;
  server.on('connection',socket=>{
    if(busy){socket.destroy();return;}
    busy=true;
    interact(socket,'server').finally(()=>{busy=false;});
  });
  let presence;
  server.listen(port,'0.0.0.0',async()=>{
    console.log(`PAIR_AGENT_READY ${port}; local consent required on both devices${flag('share-screen') ? '; MJPEG sharing requires SHARE' : ''}${flag('share-h264') ? '; H.264 sharing requires H264' : ''}`);
    // Announce the Windows host through the same discovery format as Flutter.
    // A failed discovery bind must not silently masquerade as success.
    if (!flag('no-discovery')) {
      try {
        presence=await startHostPresence({
          udpPort:Number(opt('discovery-port')||43827),
          tcpPort:Number(opt('probe-port')||43828),
        });
        console.log(`DISCOVERY_READY UDP=${presence.udpPort} TCP=${presence.tcpPort} ID=${presence.node.id}`);
      } catch(e) {console.error('DISCOVERY_UNAVAILABLE',e.message,'— manual IP pairing still works');}
    }
  });
  async function stop(){await presence?.close();server.close();rl.close();}
  process.once('SIGINT',()=>{void stop();});
  process.once('SIGTERM',()=>{void stop();});
} else if(opt('connect')) {
  const endpoint=opt('connect');
  const [host,rawPort]=endpoint.split(':');
  const connectPort=rawPort?Number(rawPort):port;
  if(!host||!Number.isInteger(connectPort)||connectPort<1||connectPort>65535)throw new Error('Usage: --connect=192.168.1.10[:port] [--view-screen --max-frames=2 --output=frame.jpg]');
  const socket=net.createConnection({host,port:connectPort});
  await interact(socket,'client');rl.close();
} else {
  console.log('Usage: node pair_agent.mjs --listen [--no-discovery] [--share-screen] [--share-h264] [--encoder=libx264|h264_nvenc] [--test-pattern] [--port=43829] | --connect=IP[:port] [--view-screen --max-frames=2 --output=frame.jpg] | --connect=IP[:port] --view-h264 [--watch-h264] --max-seconds=3 [--output=clip.ts] | --list | --revoke=<fingerprint>');
  rl.close();process.exitCode=1;
}
