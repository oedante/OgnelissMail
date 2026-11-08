package com.ogneliss.mail

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Process

/**
 * Перезапуск приложения (08.11.2026, «Настройки → Расширенные → Графика»).
 *
 * Обычное «закрыть и открыть» не перезапускает Flutter: движок живёт дольше
 * окна, а процесс держит служба почты (см. MainActivity). Движок рисования
 * выбирается только при старте процесса (GraphicsMode), поэтому нужен новый
 * процесс. Эта активность живёт в отдельном процессе «:restart»: главный
 * процесс запускает её и завершается, она дожидается его конца, открывает
 * приложение заново и завершается сама. Прозрачная, без следа в «Недавних».
 */
class RestartActivity : Activity() {
    companion object {
        const val PROCESS_SUFFIX = ":restart"
        private const val EXTRA_PID = "main_pid"

        fun restart(context: Context) {
            val i = Intent(context, RestartActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(EXTRA_PID, Process.myPid())
            context.startActivity(i)
            Runtime.getRuntime().exit(0)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pid = intent.getIntExtra(EXTRA_PID, -1)
        if (pid > 0 && pid != Process.myPid()) Process.killProcess(pid)
        GraphicsMode.relaunchIntent(this)?.let {
            startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        }
        finish()
        Runtime.getRuntime().exit(0)
    }
}
