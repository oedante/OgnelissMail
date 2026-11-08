'use strict';
// ============================================================================
// Ogneliss Weather Proxy — погода для «Моего дня» (Ogneliss Mail 1.15.1)
//
// Решение владельца 07.11.2026: условия MET Norway приняты, но данные
// пользователей сторонним сервисам не передаются. Поэтому приложение не
// обращается к MET Norway и к поиску городов напрямую: прогноз и поиск
// города идут через эту службу на сервере Ogneliss.
//
//   · Прогноз — MET Norway Locationforecast 2.0 «compact» (данные CC BY 4.0
//     и NLOD 2.0). MET видит только адрес сервера и координаты города,
//     округлённые до сотых (~1 км), — не IP и не устройство человека. Ответ
//     хранится до Expires: один запрос к MET на город для всех пользователей.
//     Условия MET соблюдаются: свой User-Agent с адресом проекта, не больше
//     4 знаков после запятой, If-Modified-Since, пауза после 429.
//   · Поиск города — по списку городов GeoNames (cities15000, CC BY 4.0),
//     который служба держит у себя (скачивает установщик). Наружу запрос
//     не уходит вовсе.
//
// Не хранится и не пишется в журнал ничего о людях: ни IP, ни координаты,
// ни поисковые строки — только счётчики (в nginx для /weather —
// access_log off).
//
// Эндпоинты (под BASE_PATH, по умолчанию /weather):
//   GET /healthz                 — {ok, cities}
//   GET /forecast?lat=..&lon=..  — тело ответа MET как есть (JSON), Expires
//                                  и Last-Modified; If-Modified-Since → 304
//   GET /search?q=..&accept-language=ru&limit=6
//                                — [{name, display_name, lat, lon}] (как у
//                                  Nominatim format=jsonv2 — приложение
//                                  разбирает тем же кодом)
// ============================================================================

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.PORT || 8789);
const HOST = process.env.HOST || '0.0.0.0';
const BASE_PATH = (process.env.BASE_PATH || '/weather').replace(/\/+$/, '');
const MET_URL = process.env.MET_URL || 'https://api.met.no/weatherapi/locationforecast/2.0/compact';
const DATA_DIR = process.env.DATA_DIR || '/data';
const CONTACT = process.env.CONTACT || 'https://github.com/oedante/OgnelissMail';
const USER_AGENT = `OgnelissMailWeatherProxy/1.0 (+${CONTACT})`;
const CACHE_MAX = Number(process.env.CACHE_MAX || 5000);
// Не чаще раза в 10 минут на город, даже если Expires раньше; без Expires —
// 30 минут.
const MIN_AGE_MS = 10 * 60 * 1000;
const DEFAULT_AGE_MS = 30 * 60 * 1000;
// Запросов с одного адреса в минуту (адрес не сохраняется — только в
// памяти, на минуту).
const PER_MINUTE = Number(process.env.PER_MINUTE || 60);

const stats = { forecast: 0, fromCache: 0, toMet: 0, met304: 0, metErrors: 0, search: 0, limited: 0 };

// ── Города GeoNames ─────────────────────────────────────────────────────────

/** Свести строку к виду для сравнения: регистр, ё/е, диакритика. */
function fold(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/ё/g, 'е')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[-‐‑–—’'`.]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function readLines(file) {
  try {
    return fs.readFileSync(file, 'utf8').split('\n');
  } catch {
    return [];
  }
}

/** cities15000.txt, admin1CodesASCII.txt, countryInfo.txt из [dir]. */
function loadCities(dir) {
  const admin1 = new Map();
  for (const l of readLines(path.join(dir, 'admin1CodesASCII.txt'))) {
    const p = l.split('\t');
    if (p.length >= 2) admin1.set(p[0], p[1]);
  }
  const countries = new Map();
  for (const l of readLines(path.join(dir, 'countryInfo.txt'))) {
    if (!l || l.startsWith('#')) continue;
    const p = l.split('\t');
    if (p.length >= 5) countries.set(p[0], p[4]);
  }
  const cities = [];
  for (const l of readLines(path.join(dir, 'cities15000.txt'))) {
    const p = l.split('\t');
    if (p.length < 15) continue;
    const lat = Number(p[4]);
    const lon = Number(p[5]);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    const names = [p[1], p[2], ...String(p[3] || '').split(',')]
      .map((n) => n.trim())
      .filter((n) => n.length > 1 && n.length < 80);
    const seen = new Set();
    const keyed = [];
    for (const n of names) {
      const f = fold(n);
      if (!f || seen.has(f)) continue;
      seen.add(f);
      keyed.push([f, n]);
    }
    cities.push({
      name: p[1],
      lat,
      lon,
      population: Number(p[14]) || 0,
      region: [admin1.get(`${p[8]}.${p[10]}`), countries.get(p[8]) || p[8]].filter(Boolean).join(', '),
      keyed,
    });
  }
  return cities;
}

const CYR = /[Ѐ-ӿ]/;
const LAT = /[a-z]/i;

/**
 * Найти города: сначала точное совпадение имени, потом начало имени; при
 * равенстве — крупнее. Имя показывается тем вариантом, который совпал
 * (по-русски, если искали по-русски).
 */
function searchCities(cities, query, limit = 6) {
  const q = fold(query);
  if (q.length < 2) return [];
  const scored = [];
  for (const c of cities) {
    let best = 0;
    let shown = c.name;
    for (const [f, n] of c.keyed) {
      let s = 0;
      if (f === q) s = 3;
      else if (f.startsWith(q + ' ') || f.startsWith(q)) s = 2;
      else if (q.length >= 4 && f.includes(' ' + q)) s = 1;
      if (s > best || (s === best && s > 0 && sameScript(n, query) && !sameScript(shown, query))) {
        best = s;
        shown = s >= 2 || !sameScript(c.name, query) ? n : c.name;
      }
    }
    if (best > 0) scored.push({ c, best, shown });
  }
  scored.sort((a, b) => b.best - a.best || b.c.population - a.c.population);
  return scored.slice(0, Math.max(1, Math.min(limit, 10))).map(({ c, shown }) => ({
    name: shown,
    display_name: [shown, c.region].filter(Boolean).join(', '),
    lat: c.lat.toFixed(4),
    lon: c.lon.toFixed(4),
  }));
}

function sameScript(a, b) {
  return CYR.test(a) === CYR.test(b) && LAT.test(a) === LAT.test(b);
}

// ── Прогноз MET Norway с кэшем ──────────────────────────────────────────────

const cache = new Map(); // ключ «lat,lon» → {body, expires, lastModified}
const inflight = new Map();
let metPauseUntil = 0;

function expiresOf(headers, now) {
  const h = headers.get('expires');
  const t = h ? Date.parse(h) : NaN;
  if (!Number.isFinite(t)) return now + DEFAULT_AGE_MS;
  return Math.max(t, now + MIN_AGE_MS);
}

function remember(key, entry) {
  cache.delete(key);
  cache.set(key, entry);
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
}

async function forecast(lat, lon) {
  const key = `${lat},${lon}`;
  const now = Date.now();
  const have = cache.get(key);
  if (have && have.expires > now) {
    stats.fromCache++;
    return have;
  }
  if (metPauseUntil > now) {
    if (have) return have;
    const e = new Error('met paused');
    e.status = 503;
    throw e;
  }
  if (inflight.has(key)) return inflight.get(key);
  const job = (async () => {
    stats.toMet++;
    const url = `${MET_URL}?lat=${lat}&lon=${lon}`;
    const headers = { 'User-Agent': USER_AGENT, 'Accept-Encoding': 'gzip, deflate' };
    if (have && have.lastModified) headers['If-Modified-Since'] = have.lastModified;
    let r;
    try {
      r = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
    } catch (e) {
      stats.metErrors++;
      if (have) return have;
      e.status = 502;
      throw e;
    }
    const t = Date.now();
    if (r.status === 304 && have) {
      stats.met304++;
      const entry = { ...have, expires: expiresOf(r.headers, t) };
      remember(key, entry);
      return entry;
    }
    if (r.status === 200 || r.status === 203) {
      if (r.status === 203) console.warn('MET Norway: 203 — версия API устарела, проверьте рассылку api-users');
      const body = await r.text();
      const entry = { body, expires: expiresOf(r.headers, t), lastModified: r.headers.get('last-modified') || null };
      remember(key, entry);
      return entry;
    }
    stats.metErrors++;
    if (r.status === 429) {
      // Условия MET: при 429 сразу снизить частоту.
      metPauseUntil = t + 10 * 60 * 1000;
      console.warn('MET Norway: 429 — пауза 10 минут');
    }
    if (have) return have;
    const e = new Error(`met ${r.status}`);
    e.status = r.status === 429 ? 503 : 502;
    throw e;
  })();
  inflight.set(key, job);
  try {
    return await job;
  } finally {
    inflight.delete(key);
  }
}

/** Координата: число в пределах, до сотых (не больше 4 знаков — условие MET). */
function coord(v, max) {
  const n = Number(v);
  if (!Number.isFinite(n) || Math.abs(n) > max) return null;
  return (Math.round(n * 100) / 100).toString();
}

// ── Ограничение частоты (в памяти, на минуту) ───────────────────────────────

const buckets = new Map();
function allowed(ip) {
  const minute = Math.floor(Date.now() / 60000);
  const b = buckets.get(ip);
  if (!b || b.minute !== minute) {
    if (buckets.size > 20000) buckets.clear();
    buckets.set(ip, { minute, n: 1 });
    return true;
  }
  b.n++;
  return b.n <= PER_MINUTE;
}

// ── HTTP ────────────────────────────────────────────────────────────────────

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'private, no-transform',
    'X-Content-Type-Options': 'nosniff',
    ...headers,
  });
  res.end(body);
}

function createServer(opts = {}) {
  const cities = opts.cities || loadCities(opts.dataDir || DATA_DIR);
  console.log(`Ogneliss Weather Proxy: городов ${cities.length}, путь ${BASE_PATH}`);
  return http.createServer(async (req, res) => {
    try {
      const u = new URL(req.url, 'http://x');
      if (req.method !== 'GET') return send(res, 405, '{"error":"method"}');
      const p = u.pathname.startsWith(BASE_PATH) ? u.pathname.slice(BASE_PATH.length) : u.pathname;
      if (p === '/healthz') return send(res, 200, JSON.stringify({ ok: true, cities: cities.length, stats }));
      const ip = String(req.headers['x-real-ip'] || req.socket.remoteAddress || '');
      if (!allowed(ip)) {
        stats.limited++;
        return send(res, 429, '{"error":"rate"}', { 'Retry-After': '60' });
      }
      if (p === '/forecast') {
        stats.forecast++;
        const lat = coord(u.searchParams.get('lat'), 90);
        const lon = coord(u.searchParams.get('lon'), 180);
        if (lat == null || lon == null) return send(res, 400, '{"error":"coords"}');
        const f = await forecast(lat, lon);
        const lm = f.lastModified;
        const ims = req.headers['if-modified-since'];
        const headers = { Expires: new Date(f.expires).toUTCString(), ...(lm ? { 'Last-Modified': lm } : {}) };
        if (lm && ims && ims === lm) {
          res.writeHead(304, headers);
          return res.end();
        }
        return send(res, 200, f.body, headers);
      }
      if (p === '/search') {
        stats.search++;
        const q = (u.searchParams.get('q') || '').slice(0, 80);
        const limit = Number(u.searchParams.get('limit') || 6) || 6;
        return send(res, 200, JSON.stringify(searchCities(cities, q, limit)));
      }
      return send(res, 404, '{"error":"not found"}');
    } catch (e) {
      return send(res, e.status || 500, JSON.stringify({ error: 'unavailable' }));
    }
  });
}

if (require.main === module) {
  createServer().listen(PORT, HOST);
  // Счётчики — раз в час, без адресов и координат.
  setInterval(() => console.log('Погода за час:', JSON.stringify(stats)), 3600 * 1000).unref();
}

module.exports = { createServer, searchCities, loadCities, fold, coord };
