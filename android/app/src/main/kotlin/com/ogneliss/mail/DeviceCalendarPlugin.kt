package com.ogneliss.mail

// Нативная реализация MethodChannel('ogneliss/device_calendar'), которую ждёт
// lib/services/device/device_calendar_sync.dart. БЕЗ этого файла канал бросал
// MissingPluginException, и exportEvent/exportAllEvents молча возвращали false/0
// (фикция, класс Г).
//
// Интеграция (одна строка) в MainActivity.configureFlutterEngine:
//     DeviceCalendarPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
// Разрешения READ_CALENDAR/WRITE_CALENDAR уже объявлены в AndroidManifest.xml;
// запрос у пользователя — на стороне Dart (permission_handler).

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

object DeviceCalendarPlugin {
    private const val CHANNEL = "ogneliss/device_calendar"

    /** Свой календарь на телефоне без календарей (см. [createLocalCalendar]). */
    private const val LOCAL_NAME = "Ogneliss Mail"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> result.success(true)
                "addEvent" -> {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val m = call.arguments as Map<String, Any?>
                        result.success(addEvent(context, m))
                    } catch (e: Exception) {
                        result.error("WRITE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Записывает событие в первый доступный на запись календарь устройства.
    private fun addEvent(context: Context, m: Map<String, Any?>): Boolean {
        val calendarId = firstWritableCalendarId(context) ?: createLocalCalendar(context) ?: return false
        val cr = context.contentResolver
        val tz = TimeZone.getDefault().id

        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, m["title"] as? String ?: "")
            (m["description"] as? String)?.let { put(CalendarContract.Events.DESCRIPTION, it) }
            (m["location"] as? String)?.let { put(CalendarContract.Events.EVENT_LOCATION, it) }
            put(CalendarContract.Events.DTSTART, (m["startTime"] as Number).toLong())
            put(CalendarContract.Events.DTEND, (m["endTime"] as Number).toLong())
            // Весь день — полночь UTC и пояс UTC (требование календаря Android;
            // Dart передаёт такие времена с 1.8.13). Раньше шло местное время с
            // местным поясом, и восточнее Гринвича событие уходило на день
            // раньше или растягивалось на два дня.
            val allDay = m["allDay"] as? Boolean == true
            put(CalendarContract.Events.EVENT_TIMEZONE, if (allDay) "UTC" else tz)
            if (allDay) put(CalendarContract.Events.ALL_DAY, 1)
        }

        val uri = cr.insert(CalendarContract.Events.CONTENT_URI, values) ?: return false
        val eventId = ContentUris.parseId(uri)

        // Напоминание (минуты до начала), если задано.
        (m["reminderMinutes"] as? Number)?.toInt()?.let { minutes ->
            val rem = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, minutes)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            cr.insert(CalendarContract.Reminders.CONTENT_URI, rem)
        }
        return true
    }

    /// ID первого календаря, доступного на запись (уровень доступа владельца/
    /// редактора). Возвращает null, если таких нет.
    ///
    /// 1.12.x (аудит устройств): видимые и синхронизируемые — раньше
    /// скрытых (событие в скрытом календаре человек не увидит); свои
    /// календари ящиков (учётная запись «Ogneliss Mail», PhoneMirrorPlugin)
    /// не берутся — они только для чтения и перезаписываются.
    private fun firstWritableCalendarId(context: Context): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.IS_PRIMARY,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.SYNC_EVENTS,
            CalendarContract.Calendars.ACCOUNT_TYPE,
        )
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, projection, null, null, null,
        )?.use { c ->
            var firstShown: Long? = null
            var firstWritable: Long? = null
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val access = c.getInt(1)
                val isPrimary = c.getInt(2) == 1
                val shown = c.getInt(3) == 1 && c.getInt(4) == 1
                if (c.getString(5) == OGNELISS_ACCOUNT_TYPE) continue
                val writable = access >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
                if (writable) {
                    if (isPrimary && shown) return id // основной — приоритетно
                    if (shown && firstShown == null) firstShown = id
                    if (firstWritable == null) firstWritable = id
                }
            }
            return firstShown ?: firstWritable
        }
        return null
    }

    /**
     * Календарь «Ogneliss Mail» на самом телефоне (1.12.x): на прошивках без
     * сервисов Google (LineageOS, /e/OS, GrapheneOS, Huawei без входа в
     * облако) календарей бывает ноль — выгрузка молча возвращала 0. Локальный
     * календарь (ACCOUNT_TYPE_LOCAL) показывают «Календарь» Android, Etar и
     * календари оболочек; на сервер он не синхронизируется. Повторно — тот же.
     */
    private fun createLocalCalendar(context: Context): Long? = try {
        val cr = context.contentResolver
        val uri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, LOCAL_NAME)
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            .build()
        val existing = cr.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.ACCOUNT_NAME} = ? AND ${CalendarContract.Calendars.ACCOUNT_TYPE} = ?",
            arrayOf(LOCAL_NAME, CalendarContract.ACCOUNT_TYPE_LOCAL),
            null,
        )?.use { c -> if (c.moveToFirst()) c.getLong(0) else null }
        existing ?: run {
            val values = ContentValues().apply {
                put(CalendarContract.Calendars.ACCOUNT_NAME, LOCAL_NAME)
                put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
                put(CalendarContract.Calendars.NAME, LOCAL_NAME)
                put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, LOCAL_NAME)
                put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFF1D4F91.toInt()) // brandBlue
                put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
                put(CalendarContract.Calendars.OWNER_ACCOUNT, LOCAL_NAME)
                put(CalendarContract.Calendars.VISIBLE, 1)
                put(CalendarContract.Calendars.SYNC_EVENTS, 1)
                put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
            }
            cr.insert(uri, values)?.let { ContentUris.parseId(it) }
        }
    } catch (e: Exception) {
        null
    }
}
