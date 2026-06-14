package com.shview.viewclock.bridge

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.shview.viewclock.accessibility.AccessibilityFocusService
import com.shview.viewclock.applist.AppListProvider
import com.shview.viewclock.deviceowner.DeviceOwnerReceiver
import com.shview.viewclock.foreground.FocusMonitorService
import com.shview.viewclock.locktask.LockTaskController
import com.shview.viewclock.usage.UsageAccessHelper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class NativeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, FocusMonitorService.Listener {
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val appListProvider = AppListProvider(activity)
    private val usageAccessHelper = UsageAccessHelper(activity)
    private val lockTaskController = LockTaskController(activity)
    private val preferences = activity.getSharedPreferences("view_clock", Activity.MODE_PRIVATE)
    private val iconExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        FocusMonitorService.listener = this
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ping" -> result.success("pong")
                "getDeviceInfo" -> result.success(getDeviceInfo())
                "getInstalledApps" -> result.success(appListProvider.getAppInventory())
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                        ?: throw IllegalArgumentException("packageName 不能为空")
                    iconExecutor.execute {
                        runCatching { appListProvider.getAppIconBase64(packageName) }
                            .onSuccess { icon ->
                                mainHandler.post { result.success(icon) }
                            }
                            .onFailure { error ->
                                mainHandler.post {
                                    result.error(
                                        "icon_error",
                                        error.message ?: error.javaClass.simpleName,
                                        null,
                                    )
                                }
                            }
                    }
                }
                "isUsageAccessGranted" -> result.success(usageAccessHelper.isGranted())
                "openUsageAccessSettings" -> {
                    usageAccessHelper.openSettings()
                    result.success(null)
                }
                "getCurrentForegroundApp" ->
                    result.success(usageAccessHelper.getCurrentForegroundPackage())
                "readAppState" -> result.success(preferences.getString(APP_STATE_KEY, null))
                "writeAppState" -> {
                    val value = call.argument<String>("value")
                        ?: throw IllegalArgumentException("value 不能为空")
                    if (!preferences.edit().putString(APP_STATE_KEY, value).commit()) {
                        throw IllegalStateException("本地数据保存失败")
                    }
                    result.success(null)
                }
                "isDeviceOwner" -> result.success(lockTaskController.isDeviceOwner())
                "setLockTaskPackages" -> {
                    val packages = call.argument<List<String>>("packages").orEmpty()
                    lockTaskController.setLockTaskPackages(packages)
                    result.success(null)
                }
                "isLockTaskPermitted" -> {
                    val packageName = call.argument<String>("packageName") ?: activity.packageName
                    result.success(lockTaskController.isLockTaskPermitted(packageName))
                }
                "startLockTaskMode" -> {
                    lockTaskController.start()
                    result.success(null)
                }
                "stopLockTaskMode" -> {
                    lockTaskController.stop()
                    result.success(null)
                }
                "isAccessibilityEnabled" ->
                    result.success(AccessibilityFocusService.isEnabled(activity))
                "openAccessibilitySettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "startFocusMonitor" -> {
                    val whitelist = call.argument<List<String>>("whitelist").orEmpty()
                    FocusMonitorService.start(activity, whitelist)
                    result.success(null)
                }
                "stopFocusMonitor" -> {
                    FocusMonitorService.stop(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) {
            result.error("security_error", error.message, null)
        } catch (error: IllegalStateException) {
            result.error("invalid_state", error.message, null)
        } catch (error: Exception) {
            result.error("native_error", error.message ?: error.javaClass.simpleName, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMonitorEvent(event: Map<String, Any?>) {
        activity.runOnUiThread { eventSink?.success(event) }
    }

    fun dispose() {
        if (FocusMonitorService.listener === this) {
            FocusMonitorService.listener = null
        }
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        iconExecutor.shutdownNow()
    }

    private fun getDeviceInfo(): Map<String, Any> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "androidRelease" to Build.VERSION.RELEASE,
        "sdkInt" to Build.VERSION.SDK_INT,
        "packageName" to activity.packageName,
        "deviceOwnerReceiver" to ComponentName(
            activity,
            DeviceOwnerReceiver::class.java,
        ).flattenToShortString(),
    )

    companion object {
        private const val METHOD_CHANNEL = "focus_lock/native"
        private const val EVENT_CHANNEL = "focus_lock/events"
        private const val APP_STATE_KEY = "app_state_json"
    }
}
