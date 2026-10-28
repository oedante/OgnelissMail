package com.ogneliss.mail

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/**
 * Очистка входящего «Поделиться» до того, как его увидит плагин
 * receive_sharing_intent.
 *
 * Плагин копирует файл из content:// в cacheDir под именем, которое сообщил
 * отправитель (_display_name), без проверки. Вредоносное приложение могло
 * передать имя «../shared_prefs/…» или «../databases/…» и перезаписать
 * настройки или базу почты (атака «dirty stream»). А file:// плагин
 * передаёт как есть — так в письмо можно было подсунуть собственную базу
 * приложения как вложение.
 *
 * Здесь каждый поток копируется самостоятельно: имя очищается от путей и
 * служебных символов, файл кладётся в отдельный каталог со случайным именем,
 * file:// из личных каталогов приложения отклоняется. Плагину передаётся уже
 * безопасный file:// на копию.
 */
object ShareIntentSanitizer {
    private const val DIR = "shared_in"
    private const val MAX_AGE_MS = 24L * 60 * 60 * 1000

    fun sanitize(ctx: Context, intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val root = File(ctx.cacheDir, DIR)
        try {
            root.mkdirs()
            cleanupOld(root)
            if (action == Intent.ACTION_SEND) {
                val uri = streamOf(intent) ?: return
                val safe = copySafe(ctx, uri, root)
                if (safe != null) {
                    intent.putExtra(Intent.EXTRA_STREAM, safe)
                } else {
                    intent.removeExtra(Intent.EXTRA_STREAM)
                }
            } else {
                val list = streamsOf(intent) ?: return
                val out = ArrayList<Uri>()
                for (u in list) {
                    copySafe(ctx, u, root)?.let { out.add(it) }
                }
                intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, out)
            }
        } catch (e: Exception) {
            // Любая ошибка — вложения не принимаем, текст остаётся.
            intent.removeExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun streamsOf(intent: Intent): ArrayList<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }

    private fun isPrivate(ctx: Context, f: File): Boolean {
        val roots = listOfNotNull(
            ctx.applicationInfo.dataDir,
            "/data/data/${ctx.packageName}",
            "/data/user/0/${ctx.packageName}",
            ctx.filesDir?.parent,
        ).map { File(it).canonicalPath }
        val p = f.canonicalPath
        return roots.any { p == it || p.startsWith(it + File.separator) }
    }

    private fun copySafe(ctx: Context, uri: Uri, root: File): Uri? {
        when (uri.scheme?.lowercase()) {
            "content" -> {
                // Свой же FileProvider — не принимаем: через него можно
                // вытащить личные файлы приложения. Исключение (1.6.33) —
                // файл, который само приложение только что отдало в
                // «Поделиться» (вложение → Ogneliss Mail: раньше «ничего не
                // происходило»): берётся только из каталога share_plus в кэше,
                // куда плагин «Поделиться» кладёт отдаваемые копии.
                if (uri.authority?.startsWith(ctx.packageName) == true) {
                    return ownShared(ctx, uri, root)
                }
            }
            "file" -> {
                val path = uri.path ?: return null
                if (isPrivate(ctx, File(path))) return null
            }
            else -> return null
        }
        val name = safeName(displayName(ctx, uri))
        val dir = File(root, UUID.randomUUID().toString())
        if (!dir.mkdirs()) return null
        val target = File(dir, name)
        // Последняя проверка: файл действительно внутри выделенного каталога.
        if (!target.canonicalPath.startsWith(dir.canonicalPath + File.separator)) return null
        val input = ctx.contentResolver.openInputStream(uri) ?: return null
        input.use { inp -> FileOutputStream(target).use { out -> inp.copyTo(out) } }
        return Uri.fromFile(target)
    }

    /** Копия файла, отданного этим же приложением через share_plus. */
    private fun ownShared(ctx: Context, uri: Uri, root: File): Uri? {
        if (uri.authority != "${ctx.packageName}.flutter.share_provider") return null
        val outDir = File(ctx.cacheDir, "share_plus")
        val name = uri.lastPathSegment ?: return null
        val src = File(outDir, name)
        // Только прямо внутри share_plus: «../» в имени не проходит.
        if (src.parentFile?.canonicalPath != outDir.canonicalPath || !src.isFile) return null
        val dir = File(root, UUID.randomUUID().toString())
        if (!dir.mkdirs()) return null
        val target = File(dir, safeName(src.name))
        if (!target.canonicalPath.startsWith(dir.canonicalPath + File.separator)) return null
        src.copyTo(target, overwrite = true)
        return Uri.fromFile(target)
    }

    private fun displayName(ctx: Context, uri: Uri): String? {
        if (uri.scheme.equals("file", ignoreCase = true)) return uri.lastPathSegment
        return try {
            ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            null
        }
    }

    /** Только имя файла: без каталогов, управляющих и запрещённых символов. */
    fun safeName(raw: String?): String {
        var n = (raw ?: "").substringAfterLast('/').substringAfterLast('\\')
        n = n.replace(Regex("[\\u0000-\\u001f\\u007f:*?\"<>|]"), "_").trim().trim('.')
        if (n.length > 120) {
            val dot = n.lastIndexOf('.')
            val ext = if (dot > 0 && n.length - dot <= 10) n.substring(dot) else ""
            n = n.take(120 - ext.length) + ext
        }
        return if (n.isEmpty()) "attachment" else n
    }

    private fun cleanupOld(root: File) {
        val now = System.currentTimeMillis()
        root.listFiles()?.forEach { d ->
            if (now - d.lastModified() > MAX_AGE_MS) d.deleteRecursively()
        }
    }
}
