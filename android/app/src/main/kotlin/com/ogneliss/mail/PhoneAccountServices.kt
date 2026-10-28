package com.ogneliss.mail

// Учётная запись «Ogneliss Mail» в системе Android (Настройки → Аккаунты).
// Нужна, чтобы контакты и календари ящиков лежали в телефоне ОТДЕЛЬНОЙ
// группой: не смешивались с личными контактами Google, отключались
// переключателем и удалялись целиком вместе с учётной записью.
//
// Данные в телефон пишет само приложение (PhoneMirrorPlugin) после
// синхронизации; системе синхронизация не поручается — адаптеры ниже
// пустые. Они объявлены, чтобы «Контакты» и «Календарь» телефона считали
// учётную запись своей (показывали её группы и календари).

import android.accounts.AbstractAccountAuthenticator
import android.accounts.Account
import android.accounts.AccountAuthenticatorResponse
import android.accounts.AccountManager
import android.app.Service
import android.content.AbstractThreadedSyncAdapter
import android.content.ContentProviderClient
import android.content.Context
import android.content.Intent
import android.content.SyncResult
import android.os.Bundle
import android.os.IBinder

const val OGNELISS_ACCOUNT_TYPE = "com.ogneliss.mail.account"

/** Аутентификатор-заглушка: учётные записи создаёт только приложение. */
class OgnelissAuthenticator(context: Context) : AbstractAccountAuthenticator(context) {
    override fun editProperties(r: AccountAuthenticatorResponse?, t: String?): Bundle? = null
    override fun addAccount(
        r: AccountAuthenticatorResponse?, t: String?, a: String?, f: Array<out String>?, o: Bundle?,
    ): Bundle? = null
    override fun confirmCredentials(r: AccountAuthenticatorResponse?, a: Account?, o: Bundle?): Bundle? = null
    override fun getAuthToken(r: AccountAuthenticatorResponse?, a: Account?, t: String?, o: Bundle?): Bundle? = null
    override fun getAuthTokenLabel(t: String?): String? = null
    override fun updateCredentials(r: AccountAuthenticatorResponse?, a: Account?, t: String?, o: Bundle?): Bundle? = null
    override fun hasFeatures(r: AccountAuthenticatorResponse?, a: Account?, f: Array<out String>?): Bundle =
        Bundle().apply { putBoolean(AccountManager.KEY_BOOLEAN_RESULT, false) }
}

class OgnelissAuthenticatorService : Service() {
    private lateinit var authenticator: OgnelissAuthenticator
    override fun onCreate() {
        super.onCreate()
        authenticator = OgnelissAuthenticator(this)
    }
    override fun onBind(intent: Intent?): IBinder? = authenticator.iBinder
}

/** Пустой адаптер синхронизации: данные пишет приложение само. */
class OgnelissNoopSyncAdapter(context: Context) : AbstractThreadedSyncAdapter(context, true) {
    override fun onPerformSync(
        account: Account?, extras: Bundle?, authority: String?,
        provider: ContentProviderClient?, syncResult: SyncResult?,
    ) {}
}

class OgnelissContactsSyncService : Service() {
    private val adapter by lazy { OgnelissNoopSyncAdapter(applicationContext) }
    override fun onBind(intent: Intent?): IBinder? = adapter.syncAdapterBinder
}

class OgnelissCalendarSyncService : Service() {
    private val adapter by lazy { OgnelissNoopSyncAdapter(applicationContext) }
    override fun onBind(intent: Intent?): IBinder? = adapter.syncAdapterBinder
}
