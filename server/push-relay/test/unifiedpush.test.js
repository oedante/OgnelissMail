'use strict';
// Автотест UnifiedPush (Android без сервисов Google, 1.10.x): служба
// запускается как есть, вместо распространителя — локальная заглушка Web Push.
// Проверяется регистрация с ключами, зашифрованный сигнал (расшифровка
// ключом «телефона»), подпись VAPID, удаление адреса по 410 и снятие
// регистрации.
//
// Запуск: npm test (или node --test) в server/push-relay. Сеть не нужна.

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const wp = require('../webpush');

function listen(handler) {
  return new Promise((resolve) => {
    const srv = http.createServer(handler);
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

function readBody(req) {
  return new Promise((resolve) => {
    const parts = [];
    req.on('data', (c) => parts.push(c));
    req.on('end', () => resolve(Buffer.concat(parts)));
  });
}

async function waitFor(fn, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try {
      if (await fn()) return true;
    } catch (_) { /* служба ещё не готова */ }
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
}

async function request(port, method, p, body, headers = {}) {
  const r = await fetch(`http://127.0.0.1:${port}/push${p}`, {
    method,
    headers: body ? { 'content-type': 'application/json', ...headers } : headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  return { status: r.status, json: text ? JSON.parse(text) : null };
}

test('UnifiedPush: регистрация, зашифрованный сигнал с VAPID, удаление по 410', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'push-relay-up-'));
  const vapidFile = path.join(dir, 'vapid.pem');
  fs.writeFileSync(vapidFile, wp.generateVapidPem());

  // «Телефон»: ключи Web Push установки.
  const phone = crypto.createECDH('prime256v1');
  phone.generateKeys();
  const p256dh = wp.b64url(phone.getPublicKey());
  const auth = wp.b64url(crypto.randomBytes(16));

  const got = [];
  const distributor = await listen(async (req, res) => {
    const body = await readBody(req);
    got.push({ url: req.url, headers: req.headers, body });
    res.statusCode = req.url.startsWith('/gone') ? 410 : 201;
    res.end();
  });
  const base = `http://127.0.0.1:${distributor.address().port}`;

  // Две установки, давно не получавшие сигнала (l: 0) — сигнал сразу:
  // рабочая и «удалённая» (распространитель отвечает 410).
  const dataFile = path.join(dir, 'tokens.json');
  const now = Date.now();
  fs.writeFileSync(dataFile, JSON.stringify({
    v: 1,
    tokens: {
      [`${base}/up1?x=1`]: { e: 'up', i: 15, m: 'normal', k: p256dh, a: auth, l: 0, r: now },
      [`${base}/gone1`]: { e: 'up', i: 30, m: 'high', k: p256dh, a: auth, l: 0, r: now },
    },
  }));

  const port = 20000 + Math.floor(Math.random() * 20000);
  const child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: {
      PATH: process.env.PATH,
      PORT: String(port),
      HOST: '127.0.0.1',
      DATA_FILE: dataFile,
      TICK_MS: '1000',
      VAPID_PRIVATE_KEY_FILE: vapidFile,
      UP_ALLOW_LOCAL_FOR_TESTS: '1',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (c) => { out += c; });
  child.stderr.on('data', (c) => { out += c; });
  t.after(() => {
    child.kill('SIGKILL');
    distributor.close();
    fs.rmSync(dir, { recursive: true, force: true });
  });

  assert.ok(await waitFor(async () => (await request(port, 'GET', '/healthz')).status === 200), out);

  // Открытый ключ VAPID для приложения.
  const v = await request(port, 'GET', '/vapid');
  assert.strictEqual(v.status, 200);
  assert.strictEqual(wp.unb64url(v.json.key).length, 65);

  // Неверные ключи и адрес — отказ.
  assert.strictEqual((await request(port, 'POST', '/register',
    { platform: 'unifiedpush', token: `${base}/up1`, p256dh: 'x', auth })).status, 400);
  assert.strictEqual((await request(port, 'POST', '/register',
    { platform: 'unifiedpush', token: 'ftp://example.org/x', p256dh, auth })).status, 400);

  // Регистрация новой установки принимается (первый сигнал — через
  // интервал, в тесте его не ждём).
  const reg = await request(port, 'POST', '/register',
    { platform: 'unifiedpush', token: `${base}/up2`, p256dh, auth, interval: 30, mode: 'normal' });
  assert.strictEqual(reg.status, 204, JSON.stringify(reg.json));

  assert.ok(await waitFor(() => got.length >= 2, 15000), `сигналов нет: ${out}`);

  const ok = got.find((g) => g.url === '/up1?x=1');
  assert.ok(ok, JSON.stringify(got.map((g) => g.url)));
  assert.strictEqual(ok.headers['content-encoding'], 'aes128gcm');
  assert.strictEqual(ok.headers.ttl, '900');
  assert.strictEqual(ok.headers.urgency, 'normal');
  // Расшифровка ключом «телефона».
  const plain = wp.decrypt(ok.body, wp.b64url(phone.getPrivateKey()), p256dh, auth);
  assert.strictEqual(plain.toString(), '{"w":"1"}');
  // Подпись VAPID — открытым ключом из /vapid.
  const m = /^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/.exec(ok.headers.authorization || '');
  assert.ok(m, ok.headers.authorization);
  assert.strictEqual(m[4], v.json.key);
  const jwk = { kty: 'EC', crv: 'P-256', x: wp.b64url(wp.unb64url(v.json.key).subarray(1, 33)), y: wp.b64url(wp.unb64url(v.json.key).subarray(33)) };
  assert.ok(crypto.verify('sha256', Buffer.from(`${m[1]}.${m[2]}`),
    { key: crypto.createPublicKey({ key: jwk, format: 'jwk' }), dsaEncoding: 'ieee-p1363' }, wp.unb64url(m[3])));
  assert.strictEqual(JSON.parse(wp.unb64url(m[2]).toString()).aud, base);

  // Адрес с ответом 410 — удалён; рабочий — остался.
  assert.ok(await waitFor(async () => {
    const h = JSON.parse(await (await fetch(`http://127.0.0.1:${port}/push/healthz`)).text());
    return h.tokens && h.tokens.up === 2;
  }), out);

  // Снятие регистрации.
  assert.strictEqual((await request(port, 'POST', '/unregister', { platform: 'unifiedpush', token: `${base}/up1?x=1` })).status, 204);
  assert.ok(await waitFor(async () => {
    const h = JSON.parse(await (await fetch(`http://127.0.0.1:${port}/push/healthz`)).text());
    return h.tokens && h.tokens.up === 1;
  }), out);
});
