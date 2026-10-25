// Human approval must not block the LAN listener indefinitely.
// The AbortSignal is supported by Node 22 readline/promises.question().
export async function askWithDeadline(question, prompt, timeoutMs = 45_000) {
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120_000) {
    throw new RangeError('Invalid approval timeout');
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const answer = await question(prompt, {signal: controller.signal});
    return typeof answer === 'string' ? answer.trim() : null;
  } catch (error) {
    if (controller.signal.aborted) return null;
    throw error;
  } finally {
    clearTimeout(timer);
  }
}
