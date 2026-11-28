// android/app/src/main/kotlin/com/ogneliss/mail/FinishWorkKeeper.kt
// Android: доделать начатое после сворачивания (2.7.5, журнал пользователя
// 27.11.2026). Письмо начало уходить (SMTP подключён), через 3 с приложение
// свернули — и отправка встала: Android 12+ замораживает свёрнутое
// приложение через несколько секунд, на медленном мобильном интернете
// письмо не успело уйти. Через 30 минут, при следующем открытии, —
// «Отправка прервана, статус неизвестен».
//
// Как на iPhone (beginBackgroundTask): пока идёт отправка или синхронизация,
// свёрнутое приложение ставит срочную задачу WorkManager. Задача ничего не
// делает — ждёт, пока Dart скажет «закончил» (или 3 минуты), а процесс с
// идущей задачей система не замораживает. Без службы и без уведомления.

package com.ogneliss.mail

import android.content.Context
import android.os.Build
import android.os.SystemClock
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object FinishWorkKeeper {
    private const val CHANNEL = "ogneliss/finish_work"
    private const val WORK = "ogneliss_finish_work"

    /** Работа идёт — задача ждёт. */
    @Volatile
    var busy = false

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> {
                    busy = true
                    result.success(enqueue(app))
                }
                "end" -> {
                    busy = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android 12+: срочная задача (без квоты — обычная). До Android 12
     * приложения так не замораживаются, а срочная задача там потребовала бы
     * службу с уведомлением, — обычная задача.
     */
    private fun enqueue(context: Context): Boolean = try {
        val request = OneTimeWorkRequest.Builder(FinishWorker::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            request.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }
        WorkManager.getInstance(context).enqueueUniqueWork(WORK, ExistingWorkPolicy.KEEP, request.build())
        true
    } catch (e: Exception) {
        false
    }
}

/** Ждёт, пока идёт работа приложения: до 3 минут, проверка раз в секунду. */
class FinishWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val until = SystemClock.elapsedRealtime() + 3 * 60_000L
        while (FinishWorkKeeper.busy && !isStopped && SystemClock.elapsedRealtime() < until) {
            try {
                Thread.sleep(1_000)
            } catch (e: InterruptedException) {
                break
            }
        }
        return Result.success()
    }
}
