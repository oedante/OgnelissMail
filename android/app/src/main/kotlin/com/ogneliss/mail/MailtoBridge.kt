package com.ogneliss.mail

import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * «Написать письмо» из других приложений: mailto-ссылка (ACTION_VIEW),
 * ACTION_SENDTO (контакты, браузер), адресаты и тема у ACTION_SEND.
 *
 * Раньше mailto приходил в плагин «Поделиться» как текст и попадал в тело
 * письма, а ACTION_SENDTO приложение не принимало вовсе (замечание
 * 11.10.2026). Теперь намерение разбирается здесь в одну ссылку
 * mailto:кому?cc=…&bcc=…&subject=…&body=… и передаётся в Dart по каналу
 * ogneliss/mailto («take» — забрать, «open» — пришло новое). Для плагина
 * «Поделиться» VIEW/SENDTO гасятся, чтобы письмо не открывалось дважды.
 */
object MailtoBridge {
    @Volatile
    private var pending: String? = null

    /** Адресаты и тема у «Поделиться» (ACTION_SEND с EXTRA_EMAIL). */
    @Volatile
    private var pendingShare: String? = null

    private var channel: MethodChannel? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "ogneliss/mailto").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        val t = pending
                        pending = null
                        result.success(t)
                    }
                    "takeShare" -> {
                        val t = pendingShare
                        pendingShare = null
                        result.success(t)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun list(intent: Intent, key: String): List<String> =
        (intent.getStringArrayExtra(key)?.toList() ?: emptyList()) +
            listOfNotNull(runCatching { intent.getStringExtra(key) }.getOrNull())

    /** Ссылка mailto из данных намерения и его дополнений. */
    private fun build(intent: Intent, withBody: Boolean): String? {
        val data: Uri? = intent.data
        val base = if (data?.scheme.equals("mailto", ignoreCase = true)) data.toString() else "mailto:"
        val extraTo = list(intent, Intent.EXTRA_EMAIL)
        val cc = list(intent, Intent.EXTRA_CC)
        val bcc = list(intent, Intent.EXTRA_BCC)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val body = if (withBody) intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() else null
        if (base == "mailto:" && extraTo.isEmpty() && cc.isEmpty() && bcc.isEmpty() && subject == null && body == null) {
            return null
        }
        val sb = StringBuilder(base)
        if (extraTo.isNotEmpty()) {
            val head = base.substringBefore('?')
            val tail = if (base.contains('?')) "?" + base.substringAfter('?') else ""
            val sep = if (head.length > "mailto:".length) "," else ""
            sb.setLength(0)
            sb.append(head).append(sep).append(extraTo.joinToString(",") { Uri.encode(it, "@") }).append(tail)
        }
        fun add(k: String, v: String) {
            sb.append(if (sb.contains('?')) '&' else '?').append(k).append('=').append(Uri.encode(v))
        }
        if (cc.isNotEmpty()) add("cc", cc.joinToString(","))
        if (bcc.isNotEmpty()) add("bcc", bcc.joinToString(","))
        if (subject != null) add("subject", subject)
        if (body != null) add("body", body)
        return sb.toString()
    }

    /** Вызывается до super.onCreate / onNewIntent. */
    fun handle(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        val isMailto = intent.data?.scheme.equals("mailto", ignoreCase = true)
        when {
            action == Intent.ACTION_SENDTO || (action == Intent.ACTION_VIEW && isMailto) -> {
                val link = build(intent, withBody = true) ?: return
                pending = link
                // Плагин «Поделиться» больше это намерение не видит.
                intent.action = Intent.ACTION_MAIN
                intent.data = null
                runCatching { channel?.invokeMethod("open", null) }
            }
            action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE -> {
                // Текст и файлы забирает плагин «Поделиться»; адресатов и тему
                // он теряет — сохраняем их отдельно.
                pendingShare = build(intent, withBody = false)
            }
        }
    }
}
