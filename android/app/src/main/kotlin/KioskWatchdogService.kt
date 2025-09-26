package id.bapenda.mdm

import android.app.*
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.pm.PackageManager

class KioskWatchdogService : Service() {
    companion object {
        private const val TAG = "KioskWatchdog"
        private const val NOTIF_CHANNEL = "kiosk_watchdog_channel"
        private const val NOTIF_ID = 1011
        private const val INTERVAL_SEC = 2L
    }

    private val CONF_PATH by lazy {
        File(applicationContext.filesDir, "kiosk_config.json").absolutePath
    }

    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private var scheduledTask: ScheduledFuture<*>? = null

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate() called")
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Watchdog starting..."))
        startWatchdogLoop()
        Log.i(TAG, "Service created and watchdog loop started")
    }

    override fun onDestroy() {
        super.onDestroy()
        stopWatchdogLoop()
        scheduler.shutdownNow()
        Log.i(TAG, "Service destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                NOTIF_CHANNEL,
                "Kiosk Watchdog",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Foreground service for kiosk watchdog"
            nm.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun buildNotification(content: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Kiosk Watchdog")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pIntent)
            .setOngoing(true)
            .build()
    }

    private fun startWatchdogLoop() {
        Log.d(TAG, "startWatchdogLoop()")
        scheduledTask = scheduler.scheduleAtFixedRate({
            try {
                runWatchdogIteration()
            } catch (t: Throwable) {
                Log.e(TAG, "watchdog loop error", t)
            }
        }, 0, INTERVAL_SEC, TimeUnit.SECONDS)
    }

    private fun stopWatchdogLoop() {
        Log.d(TAG, "stopWatchdogLoop()")
        scheduledTask?.cancel(true)
    }

    private fun runWatchdogIteration() {
        Log.d(TAG, "runWatchdogIteration() called")

        val confFile = File(CONF_PATH)
        if (!confFile.exists()) {
            Log.w(TAG, "Config file not found: $CONF_PATH")
            return
        }

        val confText = confFile.readText(Charsets.UTF_8)
        Log.d(TAG, "Config file content: $confText")

        val json = try {
            JSONObject(confText)
        } catch (e: Exception) {
            Log.w(TAG, "Invalid config JSON", e)
            return
        }

        val enabled = json.optBoolean("enabled", false)
        val target = json.optString("target", "")
        val whitelist = parseWhitelist(json)

        Log.d(TAG, "Config -> enabled=$enabled, target=$target, whitelist=$whitelist")

        if (!enabled || target.isBlank()) {
            Log.d(TAG, "Watchdog disabled or target blank, skipping iteration")
            return
        }

        var topPkg = getTopPackageByDumpsys()
        Log.d(TAG, "Top package via dumpsys: $topPkg")

        if (topPkg.isNullOrBlank()) {
            topPkg = getTopPackageByUsageStats()
            Log.d(TAG, "Top package via UsageStats: $topPkg")
        }

        topPkg = topPkg?.trim()
        Log.d(TAG, "Sanitized topPkg: $topPkg")

        if (topPkg == target) {
            Log.d(TAG, "Top package is target -> OK, nothing to do")
            return
        }

        if (!whitelist.isNullOrEmpty() && whitelist.contains(topPkg)) {
            Log.d(TAG, "Top package in whitelist -> OK, nothing to do")
            return
        }

        Log.i(TAG, "top=$topPkg not target=$target -> bringing target to front")

        val pm = packageManager
        val launch = pm.getLaunchIntentForPackage(target)
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            try {
                startActivity(launch)
                Log.i(TAG, "Launched $target via launchIntent")
                return
            } catch (e: Exception) {
                Log.w(TAG, "Failed startActivity, fallback to am start", e)
            }
        }

        val comp = resolveLaunchComponent(target)
        if (comp != null) {
            val cmd =
                "am start --user 0 -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n $comp"
            Log.d(TAG, "Executing shell cmd: $cmd")
            executeShell(cmd)
        } else {
            Log.d(TAG, "Fallback monkey start for $target")
            executeShell("monkey -p $target -c android.intent.category.LAUNCHER 1")
        }
    }

    private fun parseWhitelist(json: JSONObject): List<String> {
        val out = mutableListOf<String>()
        if (json.has("whitelist")) {
            try {
                val arr = json.get("whitelist")
                if (arr is JSONArray) {
                    for (i in 0 until arr.length()) {
                        val v = arr.optString(i, "").trim()
                        if (v.isNotEmpty()) out.add(v)
                    }
                } else if (arr is String) {
                    arr.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                        .forEach { out.add(it) }
                }
            } catch (e: Exception) {
                Log.w(TAG, "parseWhitelist failed", e)
            }
        }
        Log.d(TAG, "Whitelist parsed: $out")
        return out
    }

    private fun getTopPackageByDumpsys(): String? {
        try {
            var out =
                executeShellAndGetOutput("su -c \"dumpsys activity activities | grep mResumedActivity\"")
            Log.d(TAG, "dumpsys mResumedActivity su output: $out")

            if (out.isNullOrBlank()) {
                out = executeShellAndGetOutput("dumpsys activity activities | grep mResumedActivity")
                Log.d(TAG, "dumpsys mResumedActivity no-su output: $out")
            }
            if (!out.isNullOrBlank()) {
                val match = Regex("""\s([a-zA-Z0-9_.]+)/""").find(out)
                if (match != null) {
                    Log.d(TAG, "dumpsys parsed package: ${match.groupValues[1]}")
                    return match.groupValues[1]
                }
            }

            var out2 =
                executeShellAndGetOutput("dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp'")
            Log.d(TAG, "dumpsys window output: $out2")

            if (!out2.isNullOrBlank()) {
                val match = Regex("""\s([a-zA-Z0-9_.]+)/""").find(out2)
                if (match != null) return match.groupValues[1]
            }
        } catch (e: Exception) {
            Log.w(TAG, "getTopPackageByDumpsys error", e)
        }
        return null
    }

    private fun executeShellAndGetOutput(cmd: String): String? {
        return try {
            Log.d(TAG, "executeShellAndGetOutput: $cmd")
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val sb = StringBuilder()
            var line: String? = reader.readLine()
            while (line != null) {
                sb.append(line).append("\n")
                line = reader.readLine()
            }
            reader.close()
            process.waitFor(1500, TimeUnit.MILLISECONDS)
            val result = sb.toString()
            Log.d(TAG, "Command output: $result")
            result
        } catch (e: Exception) {
            Log.w(TAG, "exec failed: $cmd", e)
            null
        }
    }

    private fun executeShell(cmd: String) {
        try {
            Log.d(TAG, "executeShell: $cmd")
            Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
        } catch (e: Exception) {
            Log.w(TAG, "exec(cmd) failed", e)
        }
    }

    private fun resolveLaunchComponent(pkg: String): String? {
        return try {
            val pm = packageManager
            val intent = pm.getLaunchIntentForPackage(pkg) ?: return null
            val comp = intent.component ?: return null
            val compName = "${comp.packageName}/${comp.className}"
            Log.d(TAG, "Resolved component for $pkg: $compName")
            compName
        } catch (e: Exception) {
            Log.w(TAG, "resolveLaunchComponent failed", e)
            null
        }
    }

    private fun getTopPackageByUsageStats(): String? {
        try {
            val usage =
                getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
            val end = System.currentTimeMillis()
            val start = end - 10 * 1000L
            val events = usage.queryEvents(start, end)
            var lastPkg: String? = null
            val ev = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(ev)
                if (ev.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    lastPkg = ev.packageName
                    Log.d(TAG, "UsageStats found foreground: $lastPkg")
                }
            }
            return lastPkg
        } catch (e: Exception) {
            Log.w(TAG, "getTopPackageByUsageStats error", e)
            return null
        }
    }
}
