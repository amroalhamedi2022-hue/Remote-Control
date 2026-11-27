package com.example.liquid_remote_control

import kotlin.math.max
import kotlin.math.min

/** Pure sizing policy, independently testable without Android. Never upscales. */
internal object AvcCaptureSize {
    fun fit(width: Int, height: Int, longEdge: Int, alignWidth: Int, alignHeight: Int): Pair<Int, Int>? {
        require(width > 0 && height > 0 && longEdge > 0 && alignWidth > 0 && alignHeight > 0)
        val scale = min(1.0, longEdge.toDouble() / max(width, height))
        val w = (width * scale).toInt() / alignWidth * alignWidth
        val h = (height * scale).toInt() / alignHeight * alignHeight
        return if (w > 0 && h > 0) w to h else null
    }
}
