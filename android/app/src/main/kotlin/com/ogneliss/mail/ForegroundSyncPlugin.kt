package com.ogneliss.mail

// Канал управления foreground-сервисом фоновой синхронизации из Dart.
// Интеграция в MainActivity: ForegroundSyncPlugin.register(messenger, this)

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object ForegroundSyncPlugin {
    private const val CHANNEL = "ogneliss/foreground_sync"

    /** Канал главного движка — через него пульс доходит до Dart. */
    @Volatile
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    /** Медленные замеры (getprop, причины завершения) — вне главного потока. */
    private val worker = java.util.concurrent.Executors.newSingleThreadExecutor()

    /**
     * Передать пульс в Dart. [args] — опоздание будильника (lateMs, exact).
     * [done] вызывается, когда Dart ответил (или ответить не смог) — тогда
     * отпускаем блокировку сна. false — движка нет.
     */
    fun sendHeartbeat(args: Map<String, Any>?, done: () -> Unit): Boolean {
        val ch = channel ?: return false
        main.post {
            try {
                ch.invokeMethod("heartbeat", args, object : MethodChannel.Result {
                    override fun success(result: Any?) = done()
                    override fun error(code: String, message: String?, details: Any?) = done()
                    override fun notImplemented() = done()
                })
            } catch (e: Exception) {
                done()
            }
        }
        return true
    }

    /**
     * Движок Flutter уничтожен (активность закрыта насовсем): Dart больше нет,
     * держать процесс и будить его незачем.
     */
    fun detach(context: Context) {
        channel = null
        try {
            SyncForegroundService.stop(context.applicationContext)
        } catch (e: Exception) {
        }
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> result.success(true)
                // Задержка удержания из «Спец. возможностей» (1.6.46): карточка
                // письма открывается через 250 мс, но если человек выбрал
                // задержку длиннее — по ней.
                "longPressTimeout" -> result.success(android.view.ViewConfiguration.getLongPressTimeout())
                // Закрыта ли приложению сеть (1.6.43): свёрнутому приложению
                // без службы Android 16 / оболочка закрывают её — таймер
                // главного изолята тогда не стучится к серверу зря.
                "networkBlocked" -> result.success(BackgroundDiagnostics.networkBlocked(context))
                // Работает ли сервис на самом деле: запуск из фона Android 12+
                // может запретить, и сервис тихо останавливается (см. onStartCommand).
                "isRunning" -> result.success(SyncForegroundService.running)
                // Диагностика фоновой работы (BackgroundDiagnostics).
                // 1.6.9: не в главном потоке. С Flutter 3.29 главный поток
                // Android и поток интерфейса Flutter — один, а сбор вызывает
                // getprop (запуск процесса) до 13 раз: экран «Разрешения»
                // замирал при открытии.
                "diagnostics" -> {
                    val full = call.argument<Boolean>("full") ?: true
                    worker.execute {
                        try {
                            val m = BackgroundDiagnostics.collect(context, full)
                            main.post { result.success(m) }
                        } catch (e: Exception) {
                            main.post { result.error("DIAG_FAILED", e.message, null) }
                        }
                    }
                }
                "exitReasons" -> {
                    val since = (call.argument<Number>("since") ?: 0).toLong()
                    worker.execute {
                        val r = try {
                            BackgroundDiagnostics.exitReasons(context, since)
                        } catch (e: Exception) {
                            emptyList<Map<String, Any?>>()
                        }
                        main.post { result.success(r) }
                    }
                }
                "openOemSettings" -> result.success(BackgroundDiagnostics.openOemSettings(context))
                "openAppDetails" -> result.success(BackgroundDiagnostics.openAppDetails(context))
                "start" -> {
                    try {
                        SyncForegroundService.start(context.applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        SyncForegroundService.stop(context.applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_FAILED", e.message, null)
                    }
                }
                // Исключение из оптимизации батареи. Прямой запрос
                // (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) Google Play разрешает
                // лишь узкому кругу приложений — почты в нём нет. Поэтому
                // открываем системный список, где пользователь выбирает сам.
                "batteryUnrestricted" -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(context.packageName))
                }
                "openBatterySettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message, null)
                    }
                }
                // Все уведомления приложения (1.6.44): там включают выключенную
                // категорию «Почта» — без неё о письмах телефон молчит.
                "openAppNotificationSettings" -> {
                    try {
                        val i = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(android.net.Uri.parse("package:" + context.packageName))
                        }
                        context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message, null)
                    }
                }
                // Настройки канала уведомления фоновой работы: выключив его,
                // пользователь убирает строку из шторки, а сервис работает
                // дальше (Android 13+ показывает его в «Активных приложениях»).
                "openNotificationSettings" -> {
                    try {
                        val i = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, SyncForegroundService.CHANNEL_ID)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(android.net.Uri.parse("package:" + context.packageName))
                        }
                        context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
