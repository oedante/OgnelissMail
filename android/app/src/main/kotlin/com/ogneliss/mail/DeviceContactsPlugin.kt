package com.ogneliss.mail

// Нативная реализация MethodChannel('ogneliss/device_contacts'), которую ожидает
// lib/services/device/device_contacts_sync.dart. БЕЗ этого файла канал бросал
// MissingPluginException, и импорт/экспорт молча возвращали 0 (фикция, класс Г).
//
// Интеграция (одна строка) в MainActivity.configureFlutterEngine:
//     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//         super.configureFlutterEngine(flutterEngine)
//         DeviceContactsPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
//     }
// Разрешения READ_CONTACTS/WRITE_CONTACTS уже объявлены в AndroidManifest.xml;
// запрос у пользователя выполняется на стороне Dart (permission_handler).

import android.content.ContentProviderOperation
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

object DeviceContactsPlugin {
    private const val CHANNEL = "ogneliss/device_contacts"

    // Чтение адресной книги — по 3 запроса на контакт; на главном потоке
    // при нескольких сотнях контактов это заметное зависание интерфейса
    // (ANR на слабых устройствах). Работа идёт в фоне, ответ — на главном
    // потоке, как требует MethodChannel.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> result.success(true)
                "getContacts" -> worker.execute {
                    try {
                        val list = readContacts(app)
                        main.post { result.success(list) }
                    } catch (e: Exception) {
                        main.post { result.error("READ_FAILED", e.message, null) }
                    }
                }
                "addContact" -> {
                    @Suppress("UNCHECKED_CAST")
                    val m = call.arguments as? Map<String, Any?>
                    if (m == null) {
                        result.error("BAD_ARGS", "map expected", null)
                    } else {
                        worker.execute {
                            try {
                                addContact(app, m)
                                main.post { result.success(true) }
                            } catch (e: Exception) {
                                main.post { result.error("WRITE_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Читает контакты с e-mail. Возвращает список Map с ключами, которые ждёт Dart:
    /// email, displayName, givenName, familyName, middleName, phoneWork, phoneMobile,
    /// company, department, jobTitle.
    private fun readContacts(context: Context): List<Map<String, Any?>> {
        val cr = context.contentResolver
        val out = ArrayList<Map<String, Any?>>()

        // Базовый проход по e-mail: одна строка на адрес.
        val emailCursor = cr.query(
            ContactsContract.CommonDataKinds.Email.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Email.CONTACT_ID,
                ContactsContract.CommonDataKinds.Email.ADDRESS,
                ContactsContract.CommonDataKinds.Email.DISPLAY_NAME_PRIMARY,
            ),
            null, null, null,
        ) ?: return out

        emailCursor.use { c ->
            val idIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Email.CONTACT_ID)
            val addrIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Email.ADDRESS)
            val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Email.DISPLAY_NAME_PRIMARY)
            val seen = HashSet<String>()
            while (c.moveToNext()) {
                val email = c.getString(addrIdx) ?: continue
                if (email.isBlank() || !seen.add(email.lowercase())) continue
                val contactId = c.getString(idIdx)
                val displayName = c.getString(nameIdx) ?: email

                val extra = if (contactId != null) readDetails(context, contactId) else emptyMap()
                out.add(
                    hashMapOf<String, Any?>(
                        "email" to email,
                        "displayName" to displayName,
                    ).apply { putAll(extra) },
                )
            }
        }
        return out
    }

    /// Имя по частям, телефоны и организация для конкретного контакта.
    private fun readDetails(context: Context, contactId: String): Map<String, Any?> {
        val cr = context.contentResolver
        val res = HashMap<String, Any?>()

        // Структурированное имя.
        cr.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME,
                ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME,
                ContactsContract.CommonDataKinds.StructuredName.MIDDLE_NAME,
            ),
            "${ContactsContract.Data.CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(contactId, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE),
            null,
        )?.use { c ->
            if (c.moveToFirst()) {
                res["givenName"] = c.getString(0)
                res["familyName"] = c.getString(1)
                res["middleName"] = c.getString(2)
            }
        }

        // Телефоны: рабочий и мобильный.
        cr.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.TYPE,
            ),
            "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
            arrayOf(contactId),
            null,
        )?.use { c ->
            val numIdx = 0; val typeIdx = 1
            while (c.moveToNext()) {
                val number = c.getString(numIdx) ?: continue
                when (c.getInt(typeIdx)) {
                    ContactsContract.CommonDataKinds.Phone.TYPE_WORK ->
                        res.putIfAbsent("phoneWork", number)
                    ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE ->
                        res.putIfAbsent("phoneMobile", number)
                    else -> res.putIfAbsent("phoneMobile", number)
                }
            }
        }

        // Организация: компания, отдел, должность.
        cr.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Organization.COMPANY,
                ContactsContract.CommonDataKinds.Organization.DEPARTMENT,
                ContactsContract.CommonDataKinds.Organization.TITLE,
            ),
            "${ContactsContract.Data.CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(contactId, ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE),
            null,
        )?.use { c ->
            if (c.moveToFirst()) {
                res["company"] = c.getString(0)
                res["department"] = c.getString(1)
                res["jobTitle"] = c.getString(2)
            }
        }

        return res
    }

    /// Создаёт контакт в адресной книге через пакет операций.
    private fun addContact(context: Context, m: Map<String, Any?>) {
        val ops = ArrayList<ContentProviderOperation>()

        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
                .build(),
        )

        val given = m["givenName"] as? String
        val family = m["familyName"] as? String
        val display = m["displayName"] as? String
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, display)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, given)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, family)
                .build(),
        )

        (m["email"] as? String)?.takeIf { it.isNotBlank() }?.let { email ->
            ops.add(
                ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, email)
                    .withValue(ContactsContract.CommonDataKinds.Email.TYPE, ContactsContract.CommonDataKinds.Email.TYPE_WORK)
                    .build(),
            )
        }

        (m["phoneWork"] as? String)?.takeIf { it.isNotBlank() }?.let { phone ->
            ops.add(phoneOp(phone, ContactsContract.CommonDataKinds.Phone.TYPE_WORK))
        }
        (m["phoneMobile"] as? String)?.takeIf { it.isNotBlank() }?.let { phone ->
            ops.add(phoneOp(phone, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE))
        }

        val company = m["company"] as? String
        val department = m["department"] as? String
        val title = m["jobTitle"] as? String
        if (!company.isNullOrBlank() || !department.isNullOrBlank() || !title.isNullOrBlank()) {
            ops.add(
                ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Organization.COMPANY, company)
                    .withValue(ContactsContract.CommonDataKinds.Organization.DEPARTMENT, department)
                    .withValue(ContactsContract.CommonDataKinds.Organization.TITLE, title)
                    .build(),
            )
        }

        context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
    }

    private fun phoneOp(number: String, type: Int): ContentProviderOperation =
        ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
            .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, number)
            .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, type)
            .build()
}
