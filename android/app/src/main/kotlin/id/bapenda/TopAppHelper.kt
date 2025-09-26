package id.bapenda.mdm

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import android.util.Log

object TopAppHelper {
    fun getTopApp(context: Context): String? {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val tasks = am.runningAppProcesses
        if (!tasks.isNullOrEmpty()) {
            val top = tasks[0]
            if (top.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                return top.pkgList.firstOrNull()
            }
        }

        // fallback pakai UsageStatsManager
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val begin = end - 1000 * 10
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, end)
        if (!stats.isNullOrEmpty()) {
            val recent = stats.maxByOrNull { it.lastTimeUsed }
            return recent?.packageName
        }

        Log.w("TopAppHelper", "Unable to detect top app")
        return null
    }
}
