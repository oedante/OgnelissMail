package com.ogneliss.mail

// Сигналы сервера на Android (1.9.x, просьба владельца 31.10.2026) — как на
// iPhone (lib/services/push/push_wake_service.dart, server/push-relay).
// Android 15 даёт службе синхронизации (dataSync) не больше 6 часов в сутки,
// а в глубоком сне (Doze) откладывает проверки WorkManager; сигнал FCM
// приходит и тогда, и даже в выгруженный процесс.
//
// Firebase — напрямую библиотекой Android (Apache 2.0), без Flutter-плагинов
// firebase_core / firebase_messaging: те добавили бы Firebase в сборки iOS
// (и перехватывали бы там push «будильника» APNs) и Windows. Без плагина
// google-services и без google-services.json: параметры проекта приходят из
// Dart (dart-defines сборки) при регистрации. Не заданы — ничего не
// подключается, всё как раньше.
//
// Как работает:
//  · Dart вызывает register (канал ogneliss/push, тот же, что у iPhone) —
//    инициализируем Firebase и возвращаем токен FCM; регистрирует его на
//    сервере Dart (PushWakeService);
//  · сервер присылает сообщение только с данными {w: "1"} — ставим разовую
//    задачу WorkManager «push_wake» плагина workmanager: её выполняет тот же
//    Dart-обработчик callbackDispatcher (background_service.dart), что и
//    плановые проверки, — проверку делает живое приложение, если оно в
//    процессе, иначе фоновый изолят; уведомления — как обычно;
//  · сигнал высокого приоритета — задача срочная (expedited, Android 12+):
//    Android даёт её запустить и в глубоком сне.

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dev.fluttercommunity.workmanager.BackgroundWorker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object PushWakeFcm {
    private const val TAG = "PushWakeFcm"
    private const val CHANNEL = "ogneliss/push"

    /** Имя задачи для callbackDispatcher (_TaskNames.pushWake в Dart). */
    private const val TASK = "push_wake"

    /** Уникальное имя работы: сигналы, пришедшие разом, — одна проверка. */
    private const val WORK = "ogneliss_push_wake"

    /** Пакет сервисов Google Play (у microG — то же имя). */
    private const val GMS = "com.google.android.gms"

    /** Канал главного движка — через него новый токен доходит до Dart. */
    @Volatile
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "register" -> {
                    val err = ensureFirebase(app, call.arguments as? Map<*, *>)
                    if (err != null) {
                        result.error("config", err, null)
                    } else {
                        try {
                            FirebaseMessaging.getInstance().token.addOnCompleteListener { t ->
                                val token = if (t.isSuccessful) t.result else null
                                if (token.isNullOrEmpty()) {
                                    // Чаще всего SERVICE_NOT_AVAILABLE — нет
                                    // сервисов Google Play или связи с Google.
                                    result.error("token", t.exception?.message ?: "no token", null)
                                } else {
                                    result.success(token)
                                }
                            }
                        } catch (e: Exception) {
                            result.error("token", e.message ?: e.javaClass.simpleName, null)
                        }
                    }
                }
                // Есть ли сервисы Google Play (1.12.x, просьба владельца
                // 05.11.2026: «с сервисами Google и без них … пользователь не
                // должен думать»). Без них FCM токен не выдаст — Dart сразу
                // выбирает UnifiedPush или проверки по расписанию, без ошибки
                // «SERVICE_NOT_AVAILABLE» под переключателем.
                "googleServices" -> result.success(googleServices(app))
                // Выключили: токен отзываем, чтобы Google не доставлял сигналы,
                // даже если сервер ещё не узнал о выключении.
                "unregister" -> {
                    if (FirebaseApp.getApps(app).isEmpty()) {
                        result.success(null)
                    } else {
                        try {
                            FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { result.success(null) }
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Сервисы Google Play на телефоне: "ok" — установлены и включены (так же
     * выглядит microG), "disabled" — выключены в настройках, "missing" — нет
     * (Huawei и Honor с HMS, LineageOS, GrapheneOS без «песочницы» Google,
     * /e/OS без microG). Пакет виден приложению — <queries> в манифесте.
     */
    fun googleServices(context: Context): String = try {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getApplicationInfo(GMS, 0)
        if (info.enabled) "ok" else "disabled"
    } catch (e: PackageManager.NameNotFoundException) {
        "missing"
    } catch (e: Exception) {
        "unknown"
    }

    /** Версия сервисов Google Play (или microG) — для журнала; null — нет. */
    fun googleServicesVersion(context: Context): String? = try {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(GMS, 0)
        info.versionName
    } catch (e: Exception) {
        null
    }

    /** Движок уничтожен — новый токен возьмёт регистрация при запуске. */
    fun detach() {
        channel = null
    }

    /** Firebase из параметров сборки; null — готово, иначе текст ошибки. */
    private fun ensureFirebase(context: Context, args: Map<*, *>?): String? {
        if (FirebaseApp.getApps(context).isNotEmpty()) return null
        fun arg(key: String) = (args?.get(key) as? String)?.trim().orEmpty()
        val apiKey = arg("apiKey")
        val appId = arg("appId")
        val senderId = arg("senderId")
        val projectId = arg("projectId")
        if (apiKey.isEmpty() || appId.isEmpty() || senderId.isEmpty() || projectId.isEmpty()) {
            return "Firebase options are empty"
        }
        return try {
            FirebaseApp.initializeApp(
                context,
                FirebaseOptions.Builder()
                    .setApiKey(apiKey)
                    .setApplicationId(appId)
                    .setGcmSenderId(senderId)
                    .setProjectId(projectId)
                    .build(),
            )
            null
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    /** Токен сменился (Google обновляет их сам) — Dart перерегистрирует. */
    fun onNewToken(token: String) {
        val ch = channel ?: return
        main.post {
            try {
                ch.invokeMethod("onToken", mapOf("token" to token, "env" to "fcm"))
            } catch (e: Exception) {
            }
        }
    }

    /** Сигнал пришёл — разовая задача WorkManager с проверкой почты. */
    fun wake(context: Context, high: Boolean) {
        val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, TASK).build())
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        // До Android 12 срочная задача идёт через службу переднего плана, а
        // фоновый обработчик плагина её не поддерживает — там обычная.
        if (high && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            request.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }
        // KEEP: проверка уже ждёт или идёт — второй не нужно.
        WorkManager.getInstance(context).enqueueUniqueWork(WORK, ExistingWorkPolicy.KEEP, request.build())
    }

    internal fun log(msg: String) = Log.i(TAG, msg)
}

/** Приёмник сообщений FCM (AndroidManifest.xml, MESSAGING_EVENT). */
class PushWakeMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        // Только сигнал «будильника»: других сообщений сервер не шлёт.
        if (message.data["w"] != "1") return
        try {
            PushWakeFcm.wake(applicationContext, message.priority == RemoteMessage.PRIORITY_HIGH)
        } catch (e: Exception) {
            PushWakeFcm.log("wake: ${e.message}")
        }
    }

    override fun onNewToken(token: String) {
        PushWakeFcm.onNewToken(token)
    }
}
