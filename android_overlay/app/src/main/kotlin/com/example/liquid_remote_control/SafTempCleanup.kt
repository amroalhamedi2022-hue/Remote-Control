package com.example.liquid_remote_control

import java.io.IOException

/**
 * Makes failure to remove an unpublished SAF document visible to the caller.
 * If publication already failed, preserve that failure as the cause and attach
 * the cleanup failure rather than replacing or silently discarding either one.
 */
internal object SafTempCleanup {
    fun onFailure(primaryFailure: Throwable?, deleteTemporaryDocument: () -> Boolean) {
        try {
            if (!deleteTemporaryDocument()) {
                throw IOException("SAF provider refused deletion of temporary document")
            }
        } catch (cleanupFailure: Exception) {
            val reportedCleanup = IOException(
                "Failed to confirm deletion of temporary SAF document",
                cleanupFailure,
            )
            if (primaryFailure != null) {
                val combined = IOException(
                    "SAF publication failed and temporary-document cleanup also failed",
                    primaryFailure,
                )
                combined.addSuppressed(reportedCleanup)
                throw combined
            }
            throw reportedCleanup
        }
    }
}
