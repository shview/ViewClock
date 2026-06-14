package com.shview.viewclock.usage

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings

class UsageAccessHelper(private val context: Context) {
    fun isGranted(): Boolean {
        val appOps = context.getSystemService(AppOpsManager::class.java)
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openSettings() {
        context.startActivity(
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun getCurrentForegroundPackage(): String? {
        if (!isGranted()) {
            throw IllegalStateException("Usage Access 尚未授权")
        }
        val usageStatsManager = context.getSystemService(UsageStatsManager::class.java)
        val end = System.currentTimeMillis()
        val events = usageStatsManager.queryEvents(end - LOOKBACK_MILLIS, end)
        val event = UsageEvents.Event()
        var latestPackage: String? = null
        var latestTimestamp = 0L

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val isForeground = event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            if (isForeground && event.timeStamp >= latestTimestamp) {
                latestTimestamp = event.timeStamp
                latestPackage = event.packageName
            }
        }
        return latestPackage
    }

    companion object {
        private const val LOOKBACK_MILLIS = 60_000L
    }
}
