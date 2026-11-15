'use strict';
// Проверки bimi.js (1.9.x): node --test server/oauth-proxy/test
// Без сети: DNS и загрузка подменяются.

const test = require('node:test');
const assert = require('node:assert');
const os = require('os');
const fs = require('fs');
const path = require('path');
const {
  createBimi, normalizeDomain, orgDomain, parseDmarc, parseBimi, sanitizeSvg, isPublicIp,
} = require('../bimi');

const LOGO = '<svg xmlns="http://www.w3.org/2000/svg" version="1.2" baseProfile="tiny-ps" viewBox="0 0 10 10">'
  + '<title>Brand</title><circle cx="5" cy="5" r="4" fill="#c00"/></svg>';

test('домен и организационный домен', () => {
  assert.strictEqual(normalizeDomain('Mail.Example.COM.'), 'mail.example.com');
  assert.strictEqual(normalizeDomain('localhost'), null);
  assert.strictEqual(normalizeDomain('пример.рф'), null);
  assert.strictEqual(normalizeDomain('1.2.3.4'), null);
  assert.strictEqual(normalizeDomain('a_b.com'), null);
  assert.strictEqual(orgDomain('news.mail.example.com'), 'example.com');
  assert.strictEqual(orgDomain('shop.example.co.uk'), 'example.co.uk');
  assert.strictEqual(orgDomain('example.com'), 'example.com');
});

test('политика DMARC', () => {
  assert.deepStrictEqual(parseDmarc([['v=DMARC1; p=reject; rua=mailto:a@b.c']]), { p: 'reject', sp: null, pct: 100 });
  assert.deepStrictEqual(parseDmarc([['v=DMARC1; p=quarantine; ', 'sp=none; pct=50']]), { p: 'quarantine', sp: 'none', pct: 50 });
  assert.strictEqual(parseDmarc([['v=spf1 -all']]), null);
  // Две записи DMARC — как будто записи нет.
  assert.strictEqual(parseDmarc([['v=DMARC1; p=reject'], ['v=DMARC1; p=none']]), null);
  assert.strictEqual(parseDmarc([['v=DMARC1; p=bogus']]).p, 'none');
});

test('запись BIMI', () => {
  assert.deepStrictEqual(parseBimi([['v=BIMI1; l=https://example.com/logo.svg; a=https://example.com/vmc.pem']]),
    { l: 'https://example.com/logo.svg', a: 'https://example.com/vmc.pem' });
  assert.strictEqual(parseBimi([['v=BIMI1; l=http://example.com/logo.svg']]).l, null);
  assert.strictEqual(parseBimi([['v=BIMI1; l=; a=;']]).l, null);
  assert.strictEqual(parseBimi([['v=DMARC1; p=reject']]), null);
});

test('очистка SVG: допустимый логотип проходит', () => {
  const out = sanitizeSvg(`<?xml version="1.0"?>\n<!-- c -->${LOGO}`);
  assert.ok(out.startsWith('<svg '));
  assert.ok(out.includes('<circle cx="5" cy="5" r="4" fill="#c00"/>'));
  assert.ok(out.includes('<title>Brand</title>'));
});

test('очистка SVG: скрипты, foreignObject, внешние ссылки, обработчики', () => {
  const evil = '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)">'
    + '<script>alert(1)</script>'
    + '<foreignObject><div xmlns="http://www.w3.org/1999/xhtml">x</div></foreignObject>'
    + '<image href="https://evil.example/x.png"/>'
    + '<use href="https://evil.example/s.svg#a"/>'
    + '<rect width="1" height="1" fill="url(https://evil.example/x)" style="fill:url(http://e/x)"/>'
    + '<path d="M0 0L1 1" fill="url(#g)" onclick="x()"/>'
    + '</svg>';
  const out = sanitizeSvg(evil);
  assert.ok(out);
  for (const bad of ['script', 'foreignObject', 'image', 'onload', 'onclick', 'evil.example', 'http://e']) {
    assert.ok(!out.includes(bad), bad);
  }
  assert.ok(out.includes('fill="url(#g)"'));
});

test('очистка SVG: отказ на DTD, CDATA, размер, кривой XML', () => {
  assert.strictEqual(sanitizeSvg('<!DOCTYPE svg [<!ENTITY x "y">]><svg><path d="M0 0"/></svg>'), null);
  assert.strictEqual(sanitizeSvg('<svg><text><![CDATA[x]]></text></svg>'), null);
  assert.strictEqual(sanitizeSvg(`<svg><path d="M0 0"/>${' '.repeat(33 * 1024)}</svg>`), null);
  assert.strictEqual(sanitizeSvg('<svg><path d="M0 0"></svg>'), null);
  assert.strictEqual(sanitizeSvg('<html><path d="M0 0"/></html>'), null);
  assert.strictEqual(sanitizeSvg('<svg><path d=M0/></svg>'), null);
  assert.strictEqual(sanitizeSvg('<svg><title>a &nbsp; b</title><path d="M0 0"/></svg>'), null);
});

test('адреса внутренней сети отвергаются', () => {
  for (const ip of ['127.0.0.1', '10.1.2.3', '192.168.0.1', '172.16.5.5', '169.254.1.1', '::1', 'fd00::1', '::ffff:127.0.0.1']) {
    assert.strictEqual(isPublicIp(ip), false, ip);
  }
  assert.strictEqual(isPublicIp('93.184.216.34'), true);
});

function fakeDns(map) {
  const calls = [];
  return {
    calls,
    resolveTxt: async (name) => {
      calls.push(name);
      if (map[name]) return map[name];
      const e = new Error('nx'); e.code = 'ENOTFOUND'; throw e;
    },
  };
}

function fakeFetch(body, extra = {}) {
  return async () => ({
    status: extra.status || 200,
    headers: new Map(Object.entries(extra.headers || {})),
    text: async () => body,
  });
}

test('служба: логотип при p=reject, кэш, поддомен по sp', async () => {
  const dns = fakeDns({
    '_dmarc.example.com': [['v=DMARC1; p=reject; sp=quarantine']],
    'default._bimi.example.com': [['v=BIMI1; l=https://cdn.example.com/l.svg']],
  });
  const b = createBimi({ resolveTxt: dns.resolveTxt, fetch: fakeFetch(LOGO), lookupHost: async () => [{ address: '93.184.216.34' }] });
  const r = await b.lookup('example.com');
  assert.strictEqual(r.policy, 'reject');
  assert.ok(r.logo.includes('<circle'));
  const n = dns.calls.length;
  await b.lookup('EXAMPLE.com');
  assert.strictEqual(dns.calls.length, n, 'второй раз — из кэша');
  const sub = await b.lookup('news.example.com');
  assert.strictEqual(sub.policy, 'quarantine');
  assert.ok(sub.logo);
  assert.strictEqual(b.stats().cacheHits, 1);
});

test('служба: p=none и pct<100 — без логотипа; внутренний адрес — без загрузки', async () => {
  const dns = fakeDns({
    '_dmarc.none.example': [['v=DMARC1; p=none']],
    '_dmarc.half.example': [['v=DMARC1; p=quarantine; pct=50']],
    '_dmarc.inner.example': [['v=DMARC1; p=reject']],
    'default._bimi.inner.example': [['v=BIMI1; l=https://intranet.example/l.svg']],
  });
  let fetched = 0;
  const b = createBimi({
    resolveTxt: dns.resolveTxt,
    fetch: async () => { fetched++; return fakeFetch(LOGO)(); },
    lookupHost: async () => [{ address: '10.0.0.5' }],
  });
  assert.deepStrictEqual(await b.lookup('none.example'), { policy: 'none', logo: null });
  assert.deepStrictEqual(await b.lookup('half.example'), { policy: 'quarantine', logo: null });
  assert.deepStrictEqual(await b.lookup('inner.example'), { policy: 'reject', logo: null });
  assert.strictEqual(fetched, 0);
  assert.strictEqual((await b.lookup('nodmarc.example')).policy, null);
  assert.strictEqual((await b.lookup('bad domain')).bad, true);
});

test('служба: переадресация на http и слишком большой файл — без логотипа', async () => {
  const dns = fakeDns({
    '_dmarc.r.example': [['v=DMARC1; p=reject']],
    'default._bimi.r.example': [['v=BIMI1; l=https://r.example/l.svg']],
    '_dmarc.big.example': [['v=DMARC1; p=reject']],
    'default._bimi.big.example': [['v=BIMI1; l=https://big.example/l.svg']],
  });
  const b = createBimi({
    resolveTxt: dns.resolveTxt,
    lookupHost: async () => [{ address: '93.184.216.34' }],
    fetch: async (url) => (url.includes('r.example')
      ? { status: 302, headers: new Map([['location', 'http://r.example/l.svg']]) }
      : { status: 200, headers: new Map([['content-length', String(64 * 1024)]]), text: async () => LOGO }),
  });
  assert.strictEqual((await b.lookup('r.example')).logo, null);
  assert.strictEqual((await b.lookup('big.example')).logo, null);
});

test('служба: сбой DNS — временный, кэш на диске переживает перезапуск', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bimi-'));
  const cachePath = path.join(dir, 'c.json');
  const failing = createBimi({
    cachePath,
    resolveTxt: async () => { const e = new Error('t'); e.code = 'ETIMEOUT'; throw e; },
  });
  assert.strictEqual((await failing.lookup('example.org')).transient, true);
  const dns = fakeDns({
    '_dmarc.example.com': [['v=DMARC1; p=reject']],
    'default._bimi.example.com': [['v=BIMI1; l=https://cdn.example.com/l.svg']],
  });
  const a = createBimi({ cachePath, resolveTxt: dns.resolveTxt, fetch: fakeFetch(LOGO), lookupHost: async () => [{ address: '93.184.216.34' }] });
  await a.lookup('example.com');
  a.save();
  const saved = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  assert.deepStrictEqual(Object.keys(saved), ['example.com|default']);
  const b = createBimi({ cachePath, resolveTxt: async () => { throw new Error('не должно быть запроса'); } });
  assert.ok((await b.lookup('example.com')).logo);
  fs.rmSync(dir, { recursive: true, force: true });
});
