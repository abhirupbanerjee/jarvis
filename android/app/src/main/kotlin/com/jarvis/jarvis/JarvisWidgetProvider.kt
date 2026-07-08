package com.jarvis.jarvis

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class JarvisWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            val status = widgetData.getString("widget_status", "Tap to speak") ?: "Tap to speak"
            val statusText = when (status) {
                "listening" -> "Listening..."
                "speaking" -> "Speaking..."
                "thinking" -> "Thinking..."
                "connecting" -> "Connecting..."
                else -> "Tap to speak"
            }

            views.setTextViewText(R.id.widget_status, statusText)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
