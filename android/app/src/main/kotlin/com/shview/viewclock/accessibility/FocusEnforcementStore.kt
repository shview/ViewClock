package com.shview.viewclock.accessibility

import android.content.Context
import android.telecom.TelecomManager

class FocusEnforcementStore(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun update(active: Boolean, enforce: Boolean, whitelist: Collection<String>) {
        preferences.edit()
            .putBoolean(KEY_ACTIVE, active)
            .putBoolean(KEY_ENFORCE, enforce)
            .putStringSet(KEY_WHITELIST, whitelist.toSet())
            .apply()
    }

    fun clear() {
        preferences.edit()
            .putBoolean(KEY_ACTIVE, false)
            .putBoolean(KEY_ENFORCE, false)
            .remove(KEY_WHITELIST)
            .apply()
    }

    fun shouldBlock(packageName: String): Boolean {
        if (!preferences.getBoolean(KEY_ACTIVE, false) ||
            !preferences.getBoolean(KEY_ENFORCE, false)
        ) {
            return false
        }
        return packageName !in allowedPackages()
    }

    private fun allowedPackages(): Set<String> {
        val configured = preferences.getStringSet(KEY_WHITELIST, emptySet()).orEmpty()
        val dialer = appContext
            .getSystemService(TelecomManager::class.java)
            ?.defaultDialerPackage
        return buildSet {
            addAll(configured)
            add(appContext.packageName)
            add("com.android.systemui")
            add("com.android.settings")
            if (dialer != null) add(dialer)
        }
    }

    companion object {
        private const val PREFERENCES_NAME = "focus_enforcement"
        private const val KEY_ACTIVE = "active"
        private const val KEY_ENFORCE = "enforce"
        private const val KEY_WHITELIST = "whitelist"
    }
}
