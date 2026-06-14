package com.shview.viewclock.locktask

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import com.shview.viewclock.deviceowner.DeviceOwnerReceiver

class LockTaskController(private val activity: Activity) {
    private val devicePolicyManager =
        activity.getSystemService(DevicePolicyManager::class.java)
    private val adminComponent = ComponentName(activity, DeviceOwnerReceiver::class.java)

    fun isDeviceOwner(): Boolean =
        devicePolicyManager.isDeviceOwnerApp(activity.packageName)

    fun setLockTaskPackages(packages: List<String>) {
        check(isDeviceOwner()) { "只有 Device Owner 才能配置 Lock Task 白名单" }
        val safePackages = (packages + activity.packageName).distinct().toTypedArray()
        devicePolicyManager.setLockTaskPackages(adminComponent, safePackages)
    }

    fun isLockTaskPermitted(packageName: String): Boolean =
        devicePolicyManager.isLockTaskPermitted(packageName)

    fun start() {
        activity.startLockTask()
    }

    fun stop() {
        val activityManager = activity.getSystemService(ActivityManager::class.java)
        check(activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
            "当前未处于 Lock Task 或 Screen Pinning"
        }
        activity.stopLockTask()
    }
}
