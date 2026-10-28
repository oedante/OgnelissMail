package com.ogneliss.mail

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.format.DateFormat
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/*
 * Виджеты на рабочем столе: «Мой день», «Почта», «Календарь», «Заметки».
 *
 * Данные готовит приложение (lib/services/home_widget_service.dart) и пишет
 * JSON в SharedPreferences Flutter (ключи flutter.widget_*): переведённые
 * подписи, встречи, задачи, письма, заметки. Виджет сам прячет прошедшее и
 * считает даты — между обновлениями (система будит раз в 30 минут) он не
 * устаревает.
 *
 * Сетка (переработка 10.10.2026, замечание «элементы очень близко, нет
 * сеток, всё в кучу»): поля 14 dp, шапка 40 dp, отступ 10 dp, карточка
 * 16 dp со строками не ниже 44 dp и разделителями, колонка времени 52 dp.
 * Строки добавляются кодом (RemoteViews.addView) ровно столько, сколько
 * помещается по высоте виджета, остальное — «ещё N». Размеры — в стилях
 * Widget* (values/styles.xml), здесь — только расчёт высоты.
 */

/** Общее для виджетов: данные, размеры, строки. */
internal object WidgetUi {
    private const val FLUTTER = "FlutterSharedPreferences"
    private const val STATE = "ogneliss_widgets"

    // Высоты сетки, dp (совпадают со стилями Widget*).
    const val PAD = 14 * 2
    const val HEADER = 40
    const val GAP = 10
    const val CARD_PAD = 8
    const val FOOTER = 24
    const val MORE = 32

    fun json(context: Context, key: String): JSONObject? =
        context.getSharedPreferences(FLUTTER, Context.MODE_PRIVATE).getString(key, null)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }

    fun state(context: Context) = context.getSharedPreferences(STATE, Context.MODE_PRIVATE)

    /**
     * Фон виджетов (1.6.49, настройка приложения «Фон виджетов»): 0 — обычный,
     * 1 — полупрозрачный (видны обои), 2 — без фона (текст прямо на обоях:
     * для однотонных обоев; цвет текста — по теме телефона). [cards] —
     * карточки со строками внутри виджета.
     */
    fun background(context: Context, v: RemoteViews, root: Int, vararg cards: Int) {
        val mode = runCatching {
            context.getSharedPreferences(FLUTTER, Context.MODE_PRIVATE).getLong("flutter.widget_bg", 0L).toInt()
        }.getOrDefault(0)
        when (mode) {
            1 -> {
                v.setInt(root, "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_bg_soft))
                for (c in cards) v.setInt(c, "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_card_bg_soft))
            }
            2 -> {
                v.setInt(root, "setBackgroundResource", 0)
                for (c in cards) v.setInt(c, "setBackgroundResource", 0)
            }
        }
    }

    fun locale(json: JSONObject?): Locale {
        val lang = json?.optString("lang").orEmpty()
        return if (lang.isNotEmpty()) Locale.forLanguageTag(lang) else Locale.getDefault()
    }

    /** Высота виджета в dp: в портрете — наибольшая, в альбоме — наименьшая. */
    fun heightDp(context: Context, manager: AppWidgetManager, id: Int, fallback: Int): Int {
        val o: Bundle = manager.getAppWidgetOptions(id) ?: return fallback
        val land = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val h = o.getInt(
            if (land) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
        )
        return if (h > 0) h else fallback
    }

    /** Сколько строк высотой [rowDp] помещается в [availableDp] (не меньше одной). */
    fun fit(availableDp: Int, rowDp: Int, max: Int = 20): Int = (availableDp / rowDp).coerceIn(1, max)

    fun timeFormat(context: Context, locale: Locale) =
        SimpleDateFormat(if (DateFormat.is24HourFormat(context)) "HH:mm" else "h:mm a", locale)

    fun cap(s: String, locale: Locale) = s.replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }

    /** Текст или скрыть, если пусто. */
    fun text(v: RemoteViews, id: Int, s: CharSequence?) {
        if (s.isNullOrEmpty()) {
            v.setViewVisibility(id, View.GONE)
        } else {
            v.setTextViewText(id, s)
            v.setViewVisibility(id, View.VISIBLE)
        }
    }

    /** Цвет текста из ресурса: на Android 12+ цвет берётся при показе (тема меняется — меняется и он). */
    fun textColor(context: Context, v: RemoteViews, id: Int, res0: Int) {
        val res = color(context, res0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            v.setColor(id, "setTextColor", res)
        } else {
            v.setTextColor(id, context.getColor(res))
        }
    }

    /**
     * Тема виджетов (1.7.0, настройка «Тема виджетов»): 0 — как у телефона,
     * 1 — светлая, 2 — тёмная. Лаунчер берёт цвета ресурсов по теме
     * ТЕЛЕФОНА, поэтому для светлой и тёмной у каждой разметки, фона и цвета
     * есть свой вариант (_lt / _dk, tool/dev/widget_themes.py) — здесь
     * выбирается нужный.
     */
    fun theme(context: Context): Int = runCatching {
        context.getSharedPreferences(FLUTTER, Context.MODE_PRIVATE).getLong("flutter.widget_theme", 0L).toInt()
    }.getOrDefault(0)

    private fun pick(context: Context, table: Map<Int, Pair<Int, Int>>, res: Int): Int =
        when (theme(context)) {
            1 -> table[res]?.first ?: res
            2 -> table[res]?.second ?: res
            else -> res
        }

    fun layout(context: Context, res: Int): Int = pick(context, WidgetThemeRes.layouts, res)
    fun color(context: Context, res: Int): Int = pick(context, WidgetThemeRes.colors, res)
    fun drawable(context: Context, res: Int): Int = pick(context, WidgetThemeRes.drawables, res)

    fun divider(context: Context) = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_divider))

    fun note(context: Context, text: CharSequence): RemoteViews =
        RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_more)).apply { setTextViewText(R.id.row_text, text) }

    /** Строка встречи/задачи (widget_row_event). [color] — цвет ящика; [bar] — готовая метка. */
    fun eventRow(
        context: Context, time: String, end: String?, title: String, sub: String?,
        color: Int? = null, bar: Int = 0, faded: Boolean = false,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_event))
        v.setTextViewText(R.id.ev_time, time)
        text(v, R.id.ev_end, end)
        v.setTextViewText(R.id.ev_title, title)
        text(v, R.id.ev_sub, sub)
        when {
            color != null -> v.setInt(R.id.ev_bar, "setColorFilter", color)
            bar != 0 -> v.setImageViewResource(R.id.ev_bar, drawable(context, bar))
            else -> v.setViewVisibility(R.id.ev_bar, View.INVISIBLE)
        }
        // Закончившееся — приглушённым цветом (прозрачность в виджетах
        // поддерживают не все версии Android).
        if (faded) {
            textColor(context, v, R.id.ev_title, R.color.widget_muted)
            textColor(context, v, R.id.ev_time, R.color.widget_muted)
        }
        return v
    }

    fun startOfDay(ms: Long): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = ms
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    fun addDays(dayStart: Long, n: Int): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = dayStart
        c.add(Calendar.DAY_OF_YEAR, n)
        return c.timeInMillis
    }

    /** Код запроса PendingIntent, уникальный для экземпляра виджета и элемента. */
    fun req(widgetId: Int, base: Int, k: Int) = 100_000 + (widgetId % 1000) * 200 + base + k
}

/** Общий каркас: перерисовка по расписанию системы, при смене размера и из приложения. */
abstract class OgnelissWidget : AppWidgetProvider() {
    abstract fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) draw(context, manager, id)
    }

    /** Размер изменили — пересчитать, сколько строк помещается. */
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle) {
        draw(context, manager, id)
    }

    fun draw(context: Context, manager: AppWidgetManager, id: Int) {
        runCatching { manager.updateAppWidget(id, render(context, manager, id)) }
    }

    fun drawAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (id in manager.getAppWidgetIds(ComponentName(context, this::class.java))) draw(context, manager, id)
    }
}

// ════════════════════════════════════════════════════════════════════════
// «Мой день»
// ════════════════════════════════════════════════════════════════════════

/**
 * «Мой день»: встречи и задачи на сегодня карточкой (время · метка ·
 * название), внизу — непрочитанные и письма в работе. Если в приложении
 * включена доска — три колонки Предстоит · В работе · Готово.
 * Нажатие — «Мой день», карандаш — новое письмо.
 */
class MyDayWidget : OgnelissWidget() {
    companion object {
        private const val KEY = "flutter.widget_myday"
        fun refreshAll(context: Context) = MyDayWidget().drawAll(context)
    }

    override fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val json = WidgetUi.json(context, KEY)
        val board = json?.optBoolean("board") == true
        val v = RemoteViews(context.packageName, WidgetUi.layout(context, if (board) R.layout.widget_my_day_board else R.layout.widget_my_day))
        if (board) {
            WidgetUi.background(context, v, R.id.wd_root, R.id.board_c1, R.id.board_c2, R.id.board_c3)
        } else {
            WidgetUi.background(context, v, R.id.wd_root, R.id.wd_list)
        }
        val locale = WidgetUi.locale(json)
        json?.optString("title")?.takeIf { it.isNotEmpty() }?.let { v.setTextViewText(R.id.wd_title, it) }
        WidgetUi.text(v, R.id.wd_sub, WidgetUi.cap(SimpleDateFormat("EEEE, d MMMM", locale).format(Date()), locale))
        val footer = listOf(json?.optString("unread").orEmpty(), json?.optString("work").orEmpty())
            .filter { it.isNotEmpty() }.joinToString("  ·  ")
        WidgetUi.text(v, R.id.wd_footer, footer)
        v.setContentDescription(R.id.wd_action, json?.optString("compose").orEmpty())
        v.setOnClickPendingIntent(R.id.wd_root, WidgetBridge.open(context, "myday", WidgetUi.req(id, 0, 1)))
        v.setOnClickPendingIntent(R.id.wd_action, WidgetBridge.open(context, "compose", WidgetUi.req(id, 0, 2)))

        val height = WidgetUi.heightDp(context, manager, id, 180)
        val footerDp = if (footer.isNotEmpty()) WidgetUi.FOOTER else 0
        if (board) {
            fillBoard(context, v, json!!, height - WidgetUi.PAD - WidgetUi.HEADER - WidgetUi.GAP - 16 - 22 - footerDp)
            return v
        }

        v.removeAllViews(R.id.wd_list)
        val now = System.currentTimeMillis()
        val items = mutableListOf<JSONObject>()
        json?.optJSONArray("items")?.let { arr ->
            for (i in 0 until arr.length()) arr.optJSONObject(i)?.takeIf { it.optLong("end") > now }?.let(items::add)
        }
        if (items.isEmpty()) {
            v.addView(R.id.wd_list, WidgetUi.note(context,
                json?.optString("empty")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_open_app)))
            return v
        }
        val cap = WidgetUi.fit(height - WidgetUi.PAD - WidgetUi.HEADER - WidgetUi.GAP - WidgetUi.CARD_PAD - footerDp, 45)
        val shown = if (items.size > cap) (cap - 1).coerceAtLeast(1) else items.size
        for (i in 0 until shown) {
            val item = items[i]
            if (i > 0) v.addView(R.id.wd_list, WidgetUi.divider(context))
            v.addView(R.id.wd_list, WidgetUi.eventRow(context, item.optString("t"), null, item.optString("s"), null,
                bar = if (item.optString("k") == "t") R.drawable.widget_bar_task else R.drawable.widget_bar_accent))
        }
        if (items.size > shown) {
            v.addView(R.id.wd_list, WidgetUi.divider(context))
            v.addView(R.id.wd_list, WidgetUi.note(context,
                json?.optString("more").orEmpty().ifEmpty { "+{n}" }.replace("{n}", (items.size - shown).toString())))
        }
        return v
    }

    /** Доска: три колонки одинаковой ширины, дела — сколько помещается. */
    private fun fillBoard(context: Context, v: RemoteViews, json: JSONObject, availableDp: Int) {
        val titles = intArrayOf(R.id.board_c1_title, R.id.board_c2_title, R.id.board_c3_title)
        val counts = intArrayOf(R.id.board_c1_count, R.id.board_c2_count, R.id.board_c3_count)
        val lists = intArrayOf(R.id.board_c1_list, R.id.board_c2_list, R.id.board_c3_list)
        val cap = WidgetUi.fit(availableDp, 30, 8)
        val now = System.currentTimeMillis()
        val cols = json.optJSONArray("cols")
        for (c in 0 until 3) {
            val col = cols?.optJSONObject(c)
            v.setTextViewText(titles[c], col?.optString("title").orEmpty().uppercase())
            v.removeAllViews(lists[c])
            val items = mutableListOf<String>()
            col?.optJSONArray("items")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val item = arr.optJSONObject(i) ?: continue
                    // «Предстоит»: закончившееся по времени не показываем.
                    val end = item.optLong("end", 0)
                    if (c == 0 && end in 1..now) continue
                    items.add(item.optString("s"))
                }
            }
            v.setTextViewText(counts[c], if (items.isEmpty()) "" else items.size.toString())
            val shown = if (items.size > cap) (cap - 1).coerceAtLeast(1) else items.size
            for (i in 0 until shown) {
                v.addView(lists[c], RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_board)).apply {
                    setTextViewText(R.id.row_text, items[i])
                })
            }
            if (items.size > shown) {
                v.addView(lists[c], RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_board)).apply {
                    setTextViewText(R.id.row_text, json.optString("more").replace("{n}", (items.size - shown).toString()))
                    WidgetUi.textColor(context, this, R.id.row_text, R.color.widget_sub)
                })
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════════════
// «Почта»
// ════════════════════════════════════════════════════════════════════════

/**
 * «Почта»: число непрочитанных в шапке, последние непрочитанные письма
 * карточкой (метка цвета ящика · отправитель и время · тема), внизу —
 * непрочитанные по ящикам. Нажатие на письмо — письмо, на виджет — почта,
 * карандаш — новое письмо. С PIN-кодом приложение не передаёт темы и
 * отправителей.
 */
class MailWidget : OgnelissWidget() {
    companion object {
        private const val KEY = "flutter.widget_mail"
        fun refreshAll(context: Context) = MailWidget().drawAll(context)
    }

    /**
     * Под заголовком — когда почта обновлялась (1.6.48): «Обновлено в 15:40»,
     * не сегодня — с датой. Дольше положенного (staleAt, считает приложение
     * по интервалам ящиков) — «Не обновлялось с 15:40» цветом предупреждения:
     * по рабочему столу видно, что приложение «уснуло». «Сейчас» не пишем:
     * виджет перерисовывается редко, и «сейчас» устаревало бы на часы.
     */
    private fun updated(context: Context, v: RemoteViews, json: JSONObject?) {
        val upd = json?.optLong("upd", 0L) ?: 0L
        if (json == null || upd <= 0L) {
            v.setViewVisibility(R.id.mail_sub, View.GONE)
            return
        }
        val now = System.currentTimeMillis()
        val locale = WidgetUi.locale(json)
        val time = WidgetUi.timeFormat(context, locale).format(Date(upd))
        val today = WidgetUi.startOfDay(upd) == WidgetUi.startOfDay(now)
        val stamp = if (today) time else SimpleDateFormat("d MMM", locale).format(Date(upd)) + ", " + time
        val staleAt = json.optLong("staleAt", 0L)
        val stale = staleAt in 1L until now
        val text = when {
            stale -> json.optString("updStale").replace("{time}", stamp)
            today -> json.optString("updAt").replace("{time}", stamp)
            else -> json.optString("updOn").replace("{date}", stamp)
        }
        WidgetUi.text(v, R.id.mail_sub, text)
        WidgetUi.textColor(context, v, R.id.mail_sub, if (stale) R.color.widget_warn else R.color.widget_sub)
    }

    override fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val v = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_mail))
        WidgetUi.background(context, v, R.id.mail_root, R.id.mail_list)
        val json = WidgetUi.json(context, KEY)
        json?.optString("title")?.takeIf { it.isNotEmpty() }?.let { v.setTextViewText(R.id.mail_title, it) }
        WidgetUi.text(v, R.id.mail_badge, json?.optString("count"))
        val footer = json?.optString("accounts").orEmpty()
        WidgetUi.text(v, R.id.mail_footer, footer)
        updated(context, v, json)
        v.setContentDescription(R.id.mail_action, json?.optString("compose").orEmpty())
        v.setOnClickPendingIntent(R.id.mail_root, WidgetBridge.open(context, "mail", WidgetUi.req(id, 0, 1)))
        v.setOnClickPendingIntent(R.id.mail_action, WidgetBridge.open(context, "compose", WidgetUi.req(id, 0, 2)))

        v.removeAllViews(R.id.mail_list)
        val items = json?.optJSONArray("items")
        if (items == null || items.length() == 0) {
            v.addView(R.id.mail_list, WidgetUi.note(context,
                json?.optString("empty")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_open_app)))
            return v
        }
        val height = WidgetUi.heightDp(context, manager, id, 180)
        val cap = WidgetUi.fit(height - WidgetUi.PAD - WidgetUi.HEADER - WidgetUi.GAP - WidgetUi.CARD_PAD -
            (if (footer.isNotEmpty()) WidgetUi.FOOTER else 0), 53, 10)
        for (i in 0 until minOf(items.length(), cap)) {
            val item = items.optJSONObject(i) ?: continue
            if (i > 0) v.addView(R.id.mail_list, WidgetUi.divider(context))
            val row = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_mail))
            row.setTextViewText(R.id.ml_from, item.optString("f"))
            row.setTextViewText(R.id.ml_time, item.optString("t"))
            WidgetUi.text(row, R.id.ml_subj, item.optString("s"))
            if (item.has("c")) {
                row.setInt(R.id.ml_bar, "setColorFilter", item.optLong("c").toInt())
            } else {
                row.setImageViewResource(R.id.ml_bar, WidgetUi.drawable(context, R.drawable.widget_bar_accent))
            }
            val open = item.optString("open")
            if (open.isNotEmpty()) {
                row.setOnClickPendingIntent(R.id.ml_row, WidgetBridge.open(context, open, WidgetUi.req(id, 10, i)))
            }
            v.addView(R.id.mail_list, row)
        }
        return v
    }
}

// ════════════════════════════════════════════════════════════════════════
// «Календарь»: День · Неделя · Месяц
// ════════════════════════════════════════════════════════════════════════

/**
 * «Календарь» (10.10.2026 — три вида по просьбе владельца):
 *  · День — встречи дня карточкой: время начала и конца, цвет ящика,
 *    название и место; закончившиеся — бледнее;
 *  · Неделя — полоса из семи дней (число «сегодня» в круге, цветные точки
 *    встреч) и встречи недели по дням;
 *  · Месяц — сетка 7 × 5–6 с числами и точками встреч.
 * Стрелки листают день/неделю/месяц, нажатие на период — сегодня, на день
 * недели или месяца — этот день. Вид и период — у каждого экземпляра
 * виджета свои (SharedPreferences ogneliss_widgets); пролистанный период
 * сбрасывается на сегодня через 6 часов, чтобы утром виджет не показывал
 * позавчера. Встречи — всех ящиков, включённых в календаре приложения.
 * «+» — окно «Создать» (QuickCreateActivity): встреча или задача без входа
 * в приложение.
 */
class CalendarWidget : OgnelissWidget() {
    companion object {
        private const val KEY = "flutter.widget_calendar"
        private const val ACTION_NAV = "com.ogneliss.mail.CAL_NAV"
        private const val DAY_MS = 24L * 3600 * 1000
        private const val STALE_MS = 6L * 3600 * 1000
        fun refreshAll(context: Context) = CalendarWidget().drawAll(context)
    }

    private data class Ev(
        val st: Long, val en: Long, val allDay: Boolean, val title: String, val loc: String,
        val color: Int, val open: String, val join: String,
    )

    // ── Переходы (стрелки, вкладки, дни) ──

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_NAV) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                navigate(context, id, intent.getStringExtra("op").orEmpty(), intent.getLongExtra("v", 0))
                draw(context, AppWidgetManager.getInstance(context), id)
            }
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val e = WidgetUi.state(context).edit()
        for (id in appWidgetIds) e.remove("cal_mode_$id").remove("cal_anchor_$id").remove("cal_at_$id").remove("cal_sel_$id")
        e.apply()
    }

    private fun anchorOf(context: Context, id: Int, today: Long): Long {
        val st = WidgetUi.state(context)
        val at = st.getLong("cal_at_$id", 0)
        val anchor = st.getLong("cal_anchor_$id", 0)
        return if (anchor > 0 && System.currentTimeMillis() - at < STALE_MS) anchor else today
    }

    private fun navigate(context: Context, id: Int, op: String, value: Long) {
        val st = WidgetUi.state(context)
        val today = WidgetUi.startOfDay(System.currentTimeMillis())
        val mode = st.getInt("cal_mode_$id", 0)
        val anchor = anchorOf(context, id, today)
        val e = st.edit().putLong("cal_at_$id", System.currentTimeMillis())
        when (op) {
            "mode" -> e.putInt("cal_mode_$id", value.toInt().coerceIn(0, 2)).putLong("cal_anchor_$id", anchor)
            "today" -> e.remove("cal_anchor_$id").remove("cal_sel_$id")
            // Месяц со встречами дня (1.6.49): нажатие на день — выбрать его.
            "sel" -> e.putLong("cal_sel_$id", value)
            "prev", "next" -> {
                e.remove("cal_sel_$id")
                val d = if (op == "next") 1 else -1
                val c = Calendar.getInstance().apply { timeInMillis = anchor }
                when (mode) {
                    0 -> c.add(Calendar.DAY_OF_YEAR, d)
                    1 -> c.add(Calendar.DAY_OF_YEAR, 7 * d)
                    else -> { c.set(Calendar.DAY_OF_MONTH, 1); c.add(Calendar.MONTH, d) }
                }
                e.putLong("cal_anchor_$id", WidgetUi.startOfDay(c.timeInMillis))
            }
            "day" -> e.putInt("cal_mode_$id", 0).putLong("cal_anchor_$id", value).remove("cal_sel_$id")
        }
        e.apply()
    }

    private fun nav(context: Context, id: Int, op: String, value: Long, k: Int): PendingIntent {
        val intent = Intent(context, CalendarWidget::class.java).apply {
            action = ACTION_NAV
            // Своё data на каждое нажатие: иначе система склеит PendingIntent.
            data = Uri.parse("ogneliss-widget://calendar/$id/$op/$value")
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            putExtra("op", op)
            putExtra("v", value)
        }
        return PendingIntent.getBroadcast(context, WidgetUi.req(id, 100, k), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    // ── Данные ──

    private fun events(json: JSONObject?): List<Ev> {
        val out = mutableListOf<Ev>()
        val arr = json?.optJSONArray("events") ?: return out
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(Ev(
                st = o.optLong("st"), en = o.optLong("en"), allDay = o.optInt("a") == 1,
                title = o.optString("s"), loc = o.optString("l"),
                color = o.optLong("c", 0xFF5C7CFA).toInt(), open = o.optString("o"), join = o.optString("j"),
            ))
        }
        return out.sortedWith(compareBy<Ev>({ !it.allDay }, { it.st }))
    }

    /** Встречи, задевающие день [dayStart, следующий день). */
    private fun on(evs: List<Ev>, dayStart: Long): List<Ev> {
        val next = WidgetUi.addDays(dayStart, 1)
        return evs.filter { it.st < next && it.en > dayStart }
    }

    private fun dots(evs: List<Ev>): CharSequence {
        val sb = SpannableStringBuilder()
        for (e in evs.distinctBy { it.color }.take(3)) {
            val s = sb.length
            sb.append("●")
            sb.setSpan(ForegroundColorSpan(e.color), s, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return sb
    }

    // ── Отрисовка ──

    override fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val v = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_calendar))
        WidgetUi.background(context, v, R.id.cal_root, R.id.cal_list)
        val json = WidgetUi.json(context, KEY)
        val locale = WidgetUi.locale(json)
        val now = System.currentTimeMillis()
        val today = WidgetUi.startOfDay(now)
        val mode = WidgetUi.state(context).getInt("cal_mode_$id", 0).coerceIn(0, 2)
        val anchor = anchorOf(context, id, today)
        val evs = events(json)
        // Месяц: выбранный день — сохранённый, иначе сегодня (если месяц
        // текущий), иначе первое число.
        val sel = run {
            val st = WidgetUi.state(context)
            val saved = st.getLong("cal_sel_$id", 0)
            val fresh = System.currentTimeMillis() - st.getLong("cal_at_$id", 0) < STALE_MS
            val c = Calendar.getInstance().apply { timeInMillis = anchor }
            val sameMonth = { d: Long ->
                val x = Calendar.getInstance().apply { timeInMillis = d }
                x.get(Calendar.YEAR) == c.get(Calendar.YEAR) && x.get(Calendar.MONTH) == c.get(Calendar.MONTH)
            }
            when {
                saved > 0 && fresh && sameMonth(saved) -> saved
                sameMonth(today) -> today
                else -> { c.set(Calendar.DAY_OF_MONTH, 1); WidgetUi.startOfDay(c.timeInMillis) }
            }
        }

        // Вкладки.
        val tabIds = intArrayOf(R.id.cal_tab0, R.id.cal_tab1, R.id.cal_tab2)
        val tabDefaults = intArrayOf(R.string.widget_cal_day, R.string.widget_cal_week, R.string.widget_cal_month)
        val tabs = json?.optJSONArray("tabs")
        for (i in 0..2) {
            val label = tabs?.optString(i)?.takeIf { it.isNotEmpty() } ?: context.getString(tabDefaults[i])
            if (i == mode) {
                val sb = SpannableStringBuilder(label)
                sb.setSpan(StyleSpan(Typeface.BOLD), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                v.setTextViewText(tabIds[i], sb)
                v.setInt(tabIds[i], "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_tab_sel_bg))
            } else {
                v.setTextViewText(tabIds[i], label)
                v.setInt(tabIds[i], "setBackgroundResource", 0)
                WidgetUi.textColor(context, v, tabIds[i], R.color.widget_sub)
            }
            v.setOnClickPendingIntent(tabIds[i], nav(context, id, "mode", i.toLong(), i))
        }
        v.setOnClickPendingIntent(R.id.cal_prev, nav(context, id, "prev", 0, 3))
        v.setOnClickPendingIntent(R.id.cal_next, nav(context, id, "next", 0, 4))
        v.setOnClickPendingIntent(R.id.cal_head, nav(context, id, "today", 0, 5))
        v.setOnClickPendingIntent(R.id.cal_root, WidgetBridge.open(context, "calendar", WidgetUi.req(id, 0, 1)))
        // «+» — окно «Создать» (встреча или задача) прямо на рабочем столе, на
        // день, открытый в виджете.
        val createDay = when (mode) { 0 -> anchor; 2 -> sel; else -> today }
        v.setOnClickPendingIntent(R.id.cal_action, PendingIntent.getActivity(context, WidgetUi.req(id, 0, 2),
            QuickCreateActivity.intent(context, createDay).apply {
                // Своё data у каждого экземпляра: иначе система склеит PendingIntent.
                data = Uri.parse("ogneliss-widget://create/$id/$createDay")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        v.setContentDescription(R.id.cal_action, json?.optString("add").orEmpty())

        // Неделя — с первого дня недели по настройкам телефона.
        val weekStart = run {
            val c = Calendar.getInstance()
            c.timeInMillis = anchor
            val fdw = c.firstDayOfWeek
            while (c.get(Calendar.DAY_OF_WEEK) != fdw) c.add(Calendar.DAY_OF_YEAR, -1)
            WidgetUi.startOfDay(c.timeInMillis)
        }

        // Шапка: период и подпись «Календарь».
        val calLabel = json?.optString("title")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_cal_label)
        val period = when (mode) {
            0 -> {
                val rel = when (anchor) {
                    today -> json?.optString("today").orEmpty()
                    WidgetUi.addDays(today, 1) -> json?.optString("tomorrow").orEmpty()
                    else -> ""
                }
                val date = SimpleDateFormat(if (rel.isEmpty()) "EEE, d MMMM" else "d MMMM", locale).format(Date(anchor))
                WidgetUi.cap(if (rel.isEmpty()) date else "$rel, $date", locale)
            }
            1 -> {
                val end = WidgetUi.addDays(weekStart, 6)
                val f = SimpleDateFormat("d MMM", locale)
                "${f.format(Date(weekStart))} – ${f.format(Date(end))}"
            }
            else -> WidgetUi.cap(SimpleDateFormat("LLLL yyyy", locale).format(Date(anchor)), locale)
        }
        v.setTextViewText(R.id.cal_title, period)
        WidgetUi.text(v, R.id.cal_sub, calLabel)

        // Высота: поля, шапка, вкладки (8 + 32), отступ до содержимого.
        val height = WidgetUi.heightDp(context, manager, id, 300)
        var avail = height - WidgetUi.PAD - WidgetUi.HEADER - 40 - WidgetUi.GAP

        // «Подключиться» — когда на экране сегодняшний день.
        val showsToday = mode == 0 && anchor == today || mode == 1 && today >= weekStart && today < WidgetUi.addDays(weekStart, 7)
        val join = if (showsToday && json?.optBoolean("private") != true) {
            evs.firstOrNull { it.join.isNotEmpty() && it.en > now && it.st - now <= 15L * 60 * 1000 }
        } else null
        if (join != null) {
            val t = WidgetUi.timeFormat(context, locale).format(Date(join.st))
            v.setTextViewText(R.id.cal_join, "▶  ${json?.optString("joinLabel").orEmpty()} · $t ${join.title}")
            v.setViewVisibility(R.id.cal_join, View.VISIBLE)
            val view = Intent(Intent.ACTION_VIEW, Uri.parse(join.join)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            v.setOnClickPendingIntent(R.id.cal_join, PendingIntent.getActivity(context, WidgetUi.req(id, 0, 3), view,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            avail -= 40
        } else {
            v.setViewVisibility(R.id.cal_join, View.GONE)
        }

        // Месяц со встречами выбранного дня (1.6.49, как в привычных
        // календарях): сетка постоянной высоты, под ней — встречи дня, если
        // помещается хотя бы заголовок дня и одна встреча. Иначе — сетка на
        // весь виджет, как раньше.
        val gridDp = 10 + 18 + monthRows(anchor) * 40
        val listAvail = avail - gridDp - WidgetUi.GAP - WidgetUi.CARD_PAD - 26
        val monthList = mode == 2 && listAvail >= 45
        v.setViewVisibility(R.id.cal_strip, if (mode == 1) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.cal_month, if (mode == 2 && !monthList) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.cal_month_fixed, if (monthList) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.cal_list, if (mode == 2 && !monthList) View.GONE else View.VISIBLE)
        v.removeAllViews(R.id.cal_list)
        v.removeAllViews(R.id.cal_strip)
        v.removeAllViews(R.id.cal_month)
        v.removeAllViews(R.id.cal_month_fixed)

        when (mode) {
            0 -> renderDay(context, v, id, json, locale, evs, anchor, now, avail - WidgetUi.CARD_PAD)
            1 -> renderWeek(context, v, id, json, locale, evs, weekStart, today, avail - 66 - WidgetUi.CARD_PAD)
            else -> if (monthList) {
                renderMonth(context, v, id, locale, evs, anchor, today, R.id.cal_month_fixed, sel)
                // Заголовок выбранного дня (нажатие — вид «День») и его встречи.
                val head = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_day))
                val label = when (sel) {
                    today -> "${json?.optString("today").orEmpty()}, ${SimpleDateFormat("d MMM", locale).format(Date(sel))}"
                    else -> WidgetUi.cap(SimpleDateFormat("EEE, d MMM", locale).format(Date(sel)), locale)
                }
                head.setTextViewText(R.id.row_text, label)
                head.setOnClickPendingIntent(R.id.row_text, nav(context, id, "day", sel, 90))
                v.addView(R.id.cal_list, head)
                renderDay(context, v, id, json, locale, evs, sel, now, listAvail)
            } else {
                renderMonth(context, v, id, locale, evs, anchor, today, R.id.cal_month, null)
            }
        }
        return v
    }

    /** Сколько недель занимает месяц [anchor] в сетке (5 или 6, как в renderMonth). */
    private fun monthRows(anchor: Long): Int {
        val c = Calendar.getInstance()
        c.timeInMillis = anchor
        c.set(Calendar.DAY_OF_MONTH, 1)
        val month = c.get(Calendar.MONTH)
        val first = WidgetUi.startOfDay(c.timeInMillis)
        val fdw = c.firstDayOfWeek
        while (c.get(Calendar.DAY_OF_WEEK) != fdw) c.add(Calendar.DAY_OF_YEAR, -1)
        var day = WidgetUi.startOfDay(c.timeInMillis)
        val cal = Calendar.getInstance()
        var rows = 0
        for (w in 0 until 6) {
            cal.timeInMillis = day
            if (w >= 4 && cal.get(Calendar.MONTH) != month && day > first) break
            rows++
            day = WidgetUi.addDays(day, 7)
        }
        return rows
    }

    private fun eventRow(context: Context, json: JSONObject?, locale: Locale, e: Ev, dayStart: Long, now: Long): RemoteViews {
        val fmt = WidgetUi.timeFormat(context, locale)
        val next = WidgetUi.addDays(dayStart, 1)
        val allDayLabel = json?.optString("allDay")?.takeIf { it.isNotEmpty() } ?: "—"
        val whole = e.allDay || (e.st <= dayStart && e.en >= next)
        val time = when {
            whole -> allDayLabel
            e.st < dayStart -> "…"
            else -> fmt.format(Date(e.st))
        }
        val end = if (whole) null else if (e.en > next) "…" else fmt.format(Date(e.en))
        return WidgetUi.eventRow(context, time, end, e.title, e.loc.ifEmpty { null }, color = e.color,
            faded = e.en <= now)
    }

    private fun clickable(context: Context, row: RemoteViews, id: Int, e: Ev, k: Int) {
        if (e.open.isNotEmpty()) {
            row.setOnClickPendingIntent(R.id.ev_row, WidgetBridge.open(context, e.open, WidgetUi.req(id, 20, k)))
        }
    }

    private fun more(context: Context, json: JSONObject?, n: Int) =
        WidgetUi.note(context, json?.optString("more").orEmpty().ifEmpty { "+{n}" }.replace("{n}", n.toString()))

    private fun renderDay(
        context: Context, v: RemoteViews, id: Int, json: JSONObject?, locale: Locale,
        evs: List<Ev>, day: Long, now: Long, availDp: Int,
    ) {
        val list = on(evs, day)
        if (list.isEmpty()) {
            v.addView(R.id.cal_list, WidgetUi.note(context, json?.optString("free")?.takeIf { it.isNotEmpty() }
                ?: context.getString(R.string.widget_open_app)))
            return
        }
        val cap = WidgetUi.fit(availDp, 45, 12)
        val shown = if (list.size > cap) (cap - 1).coerceAtLeast(1) else list.size
        for (i in 0 until shown) {
            if (i > 0) v.addView(R.id.cal_list, WidgetUi.divider(context))
            val row = eventRow(context, json, locale, list[i], day, now)
            clickable(context, row, id, list[i], i)
            v.addView(R.id.cal_list, row)
        }
        if (list.size > shown) {
            v.addView(R.id.cal_list, WidgetUi.divider(context))
            v.addView(R.id.cal_list, more(context, json, list.size - shown))
        }
    }

    private fun renderWeek(
        context: Context, v: RemoteViews, id: Int, json: JSONObject?, locale: Locale,
        evs: List<Ev>, weekStart: Long, today: Long, availDp: Int,
    ) {
        // Полоса из семи дней.
        val strip = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_week_row))
        val cells = intArrayOf(R.id.wk_cell0, R.id.wk_cell1, R.id.wk_cell2, R.id.wk_cell3, R.id.wk_cell4, R.id.wk_cell5, R.id.wk_cell6)
        val names = intArrayOf(R.id.wk_day0, R.id.wk_day1, R.id.wk_day2, R.id.wk_day3, R.id.wk_day4, R.id.wk_day5, R.id.wk_day6)
        val nums = intArrayOf(R.id.wk_num0, R.id.wk_num1, R.id.wk_num2, R.id.wk_num3, R.id.wk_num4, R.id.wk_num5, R.id.wk_num6)
        val dotIds = intArrayOf(R.id.wk_dots0, R.id.wk_dots1, R.id.wk_dots2, R.id.wk_dots3, R.id.wk_dots4, R.id.wk_dots5, R.id.wk_dots6)
        val wd = SimpleDateFormat("EE", locale)
        val dn = SimpleDateFormat("d", locale)
        for (i in 0..6) {
            val d = WidgetUi.addDays(weekStart, i)
            strip.setTextViewText(names[i], WidgetUi.cap(wd.format(Date(d)), locale).trimEnd('.'))
            strip.setTextViewText(nums[i], dn.format(Date(d)))
            if (d == today) {
                strip.setInt(nums[i], "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_today_circle))
                WidgetUi.textColor(context, strip, nums[i], R.color.widget_on_accent)
            }
            strip.setTextViewText(dotIds[i], dots(on(evs, d)))
            strip.setOnClickPendingIntent(cells[i], nav(context, id, "day", d, 10 + i))
        }
        v.addView(R.id.cal_strip, strip)

        // Встречи недели по дням — с сегодняшнего, если неделя текущая.
        val weekEnd = WidgetUi.addDays(weekStart, 7)
        val from = if (today in weekStart until weekEnd) today else weekStart
        var left = availDp
        var added = 0
        var hidden = 0
        var k = 0
        var d = from
        while (d < weekEnd) {
            val list = on(evs, d)
            if (list.isNotEmpty()) {
                // Заголовок дня + хотя бы одна строка, и место под «ещё N».
                if (left >= 26 + 45 + WidgetUi.MORE || (left >= 26 + 45 && hidden == 0 && isLastWithEvents(evs, d, weekEnd))) {
                    val head = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_day))
                    val label = when (d) {
                        today -> "${json?.optString("today").orEmpty()}, ${SimpleDateFormat("d MMM", locale).format(Date(d))}"
                        else -> SimpleDateFormat("EEE, d MMM", locale).format(Date(d))
                    }
                    head.setTextViewText(R.id.row_text, label)
                    head.setOnClickPendingIntent(R.id.row_text, nav(context, id, "day", d, 20 + k))
                    v.addView(R.id.cal_list, head)
                    left -= 26
                    for ((j, e) in list.withIndex()) {
                        val roomForMore = if (j == list.size - 1 && isLastWithEvents(evs, d, weekEnd)) 0 else WidgetUi.MORE
                        if (left < 45 + roomForMore) { hidden += list.size - j; break }
                        if (j > 0) v.addView(R.id.cal_list, WidgetUi.divider(context))
                        val row = eventRow(context, json, locale, e, d, System.currentTimeMillis())
                        clickable(context, row, id, e, k++)
                        v.addView(R.id.cal_list, row)
                        left -= 46
                        added++
                    }
                } else {
                    hidden += list.size
                }
            }
            d = WidgetUi.addDays(d, 1)
        }
        if (added == 0 && hidden == 0) {
            v.addView(R.id.cal_list, WidgetUi.note(context, json?.optString("freeWeek")?.takeIf { it.isNotEmpty() }
                ?: json?.optString("free").orEmpty().ifEmpty { context.getString(R.string.widget_open_app) }))
        } else if (hidden > 0) {
            v.addView(R.id.cal_list, more(context, json, hidden))
        }
    }

    private fun isLastWithEvents(evs: List<Ev>, day: Long, weekEnd: Long): Boolean {
        var d = WidgetUi.addDays(day, 1)
        while (d < weekEnd) {
            if (on(evs, d).isNotEmpty()) return false
            d = WidgetUi.addDays(d, 1)
        }
        return true
    }

    /**
     * [container] — куда строить; [sel] — выбранный день (месяц со встречами
     * дня, 1.6.49): строки постоянной высоты, сегодня — заливкой акцента,
     * выбранный — светлой; нажатие на день — выбрать, на выбранный — вид
     * «День». null — сетка на весь виджет, нажатие — вид «День», как раньше.
     */
    private fun renderMonth(
        context: Context, v: RemoteViews, id: Int, locale: Locale,
        evs: List<Ev>, anchor: Long, today: Long, container: Int, sel: Long?,
    ) {
        val c = Calendar.getInstance()
        c.timeInMillis = anchor
        c.set(Calendar.DAY_OF_MONTH, 1)
        val month = c.get(Calendar.MONTH)
        val first = WidgetUi.startOfDay(c.timeInMillis)
        val fdw = c.firstDayOfWeek
        while (c.get(Calendar.DAY_OF_WEEK) != fdw) c.add(Calendar.DAY_OF_YEAR, -1)
        val gridStart = WidgetUi.startOfDay(c.timeInMillis)

        // Дни недели.
        val head = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_month_head))
        val headIds = intArrayOf(R.id.mh0, R.id.mh1, R.id.mh2, R.id.mh3, R.id.mh4, R.id.mh5, R.id.mh6)
        val wd = SimpleDateFormat("EE", locale)
        for (i in 0..6) {
            head.setTextViewText(headIds[i], WidgetUi.cap(wd.format(Date(WidgetUi.addDays(gridStart, i))), locale).trimEnd('.'))
        }
        v.addView(container, head)

        // Строки недель: столько, сколько занимает месяц (5 или 6).
        val cellIds = intArrayOf(R.id.mc0, R.id.mc1, R.id.mc2, R.id.mc3, R.id.mc4, R.id.mc5, R.id.mc6)
        val cal = Calendar.getInstance()
        var day = gridStart
        var k = 0
        for (w in 0 until 6) {
            cal.timeInMillis = day
            if (w >= 4 && cal.get(Calendar.MONTH) != month && day > first) break
            val row = RemoteViews(context.packageName, WidgetUi.layout(context,
                if (sel == null) R.layout.widget_month_row else R.layout.widget_month_row_fixed))
            for (i in 0..6) {
                cal.timeInMillis = day
                val inMonth = cal.get(Calendar.MONTH) == month
                val sb = SpannableStringBuilder(cal.get(Calendar.DAY_OF_MONTH).toString())
                if (day == today || day == sel) sb.setSpan(StyleSpan(Typeface.BOLD), 0, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.append("\n")
                val d = dots(on(evs, day))
                val s = sb.length
                sb.append(if (d.isEmpty()) " " else d)
                sb.setSpan(RelativeSizeSpan(0.6f), s, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                row.setTextViewText(cellIds[i], sb)
                if (sel == null) {
                    if (day == today) row.setInt(cellIds[i], "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_today_cell))
                    if (!inMonth) WidgetUi.textColor(context, row, cellIds[i], R.color.widget_muted)
                    row.setOnClickPendingIntent(cellIds[i], nav(context, id, "day", day, 30 + k++))
                } else {
                    when {
                        day == today -> {
                            row.setInt(cellIds[i], "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_day_today))
                            WidgetUi.textColor(context, row, cellIds[i], R.color.widget_on_accent)
                        }
                        day == sel -> row.setInt(cellIds[i], "setBackgroundResource", WidgetUi.drawable(context, R.drawable.widget_day_sel))
                        !inMonth -> WidgetUi.textColor(context, row, cellIds[i], R.color.widget_muted)
                    }
                    // Выбранный день — ещё раз: его вид «День».
                    row.setOnClickPendingIntent(cellIds[i], nav(context, id, if (day == sel) "day" else "sel", day, 30 + k++))
                }
                day = WidgetUi.addDays(day, 1)
            }
            v.addView(container, row)
        }
    }
}

// ════════════════════════════════════════════════════════════════════════
// «Заметки»
// ════════════════════════════════════════════════════════════════════════

/**
 * «Заметки»: последние заметки карточкой (заголовок и первая строка),
 * нажатие — заметка, «+» — новая, виджет — список заметок. С PIN-кодом
 * приложение передаёт только число заметок.
 */
class NotesWidget : OgnelissWidget() {
    companion object {
        private const val KEY = "flutter.widget_notes"
        fun refreshAll(context: Context) = NotesWidget().drawAll(context)
    }

    override fun render(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val v = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_notes))
        WidgetUi.background(context, v, R.id.note_root, R.id.note_list)
        val json = WidgetUi.json(context, KEY)
        json?.optString("title")?.takeIf { it.isNotEmpty() }?.let { v.setTextViewText(R.id.note_title, it) }
        WidgetUi.text(v, R.id.note_badge, json?.optString("count"))
        v.setContentDescription(R.id.note_action, json?.optString("add").orEmpty())
        v.setOnClickPendingIntent(R.id.note_root, WidgetBridge.open(context, "notes", WidgetUi.req(id, 0, 1)))
        v.setOnClickPendingIntent(R.id.note_action, WidgetBridge.open(context, "newnote", WidgetUi.req(id, 0, 2)))

        v.removeAllViews(R.id.note_list)
        val items = json?.optJSONArray("items")
        if (items == null || items.length() == 0) {
            v.addView(R.id.note_list, WidgetUi.note(context,
                json?.optString("empty")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_open_app)))
            return v
        }
        val height = WidgetUi.heightDp(context, manager, id, 180)
        val cap = WidgetUi.fit(height - WidgetUi.PAD - WidgetUi.HEADER - WidgetUi.GAP - WidgetUi.CARD_PAD, 49, 10)
        for (i in 0 until minOf(items.length(), cap)) {
            val item = items.optJSONObject(i) ?: continue
            if (i > 0) v.addView(R.id.note_list, WidgetUi.divider(context))
            val row = RemoteViews(context.packageName, WidgetUi.layout(context, R.layout.widget_row_note))
            row.setTextViewText(R.id.nt_title, item.optString("s"))
            WidgetUi.text(row, R.id.nt_prev, item.optString("p"))
            val open = item.optString("open")
            if (open.isNotEmpty()) {
                row.setOnClickPendingIntent(R.id.nt_row, WidgetBridge.open(context, open, WidgetUi.req(id, 10, i)))
            }
            v.addView(R.id.note_list, row)
        }
        return v
    }
}

/**
 * Канал ogneliss/widget: «refresh» — перерисовать виджеты; «take» — какой
 * экран открыть по нажатию на виджет (холодный запуск). Если приложение уже
 * открыто, Dart получает «open» и забирает значение тем же «take».
 */
object WidgetBridge {
    const val EXTRA = "ogneliss_widget"

    @Volatile
    private var pending: String? = null
    private var channel: MethodChannel? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        channel = MethodChannel(messenger, "ogneliss/widget").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        runCatching { MyDayWidget.refreshAll(app) }
                        runCatching { MailWidget.refreshAll(app) }
                        runCatching { CalendarWidget.refreshAll(app) }
                        runCatching { NotesWidget.refreshAll(app) }
                        result.success(null)
                    }
                    "take" -> {
                        val t = pending
                        pending = null
                        result.success(t)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Нажатие на виджет: открыть приложение и передать, какой экран показать. */
    fun open(context: Context, type: String, request: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            // Своё действие на каждое нажатие: иначе система склеит PendingIntent
            // и все строки откроют одно и то же письмо.
            action = "com.ogneliss.mail.WIDGET_$request"
            putExtra(EXTRA, type)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(context, request, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun handle(intent: Intent?) {
        val type = intent?.getStringExtra(EXTRA) ?: return
        intent?.removeExtra(EXTRA)
        pending = type
        runCatching { channel?.invokeMethod("open", null) }
    }
}
