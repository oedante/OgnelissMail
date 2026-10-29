package com.ogneliss.mail

import android.content.Intent
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Главная активность Ogneliss Mail.
 *
 * FlutterFragmentActivity, а не FlutterActivity: этого требует local_auth
 * (биометрический вход) — с обычной активностью диалог отпечатка/лица не
 * показывается и вход по биометрии падает с ошибкой no_fragment_activity.
 *
 * Здесь же регистрируются собственные платформенные каналы приложения
 * (контакты и календарь устройства, работа в фоне,
 * безопасность устройства для политик Exchange).
 * Без регистрации Dart-сторона получала бы MissingPluginException.
 *
 * Движок Flutter живёт ДОЛЬШЕ активности (07.10.2026). Раньше движок
 * уничтожался вместе с активностью: смахнули приложение из недавних или
 * вышли кнопкой «Назад» — Dart останавливался, push (IMAP IDLE, EAS Ping,
 * EWS-поток) умирал, и почта приходила только раз в 15+ минут через
 * WorkManager. Теперь движок хранится в FlutterEngineCache и продолжает
 * работать без окна, пока процесс держит SyncForegroundService (режим
 * «Мгновенно»). Новая активность подключается к тому же движку — состояние
 * приложения сохраняется. Так работает Direct Push у Nine.
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        /** Открыто письмо под грифом: FLAG_SECURE и для новой активности
         *  (движок живёт дольше активности). */
        @Volatile var secureOn = false
        const val ENGINE_ID = "ogneliss_main"

        /**
         * Движок из кэша; при первом запуске процесса — создаётся и запускается.
         * Плагины из pubspec регистрируются конструктором FlutterEngine. Вызывается
         * и окном «Создать» виджета календаря: без движка встреча из виджета
         * ждала бы открытия приложения.
         */
        fun ensureEngine(context: android.content.Context): FlutterEngine {
            val cache = FlutterEngineCache.getInstance()
            cache.get(ENGINE_ID)?.let { return it }
            val app = context.applicationContext
            val engine = FlutterEngine(app)
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}
                override fun onEngineWillDestroy() {
                    // Движок уничтожен (процесс завершается) — Dart больше нет:
                    // фоновый сервис и его пульс не нужны.
                    ForegroundSyncPlugin.detach(app)
                    FlutterEngineCache.getInstance().remove(ENGINE_ID)
                }
            })
            // Каналы, которым не нужно окно, — сразу: движок, запущенный окном
            // виджета, работает без MainActivity. Активность при подключении
            // регистрирует их заново (configureFlutterEngine).
            val messenger = engine.dartExecutor.binaryMessenger
            runCatching { DeviceContactsPlugin.register(messenger, app) }
            runCatching { DeviceCalendarPlugin.register(messenger, app) }
            runCatching { ForegroundSyncPlugin.register(messenger, app) }
            runCatching { PhoneMirrorPlugin.register(messenger, app) }
            runCatching { WidgetBridge.register(messenger, app) }
            runCatching { FileOpenBridge.register(messenger, app) }
            runCatching { TimeZoneBridge.register(messenger) }
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ENGINE_ID, engine)
            return engine
        }
    }

    // Входящее «Поделиться» очищается ДО super: плагин receive_sharing_intent
    // читает намерение при подключении к активности и в onNewIntent.
    override fun onCreate(savedInstanceState: Bundle?) {
        ShareIntentSanitizer.sanitize(this, intent)
        // mailto и «Написать письмо» — до плагина «Поделиться».
        MailtoBridge.handle(intent)
        // Рисование под системными панелями на всех версиях Android так, как
        // требует Android 15 (рекомендация Google Play): прозрачные строка
        // состояния и панель навигации, отступы задаёт приложение.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (secureOn) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        // Нажатие на виджет «Мой день» (холодный запуск).
        WidgetBridge.handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        ShareIntentSanitizer.sanitize(this, intent)
        MailtoBridge.handle(intent)
        super.onNewIntent(intent)
        WidgetBridge.handle(intent)
    }

    /**
     * Движок из кэша; при первом запуске процесса — создаётся и запускается.
     * Плагины из pubspec регистрируются конструктором FlutterEngine.
     */
    override fun getCachedEngineId(): String {
        ensureEngine(applicationContext)
        return ENGINE_ID
    }

    /** Движок не уничтожается вместе с активностью (см. описание класса). */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Каналы переподключаются к каждой новой активности (setMethodCallHandler
        // заменяет прежний обработчик) — контекст берётся applicationContext.
        DeviceContactsPlugin.register(messenger, this)
        DeviceCalendarPlugin.register(messenger, this)
        ForegroundSyncPlugin.register(messenger, this)
        DeviceSecurityPlugin.register(messenger, this)
        // Контакты и календарь ящиков в телефоне (учётная запись «Ogneliss Mail»).
        PhoneMirrorPlugin.register(messenger, this)
        // Виджет «Мой день» на рабочем столе.
        WidgetBridge.register(messenger, this)
        // Открытие вложений — не зависит от подключения плагина к окну.
        FileOpenBridge.register(messenger, this)
        // PDF внутри приложения (1.8.14) — системным PdfRenderer.
        PdfRendererPlugin.register(messenger)
        TimeZoneBridge.register(messenger)
        // mailto и «Написать письмо» из других приложений.
        MailtoBridge.register(messenger)
        // Защищённые письма (ДСП, конфиденциально): запрет снимков и записи
        // экрана, показа на внешнем экране и миниатюры в недавних
        // приложениях — FLAG_SECURE окна, пока такое письмо открыто.
        io.flutter.plugin.common.MethodChannel(messenger, "ogneliss/secure_window").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val on = call.arguments as? Boolean ?: false
                    secureOn = on
                    runOnUiThread {
                        if (on) {
                            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Нажатие на уведомление при живом движке (10.10.2026). Движок
        // переживает активность, и нажатие в шторке создаёт НОВУЮ активность
        // с намерением SELECT_NOTIFICATION. Плагин уведомлений передаёт такое
        // намерение в Dart только через getNotificationAppLaunchDetails, а Dart
        // спрашивал его один раз — при запуске процесса. Поэтому приложение
        // открывалось, а письмо или встреча — нет. Теперь Dart спрашивает при
        // каждом возврате на экран, а разобранное намерение гасит здесь, чтобы
        // не открыть письмо повторно при следующем возврате.
        io.flutter.plugin.common.MethodChannel(messenger, "ogneliss/launch_intent").setMethodCallHandler { call, result ->
            when (call.method) {
                "consume" -> {
                    val i = intent
                    if (i != null && (i.action ?: "").startsWith("SELECT_")) {
                        i.action = Intent.ACTION_MAIN
                        setIntent(i)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // HTTP режима совместимости — плагин пакета ogneliss_native_http,
        // регистрируется Flutter сам (в том числе в фоновом движке).
    }

    // cleanUpFlutterEngine больше не останавливает фоновый сервис: активность
    // закрылась, но движок и Dart работают дальше. Остановка — по
    // onEngineWillDestroy (выше) или из Dart (режим «Мгновенно» выключен).
}
