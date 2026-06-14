package com.shview.viewclock.applist

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.LauncherActivityInfo
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.Process
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

class AppListProvider(private val context: Context) {
    private val packageManager = context.packageManager
    private val iconCache = ConcurrentHashMap<String, String>()

    fun getAppInventory(): Map<String, Any> {
        val installed = getInstalledApplications()
        val launcher = getLauncherApplications()
        val fallback = getQueryIntentApplications()
        val merged = linkedMapOf<String, Map<String, Any?>>()

        installed.forEach { merged[it.getValue("packageName") as String] = it }
        (launcher + fallback).forEach { app ->
            val packageName = app.getValue("packageName") as String
            merged[packageName] = merged[packageName]
                ?.plus("isLaunchable" to true)
                ?: app
        }

        return mapOf(
            "installedCount" to installed.size,
            "launcherAppsCount" to launcher.size,
            "queryIntentCount" to fallback.size,
            "mergedCount" to merged.size,
            "apps" to merged.values.sortedBy {
                (it["name"] as String).lowercase()
            },
        )
    }

    private fun getInstalledApplications(): List<Map<String, Any?>> {
        val applications = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getInstalledApplications(
                PackageManager.ApplicationInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(0)
        }
        return applications.map(::applicationInfoToMap)
    }

    private fun getLauncherApplications(): List<Map<String, Any?>> {
        val launcherApps = context.getSystemService(LauncherApps::class.java)
        return runCatching {
            launcherApps.getActivityList(null, Process.myUserHandle())
        }.getOrDefault(emptyList())
            .distinctBy { it.applicationInfo.packageName }
            .map(::launcherActivityToMap)
    }

    private fun getQueryIntentApplications(): List<Map<String, Any?>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return activities
            .distinctBy { it.activityInfo.packageName }
            .map { resolveInfo ->
                applicationInfoToMap(resolveInfo.activityInfo.applicationInfo)
                    .plus("name" to resolveInfo.loadLabel(packageManager).toString())
                    .plus("isLaunchable" to true)
            }
    }

    private fun applicationInfoToMap(info: ApplicationInfo): Map<String, Any?> =
        mapOf(
            "name" to info.loadLabel(packageManager).toString(),
            "packageName" to info.packageName,
            "isSystemApp" to (
                (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                ),
            "isLaunchable" to false,
            "enabled" to info.enabled,
        )

    private fun launcherActivityToMap(info: LauncherActivityInfo): Map<String, Any?> =
        applicationInfoToMap(info.applicationInfo)
            .plus("name" to info.label.toString())
            .plus("isLaunchable" to true)

    fun getAppIconBase64(packageName: String): String =
        iconCache.getOrPut(packageName) { encodeAppIcon(packageName) }

    private fun encodeAppIcon(packageName: String): String {
        val drawable = packageManager.getApplicationIcon(packageName)
        val source = if (drawable is BitmapDrawable) {
            drawable.bitmap
        } else {
            Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888).also {
                drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
                drawable.draw(Canvas(it))
            }
        }
        val bitmap = if (source.width == ICON_SIZE && source.height == ICON_SIZE) {
            source
        } else {
            Bitmap.createScaledBitmap(source, ICON_SIZE, ICON_SIZE, true)
        }
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 80, output)
        return Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
    }

    companion object {
        private const val ICON_SIZE = 64
    }
}
