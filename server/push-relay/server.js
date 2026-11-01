'use strict';
// ============================================================================
// Ogneliss Push Relay — «будильник» для iPhone (Ogneliss Mail 1.7.2) и
// Android (1.9.x)
//
// Раз в выбранный интервал (15, 30 или 60 минут) отправляет пустой сигнал
// «проверь почту»: на iPhone — через Apple Push Notification service (APNs),
// на Android — через Firebase Cloud Messaging (FCM, API HTTP v1). Получив
// его, приложение само, с телефона, проверяет почтовые ящики. Зачем — в
// docs/plan/IOS_BACKGROUND_DELIVERY.md и docs/guides/ANDROID_PUSH_SETUP.md,
// установка — README.md рядом.
//
// Что хранится (файл DATA_FILE): токен уведомлений APNs или FCM (случайный,
// свой у каждой установки приложения), окружение (production / sandbox /
// fcm), интервал, вид сигнала, время последнего сигнала и регистрации.
// Ни адресов, ни учётных данных, ни писем; к почтовым серверам служба не
// обращается. Журнал запросов с IP-адресами не ведётся (в nginx для /push —
// access_log off), в журнал службы пишутся только счётчики.
//
// Эндпоинты (под BASE_PATH, по умолчанию /push):
//   GET  /healthz      — {ok, ready, fcm}; изнутри контейнера — ещё число
//                        токенов, готовность ключей и счётчики (без токенов)
//   POST /register     — {token, env, interval, mode[, platform]} → 204
//   POST /unregister   — {token[, platform]} → 204
//   POST /probe        — только изнутри контейнера: принимают ли Apple и
//                        Google ключи
//
// platform 'android' — токен FCM (регистр букв сохраняется, окружение fcm);
// без него — токен APNs, как в 1.7.2.
//
// Виды сигнала iPhone:
//   silent — content-available, приоритет 5 (этап 1, без права Apple на
//            фильтрацию уведомлений): iOS пропускает 2–3 в час, поэтому не
//            чаще раза в MIN_SILENT_MINUTES (по умолчанию 20) минут;
//   alert  — видимый push с mutable-content для расширения уведомлений
//            (этап 2, после одобрения права фильтрации).
// Виды сигнала Android (сообщение только с данными {w: '1'}, без
// уведомления):
//   normal — обычный приоритет FCM (по умолчанию): в глубоком сне (Doze)
//            Android доставит сигнал в ближайшее окно обслуживания;
//   high   — высокий приоритет: будит сразу. Google понижает приоритет
//            приложениям, чьи срочные сообщения не ведут к видимому
//            уведомлению, а сигнал «проверь почту» чаще всего пустой, —
//            поэтому high только по выбору сборки (PUSH_WAKE_ANDROID_PRIORITY).
//
// Node.js >= 18. Зависимостей нет: http, http2, crypto и fetch из Node.
// ============================================================================

const http = require('http');
const http2 = require('http2');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// ── Настройки из окружения ──
const PORT = parseInt(process.env.PORT || '8788', 10);
const HOST = process.env.HOST || '127.0.0.1';
const BASE_PATH = (process.env.BASE_PATH || '/push').replace(/\/+$/, '');
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, 'data', 'tokens.json');
const API_KEY = process.env.PUSH_API_KEY || '';
const TEAM_ID = process.env.APNS_TEAM_ID || '';
const TOPIC = process.env.APNS_TOPIC || 'com.ogneliss.mail';
const KEYS = {
  production: {
    id: process.env.APNS_KEY_ID || '',
    file: process.env.APNS_KEY_FILE || '',
  },
  // Ключ Sandbox — для сборок из Xcode. Не задан — тот же, что Production
  // (подходит ключ «для обоих окружений»).
  sandbox: {
    id: process.env.APNS_SANDBOX_KEY_ID || process.env.APNS_KEY_ID || '',
    file: process.env.APNS_SANDBOX_KEY_FILE || process.env.APNS_KEY_FILE || '',
  },
};
const APNS_HOSTS = {
  production: process.env.APNS_URL_PRODUCTION || 'https://api.push.apple.com',
  sandbox: process.env.APNS_URL_SANDBOX || 'https://api.sandbox.push.apple.com',
};
const MIN_SILENT_MINUTES = Math.max(20, parseInt(process.env.MIN_SILENT_MINUTES || '20', 10));
const EXPIRE_DAYS = Math.max(7, parseInt(process.env.EXPIRE_DAYS || '30', 10));
const MAX_TOKENS = Math.max(100, parseInt(process.env.MAX_TOKENS || '200000', 10));
const TICK_MS = Math.max(1000, parseInt(process.env.TICK_MS || '30000', 10));
const PARALLEL = 20;
const INTERVALS = [15, 30, 60];

// FCM (Android, 1.9.x): ключ сервисного аккаунта Firebase (JSON из консоли
// Firebase). Проект — из ключа; FCM_PROJECT_ID — если ключ от другого
// проекта с правом отправки. FCM_URL — только для автотестов.
const FCM_SA_FILE = process.env.FCM_SERVICE_ACCOUNT_FILE || '';
const FCM_PROJECT = process.env.FCM_PROJECT_ID || '';
const FCM_URL = (process.env.FCM_URL || 'https://fcm.googleapis.com').replace(/\/+$/, '');
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
// Токен FCM: буквы, цифры, «:», «_», «-» (обычно около 160 символов).
const FCM_TOKEN_RE = /^[A-Za-z0-9_:-]{32,512}$/;

function log(msg) {
  // Только служебные сообщения и счётчики — без токенов и IP.
  process.stdout.write(`${new Date().toISOString()} push-relay: ${msg}\n`);
}

// ── Хранилище токенов ──
// token → { e: env, i: interval, m: mode, l: last sent ms, r: registered ms }
// Окружение fcm — токен Android, production / sandbox — токен iPhone.
let tokens = new Map();

function load() {
  try {
    const raw = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    const t = raw && raw.tokens ? raw.tokens : {};
    tokens = new Map(Object.entries(t));
    log(`загружено токенов: ${tokens.size}`);
  } catch (e) {
    if (e.code !== 'ENOENT') log(`не удалось прочитать ${DATA_FILE}: ${e.message}`);
    tokens = new Map();
  }
}

let saveTimer = null;
function saveSoon() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    saveNow();
  }, 5000);
}

function saveNow() {
  try {
    fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
    const tmp = `${DATA_FILE}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ v: 1, tokens: Object.fromEntries(tokens) }), { mode: 0o600 });
    fs.renameSync(tmp, DATA_FILE);
  } catch (e) {
    log(`не удалось сохранить токены: ${e.message}`);
  }
}

// ── JWT для APNs (ES256, обновление раз в 40 минут) ──
const jwtCache = {};

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function keyReady(env) {
  const k = KEYS[env];
  return Boolean(TEAM_ID && k.id && k.file && fs.existsSync(k.file));
}

function jwt(env) {
  const now = Math.floor(Date.now() / 1000);
  const c = jwtCache[env];
  if (c && now - c.iat < 40 * 60) return c.token;
  const k = KEYS[env];
  const pem = fs.readFileSync(k.file, 'utf8');
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: k.id }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat: now }));
  const data = `${head}.${claims}`;
  const sig = crypto.sign('sha256', Buffer.from(data), { key: pem, dsaEncoding: 'ieee-p1363' });
  const token = `${data}.${b64url(sig)}`;
  jwtCache[env] = { token, iat: now };
  return token;
}

// ── Соединения HTTP/2 с APNs (по одному на окружение) ──
const sessions = {};

function session(env) {
  const old = sessions[env];
  if (old && !old.closed && !old.destroyed) return old;
  const s = http2.connect(APNS_HOSTS[env]);
  s.on('error', (e) => log(`APNs ${env}: ${e.message}`));
  s.on('goaway', () => {
    try { s.close(); } catch (_) { /* уже закрыто */ }
  });
  s.on('close', () => {
    if (sessions[env] === s) delete sessions[env];
  });
  // Без сигналов 10 минут — закрыть, при следующем откроется заново.
  s.setTimeout(10 * 60 * 1000, () => s.close());
  sessions[env] = s;
  return s;
}

function effectiveMinutes(rec) {
  return rec.m === 'silent' ? Math.max(rec.i, MIN_SILENT_MINUTES) : rec.i;
}

function payload(rec) {
  if (rec.m === 'alert') {
    // Этап 2: видимый push для расширения уведомлений. Если расширение не
    // успело ответить, iOS покажет этот текст тихо (passive).
    return {
      aps: {
        alert: { 'title-loc-key': 'PUSH_WAKE_TITLE', 'loc-key': 'PUSH_WAKE_BODY' },
        'mutable-content': 1,
        'interruption-level': 'passive',
      },
      w: 1,
    };
  }
  return { aps: { 'content-available': 1 }, w: 1 };
}

function send(token, rec) {
  return new Promise((resolve) => {
    let s;
    try {
      s = session(rec.e);
    } catch (e) {
      resolve({ status: 0, reason: e.message });
      return;
    }
    const silent = rec.m !== 'alert';
    const ttl = Math.min(effectiveMinutes(rec) * 60, 15 * 60);
    let req;
    try {
      req = s.request({
        ':method': 'POST',
        ':path': `/3/device/${token}`,
        authorization: `bearer ${jwt(rec.e)}`,
        'apns-topic': TOPIC,
        'apns-push-type': silent ? 'background' : 'alert',
        'apns-priority': silent ? '5' : '10',
        // Не дошёл за интервал — не нужен: следующий придёт сам.
        'apns-expiration': String(Math.floor(Date.now() / 1000) + ttl),
        'apns-collapse-id': 'ogneliss-wake',
        'content-type': 'application/json',
      });
    } catch (e) {
      resolve({ status: 0, reason: e.message });
      return;
    }
    let status = 0;
    let body = '';
    req.setTimeout(15000, () => {
      try { req.close(http2.constants.NGHTTP2_CANCEL); } catch (_) { /* уже закрыт */ }
    });
    req.on('response', (h) => { status = h[':status'] || 0; });
    req.setEncoding('utf8');
    req.on('data', (c) => { if (body.length < 2048) body += c; });
    req.on('end', () => {
      let reason = '';
      try { reason = JSON.parse(body).reason || ''; } catch (_) { /* пустое тело */ }
      resolve({ status, reason });
    });
    req.on('error', (e) => resolve({ status: 0, reason: e.message }));
    req.end(JSON.stringify(payload(rec)));
  });
}

// ── FCM HTTP v1 (Android, 1.9.x) ──
// Токен доступа OAuth2 — по JWT, подписанному ключом сервисного аккаунта
// (RS256, crypto из Node, без библиотек Google). Живёт час; обновляем за 5
// минут до конца.
let saCache = null; // { mtime, sa } — файл ключа заменили — перечитать
let fcmAuth = null; // { token, exp }
let fcmAuthPending = null;

function fcmAccount() {
  if (!FCM_SA_FILE) return null;
  try {
    const st = fs.statSync(FCM_SA_FILE);
    if (saCache && saCache.mtime === st.mtimeMs) return saCache.sa;
    const j = JSON.parse(fs.readFileSync(FCM_SA_FILE, 'utf8'));
    const ok = j && j.type === 'service_account' && j.client_email && j.private_key && (FCM_PROJECT || j.project_id);
    const sa = ok
      ? {
          email: j.client_email,
          key: j.private_key,
          project: FCM_PROJECT || j.project_id,
          tokenUri: j.token_uri || 'https://oauth2.googleapis.com/token',
        }
      : null;
    saCache = { mtime: st.mtimeMs, sa };
    fcmAuth = null;
    return sa;
  } catch (_) {
    return null;
  }
}

function fcmReady() {
  return Boolean(fcmAccount());
}

async function fcmAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  if (fcmAuth && fcmAuth.exp - 300 > now) return fcmAuth.token;
  // Шаг отправляет до PARALLEL сигналов разом — токен запрашиваем один раз.
  if (fcmAuthPending) return fcmAuthPending;
  fcmAuthPending = (async () => {
    const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = b64url(JSON.stringify({ iss: sa.email, scope: FCM_SCOPE, aud: sa.tokenUri, iat: now, exp: now + 3600 }));
    const data = `${head}.${claims}`;
    const sig = crypto.sign('sha256', Buffer.from(data), sa.key);
    const r = await fetch(sa.tokenUri, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${data}.${b64url(sig)}`,
      }).toString(),
      signal: AbortSignal.timeout(15000),
    });
    let j = {};
    try { j = await r.json(); } catch (_) { /* не JSON */ }
    if (!r.ok || !j.access_token) throw new Error(`OAuth ${r.status} ${j.error || ''}`.trim());
    fcmAuth = { token: j.access_token, exp: now + (parseInt(j.expires_in, 10) || 3600) };
    return fcmAuth.token;
  })();
  try {
    return await fcmAuthPending;
  } finally {
    fcmAuthPending = null;
  }
}

// Сообщение только с данными, без уведомления: приложение (PushWakeFcm.kt)
// ставит проверку почты, а уведомления показывает само — о новых письмах.
function fcmMessage(token, rec) {
  const ttl = Math.min(effectiveMinutes(rec) * 60, 15 * 60);
  return {
    token,
    data: { w: '1' },
    android: {
      priority: rec.m === 'high' ? 'HIGH' : 'NORMAL',
      // Не дошёл за интервал — не нужен: следующий придёт сам.
      ttl: `${ttl}s`,
      // Телефон был без связи — из накопившихся сигналов доставят один.
      collapse_key: 'ogneliss-wake',
    },
  };
}

async function sendFcm(token, rec, validateOnly = false) {
  const sa = fcmAccount();
  if (!sa) return { status: 0, reason: 'no_service_account' };
  let access;
  try {
    access = await fcmAccessToken(sa);
  } catch (e) {
    return { status: 0, reason: e.name === 'TimeoutError' ? 'OAuth timeout' : e.message };
  }
  try {
    const body = { message: fcmMessage(token, rec) };
    if (validateOnly) body.validate_only = true;
    const r = await fetch(`${FCM_URL}/v1/projects/${encodeURIComponent(sa.project)}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${access}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    const text = (await r.text()).slice(0, 4096);
    if (r.ok) return { status: 200, reason: '' };
    // Причина — errorCode из FcmError (UNREGISTERED, INVALID_ARGUMENT …),
    // иначе общий статус Google (PERMISSION_DENIED, UNAUTHENTICATED …).
    let reason = '';
    try {
      const err = JSON.parse(text).error || {};
      const d = (err.details || []).find((x) => x && x.errorCode);
      reason = (d && d.errorCode) || err.status || '';
    } catch (_) { /* не JSON */ }
    if (r.status === 401) fcmAuth = null;
    return { status: r.status, reason };
  } catch (e) {
    return { status: 0, reason: e.name === 'TimeoutError' ? 'timeout' : e.message };
  }
}

// Токен больше не действует — удалить. UNREGISTERED: приложение удалено или
// токен отозван. INVALID_ARGUMENT: сообщение у нас постоянное, поэтому
// неверным может быть только токен.
function fcmGone(r) {
  return r.reason === 'UNREGISTERED' || (r.status === 400 && r.reason === 'INVALID_ARGUMENT');
}

function apnsGone(r) {
  return r.status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(r.reason);
}

function ready(env) {
  return env === 'fcm' ? fcmReady() : keyReady(env);
}

// ── Плановая отправка ──
const stats = { sent: 0, failed: 0, removed: 0, lastTick: null, lastError: null };
let ticking = false;

async function tick() {
  if (ticking) return;
  ticking = true;
  try {
    const now = Date.now();
    stats.lastTick = new Date(now).toISOString();
    // Не обновлялись EXPIRE_DAYS дней — приложение удалено или функция
    // выключена без связи с сервером.
    const expireBefore = now - EXPIRE_DAYS * 24 * 3600 * 1000;
    let expired = 0;
    for (const [t, rec] of tokens) {
      if ((rec.r || 0) < expireBefore) {
        tokens.delete(t);
        expired++;
      }
    }
    if (expired) {
      stats.removed += expired;
      saveSoon();
    }
    const due = [];
    for (const [t, rec] of tokens) {
      if (!ready(rec.e)) continue;
      if (now - (rec.l || 0) >= effectiveMinutes(rec) * 60 * 1000) due.push([t, rec]);
    }
    for (let i = 0; i < due.length; i += PARALLEL) {
      await Promise.all(due.slice(i, i + PARALLEL).map(async ([t, rec]) => {
        const fcm = rec.e === 'fcm';
        const r = fcm ? await sendFcm(t, rec) : await send(t, rec);
        if (r.status === 200) {
          rec.l = Date.now();
          stats.sent++;
        } else if (fcm ? fcmGone(r) : apnsGone(r)) {
          tokens.delete(t);
          stats.removed++;
        } else {
          stats.failed++;
          stats.lastError = `${fcm ? 'FCM ' : ''}${r.status} ${r.reason}`.trim();
          if (!fcm && ['ExpiredProviderToken', 'InvalidProviderToken'].includes(r.reason)) delete jwtCache[rec.e];
          // Повтор — через минуту, а не на каждом шаге (TooManyRequests,
          // QUOTA_EXCEEDED, сбой сети, ошибки Apple и Google).
          rec.l = Date.now() - effectiveMinutes(rec) * 60 * 1000 + 60 * 1000;
        }
      }));
    }
    if (due.length) saveSoon();
  } catch (e) {
    stats.lastError = e.message;
    log(`ошибка шага: ${e.message}`);
  } finally {
    ticking = false;
  }
}

// ── HTTP API ──
const hits = new Map(); // IP → запросов за текущую минуту (только в памяти)
setInterval(() => hits.clear(), 60 * 1000).unref();

function clientIp(req) {
  // За Nginx Proxy Manager: X-Real-IP ставит сам прокси ($remote_addr), а в
  // X-Forwarded-For первое значение может прислать кто угодно — берём
  // последнее, добавленное прокси.
  const real = String(req.headers['x-real-ip'] || '').trim();
  if (real) return real;
  const xf = String(req.headers['x-forwarded-for'] || '').split(',').map((s) => s.trim()).filter(Boolean);
  return xf.length ? xf[xf.length - 1] : (req.socket.remoteAddress || '');
}

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function reply(res, code, obj) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Cache-Control', 'no-store');
  if (obj === undefined) {
    res.statusCode = code;
    res.end();
    return;
  }
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.statusCode = code;
  res.end(JSON.stringify(obj));
}

function readJson(req) {
  return new Promise((resolve) => {
    let data = '';
    req.setEncoding('utf8');
    req.on('data', (c) => {
      data += c;
      if (data.length > 2048) {
        req.destroy();
        resolve(null);
      }
    });
    req.on('end', () => {
      try { resolve(JSON.parse(data)); } catch (_) { resolve(null); }
    });
    req.on('error', () => resolve(null));
  });
}

// Запрос изнутри контейнера (docker exec … wget http://127.0.0.1:…), а не
// через Nginx Proxy Manager: прокси подключается со своего адреса в сети
// Docker и всегда добавляет X-Real-IP.
function isLocal(req) {
  const a = req.socket.remoteAddress || '';
  const loop = a === '127.0.0.1' || a === '::1' || a === '::ffff:127.0.0.1';
  return loop && !req.headers['x-real-ip'] && !req.headers['x-forwarded-for'];
}

function healthz(full) {
  // Снаружи — только «жива ли служба и готов ли ключ APNs»: число установок
  // посторонним знать незачем. Подробно — изнутри (install-push-relay.sh check).
  if (!full) return { ok: true, ready: keyReady('production'), fcm: fcmReady() };
  const count = { total: tokens.size, production: 0, sandbox: 0, fcm: 0, silent: 0, alert: 0, normal: 0, high: 0 };
  for (const rec of tokens.values()) {
    count[rec.e] = (count[rec.e] || 0) + 1;
    count[rec.m] = (count[rec.m] || 0) + 1;
  }
  return {
    ok: true,
    tokens: count,
    keys: { production: keyReady('production'), sandbox: keyReady('sandbox'), team: Boolean(TEAM_ID), fcm: fcmReady() },
    topic: TOPIC,
    fcmProject: fcmReady() ? fcmAccount().project : null,
    apiKey: Boolean(API_KEY),
    minSilentMinutes: MIN_SILENT_MINUTES,
    sent: stats.sent,
    failed: stats.failed,
    removed: stats.removed,
    lastTick: stats.lastTick,
    lastError: stats.lastError,
  };
}

// Проверка ключа APNs без телефона (install-push-relay.sh check): сигнал на
// заведомо несуществующий токен. Apple сначала проверяет подпись (ключ, Team
// ID, Bundle ID) и только потом токен: ответ 400 BadDeviceToken значит «ключ
// принят», 403 InvalidProviderToken — ключ или Team ID неверны, 400
// TopicDisallowed / DeviceTokenNotForTopic — ключ не для этого Bundle ID.
async function probe() {
  const out = {};
  for (const env of ['production', 'sandbox']) {
    if (!keyReady(env)) {
      out[env] = { ready: false };
      continue;
    }
    const r = await send('0'.repeat(64), { e: env, i: 15, m: 'silent' });
    out[env] = { ready: true, status: r.status, reason: r.reason, keyOk: r.status === 400 && r.reason === 'BadDeviceToken' };
  }
  // FCM: проверочное сообщение (validate_only — Google ничего не отправляет)
  // на заведомо неверный токен. Google сначала проверяет ключ и право
  // отправки: 400 INVALID_ARGUMENT или UNREGISTERED значит «ключ принят»,
  // 401 / 403 — ключ отозван, нет права или не включён FCM API.
  if (!fcmReady()) {
    out.fcm = { ready: false };
  } else {
    const r = await sendFcm(`probe:${'x'.repeat(140)}`, { e: 'fcm', i: 15, m: 'normal' }, true);
    out.fcm = {
      ready: true,
      status: r.status,
      reason: r.reason,
      keyOk: (r.status === 400 && r.reason === 'INVALID_ARGUMENT') || r.reason === 'UNREGISTERED',
    };
  }
  return out;
}

const server = http.createServer(async (req, res) => {
  let p = (req.url || '/').split('?')[0];
  if (BASE_PATH && (p === BASE_PATH || p.startsWith(`${BASE_PATH}/`))) p = p.slice(BASE_PATH.length) || '/';

  const ip = clientIp(req);
  const n = (hits.get(ip) || 0) + 1;
  hits.set(ip, n);
  if (n > 60) return reply(res, 429, { error: 'too_many_requests' });

  const local = isLocal(req);
  if (req.method === 'GET' && (p === '/healthz' || p === '/')) return reply(res, 200, healthz(local));
  if (req.method === 'POST' && p === '/probe' && local) return reply(res, 200, await probe());
  if (req.method !== 'POST' || (p !== '/register' && p !== '/unregister')) return reply(res, 404, { error: 'not_found' });
  if (API_KEY && !safeEqual(req.headers['x-api-key'] || '', API_KEY)) return reply(res, 401, { error: 'unauthorized' });

  const body = await readJson(req);
  // Android (1.9.x): токен FCM — с сохранением регистра букв.
  const android = Boolean(body && body.platform === 'android');
  const raw = body && typeof body.token === 'string' ? body.token.trim() : '';
  const token = android ? raw : raw.toLowerCase();
  if (!(android ? FCM_TOKEN_RE : /^[0-9a-f]{64,200}$/).test(token)) return reply(res, 400, { error: 'bad_token' });

  if (p === '/unregister') {
    if (tokens.delete(token)) saveSoon();
    return reply(res, 204);
  }

  const env = android ? 'fcm' : body.env === 'sandbox' ? 'sandbox' : 'production';
  const interval = INTERVALS.includes(body.interval) ? body.interval : 15;
  const mode = android ? (body.mode === 'high' ? 'high' : 'normal') : body.mode === 'alert' ? 'alert' : 'silent';
  const old = tokens.get(token);
  if (!old && tokens.size >= MAX_TOKENS) return reply(res, 503, { error: 'full' });
  const now = Date.now();
  tokens.set(token, {
    e: env,
    i: interval,
    m: mode,
    // Новый токен — первый сигнал через интервал (с разбросом до минуты,
    // чтобы установки не будились все разом).
    l: old ? old.l : now - Math.floor(Math.random() * 60 * 1000),
    r: now,
  });
  saveSoon();
  return reply(res, 204);
});

function shutdown() {
  if (saveTimer) clearTimeout(saveTimer);
  saveNow();
  for (const s of Object.values(sessions)) {
    try { s.close(); } catch (_) { /* уже закрыто */ }
  }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

load();
if (!TEAM_ID || !keyReady('production')) {
  log('ключ APNs не настроен (APNS_TEAM_ID, APNS_KEY_ID, APNS_KEY_FILE) — регистрации принимаются, сигналы не отправляются');
}
if (!fcmReady()) {
  log('ключ FCM не настроен (FCM_SERVICE_ACCOUNT_FILE) — регистрации Android принимаются, сигналы не отправляются');
}
server.listen(PORT, HOST, () => log(`слушает ${HOST}:${PORT}${BASE_PATH}, тема ${TOPIC}`));
setInterval(() => { tick(); }, TICK_MS);
setInterval(() => {
  log(`токенов ${tokens.size}, отправлено ${stats.sent}, ошибок ${stats.failed}, удалено ${stats.removed}`);
}, 60 * 60 * 1000).unref();
