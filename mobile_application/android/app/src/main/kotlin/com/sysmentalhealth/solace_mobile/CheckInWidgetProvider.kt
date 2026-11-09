package com.sysmentalhealth.solace_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class CheckInWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = Calendar.getInstance()
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now.time)
        val savedPrompt = widgetData.getString(KEY_PROMPT, null)
        val prompt = savedPrompt?.takeIf { it.startsWith("$date|") }?.substringAfter('|')
            ?: context.getString(R.string.widget_prompt_default)
        val sky = when (now.get(Calendar.HOUR_OF_DAY)) {
            in 5..7 -> Sky(R.drawable.widget_sky_golden, R.string.widget_light_morning)
            in 8..16 -> Sky(R.drawable.widget_sky_day, R.string.widget_light_day)
            in 17..18 -> Sky(R.drawable.widget_sky_golden, R.string.widget_light_golden)
            in 19..20 -> Sky(R.drawable.widget_sky_dusk, R.string.widget_light_dusk)
            else -> Sky(R.drawable.widget_sky_night, R.string.widget_light_night, moon = true)
        }
        val tree = widgetData.getString(KEY_TREE, null)?.let { BitmapFactory.decodeFile(it) }
        val open = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(LAUNCH_URI))
        val voice = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(VOICE_URI))
        val write = PendingIntent.getActivity(
            context,
            REQUEST_WRITE,
            Intent(context, QuickWriteActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val layouts = mutableMapOf<Layout, RemoteViews>()
        fun views(layout: Layout): RemoteViews = layouts.getOrPut(layout) {
            val resource = if (layout == Layout.Wide) R.layout.checkin_widget_wide else R.layout.checkin_widget
            RemoteViews(context.packageName, resource).apply {
                setImageViewResource(R.id.widget_scene, sky.drawable)
                setImageViewResource(
                    R.id.widget_celestial,
                    if (sky.moon) R.drawable.widget_moon else R.drawable.widget_orb,
                )
                setTextViewText(R.id.widget_light, context.getString(sky.label))
                setTextViewText(R.id.widget_prompt, prompt)
                setViewVisibility(R.id.widget_prompt, if (layout == Layout.Compact) View.GONE else View.VISIBLE)
                if (tree != null) setImageViewBitmap(R.id.widget_tree, tree)
                setOnClickPendingIntent(R.id.widget_root, open)
                setOnClickPendingIntent(R.id.widget_write, write)
                setOnClickPendingIntent(R.id.widget_voice, voice)
            }
        }

        appWidgetIds.forEach { id ->
            val options = appWidgetManager.getAppWidgetOptions(id)
            val sizes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                @Suppress("DEPRECATION")
                options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES).orEmpty()
            } else {
                emptyList()
            }
            val remote = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && sizes.isNotEmpty()) {
                RemoteViews(sizes.distinct().take(16).associateWith { views(layoutFor(it.width, it.height)) })
            } else {
                views(layoutFor(
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 140).toFloat(),
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 140).toFloat(),
                ))
            }
            appWidgetManager.updateAppWidget(id, remote)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    private data class Sky(val drawable: Int, val label: Int, val moon: Boolean = false)
    private enum class Layout { Compact, Tall, Wide }

    // Launchers report available space in dp. Cell sizes vary by home grid.
    private fun layoutFor(width: Float, height: Float): Layout = when {
        width >= 220 && width >= height * 0.94f -> Layout.Wide
        width >= 145 && height >= 255 -> Layout.Tall
        else -> Layout.Compact
    }

    companion object {
        const val KEY_PROMPT = "checkin_prompt"
        const val KEY_TREE = "forest_tree_path"
        const val LAUNCH_URI = "solace://checkin"
        const val VOICE_URI = "solace://voice"

        private const val REQUEST_WRITE = 4101
    }
}
