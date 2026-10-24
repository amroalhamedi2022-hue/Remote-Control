import test from 'node:test';
import assert from 'node:assert/strict';
import {askWithDeadline} from './consent_prompt.mjs';

test('approval trims an explicit answer and forwards AbortSignal', async () => {
  let passedSignal = false;
  const answer = await askWithDeadline(async (_prompt, {signal}) => {
    passedSignal = signal instanceof AbortSignal;
    return '  YES  ';
  }, 'Approve?', 100);
  assert.equal(answer, 'YES');
  assert.equal(passedSignal, true);
});

test('an unanswered approval is denied on deadline', async () => {
  const started = Date.now();
  const answer = await askWithDeadline((_prompt, {signal}) => new Promise((_resolve, reject) => {
    signal.addEventListener('abort', () => reject(new Error('aborted')), {once: true});
  }), 'Approve?', 15);
  assert.equal(answer, null);
  assert.ok(Date.now() - started < 1000);
});

test('ordinary input errors are not disguised as a user denial', async () => {
  await assert.rejects(
    askWithDeadline(async () => {throw new Error('input closed');}, 'Approve?', 100),
    /input closed/
  );
  await assert.rejects(askWithDeadline(async () => 'YES', 'Approve?', 0), RangeError);
});
