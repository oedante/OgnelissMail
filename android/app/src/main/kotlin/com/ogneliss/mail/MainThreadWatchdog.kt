package com.ogneliss.mail

// Сторож главного потока Android (2.7.2, микрофризы 24.11.2026: «Новое
// сообщение» открылось, но ~1,5 с не реагировало на нажатия).
//
// Касания, встроенные окна (браузер письма и редактора), плагины и вывод
// кадров на экран идут через главный поток системы. Если он занят, приложение
// не отвечает, хотя код Flutter свободен, — и журнал этого не видел. Здесь
// фоновый поток раз в 250 мс ставит в очередь главного потока пустую задачу
// и замечает, насколько она опоздала; опоздание от 300 мс запоминается, а
// Dart (JankMonitor) забирает список раз в несколько секунд и пишет в журнал
// «Android: главный поток занят N мс».
//
// Работает только пока окно приложения на экране (onResume — onPause).

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

object MainThreadWatchdog {
    private const val PERIOD_MS = 250L
    private const val STALL_MS = 300L
    private const val KEEP = 20

    private val main = Handler(Looper.getMainLooper())
    private val stalls = ArrayList<LongArray>() // [время (мс с 1970), длительность мс]

    @Volatile private var running = false
    // Поколение: старый поток после stop() + start() не продолжает работу
    // рядом с новым.
    @Volatile private var generation = 0
    private var thread: Thread? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "ogneliss/main_thread").setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> {
                    val out = synchronized(stalls) {
                        val list = stalls.map { listOf(it[0], it[1]) }
                        stalls.clear()
                        list
                    }
                    result.success(out)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun start() {
        if (running) return
        running = true
        val mine = ++generation
        thread = Thread({
            while (running && generation == mine) {
                val posted = SystemClock.uptimeMillis()
                val ranAt = AtomicLong(0L)
                val done = CountDownLatch(1)
                main.post {
                    ranAt.set(SystemClock.uptimeMillis())
                    done.countDown()
                }
                try {
                    Thread.sleep(PERIOD_MS)
                    // Главный поток ещё занят — ждём, пока задача выполнится
                    // (или сторожа остановят).
                    while (running && generation == mine && !done.await(PERIOD_MS, TimeUnit.MILLISECONDS)) {
                        // ждём дальше
                    }
                } catch (e: InterruptedException) {
                    break
                }
                val ran = ranAt.get()
                val late = ran - posted
                if (ran != 0L && late >= STALL_MS) {
                    synchronized(stalls) {
                        stalls.add(longArrayOf(System.currentTimeMillis() - (SystemClock.uptimeMillis() - posted), late))
                        while (stalls.size > KEEP) stalls.removeAt(0)
                    }
                }
            }
        }, "ogneliss-main-watchdog").apply {
            isDaemon = true
            priority = Thread.MIN_PRIORITY
            start()
        }
    }

    fun stop() {
        running = false
        generation++
        thread?.interrupt()
        thread = null
    }
}
