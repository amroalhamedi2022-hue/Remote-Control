package com.example.liquid_remote_control

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Attended, local-only diagnostic; no pixel storage, transmission or input. */
class CaptureProbeActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var start: Button
    private var requesting = false
    private val refresh = object : Runnable {
        override fun run() {
            status.text = CaptureProbeService.status
            start.isEnabled = !requesting && !CaptureProbeService.running
            handler.postDelayed(this, 250)
        }
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (24 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
        }
        layout.addView(TextView(this).apply {
            text = "Local screen capture diagnostic"
            textSize = 24f
        })
        layout.addView(TextView(this).apply {
            text = "Counts frames for up to 20 seconds. No screenshots, files, network transmission or remote input. Android will ask for permission."
            textSize = 16f
        })
        status = TextView(this).apply { textSize = 18f }
        layout.addView(status)
        start = Button(this).apply {
            text = "Request screen capture"
            setOnClickListener {
                if (requesting || CaptureProbeService.running) return@setOnClickListener
                requesting = true
                isEnabled = false
                try {
                    val manager = getSystemService(MediaProjectionManager::class.java)
                    startActivityForResult(manager.createScreenCaptureIntent(), 501)
                } catch (e: Exception) {
                    requesting = false
                    CaptureProbeService.status = "Permission request failed"
                }
            }
        }
        layout.addView(start)
        layout.addView(Button(this).apply {
            text = "Stop capture"
            setOnClickListener { stopService(Intent(this@CaptureProbeActivity, CaptureProbeService::class.java)) }
        })
        setContentView(layout)
    }

    override fun onStart() {
        super.onStart()
        handler.post(refresh)
    }
    override fun onStop() {
        handler.removeCallbacks(refresh)
        super.onStop()
    }
    override fun onDestroy() {
        handler.removeCallbacks(refresh)
        stopService(Intent(this, CaptureProbeService::class.java))
        super.onDestroy()
    }

    @Deprecated("Activity result API used by the existing native overlay")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 501) return
        requesting = false
        if (resultCode != RESULT_OK || data == null) {
            CaptureProbeService.status = "Permission denied; no capture"
            return
        }
        val service = Intent(this, CaptureProbeService::class.java)
            .putExtra("consent", data)
        CaptureProbeService.running = true
        CaptureProbeService.status = "Starting local diagnostic"
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        } catch (e: Exception) {
            CaptureProbeService.running = false
            CaptureProbeService.status = "Foreground service could not start"
        }
    }
}
