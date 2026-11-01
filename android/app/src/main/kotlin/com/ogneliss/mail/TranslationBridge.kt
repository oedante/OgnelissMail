package com.ogneliss.mail

import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.languageid.LanguageIdentifier
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026) —
 * Google ML Kit: перевод (com.google.mlkit:translate) и определение языка
 * (com.google.mlkit:language-id). Бесплатно; текст переводится на телефоне,
 * модели языков (~30 МБ) скачиваются один раз. Канал 'ogneliss/translate',
 * Dart — lib/services/translation/translator.dart.
 *
 * Задачи ML Kit ждём в своём потоке (Tasks.await нельзя в главном): письмо
 * из сотен кусков переводится, а интерфейс не замирает.
 */
object TranslationBridge {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var identifier: LanguageIdentifier? = null

    /** Переводчики пар языков — несколько последних (создание дорогое). */
    private val translators = LinkedHashMap<String, Translator>()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "ogneliss/translate").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    val r = handle(call.method, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    main.post { if (r === NotImplemented) result.notImplemented() else result.success(r) }
                } catch (e: Exception) {
                    main.post { result.error("translate", e.message ?: e.toString(), null) }
                }
            }
        }
    }

    private object NotImplemented

    private fun handle(method: String, a: Map<*, *>): Any? = when (method) {
        "available" -> true
        "languages" -> TranslateLanguage.getAllLanguages()
        "detect" -> detect(a["text"] as? String ?: "")
        "names" -> {
            val display = Locale.forLanguageTag(a["display"] as? String ?: "en")
            (a["codes"] as? List<*>).orEmpty().filterIsInstance<String>()
                .associateWith { Locale.forLanguageTag(it).getDisplayLanguage(display) }
        }
        "downloaded" -> Tasks.await(
            RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
        ).map { it.language }
        "missing" -> listOf(code(a["from"]), code(a["to"])).distinct().filter {
            !Tasks.await(RemoteModelManager.getInstance().isModelDownloaded(TranslateRemoteModel.Builder(it).build()))
        }
        "download" -> {
            val conditions = DownloadConditions.Builder().apply {
                if (a["wifiOnly"] == true) requireWifi()
            }.build()
            Tasks.await(translator(code(a["from"]), code(a["to"])).downloadModelIfNeeded(conditions))
            null
        }
        "delete" -> {
            val lang = code(a["lang"])
            // Переводчики с этим языком закрываются: модель уходит из памяти.
            translators.keys.filter { it.split('|').contains(lang) }.forEach { translators.remove(it)?.close() }
            Tasks.await(
                RemoteModelManager.getInstance().deleteDownloadedModel(TranslateRemoteModel.Builder(lang).build())
            )
            null
        }
        "translate" -> {
            val t = translator(code(a["from"]), code(a["to"]))
            (a["texts"] as? List<*>).orEmpty().map { s ->
                val text = s as? String ?: ""
                if (text.isBlank()) text else Tasks.await(t.translate(text))
            }
        }
        else -> NotImplemented
    }

    /** Код языка ML Kit; незнакомый — ошибка (Dart покажет «Не удалось перевести»). */
    private fun code(v: Any?): String {
        val s = v as? String ?: throw IllegalArgumentException("no language")
        return TranslateLanguage.fromLanguageTag(s) ?: throw IllegalArgumentException("unsupported language $s")
    }

    /**
     * Язык текста: код BCP-47 или null («und» — не определён; «ru-Latn» —
     * русский латиницей, такой текст переводчику не назвать).
     */
    private fun detect(text: String): String? {
        if (text.isBlank()) return null
        val id = identifier ?: LanguageIdentification.getClient().also { identifier = it }
        val tag = Tasks.await(id.identifyLanguage(text))
        if (tag == "und" || tag.contains("-Latn")) return null
        return tag
    }

    private fun translator(from: String, to: String): Translator {
        val key = "$from|$to"
        translators.remove(key)?.let { translators[key] = it; return it }
        val t = Translation.getClient(
            TranslatorOptions.Builder().setSourceLanguage(from).setTargetLanguage(to).build()
        )
        translators[key] = t
        while (translators.size > 3) {
            val oldest = translators.keys.first()
            translators.remove(oldest)?.close()
        }
        return t
    }
}
