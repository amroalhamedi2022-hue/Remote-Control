package com.example.liquid_remote_control

/** Cancellable handle returned by the stage-idle scheduler. */
internal fun interface StageLeaseCancellation {
    fun cancel()
}

/** Small scheduler seam so lease generation/race behavior is tested without Android. */
internal fun interface StageLeaseScheduler {
    fun schedule(delayMillis: Long, action: () -> Unit): StageLeaseCancellation
}

/**
 * One-shot inactivity lease for private incoming-file staging. Every accepted chunk
 * refreshes it; stale timer callbacks cannot expire a refreshed or closed lease.
 */
internal class IdleStageLease(
    private val timeoutMillis: Long,
    private val scheduler: StageLeaseScheduler,
    private val onExpired: () -> Unit,
) {
    private val lock = Any()
    private var generation = 0L
    private var closed = false
    private var pending: StageLeaseCancellation? = null

    init { require(timeoutMillis > 0L) { "Stage idle timeout must be positive" } }

    fun touch() {
        synchronized(lock) {
            if (closed) return
            generation++
            val token = generation
            pending?.cancel()
            pending = null
            pending = scheduler.schedule(timeoutMillis) { expire(token) }
        }
    }

    private fun expire(token: Long) {
        val shouldExpire = synchronized(lock) {
            if (closed || token != generation) false
            else {
                closed = true
                pending = null
                true
            }
        }
        if (shouldExpire) onExpired()
    }

    fun close() {
        synchronized(lock) {
            if (closed) return
            closed = true
            generation++
            pending?.cancel()
            pending = null
        }
    }
}
