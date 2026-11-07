package com.sysmentalhealth.solace_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen check-in widget: a tiny forest (the sky of the hour and the tree that is growing) with the check-in line
 * on it, a pencil that opens a small text pop-up, and a microphone.
 *
 * Android widgets are RemoteViews, so this is a native layout. It cannot run Flutter or an animation of its own; the
 * picture is drawn by the app and pushed here when the tree or the light of the hour changes. When the widget is
 * made smaller, the words go first, then the microphone, until only the forest and the pencil are left.
 *
 * The widget never carries a streak, counter or badge.
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
        val scene = widgetData.getString(KEY_SCENE, null)?.let { path ->
            try {
                if (File(path).exists()) BitmapFactory.decodeFile(path) else null
            } catch (e: Exception) {
                null
            }
        }

        appWidgetIds.forEach { widgetId ->
            // The room there is, in dp, so the words can give way when the widget is shrunk.
            val options = appWidgetManager.getAppWidgetOptions(widgetId)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val showWords = width >= WORDS_MIN_WIDTH
            val showVoice = width >= VOICE_MIN_WIDTH

            val views = RemoteViews(context.packageName, R.layout.checkin_widget).apply {
                setTextViewText(R.id.widget_prompt, prompt)
                if (scene != null) {
                    setImageViewBitmap(R.id.widget_scene, scene)
                    setViewVisibility(R.id.widget_scene, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_scene, View.GONE)
                }
                setViewVisibility(R.id.widget_words, if (showWords) View.VISIBLE else View.GONE)
                setViewVisibility(R.id.widget_voice, if (showVoice) View.VISIBLE else View.GONE)

                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(LAUNCH_URI),
                    ),
                )
                // The pencil opens a small text pop-up over the home screen; the microphone opens straight to talking.
                setOnClickPendingIntent(
                    R.id.widget_write,
                    PendingIntent.getActivity(
                        context,
                        REQUEST_WRITE,
                        Intent(context, QuickWriteActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    ),
                )
                setOnClickPendingIntent(
                    R.id.widget_voice,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(VOICE_URI),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Resizing the widget redraws it, so the words appear and disappear as there is room for them. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    companion object {
        /** Shared-preferences key holding the prompt line, written from Dart. */
        const val KEY_PROMPT = "checkin_prompt"

        /** Shared-preferences key holding the path of the forest picture, written from Dart. */
        const val KEY_SCENE = "forest_scene_path"

        /** Deep link the widget opens; the app maps `checkin` to the flow. */
        const val LAUNCH_URI = "solace://checkin"

        /** Deep link for the microphone button; the app opens the voice check-in. */
        const val VOICE_URI = "solace://voice"

        private const val REQUEST_WRITE = 4101

        /** Narrower than this (in dp) there is no room for the words. */
        private const val WORDS_MIN_WIDTH = 200

        /** Narrower than this there is no room for the microphone either. */
        private const val VOICE_MIN_WIDTH = 140
    }
}
