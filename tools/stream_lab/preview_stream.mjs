// Experimental, low-FPS screen preview, NOT production video transport.
// Requires explicitly approved authenticated pairing and an additional host SHARE confirmation.
import { spawn } from 'node:child_process';

export const MAX_JPEG_BYTES = 512 * 1024;
export const CHUNK_BYTES = 2600;
const MAX_BACKLOG = 512 * 1024;
const SOI = Buffer.from([0xff, 0xd8]);
const EOI = Buffer.from([0xff, 0xd9]);

export class JpegFrames {
  constructor(onFrame) { this.onFrame = onFrame; this.pending = Buffer.alloc(0); this.frames=0; }
  push(chunk) {
    this.pending = Buffer.concat([this.pending, chunk]);
    while (this.pending.length > 0) {
      const start = this.pending.indexOf(SOI);
      if (start < 0) { this.pending=this.pending.subarray(Math.max(0,this.pending.length-1)); return; }
      if (start > 0) this.pending=this.pending.subarray(start);
      const end = this.pending.indexOf(EOI, 2);
      if (end === -1) {
        if (this.pending.length > MAX_JPEG_BYTES) throw new Error('JPEG oversized / corrupted');
        return;
      }
      const jpg=this.pending.subarray(0,end+2);
      this.pending=this.pending.subarray(end+2);
      if (jpg.length>MAX_JPEG_BYTES) throw new Error('JPEG frame exceeds bound');
      this.onFrame(Buffer.from(jpg), this.frames++);
    }
  }
}

export function captureArguments({testPattern=false,fps=4,width=640,quality=10}={}) {
  if(!Number.isInteger(fps)||fps<1||fps>15)throw new Error('Bad fps');
  if(!Number.isInteger(width)||width<160||width>1280||width%2)throw new Error('Bad width');
  if(!Number.isInteger(quality)||quality<3||quality>24)throw new Error('Bad jpeg quality');
  const input=testPattern ? ['-f','lavfi','-i',`testsrc2=size=1280x720:rate=${fps}`]
    : ['-f','gdigrab','-framerate',String(fps),'-i','desktop'];
  return ['-hide_banner','-loglevel','error','-nostdin',...input,
    '-vf',`scale=${width}:-2:flags=fast_bilinear`,'-an','-c:v','mjpeg','-q:v',String(quality),
    '-f','image2pipe','pipe:1'];
}

export function jpegMessages(jpeg,id) {
  if(!Buffer.isBuffer(jpeg)||jpeg.length<4||jpeg.length>MAX_JPEG_BYTES||
    !jpeg.subarray(0,2).equals(SOI)||!jpeg.subarray(-2).equals(EOI))throw new Error('Invalid JPEG');
  if(!Number.isSafeInteger(id)||id<0)throw new Error('Bad frame id');
  const messages=[{type:'FRAME_BEGIN',id,bytes:jpeg.length}];
  for(let p=0;p<jpeg.length;p+=CHUNK_BYTES) {
    messages.push({type:'FRAME_PART',id,offset:p,data:jpeg.subarray(p,p+CHUNK_BYTES).toString('base64url')});
  }
  messages.push({type:'FRAME_END',id});
  return messages;
}

export class PreviewAssembler {
  constructor(onFrame){this.onFrame=onFrame;this.frame=null;this.lastId=-1;}
  ingest(msg){
    if(msg?.type==='FRAME_BEGIN'){
      if(!Number.isSafeInteger(msg.id)||msg.id<=this.lastId||
         !Number.isInteger(msg.bytes)||msg.bytes<4||msg.bytes>MAX_JPEG_BYTES)throw Error('Bad frame header');
      this.frame={id:msg.id,bytes:msg.bytes,received:0,parts:[]};return;
    }
    if(msg?.type==='FRAME_PART'){
      if(!this.frame||msg.id!==this.frame.id||msg.offset!==this.frame.received||
         typeof msg.data!=='string'||msg.data.length>4000||!(/^[A-Za-z0-9_-]+$/).test(msg.data)) throw Error('Bad frame part');
      const part=Buffer.from(msg.data,'base64url');
      if(part.length>CHUNK_BYTES||this.frame.received+part.length>this.frame.bytes)throw Error('Frame overflow');
      this.frame.parts.push(part);this.frame.received+=part.length;return;
    }
    if(msg?.type==='FRAME_END'){
      if(!this.frame||msg.id!==this.frame.id||this.frame.received!==this.frame.bytes)throw Error('Incomplete frame');
      const jpeg=Buffer.concat(this.frame.parts);
      if(!jpeg.subarray(0,2).equals(SOI)||!jpeg.subarray(-2).equals(EOI))throw Error('Invalid JPEG boundaries');
      this.lastId=msg.id;this.frame=null;this.onFrame(jpeg);return;
    }
    throw Error('Unexpected preview message');
  }
}

/** Source process must be killed on disconnect. Backpressure drops whole frames, never partial frames.
 * Encrypted envelope uses small chunks, so each underlying JsonLine remains <8KB.
 */
export async function sendPreview(channel,socket,{testPattern=false,fps=4,width=640,quality=10,ffmpeg='ffmpeg',maxFrames=Infinity}={}) {
  const args=captureArguments({testPattern,fps,width,quality});
  const child=spawn(ffmpeg,args,{stdio:['ignore','pipe','pipe'],windowsHide:true});
  let stderr='';let stopped=false;let sent=0;let dropped=0;
  const done = new Promise((resolve,reject)=>{
    child.on('error',reject);
    child.on('close',code=>resolve(code));
  });
  // A missing/broken FFmpeg executable can emit 'error' before stdout's
  // async iterator finishes. Attach a rejection handler immediately so Node
  // does not terminate on an unhandled rejection; the later await still throws.
  void done.catch(() => {});
  child.stderr.on('data',b=>{stderr+=b.toString().slice(0,512);stderr=stderr.slice(-2048);});
  let parser;
  try{
    parser=new JpegFrames((jpeg,id)=>{
      if(stopped)return;
      if(sent>=maxFrames){stopped=true;child.kill();return;}
      if(socket.destroyed||socket.writableLength>MAX_BACKLOG){dropped++;return;}
      for (const message of jpegMessages(jpeg,id))channel.send(message);
      sent++;
    });
    for await (const chunk of child.stdout){
      if(socket.destroyed||stopped)break;
      parser.push(chunk);
    }
    if(!child.killed&&!stopped)await done;
  }finally{
    if(!child.killed)child.kill();
  }
  if(sent===0&&!socket.destroyed)throw new Error('No frames captured. '+stderr.slice(-220));
  return {sent,dropped};
}
