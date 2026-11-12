package com.ogneliss.mail

import android.app.Application
import android.os.Build

/**
 * Приложение (08.11.2026). До первого движка Flutter — выбрать движок
 * рисования (GraphicsMode): после падения Impeller на этом телефоне — Skia.
 * Раньше здесь был android.app.Application по умолчанию
 * (`${applicationName}` из плагина Flutter для Gradle): своего кода не было.
 * 2.3.2 — ещё будильник фоновой проверки (SyncHeartbeat.ensureArmed).
 */
class OgnelissApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Процесс перезапуска (RestartActivity, «:restart») Flutter не нужен.
        if (processName().endsWith(RestartActivity.PROCESS_SUFFIX)) return
        GraphicsMode.applyAtStart(this)
        // Будильник фоновой проверки (2.3.2): после перезагрузки телефона,
        // обновления приложения или принудительной остановки его нет —
        // выставить при первом же запуске процесса (плановая задача, сигнал
        // сервера, виджет, открытие приложения). Не в главном потоке: читает
        // настройки с диска.
        val app = this
        Thread({ SyncHeartbeat.ensureArmed(app) }, "ogneliss-alarm").start()
    }

    private fun processName(): String = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Application.getProcessName() ?: ""
        } else {
            java.io.File("/proc/self/cmdline").readText().trimEnd('\u0000')
        }
    } catch (e: Exception) {
        ""
    }
}
