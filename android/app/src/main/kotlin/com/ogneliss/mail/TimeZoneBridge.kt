package com.ogneliss.mail

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Пояс устройства по имени (Asia/Yekaterinburg), 1.6.2. Dart знает только
 * смещение и сокращение («+05»): по одному смещению Exchange выбирал первый
 * пояс из списка — «Ашхабад, Ташкент» вместо «Екатеринбург» (13.10.2026).
 */
object TimeZoneBridge {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "ogneliss/time_zone").setMethodCallHandler { call, result ->
            if (call.method == "id") result.success(TimeZone.getDefault().id) else result.notImplemented()
        }
    }
}
