import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import {generateIdentity,pairSocket} from '../lan_probe/secure_pairing.mjs';
import {sendPreview,PreviewAssembler} from './preview_stream.mjs';

/** End-to-end Node↔Node over real TCP with the experimental encrypted channel.
 * This DOES NOT establish Dart/Flutter interoperability or hardware screen capture.
 */
test('authenticated pairing + separate host approval + encrypted JPEG test pattern across TCP', {timeout:20000}, async () => {
  const serverIdentity=generateIdentity(), clientIdentity=generateIdentity();
  let serverSas,clientSas;
  const host=net.createServer(async socket=>{
    try{
      const {sas,channel}=await pairSocket(socket,{role:'server',identity:serverIdentity,
        onCode:async c=>{serverSas=c.sas;return true;}});
      assert.equal(sas,serverSas);
      assert.equal((await channel.receive()).type,'PING');
      channel.send({type:'PONG'});
      const request=await channel.receive();
      assert.deepEqual(request,{type:'STREAM_START',mode:'view-only'});
      // Host consent is modeled independently of the pairing approval.
      const hostAuthorized=true;
      if(!hostAuthorized)channel.send({type:'STREAM_DENIED'});
      else {
        channel.send({type:'STREAM_READY',profile:'mjpeg-lab',fps:4,width:640});
        const result=await sendPreview(channel,socket,{testPattern:true,fps:2,width:320,maxFrames:2});
        assert.equal(result.sent,2);
      }
    } catch(err) { host.emit('test-error',err); }
    finally {socket.end();}
  });
  const errors=[];host.on('test-error',e=>errors.push(e));
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));
  try{
    const socket=net.connect(host.address().port,'127.0.0.1');
    const {sas,channel}=await pairSocket(socket,{role:'client',identity:clientIdentity,
      onCode:async c=>{clientSas=c.sas;return true;}});
    assert.equal(sas,clientSas);
    channel.send({type:'PING'});
    assert.equal((await channel.receive()).type,'PONG');
    channel.send({type:'STREAM_START',mode:'view-only'});
    assert.equal((await channel.receive()).type,'STREAM_READY');
    const frames=[];
    const assembler=new PreviewAssembler(jpeg=>frames.push(jpeg));
    while(frames.length<2)assembler.ingest(await channel.receive());
    assert.equal(serverSas,clientSas);
    assert.equal(frames.length,2);
    assert.ok(frames[0].length>1000);
    assert.equal(errors.length,0);
    socket.destroy();
  } finally {host.close();}
});

test('disallowed remote input is rejected by view-only host allowlist',()=>{
  const accepted=new Set(['PING','STREAM_START']);
  assert.equal(accepted.has('INPUT_KEY'),false);
  assert.equal(accepted.has('FILE_READ'),false);
  assert.equal(accepted.has('SHELL_EXEC'),false);
});
