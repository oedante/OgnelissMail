package com.ogneliss.mail

// Диагностика фоновой работы и уведомлений на конкретном устройстве.
//
// Зачем: на «чистом» Android (Pixel) фоновую работу ограничивают Doze,
// корзины ожидания (App Standby Buckets) и «Батарея → Ограничено». Поверх
// этого производители ставят собственные «оптимизаторы», которые убивают
// процесс, запрещают автозапуск и будильники: MIUI/HyperOS (Xiaomi, Redmi,
// POCO), EMUI/MagicOS (Huawei, Honor), ColorOS/OxygenOS/realme UI (OPPO,
// OnePlus, realme), Funtouch/OriginOS (vivo, iQOO), One UI («Спящие
// приложения» Samsung), MyOS/nubia UI (ZTE, nubia, RedMagic). По журналу
// это выглядит как «push работал, потом пропал» без единой ошибки. Здесь
// собирается всё, что Android позволяет узнать о таких ограничениях без
// особых разрешений, — для журнала, пакета диагностики и экрана разрешений.

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.ApplicationExitInfo
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import java.io.BufferedReader
import java.io.InputStreamReader

object BackgroundDiagnostics {

    private fun prop(name: String): String = try {
        val p = Runtime.getRuntime().exec(arrayOf("getprop", name))
        BufferedReader(InputStreamReader(p.inputStream)).use { it.readLine()?.trim() ?: "" }
    } catch (e: Exception) {
        ""
    }

    /** Оболочка производителя за время жизни процесса не меняется (1.6.9). */
    @Volatile
    private var romCache: Pair<String, String>? = null

    /** Оболочка производителя и её версия (по системным свойствам). */
    fun rom(): Pair<String, String> = romCache ?: detectRom().also { romCache = it }

    private fun detectRom(): Pair<String, String> {
        val checks = listOf(
            "HyperOS" to "ro.mi.os.version.name",
            "MIUI" to "ro.miui.ui.version.name",
            "MagicOS" to "ro.build.version.magic",
            "EMUI" to "ro.build.version.emui",
            "HarmonyOS" to "hw_sc.build.platform.version",
            "ColorOS" to "ro.build.version.opporom",
            "OxygenOS" to "ro.oxygen.version",
            "realme UI" to "ro.build.version.realmeui",
            "OriginOS/Funtouch" to "ro.vivo.os.version",
            "MyOS/MiFavor" to "ro.build.MiFavor_version",
            "nubia UI" to "ro.build.nubia.rom.name",
            "Flyme" to "ro.build.display.id.flyme",
            "One UI" to "ro.build.version.oneui",
        )
        for ((name, key) in checks) {
            val v = prop(key)
            if (v.isNotEmpty()) return name to v
        }
        val display = Build.DISPLAY ?: ""
        if (display.contains("Flyme", true)) return "Flyme" to display
        return "" to ""
    }

    private fun bucketName(b: Int): String = when (b) {
        5 -> "exempted"
        UsageStatsManager.STANDBY_BUCKET_ACTIVE -> "active"
        UsageStatsManager.STANDBY_BUCKET_WORKING_SET -> "working_set"
        UsageStatsManager.STANDBY_BUCKET_FREQUENT -> "frequent"
        UsageStatsManager.STANDBY_BUCKET_RARE -> "rare"
        45 -> "restricted"
        else -> "bucket_$b"
    }

    /** [full] = false — без оболочки производителя (getprop): для частых замеров. */
    fun collect(context: Context, full: Boolean = true): Map<String, Any?> {
        val ctx = context.applicationContext
        val out = HashMap<String, Any?>()
        out["manufacturer"] = Build.MANUFACTURER
        out["brand"] = Build.BRAND
        out["model"] = Build.MODEL
        out["device"] = Build.DEVICE
        out["sdk"] = Build.VERSION.SDK_INT
        out["release"] = Build.VERSION.RELEASE
        if (full) {
            val (romName, romVer) = rom()
            out["rom"] = romName
            out["romVersion"] = romVer
        }

        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        out["ignoringBatteryOptimizations"] = pm.isIgnoringBatteryOptimizations(ctx.packageName)
        out["powerSaveMode"] = pm.isPowerSaveMode
        out["deviceIdleMode"] = pm.isDeviceIdleMode
        out["interactive"] = pm.isInteractive

        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            out["backgroundRestricted"] = am.isBackgroundRestricted
            val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            out["standbyBucket"] = bucketName(usm.appStandbyBucket)
        }

        val alarm = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        out["exactAlarms"] = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        out["notificationsEnabled"] = nm.areNotificationsEnabled()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            out["channels"] = nm.notificationChannels.map {
                mapOf("id" to it.id, "importance" to it.importance)
            }
        }

        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        // 1 — «Экономия трафика» выключена, 2 — приложение в исключениях,
        // 3 — включена: фоновая передача данных запрещена.
        out["dataSaver"] = when (cm.restrictBackgroundStatus) {
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED -> "off"
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED -> "allowed"
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED -> "on"
            else -> "unknown"
        }

        val battery = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (battery != null) {
            val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            if (level >= 0 && scale > 0) out["batteryPct"] = level * 100 / scale
            val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            out["charging"] = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        }
        out["foregroundService"] = SyncForegroundService.running
        out["networkBlocked"] = networkBlocked(ctx)
        return out
    }

    /**
     * Сеть для приложения закрыта системой (1.6.43): Doze, корзина ожидания,
     * экономия энергии или трафика, ограничения фона Android 15+, правила
     * оболочки производителя. ConnectivityManager отдаёт приложению состояние
     * сети с учётом его запретов: при запрете — DetailedState.BLOCKED.
     * Журнал OnePlus 18.10.2026: свёрнутое приложение без службы два часа
     * получало «Unable to resolve host», а фоновая задача в то же время — 200.
     */
    @Suppress("DEPRECATION")
    fun networkBlocked(context: Context): Boolean = try {
        val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.activeNetworkInfo?.detailedState == android.net.NetworkInfo.DetailedState.BLOCKED
    } catch (e: Exception) {
        false
    }

    private fun reasonName(r: Int): String = when (r) {
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency_died"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
        ApplicationExitInfo.REASON_EXIT_SELF -> "exit_self"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "init_failure"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
        ApplicationExitInfo.REASON_OTHER -> "other"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission_change"
        ApplicationExitInfo.REASON_SIGNALED -> "signaled"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
        14 -> "freezer"
        15 -> "package_state_change"
        16 -> "package_updated"
        else -> "reason_$r"
    }

    /**
     * Читаемые строки из записи о падении в машинном коде (1.7.2+114). На
     * Android 12+ система хранит её (tombstone) в формате protobuf: сигнал,
     * причина, сообщение abort, библиотеки в стеке. Разбирать формат не
     * нужно — достаточно печатных строк. Журнал владельца 25.10.2026 («Сжать»
     * закрывало приложение) показал только «crash_native» — без места
     * падения. Ни писем, ни адресов в этой записи нет: только код.
     */
    private fun crashTrace(info: ApplicationExitInfo): String? {
        if (info.reason != ApplicationExitInfo.REASON_CRASH_NATIVE) return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            val raw = info.traceInputStream?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val chunk = ByteArray(16 * 1024)
                while (out.size() < 768 * 1024) {
                    val n = input.read(chunk)
                    if (n <= 0) break
                    out.write(chunk, 0, n)
                }
                out.toByteArray()
            } ?: return null
            val strings = LinkedHashSet<String>()
            val sb = StringBuilder()
            for (b in raw) {
                val c = b.toInt() and 0xFF
                if (c in 0x20..0x7E) {
                    sb.append(c.toChar())
                } else {
                    if (sb.length >= 4) strings.add(sb.toString())
                    sb.setLength(0)
                }
            }
            if (sb.length >= 4) strings.add(sb.toString())
            val keys = listOf("SIG", "SEGV", "BUS_", "abort", "Abort", "Cause", "fault", "Exhausted",
                "Out of memory", "FATAL", "Check failed", "assert", "Assert")
            val important = strings.filter { s -> keys.any { s.contains(it) } }.take(12)
            // Библиотеки в порядке появления (первым идёт стек упавшего
            // потока): libflutter, libapp, libc, драйвер видеокарты…
            val libs = strings.filter { it.endsWith(".so") }
                .map { it.substringAfterLast('/') }
                .distinct()
                .take(10)
            val threadName = Regex("^\\d+\\.(ui|raster|io|platform)$")
            val threads = strings.filter { it.matches(threadName) || it.startsWith("DartWorker") }
                .distinct()
                .take(4)
            val parts = mutableListOf<String>()
            if (important.isNotEmpty()) parts.add(important.joinToString(" | "))
            if (libs.isNotEmpty()) parts.add("lib: " + libs.joinToString(", "))
            if (threads.isNotEmpty()) parts.add("потоки: " + threads.joinToString(", "))
            if (parts.isEmpty()) null else parts.joinToString(" ; ").take(1500)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Почему система завершала процесс (Android 11+): нехватка памяти,
     * «оптимизатор» производителя (обычно other/signaled), смахивание,
     * обновление. Только записи новее [sinceMs].
     */
    fun exitReasons(context: Context, sinceMs: Long): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return try {
            am.getHistoricalProcessExitReasons(context.packageName, 0, 16)
                .filter { it.timestamp > sinceMs }
                .map {
                    mapOf(
                        "ts" to it.timestamp,
                        "reason" to reasonName(it.reason),
                        "importance" to it.importance,
                        "description" to (it.description ?: ""),
                        "pss" to it.pss,
                        "process" to (it.processName ?: ""),
                        "pid" to it.pid,
                        "trace" to crashTrace(it),
                    )
                }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Открыть экран производителя, где разрешают автозапуск и работу в фоне.
     * Компоненты известны по опыту других приложений (dontkillmyapp.com);
     * на конкретной прошивке экрана может не быть — тогда пробуем следующий,
     * а в конце открываем сведения о приложении (там на Android 12+ есть
     * «Батарея → Без ограничений»). Возвращает, что удалось открыть.
     */
    fun openOemSettings(context: Context): String {
        val pkg = context.packageName
        val candidates = listOf(
            // Xiaomi / Redmi / POCO (MIUI, HyperOS)
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"),
            // Huawei / Honor
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            ComponentName("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            // OPPO / realme / OnePlus (ColorOS, OxygenOS 12+)
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
            ComponentName("com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
            ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
            // vivo / iQOO
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            // Samsung (Обслуживание устройства → Батарея)
            ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"),
            ComponentName("com.samsung.android.sm", "com.samsung.android.sm.battery.ui.BatteryActivity"),
            // ZTE / nubia / RedMagic
            ComponentName("com.zte.heartyservice", "com.zte.heartyservice.autorun.AppAutoRunManager"),
            ComponentName("cn.nubia.security2", "cn.nubia.security.appmanage.selfstart.ui.SelfStartActivity"),
            ComponentName("com.zte.powersavemode", "com.zte.powersavemode.ui.AppPowerManagerActivity"),
            // ASUS, Meizu
            ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity"),
            ComponentName("com.meizu.safe", "com.meizu.safe.permission.SmartBGActivity"),
        )
        val maker = Build.MANUFACTURER.lowercase()
        val ordered = candidates.sortedByDescending { c ->
            val p = c.packageName
            when {
                maker.contains("xiaomi") || maker.contains("redmi") || maker.contains("poco") -> p.startsWith("com.miui")
                maker.contains("huawei") -> p.startsWith("com.huawei")
                maker.contains("honor") -> p.startsWith("com.hihonor") || p.startsWith("com.huawei")
                maker.contains("oppo") || maker.contains("realme") || maker.contains("oneplus") ->
                    p.startsWith("com.coloros") || p.startsWith("com.oplus") || p.startsWith("com.oppo") || p.startsWith("com.oneplus")
                maker.contains("vivo") || maker.contains("iqoo") -> p.startsWith("com.vivo") || p.startsWith("com.iqoo")
                maker.contains("samsung") -> p.startsWith("com.samsung")
                maker.contains("zte") || maker.contains("nubia") -> p.startsWith("com.zte") || p.startsWith("cn.nubia")
                maker.contains("asus") -> p.startsWith("com.asus")
                maker.contains("meizu") -> p.startsWith("com.meizu")
                else -> false
            }
        }
        for (c in ordered) {
            try {
                val i = Intent().setComponent(c).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra("package_name", pkg).putExtra("packageName", pkg)
                context.startActivity(i)
                return c.flattenToShortString()
            } catch (e: ActivityNotFoundException) {
            } catch (e: SecurityException) {
            } catch (e: Exception) {
            }
        }
        return if (openAppDetails(context)) "app_details" else ""
    }

    fun openAppDetails(context: Context): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:" + context.packageName))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        false
    }
}
