package com.example.liquid_remote_control

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.view.Surface

/**
 * Surface-input AVC encoder for an explicitly consented projection.
 * All calls belong to one owner thread. Diagnostic drains only metadata:
 * no encoded payload is copied, retained, saved or sent to a peer.
 */
internal class AvcCaptureEncoder private constructor(
    private val codec: MediaCodec,
    val surface: Surface,
    val width: Int,
    val height: Int,
    val codecName: String,
    val acceleration: String
) : AutoCloseable {
    private val info = MediaCodec.BufferInfo()
    private var closed = false
    var frames = 0L
        private set
    var bytes = 0L
        private set
    var keyFrames = 0L
        private set

    fun drainAvailable() {
        check(!closed)
        // Never block the service thread or accumulate unbounded output.
        repeat(8) {
            val index = codec.dequeueOutputBuffer(info, 0L)
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return
            if (index < 0) return@repeat
            try {
                if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    frames++
                    bytes += info.size.toLong()
                    if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) keyFrames++
                }
            } finally {
                codec.releaseOutputBuffer(index, false)
            }
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        runCatching { codec.stop() }
        runCatching { surface.release() }
        runCatching { codec.release() }
    }

    companion object {
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val FPS = 30

        fun open(sourceWidth: Int, sourceHeight: Int): AvcCaptureEncoder {
            require(sourceWidth > 0 && sourceHeight > 0)
            val candidates = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder && it.supportedTypes.any { type -> type.equals(MIME, true) } }
                .sortedByDescending { Build.VERSION.SDK_INT >= 29 && it.isHardwareAccelerated }
            for (candidate in candidates) {
                val capabilities = runCatching { candidate.getCapabilitiesForType(MIME) }.getOrNull()
                    ?: continue
                if (MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface !in capabilities.colorFormats) continue
                val video = capabilities.videoCapabilities ?: continue
                for (edge in intArrayOf(1280, 960, 640)) {
                    val size = AvcCaptureSize.fit(sourceWidth, sourceHeight, edge,
                        video.widthAlignment, video.heightAlignment) ?: continue
                    val (width, height) = size
                    if (!runCatching { video.areSizeAndRateSupported(width, height, FPS.toDouble()) }.getOrDefault(false)) continue
                    var codec: MediaCodec? = null
                    var surface: Surface? = null
                    try {
                        val bitrate = (width.toLong() * height * 4L)
                            .coerceIn(500_000L, 5_000_000L).toInt()
                            .coerceIn(video.bitrateRange.lower, video.bitrateRange.upper)
                        val format = MediaFormat.createVideoFormat(MIME, width, height).apply {
                            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                            setInteger(MediaFormat.KEY_FRAME_RATE, FPS)
                            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                        }
                        val activeCodec = MediaCodec.createByCodecName(candidate.name)
                        codec = activeCodec
                        activeCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                        val input = activeCodec.createInputSurface()
                        surface = input
                        activeCodec.start()
                        val acceleration = if (Build.VERSION.SDK_INT >= 29) {
                            if (candidate.isHardwareAccelerated) "hardware" else "not hardware"
                        } else "unknown on this Android version"
                        return AvcCaptureEncoder(activeCodec, input, width, height, candidate.name, acceleration)
                    } catch (_: Exception) {
                        runCatching { codec?.stop() }
                        runCatching { surface?.release() }
                        runCatching { codec?.release() }
                    }
                }
            }
            error("No compatible surface-input AVC encoder")
        }
    }
}
