package com.ogneliss.mail

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Открыть файл внешним приложением (1.6.2).
 *
 * Плагин open_filex заводит свой канал только при подключении к окну и
 * снимает его при отключении. У приложения один движок на все окна
 * (MainActivity.ENGINE_ID): после пересоздания окна канал плагина мог
 * остаться снятым — «MissingPluginException … channel open_file» (замечание
 * 13.10.2026). Этот канал не зависит от окна: он ставится при создании
 * движка и запускает просмотр через FileProvider приложения.
 * Файл вне каталогов провайдера копируется в cache/open.
 *
 * «saveDownload» (1.6.33): сохранить файл в общую папку «Загрузки» одним
 * нажатием — через MediaStore (Android 10+), без разрешений. Раньше вложение
 * можно было только «Поделиться», а «Сохранить в Загрузки» в листе нет
 * (замечание 18.10.2026). На Android 7–9 — «unsupported», Dart предлагает
 * системный выбор папки.
 */
object FileOpenBridge {
    private const val CHANNEL = "ogneliss/open_file"

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveDownload") {
                val p = call.argument<String>("path")
                val name = call.argument<String>("name")?.takeIf { it.isNotBlank() } ?: p?.let { File(it).name }
                val m = call.argument<String>("mime")?.takeIf { it.isNotBlank() && it != "*/*" }
                    ?: "application/octet-stream"
                if (p.isNullOrEmpty() || name.isNullOrEmpty()) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                // Копирование большого файла — не в главном потоке.
                Thread {
                    val r = saveDownload(app, File(p), name, m)
                    android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(r) }
                }.start()
                return@setMethodCallHandler
            }
            // Картинка из письма — в буфер обмена (1.8.12): файл через
            // FileProvider; приложение, куда её вставят, получает доступ на
            // чтение от системы вместе с буфером.
            if (call.method == "copyImage") {
                val p = call.argument<String>("path")
                val m = call.argument<String>("mime")?.takeIf { it.startsWith("image/") } ?: "image/png"
                if (p.isNullOrEmpty() || !File(p).exists()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                result.success(copyImage(app, File(p), m))
                return@setMethodCallHandler
            }
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val mime = call.argument<String>("mime")?.takeIf { it.isNotBlank() } ?: "*/*"
            if (path.isNullOrEmpty()) {
                result.success("error")
                return@setMethodCallHandler
            }
            result.success(open(app, File(path), mime))
        }
    }

    private fun open(app: Context, src: File, mime: String): String {
        if (!src.exists()) return "missing"
        return try {
            val file = shareable(app, src)
            val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", file)
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            app.startActivity(view)
            "done"
        } catch (e: ActivityNotFoundException) {
            "no_app"
        } catch (e: Exception) {
            "error"
        }
    }

    private fun copyImage(app: Context, src: File, mime: String): Boolean = try {
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", shareable(app, src))
        val clip = android.content.ClipData(
            android.content.ClipDescription(src.name, arrayOf(mime)),
            android.content.ClipData.Item(uri),
        )
        val cm = app.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.setPrimaryClip(clip)
        true
    } catch (e: Exception) {
        false
    }

    /**
     * Файл → «Загрузки». Возвращает имя, под которым файл лёг (система
     * добавляет « (1)», если такое уже есть), «unsupported» до Android 10,
     * null — не удалось.
     */
    private fun saveDownload(app: Context, src: File, name: String, mime: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unsupported"
        if (!src.exists()) return null
        val resolver = app.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = try {
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } catch (e: Exception) {
            null
        } ?: return null
        return try {
            val out = resolver.openOutputStream(uri) ?: throw java.io.IOException("no stream")
            out.use { o -> src.inputStream().use { it.copyTo(o) } }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: name
        } catch (e: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            null
        }
    }

    /** Файл в каталоге провайдера (files, cache) — как есть, иначе копия в cache/open. */
    private fun shareable(app: Context, src: File): File {
        val path = src.canonicalPath
        val roots = listOfNotNull(app.filesDir, app.cacheDir, app.getExternalFilesDir(null), app.externalCacheDir)
            .map { it.canonicalPath }
        if (roots.any { path.startsWith(it + File.separator) }) return src
        val dir = File(app.cacheDir, "open").apply { mkdirs() }
        // Прежние копии — не старше суток.
        dir.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 86_400_000L) it.delete() }
        val dst = File(dir, src.name)
        src.copyTo(dst, overwrite = true)
        return dst
    }
}
