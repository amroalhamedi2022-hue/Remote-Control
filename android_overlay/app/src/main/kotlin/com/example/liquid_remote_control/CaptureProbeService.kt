package com.example.liquid_remote_control

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlin.math.max
import kotlin.math.roundToInt

/** Local diagnostic only: discard every frame, never expose pixels or sockets. */
class CaptureProbeService : Service() {
    companion object {
        @Volatile var running = false
        @Volatile var status = "Ready; no capture"
        private const val CHANNEL = "local_capture_probe"
        private const val NOTIFICATION = 502
        private const val STOP = "liquidremote.STOP_LOCAL_PROBE"
    }
    private val handler = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var frames = 0L
    private var finished = false
    private val deadline = Runnable { finish("Diagnostic finished") }
    private val callback = object : MediaProjection.Callback() {
        override fun onStop() { finish("Android stopped capture") }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            finish("Stopped by user")
            return START_NOT_STICKY
        }
        if (projection != null || finished) return START_NOT_STICKY
        val consent: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra("consent", Intent::class.java)
        } else {
            intent?.getParcelableExtra("consent")
        }
        if (consent == null) {
            finish("No capture permission")
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL,
                    "Local screen diagnostic", NotificationManager.IMPORTANCE_LOW))
            }
            val stopIntent = PendingIntent.getService(this, 503,
                Intent(this, CaptureProbeService::class.java).setAction(STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
                else Notification.Builder(this)
            val notice = builder.setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("Local screen diagnostic")
                .setContentText("Frame count only; no network or recording")
                .setOngoing(true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(NOTIFICATION, notice)
            }
            val media = getSystemService(MediaProjectionManager::class.java)
                .getMediaProjection(Activity.RESULT_OK, consent)
                ?: error("Projection permission unavailable")
            projection = media
            media.registerCallback(callback, handler)
            val metrics = resources.displayMetrics
            val scale = 640.0 / max(metrics.widthPixels, metrics.heightPixels).coerceAtLeast(1)
            val width = (metrics.widthPixels * scale.coerceAtMost(1.0)).roundToInt().coerceAtLeast(1)
            val height = (metrics.heightPixels * scale.coerceAtMost(1.0)).roundToInt().coerceAtLeast(1)
            val images = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            reader = images
            images.setOnImageAvailableListener({ source ->
                if (!finished) {
                    try {
                        source.acquireLatestImage()?.use {
                            frames++
                            status = "Capturing locally: $frames frames"
                        }
                    } catch (e: Exception) {
                        finish("Frame acquisition failed")
                    }
                }
            }, handler)
            display = media.createVirtualDisplay("LocalDiagnostic", width, height,
                metrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                images.surface, null, handler)
            running = true
            status = "Capturing locally: 0 frames"
            handler.postDelayed(deadline, 20_000)
        } catch (e: Exception) {
            finish("Capture failed: ${e.javaClass.simpleName}")
        }
        return START_NOT_STICKY
    }

    private fun finish(reason: String) {
        if (finished) return
        finished = true
        handler.removeCallbacks(deadline)
        runCatching { reader?.setOnImageAvailableListener(null, null) }
        runCatching { display?.release() }
        display = null
        runCatching { reader?.close() }
        reader = null
        val media = projection
        projection = null
        runCatching { media?.unregisterCallback(callback) }
        runCatching { media?.stop() }
        status = "$reason — $frames frames observed"
        running = false
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }
    override fun onDestroy() {
        finish("Capture stopped")
        super.onDestroy()
    }
}
