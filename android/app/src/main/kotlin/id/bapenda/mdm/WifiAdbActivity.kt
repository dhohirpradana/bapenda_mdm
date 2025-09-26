package id.bapenda.mdm

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class WifiAdbWatchdogService : Service() {
    companion object {
        private const val TAG = "WifiAdbWatchdog"
        private const val NOTIF_CHANNEL = "wifiadb_watchdog_channel"
        private const val NOTIF_ID = 2023
        private const val INTERVAL_SEC = 2L
        private const val ADB_PORT = "15555"
    }

    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private var scheduledTask: ScheduledFuture<*>? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate called")
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("WiFi ADB watchdog running..."))
        Log.d(TAG, "Foreground started")
        startWatchdogLoop()
        Log.d(TAG, "Watchdog loop scheduled")
    }

    override fun onDestroy() {
        super.onDestroy()
        stopWatchdogLoop()
        scheduler.shutdownNow()
        Log.d(TAG, "Service destroyed, watchdog stopped")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                NOTIF_CHANNEL,
                "WiFi ADB Watchdog",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Foreground service for WiFi ADB watchdog"
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
            .setContentTitle("WiFi ADB Watchdog")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pIntent)
            .setOngoing(true)
            .build()
    }

    private fun startWatchdogLoop() {
        scheduledTask = scheduler.scheduleAtFixedRate({
            try {
                maintainAdb()
            } catch (t: Throwable) {
                Log.e(TAG, "watchdog loop error", t)
            }
        }, 0, INTERVAL_SEC, TimeUnit.SECONDS)
    }

    private fun stopWatchdogLoop() {
        scheduledTask?.cancel(true)
    }

    private fun maintainAdb() {
        try {
            val currentPort = getProp("service.adb.tcp.port")
            if (currentPort != ADB_PORT) {
                Log.d(TAG, "ADB port $currentPort != $ADB_PORT -> enabling ADB WiFi")
                enableAdb()
            } else {
                Log.d(TAG, "ADB WiFi already on port $ADB_PORT")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to maintain ADB", e)
        }
    }

    private fun enableAdb() {
        execShell("su -c setprop service.adb.tcp.port $ADB_PORT")
        execShell("su -c stop adbd")
        execShell("su -c start adbd")
    }

    private fun getProp(prop: String): String? {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", "getprop $prop"))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val value = reader.readLine()?.trim()
            reader.close()
            value
        } catch (e: Exception) {
            Log.w(TAG, "getProp failed for $prop", e)
            null
        }
    }

    private fun execShell(cmd: String) {
        try {
            Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
        } catch (e: Exception) {
            Log.w(TAG, "execShell failed: $cmd", e)
        }
    }
}
