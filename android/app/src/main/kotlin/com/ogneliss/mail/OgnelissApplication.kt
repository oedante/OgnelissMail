package com.ogneliss.mail

import android.app.Application
import android.os.Build

/**
 * Приложение (08.11.2026). Единственная задача — до первого движка Flutter
 * выбрать движок рисования (GraphicsMode): после падения Impeller на этом
 * телефоне — Skia. Раньше здесь был android.app.Application по умолчанию
 * (`${applicationName}` из плагина Flutter для Gradle): своего кода не было.
 */
class OgnelissApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Процесс перезапуска (RestartActivity, «:restart») Flutter не нужен.
        if (processName().endsWith(RestartActivity.PROCESS_SUFFIX)) return
        GraphicsMode.applyAtStart(this)
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
