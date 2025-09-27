package id.bapenda.mdm

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.BufferedReader
import java.io.InputStreamReader

class TouchDetectService : Service() {
    companion object {
        private const val TAG = "TouchDetectService"
        private const val NOTIF_CHANNEL = "touch_detect_channel"
        private const val NOTIF_ID = 2024
    }

    private var process: Process? = null
    private var readerThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "TouchDetectService created (root mode)")
        createNotificationChannel()
        startForeground(
            NOTIF_ID,
            buildNotification("Touch detection (root) running...")
        )
        startRootListener()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRootListener()
        Log.d(TAG, "TouchDetectService destroyed")
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            NOTIF_CHANNEL,
            "Touch Detect Service (Root)",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Foreground service for detecting screen touches with root"
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(content: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Touch Detect Service (Root)")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pIntent)
            .setOngoing(true)
            .build()
    }

    private fun startRootListener() {
        readerThread = Thread {
            try {
                // Jalankan getevent -l dengan root
                process = Runtime.getRuntime().exec(arrayOf("su", "-c", "getevent -l"))

                val reader = BufferedReader(InputStreamReader(process!!.inputStream))
                var line: String?

                while (reader.readLine().also { line = it } != null) {
                    // Contoh output getevent -l:
                    // /dev/input/event2: EV_ABS       ABS_MT_POSITION_X    0000030d
                    // /dev/input/event2: EV_SYN       SYN_REPORT           00000000
                    if (line!!.contains("EV_ABS") || line!!.contains("EV_KEY")) {
                        Log.d(TAG, "Touch detected via root: $line")
                        val intent = Intent("id.bapenda.mdm.RESET_IDLE")
                        sendBroadcast(intent)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading input events", e)
            }
        }
        readerThread?.start()
    }

    private fun stopRootListener() {
        try {
            process?.destroy()
            readerThread?.interrupt()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping root listener", e)
        }
    }
}
