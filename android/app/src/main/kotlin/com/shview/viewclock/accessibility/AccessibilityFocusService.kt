package com.shview.viewclock.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import com.shview.viewclock.MainActivity

class AccessibilityFocusService : AccessibilityService() {
    private lateinit var enforcementStore: FocusEnforcementStore
    private var lastBlockedPackage: String? = null
    private var lastBlockedAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        enforcementStore = FocusEnforcementStore(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null ||
            event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) {
            return
        }
        val packageName = event.packageName?.toString()?.takeIf { it.isNotBlank() } ?: return
        if (!::enforcementStore.isInitialized || !enforcementStore.shouldBlock(packageName)) {
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastBlockedAt < BLOCK_DEBOUNCE_MILLIS) {
            return
        }
        lastBlockedPackage = packageName
        lastBlockedAt = now
        val launchIntent = packageManager
            .getLaunchIntentForPackage(this.packageName)
            ?: Intent(this, MainActivity::class.java)
        runCatching {
            startActivity(
                launchIntent
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    )
                    .putExtra(EXTRA_BLOCKED_PACKAGE, packageName)
                    .putExtra(EXTRA_BLOCKED_AT, now),
            )
        }.onFailure {
            performGlobalAction(GLOBAL_ACTION_HOME)
        }
    }

    override fun onInterrupt() = Unit

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blockedPackage"
        const val EXTRA_BLOCKED_AT = "blockedAt"
        private const val BLOCK_DEBOUNCE_MILLIS = 3_000L

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
