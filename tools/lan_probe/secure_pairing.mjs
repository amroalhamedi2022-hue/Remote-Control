// Experimental cryptographic interoperability fixture; NOT production audited.
// Authenticated ephemeral X25519 + signed Ed25519 hello + 6-digit locally compared SAS.
// AES-256-GCM envelopes only after explicit approval on BOTH devices. No remote control APIs.
import crypto from 'node:crypto';

export const PAIR_PROTOCOL = 'liquidremote.pair.v1';
const MAX_LINE = 8192;
const MAX_TIMEOUT_MS = 120_000;
const b64 = b => Buffer.from(b).toString('base64url');
const unb64 = s => Buffer.from(s, 'base64url');
const sha = b => crypto.createHash('sha256').update(b).digest();
const json = x => JSON.stringify(x);
const safeB64 = s => typeof s === 'string' && s.length < 256 && /^[A-Za-z0-9_-]+$/.test(s);

export function generateIdentity() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  return {
    publicKey: b64(publicKey.export({type: 'spki', format: 'der'})),
    privateKey: b64(privateKey.export({type: 'pkcs8', format: 'der'})),
  };
}
export function identityFingerprint(publicKey) {
  return sha(unb64(publicKey)).toString('hex');
}
function privateIdentity(identity) {
  const key = crypto.createPrivateKey({key:unb64(identity.privateKey),type:'pkcs8',format:'der'});
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('Identity key must be Ed25519');
  return key;
}
function validateHello(h, kind) {
  if (!h || typeof h !== 'object' || Array.isArray(h) || h.v !== PAIR_PROTOCOL || h.type !== kind ||
      !safeB64(h.identity) || !safeB64(h.ephemeral) || !safeB64(h.nonce) || !safeB64(h.sig))
    throw new Error('Bad signed hello');
  if (kind === 'SERVER_HELLO' && (!safeB64(h.clientHash) || unb64(h.clientHash).length !== 32))
    throw new Error('Unbound server hello');
  if (unb64(h.nonce).length !== 24) throw new Error('Bad nonce');
  const identity = crypto.createPublicKey({key:unb64(h.identity),type:'spki',format:'der'});
  const ephemeral = crypto.createPublicKey({key:unb64(h.ephemeral),type:'spki',format:'der'});
  if (identity.asymmetricKeyType !== 'ed25519' || ephemeral.asymmetricKeyType !== 'x25519')
    throw new Error('Unexpected public key type');
  const {sig, ...signed} = h;
  if (!crypto.verify(null, Buffer.from(json(signed)), identity, unb64(sig)))
    throw new Error('Invalid identity signature');
  return ephemeral;
}
function createHello(kind, identity, ephemeralPublic, clientHash) {
  const unsigned = {
    v: PAIR_PROTOCOL, type:kind, identity:identity.publicKey,
    ephemeral:b64(ephemeralPublic.export({type:'spki',format:'der'})),
    nonce:b64(crypto.randomBytes(24)),
    ...(clientHash ? {clientHash} : {}),
  };
  return {...unsigned, sig:b64(crypto.sign(null,Buffer.from(json(unsigned)),privateIdentity(identity)))};
}

class JsonLines {
  constructor(socket) {
    this.socket=socket;this.buffer='';this.queue=[];this.waiter=null;this.dead=false;this.reason=null;
    socket.setTimeout(MAX_TIMEOUT_MS,()=>socket.destroy(new Error('Idle timeout')));
    socket.on('data', data=>{
      if (this.dead) return;
      this.buffer+=data.toString('utf8');
      let i;
      while ((i=this.buffer.indexOf('\n'))>=0) {
        const line=this.buffer.slice(0,i);this.buffer=this.buffer.slice(i+1);
        if (Buffer.byteLength(line)>MAX_LINE) return socket.destroy(new Error('Oversized frame'));
        if(this.waiter){const f=this.waiter;this.waiter=null;f.resolve(line);}else this.queue.push(line);
        if (this.queue.length > 512) return socket.destroy(new Error('Too many queued frames'));
      }
      // Only the unfinished line is size-limited here: TCP can coalesce many valid lines.
      if (Buffer.byteLength(this.buffer)>MAX_LINE) socket.destroy(new Error('Oversized message'));
    });
    socket.on('error',err=>this.close(err));
    socket.on('close',()=>this.close(new Error('Connection closed')));
  }
  close(err) {this.dead=true;this.reason=err;if(this.waiter){this.waiter.reject(err);this.waiter=null;}}
  async receive() {
    if(this.queue.length) return this.parse(this.queue.shift());
    if(this.dead) throw this.reason || new Error('Closed');
    const line=await new Promise((resolve,reject)=>this.waiter={resolve,reject});
    return this.parse(line);
  }
  parse(line) {try{const x=JSON.parse(line);if(!x || typeof x !== 'object' || Array.isArray(x))throw 0;return x;}catch{throw new Error('Invalid JSON frame');}}
  send(x) {if(this.dead)throw this.reason;const line=json(x)+'\n';if(Buffer.byteLength(line)>MAX_LINE)throw new Error('Oversized output');this.socket.write(line);}
}

function secrets(shared, hash, role) {
  const k = tag => Buffer.from(crypto.hkdfSync('sha256', shared, hash, `liquidremote/v1/${tag}`,32));
  return {sendKey:k(role==='client'?'c2s':'s2c'), recvKey:k(role==='client'?'s2c':'c2s'),
    sendDir:role==='client'?'C2S1':'S2C1', recvDir:role==='client'?'S2C1':'C2S1'};
}
function nonce(direction, seq) {
  const n=Buffer.alloc(12);
  n.write(direction,0,'ascii');n.writeBigUInt64BE(BigInt(seq),4);
  return n;
}
export class SecureEnvelope {
  constructor(lines, shared, transcriptHash, role) {
    this.lines=lines;this.keys=secrets(shared,transcriptHash,role);
    this.sent=0;this.received=0;this.failed=false;
  }
  // A rejected frame is a terminal authentication failure, not a recoverable
  // parsing error. Never accept later frames on a poisoned encrypted channel.
  failClosed(error) {
    this.failed=true;
    this.lines.socket.destroy();
    throw error;
  }
  send(message) {
    if(this.failed)throw new Error('Encrypted session closed');
    try {
      if(this.sent>=Number.MAX_SAFE_INTEGER)throw new Error('Nonce counter exhausted');
      const seq=this.sent;
      const cipher=crypto.createCipheriv('aes-256-gcm',this.keys.sendKey,nonce(this.keys.sendDir,seq));
      cipher.setAAD(Buffer.from(`${PAIR_PROTOCOL}|${this.keys.sendDir}|${seq}`));
      const payload=Buffer.concat([cipher.update(Buffer.from(json(message))),cipher.final(),cipher.getAuthTag()]);
      this.lines.send({type:'SEALED',seq,data:b64(payload)});
      this.sent++;
    } catch(error) {this.failClosed(error);}
  }
  async receive() {
    if(this.failed)throw new Error('Encrypted session closed');
    try {
      const frame=await this.lines.receive();
      if(frame.type!=='SEALED'||frame.seq!==this.received||typeof frame.data!=='string'||frame.data.length>10000||!(/^[A-Za-z0-9_-]+$/).test(frame.data))
        throw new Error('Unexpected or replayed encrypted frame');
      const bytes=unb64(frame.data);
      if(bytes.length<16)throw new Error('Truncated encrypted frame');
      const seq=this.received;
      const decipher=crypto.createDecipheriv('aes-256-gcm',this.keys.recvKey,nonce(this.keys.recvDir,seq));
      decipher.setAAD(Buffer.from(`${PAIR_PROTOCOL}|${this.keys.recvDir}|${seq}`));
      decipher.setAuthTag(bytes.subarray(-16));
      let output;
      try{output=Buffer.concat([decipher.update(bytes.subarray(0,-16)),decipher.final()]);}
      catch{throw new Error('Unauthenticated ciphertext');}
      let message;
      try{message=JSON.parse(output.toString('utf8'));}
      catch{throw new Error('Invalid encrypted payload');}
      this.received++;
      return message;
    } catch(error) {this.failClosed(error);}
  }
}

/** Both parties MUST independently compare the locally calculated code before approving.
 * The callback must represent local human consent. Never use remote-provided approval alone.
 * trustStore: optional Map<fingerprint, publicKey>; written only after both confirmations.
 */
export async function pairSocket(socket,{role,identity,onCode,trustStore=new Map(),debugHooks={},consentTimeoutMs=MAX_TIMEOUT_MS}) {
  if(!['client','server'].includes(role))throw new Error('Invalid role');
  if(typeof onCode!=='function')throw new Error('Local consent callback required');
  if(!Number.isSafeInteger(consentTimeoutMs) || consentTimeoutMs < 1 || consentTimeoutMs > MAX_TIMEOUT_MS)
    throw new Error('Invalid pairing consent timeout');
  const io=new JsonLines(socket);
  const keys=crypto.generateKeyPairSync('x25519');
  let hello, reply, otherPub;
  try {
    if(role==='client') {
      hello=createHello('CLIENT_HELLO',identity,keys.publicKey);
      io.send(debugHooks.mutateHello?.(hello)??hello);
      reply=await io.receive();
      otherPub=validateHello(reply,'SERVER_HELLO');
      if(reply.clientHash!==b64(sha(Buffer.from(json(hello)))))throw new Error('Server hello not bound to client');
    } else {
      hello=await io.receive();
      otherPub=validateHello(hello,'CLIENT_HELLO');
      reply=createHello('SERVER_HELLO',identity,keys.publicKey,b64(sha(Buffer.from(json(hello)))));
      io.send(debugHooks.mutateReply?.(reply)??reply);
    }
    const otherIdentity=role==='client'?reply.identity:hello.identity;
    const fingerprint=identityFingerprint(otherIdentity);
    // Peers with same discovery name but different identity are NOT equivalent.
    if(trustStore.has(fingerprint)&&trustStore.get(fingerprint)!==otherIdentity)
      throw new Error('Pinned identity mismatch');
    const transcriptHash=sha(Buffer.from(json([hello,reply])));
    const shared=crypto.diffieHellman({privateKey:keys.privateKey,publicKey:otherPub});
    const code = crypto.createHmac('sha256',shared).update(transcriptHash).digest().readUInt32BE(0)%1_000_000;
    const sas=String(code).padStart(6,'0');
    // No encrypted CONFIRM without LOCAL approval. Never silently accept on first contact.
    // A stalled permission UI must never leave a pairing socket and ephemeral
    // handshake pending forever. Consent is local and time-bounded; timing out
    // destroys the socket without pinning an identity or opening a channel.
    let consentTimer;
    const approved=await Promise.race([
      Promise.resolve().then(()=>onCode({sas, fingerprint,known:trustStore.get(fingerprint)===otherIdentity})),
      new Promise((_,reject)=>{
        consentTimer=setTimeout(()=>reject(new Error('Pairing consent timed out')),consentTimeoutMs);
      }),
    ]).finally(()=>clearTimeout(consentTimer));
    if(approved!==true)throw new Error('Local user declined pairing');
    const channel=new SecureEnvelope(io,shared,transcriptHash,role);
    channel.send({type:'CONFIRM'});
    const confirmation=await channel.receive();
    if(confirmation?.type!=='CONFIRM')throw new Error('Remote peer did not confirm');
    const wasKnown=trustStore.get(fingerprint)===otherIdentity;
    trustStore.set(fingerprint,otherIdentity);
    return {fingerprint, sas, channel, known:wasKnown};
  }catch(err){socket.destroy();throw err;}
}
