'use strict';
// ============================================================================
// BIMI — логотипы проверенных отправителей (1.9.x, просьба владельца
// 31.10.2026). Приложение спрашивает GET /bimi?d=<домен>, сервер сам читает
// DNS (_dmarc и <селектор>._bimi), скачивает SVG по HTTPS и очищает его по
// строгому списку разрешённого (профиль SVG Tiny PS). DNS — только с этого
// сервера: домены отправителей не уходят к третьим лицам (публичный DoH не
// используется, решено с владельцем 31.10.2026).
//
// Ответ: {policy: "reject|quarantine|none"|null, logo: "<svg…>"|null}.
// Домены в журнал не пишутся — только счётчики (как у push-relay).
// Зависимостей нет: dns, fs, встроенный fetch (Node.js 18+).
// ============================================================================

const dnsp = require('dns').promises;
const fs = require('fs');
const path = require('path');
const net = require('net');

const MAX_SVG_BYTES = 32 * 1024;
const FETCH_TIMEOUT_MS = 5000;
const POSITIVE_TTL_MS = 7 * 24 * 3600 * 1000;
const NEGATIVE_TTL_MS = 24 * 3600 * 1000;
// Временный сбой DNS или сайта — не повод на сутки остаться без логотипа.
const TRANSIENT_TTL_MS = 10 * 60 * 1000;

// ── Домены ──

// Домен из адреса отправителя: только ASCII (IDN — в punycode), метки по
// правилам DNS. Иначе null — запрос не выполняется.
function normalizeDomain(d) {
  const s = String(d || '').trim().toLowerCase().replace(/\.$/, '');
  if (!s || s.length > 253) return null;
  const labels = s.split('.');
  if (labels.length < 2) return null;
  for (const l of labels) {
    if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(l)) return null;
  }
  if (/^\d+$/.test(labels[labels.length - 1])) return null; // IP-адрес
  return s;
}

function normalizeSelector(s) {
  const v = String(s || '').trim().toLowerCase();
  if (!v) return 'default';
  return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(v) ? v : null;
}

// Организационный домен — упрощённо, без полного Public Suffix List: две
// последние метки, три — для частых составных зон (co.uk, com.au, com.ru…).
const MULTI_SUFFIXES = new Set([
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'com.au', 'net.au', 'org.au', 'co.nz', 'co.jp', 'ne.jp',
  'or.jp', 'co.kr', 'com.br', 'com.cn', 'com.tr', 'com.mx', 'com.ar', 'co.in', 'co.za', 'com.sg', 'com.hk',
  'com.tw', 'co.il', 'com.ua', 'com.ru', 'msk.ru', 'spb.ru', 'com.pl', 'co.id', 'com.my', 'com.vn',
]);
function orgDomain(domain) {
  const labels = domain.split('.');
  if (labels.length <= 2) return domain;
  const last2 = labels.slice(-2).join('.');
  const n = MULTI_SUFFIXES.has(last2) ? 3 : 2;
  return labels.slice(-n).join('.');
}

// ── Разбор записей DNS ──

// Теги записи вида «k=v; k=v» (RFC 7489, раздел 6.4). Ключи — без учёта
// регистра, значения — как есть.
function parseTags(record) {
  const out = {};
  for (const part of String(record).split(';')) {
    const i = part.indexOf('=');
    if (i <= 0) continue;
    const k = part.slice(0, i).trim().toLowerCase();
    if (!(k in out)) out[k] = part.slice(i + 1).trim();
  }
  return out;
}

// TXT приходит кусками по 255 байт: куски одной записи склеиваются.
function joinTxt(txts) {
  return (txts || []).map((r) => (Array.isArray(r) ? r.join('') : String(r)));
}

// DMARC: ровно одна запись «v=DMARC1; p=…». Несколько записей — как будто
// записи нет (RFC 7489, 6.6.3). Неизвестное p — none.
function parseDmarc(txts) {
  const recs = joinTxt(txts).filter((r) => /^v\s*=\s*DMARC1\s*(;|$)/i.test(r.trim()));
  if (recs.length !== 1) return null;
  const t = parseTags(recs[0]);
  const pol = (v) => (['none', 'quarantine', 'reject'].includes(String(v || '').toLowerCase())
    ? String(v).toLowerCase() : null);
  const pct = /^\d{1,3}$/.test(t.pct || '') ? Math.min(100, parseInt(t.pct, 10)) : 100;
  return { p: pol(t.p) || 'none', sp: pol(t.sp), pct };
}

// BIMI: «v=BIMI1; l=<https-адрес SVG>; a=<адрес VMC>». Пустой l — домен
// отказался от логотипа.
function parseBimi(txts) {
  const recs = joinTxt(txts).filter((r) => /^v\s*=\s*BIMI1\s*(;|$)/i.test(r.trim()));
  if (recs.length !== 1) return null;
  const t = parseTags(recs[0]);
  const first = String(t.l || '').split(',')[0].trim();
  let l = null;
  if (first) {
    try {
      const u = new URL(first);
      if (u.protocol === 'https:' && !u.username && !u.password) l = u.toString();
    } catch { /* не адрес */ }
  }
  const a = String(t.a || '').trim();
  return { l, a: /^https:\/\//i.test(a) ? a : null };
}

// ── Очистка SVG (SVG Tiny PS: без скриптов, внешних ссылок, foreignObject) ──

const SVG_ELEMENTS = new Set([
  'svg', 'g', 'defs', 'title', 'desc', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon',
  'linearGradient', 'radialGradient', 'stop', 'use', 'text', 'tspan', 'solidColor',
]);
const TEXT_ELEMENTS = new Set(['title', 'desc', 'text', 'tspan']);
const SVG_ATTRS = new Set([
  'xmlns', 'xmlns:xlink', 'version', 'baseProfile', 'viewBox', 'width', 'height', 'preserveAspectRatio',
  'id', 'x', 'y', 'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'fx', 'fy', 'd', 'points',
  'transform', 'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity',
  'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'stroke-dasharray', 'stroke-dashoffset',
  'opacity', 'color', 'display', 'visibility', 'offset', 'stop-color', 'stop-opacity', 'gradientUnits',
  'gradientTransform', 'spreadMethod', 'href', 'xlink:href', 'font-family', 'font-size', 'font-weight',
  'font-style', 'text-anchor', 'clip-rule', 'xml:space', 'solid-color', 'solid-opacity', 'vector-effect',
  'style',
]);
const MAX_DEPTH = 64;
const MAX_ELEMENTS = 4000;

function decodeEntities(s) {
  // Только сущности XML и числовые; прочие (&nbsp; из HTML, свои из DTD)
  // — ошибка: DTD не разбираем вовсе.
  // «&» без сущности после него — тоже ошибка (так требует XML).
  if (/&(?!(#x[0-9a-fA-F]{1,6}|#\d{1,7}|[A-Za-z][A-Za-z0-9]*);)/.test(s)) return null;
  let bad = false;
  const out = String(s).replace(/&(#x[0-9a-fA-F]{1,6}|#\d{1,7}|[A-Za-z][A-Za-z0-9]*);/g, (m, e) => {
    if (e === 'amp') return '&';
    if (e === 'lt') return '<';
    if (e === 'gt') return '>';
    if (e === 'quot') return '"';
    if (e === 'apos') return "'";
    if (e[0] === '#') {
      const n = e[1] === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      if (!(n > 0 && n <= 0x10ffff) || (n >= 0xd800 && n <= 0xdfff)) { bad = true; return ''; }
      return String.fromCodePoint(n);
    }
    bad = true;
    return '';
  });
  return bad ? null : out;
}

function escapeXml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Значение атрибута безопасно: ссылки — только внутрь файла (#id и url(#id)),
// никаких схем (javascript:, data:), выражений и обратных косых.
function safeAttrValue(name, v) {
  if (/[<\\]/.test(v)) return false;
  if (/javascript:|vbscript:|data:|expression\s*\(|@import|behavior\s*:|-moz-binding/i.test(v)) return false;
  const urls = v.match(/url\s*\(([^)]*)\)?/gi) || [];
  for (const u of urls) {
    if (!/^url\s*\(\s*['"]?#[A-Za-z_][\w.:-]*['"]?\s*\)$/i.test(u)) return false;
  }
  if (name === 'href' || name === 'xlink:href') return /^#[A-Za-z_][\w.:-]*$/.test(v);
  if (name === 'xmlns') return v === 'http://www.w3.org/2000/svg';
  if (name === 'xmlns:xlink') return v === 'http://www.w3.org/1999/xlink';
  return true;
}

// Возвращает очищенный SVG или null. Элементы вне списка выбрасываются
// вместе с содержимым, атрибуты вне списка — по одному. DOCTYPE со своими
// сущностями, CDATA, незакрытые теги, лишняя вложенность — отказ.
function sanitizeSvg(input) {
  const src = String(input || '').replace(/^﻿/, '');
  if (!src || Buffer.byteLength(src, 'utf8') > MAX_SVG_BYTES) return null;
  let i = 0;
  const out = [];
  const stack = []; // {name, keep}
  let dropDepth = 0; // >0 — внутри выброшенного элемента
  let elements = 0;
  let root = false;
  const n = src.length;
  while (i < n) {
    const lt = src.indexOf('<', i);
    const textEnd = lt < 0 ? n : lt;
    if (textEnd > i) {
      const raw = src.slice(i, textEnd);
      const top = stack[stack.length - 1];
      if (dropDepth === 0 && top && TEXT_ELEMENTS.has(top.name) && raw.trim()) {
        const t = decodeEntities(raw);
        if (t == null) return null;
        out.push(escapeXml(t));
      } else if (raw.trim() && !top) {
        return null; // текст вне корня
      }
      i = textEnd;
      continue;
    }
    if (src.startsWith('<?', i)) {
      const e = src.indexOf('?>', i + 2);
      if (e < 0) return null;
      i = e + 2; // объявление XML и инструкции обработки — выбрасываются
      continue;
    }
    if (src.startsWith('<!--', i)) {
      const e = src.indexOf('-->', i + 4);
      if (e < 0) return null;
      i = e + 3;
      continue;
    }
    if (src.startsWith('<![CDATA[', i)) return null;
    if (/^<!DOCTYPE/i.test(src.slice(i, i + 9))) {
      const e = src.indexOf('>', i);
      if (e < 0 || src.slice(i, e).includes('[')) return null; // свои сущности — отказ
      i = e + 1;
      continue;
    }
    if (src.startsWith('</', i)) {
      const e = src.indexOf('>', i);
      if (e < 0) return null;
      const name = src.slice(i + 2, e).trim();
      const top = stack.pop();
      if (!top || top.name !== name) return null;
      if (top.keep) out.push(`</${name}>`);
      else dropDepth--;
      i = e + 1;
      continue;
    }
    // Открывающий тег.
    const m = /^<([A-Za-z_][\w:.-]*)/.exec(src.slice(i, i + 256));
    if (!m) return null;
    const name = m[1];
    let j = i + m[0].length;
    const attrs = [];
    let selfClose = false;
    for (;;) {
      while (j < n && /\s/.test(src[j])) j++;
      if (j >= n) return null;
      if (src.startsWith('/>', j)) { selfClose = true; j += 2; break; }
      if (src[j] === '>') { j++; break; }
      const am = /^([^\s=/>]+)\s*=\s*(["'])/.exec(src.slice(j, j + 256));
      if (!am) return null; // атрибуты без кавычек и без значения — отказ
      const q = am[2];
      const vs = j + am[0].length;
      const ve = src.indexOf(q, vs);
      if (ve < 0) return null;
      const rawV = src.slice(vs, ve);
      if (rawV.includes('<')) return null;
      const v = decodeEntities(rawV);
      if (v == null) return null;
      attrs.push([am[1], v]);
      j = ve + 1;
    }
    if (++elements > MAX_ELEMENTS) return null;
    if (!root) {
      if (name !== 'svg') return null;
      root = true;
    } else if (stack.length === 0) {
      return null; // второй корень
    }
    const keep = dropDepth === 0 && SVG_ELEMENTS.has(name) && (name !== 'svg' || stack.length === 0);
    if (keep) {
      const kept = [];
      const seen = new Set();
      for (const [an, av] of attrs) {
        if (seen.has(an)) return null;
        seen.add(an);
        if (!SVG_ATTRS.has(an) || !safeAttrValue(an, av)) continue;
        kept.push(` ${an}="${escapeXml(av)}"`);
      }
      out.push(`<${name}${kept.join('')}${selfClose ? '/>' : '>'}`);
    }
    if (!selfClose) {
      if (stack.length >= MAX_DEPTH) return null;
      stack.push({ name, keep });
      if (!keep) dropDepth++;
    }
    i = j;
  }
  if (!root || stack.length) return null;
  const svg = out.join('');
  return /<(path|rect|circle|ellipse|polygon|polyline|line|text|use)\b/.test(svg) ? svg : null;
}

// ── Адрес логотипа: только HTTPS и не внутренняя сеть ──

function isPublicIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    if (a === 10 || a === 127 || a === 0 || a >= 224) return false;
    if (a === 169 && b === 254) return false;
    if (a === 172 && b >= 16 && b <= 31) return false;
    if (a === 192 && b === 168) return false;
    if (a === 100 && b >= 64 && b <= 127) return false;
    return true;
  }
  if (net.isIPv6(ip)) {
    const v = ip.toLowerCase();
    if (v === '::1' || v === '::') return false;
    if (/^(fc|fd|fe8|fe9|fea|feb|ff)/.test(v)) return false;
    const m = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(v);
    if (m) return isPublicIp(m[1]);
    return true;
  }
  return false;
}

// ── Служба: кэш, DNS, загрузка ──

function createBimi(opts = {}) {
  const resolver = new dnsp.Resolver({ timeout: 3000, tries: 2 });
  const resolveTxt = opts.resolveTxt || ((name) => resolver.resolveTxt(name));
  const lookupHost = opts.lookupHost || ((host) => dnsp.lookup(host, { all: true }));
  const doFetch = opts.fetch || fetch;
  const now = opts.now || Date.now;
  const cachePath = opts.cachePath || '';
  const maxEntries = opts.maxEntries || 1000;

  const cache = new Map(); // ключ «домен|селектор» → {until, v, disk}
  const inflight = new Map();
  const stats = { requests: 0, cacheHits: 0, lookups: 0, logos: 0, failures: 0 };
  let dirty = false;
  let diskOk = Boolean(cachePath);

  if (cachePath) {
    try {
      const saved = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
      const t = now();
      for (const [k, e] of Object.entries(saved || {})) {
        if (e && e.until > t && e.v) cache.set(k, { until: e.until, v: e.v, disk: true });
      }
    } catch { /* файла ещё нет */ }
  }

  function put(key, v, ttl, disk = true) {
    cache.delete(key);
    cache.set(key, { until: now() + ttl, v, disk });
    while (cache.size > maxEntries) cache.delete(cache.keys().next().value);
    if (disk) dirty = true;
  }

  function save() {
    if (!dirty || !diskOk) return;
    dirty = false;
    try {
      const obj = {};
      for (const [k, e] of cache) if (e.disk) obj[k] = { until: e.until, v: e.v };
      fs.mkdirSync(path.dirname(cachePath), { recursive: true });
      const tmp = `${cachePath}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify(obj), { mode: 0o600 });
      fs.renameSync(tmp, cachePath);
    } catch (e) {
      // Контейнер только для чтения — кэш остаётся в памяти.
      diskOk = false;
      console.warn(`oauth-proxy: кэш BIMI не записан на диск (${e.code || e.message}) — только в памяти`);
    }
  }

  async function txt(name) {
    try {
      return await resolveTxt(name);
    } catch (e) {
      if (e && (e.code === 'ENOTFOUND' || e.code === 'ENODATA' || e.code === 'NXDOMAIN')) return [];
      const err = new Error('dns');
      err.transient = true;
      throw err;
    }
  }

  async function dmarcFor(domain) {
    const own = parseDmarc(await txt(`_dmarc.${domain}`));
    if (own) return own.p === 'none' ? { policy: 'none', pct: own.pct } : { policy: own.p, pct: own.pct };
    const org = orgDomain(domain);
    if (org === domain) return null;
    const parent = parseDmarc(await txt(`_dmarc.${org}`));
    if (!parent) return null;
    // Поддомен: действует sp, если задано (RFC 7489, 6.3).
    return { policy: parent.sp || parent.p, pct: parent.pct };
  }

  async function bimiFor(domain, selector) {
    const own = parseBimi(await txt(`${selector}._bimi.${domain}`));
    if (own) return own;
    const org = orgDomain(domain);
    return org === domain ? null : parseBimi(await txt(`${selector}._bimi.${org}`));
  }

  // Скачать SVG: HTTPS, 5 секунд, не больше 32 КБ, переадресация — только
  // на HTTPS и не дальше трёх шагов, адрес — не внутренняя сеть.
  async function fetchSvg(url) {
    let u = new URL(url);
    for (let hop = 0; hop < 4; hop++) {
      if (u.protocol !== 'https:') return null;
      const host = u.hostname.replace(/^\[|\]$/g, '');
      const addrs = net.isIP(host) ? [{ address: host }] : await lookupHost(host);
      if (!addrs.length || !addrs.every((a) => isPublicIp(a.address))) return null;
      const r = await doFetch(u.toString(), {
        redirect: 'manual',
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
        headers: { Accept: 'image/svg+xml' },
      });
      if (r.status >= 300 && r.status < 400) {
        const loc = r.headers.get('location');
        if (!loc) return null;
        u = new URL(loc, u);
        continue;
      }
      if (r.status !== 200) return null;
      const len = parseInt(r.headers.get('content-length') || '0', 10);
      if (len > MAX_SVG_BYTES) return null;
      return readCapped(r);
    }
    return null;
  }

  async function readCapped(r) {
    if (!r.body || !r.body.getReader) {
      const t = await r.text();
      return Buffer.byteLength(t, 'utf8') > MAX_SVG_BYTES ? null : t;
    }
    const reader = r.body.getReader();
    const chunks = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_SVG_BYTES) { try { await reader.cancel(); } catch { /* */ } return null; }
      chunks.push(Buffer.from(value));
    }
    return Buffer.concat(chunks).toString('utf8');
  }

  async function resolve(domain, selector) {
    stats.lookups++;
    const dmarc = await dmarcFor(domain);
    const policy = dmarc ? dmarc.policy : null;
    // BIMI требует строгую политику на все письма: quarantine/reject, pct=100.
    if (!dmarc || !['quarantine', 'reject'].includes(policy) || dmarc.pct < 100) {
      return { policy, logo: null };
    }
    const rec = await bimiFor(domain, selector);
    if (!rec || !rec.l) return { policy, logo: null };
    let raw;
    try {
      raw = await fetchSvg(rec.l);
    } catch {
      const err = new Error('fetch');
      err.transient = true;
      throw err;
    }
    const logo = raw ? sanitizeSvg(raw) : null;
    if (logo) stats.logos++;
    return { policy, logo };
  }

  async function lookup(d, s) {
    stats.requests++;
    const domain = normalizeDomain(d);
    const selector = normalizeSelector(s);
    if (!domain || !selector) return { policy: null, logo: null, bad: true };
    const key = `${domain}|${selector}`;
    const hit = cache.get(key);
    if (hit && hit.until > now()) { stats.cacheHits++; return hit.v; }
    if (inflight.has(key)) return inflight.get(key);
    const p = (async () => {
      try {
        const v = await resolve(domain, selector);
        put(key, v, v.logo ? POSITIVE_TTL_MS : NEGATIVE_TTL_MS);
        return v;
      } catch (e) {
        stats.failures++;
        const v = { policy: null, logo: null };
        put(key, v, TRANSIENT_TTL_MS, false);
        return { ...v, transient: true };
      } finally {
        inflight.delete(key);
      }
    })();
    inflight.set(key, p);
    return p;
  }

  const timer = cachePath ? setInterval(save, 60 * 1000) : null;
  if (timer && timer.unref) timer.unref();

  return {
    lookup,
    save,
    stats: () => ({ ...stats, cached: cache.size }),
  };
}

module.exports = {
  createBimi,
  normalizeDomain,
  normalizeSelector,
  orgDomain,
  parseDmarc,
  parseBimi,
  sanitizeSvg,
  isPublicIp,
  MAX_SVG_BYTES,
};
