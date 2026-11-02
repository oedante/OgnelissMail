package com.ogneliss.mail

// Сигналы сервера на Android без сервисов Google (1.10.x, просьба владельца
// 01.11.2026) — через UnifiedPush: распространитель на телефоне (ntfy,
// NextPush, Sunup…) держит своё соединение и передаёт приложению сигналы
// «будильника» (server/push-relay, webpush.js). Для телефонов Huawei и Honor
// с HMS, прошивок без Google и сборок из RuStore — там FCM нет.
//
// Библиотека UnifiedPush connector (Apache 2.0, с Google Tink для
// расшифровки Web Push) — прямо в Android-части, как Firebase в
// PushWakeFcm.kt: без Flutter-плагина.
//
// Как работает:
//  · Dart (PushWakeService) спрашивает список распространителей
//    («distributors»), человек выбирает; «register» сохраняет выбор и
//    регистрирует установку (с открытым ключом VAPID сервера, если он есть);
//  · адрес и ключи приходят асинхронно в PushWakeUnifiedPushService.onNewEndpoint
//    — сохраняем и передаём в Dart («onEndpoint»), Dart регистрирует их на
//    сервере. Dart, запущенный позже, берёт сохранённое («current»);
//  · сигнал (расшифрованный {"w":"1"}) ставит ту же разовую задачу
//    WorkManager «push_wake», что и сигнал FCM (PushWakeFcm.wake).

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.unifiedpush.android.connector.FailedReason
import org.unifiedpush.android.connector.PushService
import org.unifiedpush.android.connector.UnifiedPush
import org.unifiedpush.android.connector.data.PushEndpoint
import org.unifiedpush.android.connector.data.PushMessage

object PushWakeUnifiedPush {
    private const val TAG = "PushWakeUP"
    private const val CHANNEL = "ogneliss/unifiedpush"
    private const val PREFS = "ogneliss_unifiedpush"
    private const val INSTANCE = "default"

    @Volatile
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    private fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "distributors" -> result.success(distributors(app))
                    "current" -> result.success(current(app))
                    "register" -> {
                        val args = call.arguments as? Map<*, *>
                        val dist = (args?.get("distributor") as? String)?.trim().orEmpty()
                        val vapid = (args?.get("vapid") as? String)?.trim()?.takeIf { it.isNotEmpty() }
                        if (dist.isEmpty()) {
                            result.error("args", "no distributor", null)
                        } else {
                            prefs(app).edit().remove("error").apply()
                            UnifiedPush.saveDistributor(app, dist)
                            UnifiedPush.register(app, INSTANCE, "Ogneliss Mail", vapid)
                            result.success(null)
                        }
                    }
                    "unregister" -> {
                        try {
                            UnifiedPush.unregister(app, INSTANCE)
                        } catch (e: Exception) {
                            Log.i(TAG, "unregister: ${e.message}")
                        }
                        prefs(app).edit().clear().apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("unifiedpush", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    fun detach() {
        channel = null
    }

    /** Установленные распространители: пакет и название приложения. */
    private fun distributors(c: Context): List<Map<String, String>> {
        val pm = c.packageManager
        return UnifiedPush.getDistributors(c).map { pkg ->
            val name = try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                pkg
            }
            mapOf("id" to pkg, "name" to name)
        }
    }

    /** Выбранный распространитель и последний адрес с ключами (или null). */
    private fun current(c: Context): Map<String, Any?> {
        val p = prefs(c)
        return mapOf(
            "distributor" to (UnifiedPush.getAckDistributor(c) ?: UnifiedPush.getSavedDistributor(c)),
            "url" to p.getString("url", null),
            "p256dh" to p.getString("p256dh", null),
            "auth" to p.getString("auth", null),
            "error" to p.getString("error", null),
        )
    }

    internal fun onEndpoint(c: Context, endpoint: PushEndpoint) {
        val keys = endpoint.pubKeySet
        prefs(c).edit()
            .putString("url", endpoint.url)
            .putString("p256dh", keys?.pubKey)
            .putString("auth", keys?.auth)
            .remove("error")
            .apply()
        notify("onEndpoint", mapOf("url" to endpoint.url, "p256dh" to keys?.pubKey, "auth" to keys?.auth))
    }

    internal fun onFailed(c: Context, reason: String) {
        prefs(c).edit().putString("error", reason).apply()
        notify("onError", mapOf("reason" to reason))
    }

    internal fun onUnregistered(c: Context) {
        prefs(c).edit().remove("url").remove("p256dh").remove("auth").apply()
        notify("onUnregistered", emptyMap<String, Any?>())
    }

    private fun notify(method: String, args: Map<String, Any?>) {
        val ch = channel ?: return
        main.post {
            try {
                ch.invokeMethod(method, args)
            } catch (e: Exception) {
            }
        }
    }

    internal fun log(msg: String) = Log.i(TAG, msg)
}

/** Служба библиотеки UnifiedPush (AndroidManifest.xml, PUSH_EVENT). */
class PushWakeUnifiedPushService : PushService() {
    override fun onNewEndpoint(endpoint: PushEndpoint, instance: String) {
        PushWakeUnifiedPush.onEndpoint(applicationContext, endpoint)
    }

    override fun onMessage(message: PushMessage, instance: String) {
        // Только сигнал «будильника», зашифрованный ключом этой установки:
        // других сообщений сервер не шлёт.
        val text = try {
            String(message.content, Charsets.UTF_8)
        } catch (e: Exception) {
            ""
        }
        if (!message.decrypted || !text.contains("\"w\"")) return
        try {
            PushWakeFcm.wake(applicationContext, false)
        } catch (e: Exception) {
            PushWakeUnifiedPush.log("wake: ${e.message}")
        }
    }

    override fun onRegistrationFailed(reason: FailedReason, instance: String) {
        PushWakeUnifiedPush.onFailed(applicationContext, reason.name)
    }

    override fun onUnregistered(instance: String) {
        PushWakeUnifiedPush.onUnregistered(applicationContext)
    }
}
