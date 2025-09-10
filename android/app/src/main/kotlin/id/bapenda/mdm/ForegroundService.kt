package id.bapenda.mdm

import android.app.*
import android.content.*
import android.graphics.*
import android.os.*
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat

class ForegroundService : Service() {
    private val CHANNEL_ID = "BapendaMDMForegroundChannel"
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var handler: Handler? = null
    private var runnable: Runnable? = null
    private var isScreensaverShown = false
    private val interval: Long = 30_000 // 30 detik

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        handler = Handler(Looper.getMainLooper())

        // Notifikasi agar service jalan di background
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Foreground Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Bapenda MDM")
            .setContentText("Screensaver service aktif")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()

        startForeground(1, notification)

        // Runnable untuk menampilkan screensaver setelah 10 detik
        runnable = Runnable {
            showOverlay()
        }

        resetIdleTimer()

        // Daftar broadcast reset
        val filter = IntentFilter("id.bapenda.mdm.RESET_IDLE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(resetReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(resetReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        handler?.removeCallbacks(runnable!!)
        unregisterReceiver(resetReceiver)
        hideOverlay()
    }

    // Receiver untuk reset dari luar
    private val resetReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            resetIdleTimer()
        }
    }

    private fun resetIdleTimer() {
        handler?.removeCallbacks(runnable!!)
        handler?.postDelayed(runnable!!, interval)
        if (isScreensaverShown) {
            hideOverlay()
        }
    }

    private fun showOverlay() {
        if (overlayView != null) return
        isScreensaverShown = true

        val layout = FrameLayout(this)
        layout.setBackgroundColor(Color.BLACK)

        val text = TextView(this).apply {
            textSize = 48f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            text = "Screensaver aktif"
        }

        layout.addView(
            text,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        layout.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                resetIdleTimer()
                true
            } else false
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        overlayView = layout
        windowManager?.addView(overlayView, params)

        // Immersive mode supaya status bar hilang
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            overlayView?.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
    }

    private fun hideOverlay() {
        overlayView?.let {
            windowManager?.removeViewImmediate(it)
        }
        overlayView = null
        isScreensaverShown = false
    }
}
