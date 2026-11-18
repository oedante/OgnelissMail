package com.ogneliss.nativehttp;

// Сертификат клиента TLS из системного хранилища Android — KeyChain (2.6.5,
// шаг 2 сертификатов клиента): установленный пользователем в «Настройки →
// Безопасность → Шифрование и учётные данные» или выданный устройству
// политикой организации (Android Enterprise, Intune «Сертификат PKCS» и т. п.).
//
// Закрытый ключ такого сертификата обычно хранится в Android Keystore
// (часто аппаратно) и наружу не выдаётся, поэтому TLS с ним делает сетевой
// стек системы: этот KeyManager отдаёт HttpsURLConnection псевдоним, цепочку
// и ключ из KeyChain. Доступ к псевдониму приложение получает, когда
// пользователь выбрал сертификат в системном окне (KeyChain.
// choosePrivateKeyAlias), или его открыла организация.

import android.content.Context;
import android.security.KeyChain;

import java.net.Socket;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;

import javax.net.ssl.SSLEngine;
import javax.net.ssl.X509ExtendedKeyManager;

final class KeyChainKeyManager extends X509ExtendedKeyManager {
    private final Context context;
    private final String alias;
    private volatile X509Certificate[] chain;
    private volatile PrivateKey key;

    KeyChainKeyManager(Context context, String alias) {
        this.context = context;
        this.alias = alias;
    }

    @Override
    public String chooseClientAlias(String[] keyTypes, Principal[] issuers, Socket socket) {
        return alias;
    }

    @Override
    public String chooseEngineClientAlias(String[] keyTypes, Principal[] issuers, SSLEngine engine) {
        return alias;
    }

    @Override
    public X509Certificate[] getCertificateChain(String a) {
        if (!alias.equals(a)) return null;
        X509Certificate[] c = chain;
        if (c == null) {
            try {
                c = KeyChain.getCertificateChain(context, alias);
            } catch (Exception e) {
                c = null; // доступа нет — без сертификата клиента
            }
            chain = c;
        }
        return c;
    }

    @Override
    public PrivateKey getPrivateKey(String a) {
        if (!alias.equals(a)) return null;
        PrivateKey k = key;
        if (k == null) {
            try {
                k = KeyChain.getPrivateKey(context, alias);
            } catch (Exception e) {
                k = null;
            }
            key = k;
        }
        return k;
    }

    // Сервером приложение не бывает.
    @Override
    public String[] getClientAliases(String keyType, Principal[] issuers) {
        return new String[]{alias};
    }

    @Override
    public String[] getServerAliases(String keyType, Principal[] issuers) {
        return null;
    }

    @Override
    public String chooseServerAlias(String keyType, Principal[] issuers, Socket socket) {
        return null;
    }
}
