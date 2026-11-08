package com.ogneliss.mail

// «Пульс» фоновой работы: будильник ОС раз в ~10 минут будит процесс, пока
// работает SyncForegroundService, и даёт Dart до двух минут, чтобы проверить
// push и выполнить плановую синхронизацию.
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
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker

object SyncHeartbeat {
    private const val INTERVAL_MS = 10 * 60 * 1000L

    /**
     * Пульс без службы (2.0.0): служба остановлена не приложением — лимит
     * Android 15 (6 часов в сутки) или процесс выгружен системой. Будильник
     * остаётся и раз в 15 минут (как плановая задача, но и в глубоком сне)
     * ставит срочную задачу проверки почты. Снимается явной остановкой
     * фоновой работы из приложения и при следующем запуске службы.
     */
    private const val STANDBY_INTERVAL_MS = 15 * 60 * 1000L
    private const val STANDBY_WORK = "ogneliss_heartbeat_check"

    /** Задача Dart — та же, что у плановой проверки (BackgroundService). */
    private const val STANDBY_TASK = "periodic_sync"
    /** Сколько держим процессор ради одного пульса (Dart отвечает раньше). */
    const val MAX_WORK_MS = 2 * 60 * 1000L
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

    fun schedule(context: Context, standby: Boolean = false) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pending(context, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        val at = SystemClock.elapsedRealtime() + if (standby) STANDBY_INTERVAL_MS else INTERVAL_MS
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

    /** Срочная задача проверки почты (без службы); одна на все пульсы. */
    fun wakeCheck(context: Context) {
        try {
            val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                .setInputData(Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, STANDBY_TASK).build())
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                request.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }
            WorkManager.getInstance(context)
                .enqueueUniqueWork(STANDBY_WORK, ExistingWorkPolicy.KEEP, request.build())
        } catch (e: Exception) {
        }
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        expectedAt = 0L
        val pi = pending(context, PendingIntent.FLAG_NO_CREATE) ?: return
        am.cancel(pi)
        pi.cancel()
    }
}

class SyncHeartbeatReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext
        // Службы нет, а будильник есть — значит, её остановило не приложение
        // (явная остановка снимает будильник): лимит Android 15 или процесс
        // выгружен. Дальше — пульс без службы: срочная задача проверки почты
        // раз в 15 минут, и в глубоком сне (2.0.0).
        if (!SyncForegroundService.running) {
            SyncHeartbeat.schedule(app, standby = true)
            SyncHeartbeat.wakeCheck(app)
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
