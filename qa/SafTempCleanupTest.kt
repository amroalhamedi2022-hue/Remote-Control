package com.example.liquid_remote_control

import java.io.IOException

fun main() {
    run {
        var called = false
        SafTempCleanup.onFailure(null) { called = true; true }
        check(called)
    }

    run {
        val failure = runCatching {
            SafTempCleanup.onFailure(null) { false }
        }.exceptionOrNull()
        check(failure is IOException)
        check(failure.message!!.contains("temporary SAF document"))
        check(failure.cause is IOException)
    }

    run {
        val primary = IOException("SAF readback hash mismatch")
        val cleanup = IllegalStateException("provider refused delete")
        val failure = runCatching {
            SafTempCleanup.onFailure(primary) { throw cleanup }
        }.exceptionOrNull()
        check(failure is IOException)
        check(failure.message!!.contains("cleanup also failed"))
        check(failure.cause === primary)
        check(failure.suppressed.size == 1)
        check(failure.suppressed.single().cause === cleanup)
    }

    run {
        val primary = IOException("rename failed")
        val failure = runCatching {
            SafTempCleanup.onFailure(primary) { false }
        }.exceptionOrNull()
        check(failure is IOException)
        check(failure.cause === primary)
        check(failure.suppressed.single().cause is IOException)
    }

    println("PASS: failed SAF temp-document cleanup is reported with the original publication failure")
}
