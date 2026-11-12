package com.ogneliss.mail

// Движок рисования Flutter: Impeller (по умолчанию) или Skia (совместимость).
//
// Зачем (диагностика владельца 08.11.2026, HUAWEI DEL-LX9, Android 12, EMUI):
// после листания и просмотра вложений, при ответе или пересылке — чёрный
// экран, «ничего не помогает, только перезагрузка или долгое ожидание».
// В журнале — падение в машинном коде:
//   [FATAL:flutter/impeller/renderer/backend/gles/blit_pass_gles.cc(88)]
//   Check failed: result. Must be able to encode GL commands without error.
// Impeller на OpenGL ES (на телефонах, где он не выбрал Vulkan) не смог
// передать в видеопамять картинку (загрузка текстуры, уменьшение, mip-уровни)
// и намеренно остановил приложение. Skia в том же случае просто не рисует
// одну картинку. Экран остаётся чёрным, а не закрывается, потому что движок
// Flutter живёт дольше окна и процесс держит служба почты (MainActivity) —
// повторное открытие подключается к тому же сломанному движку.
//
// Что делаем:
//  · при запуске процесса смотрим, как завершались прошлые (Android 11+);
//    нашли падение в Impeller — на этом телефоне дальше рисуем через Skia
//    («Автоматически»);
//  · в «Настройки → Расширенные → Графика» можно выбрать вручную: Skia
//    (совместимость) или Impeller; применяется с перезапуском приложения
//    (RestartActivity);
//  · в диагностике — какой движок работает и сколько памяти у телефона.
//
// Переключение — штатный флаг движка `--enable-impeller=false`
// (FlutterEngineFlags.ENABLE_IMPELLER, разрешён в выпускной сборке). Флаг
// читается один раз, при первой инициализации FlutterLoader в процессе,
// поэтому выставляется из OgnelissApplication.onCreate — раньше главного и
// фоновых движков (WorkManager, сигнал сервера, виджеты).
//
// HCPP (12.11.2026, план 2026-11 п. 3: «проверить новый режим встраивания
// вместо Hybrid Composition»): Hybrid Composition++ — встроенные окна
// Android (окно письма, редактор) рисуются через SurfaceControl. Тот же
// способ включения: флаг движка `--enable-hcpp-and-surface-control`
// (FlutterEngineFlags.ENABLE_HCPP, разрешён в выпускной сборке). С ним движок
// сам создаёт все встроенные окна по-новому (PlatformViewsChannel.create) —
// плагин окна письма менять не нужно. Нужны Android 14+ и Impeller на
// Vulkan; иначе движок работает, как раньше. По умолчанию выключено:
// выключатель там же, в «Графике», применяется с перезапуском.

import android.app.ActivityManager
import android.app.Application
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

object GraphicsMode {
    private const val TAG = "OgnelissGraphics"
    private const val PREFS = "ogneliss_graphics"
    private const val KEY_MODE = "mode" // auto | skia | impeller
    private const val KEY_AUTO = "auto_skia"
    private const val KEY_AUTO_AT = "auto_at"
    private const val KEY_AUTO_WHY = "auto_reason"
    private const val KEY_SCANNED = "scanned_to"
    private const val KEY_GLES_FP = "gles_fingerprint"
    private const val KEY_GLES_WHY = "gles_reason"
    private const val KEY_HCPP = "hcpp"
    private const val ARG_HCPP = "--enable-hcpp-and-surface-control"

    /** Чипы, на которых Flutter не включает Vulkan (kBadSocs, Flutter 3.47). */
    private val BAD_SOCS = setOf(
        "exynos7870", "exynos7880", "exynos7872", "exynos7884", "exynos7885", "exynos7904",
        "exynos8890", "exynos8895", "exynos9609", "exynos9610", "exynos9611", "exynos9810",
        "exynos9820", "exynos9825", "rk30sdk",
    )

    /** Движок этого процесса: skia — выключили Impeller флагом. */
    @Volatile
    var active: String = "impeller"
        private set

    /** «Impeller (OpenGLES)» / «(Vulkan)» — из сообщения движка, если удалось прочитать. */
    @Volatile
    private var backend: String? = null

    @Volatile
    private var gpuCache: String? = null

    /** Этот процесс запущен с флагом HCPP. */
    @Volatile
    var hcppActive: Boolean = false
        private set

    /** HCPP есть смысл включать: Android 14+ и Impeller на Vulkan. */
    fun hcppSupported(c: Context): Boolean =
        Build.VERSION.SDK_INT >= 34 && glesReason(c) == null

    /** Включить ли HCPP при следующем запуске процесса (со Skia он не работает). */
    fun wantHcpp(c: Context): Boolean =
        prefs(c).getBoolean(KEY_HCPP, false) && hcppSupported(c) && !wantSkia(c)

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun mode(c: Context): String = prefs(c).getString(KEY_MODE, "auto") ?: "auto"

    /**
     * Рисовать ли через Skia при следующем запуске процесса. «Автоматически»
     * — Skia после падения Impeller и там, где Impeller рисовал бы через
     * OpenGL ES (glesReason): уточнение владельца 08.11.2026 — чёрный экран
     * при ответе или пересылке после просмотра файла, без падения процесса,
     * то есть по одним падениям такой телефон не распознать.
     */
    fun wantSkia(c: Context): Boolean {
        val p = prefs(c)
        return when (mode(c)) {
            "skia" -> true
            "impeller" -> false
            else -> p.getBoolean(KEY_AUTO, false) || glesReason(c) != null
        }
    }

    /**
     * Почему Impeller на этом телефоне рисовал бы через OpenGL ES, а не
     * Vulkan; null — Vulkan. Те же правила, что у Flutter 3.47
     * (engine/…/android/android_context_dynamic_impeller.cc): Huawei («AHB
     * imports do not consistently work»), MediaTek с прошивкой до API 32,
     * эмулятор, чипы из списка Flutter, нет Vulkan 1.1. Ниже Android 10
     * Flutter и так рисует через Skia. Считается один раз на версию прошивки
     * (getprop — отдельные процессы, не на каждый запуск).
     */
    fun glesReason(c: Context): String? {
        val p = prefs(c)
        val fp = Build.FINGERPRINT ?: ""
        if (p.getString(KEY_GLES_FP, null) == fp) {
            return p.getString(KEY_GLES_WHY, "").orEmpty().ifEmpty { null }
        }
        val why = try {
            detectGles(c).orEmpty()
        } catch (e: Throwable) {
            ""
        }
        p.edit().putString(KEY_GLES_FP, fp).putString(KEY_GLES_WHY, why).apply()
        return why.ifEmpty { null }
    }

    private fun detectGles(c: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val prop = BackgroundDiagnostics::prop
        val hw = prop("ro.hardware")
        if (hw == "goldfish" || hw == "ranchu" || hw == "qemu" || Build.MODEL.contains("gphone")) {
            return "эмулятор"
        }
        if (prop("ro.com.google.clientidbase") == "android-huawei") return "Huawei"
        val vendorSdk = prop("ro.vendor.build.version.sdk").toIntOrNull() ?: Build.VERSION.SDK_INT
        if (vendorSdk < 32 && prop("ro.vendor.mediatek.platform").isNotEmpty()) {
            return "MediaTek, прошивка API $vendorSdk"
        }
        val board = prop("ro.product.board")
        if (board in BAD_SOCS) return "чип $board"
        if (!c.packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x401000)) {
            return "нет Vulkan 1.1"
        }
        return null
    }

    /**
     * Из Application.onCreate, до создания любого движка Flutter. Ошибка здесь
     * не должна мешать запуску: тогда просто остаётся Impeller.
     */
    fun applyAtStart(app: Application) {
        try {
            scanCrashes(app)
            val skia = wantSkia(app)
            val hcpp = !skia && wantHcpp(app)
            if (!skia && !hcpp) return
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, arrayOf(if (skia) "--enable-impeller=false" else ARG_HCPP))
            if (skia) active = "skia" else hcppActive = true
        } catch (e: Throwable) {
            Log.w(TAG, "graphics mode: ${e.message}")
        }
    }

    /**
     * Падения процесса в Impeller с прошлой проверки (Android 11+). Нашли —
     * «Автоматически» переходит на Skia. Только главный процесс приложения:
     * WebView-процессы и процесс перезапуска здесь ни при чём.
     */
    private fun scanCrashes(c: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val p = prefs(c)
        val since = p.getLong(KEY_SCANNED, 0L)
        val am = c.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        // 0 — все записи, что хранит система (обычно последние 16 на пакет,
        // вместе с процессами WebView — поэтому проверяем при каждом запуске).
        val list = am.getHistoricalProcessExitReasons(c.packageName, 0, 0)
        var newest = since
        val edit = p.edit()
        for (info in list) {
            if (info.timestamp <= since) continue
            if (info.timestamp > newest) newest = info.timestamp
            if (info.reason != ApplicationExitInfo.REASON_CRASH_NATIVE) continue
            if (info.processName != c.packageName) continue
            val trace = BackgroundDiagnostics.crashTrace(info) ?: continue
            if (!isImpellerCrash(trace)) continue
            if (info.timestamp >= p.getLong(KEY_AUTO_AT, 0L)) {
                edit.putBoolean(KEY_AUTO, true)
                    .putLong(KEY_AUTO_AT, info.timestamp)
                    .putString(KEY_AUTO_WHY, firstFatal(trace))
            }
        }
        if (newest > since) edit.putLong(KEY_SCANNED, newest)
        edit.apply()
    }

    /** Сообщение движка о падении — путь к исходнику Impeller в строке FATAL. */
    fun isImpellerCrash(trace: String): Boolean = trace.contains("impeller", ignoreCase = true)

    private fun firstFatal(trace: String): String =
        trace.split(" | ").firstOrNull { it.contains("impeller", ignoreCase = true) }?.take(240)
            ?: trace.take(240)

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, "ogneliss/graphics").setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> Thread {
                    val s = state(app)
                    Handler(Looper.getMainLooper()).post { result.success(s) }
                }.start()
                "setMode" -> {
                    val m = call.arguments as? String
                    if (m != "auto" && m != "skia" && m != "impeller") {
                        result.error("bad_mode", m, null)
                    } else {
                        // commit: сразу за выбором может последовать перезапуск.
                        prefs(app).edit().putString(KEY_MODE, m).commit()
                        result.success(state(app, readLog = false))
                    }
                }
                "setHcpp" -> {
                    prefs(app).edit().putBoolean(KEY_HCPP, call.arguments == true).commit()
                    result.success(state(app, readLog = false))
                }
                "restart" -> {
                    result.success(null)
                    Handler(Looper.getMainLooper()).postDelayed({ RestartActivity.restart(app) }, 150)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun state(c: Context, readLog: Boolean = true): Map<String, Any?> {
        val p = prefs(c)
        if (readLog && active == "impeller" && backend == null) backend = readBackend()
        if (readLog && gpuCache == null) gpuCache = gpu(c)
        return mapOf(
            "mode" to mode(c),
            "active" to active,
            "backend" to backend,
            "next" to if (wantSkia(c)) "skia" else "impeller",
            "autoSkia" to p.getBoolean(KEY_AUTO, false),
            "autoAt" to p.getLong(KEY_AUTO_AT, 0L),
            "autoReason" to p.getString(KEY_AUTO_WHY, null),
            "glesReason" to glesReason(c),
            "hcpp" to p.getBoolean(KEY_HCPP, false),
            "hcppActive" to hcppActive,
            "hcppNext" to wantHcpp(c),
            "hcppSupported" to hcppSupported(c),
            "memory" to memory(c),
            "gpu" to gpuCache,
        )
    }

    /**
     * Чип, графический драйвер и Vulkan (08.11.2026): Impeller рисует через
     * Vulkan 1.1, а без него (или с драйвером из чёрного списка Flutter) —
     * через OpenGL ES, где и случился сбой. Строка — для журнала.
     */
    private fun gpu(c: Context): String = try {
        val parts = mutableListOf<String>()
        BackgroundDiagnostics.prop("ro.board.platform").takeIf { it.isNotEmpty() }?.let { parts.add("чип $it") }
        BackgroundDiagnostics.prop("ro.hardware.egl").takeIf { it.isNotEmpty() }?.let { parts.add("EGL $it") }
        BackgroundDiagnostics.prop("ro.hardware.vulkan").takeIf { it.isNotEmpty() }?.let { parts.add("драйвер Vulkan $it") }
        val pm = c.packageManager
        val vk = when {
            pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x401000) -> "1.1+"
            pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x400000) -> "1.0"
            else -> "нет"
        }
        parts.add("Vulkan $vk")
        parts.joinToString(", ")
    } catch (e: Throwable) {
        ""
    }

    /**
     * Какой путь выбрал Impeller (Vulkan или OpenGLES) — движок пишет это в
     * системный журнал при создании. Приложение видит в logcat только свои
     * строки; на прошивках с выключенным журналом (часть Huawei) — пусто.
     */
    private fun readBackend(): String? = try {
        val proc = ProcessBuilder("logcat", "-d", "-v", "raw", "-t", "4000", "-s", "flutter:I")
            .redirectErrorStream(true)
            .start()
        val found = BufferedReader(InputStreamReader(proc.inputStream)).use { r ->
            r.lineSequence()
                .filter { it.contains("Impeller rendering backend") }
                .lastOrNull()
        }
        // logcat -d сам завершается после вывода; destroy — на всякий случай
        // (waitFor с таймаутом есть только с Android 8, minSdk — 7).
        proc.destroy()
        // «Using the Impeller rendering backend (OpenGLES).» → «OpenGLES».
        found?.substringAfter("backend")?.trim('.', ' ', '(', ')')?.takeIf { it.isNotEmpty() }
    } catch (e: Throwable) {
        null
    }

    /** Память телефона и приложения — чтобы видеть, не в её нехватке ли дело. */
    fun memory(c: Context): Map<String, Any?> = try {
        val am = c.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val mb = 1024L * 1024L
        mapOf(
            "totalMb" to mi.totalMem / mb,
            "availMb" to mi.availMem / mb,
            "thresholdMb" to mi.threshold / mb,
            "low" to mi.lowMemory,
            "lowRamDevice" to am.isLowRamDevice,
            "appLimitMb" to am.memoryClass,
            "appPssMb" to Debug.getPss() / 1024L,
        )
    } catch (e: Exception) {
        emptyMap()
    }

    /** Чем открыть приложение после перезапуска (RestartActivity). */
    internal fun relaunchIntent(c: Context): Intent? =
        c.packageManager.getLaunchIntentForPackage(c.packageName)
}
