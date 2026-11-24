'use strict';
// Ограничение частоты запросов сервера входа (безопасность, этап 2,
// 24.11.2026). Без сторонних пакетов, счётчики только в памяти — перезапуск
// их сбрасывает (как лимит /bimi и счётчик push-relay).
//
//   hit(name, key, max, windowMs) — не больше max запросов за окно на ключ
//     (адрес клиента или провайдер); ответ — сколько секунд ждать (0 — можно);
//   fail(name, key, maxFails, windowMs, pauseMs) — неудачная попытка
//     (неверный state, неверный одноразовый код); после maxFails неудач за
//     окно ключ получает паузу pauseMs;
//   paused(name, key) — сколько секунд осталось паузы (0 — паузы нет).
//
// Ключ адреса — ipKey(): IPv4 как есть, IPv6 — по сети /64 (один абонент
// обычно получает целую /64 и менял бы адрес на каждый запрос).

const MAX_KEYS = 200000;

function createLimits({ now = () => Date.now() } = {}) {
  const buckets = new Map(); // `${name}|${key}` → { n, reset }
  const fails = new Map(); // `${name}|${key}` → { n, reset, until }
  const refused = {}; // name → отказов с запуска (для /healthz)
  const pauses = {}; // name → выданных пауз с запуска

  // Защита памяти: при наплыве адресов лучше потерять счётчики, чем память.
  function roomFor(map) {
    if (map.size < MAX_KEYS) return;
    sweep();
    if (map.size >= MAX_KEYS) map.clear();
  }

  function hit(name, key, max, windowMs) {
    const k = `${name}|${key}`;
    const t = now();
    let b = buckets.get(k);
    if (!b || b.reset <= t) {
      roomFor(buckets);
      b = { n: 0, reset: t + windowMs };
      buckets.set(k, b);
    }
    b.n += 1;
    if (b.n <= max) return 0;
    refused[name] = (refused[name] || 0) + 1;
    return Math.max(1, Math.ceil((b.reset - t) / 1000));
  }

  function paused(name, key) {
    const f = fails.get(`${name}|${key}`);
    const t = now();
    return f && f.until > t ? Math.max(1, Math.ceil((f.until - t) / 1000)) : 0;
  }

  function fail(name, key, maxFails, windowMs, pauseMs) {
    const k = `${name}|${key}`;
    const t = now();
    let f = fails.get(k);
    if (f && f.until > t) return true;
    if (!f || f.reset <= t) {
      roomFor(fails);
      f = { n: 0, reset: t + windowMs, until: 0 };
      fails.set(k, f);
    }
    f.n += 1;
    if (f.n < maxFails) return false;
    f.until = t + pauseMs;
    f.n = 0;
    f.reset = f.until;
    pauses[name] = (pauses[name] || 0) + 1;
    return true;
  }

  function sweep() {
    const t = now();
    for (const [k, b] of buckets) if (b.reset <= t) buckets.delete(k);
    for (const [k, f] of fails) if (f.reset <= t && f.until <= t) fails.delete(k);
  }

  return {
    hit,
    fail,
    paused,
    sweep,
    stats: () => ({ refused: { ...refused }, pauses: { ...pauses } }),
    size: () => buckets.size + fails.size,
  };
}

// Развернуть IPv6 в 8 групп; null — не IPv6.
function expandV6(ip) {
  if (!ip.includes(':')) return null;
  let s = ip.split('%')[0].toLowerCase();
  // Хвост IPv4 (::ffff:1.2.3.4, 64:ff9b::1.2.3.4) — в две группы.
  const v4 = /(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(s);
  if (v4) {
    const n = v4.slice(1).map(Number);
    if (n.some((x) => x > 255)) return null;
    s = s.slice(0, v4.index) + ((n[0] << 8) | n[1]).toString(16) + ':' + ((n[2] << 8) | n[3]).toString(16);
  }
  const halves = s.split('::');
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(':') : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(':') : [];
  const fill = halves.length === 2 ? 8 - head.length - tail.length : 0;
  if (fill < 0) return null;
  const groups = [...head, ...Array(fill).fill('0'), ...tail];
  if (groups.length !== 8 || groups.some((g) => !/^[0-9a-f]{1,4}$/.test(g))) return null;
  return groups.map((g) => parseInt(g, 16));
}

/** Ключ адреса клиента для счётчиков: IPv4 — адрес, IPv6 — сеть /64. */
function ipKey(ip) {
  const s = String(ip || '');
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(s);
  if (mapped) return mapped[1];
  const g = expandV6(s);
  if (!g) return s;
  return g.slice(0, 4).map((x) => x.toString(16)).join(':') + '::/64';
}

module.exports = { createLimits, ipKey };
