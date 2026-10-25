// Shared, platform-independent lifecycle policy for local screen-capture child processes.
// Does not shell out or add dependencies. Call requestStop on trust revocation/disconnect,
// and cleanup in finally; process exit is determined by exitCode/signalCode, not child.killed.
export function createChildLifecycle(child, {graceMs = 500} = {}) {
  let terminationRequested = false;
  let forceKillTimer;

  const clearTimer = () => {
    if (forceKillTimer) {
      clearTimeout(forceKillTimer);
      forceKillTimer = undefined;
    }
  };
  child.once('close', clearTimer);

  function requestStop() {
    if (terminationRequested) return;
    terminationRequested = true;
    // Arm escalation before sending the first signal so even a synchronous close
    // event (for injected/test children) cannot leave an unnecessary timer behind.
    forceKillTimer = setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        try { child.kill('SIGKILL'); } catch { /* cleanup also makes a final attempt */ }
      }
    }, graceMs);
    forceKillTimer.unref?.();
    try { child.kill(); } catch { /* cleanup rechecks the actual process state */ }
  }

  function cleanup() {
    clearTimer();
    // child.killed only says that a signal was sent. It does not prove exit.
    if (child.exitCode === null && child.signalCode === null) {
      try { child.kill('SIGKILL'); } catch { /* preserve the original capture error */ }
    }
  }

  return {
    requestStop,
    cleanup,
    get terminationRequested() { return terminationRequested; }
  };
}
