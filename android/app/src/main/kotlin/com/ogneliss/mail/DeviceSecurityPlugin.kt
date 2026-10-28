package com.ogneliss.mail

import android.app.Activity
import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Безопасность устройства для политик Exchange (канал "ogneliss/device_security").
 *
 *  status            → состояние блокировки экрана, шифрования, администратора
 *  requestScreenLock → системный экран установки блокировки нужной сложности
 *  requestAdmin      → системный экран включения администратора устройства
 *  setMaxTimeToLock  → тайм-аут блокировки экрана (только при включённом админе)
 *  openSecuritySettings → настройки безопасности (шифрование на Android 7–9)
 *  removeAdmin       → выключить администратора (удаление последнего аккаунта)
 *
 * Сложность блокировки (Android 10+, разрешение REQUEST_PASSWORD_COMPLEXITY):
 *  LOW    — графический ключ или PIN с повторами/последовательностями (1111, 1234)
 *  MEDIUM — PIN без повторов от 4 цифр, пароль от 4 символов
 *  HIGH   — PIN без повторов от 8 цифр, пароль от 6 символов
 * На Android 7–9 сложность недоступна — сообщаем только, есть ли блокировка.
 */
object DeviceSecurityPlugin {
    private const val CHANNEL = "ogneliss/device_security"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(activity, OgnelissDeviceAdminReceiver::class.java)

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status(activity, dpm, admin))
                    "requestScreenLock" -> {
                        val level = call.argument<String>("complexity") ?: "medium"
                        result.success(requestScreenLock(activity, level))
                    }
                    "requestAdmin" -> {
                        val text = call.argument<String>("explanation") ?: ""
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                            .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, text)
                        activity.startActivity(intent)
                        result.success(true)
                    }
                    "setMaxTimeToLock" -> {
                        val ms = (call.argument<Number>("ms") ?: 0).toLong()
                        if (dpm.isAdminActive(admin)) {
                            dpm.setMaximumTimeToLock(admin, ms)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "openSecuritySettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                        result.success(true)
                    }
                    "removeAdmin" -> {
                        if (dpm.isAdminActive(admin)) dpm.removeActiveAdmin(admin)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("SECURITY", e.message, null)
            } catch (e: Exception) {
                result.error("FAILED", e.message, null)
            }
        }
    }

    private fun status(activity: Activity, dpm: DevicePolicyManager, admin: ComponentName): Map<String, Any> {
        val keyguard = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        var complexity = "unknown"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            complexity = try {
                when (dpm.passwordComplexity) {
                    DevicePolicyManager.PASSWORD_COMPLEXITY_HIGH -> "high"
                    DevicePolicyManager.PASSWORD_COMPLEXITY_MEDIUM -> "medium"
                    DevicePolicyManager.PASSWORD_COMPLEXITY_LOW -> "low"
                    else -> "none"
                }
            } catch (e: Exception) {
                // IllegalStateException, пока пользователь не разблокировал устройство.
                "unknown"
            }
        }
        val encryption = when (dpm.storageEncryptionStatus) {
            DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE,
            DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER -> "active"
            DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_DEFAULT_KEY -> "default_key"
            DevicePolicyManager.ENCRYPTION_STATUS_ACTIVATING -> "activating"
            DevicePolicyManager.ENCRYPTION_STATUS_INACTIVE -> "inactive"
            else -> "unsupported"
        }
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "deviceSecure" to keyguard.isDeviceSecure,
            "complexity" to complexity,
            "encryption" to encryption,
            "adminActive" to dpm.isAdminActive(admin),
            "maxTimeToLockMs" to (if (dpm.isAdminActive(admin)) dpm.getMaximumTimeToLock(admin) else 0L),
        )
    }

    private fun requestScreenLock(activity: Activity, level: String): Boolean {
        val intent = Intent(DevicePolicyManager.ACTION_SET_NEW_PASSWORD)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val c = when (level) {
                "high" -> DevicePolicyManager.PASSWORD_COMPLEXITY_HIGH
                "low" -> DevicePolicyManager.PASSWORD_COMPLEXITY_LOW
                else -> DevicePolicyManager.PASSWORD_COMPLEXITY_MEDIUM
            }
            intent.putExtra(DevicePolicyManager.EXTRA_PASSWORD_COMPLEXITY, c)
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            // Некоторые прошивки не обрабатывают ACTION_SET_NEW_PASSWORD.
            activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
            false
        }
    }
}
