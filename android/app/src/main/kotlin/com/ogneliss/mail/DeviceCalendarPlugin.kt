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
        val calendarId = firstWritableCalendarId(context) ?: return false
        val cr = context.contentResolver
        val tz = TimeZone.getDefault().id

        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, m["title"] as? String ?: "")
            (m["description"] as? String)?.let { put(CalendarContract.Events.DESCRIPTION, it) }
            (m["location"] as? String)?.let { put(CalendarContract.Events.EVENT_LOCATION, it) }
            put(CalendarContract.Events.DTSTART, (m["startTime"] as Number).toLong())
            put(CalendarContract.Events.DTEND, (m["endTime"] as Number).toLong())
            put(CalendarContract.Events.EVENT_TIMEZONE, tz)
            if (m["allDay"] as? Boolean == true) put(CalendarContract.Events.ALL_DAY, 1)
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
    private fun firstWritableCalendarId(context: Context): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.IS_PRIMARY,
        )
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI, projection, null, null, null,
        )?.use { c ->
            var firstWritable: Long? = null
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val access = c.getInt(1)
                val isPrimary = c.getInt(2) == 1
                val writable = access >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
                if (writable) {
                    if (isPrimary) return id // основной — приоритетно
                    if (firstWritable == null) firstWritable = id
                }
            }
            return firstWritable
        }
        return null
    }
}
