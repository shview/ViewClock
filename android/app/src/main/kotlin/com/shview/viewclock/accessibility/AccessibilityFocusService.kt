package com.shview.viewclock.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

class AccessibilityFocusService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    companion object {
        fun isEnabled(context: Context): Boolean {
            val expected = ComponentName(
                context,
                AccessibilityFocusService::class.java,
            ).flattenToString()
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ).orEmpty()
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }
    }
}
