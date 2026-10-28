package com.ogneliss.mail

// Контакты и календарь ящиков — в телефоне (MethodChannel 'ogneliss/phone_mirror',
// Dart: lib/services/device/phone_mirror_service.dart).
//
// Каждый ящик — отдельная учётная запись типа «Ogneliss Mail» (см.
// PhoneAccountServices.kt). Под ней:
//  · контакты ящика — определитель номера в «Телефоне» и Ogneliss Dialer,
//    поиск в «Контактах»; с личными контактами Google не смешиваются;
//  · календарь ящика — только для чтения (изменения делаются в приложении и
//    уходят на сервер; правка в календаре телефона не синхронизировалась бы).
// Направление — из приложения в телефон. Удаление ящика или выключение
// переключателя удаляет его данные из телефона целиком.
//
// Записи узнаются по SOURCE_ID / _SYNC_ID (id в приложении) и хэшу полей
// (SYNC1 / SYNC_DATA1): неизменённые не переписываются.

import android.accounts.Account
import android.accounts.AccountManager
import android.content.ContentProviderOperation
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.provider.ContactsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone
import java.util.concurrent.Executors

object PhoneMirrorPlugin {
    private const val CHANNEL = "ogneliss/phone_mirror"
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "ping") {
                result.success(true)
                return@setMethodCallHandler
            }
            @Suppress("UNCHECKED_CAST")
            val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
            worker.execute {
                try {
                    val value: Any? = when (call.method) {
                        "syncContacts" -> syncContacts(app, args)
                        "syncEvents" -> syncEvents(app, args)
                        "remove" -> { remove(app, args); true }
                        "prune" -> prune(app, args)
                        else -> {
                            main.post { result.notImplemented() }
                            return@execute
                        }
                    }
                    main.post { result.success(value) }
                } catch (e: SecurityException) {
                    main.post { result.error("NO_PERMISSION", e.message, null) }
                } catch (e: Exception) {
                    main.post { result.error("FAILED", e.message, null) }
                }
            }
        }
    }

    // ───────────────────────── Учётная запись ─────────────────────────

    private fun ensureAccount(ctx: Context, name: String): Account {
        val am = AccountManager.get(ctx)
        val account = Account(name, OGNELISS_ACCOUNT_TYPE)
        if (am.getAccountsByType(OGNELISS_ACCOUNT_TYPE).none { it.name == name }) {
            am.addAccountExplicitly(account, null, null)
        }
        return account
    }

    private fun findAccount(ctx: Context, name: String): Account? =
        AccountManager.get(ctx).getAccountsByType(OGNELISS_ACCOUNT_TYPE).firstOrNull { it.name == name }

    /** Ящики, которых больше нет в приложении, — убрать из телефона. */
    private fun prune(ctx: Context, args: Map<String, Any?>): Int {
        @Suppress("UNCHECKED_CAST")
        val keep = (args["keep"] as? List<String>)?.toSet() ?: return 0
        val am = AccountManager.get(ctx)
        var n = 0
        for (a in am.getAccountsByType(OGNELISS_ACCOUNT_TYPE)) {
            if (a.name !in keep) {
                am.removeAccountExplicitly(a)
                n++
            }
        }
        return n
    }

    /** Выключили переключатель: удалить контакты и/или календарь ящика. */
    private fun remove(ctx: Context, args: Map<String, Any?>) {
        val name = args["account"] as? String ?: return
        val account = findAccount(ctx, name) ?: return
        val cr = ctx.contentResolver
        if (args["removeAccount"] == true) {
            // Вместе с учётной записью система удаляет её контакты и календари.
            AccountManager.get(ctx).removeAccountExplicitly(account)
            return
        }
        if (args["contacts"] == true) {
            cr.delete(
                contactsSyncUri(ContactsContract.RawContacts.CONTENT_URI, account),
                "${ContactsContract.RawContacts.ACCOUNT_NAME} = ? AND ${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
                arrayOf(account.name, account.type),
            )
        }
        if (args["calendar"] == true) {
            cr.delete(
                calendarSyncUri(CalendarContract.Calendars.CONTENT_URI, account),
                "${CalendarContract.Calendars.ACCOUNT_NAME} = ? AND ${CalendarContract.Calendars.ACCOUNT_TYPE} = ?",
                arrayOf(account.name, account.type),
            )
        }
    }

    // ───────────────────────── Контакты ─────────────────────────

    private fun contactsSyncUri(base: Uri, a: Account): Uri = base.buildUpon()
        .appendQueryParameter(ContactsContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(ContactsContract.RawContacts.ACCOUNT_NAME, a.name)
        .appendQueryParameter(ContactsContract.RawContacts.ACCOUNT_TYPE, a.type)
        .build()

    /** Возвращает число записанных (новых и изменённых) контактов. */
    private fun syncContacts(ctx: Context, args: Map<String, Any?>): Int {
        val name = args["account"] as? String ?: return 0
        @Suppress("UNCHECKED_CAST")
        val items = (args["contacts"] as? List<Map<String, Any?>>) ?: emptyList()
        val account = ensureAccount(ctx, name)
        val cr = ctx.contentResolver
        val rawUri = contactsSyncUri(ContactsContract.RawContacts.CONTENT_URI, account)
        val dataUri = contactsSyncUri(ContactsContract.Data.CONTENT_URI, account)

        // Группа ящика видна в «Контактах» (без неё часть приложений прячет
        // контакты учётных записей без групп).
        try {
            cr.insert(
                contactsSyncUri(ContactsContract.Settings.CONTENT_URI, account),
                ContentValues().apply {
                    put(ContactsContract.Settings.ACCOUNT_NAME, account.name)
                    put(ContactsContract.Settings.ACCOUNT_TYPE, account.type)
                    put(ContactsContract.Settings.UNGROUPED_VISIBLE, 1)
                },
            )
        } catch (_: Exception) {}

        // Уже записанные: id в приложении → (rawId, хэш).
        val existing = HashMap<String, Pair<Long, String?>>()
        cr.query(
            rawUri,
            arrayOf(ContactsContract.RawContacts._ID, ContactsContract.RawContacts.SOURCE_ID, ContactsContract.RawContacts.SYNC1),
            "${ContactsContract.RawContacts.ACCOUNT_NAME} = ? AND ${ContactsContract.RawContacts.ACCOUNT_TYPE} = ? AND ${ContactsContract.RawContacts.DELETED} = 0",
            arrayOf(account.name, account.type),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val sid = c.getString(1) ?: continue
                existing[sid] = Pair(c.getLong(0), c.getString(2))
            }
        }

        val ops = ArrayList<ContentProviderOperation>()
        fun flush() {
            if (ops.isNotEmpty()) {
                cr.applyBatch(ContactsContract.AUTHORITY, ops)
                ops.clear()
            }
        }
        var written = 0
        val seen = HashSet<String>()
        for (m in items) {
            val id = m["id"] as? String ?: continue
            val hash = m["hash"] as? String ?: ""
            seen.add(id)
            val old = existing[id]
            if (old != null && old.second == hash) continue
            if (old != null) {
                // Изменился: данные заменяются целиком, запись остаётся той же.
                ops.add(
                    ContentProviderOperation.newDelete(dataUri)
                        .withSelection("${ContactsContract.Data.RAW_CONTACT_ID} = ?", arrayOf(old.first.toString()))
                        .build(),
                )
                ops.add(
                    ContentProviderOperation.newUpdate(rawUri)
                        .withSelection("${ContactsContract.RawContacts._ID} = ?", arrayOf(old.first.toString()))
                        .withValue(ContactsContract.RawContacts.SYNC1, hash)
                        .build(),
                )
                addContactData(ops, dataUri, m, rawId = old.first, backRef = -1)
            } else {
                val back = ops.size
                ops.add(
                    ContentProviderOperation.newInsert(rawUri)
                        .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, account.name)
                        .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, account.type)
                        .withValue(ContactsContract.RawContacts.SOURCE_ID, id)
                        .withValue(ContactsContract.RawContacts.SYNC1, hash)
                        .build(),
                )
                addContactData(ops, dataUri, m, rawId = -1, backRef = back)
            }
            written++
            if (ops.size > 300) flush()
        }
        flush()

        // Удалённые в приложении — удалить и из телефона.
        for ((sid, v) in existing) {
            if (sid in seen) continue
            ops.add(
                ContentProviderOperation.newDelete(rawUri)
                    .withSelection("${ContactsContract.RawContacts._ID} = ?", arrayOf(v.first.toString()))
                    .build(),
            )
            if (ops.size > 300) flush()
        }
        flush()
        return written
    }

    private fun addContactData(
        ops: ArrayList<ContentProviderOperation>, dataUri: Uri, m: Map<String, Any?>, rawId: Long, backRef: Int,
    ) {
        fun insert(mime: String): ContentProviderOperation.Builder {
            val b = ContentProviderOperation.newInsert(dataUri).withValue(ContactsContract.Data.MIMETYPE, mime)
            return if (backRef >= 0) b.withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, backRef)
            else b.withValue(ContactsContract.Data.RAW_CONTACT_ID, rawId)
        }
        fun s(k: String): String? = (m[k] as? String)?.trim()?.takeIf { it.isNotEmpty() }

        ops.add(
            insert(ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, s("displayName"))
                .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, s("givenName"))
                .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, s("familyName"))
                .withValue(ContactsContract.CommonDataKinds.StructuredName.MIDDLE_NAME, s("middleName"))
                .build(),
        )
        @Suppress("UNCHECKED_CAST")
        val emails = (m["emails"] as? List<String>) ?: emptyList()
        for (e in emails.filter { it.isNotBlank() }.distinct()) {
            ops.add(
                insert(ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, e)
                    .withValue(ContactsContract.CommonDataKinds.Email.TYPE, ContactsContract.CommonDataKinds.Email.TYPE_WORK)
                    .build(),
            )
        }
        s("phoneMobile")?.let {
            ops.add(
                insert(ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, it)
                    .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
                    .build(),
            )
        }
        s("phoneWork")?.let {
            ops.add(
                insert(ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, it)
                    .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_WORK)
                    .build(),
            )
        }
        if (s("company") != null || s("department") != null || s("jobTitle") != null) {
            ops.add(
                insert(ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Organization.COMPANY, s("company"))
                    .withValue(ContactsContract.CommonDataKinds.Organization.DEPARTMENT, s("department"))
                    .withValue(ContactsContract.CommonDataKinds.Organization.TITLE, s("jobTitle"))
                    .build(),
            )
        }
    }

    // ───────────────────────── Календарь ─────────────────────────

    private fun calendarSyncUri(base: Uri, a: Account): Uri = base.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, a.name)
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, a.type)
        .build()

    private fun ensureCalendar(ctx: Context, a: Account, displayName: String, color: Int): Long {
        val cr = ctx.contentResolver
        cr.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.ACCOUNT_NAME} = ? AND ${CalendarContract.Calendars.ACCOUNT_TYPE} = ?",
            arrayOf(a.name, a.type),
            null,
        )?.use { c -> if (c.moveToFirst()) return c.getLong(0) }
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, a.name)
            put(CalendarContract.Calendars.ACCOUNT_TYPE, a.type)
            put(CalendarContract.Calendars.NAME, a.name)
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, displayName)
            put(CalendarContract.Calendars.CALENDAR_COLOR, color)
            // Только чтение: правка в календаре телефона не ушла бы на сервер.
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_READ)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, a.name)
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }
        val uri = cr.insert(calendarSyncUri(CalendarContract.Calendars.CONTENT_URI, a), values)
            ?: throw IllegalStateException("calendar insert failed")
        return uri.lastPathSegment?.toLong() ?: throw IllegalStateException("calendar id")
    }

    /** Возвращает число записанных (новых и изменённых) встреч. */
    private fun syncEvents(ctx: Context, args: Map<String, Any?>): Int {
        val name = args["account"] as? String ?: return 0
        val display = args["calendarName"] as? String ?: name
        val color = (args["color"] as? Number)?.toInt() ?: 0xFF1D4F91.toInt()
        @Suppress("UNCHECKED_CAST")
        val items = (args["events"] as? List<Map<String, Any?>>) ?: emptyList()
        val account = ensureAccount(ctx, name)
        val calId = ensureCalendar(ctx, account, display, color)
        val cr = ctx.contentResolver
        val eventsUri = calendarSyncUri(CalendarContract.Events.CONTENT_URI, account)
        val remUri = calendarSyncUri(CalendarContract.Reminders.CONTENT_URI, account)

        // Цвет и имя календаря могли смениться в приложении.
        cr.update(
            calendarSyncUri(CalendarContract.Calendars.CONTENT_URI, account),
            ContentValues().apply {
                put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, display)
                put(CalendarContract.Calendars.CALENDAR_COLOR, color)
            },
            "${CalendarContract.Calendars._ID} = ?", arrayOf(calId.toString()),
        )

        val existing = HashMap<String, Pair<Long, String?>>()
        cr.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events._ID, CalendarContract.Events._SYNC_ID, CalendarContract.Events.SYNC_DATA1),
            "${CalendarContract.Events.CALENDAR_ID} = ? AND ${CalendarContract.Events.DELETED} = 0",
            arrayOf(calId.toString()),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val sid = c.getString(1) ?: continue
                existing[sid] = Pair(c.getLong(0), c.getString(2))
            }
        }

        var written = 0
        val seen = HashSet<String>()
        val ops = ArrayList<ContentProviderOperation>()
        fun flush() {
            if (ops.isNotEmpty()) {
                cr.applyBatch(CalendarContract.AUTHORITY, ops)
                ops.clear()
            }
        }
        for (m in items) {
            val id = m["id"] as? String ?: continue
            val hash = m["hash"] as? String ?: ""
            seen.add(id)
            val old = existing[id]
            if (old != null && old.second == hash) continue
            val allDay = m["allDay"] == true
            val values = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calId)
                put(CalendarContract.Events._SYNC_ID, id)
                put(CalendarContract.Events.SYNC_DATA1, hash)
                put(CalendarContract.Events.TITLE, m["title"] as? String ?: "")
                put(CalendarContract.Events.DESCRIPTION, m["description"] as? String)
                put(CalendarContract.Events.EVENT_LOCATION, m["location"] as? String)
                put(CalendarContract.Events.DTSTART, (m["start"] as Number).toLong())
                put(CalendarContract.Events.DTEND, (m["end"] as Number).toLong())
                // Весь день — полночь UTC и пояс UTC (требование календаря Android).
                put(CalendarContract.Events.EVENT_TIMEZONE, if (allDay) "UTC" else TimeZone.getDefault().id)
                put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
                put(CalendarContract.Events.HAS_ALARM, if (m["reminderMinutes"] is Number) 1 else 0)
            }
            val reminder = (m["reminderMinutes"] as? Number)?.toInt()
            if (old != null) {
                ops.add(
                    ContentProviderOperation.newUpdate(eventsUri)
                        .withSelection("${CalendarContract.Events._ID} = ?", arrayOf(old.first.toString()))
                        .withValues(values)
                        .build(),
                )
                ops.add(
                    ContentProviderOperation.newDelete(remUri)
                        .withSelection("${CalendarContract.Reminders.EVENT_ID} = ?", arrayOf(old.first.toString()))
                        .build(),
                )
                if (reminder != null) {
                    ops.add(
                        ContentProviderOperation.newInsert(remUri)
                            .withValue(CalendarContract.Reminders.EVENT_ID, old.first)
                            .withValue(CalendarContract.Reminders.MINUTES, reminder)
                            .withValue(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                            .build(),
                    )
                }
            } else {
                val back = ops.size
                ops.add(ContentProviderOperation.newInsert(eventsUri).withValues(values).build())
                if (reminder != null) {
                    ops.add(
                        ContentProviderOperation.newInsert(remUri)
                            .withValueBackReference(CalendarContract.Reminders.EVENT_ID, back)
                            .withValue(CalendarContract.Reminders.MINUTES, reminder)
                            .withValue(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                            .build(),
                    )
                }
            }
            written++
            if (ops.size > 300) flush()
        }
        flush()

        for ((sid, v) in existing) {
            if (sid in seen) continue
            ops.add(
                ContentProviderOperation.newDelete(eventsUri)
                    .withSelection("${CalendarContract.Events._ID} = ?", arrayOf(v.first.toString()))
                    .build(),
            )
            if (ops.size > 300) flush()
        }
        flush()
        return written
    }
}
