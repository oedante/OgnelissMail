package com.ogneliss.mail

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle

/**
 * Что показывает этот виджет «Почта» (08.11.2026, план п. 8.1): все
 * непрочитанные, VIP, с флажком, «На контроле» или один ящик. Открывается
 * при добавлении виджета (Android 11 и старше) и по «Настроить» в меню
 * виджета (Android 12+, виджет добавляется сразу — как в настройках
 * приложения). Список и подписи готовит приложение (flutter.widget_mail_filters,
 * HomeWidgetService), данные по каждому варианту — тоже оно.
 *
 * Выбор хранится в состоянии виджетов («mail_filter_<id>»); без выбора —
 * как в «Настройки → Общие → Виджет «Почта»».
 */
class MailWidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val json = WidgetUi.json(this, "flutter.widget_mail_filters")
        val codes = mutableListOf<String>()
        val names = mutableListOf<String>()
        json?.optJSONArray("items")?.let { arr ->
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val f = o.optString("f")
                if (f.isEmpty()) continue
                codes.add(f)
                names.add(o.optString("t").ifEmpty { f })
            }
        }
        val current = WidgetUi.state(this).getString(MailWidget.FILTER_PREFIX + id, null)
        // Приложение ещё не заполнило список — виджет как в настройках.
        if (codes.isEmpty()) {
            done(id, current)
            return
        }
        val night = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val theme = if (night) {
            android.R.style.Theme_DeviceDefault_Dialog_Alert
        } else {
            android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        }
        AlertDialog.Builder(this, theme)
            .setTitle(json?.optString("title").orEmpty().ifEmpty { getString(R.string.widget_mail_label) })
            .setSingleChoiceItems(names.toTypedArray(), codes.indexOf(current ?: "")) { d, which ->
                d.dismiss()
                done(id, codes[which])
            }
            // Закрыли без выбора — виджет остаётся (как раньше или как в настройках).
            .setOnCancelListener { done(id, current) }
            .show()
    }

    private fun done(id: Int, filter: String?) {
        val e = WidgetUi.state(this).edit()
        if (filter == null) e.remove(MailWidget.FILTER_PREFIX + id) else e.putString(MailWidget.FILTER_PREFIX + id, filter)
        e.apply()
        runCatching { MailWidget().draw(this, AppWidgetManager.getInstance(this), id) }
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        finish()
    }
}
