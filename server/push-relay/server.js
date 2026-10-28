'use strict';
// ============================================================================
// Ogneliss Push Relay — «будильник» для iPhone (Ogneliss Mail 1.7.2)
//
// Раз в выбранный интервал (15, 30 или 60 минут) отправляет через Apple Push
// Notification service (APNs) пустой сигнал «проверь почту». Получив его,
// приложение само, с телефона, проверяет почтовые ящики. Зачем — в
// docs/plan/IOS_BACKGROUND_DELIVERY.md, установка — README.md рядом.
//
// Что хранится (файл DATA_FILE): токен уведомлений APNs (случайный, свой у
// каждой установки приложения), окружение (production / sandbox), интервал,
// вид сигнала (silent / alert), время последнего сигнала и регистрации.
// Ни адресов, ни учётных данных, ни писем; к почтовым серверам служба не
// обращается. Журнал запросов с IP-адресами не ведётся (в nginx для /push —
// access_log off), в журнал службы пишутся только счётчики.
//
// Эндпоинты (под BASE_PATH, по умолчанию /push):
//   GET  /healthz      — {ok, ready}; изнутри контейнера — ещё число токенов,
//                        готовность ключей и счётчики (без самих токенов)
//   POST /register     — {token, env, interval, mode} → 204
//   POST /unregister   — {token} → 204
//   POST /probe        — только изнутри контейнера: принимает ли Apple ключ
//
// Виды сигнала:
//   silent — content-available, приоритет 5 (этап 1, без права Apple на
//            фильтрацию уведомлений): iOS пропускает 2–3 в час, поэтому не
//            чаще раза в MIN_SILENT_MINUTES (по умолчанию 20) минут;
//   alert  — видимый push с mutable-content для расширения уведомлений
//            (этап 2, после одобрения права фильтрации).
//
// Node.js >= 18. Зависимостей нет: http, http2 и crypto из Node.
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

function log(msg) {
  // Только служебные сообщения и счётчики — без токенов и IP.
  process.stdout.write(`${new Date().toISOString()} push-relay: ${msg}\n`);
}

// ── Хранилище токенов ──
// token → { e: env, i: interval, m: mode, l: last sent ms, r: registered ms }
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
      if (!keyReady(rec.e)) continue;
      if (now - (rec.l || 0) >= effectiveMinutes(rec) * 60 * 1000) due.push([t, rec]);
    }
    for (let i = 0; i < due.length; i += PARALLEL) {
      await Promise.all(due.slice(i, i + PARALLEL).map(async ([t, rec]) => {
        const r = await send(t, rec);
        if (r.status === 200) {
          rec.l = Date.now();
          stats.sent++;
        } else if (r.status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(r.reason)) {
          tokens.delete(t);
          stats.removed++;
        } else {
          stats.failed++;
          stats.lastError = `${r.status} ${r.reason}`.trim();
          if (['ExpiredProviderToken', 'InvalidProviderToken'].includes(r.reason)) delete jwtCache[rec.e];
          // Повтор — через минуту, а не на каждом шаге (TooManyRequests,
          // сбой сети, ошибки Apple).
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
  if (!full) return { ok: true, ready: keyReady('production') };
  const count = { total: tokens.size, production: 0, sandbox: 0, silent: 0, alert: 0 };
  for (const rec of tokens.values()) {
    count[rec.e] = (count[rec.e] || 0) + 1;
    count[rec.m] = (count[rec.m] || 0) + 1;
  }
  return {
    ok: true,
    tokens: count,
    keys: { production: keyReady('production'), sandbox: keyReady('sandbox'), team: Boolean(TEAM_ID) },
    topic: TOPIC,
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
  const token = body && typeof body.token === 'string' ? body.token.trim().toLowerCase() : '';
  if (!/^[0-9a-f]{64,200}$/.test(token)) return reply(res, 400, { error: 'bad_token' });

  if (p === '/unregister') {
    if (tokens.delete(token)) saveSoon();
    return reply(res, 204);
  }

  const env = body.env === 'sandbox' ? 'sandbox' : 'production';
  const interval = INTERVALS.includes(body.interval) ? body.interval : 15;
  const mode = body.mode === 'alert' ? 'alert' : 'silent';
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
server.listen(PORT, HOST, () => log(`слушает ${HOST}:${PORT}${BASE_PATH}, тема ${TOPIC}`));
setInterval(() => { tick(); }, TICK_MS);
setInterval(() => {
  log(`токенов ${tokens.size}, отправлено ${stats.sent}, ошибок ${stats.failed}, удалено ${stats.removed}`);
}, 60 * 60 * 1000).unref();
