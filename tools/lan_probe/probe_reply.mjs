// Strict parser for the unauthenticated LAN reachability probe.
// Accept only one exact PONG line followed by EOF. This is not pairing or authorization.
export function readExactPong(socket, timeoutMs = 1500) {
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120000) {
    return Promise.resolve(false);
  }
  return new Promise(resolve => {
    let settled = false;
    let lineEnded = false;
    let validLine = false;
    const received = [];
    const timer = setTimeout(() => finish(false), timeoutMs);

    function cleanup() {
      clearTimeout(timer);
      socket.off('data', onData);
      socket.off('end', onEnd);
      socket.off('error', onError);
      socket.off('timeout', onTimeout);
      socket.off('close', onClose);
    }
    function finish(result) {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(result);
    }
    function onData(chunk) {
      if (!(Buffer.isBuffer(chunk) || chunk instanceof Uint8Array)) {
        finish(false);
        return;
      }
      for (const byte of chunk) {
        // PONG\\n is 5 bytes; PONG\\r\\n is 6. No extra byte is ever retained.
        if (lineEnded || received.length >= 6) {
          finish(false);
          return;
        }
        received.push(byte);
        if (byte === 10) {
          lineEnded = true;
          validLine = (received.length === 5 &&
              received[0] === 80 && received[1] === 79 &&
              received[2] === 78 && received[3] === 71) ||
            (received.length === 6 &&
              received[0] === 80 && received[1] === 79 &&
              received[2] === 78 && received[3] === 71 &&
              received[4] === 13);
          if (!validLine) {
            finish(false);
            return;
          }
        }
      }
    }
    function onEnd() { finish(lineEnded && validLine); }
    function onError() { finish(false); }
    function onTimeout() { finish(false); }
    function onClose() { finish(false); }

    socket.on('data', onData);
    socket.on('end', onEnd);
    socket.on('error', onError);
    socket.on('timeout', onTimeout);
    socket.on('close', onClose);
  });
}
