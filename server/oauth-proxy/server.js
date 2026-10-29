'use strict';
// ============================================================================
// Mail OAuth Proxy
// Серверный посредник OAuth для организации: хранит client_secret провайдеров,
// ловит redirect, меняет код на токены и ОБНОВЛЯЕТ их по refresh-токену,
// чтобы пользователь не логинился заново.
//
// Эндпоинты:
//   GET  /healthz                          — проверка живости и настройки
//   GET  /oauth/:provider/login?redirect=  — старт авторизации (редирект к провайдеру)
//   GET  /oauth/callback?code&state        — приём кода, обмен на токены, редирект в приложение
//   GET  /token?session=...                — выдать действующий access_token (с авто-refresh)
//   POST /refresh                          — принудительное обновление (body: {session})
//   POST /revoke                           — отозвать доступ (body: {session} | {rt, provider})
//
// Требует Node.js >= 18 (встроенный fetch). Зависимость: express.
// Все секреты — только в переменных окружения (.env), НЕ в приложении.
// ============================================================================

const express = require('express');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// ── Конфигурация из окружения ──
const PORT = parseInt(process.env.PORT || '8787', 10);
// В Docker слушаем все интерфейсы (HOST=0.0.0.0 из compose/Dockerfile),
// иначе NPM/другой контейнер не достучится → 502. На хосте (systemd+nginx)
// по умолчанию 127.0.0.1 — наружу не торчим.
const HOST = process.env.HOST || '127.0.0.1';
const BASE_URL = (process.env.BASE_URL || `http://127.0.0.1:${PORT}`).replace(/\/$/, '');

// Прокси может жить либо на своём поддомене (BASE_URL=https://oauth.example.ru),
// либо НА ПУТИ основного домена (BASE_URL=https://www.example.ru/oauth) — это удобно,
// когда сертификат покрывает www, но не oauth.*. Префикс пути берём из BASE_URL и
// монтируем на него все маршруты.
let BASE_PATH = '';
try { BASE_PATH = new URL(BASE_URL).pathname.replace(/\/+$/, ''); } catch { BASE_PATH = ''; }

// redirect_uri, который регистрируется в консолях провайдеров.
// Поддомен:  https://oauth.example.ru/oauth/callback  (как было — совместимость)
// На пути:   https://www.example.ru/oauth/callback    (короткий и чистый)
const CALLBACK_URL = process.env.CALLBACK_URL
  || (BASE_PATH ? `${BASE_URL}/callback` : `${BASE_URL}/oauth/callback`);
const API_KEY = process.env.PROXY_API_KEY || '';
// Секреты обязательны. Раньше при их отсутствии брался случайный ключ:
// после перезапуска все выданные приложениям refresh-blob переставали
// расшифровываться, и пользователи молча теряли вход. Лучше не стартовать.
for (const name of ['STATE_SECRET', 'PROXY_API_KEY']) {
  if (!process.env[name] || process.env[name].length < 16) {
    console.error(`oauth-proxy: переменная ${name} не задана или короче 16 символов — запуск остановлен`);
    process.exit(1);
  }
}
const STATE_SECRET = process.env.STATE_SECRET;
const STORE_PATH = process.env.STORE_PATH || '/var/lib/oauth-proxy/store.json';
// Разрешённые схемы/URL для возврата в приложение (защита open-redirect)
const ALLOWED_REDIRECTS = (process.env.ALLOWED_REDIRECTS ||
  'com.ogneliss.mail://oauth,https://mail.example.com/oauth2redirect.html')
  .split(',').map((s) => s.trim()).filter(Boolean);

// ── Описание провайдеров (endpoints фиксированы, секреты — из env) ──
// (имя провайдера проставляется ниже — для журнала)
const PROVIDERS = {
  google: {
    authUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenUrl: 'https://oauth2.googleapis.com/token',
    clientId: process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
    // Календарь и контакты Gmail идут по CalDAV/CardDAV тем же токеном —
    // без этих scope Google отвечает 403 (см. lib/services/mail/dav).
    scope: process.env.GOOGLE_SCOPE || 'https://mail.google.com/ https://www.googleapis.com/auth/gmail.settings.basic https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav openid email profile',
    extra: { access_type: 'offline', prompt: 'consent' }, // чтобы выдавался refresh_token
  },
  microsoft: {
    authUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    tokenUrl: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    clientId: process.env.MS_CLIENT_ID,
    clientSecret: process.env.MS_CLIENT_SECRET,
    // IMAP/SMTP (Outlook.com, Hotmail, Live, Office 365). Ресурс в одном
    // токене может быть только один: outlook.office.com. Права в Entra
    // («Разрешения API» → Microsoft Graph → IMAP.AccessAsUser.All, SMTP.Send,
    // offline_access, openid, email, profile) запрашиваются с этим префиксом.
    // Для EWS Exchange Online — отдельное право «Office 365 Exchange Online →
    // EWS.AccessAsUser.All» и MS_SCOPE с https://outlook.office.com/EWS.AccessAsUser.All.
    scope: process.env.MS_SCOPE || 'https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access openid email profile',
    // select_account: выбор учётной записи, если в браузере их несколько.
    // consent — не нужен: согласие запрашивается само при первом входе.
    extra: { prompt: 'select_account' },
  },
  // Exchange Online (Microsoft 365) по ActiveSync и Microsoft Graph (1.8.11).
  // Только рабочие учётные записи (/organizations). Токен — для ActiveSync и
  // EWS (ресурс outlook.office365.com); согласие при входе — ещё и на права
  // Microsoft Graph без согласия администратора: Microsoft отключает EWS в
  // Exchange Online, адресная книга, подсказки MailTips, правила сервера и
  // «Восстановить удалённые» идут через Graph. Токен Graph — тем же входом:
  // POST /token с resource=graph. Организация не разрешает сотрудникам
  // давать согласие на Graph — вход повторяется без него (ActiveSync
  // работает и так). EXO_GRAPH=0 — не просить Graph вовсе.
  // Клиент — тот же, что у microsoft (EXO_CLIENT_ID/SECRET, иначе MS_*), с
  // правами «Office 365 Exchange Online → EAS.AccessAsUser.All,
  // EWS.AccessAsUser.All» и правами Graph (docs/guides/OAUTH_SETUP.md).
  exchange: {
    authUrl: 'https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize',
    tokenUrl: 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
    clientId: process.env.EXO_CLIENT_ID || process.env.MS_CLIENT_ID,
    clientSecret: process.env.EXO_CLIENT_SECRET || process.env.MS_CLIENT_SECRET,
    scope: process.env.EXO_SCOPE || 'https://outlook.office365.com/EAS.AccessAsUser.All https://outlook.office365.com/EWS.AccessAsUser.All offline_access openid email profile',
    consentScope: process.env.EXO_GRAPH === '0' ? '' : (process.env.EXO_GRAPH_CONSENT || [
      'https://graph.microsoft.com/User.Read',
      'https://graph.microsoft.com/User.ReadBasic.All',
      'https://graph.microsoft.com/People.Read',
      'https://graph.microsoft.com/Mail.ReadWrite',
      'https://graph.microsoft.com/MailboxSettings.ReadWrite',
    ].join(' ')),
    // Все права Graph, на которые есть согласие (в том числе выданные
    // администратором: Place.Read.All, GroupMember.Read.All, User.Read.All).
    graphScope: 'https://graph.microsoft.com/.default offline_access',
    // У входа два ресурса — при обмене кода и обновлении scope указывается
    // явно, иначе Microsoft выберет ресурс сам.
    explicitScope: true,
    extra: { prompt: 'select_account' },
  },
  yandex: {
    authUrl: 'https://oauth.yandex.ru/authorize',
    tokenUrl: 'https://oauth.yandex.ru/token',
    clientId: process.env.YANDEX_CLIENT_ID,
    clientSecret: process.env.YANDEX_CLIENT_SECRET,
    // login:email и login:info — адрес и имя владельца: без них адрес
    // Яндекс 360 на своём домене не узнать (подставлялся логин@yandex.ru).
    scope: process.env.YANDEX_SCOPE || 'mail:imap_full mail:smtp calendar:all addressbook:all login:email login:info',
    // Запасные наборы по очереди: если в приложении на oauth.yandex.ru не
    // отмечены какие-то права, Яндекс отвечает invalid_scope и вход ломается
    // целиком. Сначала без календаря и контактов, но С правами профиля —
    // без login:info и login:email имя ящика превращалось в логин
    // («испортилось имя», 09.10.2026), а адрес Яндекс 360 — в логин@yandex.ru.
    // Затем без профиля, затем только почта.
    fallbackScopes: [
      'mail:imap_full mail:smtp login:email login:info',
      'mail:imap_full mail:smtp calendar:all addressbook:all',
      'mail:imap_full mail:smtp login:email',
      process.env.YANDEX_BASE_SCOPE || 'mail:imap_full mail:smtp',
    ],
    // Яндекс на ogneliss.ru отвечал invalid_client, пока client_secret шёл в
    // теле запроса; с заголовком Basic вход заработал (06.10.2026). Basic
    // Яндекс поддерживает официально. ВАЖНО: учётные данные клиента НЕ
    // удаляются из тела для остальных провайдеров — без них Google отвечает
    // 401 invalid_client на каждое обновление токена.
    authStyle: 'basic',
    extra: {},
  },
  // Mail.ru — по документации OAuth Mail (oauth.mail.ru, ред. 2025):
  //  · openid обязателен (без него 401), mail.imap — только вместе с openid;
  //  · refresh_token выдаётся только с offline_access и prompt=consent;
  //  · обмен кода — только с code_verifier (PKCE обязателен);
  //  · client_id:client_secret — в заголовке Basic, при обновлении client_id
  //    ещё и в теле;
  //  · в ответе на обмен нет id_token — адрес и имя берутся из userinfo;
  //  · ошибка может прийти с HTTP 200 (поле error в JSON).
  // Прежний набор «userinfo mail.imap» (старые приложения) — запасной.
  mailru: {
    authUrl: 'https://oauth.mail.ru/login',
    tokenUrl: 'https://oauth.mail.ru/token',
    userinfoUrl: 'https://oauth.mail.ru/api/v1/oidc/userinfo',
    clientId: process.env.MAILRU_CLIENT_ID,
    clientSecret: process.env.MAILRU_CLIENT_SECRET,
    scope: (!process.env.MAILRU_SCOPE || process.env.MAILRU_SCOPE.trim() === 'userinfo mail.imap')
      ? 'openid email profile mail.imap offline_access'
      : process.env.MAILRU_SCOPE,
    fallbackScopes: ['openid mail.imap offline_access', 'userinfo mail.imap'],
    authStyle: 'basic',
    clientIdInBody: true,
    pkce: true,
    // state — ровно 256 бит, как в документации; данные входа — в памяти.
    shortState: true,
    extra: { prompt: 'consent' },
  },
  yahoo: {
    authUrl: 'https://api.login.yahoo.com/oauth2/request_auth',
    tokenUrl: 'https://api.login.yahoo.com/oauth2/get_token',
    clientId: process.env.YAHOO_CLIENT_ID,
    clientSecret: process.env.YAHOO_CLIENT_SECRET,
    // Scope зависит от прав, выданных приложению в Yahoo Developer.
    // mail-w обязателен: без него IMAP/SMTP Yahoo не принимают XOAUTH2
    // (прежнее значение «openid email» давало вход без доступа к почте).
    scope: process.env.YAHOO_SCOPE || 'openid email profile mail-w',
    fallbackScopes: ['openid mail-w', 'mail-w'],
    // Yahoo требует client_id:client_secret в заголовке Basic на token-endpoint.
    authStyle: 'basic',
    extra: {},
  },
};

// ── Шифрование refresh-токена в blob rt (AES-256-GCM), stateless-модель ──
// ENC_SECRET отдельно от STATE_SECRET; если его нет — как и раньше берём
// STATE_SECRET (иначе ранее выданные refresh-blob перестали бы работать).
if (!process.env.ENC_SECRET) console.warn('oauth-proxy: ENC_SECRET не задан, ключ шифрования выводится из STATE_SECRET');
const ENC_KEY = crypto.createHash('sha256').update(process.env.ENC_SECRET || STATE_SECRET).digest();
function encRt(plain) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', ENC_KEY, iv);
  const ct = Buffer.concat([c.update(Buffer.from(plain, 'utf8')), c.final()]);
  return Buffer.concat([iv, ct, c.getAuthTag()]).toString('base64url');
}
function decRt(blob) {
  const raw = Buffer.from(String(blob), 'base64url');
  const iv = raw.subarray(0, 12), tag = raw.subarray(raw.length - 16), ct = raw.subarray(12, raw.length - 16);
  const d = crypto.createDecipheriv('aes-256-gcm', ENC_KEY, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(ct), d.final()]).toString('utf8');
}

// ── Простое файловое хранилище сессий (sessionId -> {provider, refresh, access, expiry}) ──
function loadStore() {
  try { return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8')); }
  catch { return {}; }
}
function saveStore(store) {
  fs.mkdirSync(path.dirname(STORE_PATH), { recursive: true });
  const tmp = STORE_PATH + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(store), { mode: 0o600 });
  fs.renameSync(tmp, STORE_PATH);
}

// ── Подпись state (HMAC) против CSRF/подмены ──
function signState(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const mac = crypto.createHmac('sha256', STATE_SECRET).update(body).digest('base64url');
  return `${body}.${mac}`;
}
// Короткий state (Mail.ru: «длина должна быть 256 бит»): случайные 32 байта,
// а сами данные входа — в памяти на 10 минут. Перезапуск прокси прерывает
// только незавершённые входы.
const SHORT_STATES = new Map();
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of SHORT_STATES) if (now - v.ts > 10 * 60 * 1000) SHORT_STATES.delete(k);
}, 60 * 1000).unref();
function makeState(p, payload) {
  if (!p.shortState) return signState(payload);
  const k = crypto.randomBytes(32).toString('base64url');
  SHORT_STATES.set(k, payload);
  return k;
}

function verifyState(state) {
  const short = SHORT_STATES.get(String(state || ''));
  if (short) { SHORT_STATES.delete(String(state)); return short; }
  const [body, mac] = String(state || '').split('.');
  if (!body || !mac) return null;
  const expect = crypto.createHmac('sha256', STATE_SECRET).update(body).digest('base64url');
  if (!safeEqual(mac, expect)) return null;
  try { return JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); }
  catch { return null; }
}

// Сравнение за постоянное время; timingSafeEqual бросает исключение при
// разной длине — раньше неверная подпись state давала 500 вместо 400.
function safeEqual(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  if (x.length !== y.length) return false;
  return crypto.timingSafeEqual(x, y);
}

// PKCE между прокси и провайдером (Mail.ru требует code_verifier при обмене
// кода). Verifier не хранится: он выводится из секрета и nonce из state —
// 43 символа base64url, как требует RFC 7636. В адрес он не попадает,
// уходит только code_challenge.
function pkceVerifier(nonce) {
  return crypto.createHmac('sha256', STATE_SECRET).update(`pkce:${nonce}`).digest('base64url');
}
function pkceChallenge(verifier) {
  return crypto.createHash('sha256').update(verifier).digest('base64url');
}

function requireApiKey(req, res, next) {
  if (!API_KEY) return res.status(500).json({ error: 'proxy_misconfigured: PROXY_API_KEY не задан' });
  if (!safeEqual(req.get('x-api-key') || '', API_KEY)) return res.status(401).json({ error: 'unauthorized' });
  next();
}

// ── Одноразовые коды возврата (PKCE между приложением и прокси) ──
// Раньше access- и refresh-токены передавались в адресе возврата
// (com.ogneliss.mail://oauth?at=…&rt=…). Свою схему может зарегистрировать
// любое приложение на устройстве и перехватить токены. Теперь, если
// приложение прислало code_challenge (cc), в адрес возврата уходит только
// одноразовый код (oc) на 2 минуты, а токены выдаются по POST /exchange
// тому, кто знает code_verifier. Старые версии приложения (без cc)
// работают по-прежнему.
const PENDING = new Map();
const PENDING_TTL_MS = 2 * 60 * 1000;
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of PENDING) if (v.until < now) PENDING.delete(k);
}, 30 * 1000).unref();

function plain(res, status, text) {
  return res.status(status).type('text/plain; charset=utf-8').send(String(text).slice(0, 300));
}

// ── Обмен/обновление токенов у провайдера ──
for (const [name, p] of Object.entries(PROVIDERS)) p.name = name;

// Отпечаток секрета для сверки (первые 8 hex от SHA-256). По нему видно,
// что прокси и приложение собраны с одним ключом и что ключ шифрования не
// менялся после переезда, — сами секреты при этом не раскрываются.
function fingerprint(v) {
  return v ? crypto.createHash('sha256').update(String(v)).digest('hex').slice(0, 8) : 'не задан';
}

// Способ передачи client_id/secret: провайдеры принимают разное (Яндекс и
// Mail.ru — заголовок Basic, Google и Microsoft — тело). При отказе
// invalid_client (или 401) запрос повторяется вторым способом (09.10.2026):
// раньше вход Mail.ru падал на обмене кода, а пользователь видел только
// страницу ошибки на адресе /callback.
async function tokenRequest(p, params) {
  try {
    return await tokenRequestStyle(p, params, p.authStyle === 'basic' ? 'basic' : 'body');
  } catch (e) {
    const code = e.body && e.body.error;
    if (e.status === 401 || code === 'invalid_client' || code === 'unauthorized_client') {
      const other = p.authStyle === 'basic' ? 'body' : 'basic';
      console.warn(`oauth-proxy: ${p.name || '?'} — повтор обмена с передачей ключа способом «${other}»`);
      return tokenRequestStyle(p, params, other);
    }
    throw e;
  }
}

async function tokenRequestStyle(p, params, style) {
  const headers = { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' };
  const body = new URLSearchParams(params);
  if (style === 'basic') {
    // Yahoo и др.: client_id:client_secret в заголовке Authorization: Basic,
    // а не в теле запроса.
    headers.Authorization = 'Basic ' + Buffer.from(`${p.clientId}:${p.clientSecret}`).toString('base64');
    // Mail.ru в примере обновления передаёт client_id и в теле.
    if (p.clientIdInBody) body.set('client_id', p.clientId);
  } else {
    body.set('client_id', p.clientId);
    body.set('client_secret', p.clientSecret);
  }
  const r = await fetch(p.tokenUrl, {
    method: 'POST',
    headers,
    body,
  });
  const text = await r.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  // Mail.ru может вернуть ошибку с HTTP 200 — тогда в JSON есть error.
  if (!r.ok || json.error) {
    // В журнал службы — провайдер, код и поле error провайдера (секретов в
    // нём нет). Раньше причина отказа была видна только в приложении.
    console.warn(`oauth-proxy: ${p.name || '?'} ${params.grant_type || ''} → HTTP ${r.status} ${json.error || ''}`
      + (json.error_description ? ` (${String(json.error_description).slice(0, 160)})` : ''));
    const err = new Error(`token_endpoint_${r.status}: ${json.error || text}`);
    err.status = r.ok ? 400 : r.status; err.body = json;
    throw err;
  }
  return json;
}

function isAllowedRedirect(back) {
  if (ALLOWED_REDIRECTS.includes(back)) return true;
  try { const u = new URL(back); return u.protocol === 'http:' && (u.hostname === '127.0.0.1' || u.hostname === 'localhost'); }
  catch { return false; }
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '16kb' }));
app.use((_req, res, next) => {
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Referrer-Policy', 'no-referrer');
  res.set('Cache-Control', 'no-store');
  next();
});
app.set('trust proxy', true);

// Журнал запросов: одна строка на запрос — метод, путь БЕЗ параметров
// (в них коды и сессии), статус, время, адрес клиента. healthz — только
// при ошибке, иначе мониторинг засоряет журнал. Ротацию журнала делает
// Docker (json-file: 10 МБ × 5, см. docker-compose.yml).
const LOG_HEALTHZ = process.env.LOG_HEALTHZ === '1';
app.use((req, res, next) => {
  const t0 = Date.now();
  res.on('finish', () => {
    const p = req.path || '';
    if (p.endsWith('/healthz') && res.statusCode < 400 && !LOG_HEALTHZ) return;
    const line = `${new Date().toISOString()} ${req.method} ${p} → ${res.statusCode} ${Date.now() - t0}ms ip=${req.ip}`;
    (res.statusCode >= 500 ? console.error : res.statusCode >= 400 ? console.warn : console.log)(line);
  });
  next();
});

// Все маршруты — на роутере, чтобы смонтировать их по BASE_PATH.
const router = express.Router();

// Корень: короткая заглушка (без секретов) — чтобы браузер/мониторинг не
// получали 404. Полезные эндпоинты перечислены ниже.
router.get('/', (_req, res) => {
  const b = BASE_PATH || '';
  res.type('text/plain').send(
    'Ogneliss OAuth proxy\n'
    + 'status: ok\n'
    + `endpoints: ${b}/healthz, ${b}/oauth/:provider/login, ${b}/callback, ${b}/token\n`
  );
});

// Проверка живости и настройки — без секретов: для каждого провайдера
// видно, заданы ли client_id и client_secret и как они передаются, а по
// отпечаткам ключей — тот ли это .env, что был до переезда.
router.get('/healthz', (_req, res) => res.json({
  ok: true,
  providers: Object.keys(PROVIDERS),
  config: Object.fromEntries(Object.entries(PROVIDERS).map(([name, p]) => [name, {
    clientId: Boolean(p.clientId),
    clientSecret: Boolean(p.clientSecret),
    auth: p.authStyle === 'basic' ? 'basic' : 'body',
    ...(p.graphScope ? { graph: Boolean(p.consentScope) } : {}),
  }])),
  keys: {
    api: fingerprint(API_KEY),
    enc: fingerprint(process.env.ENC_SECRET || process.env.STATE_SECRET),
  },
}));

// 1) Старт авторизации
router.get('/oauth/:provider/login', (req, res) => {
  const p = PROVIDERS[req.params.provider];
  if (!p) return plain(res, 404, 'unknown provider');
  if (!p.clientId || !p.clientSecret) return plain(res, 500, 'provider not configured');

  const redirect = String(req.query.redirect || ALLOWED_REDIRECTS[0]);
  if (!isAllowedRedirect(redirect)) return plain(res, 400, 'redirect not allowed');

  const cc = req.query.cc ? String(req.query.cc) : '';
  if (cc && !/^[A-Za-z0-9_-]{43}$/.test(cc)) return plain(res, 400, 'bad code_challenge');
  const nonce = crypto.randomBytes(16).toString('hex');
  // g — просили согласие и на Graph (Exchange Online).
  const g = p.consentScope ? 1 : undefined;
  const state = makeState(p, {
    provider: req.params.provider,
    redirect,
    cc: cc || undefined,
    nonce,
    g,
    ts: Date.now(),
  });
  res.redirect(authUrl(p, state, g ? `${p.scope} ${p.consentScope}` : p.scope, nonce));
});

// Отказ, после которого вход стоит повторить без прав Graph (как в
// приложении, DirectOAuth.isConsentError): организация требует согласия
// администратора (AADSTS90094, 90095, 65001), человек отказался от новых прав
// (65004), права неизвестны регистрации (650057, invalid_scope).
function isConsentError(code, detail) {
  const d = String(detail || '').toUpperCase();
  if (['consent_required', 'invalid_scope', 'interaction_required'].includes(code)) return true;
  return ['AADSTS65001', 'AADSTS65004', 'AADSTS90094', 'AADSTS90095', 'AADSTS650057', 'AADSTS90008'].some((c) => d.includes(c));
}

function authUrl(p, state, scope, nonce) {
  const auth = new URL(p.authUrl);
  auth.searchParams.set('response_type', 'code');
  auth.searchParams.set('client_id', p.clientId);
  auth.searchParams.set('redirect_uri', CALLBACK_URL);
  auth.searchParams.set('scope', scope);
  auth.searchParams.set('state', state);
  for (const [k, v] of Object.entries(p.extra)) auth.searchParams.set(k, v);
  if (p.pkce && nonce) {
    auth.searchParams.set('code_challenge', pkceChallenge(pkceVerifier(nonce)));
    auth.searchParams.set('code_challenge_method', 'S256');
  }
  return auth.toString();
}

// 2) Callback от провайдера
router.get(['/oauth/callback', '/callback'], async (req, res) => {
  const data = verifyState(req.query.state);
  if (!data) return plain(res, 400, 'invalid state');
  if (Date.now() - data.ts > 10 * 60 * 1000) return plain(res, 400, 'state expired');
  const p = PROVIDERS[data.provider];
  if (!p) return plain(res, 400, 'unknown provider');
  // text/plain: значение error приходит из адреса и раньше попадало в HTML
  // как есть (отражённый XSS на домене прокси).
  if (req.query.error) {
    const err = /^[a-z_]{1,40}$/.test(String(req.query.error)) ? String(req.query.error) : 'provider_error';
    // Exchange Online: согласия на Graph не дали — вход без Graph.
    if (data.g && isConsentError(err, req.query.error_description)) {
      const aad = /AADSTS\d+/.exec(String(req.query.error_description || ''));
      console.warn(`[${data.provider}] согласие на Microsoft Graph не получено (${aad ? aad[0] : err}) — вход без Graph`);
      const nonce = crypto.randomBytes(16).toString('hex');
      return res.redirect(authUrl(p, makeState(p, {
        ...data,
        g: undefined,
        nonce,
        ts: Date.now(),
      }), p.scope, nonce));
    }
    // Не все права выданы приложению у провайдера — повтор со следующим
    // запасным набором (data.fb — сколько наборов уже пробовали).
    const tried = Number(data.fb || 0);
    const next = (p.fallbackScopes || [])[tried];
    if (err === 'invalid_scope' && next) {
      console.warn(`[${data.provider}] invalid_scope — повтор с правами: ${next}`);
      const nonce = crypto.randomBytes(16).toString('hex');
      return res.redirect(authUrl(p, makeState(p, {
        ...data,
        fb: tried + 1,
        nonce,
        ts: Date.now(),
      }), next, nonce));
    }
    // Вернуть ошибку в приложение: оно закроет браузер и покажет понятный
    // текст. Раньше вкладка оставалась на странице «provider error: …».
    const back = new URL(data.redirect);
    back.searchParams.set('provider', data.provider);
    back.searchParams.set('error', err);
    return res.redirect(back.toString());
  }

  try {
    const params = {
      grant_type: 'authorization_code',
      code: String(req.query.code || ''),
      redirect_uri: CALLBACK_URL,
    };
    if (p.pkce && data.nonce) params.code_verifier = pkceVerifier(data.nonce);
    if (p.explicitScope) params.scope = p.scope;
    const tok = await tokenRequest(p, params);
    // Stateless: refresh шифруется в blob rt и отдаётся клиенту (сервер БД не ведёт).
    const access = tok.access_token || '';
    const expMs = Date.now() + ((tok.expires_in || 3600) * 1000);
    const rt = tok.refresh_token ? encRt(tok.refresh_token) : '';
    // Адрес и имя — из id_token (получен напрямую от провайдера по TLS,
    // подпись не проверяем). Токен Microsoft для outlook.office.com у личных
    // ящиков непрозрачный — узнать адрес иначе нельзя.
    if (data.fb) console.warn(`[${data.provider}] вход с запасным набором прав №${data.fb} — отметьте недостающие права в приложении провайдера`);
    let ident = idTokenIdentity(tok.id_token);
    // Mail.ru id_token не присылает — адрес и имя из userinfo.
    if (!ident.email && p.userinfoUrl && access) ident = await userinfoIdentity(p, access);

    // Возврат в приложение: deep link или web-redirect страница
    const back = new URL(data.redirect);
    back.searchParams.set('provider', data.provider);
    if (data.cc) {
      const oc = crypto.randomBytes(24).toString('base64url');
      PENDING.set(oc, { at: access, exp: expMs, rt, provider: data.provider, cc: data.cc, email: ident.email, name: ident.name, graph: Boolean(data.g), until: Date.now() + PENDING_TTL_MS });
      back.searchParams.set('oc', oc);
    } else {
      back.searchParams.set('at', access);
      back.searchParams.set('exp', String(expMs));
      if (rt) back.searchParams.set('rt', rt);
      if (ident.email) back.searchParams.set('email', ident.email);
    }
    if (data.redirect.startsWith('http')) {
      // web: маленькая страница, шлёт session в открывающее окно и закрывается
      res.set('Content-Type', 'text/html; charset=utf-8');
      return res.send(`<!doctype html><meta charset=utf-8><body>
<script>
  try { window.opener && window.opener.postMessage(${JSON.stringify({ ok: true })}, '*'); } catch (e) {}
  location.replace(${JSON.stringify(back.toString())});
</script>Готово. Можно закрыть окно.</body>`);
    }
    return res.redirect(back.toString());
  } catch (e) {
    // Не страница ошибки на /callback, а возврат в приложение с кодом
    // провайдера (invalid_client, invalid_grant, AADSTS…): приложение закроет
    // браузер и покажет понятный текст, причина — и в журнале службы.
    const b = e.body || {};
    const aad = /AADSTS\d+/.exec(String(b.error_description || ''));
    const desc = String((aad && aad[0]) || b.error || `http_${e.status || 0}`).replace(/[^A-Za-z0-9_.-]/g, '').slice(0, 60);
    console.warn(`[${data.provider}] обмен кода не удался: ${desc} ${String(b.error_description || e.message || '').slice(0, 200)}`);
    try {
      const back = new URL(data.redirect);
      back.searchParams.set('provider', data.provider);
      back.searchParams.set('error', 'token_exchange');
      back.searchParams.set('desc', desc);
      return res.redirect(back.toString());
    } catch (_) {
      return plain(res, 502, `token exchange failed: ${desc}`);
    }
  }
});

// Адрес и имя по access_token (OIDC userinfo). Сначала новый адрес Mail.ru
// (POST с Bearer), затем прежний (GET ?access_token=). Ошибка — не повод
// срывать вход: приложение спросит адрес само.
async function userinfoIdentity(p, access) {
  const tries = [
    () => fetch(p.userinfoUrl, { method: 'POST', headers: { Authorization: `Bearer ${access}`, Accept: 'application/json' }, signal: AbortSignal.timeout(5000) }),
  ];
  if (p.name === 'mailru') {
    tries.push(() => fetch(`https://oauth.mail.ru/userinfo?access_token=${encodeURIComponent(access)}`, { signal: AbortSignal.timeout(5000) }));
  }
  for (const t of tries) {
    try {
      const r = await t();
      const j = await r.json().catch(() => ({}));
      const email = String(j.email || '');
      if (r.ok && !j.error && /^[^@\s]+@[^@\s]+$/.test(email)) {
        const name = j.name || [j.given_name || j.first_name, j.family_name || j.last_name].filter(Boolean).join(' ');
        return { email: email.toLowerCase(), name: String(name || '').slice(0, 120) };
      }
    } catch (_) { /* следующий способ */ }
  }
  console.warn(`[${p.name}] userinfo: адрес не получен`);
  return {};
}

function idTokenIdentity(idt) {
  try {
    if (!idt) return {};
    const payload = JSON.parse(Buffer.from(String(idt).split('.')[1], 'base64url').toString('utf8'));
    const email = payload.email || payload.preferred_username || payload.upn || '';
    return {
      email: /^[^@\s]+@[^@\s]+$/.test(email) ? String(email).toLowerCase() : '',
      name: typeof payload.name === 'string' ? payload.name.slice(0, 120) : '',
    };
  } catch (_) {
    return {};
  }
}

// Обмен одноразового кода на токены (только с code_verifier).
router.post('/exchange', requireApiKey, (req, res) => {
  const oc = String(req.body.oc || '');
  const cv = String(req.body.cv || '');
  const entry = PENDING.get(oc);
  PENDING.delete(oc); // одноразовый — даже при неверном verifier
  if (!entry || entry.until < Date.now()) return res.status(400).json({ error: 'invalid or expired code' });
  const challenge = crypto.createHash('sha256').update(cv).digest('base64url');
  if (!safeEqual(challenge, entry.cc)) return res.status(400).json({ error: 'invalid verifier' });
  res.json({ access_token: entry.at, expires_at: entry.exp, rt: entry.rt, provider: entry.provider, email: entry.email || '', name: entry.name || '', ...(entry.graph ? { graph: true } : {}) });
});

// 3) Выдать действующий access_token (с авто-обновлением)
async function ensureFreshAccess(session) {
  const store = loadStore();
  const s = store[session];
  if (!s) { const e = new Error('unknown session'); e.status = 404; throw e; }
  // Запас 60 секунд до истечения
  if (s.access && Date.now() < s.expiry - 60 * 1000) {
    return { access: s.access, expiry: s.expiry, provider: s.provider };
  }
  if (!s.refresh) { const e = new Error('no refresh token; re-login required'); e.status = 410; throw e; }
  const p = PROVIDERS[s.provider];
  const tok = await tokenRequest(p, { grant_type: 'refresh_token', refresh_token: s.refresh });
  s.access = tok.access_token || s.access;
  if (tok.refresh_token) s.refresh = tok.refresh_token; // некоторые провайдеры ротируют refresh
  s.expiry = Date.now() + ((tok.expires_in || 3600) * 1000);
  store[session] = s;
  saveStore(store);
  return { access: s.access, expiry: s.expiry, provider: s.provider };
}

router.get('/token', requireApiKey, async (req, res) => {
  try {
    const out = await ensureFreshAccess(String(req.query.session || ''));
    res.json({ access_token: out.access, expires_at: out.expiry, provider: out.provider });
  } catch (e) {
    res.status(e.status || 502).json({ error: e.message });
  }
});

router.post('/refresh', requireApiKey, async (req, res) => {
  try {
    const out = await ensureFreshAccess(String(req.body.session || ''));
    res.json({ access_token: out.access, expires_at: out.expiry, provider: out.provider });
  } catch (e) {
    res.status(e.status || 502).json({ error: e.message });
  }
});

// Отзыв доступа при удалении аккаунта в приложении.
//  · {session} — старая stateful-сессия: удаляется из хранилища;
//  · {rt, provider} — stateless: refresh-токен расшифровывается и отзывается
//    у провайдера, где это возможно без участия пользователя (Google —
//    oauth2.googleapis.com/revoke; у Microsoft, Яндекса, Mail.ru и Yahoo
//    публичного отзыва refresh-токена нет — токен просто перестаёт храниться
//    на телефоне и истекает сам).
router.post('/revoke', requireApiKey, async (req, res) => {
  const store = loadStore();
  if (req.body.session && store[req.body.session]) { delete store[req.body.session]; saveStore(store); }
  let revoked = false;
  const provider = String(req.body.provider || '');
  const rt = String(req.body.rt || '');
  if (rt && provider === 'google') {
    try {
      const refresh = decRt(rt);
      const r = await fetch('https://oauth2.googleapis.com/revoke', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: refresh }),
      });
      revoked = r.ok;
    } catch { /* недействительный rt или сеть — отзывать нечего */ }
  }
  res.json({ ok: true, revoked });
});

// Stateless-обновление по refresh-blob rt — основной эндпоинт для приложения.
// resource=graph (Exchange Online, 1.8.11) — токен Microsoft Graph тем же
// входом; в ответе тогда resource: 'graph' (по нему приложение отличает
// новый сервер от прежнего, который resource не знает).
router.post('/token', requireApiKey, async (req, res) => {
  try {
    const provider = String(req.body.provider || '');
    const rt = String(req.body.rt || '');
    const resource = String(req.body.resource || '');
    const p = PROVIDERS[provider];
    if (!p) return res.status(400).json({ error: 'unknown provider' });
    if (!rt) return res.status(400).json({ error: 'rt required' });
    if (resource && !(resource === 'graph' && p.graphScope)) return res.status(400).json({ error: 'unknown resource' });
    let refresh;
    try { refresh = decRt(rt); } catch { return res.status(400).json({ error: 'bad rt' }); }
    const params = { grant_type: 'refresh_token', refresh_token: refresh };
    if (resource === 'graph') params.scope = p.graphScope;
    else if (p.explicitScope) params.scope = p.scope;
    const tok = await tokenRequest(p, params);
    const out = { access_token: tok.access_token, expires_at: Date.now() + ((tok.expires_in || 3600) * 1000) };
    if (tok.refresh_token) out.rt = encRt(tok.refresh_token); // ротация refresh
    if (resource) out.resource = resource;
    res.json(out);
  } catch (e) {
    // Код AADSTS (без секретов) — приложению: по нему видно, что не так
    // (например, AADSTS65001 — нет согласия на права Graph).
    const aad = /AADSTS\d+/.exec(String((e.body || {}).error_description || ''));
    res.status(e.status === 401 ? 401 : 400).json({ error: e.message, ...(aad ? { aadsts: aad[0] } : {}) });
  }
});

app.use(BASE_PATH || '/', router);

// Неизвестный путь — в журнал (частая причина «не работает»: NPM пересылает
// без префикса /oauth или с лишним).
app.use((req, res) => res.status(404).type('text/plain').send(`not found: ${req.path}\nbase path: ${BASE_PATH || '/'}\n`));

// Необработанные ошибки — в журнал, а не молча.
app.use((err, req, res, _next) => {
  console.error(`${new Date().toISOString()} ERROR ${req.method} ${req.path}: ${err && err.stack || err}`);
  if (!res.headersSent) res.status(500).json({ error: 'internal error' });
});
process.on('unhandledRejection', (e) => console.error(`oauth-proxy: unhandledRejection: ${e && e.stack || e}`));
process.on('uncaughtException', (e) => { console.error(`oauth-proxy: uncaughtException: ${e && e.stack || e}`); process.exit(1); });

const server = app.listen(PORT, HOST, () => {
  console.log(`oauth-proxy listening on ${HOST}:${PORT} (base ${BASE_URL}, path '${BASE_PATH || '/'}')`);
  console.log(`redirect_uri для консолей провайдеров: ${CALLBACK_URL}`);
});

// Остановка по docker stop / перезапуску — без обрыва запросов на полуслове.
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`oauth-proxy: ${sig} — остановка`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 5000).unref();
  });
}
