package com.ogneliss.mail

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.RestrictionsManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.enterprise.feedback.KeyedAppState
import androidx.enterprise.feedback.KeyedAppStatesCallback
import androidx.enterprise.feedback.KeyedAppStatesReporter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Управляемые настройки организации (MDM, 1.10.5): Android Enterprise
 * передаёт их приложению через RestrictionsManager. Список ключей —
 * res/xml/app_restrictions.xml (его читают консоли MDM), разбор и
 * применение — lib/services/security/managed_config.dart.
 *
 * Канал «ogneliss/mdm»: «get» — нынешние настройки словарём (пусто — не
 * управляется); «changed» — в Dart, когда MDM прислал новые (широковещание
 * ACTION_APPLICATION_RESTRICTIONS_CHANGED, только пока процесс жив; при
 * следующем запуске Dart спрашивает «get» сам); «report» — отчёт для
 * консоли MDM (2.2.0, KeyedAppStates из androidx.enterprise:enterprise-feedback,
 * Apache-2.0): список {key, severity, message, data}, что сообщать —
 * lib/services/security/managed_feedback.dart.
 */
object MdmBridge {
    private const val CHANNEL = "ogneliss/mdm"
    private var receiver: BroadcastReceiver? = null
    private var channel: MethodChannel? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(read(app))
                "report" -> {
                    report(app, call.arguments as? List<*> ?: emptyList<Any>())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        if (receiver == null) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) {
                    Handler(Looper.getMainLooper()).post {
                        runCatching { channel?.invokeMethod("changed", null) }
                    }
                }
            }
            val filter = IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED)
            runCatching {
                // Системное широковещание: на Android 13+ приёмник
                // регистрируется явно как не принимающий чужие намерения.
                if (Build.VERSION.SDK_INT >= 33) {
                    app.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    app.registerReceiver(r, filter)
                }
                receiver = r
            }
        }
    }

    private var reporter: KeyedAppStatesReporter? = null

    /**
     * Отчёт консоли MDM. Без управляющего приложения (DPC) или на старом
     * Android отчёт просто никуда не уходит; сбой — только в журнал.
     */
    private fun report(context: Context, items: List<*>) {
        runCatching {
            val states = items.mapNotNull { item ->
                val m = item as? Map<*, *> ?: return@mapNotNull null
                val key = m["key"] as? String ?: return@mapNotNull null
                runCatching {
                    KeyedAppState.builder()
                        .setKey(key)
                        .setSeverity(
                            if ((m["severity"] as? Number)?.toInt() == 2) KeyedAppState.SEVERITY_ERROR
                            else KeyedAppState.SEVERITY_INFO
                        )
                        .setMessage(m["message"] as? String)
                        .setData(m["data"] as? String)
                        .build()
                }.getOrNull()
            }
            if (states.isEmpty()) return
            val r = reporter ?: KeyedAppStatesReporter.create(context).also { reporter = it }
            r.setStates(states) { status, error ->
                if (status != KeyedAppStatesCallback.STATUS_SUCCESS) {
                    Log.w("OgnelissMdm", "KeyedAppStates: status $status ${error ?: ""}")
                }
            }
        }.onFailure { Log.w("OgnelissMdm", "KeyedAppStates: $it") }
    }

    private fun read(context: Context): Map<String, Any?> {
        val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as? RestrictionsManager
            ?: return emptyMap()
        val b: Bundle = runCatching { rm.applicationRestrictions }.getOrNull() ?: return emptyMap()
        val out = HashMap<String, Any?>()
        for (key in b.keySet()) {
            @Suppress("DEPRECATION")
            when (val v = b.get(key)) {
                is String, is Boolean, is Int, is Long -> out[key] = v
                is Array<*> -> out[key] = v.map { it?.toString() }
                null -> {}
                else -> out[key] = v.toString()
            }
        }
        return out
    }
}
