package com.ogneliss.mail.baselineprofile

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Снимает профиль запуска Ogneliss Mail: холодный старт до первого кадра и
 * прокрутка ленты. Интерфейс Flutter не виден UiAutomator по id, поэтому
 * сценарий — жестами по экрану. Перед запуском войдите в приложение на
 * телефоне хотя бы в один ящик: тогда профиль покрывает ленту писем, а не
 * только экран входа.
 */
@RunWith(AndroidJUnit4::class)
@LargeTest
class BaselineProfileGenerator {

    @get:Rule
    val rule = BaselineProfileRule()

    @Test
    fun startup() = rule.collect(
        packageName = "com.ogneliss.mail",
        includeInStartupProfile = true,
    ) {
        pressHome()
        startActivityAndWait()
        device.waitForIdle()

        // Прокрутка ленты вниз и обратно.
        val w = device.displayWidth
        val h = device.displayHeight
        repeat(3) {
            device.swipe(w / 2, h * 3 / 4, w / 2, h / 4, 20)
            device.waitForIdle()
        }
        repeat(3) {
            device.swipe(w / 2, h / 4, w / 2, h * 3 / 4, 20)
            device.waitForIdle()
        }
    }
}
