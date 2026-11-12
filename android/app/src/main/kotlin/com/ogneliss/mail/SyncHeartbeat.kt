package com.ogneliss.mail

// «Пульс» фоновой работы: будильник ОС раз в ~10 минут будит процесс, пока
// работает SyncForegroundService, и даёт Dart до двух минут, чтобы проверить
// push и выполнить плановую синхронизацию.
//
// Будильник без службы (2.3.2, требование владельца 11.11.2026: «для всех
// режимов — 15, 30, час, по расписанию, пуш — проверки должны срабатывать
// вовремя, а не когда придётся»). Служба работает только у ящиков
// «Мгновенно» и «По расписанию»; у остальных почту в фоне проверяли плановая
// задача WorkManager и сигнал сервера (FCM обычного приоритета), а их
// Android в глубоком сне (Doze) откладывает до редких окон обслуживания:
// журнал 10.11.2026 — проверки в 16:05, 17:28, 19:39 при «раз в 15 минут».
// Теперь будильник выставлен всегда, когда включены фоновые проверки: к
// сроку ближайшего ящика (его пишет Dart после каждой проверки) он на
// время проверки поднимает службу почты — у процесса со службой сеть и
// процессор есть и в глубоком сне — и ставит задачу проверки (та же, что у
// плановой). Служба стартовать не смогла (Android 12+ без точных
// будильников) — срочная задача WorkManager, как раньше.
//
// Зачем, если процесс и так жив (foreground service): живой процесс ≠
// работающий процессор. Экран погас — процессор засыпает, Dart-таймеры
// (перезапуск IMAP IDLE, сторож push, проверка каждые 5 минут) не
// срабатывают. Тем временем NAT оператора забывает молчащее соединение, и
// сервер уже не может сообщить о письме. Отсюда «push работает, а через
// какое-то время перестаёт», тогда как опрос раз в 15 минут (WorkManager —
// JobScheduler с собственной блокировкой сна) работал.
//
// setExactAndAllowWhileIdle / setAndAllowWhileIdle срабатывают и в Doze
// (не чаще раза в ~9–15 минут — этого достаточно). Точный вариант — если
// разрешены точные будильники (их уже просят для напоминаний о встречах).

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker

object SyncHeartbeat {
    /** Пульс при работающей службе («Мгновенно», «По расписанию»). */
    private const val INTERVAL_MS = 10 * 60 * 1000L

    // ── Будильник без службы ────────────────────────────────────────────
    // Настройку пишет Dart в SharedPreferences Flutter (BackgroundAlarm):
    //  · bg_alarm_minutes — наименьший интервал проверки среди ящиков, минуты
    //    (0 или нет — фоновые проверки выключены, будильник не нужен);
    //  · bg_next_due_at — срок ближайшего ящика, мс эпохи (0 — неизвестен).
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_MINUTES = "flutter.bg_alarm_minutes"
    private const val KEY_DUE = "flutter.bg_next_due_at"

    /** До срока меньше этого — проверяем сейчас (у Dart запас в минуту). */
    private const val EARLY_MS = 30_000L

    /** Срок прошёл, а будильника не было (запуск процесса) — через 2 минуты. */
    private const val SOON_MS = 2 * 60 * 1000L
    private const val MIN_DELAY_MS = 60_000L

    /** Уникальные имена работ: проверка из службы и запасная (срочная). */
    private const val CHECK_WORK = "ogneliss_alarm_check"
    private const val FALLBACK_WORK = "ogneliss_heartbeat_check"

    /** Задача Dart (BackgroundService._TaskNames.alarmCheck). */
    private const val CHECK_TASK = "alarm_check"

    /** Сколько держим процессор ради одного пульса (Dart отвечает раньше). */
    const val MAX_WORK_MS = 2 * 60 * 1000L

    /** Потолок короткой проверки в службе (у задачи Dart — 3 минуты). */
    const val MAX_CHECK_MS = 3 * 60 * 1000L + 30_000L
    private const val REQUEST_CODE = 4712

    /**
     * Когда должен сработать выставленный будильник (elapsedRealtime) и точный
     * ли он (1.6.43): по опозданию пульса видно, что оболочка производителя
     * останавливала приложение целиком (журнал Honor 19.10.2026 — 84 минуты
     * без единого пульса при службе и точных будильниках).
     */
    @Volatile
    private var expectedAt = 0L
    @Volatile
    var lastExact = false
        private set

    /** На сколько опоздал сработавший пульс, мс (0 — не знаем или вовремя). */
    fun lateMs(): Long {
        val at = expectedAt
        if (at <= 0L) return 0L
        val late = SystemClock.elapsedRealtime() - at
        return if (late > 0L) late else 0L
    }

    private fun pending(context: Context, flags: Int): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, SyncHeartbeatReceiver::class.java),
            flags or PendingIntent.FLAG_IMMUTABLE,
        )

    /** Будильник через [delayMs]: точный, если разрешено; срабатывает и в Doze. */
    private fun set(context: Context, delayMs: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pending(context, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        val at = SystemClock.elapsedRealtime() + delayMs
        try {
            val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
            if (exact) {
                am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
            }
            lastExact = exact
        } catch (e: SecurityException) {
            // Разрешение на точные будильники отозвали между проверкой и вызовом.
            am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
            lastExact = false
        }
        expectedAt = at
    }

    /** Пульс при работающей службе: следующий — через 10 минут. */
    fun schedule(context: Context) = set(context, INTERVAL_MS)

    private fun long(context: Context, key: String): Long = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(key, 0L)
    } catch (e: Exception) {
        // Значение другого типа или файл не прочитался — как «не задано».
        0L
    }

    /** Интервал будильника без службы, мс; 0 — фоновые проверки выключены. */
    fun standbyIntervalMs(context: Context): Long {
        val minutes = long(context, KEY_MINUTES)
        return if (minutes <= 0L) 0L else minutes.coerceIn(5L, 60L) * 60_000L
    }

    /** Сколько до срока ближайшего ящика, мс; null — срок неизвестен. */
    private fun untilDueMs(context: Context): Long? {
        val due = long(context, KEY_DUE)
        return if (due <= 0L) null else due - System.currentTimeMillis()
    }

    /**
     * Сработал будильник без службы: ждать срока или проверять.
     * Возвращает задержку следующего будильника и «проверять сейчас».
     * До срока больше [EARLY_MS] (почту уже проверили: приложение, плановая
     * задача, сигнал сервера) — будильник переставляется на срок, проверки
     * нет. Иначе — проверка, а следующий будильник — через интервал: после
     * проверки он переставится по новому сроку ([afterCheck]).
     */
    internal fun standbyPlan(intervalMs: Long, untilDueMs: Long?): Pair<Long, Boolean> {
        if (untilDueMs != null && untilDueMs > EARLY_MS) {
            return Pair(untilDueMs.coerceAtMost(intervalMs).coerceAtLeast(MIN_DELAY_MS), false)
        }
        return Pair(intervalMs, true)
    }

    /**
     * Выставить будильник без службы по настройке (запуск процесса, служба
     * остановлена, приложение свернули или сменили настройки). Фоновые
     * проверки выключены — снять.
     */
    fun applyStandby(context: Context) {
        val interval = standbyIntervalMs(context)
        if (interval <= 0L) {
            cancel(context)
            return
        }
        val wait = untilDueMs(context)
        val delay = when {
            wait == null -> interval
            wait > MIN_DELAY_MS -> wait.coerceAtMost(interval)
            else -> SOON_MS
        }
        set(context, delay)
    }

    /**
     * Запуск процесса (OgnelissApplication): будильника нет (перезагрузка
     * телефона, обновление приложения, принудительная остановка) — выставить.
     * Приёмника загрузки у приложения нет (замечание Google Play, 1.6.12):
     * после перезагрузки процесс поднимает плановая задача WorkManager.
     */
    fun ensureArmed(context: Context) {
        try {
            if (SyncForegroundService.running) return
            if (pending(context, PendingIntent.FLAG_NO_CREATE) != null) return
            applyStandby(context)
        } catch (e: Exception) {
        }
    }

    /** Сработал будильник, службы нет. */
    fun onStandbyAlarm(context: Context) {
        val interval = standbyIntervalMs(context)
        // Фоновые проверки выключены — цепочка будильников на этом кончается.
        if (interval <= 0L) return
        val (delay, check) = standbyPlan(interval, untilDueMs(context))
        set(context, delay)
        if (check) startCheck(context)
    }

    /**
     * Проверка почты по будильнику без постоянной службы: служба почты
     * поднимается на время проверки — у процесса со службой переднего плана
     * сеть и процессор есть и в глубоком сне. Запуск службы из фона Android
     * 12+ разрешает точному будильнику; не разрешил — срочная задача.
     */
    private fun startCheck(context: Context) {
        try {
            SyncForegroundService.startCheck(context)
        } catch (e: Exception) {
            enqueueCheck(context, inService = false)
        }
    }

    /**
     * Задача проверки почты (Dart: callbackDispatcher, как у плановой).
     * [inService] — служба поднята: без условия «есть сеть» и не срочная —
     * WorkManager запускает её сразу в этом же процессе, а сеть процессу даёт
     * служба. Иначе — срочная задача с условием сети (Android 12+: система
     * выполняет её и в глубоком сне, пока хватает квоты; до Android 12
     * срочных задач нет — обычная).
     */
    fun enqueueCheck(context: Context, inService: Boolean): androidx.work.Operation? = try {
        val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, CHECK_TASK).build())
        if (!inService) {
            request.setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                request.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }
        }
        // KEEP: проверка уже ждёт или идёт — второй не нужно.
        WorkManager.getInstance(context).enqueueUniqueWork(
            if (inService) CHECK_WORK else FALLBACK_WORK,
            ExistingWorkPolicy.KEEP,
            request.build(),
        )
    } catch (e: Exception) {
        null
    }

    /**
     * Проверка из службы: поставить задачу и сообщить [done], когда она
     * закончилась (успехом, ошибкой или отменой). Состояние работы
     * опрашивается раз в полторы секунды; потолок по времени — у службы.
     */
    fun runCheckInService(context: Context, done: () -> Unit) {
        val main = ContextCompat.getMainExecutor(context)
        val op = enqueueCheck(context, inService = true)
        if (op == null) {
            done()
            return
        }
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        fun poll() {
            try {
                val f = WorkManager.getInstance(context).getWorkInfosForUniqueWork(CHECK_WORK)
                f.addListener({
                    val finished = try {
                        f.get().all { it.state.isFinished }
                    } catch (e: Exception) {
                        true
                    }
                    if (finished) done() else handler.postDelayed({ poll() }, 1500L)
                }, main)
            } catch (e: Exception) {
                done()
            }
        }
        try {
            // Сначала — запись работы в базу WorkManager: иначе опрос увидел
            // бы прежнюю, уже завершённую работу с тем же именем.
            op.result.addListener({ poll() }, main)
        } catch (e: Exception) {
            done()
        }
    }

    /**
     * Проверка закончилась: будильник — на новый срок, если Dart его записал
     * (иначе остаётся выставленный при срабатывании — через интервал).
     */
    fun afterCheck(context: Context) {
        val interval = standbyIntervalMs(context)
        if (interval <= 0L) return
        val wait = untilDueMs(context) ?: return
        if (wait > MIN_DELAY_MS) set(context, wait.coerceAtMost(interval))
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        expectedAt = 0L
        val pi = pending(context, PendingIntent.FLAG_NO_CREATE) ?: return
        am.cancel(pi)
        pi.cancel()
    }

    /** Для журнала Dart: интервал без службы (мин) и точный ли будильник. */
    fun state(context: Context): Map<String, Any> {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || try {
            am.canScheduleExactAlarms()
        } catch (e: Exception) {
            false
        }
        return mapOf(
            "minutes" to (standbyIntervalMs(context) / 60_000L).toInt(),
            "exact" to exact,
            "armed" to (pending(context, PendingIntent.FLAG_NO_CREATE) != null),
            "service" to SyncForegroundService.running,
        )
    }
}

class SyncHeartbeatReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext
        // Постоянной службы нет («раз в 15 минут», «30», «час» — или службу
        // остановила система): будильник без службы — проверка к сроку
        // ближайшего ящика, и в глубоком сне (2.3.2).
        if (!SyncForegroundService.running) {
            SyncHeartbeat.onStandbyAlarm(app)
            return
        }
        // Опоздание — до перестановки будильника (она сбрасывает ожидание).
        val args = mapOf<String, Any>("lateMs" to SyncHeartbeat.lateMs(), "exact" to SyncHeartbeat.lastExact)
        SyncHeartbeat.schedule(app) // следующий — сразу, до работы

        val pm = app.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ogneliss:sync-heartbeat")
        wl.setReferenceCounted(false)
        wl.acquire(SyncHeartbeat.MAX_WORK_MS)
        val sent = ForegroundSyncPlugin.sendHeartbeat(args) {
            if (wl.isHeld) wl.release()
        }
        if (!sent && wl.isHeld) wl.release()
    }
}
