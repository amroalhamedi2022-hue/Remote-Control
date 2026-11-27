package com.example.liquid_remote_control

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.content.res.Configuration

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
    private var encoder: AvcCaptureEncoder? = null
    private var orientation = Configuration.ORIENTATION_UNDEFINED
    private val drain = object : Runnable {
        override fun run() {
            if (finished) return
            val active = encoder ?: return
            try {
                active.drainAvailable()
                status = "${active.width}x${active.height} AVC · ${active.acceleration}\n" +
                    "${active.codecName}\n${active.frames} frames · ${active.keyFrames} keyframes · ${active.bytes} bytes"
                handler.postDelayed(this, 16)
            } catch (_: Exception) {
                finish("Encoder drain failed")
            }
        }
    }
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
            orientation = resources.configuration.orientation
            val active = AvcCaptureEncoder.open(metrics.widthPixels, metrics.heightPixels)
            encoder = active
            display = media.createVirtualDisplay("LocalAvcDiagnostic", active.width, active.height,
                metrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                active.surface, null, handler) ?: error("Virtual display unavailable")
            running = true
            status = "Starting AVC encoder"
            handler.post(drain)
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
        handler.removeCallbacks(drain)
        runCatching { display?.release() }
        display = null
        val active = encoder
        encoder = null
        val summary = if (active == null) "no encoder" else
            "${active.frames} AVC frames · ${active.keyFrames} keyframes · ${active.bytes} bytes · ${active.acceleration}"
        active?.close()
        val media = projection
        projection = null
        runCatching { media?.unregisterCallback(callback) }
        runCatching { media?.stop() }
        status = "$reason — $summary"
        running = false
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (encoder != null && newConfig.orientation != orientation) {
            finish("Orientation changed; request a new capture")
        }
    }
    override fun onDestroy() {
        finish("Capture stopped")
        super.onDestroy()
    }
}
