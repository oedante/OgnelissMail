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
//   · Поиск города — по спискам мест GeoNames (CC BY 4.0), которые служба
//     держит у себя (скачивает установщик): города от 1000 жителей по
//     всему миру (cities1000), а по России — все населённые пункты и
//     аэропорты (places-RU.txt, 2.6.4). Наружу запрос не уходит вовсе.
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
//                                — [{name, display_name, lat, lon, timezone}] (как у
//                                  Nominatim format=jsonv2 — приложение
//                                  разбирает тем же кодом)
//   GET /bimi?d=<домен>[&s=<селектор>]
//                                — логотип отправителя BIMI и политика DMARC
//                                  (2.5.5: перенесено из снятого сервера
//                                  входа, bimi.js). Домены в журнал не
//                                  пишутся; кэш — в памяти (контейнер только
//                                  для чтения). У ящиков Google приложение
//                                  логотипы не запрашивает.
// ============================================================================

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { StringDecoder } = require('node:string_decoder');
const { createBimi } = require('./bimi');

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

/**
 * Строки файла по одной, без чтения целиком: населённые пункты России —
 * десятки мегабайт, а контейнеру отведено 256 МБ (2.6.4).
 */
function forEachLine(file, fn) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
  } catch {
    return;
  }
  const buf = Buffer.allocUnsafe(1 << 20);
  const dec = new StringDecoder('utf8');
  let rest = '';
  try {
    for (;;) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n === 0) break;
      const lines = (rest + dec.write(buf.subarray(0, n))).split('\n');
      rest = lines.pop();
      for (const l of lines) fn(l);
    }
    rest += dec.end();
    if (rest) fn(rest);
  } finally {
    fs.closeSync(fd);
  }
}

// Не места, а их следы: исторические, заброшенные, разрушенные, части
// других населённых пунктов.
const SKIP_CODES = new Set(['PPLH', 'PPLQ', 'PPLW', 'PPLX', 'PPLCH']);

/**
 * Файлы мест в [dir]: cities<N>.txt GeoNames (города от N жителей по миру)
 * и places-<страна>.txt — все населённые пункты и аэропорты страны (их
 * выбирает установщик из выгрузки страны; 18.11.2026: вахтовый посёлок
 * Сабетта на Ямале не находился — в cities15000 только города от 15 000
 * жителей).
 */
function placeFiles(dir) {
  let all = [];
  try {
    all = fs.readdirSync(dir);
  } catch {
    return [];
  }
  const cities = all.filter((f) => /^cities\d+\.txt$/.test(f)).sort((a, b) => parseInt(a.slice(6)) - parseInt(b.slice(6)));
  const extra = all.filter((f) => /^places-[A-Z]{2}\.txt$/.test(f)).sort();
  // Из списков городов нужен один — самый полный (cities1000 включает
  // cities15000).
  return [...cities.slice(0, 1), ...extra].map((f) => path.join(dir, f));
}

/** Мест в одном куске строк имён. */
const CHUNK = 4096;

/**
 * Места GeoNames из [dir] (+ admin1CodesASCII.txt, countryInfo.txt).
 *
 * Мест — сотни тысяч, контейнеру отведено 256 МБ, поэтому не объект на
 * место, а столбцы: имена для сравнения — строки на CHUNK мест («\nимя»
 * подряд; поиск — indexOf по ним), исходные имена для показа — такие же
 * строки, координаты, население и область — типизированные массивы.
 * Куски не склеиваются в одну строку: склейка удваивала бы память.
 */
function loadCities(dir) {
  const admin1 = new Map();
  forEachLine(path.join(dir, 'admin1CodesASCII.txt'), (l) => {
    const p = l.split('\t');
    if (p.length >= 2) admin1.set(p[0], p[1]);
  });
  const countries = new Map();
  forEachLine(path.join(dir, 'countryInfo.txt'), (l) => {
    if (!l || l.startsWith('#')) return;
    const p = l.split('\t');
    if (p.length >= 5) countries.set(p[0], p[4]);
  });
  const regionIndex = new Map();
  const regions = [];
  // Часовые пояса (2.7.1: часы городов в «Моём дне») — номер в списке.
  const zoneIndex = new Map();
  const zones = [];
  const seenIds = new Set();
  const lat = [];
  const lon = [];
  const pop = [];
  const reg = [];
  const zone = [];
  const keyStart = [];
  const nameStart = [];
  const keyChunks = [];
  const nameChunks = [];
  let keyParts = [];
  let nameParts = [];
  let keyLen = 0;
  let nameLen = 0;
  const flush = () => {
    if (keyParts.length === 0) return;
    // «\n» в конце — граница последнего имени куска.
    keyChunks.push(keyParts.join('') + '\n');
    nameChunks.push(nameParts.join(''));
    keyParts = [];
    nameParts = [];
    keyLen = 0;
    nameLen = 0;
  };
  for (const file of placeFiles(dir)) {
    forEachLine(file, (l) => {
      const p = l.split('\t');
      if (p.length < 15) return;
      if (!(p[6] === 'P' && !SKIP_CODES.has(p[7])) && p[7] !== 'AIRP') return;
      const id = Number(p[0]);
      if (seenIds.has(id)) return;
      seenIds.add(id);
      const la = Number(p[4]);
      const lo = Number(p[5]);
      if (!Number.isFinite(la) || !Number.isFinite(lo)) return;
      const names = [p[1], p[2], ...String(p[3] || '').split(',')]
        .map((n) => n.trim())
        .filter((n) => n.length > 1 && n.length < 80);
      const seen = new Set();
      let k = '';
      let n = '';
      for (const name of names) {
        const f = fold(name);
        if (!f || seen.has(f)) continue;
        seen.add(f);
        k += '\n' + f;
        n += '\n' + name;
      }
      if (!k) return;
      const regionKey = `${p[8]}.${p[10]}`;
      let r = regionIndex.get(regionKey);
      if (r === undefined) {
        r = regions.length;
        regions.push([admin1.get(regionKey), countries.get(p[8]) || p[8]].filter(Boolean).join(', '));
        regionIndex.set(regionKey, r);
      }
      const tzName = String(p[17] || '').trim();
      let z = zoneIndex.get(tzName);
      if (z === undefined) {
        z = zones.length;
        zones.push(tzName);
        zoneIndex.set(tzName, z);
      }
      lat.push(la);
      lon.push(lo);
      pop.push(Number(p[14]) || 0);
      reg.push(r);
      zone.push(z);
      keyStart.push(keyLen);
      nameStart.push(nameLen);
      keyParts.push(k);
      nameParts.push(n);
      keyLen += k.length;
      nameLen += n.length;
      if (keyParts.length >= CHUNK) flush();
    });
  }
  flush();
  return {
    length: lat.length,
    keyChunks,
    nameChunks,
    keyStart: Int32Array.from(keyStart),
    nameStart: Int32Array.from(nameStart),
    lat: Float64Array.from(lat),
    lon: Float64Array.from(lon),
    population: Int32Array.from(pop),
    region: Int32Array.from(reg),
    regions,
    zone: Int32Array.from(zone),
    zones,
  };
}

/** Номер места куска [base, end), в чьи имена попадает позиция [i]. */
function placeAt(starts, base, end, i) {
  let lo = base;
  let hi = end - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= i) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

const CYR = /[Ѐ-ӿ]/;
const LAT = /[a-z]/i;

/**
 * Найти места: сначала точное совпадение имени, потом начало имени, потом
 * слово внутри («Сабетта» — «Международный аэропорт Сабетта»); при
 * равенстве — крупнее. Имя показывается тем вариантом, который совпал
 * (по-русски, если искали по-русски).
 */
function searchCities(places, query, limit = 6) {
  const q = fold(query);
  if (q.length < 2 || !places || !places.length || !places.keyChunks) return [];
  const best = new Map();
  places.keyChunks.forEach((K, c) => {
    const base = c * CHUNK;
    const end = Math.min(base + CHUNK, places.length);
    for (let i = K.indexOf(q); i !== -1; i = K.indexOf(q, i + 1)) {
      const before = K.charCodeAt(i - 1);
      let s = 0;
      if (before === 10) s = K.charCodeAt(i + q.length) === 10 ? 3 : 2;
      else if (before === 32 && q.length >= 4) s = 1;
      if (s === 0) continue;
      const idx = placeAt(places.keyStart, base, end, i);
      if ((best.get(idx) || 0) < s) best.set(idx, s);
    }
  });
  const scored = [...best].sort((a, b) => b[1] - a[1] || places.population[b[0]] - places.population[a[0]]);
  return scored.slice(0, Math.max(1, Math.min(limit, 10))).map(([idx]) => {
    const shown = shownName(places, idx, q, query);
    const region = places.regions[places.region[idx]];
    const timezone = places.zones && places.zone ? places.zones[places.zone[idx]] : '';
    return {
      name: shown,
      display_name: [shown, region].filter(Boolean).join(', '),
      lat: places.lat[idx].toFixed(4),
      lon: places.lon[idx].toFixed(4),
      // Часовой пояс места (IANA) — для часов города в приложении (2.7.1).
      ...(timezone ? { timezone } : {}),
    };
  });
}

/** Какое из имён места показать: совпавшее, в письменности запроса. */
function shownName(places, idx, q, query) {
  const c = Math.floor(idx / CHUNK);
  const last = idx + 1 === Math.min((c + 1) * CHUNK, places.length);
  const K = places.keyChunks[c];
  const N = places.nameChunks[c];
  const keys = K.slice(places.keyStart[idx] + 1, last ? K.length - 1 : places.keyStart[idx + 1]).split('\n');
  const names = N.slice(places.nameStart[idx] + 1, last ? N.length : places.nameStart[idx + 1]).split('\n');
  const main = names[0];
  let best = 0;
  let shown = main;
  for (let i = 0; i < keys.length; i++) {
    const f = keys[i];
    const n = names[i];
    let s = 0;
    if (f === q) s = 3;
    else if (f.startsWith(q)) s = 2;
    else if (q.length >= 4 && f.includes(' ' + q)) s = 1;
    if (s > best || (s === best && s > 0 && sameScript(n, query) && !sameScript(shown, query))) {
      best = s;
      shown = s >= 2 || !sameScript(main, query) ? n : main;
    }
  }
  // Код аэропорта (SBT, USDA) — не имя: показать название.
  return /^[A-Z0-9]{3,4}$/.test(shown) ? main : shown;
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
  // Логотипы BIMI: BIMI=0 — выключены.
  const bimi = opts.bimi !== undefined ? opts.bimi : process.env.BIMI === '0' ? null : createBimi({});
  console.log(`Ogneliss Weather Proxy: городов ${cities.length}, путь ${BASE_PATH}`);
  return http.createServer(async (req, res) => {
    try {
      const u = new URL(req.url, 'http://x');
      if (req.method !== 'GET') return send(res, 405, '{"error":"method"}');
      const p = u.pathname.startsWith(BASE_PATH) ? u.pathname.slice(BASE_PATH.length) : u.pathname;
      if (p === '/healthz') {
        return send(res, 200, JSON.stringify({ ok: true, cities: cities.length, stats, ...(bimi ? { bimi: bimi.stats() } : {}) }));
      }
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
      if (p === '/bimi') {
        if (!bimi) return send(res, 404, '{"error":"disabled"}');
        const out = await bimi.lookup(u.searchParams.get('d'), u.searchParams.get('s'));
        if (out.bad) return send(res, 400, '{"error":"bad domain"}');
        if (out.transient) return send(res, 503, '{"error":"unavailable"}');
        return send(res, 200, JSON.stringify({ policy: out.policy, logo: out.logo }));
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
