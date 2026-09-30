package com.sysmentalhealth.solace_mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen check-in widget.
 *
 * Deliberately static: Android widgets are RemoteViews, so this is a native
 * layout rather than Flutter output, and RemoteViews cannot run Flutter or any
 * custom animation. It states today's check-in state and one tap opens the
 * check-in flow through [MainActivity].
 *
 * Copy is pushed from Dart so the wording lives in one place, and the widget
 * never carries a streak, counter or badge.
 */
class CheckInWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val prompt = widgetData.getString(KEY_PROMPT, null)
            ?: context.getString(R.string.checkin_widget_prompt)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.checkin_widget).apply {
                setTextViewText(R.id.widget_prompt, prompt)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(LAUNCH_URI),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    companion object {
        /** Shared-preferences key holding the prompt line, written from Dart. */
        const val KEY_PROMPT = "checkin_prompt"

        /** Deep link the widget opens; the app maps `checkin` to the flow. */
        const val LAUNCH_URI = "solace://checkin"
    }
}
