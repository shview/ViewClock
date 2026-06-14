package com.shview.viewclock.foreground

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.shview.viewclock.R
import com.shview.viewclock.accessibility.FocusEnforcementStore
import com.shview.viewclock.usage.UsageAccessHelper

class FocusMonitorService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var usageAccessHelper: UsageAccessHelper
    private lateinit var enforcementStore: FocusEnforcementStore
    private var whitelist: Set<String> = emptySet()
    private var lastPackage: String? = null

    private val pollRunnable = object : Runnable {
        override fun run() {
            runCatching { usageAccessHelper.getCurrentForegroundPackage() }
                .onSuccess { packageName ->
                    if (packageName != null && packageName != lastPackage) {
                        lastPackage = packageName
                        emit(
                            mapOf(
                                "type" to "foregroundAppChanged",
                                "packageName" to packageName,
                                "allowed" to whitelist.contains(packageName),
                                "timestamp" to System.currentTimeMillis(),
                            ),
                        )
                        if (!whitelist.contains(packageName)) {
                            emit(
                                mapOf(
                                    "type" to "violationDetected",
                                    "packageName" to packageName,
                                    "timestamp" to System.currentTimeMillis(),
                                ),
                            )
                        }
                    }
                }
                .onFailure { error ->
                    emit(
                        mapOf(
                            "type" to "nativeError",
                            "message" to (error.message ?: error.javaClass.simpleName),
                            "timestamp" to System.currentTimeMillis(),
                        ),
                    )
                }
            handler.postDelayed(this, POLL_INTERVAL_MILLIS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        usageAccessHelper = UsageAccessHelper(this)
        enforcementStore = FocusEnforcementStore(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        whitelist = intent
            ?.getStringArrayListExtra(EXTRA_WHITELIST)
            .orEmpty()
            .plus(packageName)
            .toSet()
        enforcementStore.update(
            active = true,
            enforce = intent?.getBooleanExtra(EXTRA_ENFORCE, false) == true,
            whitelist = whitelist,
        )
        startForeground(
            NOTIFICATION_ID,
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("View Clock 专注监控正在运行")
                .setContentText("仅检测当前前台 App，不会自动执行 root 操作")
                .setOngoing(true)
                .build(),
        )
        handler.removeCallbacks(pollRunnable)
        handler.post(pollRunnable)
        emit(mapOf("type" to "monitorStateChanged", "running" to true))
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        enforcementStore.clear()
        emit(mapOf("type" to "monitorStateChanged", "running" to false))
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "View Clock 前台监控",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun emit(event: Map<String, Any?>) {
        listener?.onMonitorEvent(event)
    }

    interface Listener {
        fun onMonitorEvent(event: Map<String, Any?>)
    }

    companion object {
        @Volatile
        var listener: Listener? = null

        private const val CHANNEL_ID = "focus_monitor"
        private const val NOTIFICATION_ID = 1001
        private const val EXTRA_WHITELIST = "whitelist"
        private const val EXTRA_ENFORCE = "enforce"
        private const val POLL_INTERVAL_MILLIS = 1_000L

        fun start(context: Context, whitelist: List<String>, enforce: Boolean) {
            val intent = Intent(context, FocusMonitorService::class.java).putStringArrayListExtra(
                EXTRA_WHITELIST,
                ArrayList(whitelist),
            ).putExtra(EXTRA_ENFORCE, enforce)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            FocusEnforcementStore(context).clear()
            context.stopService(Intent(context, FocusMonitorService::class.java))
        }
    }
}
