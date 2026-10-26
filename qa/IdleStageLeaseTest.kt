package com.example.liquid_remote_control

private class FakeStageLeaseScheduler : StageLeaseScheduler {
    data class Task(val delayMillis: Long, val action: () -> Unit, var cancelled: Boolean = false)
    val tasks = mutableListOf<Task>()

    override fun schedule(delayMillis: Long, action: () -> Unit): StageLeaseCancellation {
        val task = Task(delayMillis, action)
        tasks += task
        return StageLeaseCancellation { task.cancelled = true }
    }

    fun fire(task: Task, evenIfCancelled: Boolean = false) {
        if (!task.cancelled || evenIfCancelled) task.action()
    }
}

fun main() {
    val scheduler = FakeStageLeaseScheduler()
    var expirations = 0
    val lease = IdleStageLease(120_000L, scheduler) { expirations++ }
    lease.touch()
    val stale = scheduler.tasks.last()
    lease.touch()
    val current = scheduler.tasks.last()
    check(stale.cancelled && current.delayMillis == 120_000L)
    scheduler.fire(stale, evenIfCancelled = true) // simulate a callback already dequeued
    check(expirations == 0) { "Stale timer expired a refreshed staging session" }
    scheduler.fire(current)
    check(expirations == 1) { "Current timer did not expire the idle staging session" }
    lease.touch()
    check(scheduler.tasks.size == 2) { "Expired lease was unexpectedly re-armed" }

    val cancelledScheduler = FakeStageLeaseScheduler()
    var cancelledExpirations = 0
    val cancelledLease = IdleStageLease(1L, cancelledScheduler) { cancelledExpirations++ }
    cancelledLease.touch()
    val cancelledTask = cancelledScheduler.tasks.single()
    cancelledLease.close()
    check(cancelledTask.cancelled)
    cancelledScheduler.fire(cancelledTask, evenIfCancelled = true)
    check(cancelledExpirations == 0) { "Closed staging lease still expired" }
    check(runCatching { IdleStageLease(0L, cancelledScheduler) {} }.exceptionOrNull() is IllegalArgumentException)
    println("PASS: SAF staging idle lease refresh, stale callback rejection and close")
}
