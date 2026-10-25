#!/usr/bin/env node
// Secure pairing laboratory agent. User-facing confirmation is always mandatory.
// Plaintext private key storage in this fixture is NOT approved for product release.
import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { pairSocket, generateIdentity, identityFingerprint, requireSignedIntent } from './secure_pairing.mjs';
import { sendPreview, PreviewAssembler } from '../stream_lab/preview_stream.mjs';
import { sendH264, H264Assembler } from '../video_lab/h264_transport.mjs';
import { H264LiveViewer } from '../video_lab/h264_live_viewer.mjs';
import { startHostPresence } from './host_presence.mjs';
import { isLanIpv4 } from './protocol.mjs';
import { askWithDeadline } from './consent_prompt.mjs';
import { acceptClipboardRequest, writeWindowsClipboard, clipboardByteLength } from './clipboard_transfer.mjs';
import { sendFileOnce, receiveFileOnce } from './file_transfer.mjs';
import { sendFolderOnce, receiveFolderOnce, cleanupStaleFolderTransfers } from './file_batch.mjs';

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
  const answer=await askWithDeadline(rl.question.bind(rl),
    'Only if the 6-digit codes match on both devices, type YES: (45s) ');
  return answer === 'YES';
}
// Transfer progress is real acknowledged/written bytes, not an estimated timer.
// Log at most once per MiB plus verified completion (never log file contents).
function fileProgress(label) {
  let lastMiB = -1;
  return ({bytes,total,verified}) => {
    const mib = Math.floor(bytes / (1024 * 1024));
    if (!verified && mib === lastMiB) return;
    lastMiB = mib;
    console.log(`FILE_${label}_${verified ? 'VERIFIED' : 'PROGRESS'} ${bytes}/${total}`);
  };
}

// Ctrl+C during a one-shot transfer cancels the encrypted read and lets the
// receiver remove its temporary .part file instead of exiting mid-write.
async function withTransferCancellation(run) {
  const controller = new AbortController();
  const cancel = () => controller.abort();
  process.on('SIGINT', cancel);
  process.on('SIGTERM', cancel);
  try { return await run(controller.signal); }
  finally {
    process.off('SIGINT', cancel);
    process.off('SIGTERM', cancel);
  }
}

async function interact(socket,role) {
  try {
    const {fingerprint,channel,known,peerIntent}=await pairSocket(socket,{role,identity,trustStore:trusted,onCode:approve,
      intent:role==='client' ? ((opt('send-file') || opt('send-folder')) ? 'file' : flag('send-clipboard') ? 'clipboard' : null) : null});
    saveTrust();
    console.log(`PAIR_OK ${fingerprint.slice(0,20)} (${known?'recognized':'new'}) — encrypted channel active`);
    if(role==='client') {
      channel.send({type:'PING',sentAt:Date.now()});
      const response=await channel.receive();
      if(response?.type!=='PONG')throw new Error('Unexpected secure response');
      console.log('SECURE_PONG received; no remote access permission was granted');
      if(opt('send-file')) {
        const sent=await withTransferCancellation(signal=>sendFileOnce(channel,opt('send-file'),
          {onProgress:fileProgress('SEND'),signal}));
        console.log('FILE_TRANSFER_VERIFIED',sent.bytes,sent.sha256);
        return;
      }
      if(opt('send-folder')) {
        const sent=await withTransferCancellation(signal=>sendFolderOnce(channel,opt('send-folder'),
          {signal,onProgress:p=>console.log('FOLDER_SEND_PROGRESS',p.files,p.totalFiles,p.bytes,p.totalBytes)}));
        console.log('FOLDER_TRANSFER_VERIFIED',sent.count,sent.bytes);
        return;
      }
      if(flag('send-clipboard')) {
        // One line entered interactively: never put private text in CLI args, logs or files.
        const text=await askWithDeadline(rl.question.bind(rl),
          'Text to send once to the Android clipboard (max 2048 UTF-8 bytes, 45s): ');
        clipboardByteLength(text);
        channel.send({type:'CLIPBOARD_PUT',text});
        const result=await channel.receive();
        if(result?.type==='CLIPBOARD_DENIED')throw new Error('Android user denied clipboard transfer');
        if(result?.type!=='CLIPBOARD_OK'||result.bytes!==Buffer.byteLength(text,'utf8'))
          throw new Error('Android clipboard acknowledgement invalid');
        console.log('ANDROID_CLIPBOARD_WRITTEN_WITH_CONSENT');
      }
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
      if(opt('receive-folder')) {
        requireSignedIntent(peerIntent,'file');
        const begin=await channel.receive();
        const received=await withTransferCancellation(signal=>receiveFolderOnce(channel,begin,{
          directory:opt('receive-folder'),signal,
          onProgress:p=>console.log('FOLDER_RECEIVE_PROGRESS',p.files,p.totalFiles,p.bytes,p.totalBytes),
          approve:async ({folder,count,bytes})=>{
            console.log('Folder offer',folder,count,'files',bytes,'bytes from',fingerprint.slice(0,20));
            const answer=await askWithDeadline(rl.question.bind(rl),
              'To receive this entire folder (max 64 files, 256 MiB), type FOLDER: (45s) ');
            return answer==='FOLDER';
          }
        }));
        console.log(received?'FOLDER_RECEIVED_VERIFIED':'FOLDER_DENIED',received?.count??0);
        return;
      }
      if(opt('receive-file')) {
        requireSignedIntent(peerIntent, 'file');
        const offer=await channel.receive();
        const received=await withTransferCancellation(signal=>receiveFileOnce(channel,offer,{
          directory:opt('receive-file'),
          signal,
          onProgress:fileProgress('RECEIVE'),
          approve:async ({name,bytes})=>{
            console.log('One-shot file offer from',fingerprint.slice(0,20),name,bytes,'bytes');
            const answer=await askWithDeadline(rl.question.bind(rl),
              'To receive this file into the selected folder, type FILE: (45s) ');
            return answer==='FILE';
          }
        }));
        console.log(received ? 'FILE_RECEIVED_VERIFIED' : 'FILE_DENIED',received?.bytes ?? 0);
        return;
      }
      if(flag('receive-clipboard')) {
        // Trusted pairing alone never authorizes a privileged clipboard session.
        requireSignedIntent(peerIntent, 'clipboard');
        const req = await channel.receive();
        // A separate --revoke process edits trusted.json while this listener
        // remains alive. Re-check pinned identity on disk at consent, write,
        // and ACK boundaries; never trust the stale in-memory Map alone.
        const clipboardSessionActive = () => {
          if (socket.destroyed || socket.writableEnded || !trusted.has(fingerprint)) return false;
          try {
            const current=JSON.parse(fs.readFileSync(trustFile,'utf8'));
            return Object.hasOwn(current,fingerprint) &&
              current[fingerprint]===trusted.get(fingerprint);
          } catch { return false; }
        };
        const accepted = await withTransferCancellation(signal=>
          acceptClipboardRequest(channel, req, {
            signal, isSessionActive:clipboardSessionActive,
            approve: async () => {
              console.log('One-shot clipboard request from paired peer', fingerprint.slice(0, 20));
              const answer = await askWithDeadline(rl.question.bind(rl),
                'To replace THIS Windows clipboard once, type CLIP: (45s) ');
              return answer === 'CLIP';
            },
            writeClipboard: writeWindowsClipboard,
          }));
        console.log(accepted ? 'CLIPBOARD_WRITTEN_WITH_CONSENT' : 'CLIPBOARD_DENIED');
        return;
      }
      if(flag('share-screen') || flag('share-h264')) {
        const req=await channel.receive();
        if(req?.type==='H264_START') {
          if(!flag('share-h264') || req.mode!=='view-only' ||
             !Number.isInteger(req.seconds) || req.seconds<1 || req.seconds>10) {
            channel.send({type:'H264_DENIED'});
            throw Error('H.264 view-only access denied by host policy');
          }
          console.log(`\nH.264 VIEW-ONLY request from ${fingerprint.slice(0,20)}... (${req.seconds}s)`);
          const consent=await askWithDeadline(rl.question.bind(rl),
            'To share THIS session only, type H264: (45s) ');
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
        const answer=await askWithDeadline(rl.question.bind(rl),
          'To allow your screen to be shared THIS SESSION, type SHARE: (45s) ');
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
if((opt('send-file') || opt('send-folder')) &&
   (Boolean(opt('send-file')) === Boolean(opt('send-folder')) || flag('send-clipboard') ||
    flag('view-screen') || flag('view-h264') || flag('watch-h264') || flag('listen'))) {
  throw new Error('One-shot file sending requires a separate client session');
}
if((opt('receive-file') || opt('receive-folder')) &&
   (Boolean(opt('receive-file')) === Boolean(opt('receive-folder')) || flag('receive-clipboard') ||
    flag('share-screen') || flag('share-h264') || !flag('listen'))) {
  throw new Error('One-shot file receiving requires a separate host session');
}
if(flag('send-clipboard') && (flag('view-screen') || flag('view-h264') || flag('watch-h264') || flag('listen'))) {
  throw new Error('One-shot clipboard sending requires a separate client session');
}
if(flag('receive-clipboard') && (flag('share-screen') || flag('share-h264'))) {
  throw new Error('Clipboard and screen sharing require separate host sessions');
}
// A fresh listener owns this destination exclusively (one session at a time).
// Reclaim only verifiably old, marked staging directories BEFORE opening the
// listener; never run the cleaner concurrently with a live receive.
if (flag('listen') && opt('receive-folder')) {
  const recovered=await cleanupStaleFolderTransfers(opt('receive-folder'));
  console.log('FOLDER_STAGING_RECOVERY',
    'removed='+recovered.removed,'skipped='+recovered.skipped);
}
if(flag('listen')) {
  const server=net.createServer();
  let busy=false;
  server.on('connection',socket=>{
    if(!isLanIpv4(socket.remoteAddress)){socket.destroy();return;}
    if(busy){socket.destroy();return;}
    busy=true;
    interact(socket,'server').finally(()=>{busy=false;});
  });
  let presence;
  server.listen(port,'0.0.0.0',async()=>{
    console.log(`PAIR_AGENT_READY ${port}; local consent required on both devices${flag('share-screen') ? '; MJPEG sharing requires SHARE' : ''}${flag('share-h264') ? '; H.264 sharing requires H264' : ''}${flag('receive-clipboard') ? '; clipboard requires CLIP' : ''}${opt('receive-file') ? '; file receiving requires FILE' : ''}`);
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
  if(!isLanIpv4(host))throw new Error('LAN-only pairing requires a private or loopback IPv4 address');
  const socket=net.createConnection({host,port:connectPort});
  await interact(socket,'client');rl.close();
} else {
  console.log('Usage: node pair_agent.mjs --listen [--no-discovery] [--share-screen] [--share-h264] [--receive-clipboard] [--encoder=libx264|h264_nvenc] [--test-pattern] [--port=43829] | --connect=IP[:port] [--view-screen --max-frames=2 --output=frame.jpg] | --connect=IP[:port] --send-clipboard | --connect=IP[:port] --view-h264 [--watch-h264] --max-seconds=3 [--output=clip.ts] | --listen --receive-file=EXISTING_FOLDER | --connect=IP[:port] --send-file=FILE | --listen --receive-folder=EXISTING_FOLDER | --connect=IP[:port] --send-folder=FOLDER | --list | --revoke=<fingerprint>');
  rl.close();process.exitCode=1;
}
