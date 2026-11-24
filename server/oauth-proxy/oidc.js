'use strict';
// Проверка id_token (безопасность, этап 2, 24.11.2026): подпись по ключам
// провайдера (JWKS, кэш в памяти), издатель (iss), получатель (aud), срок
// (exp, nbf). Встроенный crypto Node, без сторонних пакетов.
//
// Из id_token сервер входа берёт адрес и имя ящика. Токен приходит напрямую
// от провайдера по TLS (обмен кода), но подпись проверяется дополнительно:
// подменённый или чужой токен (другой aud) не даст чужой адрес. Не прошёл
// проверку или ключи провайдера недоступны — адрес из токена не берётся,
// приложение узнаёт его само (userinfo) или спрашивает у человека.
//
// Провайдеры: Google, Microsoft (личные и рабочие учётные записи, Exchange
// Online), Yahoo. Яндекс и Mail.ru id_token не присылают (адрес — из
// userinfo), для них проверки нет: токен без настроек не принимается.

const crypto = require('crypto');

const MS_ISSUER = /^https:\/\/login\.microsoftonline\.com\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/v2\.0$/;

const PROVIDERS = {
  google: {
    jwks: 'https://www.googleapis.com/oauth2/v3/certs',
    iss: (iss) => iss === 'https://accounts.google.com' || iss === 'accounts.google.com',
  },
  microsoft: {
    jwks: 'https://login.microsoftonline.com/common/discovery/v2.0/keys',
    // Издатель — с организацией (tid) самого токена; у личных учётных
    // записей Microsoft tid — 9188040d-6c67-4c5b-b112-36a304b66dad.
    iss: (iss, c) => {
      const m = MS_ISSUER.exec(String(iss || ''));
      return Boolean(m) && m[1] === String(c.tid || '').toLowerCase();
    },
  },
  yahoo: {
    jwks: 'https://api.login.yahoo.com/openid/v1/certs',
    iss: (iss) => iss === 'https://api.login.yahoo.com',
  },
};
PROVIDERS.exchange = PROVIDERS.microsoft;

// Допуск расхождения часов сервера и провайдера.
const SKEW_S = 300;
// Сколько держать ключи, если провайдер не указал max-age.
const DEFAULT_TTL_MS = 6 * 60 * 60 * 1000;
const MIN_TTL_MS = 5 * 60 * 1000;
const MAX_TTL_MS = 24 * 60 * 60 * 1000;
// Неизвестный kid — ключи перечитываются, но не чаще раза в минуту.
const REFETCH_MS = 60 * 1000;

function b64json(part) {
  return JSON.parse(Buffer.from(String(part), 'base64url').toString('utf8'));
}

function createIdTokenVerifier({
  fetchImpl = (...a) => fetch(...a),
  now = () => Date.now(),
  providers = PROVIDERS,
  log = (m) => console.warn(m),
} = {}) {
  const cache = new Map(); // url → { keys: Map(kid → KeyObject), until, fetchedAt }
  const inflight = new Map(); // url → Promise
  const counts = { ok: 0, rejected: 0, noKeys: 0 };

  async function load(url) {
    if (inflight.has(url)) return inflight.get(url);
    const p = (async () => {
      const t = now();
      const r = await fetchImpl(url, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(5000) });
      if (!r.ok) throw new Error(`JWKS HTTP ${r.status}`);
      const j = await r.json();
      const keys = new Map();
      for (const jwk of Array.isArray(j && j.keys) ? j.keys : []) {
        if (!jwk || typeof jwk.kid !== 'string' || (jwk.use && jwk.use !== 'sig')) continue;
        if (jwk.kty !== 'RSA' && jwk.kty !== 'EC') continue;
        try {
          const pub = { kty: jwk.kty };
          if (jwk.kty === 'RSA') Object.assign(pub, { n: jwk.n, e: jwk.e });
          else Object.assign(pub, { crv: jwk.crv, x: jwk.x, y: jwk.y });
          keys.set(jwk.kid, { key: crypto.createPublicKey({ key: pub, format: 'jwk' }), alg: jwk.alg || '' });
        } catch (_) { /* неподдерживаемый ключ — пропускаем */ }
      }
      let ttl = DEFAULT_TTL_MS;
      const cc = /max-age=(\d+)/i.exec(String((r.headers && r.headers.get && r.headers.get('cache-control')) || ''));
      if (cc) ttl = Math.min(MAX_TTL_MS, Math.max(MIN_TTL_MS, Number(cc[1]) * 1000));
      const entry = { keys, until: t + ttl, fetchedAt: t };
      cache.set(url, entry);
      return entry;
    })();
    inflight.set(url, p);
    try { return await p; } finally { inflight.delete(url); }
  }

  // Ключ по kid: из кэша, иначе (кэш устарел или ключ новый) — перечитать.
  async function keyFor(url, kid) {
    let e = cache.get(url);
    const t = now();
    if (!e || e.until <= t || (!e.keys.has(kid) && t - e.fetchedAt >= REFETCH_MS)) {
      try {
        e = await load(url);
      } catch (err) {
        // Сеть: устаревший кэш лучше, чем никакого.
        if (!e) throw err;
        log(`oidc: ключи ${url} не обновлены (${err.message}) — проверка по прежним`);
      }
    }
    return e.keys.get(kid) || null;
  }

  function reject(error) {
    counts.rejected += 1;
    return { error };
  }

  /**
   * Проверить id_token провайдера [provider] для клиента [clientId].
   * Ответ: { claims } — токен подлинный; { error } — нет (причина для журнала).
   */
  async function verify(provider, idToken, clientId) {
    const cfg = providers[provider];
    if (!cfg) return reject('no_keys_for_provider');
    const parts = String(idToken || '').split('.');
    if (parts.length !== 3 || !parts[2]) return reject('malformed');
    let header;
    let claims;
    try {
      header = b64json(parts[0]);
      claims = b64json(parts[1]);
    } catch (_) {
      return reject('malformed');
    }
    if (!claims || typeof claims !== 'object') return reject('malformed');
    // Только асимметричная подпись: «none» и HS256 (ключ — client_secret,
    // известный и прокси) не принимаются.
    if (header.alg !== 'RS256' && header.alg !== 'ES256') return reject(`alg_${String(header.alg).slice(0, 10)}`);
    if (typeof header.kid !== 'string' || !header.kid) return reject('no_kid');

    let k;
    try {
      k = await keyFor(cfg.jwks, header.kid);
    } catch (err) {
      counts.noKeys += 1;
      return { error: `keys_unavailable (${String(err.message || err).slice(0, 80)})` };
    }
    if (!k) return reject('unknown_kid');
    if (k.alg && k.alg !== header.alg) return reject('alg_mismatch');
    const data = Buffer.from(`${parts[0]}.${parts[1]}`);
    const sig = Buffer.from(parts[2], 'base64url');
    let ok = false;
    try {
      if (header.alg === 'RS256') {
        ok = k.key.asymmetricKeyType === 'rsa' && crypto.verify('sha256', data, k.key, sig);
      } else {
        ok = k.key.asymmetricKeyType === 'ec'
          && (k.key.asymmetricKeyDetails || {}).namedCurve === 'prime256v1'
          && crypto.verify('sha256', data, { key: k.key, dsaEncoding: 'ieee-p1363' }, sig);
      }
    } catch (_) {
      ok = false;
    }
    if (!ok) return reject('bad_signature');

    const t = Math.floor(now() / 1000);
    if (!cfg.iss(claims.iss, claims)) return reject('bad_iss');
    const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (!clientId || !aud.includes(clientId)) return reject('bad_aud');
    if (aud.length > 1 && claims.azp !== undefined && claims.azp !== clientId) return reject('bad_azp');
    if (typeof claims.exp !== 'number' || claims.exp + SKEW_S < t) return reject('expired');
    if (typeof claims.nbf === 'number' && claims.nbf - SKEW_S > t) return reject('not_yet_valid');
    if (typeof claims.iat === 'number' && claims.iat - SKEW_S > t) return reject('issued_in_future');
    counts.ok += 1;
    return { claims };
  }

  return { verify, stats: () => ({ ...counts }) };
}

module.exports = { createIdTokenVerifier, PROVIDERS };
