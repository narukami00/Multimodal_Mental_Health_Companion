package com.sysmentalhealth.solace_mobile

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings

/**
 * Reads device usage events for the daily behavior row.
 *
 * Deliberately narrow: it maps a handful of platform event types onto the names
 * Dart expects and returns nothing else. No notification, window title, or
 * content information is read, and nothing is stored here. All logic that turns
 * events into numbers lives in Dart, where it can be tested.
 */
class UsageCollector(private val context: Context) {

    /** Whether the user has granted usage access to this app. */
    fun hasAccess(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * The system screen where usage access is granted, opened on this app's own
     * entry where the platform supports it.
     */
    fun accessSettingsIntent(): Intent {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            intent.data = Uri.fromParts("package", context.packageName, null)
        }
        return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /**
     * Events in [fromMs, toMs), in time order, as maps of `time` (epoch ms),
     * `type` and, for app events, `package`. Empty when access is not granted.
     */
    fun events(fromMs: Long, toMs: Long): List<Map<String, Any?>> {
        if (!hasAccess() || toMs <= fromMs) return emptyList()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(fromMs, toMs)
        val event = UsageEvents.Event()
        val result = ArrayList<Map<String, Any?>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val type = typeName(event.eventType) ?: continue
            val isApp = type == "appForeground" || type == "appBackground"
            result.add(
                mapOf(
                    "time" to event.timeStamp,
                    "type" to type,
                    "package" to if (isApp) event.packageName else null
                )
            )
        }
        return result
    }

    /**
     * What each package is, for grouping time by category. A package this app
     * cannot see (package visibility) comes back as not visible rather than
     * failing, so it is simply counted as "other" by the caller.
     */
    fun describeApps(packages: List<String>): Map<String, Map<String, Any?>> {
        val pm = context.packageManager
        val launchers = homePackages(pm)
        val result = HashMap<String, Map<String, Any?>>()
        for (pkg in packages) {
            val ignore = pkg == context.packageName || pkg == "android" ||
                pkg == "com.android.systemui" || launchers.contains(pkg)
            try {
                val info = pm.getApplicationInfo(pkg, 0)
                result[pkg] = mapOf(
                    "label" to pm.getApplicationLabel(info).toString(),
                    "category" to categoryName(info),
                    "ignore" to ignore,
                    "visible" to true
                )
            } catch (e: PackageManager.NameNotFoundException) {
                result[pkg] = mapOf(
                    "label" to pkg,
                    "category" to null,
                    "ignore" to ignore,
                    "visible" to false
                )
            }
        }
        return result
    }

    private fun homePackages(pm: PackageManager): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return try {
            pm.queryIntentActivities(intent, 0).map { it.activityInfo.packageName }.toSet()
        } catch (e: Exception) {
            emptySet()
        }
    }

    /**
     * Only the platform's own category, and only for the few that matter here.
     * Anything else is left for Dart to decide, so the grouping rules live in
     * one place.
     */
    private fun categoryName(info: ApplicationInfo): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return if (info.flags and ApplicationInfo.FLAG_IS_GAME != 0) "games" else null
        }
        return when (info.category) {
            ApplicationInfo.CATEGORY_GAME -> "games"
            ApplicationInfo.CATEGORY_VIDEO -> "video"
            ApplicationInfo.CATEGORY_SOCIAL -> "social"
            ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
            else -> null
        }
    }

    /** Platform event type to the name Dart reads, or null for ones it ignores. */
    private fun typeName(type: Int): String? = when (type) {
        UsageEvents.Event.ACTIVITY_RESUMED -> "appForeground"
        UsageEvents.Event.ACTIVITY_PAUSED -> "appBackground"
        SCREEN_INTERACTIVE -> "screenOn"
        SCREEN_NON_INTERACTIVE -> "screenOff"
        KEYGUARD_SHOWN -> "keyguardShown"
        KEYGUARD_HIDDEN -> "keyguardHidden"
        else -> null
    }

    private companion object {
        // Constants written out because they are not all visible at the minimum
        // supported API level. Older devices simply never emit them.
        const val SCREEN_INTERACTIVE = 15
        const val SCREEN_NON_INTERACTIVE = 16
        const val KEYGUARD_SHOWN = 17
        const val KEYGUARD_HIDDEN = 18
    }
}
