package com.ogneliss.mail

import android.app.admin.DeviceAdminReceiver

/**
 * Администратор устройства Ogneliss Mail — только «Блокировка экрана»
 * (res/xml/device_admin.xml: force-lock).
 *
 * Нужен для одного требования политики Exchange — MaxInactivityTimeDeviceLock
 * (тайм-аут блокировки экрана). Остальное администратору недоступно:
 * требования к паролю у приложений с targetSdk 29+ бросают SecurityException
 * (Google закрыл их в Android 10), а стирание всего телефона обычным
 * администратором при targetSdk 34+ запрещено (IllegalStateException).
 * Требование PIN проверяется без прав администратора — через сложность
 * блокировки экрана (DeviceSecurityPlugin).
 *
 * Включается пользователем вручную (системный экран), выключается в
 * Настройки → Безопасность → Приложения администратора устройства.
 */
class OgnelissDeviceAdminReceiver : DeviceAdminReceiver()
