import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { createChildLifecycle } from './child_lifecycle.mjs';

function fakeChild({ignoreGraceful = false} = {}) {
  const child = new EventEmitter();
  child.exitCode = null;
  child.signalCode = null;
  child.killed = false;
  child.signals = [];
  child.kill = signal => {
    child.killed = true;
    child.signals.push(signal ?? null);
    if (signal === 'SIGKILL' || !ignoreGraceful) {
      child.signalCode = signal ?? 'SIGTERM';
      queueMicrotask(() => child.emit('close', null, child.signalCode));
    }
    return true;
  };
  return child;
}

test('capture lifecycle escalates if graceful termination is ignored', {timeout: 2000}, async () => {
  const keepAlive = setTimeout(() => {}, 1000); // production child handles keep the event loop alive
  try {
    const child = fakeChild({ignoreGraceful: true});
    const lifecycle = createChildLifecycle(child, {graceMs: 20});
    const closed = once(child, 'close');
    lifecycle.requestStop();
    await closed;
    assert.deepEqual(child.signals, [null, 'SIGKILL']);
    assert.equal(child.signalCode, 'SIGKILL');
    assert.equal(lifecycle.terminationRequested, true);
    lifecycle.cleanup();
    assert.deepEqual(child.signals, [null, 'SIGKILL']);
  } finally { clearTimeout(keepAlive); }
});

test('capture lifecycle does not escalate after graceful close', {timeout: 2000}, async () => {
  const keepAlive = setTimeout(() => {}, 1000);
  try {
    const child = fakeChild();
    const lifecycle = createChildLifecycle(child, {graceMs: 40});
    const closed = once(child, 'close');
    lifecycle.requestStop();
    await closed;
    await new Promise(resolve => setTimeout(resolve, 60));
    assert.deepEqual(child.signals, [null]);
    assert.equal(child.signalCode, 'SIGTERM');
  } finally { clearTimeout(keepAlive); }
});

test('cleanup force-stops a still-live child and clears pending escalation timer', {timeout: 2000}, async () => {
  const keepAlive = setTimeout(() => {}, 1000);
  try {
    const child = fakeChild({ignoreGraceful: true});
    const lifecycle = createChildLifecycle(child, {graceMs: 1000});
    lifecycle.requestStop();
    const closed = once(child, 'close');
    lifecycle.cleanup();
    await closed;
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.deepEqual(child.signals, [null, 'SIGKILL']);
    assert.equal(child.signalCode, 'SIGKILL');
  } finally { clearTimeout(keepAlive); }
});
