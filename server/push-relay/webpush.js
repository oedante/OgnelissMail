'use strict';
// ============================================================================
// Web Push для сигналов UnifiedPush (Ogneliss Mail 1.10.x, Android без
// сервисов Google; просьба владельца 01.11.2026).
//
// Приложение регистрирует у сервера адрес (endpoint), который выдал
// распространитель UnifiedPush на телефоне (ntfy, NextPush, Sunup…), и ключи
// шифрования этой установки. Сигнал «проверь почту» отправляется POST-запросом
// на этот адрес, зашифрованным по Web Push:
//   · RFC 8291 (Message Encryption for Web Push) + RFC 8188 (aes128gcm);
//   · RFC 8292 (VAPID) — подпись сервера, если задан ключ VAPID: часть
//     распространителей без неё регистрацию не принимает.
// Содержимое сигнала — {"w":"1"}, как у FCM; расшифровывает его библиотека
// UnifiedPush в приложении.
//
// Адрес присылает приложение — сервер не должен ходить по нему во
// внутреннюю сеть (SSRF): только https, порт 443, имя узла, которое
// указывает на публичные адреса (checkEndpoint).
//
// Зависимостей нет: crypto, dns и fetch из Node.js 18+.
// ============================================================================

const crypto = require('crypto');
const dns = require('dns').promises;
const net = require('net');

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function unb64url(s) {
  return Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function hmac(key, data) {
  return crypto.createHmac('sha256', key).update(data).digest();
}

/**
 * Зашифровать [payload] для получателя с ключом [uaPublic] (65 байт, P-256
 * без сжатия, base64url) и секретом [authSecret] (16 байт, base64url).
 * [opts.salt] и [opts.asPrivate] — только для проверки по примеру RFC 8291.
 * Возвращает тело запроса (заголовок aes128gcm + шифротекст).
 */
function encrypt(payload, uaPublic, authSecret, opts = {}) {
  const ua = unb64url(uaPublic);
  const auth = unb64url(authSecret);
  if (ua.length !== 65 || ua[0] !== 4) throw new Error('bad p256dh');
  if (auth.length !== 16) throw new Error('bad auth');
  const ecdh = crypto.createECDH('prime256v1');
  if (opts.asPrivate) ecdh.setPrivateKey(unb64url(opts.asPrivate));
  else ecdh.generateKeys();
  const asPublic = ecdh.getPublicKey();
  const secret = ecdh.computeSecret(ua);
  const salt = opts.salt ? unb64url(opts.salt) : crypto.randomBytes(16);

  // RFC 8291, раздел 3.4: IKM из общего секрета и auth.
  const prkKey = hmac(auth, secret);
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), ua, asPublic]);
  const ikm = hmac(prkKey, Buffer.concat([keyInfo, Buffer.from([1])]));
  // RFC 8188: ключ и nonce записи.
  const prk = hmac(salt, ikm);
  const cek = hmac(prk, Buffer.from('Content-Encoding: aes128gcm\0\x01')).subarray(0, 16);
  const nonce = hmac(prk, Buffer.from('Content-Encoding: nonce\0\x01')).subarray(0, 12);

  // Одна запись: текст + разделитель последней записи 0x02.
  const plain = Buffer.concat([Buffer.from(payload), Buffer.from([2])]);
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const body = Buffer.concat([cipher.update(plain), cipher.final(), cipher.getAuthTag()]);

  const rs = 4096;
  const header = Buffer.alloc(16 + 4 + 1);
  salt.copy(header, 0);
  header.writeUInt32BE(rs, 16);
  header.writeUInt8(asPublic.length, 20);
  return Buffer.concat([header, asPublic, body]);
}

/** Расшифровать (для тестов): приватный ключ получателя — base64url d. */
function decrypt(message, uaPrivate, uaPublic, authSecret) {
  const buf = Buffer.from(message);
  const salt = buf.subarray(0, 16);
  const idlen = buf.readUInt8(20);
  const asPublic = buf.subarray(21, 21 + idlen);
  const data = buf.subarray(21 + idlen);
  const ecdh = crypto.createECDH('prime256v1');
  ecdh.setPrivateKey(unb64url(uaPrivate));
  const ua = unb64url(uaPublic);
  const secret = ecdh.computeSecret(asPublic);
  const prkKey = hmac(unb64url(authSecret), secret);
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), ua, asPublic]);
  const ikm = hmac(prkKey, Buffer.concat([keyInfo, Buffer.from([1])]));
  const prk = hmac(salt, ikm);
  const cek = hmac(prk, Buffer.from('Content-Encoding: aes128gcm\0\x01')).subarray(0, 16);
  const nonce = hmac(prk, Buffer.from('Content-Encoding: nonce\0\x01')).subarray(0, 12);
  const tag = data.subarray(data.length - 16);
  const d = crypto.createDecipheriv('aes-128-gcm', cek, nonce);
  d.setAuthTag(tag);
  const plain = Buffer.concat([d.update(data.subarray(0, data.length - 16)), d.final()]);
  let end = plain.length - 1;
  while (end >= 0 && plain[end] === 0) end--; // заполнитель
  if (plain[end] !== 2) throw new Error('bad delimiter');
  return plain.subarray(0, end);
}

// ── VAPID (RFC 8292) ──

/** Ключ VAPID из PEM (EC P-256): {key, publicKey: base64url 65 байт}. */
function loadVapid(pem) {
  const key = crypto.createPrivateKey(pem);
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('VAPID: нужен ключ EC P-256');
  }
  const jwk = crypto.createPublicKey(key).export({ format: 'jwk' });
  const pub = Buffer.concat([Buffer.from([4]), unb64url(jwk.x), unb64url(jwk.y)]);
  return { key, publicKey: b64url(pub) };
}

/** Новый ключ VAPID в PEM (для install-push-relay.sh). */
function generateVapidPem() {
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  return privateKey.export({ type: 'pkcs8', format: 'pem' });
}

/** Заголовок Authorization для адреса [endpoint]. */
function vapidAuthorization(endpoint, vapid, subject, now = Date.now()) {
  const aud = new URL(endpoint).origin;
  const header = b64url(JSON.stringify({ typ: 'JWT', alg: 'ES256' }));
  const claims = b64url(JSON.stringify({ aud, exp: Math.floor(now / 1000) + 12 * 3600, sub: subject }));
  const data = `${header}.${claims}`;
  const sig = crypto.sign('sha256', Buffer.from(data), { key: vapid.key, dsaEncoding: 'ieee-p1363' });
  return `vapid t=${data}.${b64url(sig)}, k=${vapid.publicKey}`;
}

// ── Проверка адреса (SSRF) ──

function privateIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
  }
  const v = ip.toLowerCase();
  if (v.startsWith('::ffff:')) return privateIp(v.slice(7));
  return v === '::1' || v === '::' || v.startsWith('fc') || v.startsWith('fd') || v.startsWith('fe80') ||
    v.startsWith('ff');
}

/** Формат адреса без сети: null — годится, иначе причина. */
function endpointShape(raw) {
  if (typeof raw !== 'string' || raw.length < 12 || raw.length > 1024) return 'length';
  let u;
  try {
    u = new URL(raw);
  } catch (_) {
    return 'url';
  }
  if (u.protocol !== 'https:') return 'https';
  if (u.port && u.port !== '443') return 'port';
  if (u.username || u.password) return 'userinfo';
  const host = u.hostname;
  if (!host || net.isIP(host.replace(/^\[|\]$/g, '')) || host === 'localhost' || host.endsWith('.local') ||
      host.endsWith('.internal') || !host.includes('.')) {
    return 'host';
  }
  return null;
}

/** Только для автотестов службы (test/unifiedpush.test.js): заглушка на 127.0.0.1. */
function testLocal(raw) {
  if (process.env.UP_ALLOW_LOCAL_FOR_TESTS !== '1') return false;
  try {
    return new URL(raw).hostname === '127.0.0.1';
  } catch (_) {
    return false;
  }
}

/** Полная проверка: формат и публичные адреса узла (DNS). */
async function checkEndpoint(raw, resolve = (h) => dns.lookup(h, { all: true })) {
  if (testLocal(raw)) return null;
  const shape = endpointShape(raw);
  if (shape) return shape;
  try {
    const addrs = await resolve(new URL(raw).hostname);
    if (!addrs.length || addrs.some((a) => privateIp(a.address))) return 'private';
  } catch (_) {
    return 'dns';
  }
  return null;
}

/**
 * Отправить сигнал. {status, reason}: 200/201 — принят; 404/410 — адрес
 * больше не действует (удалить регистрацию).
 */
async function send(rec, endpoint, { vapid, subject, urgency = 'normal', ttl = 3600, fetchImpl = fetch } = {}) {
  // Перед каждым запросом — снова DNS: имя могли перенаправить внутрь.
  const bad = await checkEndpoint(endpoint);
  if (bad) return { status: 0, reason: `endpoint_${bad}` };
  const body = encrypt('{"w":"1"}', rec.k, rec.a);
  const headers = {
    'content-type': 'application/octet-stream',
    'content-encoding': 'aes128gcm',
    ttl: String(ttl),
    urgency,
  };
  if (vapid) headers.authorization = vapidAuthorization(endpoint, vapid, subject);
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 15000);
  try {
    const r = await fetchImpl(endpoint, { method: 'POST', headers, body, redirect: 'manual', signal: ctl.signal });
    const status = r.status >= 200 && r.status < 300 ? 200 : r.status;
    return { status, reason: status === 200 ? '' : `HTTP ${r.status}` };
  } catch (e) {
    return { status: 0, reason: e.name === 'AbortError' ? 'timeout' : 'network' };
  } finally {
    clearTimeout(timer);
  }
}

function gone(r) {
  return r.status === 404 || r.status === 410;
}

module.exports = {
  b64url, unb64url, encrypt, decrypt, loadVapid, generateVapidPem, vapidAuthorization,
  privateIp, endpointShape, checkEndpoint, send, gone,
};
