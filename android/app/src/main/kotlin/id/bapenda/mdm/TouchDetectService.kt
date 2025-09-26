package id.bapenda.mdm

import android.app.*
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.*
import androidx.core.app.NotificationCompat

class TouchDetectService : Service() {
    companion object {
        private const val TAG = "TouchDetectService"
        private const val NOTIF_CHANNEL = "touch_detect_channel"
        private const val NOTIF_ID = 2024
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "TouchDetectService created")
        createNotificationChannel()
        startForeground(
            NOTIF_ID,
            buildNotification("Touch detection service running...")
        )
        addTouchOverlay()
    }

    override fun onDestroy() {
        super.onDestroy()
        removeTouchOverlay()
        Log.d(TAG, "TouchDetectService destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                NOTIF_CHANNEL,
                "Touch Detect Service",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Foreground service for detecting screen touches"
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(content: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Touch Detect Service")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pIntent)
            .setOngoing(true)
            .build()
    }

    private fun addTouchOverlay() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        overlayView = View(this).apply {
            setBackgroundColor(0x00000000) // transparan
            isClickable = true
            isFocusable = false

            setOnTouchListener { _, _ ->
                Log.d(TAG, "Screen touched, sending RESET_IDLE broadcast")
                val intent = Intent("id.bapenda.mdm.RESET_IDLE")
                sendBroadcast(intent)
                false // jangan block sentuhan
            }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                    or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        windowManager?.addView(overlayView, params)
    }

    private fun removeTouchOverlay() {
        overlayView?.let {
            windowManager?.removeView(it)
            overlayView = null
        }
    }
}
