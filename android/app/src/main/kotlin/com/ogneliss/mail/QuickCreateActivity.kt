package com.ogneliss.mail

import android.app.Activity
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.format.DateFormat
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.Spinner
import android.widget.TextView
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Окно «Создать» виджета «Календарь»: встреча или задача без входа в
 * приложение (просьба владельца 10.10.2026).
 *
 * Встреча — название, дата, время начала и конца (или «весь день»), ящик.
 * Задача — название, срок (или «без срока»), напоминание. Дата и время
 * выбираются барабанами. Подписи — на языке приложения (их пишет приложение
 * в данные виджета, ключ «qc»).
 *
 * «Создать» кладёт запрос в очередь (flutter.widget_create_queue) и будит
 * Dart: движок работает — вызов «create» канала ogneliss/widget; движка нет
 * — он запускается (MainActivity.ensureEngine), очередь разбирается при
 * запуске (lib/services/calendar/quick_create_service.dart). Встреча сразу
 * появляется в виджете (предварительная запись), после создания на сервере
 * её заменяют данные приложения.
 */
class QuickCreateActivity : Activity() {
    companion object {
        private const val PREFS = "FlutterSharedPreferences"
        private const val QUEUE = "flutter.widget_create_queue"
        private const val CAL = "flutter.widget_calendar"
        const val EXTRA_DAY = "day"

        fun intent(context: Context, day: Long): Intent =
            Intent(context, QuickCreateActivity::class.java).apply {
                putExtra(EXTRA_DAY, day)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
    }

    private var json: JSONObject? = null
    private var qc: JSONObject? = null
    private lateinit var locale: Locale

    private var task = false
    private val day: Calendar = Calendar.getInstance()
    private var startMin = 9 * 60
    private var endMin = 10 * 60
    private var allDay = false
    private var noDate = false
    private var remind = false
    private var remMin = 9 * 60
    private val accountIds = mutableListOf<String>()
    private val accountColors = mutableListOf<Int>()

    private fun t(key: String, fallback: String) = qc?.optString(key)?.takeIf { it.isNotEmpty() } ?: fallback

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_quick_create)
        json = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(CAL, null)
            ?.let { runCatching { JSONObject(it) }.getOrNull() }
        qc = json?.optJSONObject("qc")
        locale = WidgetUi.locale(json)

        // День — тот, что открыт в виджете (вид «День»), иначе сегодня.
        val now = Calendar.getInstance()
        val asked = intent.getLongExtra(EXTRA_DAY, 0)
        day.timeInMillis = if (asked > 0) asked else now.timeInMillis
        if (WidgetUi.startOfDay(day.timeInMillis) == WidgetUi.startOfDay(now.timeInMillis)) {
            // Сегодня — ближайшие полчаса.
            val m = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
            startMin = ((m / 30) + 1) * 30
            if (startMin > 23 * 60) startMin = 23 * 60
        }
        endMin = (startMin + 60).coerceAtMost(23 * 60 + 59)
        remMin = startMin

        findViewById<TextView>(R.id.qc_title).text = t("title", "Create")
        findViewById<RadioButton>(R.id.qc_event).text = t("event", "Meeting")
        findViewById<RadioButton>(R.id.qc_task).text = t("task", "Task")
        val name = findViewById<EditText>(R.id.qc_name)
        name.hint = t("name", "Title")
        name.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE) { create(); true } else false
        }
        findViewById<CheckBox>(R.id.qc_allday).text = t("allDay", "All day")
        findViewById<CheckBox>(R.id.qc_nodate).text = t("noDate", "No due date")
        findViewById<CheckBox>(R.id.qc_remind).text = t("remind", "Remind me")
        findViewById<Button>(R.id.qc_cancel).text = t("cancel", "Cancel")
        findViewById<Button>(R.id.qc_create).text = t("create", "Create")

        findViewById<RadioGroup>(R.id.qc_kind).setOnCheckedChangeListener { _, id ->
            task = id == R.id.qc_task
            refresh()
        }
        findViewById<CheckBox>(R.id.qc_allday).setOnCheckedChangeListener { _, v -> allDay = v; refresh() }
        findViewById<CheckBox>(R.id.qc_nodate).setOnCheckedChangeListener { _, v -> noDate = v; refresh() }
        findViewById<CheckBox>(R.id.qc_remind).setOnCheckedChangeListener { _, v -> remind = v; refresh() }
        findViewById<View>(R.id.qc_date).setOnClickListener { pickDate() }
        findViewById<View>(R.id.qc_start).setOnClickListener { pickTime(startMin) { m ->
            val len = endMin - startMin
            startMin = m
            endMin = (m + len.coerceAtLeast(15)).coerceAtMost(23 * 60 + 59)
        } }
        findViewById<View>(R.id.qc_end).setOnClickListener { pickTime(endMin) { m ->
            endMin = if (m > startMin) m else (startMin + 30).coerceAtMost(23 * 60 + 59)
        } }
        findViewById<View>(R.id.qc_rem_time).setOnClickListener { pickTime(remMin) { m -> remMin = m; remind = true } }
        findViewById<View>(R.id.qc_cancel).setOnClickListener { finish() }
        findViewById<View>(R.id.qc_create).setOnClickListener { create() }

        setupAccounts()
        refresh()
        name.requestFocus()
    }

    /** Ящики (если их несколько): первым — активный в приложении. */
    private fun setupAccounts() {
        val arr = json?.optJSONArray("accounts") ?: return
        val def = json?.optString("defaultAccount").orEmpty()
        val labels = mutableListOf<String>()
        for (i in 0 until arr.length()) {
            val a = arr.optJSONObject(i) ?: continue
            accountIds.add(a.optString("id"))
            accountColors.add(a.optLong("c", 0xFF5C7CFA).toInt())
            labels.add(a.optString("label").ifEmpty { a.optString("id") })
        }
        if (accountIds.size < 2) return
        val spinner = findViewById<Spinner>(R.id.qc_account)
        spinner.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, labels)
        accountIds.indexOf(def).takeIf { it >= 0 }?.let { spinner.setSelection(it) }
        spinner.visibility = View.VISIBLE
        findViewById<TextView>(R.id.qc_account_label).apply {
            text = t("account", "Account")
            visibility = View.VISIBLE
        }
    }

    private fun hm(min: Int): String {
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, min / 60)
        c.set(Calendar.MINUTE, min % 60)
        return WidgetUi.timeFormat(this, locale).format(c.time)
    }

    private fun refresh() {
        val date = WidgetUi.cap(SimpleDateFormat("EEEE, d MMMM", locale).format(day.time), locale)
        val dateView = findViewById<TextView>(R.id.qc_date)
        dateView.text = date
        dateView.visibility = if (task && noDate) View.GONE else View.VISIBLE
        findViewById<View>(R.id.qc_times).visibility = if (!task && !allDay) View.VISIBLE else View.GONE
        findViewById<TextView>(R.id.qc_start).text = hm(startMin)
        findViewById<TextView>(R.id.qc_end).text = hm(endMin)
        findViewById<View>(R.id.qc_allday).visibility = if (task) View.GONE else View.VISIBLE
        findViewById<View>(R.id.qc_nodate).visibility = if (task) View.VISIBLE else View.GONE
        findViewById<View>(R.id.qc_remind_row).visibility = if (task && !noDate) View.VISIBLE else View.GONE
        findViewById<CheckBox>(R.id.qc_remind).isChecked = remind
        findViewById<TextView>(R.id.qc_rem_time).apply {
            text = hm(remMin)
            alpha = if (remind) 1f else 0.5f
        }
    }

    private fun pickDate() {
        DatePickerDialog(this, R.style.QuickPickerTheme, { _, y, m, d ->
            day.set(y, m, d)
            refresh()
        }, day.get(Calendar.YEAR), day.get(Calendar.MONTH), day.get(Calendar.DAY_OF_MONTH)).show()
    }

    private fun pickTime(current: Int, set: (Int) -> Unit) {
        TimePickerDialog(this, R.style.QuickPickerTheme, { _, h, m ->
            set(h * 60 + m)
            refresh()
        }, current / 60, current % 60, DateFormat.is24HourFormat(this)).show()
    }

    private fun at(min: Int): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = WidgetUi.startOfDay(day.timeInMillis)
        c.add(Calendar.MINUTE, min)
        return c.timeInMillis
    }

    private fun create() {
        val title = findViewById<EditText>(R.id.qc_name).text.toString().trim()
        val error = findViewById<TextView>(R.id.qc_error)
        if (title.isEmpty()) {
            error.text = t("empty", "Enter a title")
            error.visibility = View.VISIBLE
            return
        }
        val spinner = findViewById<Spinner>(R.id.qc_account)
        val accIndex = if (spinner.visibility == View.VISIBLE) spinner.selectedItemPosition else 0
        val acc = accountIds.getOrNull(accIndex)
        val dayStart = WidgetUi.startOfDay(day.timeInMillis)
        val req = JSONObject().put("title", title)
        acc?.let { req.put("acc", it) }
        if (task) {
            req.put("t", "task")
            if (!noDate) {
                req.put("due", dayStart)
                if (remind) req.put("rem", at(remMin))
            }
        } else {
            req.put("t", "event")
            if (allDay) {
                req.put("a", true)
                req.put("st", dayStart)
                req.put("en", WidgetUi.addDays(dayStart, 1))
            } else {
                req.put("st", at(startMin))
                req.put("en", at(endMin))
            }
        }
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = prefs.getString(QUEUE, null)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: JSONArray()
        queue.put(req)
        val edit = prefs.edit().putString(QUEUE, queue.toString())

        // Встреча — сразу в виджете (предварительно, до ответа сервера).
        if (!task) {
            val cal = json ?: JSONObject()
            val events = cal.optJSONArray("events") ?: JSONArray().also { cal.put("events", it) }
            events.put(JSONObject()
                .put("st", req.optLong("st"))
                .put("en", req.optLong("en"))
                .put("a", if (allDay) 1 else 0)
                .put("s", title)
                .put("c", accountColors.getOrNull(accIndex) ?: 0xFF5C7CFA.toInt()))
            edit.putString(CAL, cal.toString())
        }
        edit.commit()
        runCatching { CalendarWidget.refreshAll(applicationContext) }

        // Разбудить приложение: движок работает — сразу, иначе — запустить.
        val engine = FlutterEngineCache.getInstance().get(MainActivity.ENGINE_ID)
        if (engine != null) {
            runCatching { MethodChannel(engine.dartExecutor.binaryMessenger, "ogneliss/widget").invokeMethod("create", null) }
        } else {
            runCatching { MainActivity.ensureEngine(applicationContext) }
        }
        finish()
    }
}
