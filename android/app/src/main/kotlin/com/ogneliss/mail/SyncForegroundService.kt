package com.ogneliss.mail

// Foreground Service: держит процесс приложения живым, когда оно свёрнуто, чтобы
// продолжали работать УЖЕ существующие Dart-таймеры (BackgroundService.
// _foregroundSyncTimer → syncAll) и IMAP IDLE — в ГЛАВНОМ изоляте, без bootstrap
// отдельного изолята и без мультиизолятной работы с БД.
//
// Почему так: когда Activity уходит в фон, Flutter-движок НЕ уничтожается и Dart
// (таймеры/async) продолжает исполняться — останавливает его лишь убийство
// процесса системой. Foreground service помечает процесс как «делает видимую
// пользователю работу», и система его не убивает и меньше троттлит (Doze).
//
// Смахнули из недавних (onTaskRemoved): движок Flutter хранится в
// FlutterEngineCache и переживает активность, поэтому сервис продолжает
// работать (07.10.2026). Процесс убит системой — сервис не пересоздаётся.
//
// Почему уведомление «висело постоянно» (исправлено 05.10.2026):
//  · START_STICKY: после убийства процесса система пересоздавала сервис БЕЗ
//    Flutter-движка — синхронизации уже не было, а уведомление оставалось;
//  · onTaskRemoved не обрабатывался — после закрытия приложения из недавних
//    сервис жил дальше.
// Теперь сервис живёт строго вместе с приложением. Скрыть уведомление можно
// кнопкой в нём (системные настройки канала) — синхронизация при этом идёт.
//
// Короткая проверка по будильнику (2.3.2, требование владельца 11.11.2026:
// «проверки должны срабатывать вовремя во всех режимах»). У ящиков «раз в
// 15 минут / 30 / час» постоянной службы нет, и в глубоком сне (Doze)
// Android закрывает приложению сеть и откладывает задачи WorkManager на
// часы. Будильник (SyncHeartbeat) к сроку проверки запускает эту же службу
// на время одной проверки: у процесса со службой переднего плана сеть и
// процессор есть и в глубоком сне. Проверку выполняет задача WorkManager
// (тот же обработчик Dart, что у плановой), служба ждёт её конца и
// останавливается. Уведомление — то же, тихое; на Android 12+ система не
// показывает его первые 10 секунд, и короткая проверка его не успевает
// показать.

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache

class SyncForegroundService : Service() {

    companion object {
        // Новый id: важность канала после создания не меняется, а прежний
        // (ogneliss_bg_sync) был IMPORTANCE_LOW — со значком в строке состояния.
        const val CHANNEL_ID = "ogneliss_bg_sync_v2"
        private const val OLD_CHANNEL_ID = "ogneliss_bg_sync"
        private const val NOTIF_ID = 4711

        /** Сервис работает (для пульса: без сервиса будильник не нужен). */
        @Volatile
        var running = false
            private set

        /** Запуск из приложения (кнопка «Работать в фоне», открытое окно). */
        const val EXTRA_FROM_APP = "com.ogneliss.mail.FGS_FROM_APP"

        /** Запуск будильником: одна проверка почты — и остановка (2.3.2). */
        const val EXTRA_CHECK = "com.ogneliss.mail.FGS_CHECK"

        /**
         * Короткая проверка по будильнику. Бросает исключение, если система
         * не разрешила запуск службы из фона (Android 12+ без точного
         * будильника) — тогда проверку ставит срочная задача (SyncHeartbeat).
         */
        fun startCheck(context: Context) {
            val intent = Intent(context, SyncForegroundService::class.java)
                .putExtra(EXTRA_CHECK, true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun start(context: Context) {
            val intent = Intent(context, SyncForegroundService::class.java)
                .putExtra(EXTRA_FROM_APP, true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SyncForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // Лимит времени службы. До 2.0.0 тип был dataSync: на Android 15+ — не
    // больше 6 часов в сутки, по истечении система вызывает onTimeout, и
    // служба обязана остановиться за несколько секунд (иначе приложение
    // аварийно завершится). У specialUse (с 2.0.0) лимита нет; обработчик
    // оставлен на случай, если тип придётся вернуть (отказ Google Play).
    // Пульс после этого НЕ снимается — он продолжает будить проверку почты
    // срочной задачей WorkManager (SyncHeartbeatReceiver, режим без службы);
    // раньше служба и пульс останавливались до следующего открытия
    // приложения, а плановую задачу Android в глубоком сне откладывает.
    override fun onTimeout(startId: Int, fgsType: Int) {
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        endCheck()
        // Постоянная служба остановлена (приложением, системой, смахиванием):
        // будильник не снимается, а переходит в режим «без службы» — если
        // фоновые проверки включены (2.3.2; раньше явная остановка снимала
        // его, и почту в глубоком сне никто не проверял).
        if (permanent) SyncHeartbeat.applyStandby(applicationContext)
        permanent = false
        super.onDestroy()
    }

    /** Служба запускалась приложением как постоянная (не только проверка). */
    private var permanent = false

    /** Идёт короткая проверка по будильнику. */
    private var checking = false
    private var checkLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val checkTimeout = Runnable { finishCheck() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 15+ (замечание Google Play 14.10.2026): службу типа dataSync
        // нельзя запускать из BOOT_COMPLETED. Служба стартует только по
        // явному запуску из приложения ([start]) или будильником проверки
        // ([startCheck]); любой другой запуск (перезапуск системой, после
        // загрузки) — сразу остановка, без startForeground. Почту в этом
        // случае проверяет WorkManager.
        val fromApp = intent?.getBooleanExtra(EXTRA_FROM_APP, false) == true
        val check = intent?.getBooleanExtra(EXTRA_CHECK, false) == true
        if (!fromApp && !check) {
            if (!running && !checking) stopSelf(startId)
            return START_NOT_STICKY
        }
        createChannel()
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                // 2.0.0: specialUse вместо dataSync — без лимита 6 часов в
                // сутки (Android 15+); декларация — в Play Console.
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            // Android 12+: из фона (в т.ч. при перезапуске START_STICKY) запуск
            // foreground-сервиса запрещён, а у dataSync исчерпан суточный лимит
            // (Android 15+). Не падаем — синхронизацию продолжит WorkManager:
            // для проверки по будильнику — срочной задачей.
            if (check) SyncHeartbeat.enqueueCheck(applicationContext, inService = false)
            if (fromApp) running = false
            if (!running && !checking) stopSelf()
            return START_NOT_STICKY
        }
        if (fromApp) {
            // Пульс: будит процесс и в глубоком сне (см. SyncHeartbeat).
            // Повторный старт сервиса просто переставляет будильник.
            running = true
            permanent = true
            SyncHeartbeat.schedule(applicationContext)
        } else if (!running) {
            beginCheck()
        }
        // Не пересоздавать после убийства процесса: без Flutter-движка сервис
        // ничего не синхронизирует, а уведомление висело бы впустую.
        return START_NOT_STICKY
    }

    /** Короткая проверка: задача WorkManager под защитой службы. */
    private fun beginCheck() {
        if (checking) return
        checking = true
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            checkLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ogneliss:alarm-check").apply {
                setReferenceCounted(false)
                acquire(SyncHeartbeat.MAX_CHECK_MS)
            }
        } catch (e: Exception) {
        }
        handler.postDelayed(checkTimeout, SyncHeartbeat.MAX_CHECK_MS)
        SyncHeartbeat.runCheckInService(applicationContext) { handler.post { finishCheck() } }
    }

    /** Проверка закончилась (или вышло время): остановить службу, если она не постоянная. */
    private fun finishCheck() {
        if (!checking) return
        endCheck()
        if (!running) {
            // Следующий будильник — по сроку, который записала проверка.
            SyncHeartbeat.afterCheck(applicationContext)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun endCheck() {
        checking = false
        handler.removeCallbacks(checkTimeout)
        try {
            checkLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
        }
        checkLock = null
    }

    // Приложение смахнули из недавних. С 07.10.2026 движок Flutter живёт
    // дольше активности (MainActivity, FlutterEngineCache): Dart продолжает
    // синхронизировать и держать push — сервис остаётся. Останавливаемся,
    // только если движка нет (тогда синхронизации действительно не будет).
    override fun onTaskRemoved(rootIntent: Intent?) {
        // Идёт короткая проверка — дать ей закончиться (движок ей не нужен:
        // у задачи WorkManager свой).
        if (!checking && !FlutterEngineCache.getInstance().contains(MainActivity.ENGINE_ID)) {
            running = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        // Нажатие — открыть приложение.
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, flags)
        }
        val b = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.bg_sync_title))
            .setContentText(getString(R.string.bg_sync_text))
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setOngoing(true)
            .setShowWhen(false)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_DEFERRED)
        if (open != null) b.setContentIntent(open)
        // «Скрыть»: настройки этого канала — пользователь выключает показ, а
        // синхронизация продолжается (Android 8+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val hide = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL_ID)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            b.addAction(0, getString(R.string.bg_sync_hide), PendingIntent.getActivity(this, 1, hide, flags))
        }
        return b.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // IMPORTANCE_MIN: без значка в строке состояния — только строка в
            // свёрнутом виде внизу шторки.
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.bg_sync_channel),
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = getString(R.string.bg_sync_channel_desc)
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.deleteNotificationChannel(OLD_CHANNEL_ID)
            nm.createNotificationChannel(channel)
        }
    }
}
