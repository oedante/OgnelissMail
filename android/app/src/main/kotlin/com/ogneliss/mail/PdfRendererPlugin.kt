package com.ogneliss.mail

// PDF внутри приложения (1.8.14, просьба пользователей через владельца
// 29.10.2026): страницы рисует системный android.graphics.pdf.PdfRenderer —
// без сторонних библиотек и их лицензий. Канал 'ogneliss/pdf' ждёт
// lib/features/mail/widgets/pdf_view.dart:
//   open(path)                → {id, sizes: [[w, h], …]} (точки PDF);
//                               защищённый паролем — ошибка «protected»;
//   render(id, index, width)  → {w, h, pixels} — RGBA, белый фон;
//   close(id).
// PdfRenderer не потокобезопасен: всё — в одном фоновом потоке, по очереди;
// главный поток Android не занят ни открытием, ни рисованием страниц.

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.roundToInt

object PdfRendererPlugin {
    private const val CHANNEL = "ogneliss/pdf"

    /** Наибольшая страница в пикселях (≈48 МБ): больше — не хватит памяти. */
    private const val MAX_PIXELS = 12_000_000L

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val docs = HashMap<Int, Pair<ParcelFileDescriptor, PdfRenderer>>()
    private var next = 1

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("args", "path", null)
                        return@setMethodCallHandler
                    }
                    worker.execute { open(path, result) }
                }
                "render" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val index = call.argument<Int>("index") ?: 0
                    val width = call.argument<Int>("width") ?: 0
                    worker.execute { render(id, index, width, result) }
                }
                "close" -> {
                    val id = call.argument<Int>("id") ?: 0
                    worker.execute { close(id) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun open(path: String, result: MethodChannel.Result) {
        val fd: ParcelFileDescriptor
        try {
            fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        } catch (e: Throwable) {
            main.post { result.error("open", e.message, null) }
            return
        }
        try {
            val r = PdfRenderer(fd)
            val sizes = ArrayList<List<Int>>(r.pageCount)
            for (i in 0 until r.pageCount) {
                val p = r.openPage(i)
                try {
                    sizes.add(listOf(p.width, p.height))
                } finally {
                    p.close()
                }
            }
            val id = next++
            docs[id] = Pair(fd, r)
            main.post { result.success(mapOf("id" to id, "sizes" to sizes)) }
        } catch (e: SecurityException) {
            // PDF с паролем: системный PdfRenderer такие не открывает.
            runCatching { fd.close() }
            main.post { result.error("protected", e.message, null) }
        } catch (e: Throwable) {
            runCatching { fd.close() }
            main.post { result.error("open", e.message, null) }
        }
    }

    private fun render(id: Int, index: Int, width: Int, result: MethodChannel.Result) {
        val doc = docs[id]
        if (doc == null || index < 0 || index >= doc.second.pageCount || width <= 0) {
            main.post { result.error("args", "page", null) }
            return
        }
        try {
            val p = doc.second.openPage(index)
            try {
                var w = width
                var h = (w.toDouble() * p.height / p.width.coerceAtLeast(1)).roundToInt().coerceAtLeast(1)
                if (w.toLong() * h > MAX_PIXELS) {
                    val k = Math.sqrt(MAX_PIXELS.toDouble() / (w.toLong() * h))
                    w = (w * k).toInt().coerceAtLeast(1)
                    h = (h * k).toInt().coerceAtLeast(1)
                }
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                try {
                    // Страница PDF бывает прозрачной — фон бумаги белый.
                    bmp.eraseColor(Color.WHITE)
                    p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val buf = ByteBuffer.allocate(bmp.byteCount)
                    bmp.copyPixelsToBuffer(buf)
                    val bytes = buf.array()
                    main.post { result.success(mapOf("w" to w, "h" to h, "pixels" to bytes)) }
                } finally {
                    bmp.recycle()
                }
            } finally {
                p.close()
            }
        } catch (e: Throwable) {
            main.post { result.error("render", e.message, null) }
        }
    }

    private fun close(id: Int) {
        val doc = docs.remove(id) ?: return
        runCatching { doc.second.close() }
        runCatching { doc.first.close() }
    }
}
