package com.ogneliss.nativehttp;

// HTTP-запросы через сетевой стек Android (HttpsURLConnection: OkHttp внутри
// системы, TLS — Conscrypt), а не через dart:io (BoringSSL Dart VM).
//
// Зачем: анти-бот шлюз перед корпоративным Exchange (например, ServicePipe)
// различает клиентов не только по User-Agent, но и по «отпечатку»
// TLS-рукопожатия. Почтовые приложения Android проходят, Dart-клиент получает
// 403 при любом User-Agent. Используется в режиме «Совместимость со шлюзом»
// (lib/core/network/native_android_http_client.dart).
//
// Оформлен плагином (FlutterPlugin), а не регистрацией в MainActivity:
// Flutter подключает плагины пакетов к каждому движку, включая фоновый движок
// WorkManager. Прежний Kotlin-объект регистрировался только в MainActivity,
// и в фоне каждый запрос заканчивался MissingPluginException.

import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import androidx.annotation.NonNull;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class NativeHttpPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "ogneliss/native_http";

    // Общие для всех движков процесса: запросы независимы, состояние не хранится.
    private static final ExecutorService POOL = Executors.newCachedThreadPool();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("deviceUserCas".equals(call.method)) {
            // ЦС, установленные пользователем/ИБ на устройство: Dart (BoringSSL)
            // системное хранилище не читает — отдаём их явно.
            POOL.execute(() -> {
                List<byte[]> list;
                try {
                    list = deviceUserCas();
                } catch (Exception e) {
                    list = Collections.emptyList();
                }
                final List<byte[]> out = list;
                MAIN.post(() -> result.success(out));
            });
            return;
        }
        if (!"send".equals(call.method)) {
            result.notImplemented();
            return;
        }
        final String method = orDefault(call.<String>argument("method"), "GET");
        final String url = orDefault(call.<String>argument("url"), "");
        final Map<String, String> headers = orDefault(call.<Map<String, String>>argument("headers"),
                Collections.<String, String>emptyMap());
        final byte[] body = call.argument("body");
        final Integer timeoutArg = call.argument("timeoutMs");
        final int timeoutMs = timeoutArg != null ? timeoutArg : 120_000;
        final List<String> trustedList = orDefault(call.<List<String>>argument("trustedSha256"),
                Collections.<String>emptyList());
        final Set<String> trusted = new HashSet<>(trustedList);
        final Boolean acceptAnyArg = call.argument("acceptAny");
        final boolean acceptAny = acceptAnyArg != null && acceptAnyArg;
        // Дополнительные ЦС приложения (встроенные Минцифры, импортированные).
        final List<byte[]> extraCas = orDefault(call.<List<byte[]>>argument("extraCas"),
                Collections.<byte[]>emptyList());

        POOL.execute(() -> {
            final X509Certificate[] rejected = new X509Certificate[1];
            try {
                final Map<String, Object> res =
                        send(method, url, headers, body, timeoutMs, trusted, acceptAny, extraCas, rejected);
                MAIN.post(() -> result.success(res));
            } catch (Exception e) {
                final String msg = e.getClass().getSimpleName() + ": " + e.getMessage();
                final X509Certificate cert = rejected[0];
                if (cert != null) {
                    // Сертификат не прошёл системную проверку и не принят
                    // пользователем — данные для диалога «Доверять?».
                    final Map<String, Object> info = new HashMap<>();
                    try {
                        info.put("der", cert.getEncoded());
                    } catch (Exception ignored) {
                        info.put("der", new byte[0]);
                    }
                    info.put("subject", cert.getSubjectX500Principal().getName());
                    info.put("issuer", cert.getIssuerX500Principal().getName());
                    info.put("notBefore", cert.getNotBefore().getTime());
                    info.put("notAfter", cert.getNotAfter().getTime());
                    MAIN.post(() -> result.error("CERT", msg, info));
                } else {
                    MAIN.post(() -> result.error("NET", msg, null));
                }
            }
        });
    }

    private static <T> T orDefault(T value, T fallback) {
        return value != null ? value : fallback;
    }

    private static Map<String, Object> send(
            String method, String url, Map<String, String> headers,
            byte[] body, int timeoutMs,
            Set<String> trusted, boolean acceptAny, List<byte[]> extraCas,
            X509Certificate[] rejected) throws Exception {
        final HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        if (conn instanceof HttpsURLConnection) {
            ((HttpsURLConnection) conn).setSSLSocketFactory(sslFactory(trusted, acceptAny, extraCas, rejected));
        }
        try {
            conn.setInstanceFollowRedirects(false);
            conn.setConnectTimeout(20_000);
            conn.setReadTimeout(timeoutMs);
            conn.setRequestMethod(method);
            conn.setUseCaches(false);
            for (Map.Entry<String, String> h : headers.entrySet()) {
                final String k = h.getKey();
                // Сжатие ответа система включает и снимает сама.
                if ("accept-encoding".equalsIgnoreCase(k)) continue;
                if ("content-length".equalsIgnoreCase(k)) continue;
                conn.setRequestProperty(k, h.getValue());
            }
            if (body != null && body.length > 0) {
                conn.setDoOutput(true);
                conn.setFixedLengthStreamingMode(body.length);
                try (OutputStream os = conn.getOutputStream()) {
                    os.write(body);
                }
            }
            final int status = conn.getResponseCode();
            InputStream stream;
            if (status >= 400) {
                stream = conn.getErrorStream();
            } else {
                try {
                    stream = conn.getInputStream();
                } catch (Exception e) {
                    stream = conn.getErrorStream();
                }
            }
            byte[] bytes = new byte[0];
            if (stream != null) {
                try (InputStream in = stream) {
                    bytes = readAll(in);
                }
            }
            final Map<String, String> outHeaders = new HashMap<>();
            for (Map.Entry<String, List<String>> e : conn.getHeaderFields().entrySet()) {
                final String k = e.getKey();
                final List<String> v = e.getValue();
                if (k == null || v == null) continue;
                // Content-Encoding снят системой вместе с распаковкой — не
                // передаём, иначе http-клиент Dart распакует ещё раз.
                if ("content-encoding".equalsIgnoreCase(k)) continue;
                if ("content-length".equalsIgnoreCase(k)) continue;
                outHeaders.put(k.toLowerCase(Locale.ROOT), String.join(", ", v));
            }
            final Map<String, Object> out = new HashMap<>();
            out.put("status", status);
            out.put("reason", conn.getResponseMessage());
            out.put("headers", outHeaders);
            out.put("body", bytes);
            return out;
        } finally {
            conn.disconnect();
        }
    }

    /**
     * Системная проверка сертификата, а при отказе — дополнительные ЦС
     * приложения, затем принятие по отпечатку (SHA-256 листового
     * сертификата, base64), который пользователь уже подтвердил, или любого
     * сертификата доверенного домена. Остальное отклоняется, сертификат
     * сохраняется для диалога.
     */
    private static SSLSocketFactory sslFactory(
            Set<String> trusted, boolean acceptAny, List<byte[]> extraCas,
            X509Certificate[] rejected) throws Exception {
        final TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init((KeyStore) null);
        X509TrustManager sys = null;
        for (TrustManager t : tmf.getTrustManagers()) {
            if (t instanceof X509TrustManager) {
                sys = (X509TrustManager) t;
                break;
            }
        }
        if (sys == null) throw new IllegalStateException("Нет системного X509TrustManager");
        final X509TrustManager system = sys;
        final X509TrustManager extra = extraTrustManager(extraCas);

        final X509TrustManager tm = new X509TrustManager() {
            @Override
            public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException {
                system.checkClientTrusted(chain, authType);
            }

            @Override
            public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {
                try {
                    system.checkServerTrusted(chain, authType);
                } catch (CertificateException e) {
                    if (extra != null) {
                        try {
                            extra.checkServerTrusted(chain, authType);
                            return;
                        } catch (CertificateException ignored) {
                            // проверяем дальше по отпечатку
                        }
                    }
                    if (chain == null || chain.length == 0) throw e;
                    final X509Certificate leaf = chain[0];
                    final String fp;
                    try {
                        fp = Base64.encodeToString(
                                MessageDigest.getInstance("SHA-256").digest(leaf.getEncoded()), Base64.NO_WRAP);
                    } catch (Exception digestError) {
                        throw e;
                    }
                    if (acceptAny || trusted.contains(fp)) return;
                    rejected[0] = leaf;
                    throw e;
                }
            }

            @Override
            public X509Certificate[] getAcceptedIssuers() {
                return system.getAcceptedIssuers();
            }
        };
        final SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(null, new TrustManager[]{tm}, null);
        return ctx.getSocketFactory();
    }

    /** Проверка цепочки только по дополнительным ЦС приложения. */
    private static X509TrustManager extraTrustManager(List<byte[]> cas) {
        if (cas.isEmpty()) return null;
        try {
            final CertificateFactory cf = CertificateFactory.getInstance("X.509");
            final KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
            ks.load(null, null);
            for (int i = 0; i < cas.size(); i++) {
                ks.setCertificateEntry("extra" + i, cf.generateCertificate(new ByteArrayInputStream(cas.get(i))));
            }
            final TrustManagerFactory f = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            f.init(ks);
            for (TrustManager t : f.getTrustManagers()) {
                if (t instanceof X509TrustManager) return (X509TrustManager) t;
            }
            return null;
        } catch (Exception e) {
            return null;
        }
    }

    /** Сертификаты ЦС, установленные пользователем (AndroidCAStore, «user:…»). */
    private static List<byte[]> deviceUserCas() throws Exception {
        final KeyStore ks = KeyStore.getInstance("AndroidCAStore");
        ks.load(null, null);
        final List<byte[]> out = new ArrayList<>();
        final Enumeration<String> aliases = ks.aliases();
        while (aliases.hasMoreElements()) {
            final String alias = aliases.nextElement();
            if (!alias.startsWith("user:")) continue;
            final java.security.cert.Certificate c = ks.getCertificate(alias);
            if (c == null) continue;
            out.add(c.getEncoded());
        }
        return out;
    }

    private static byte[] readAll(InputStream input) throws IOException {
        final ByteArrayOutputStream out = new ByteArrayOutputStream();
        final byte[] buf = new byte[16 * 1024];
        int n;
        while ((n = input.read(buf)) >= 0) {
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }
}
