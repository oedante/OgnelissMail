'use strict';
// Автотест FCM (Android, 1.9.x): служба запускается как есть, вместо Google —
// локальные заглушки OAuth и FCM. Проверяется подпись JWT ключом сервисного
// аккаунта, вид сообщения (только данные, приоритет, ttl), удаление токенов
// по UNREGISTERED / INVALID_ARGUMENT, регистрация с platform: 'android' и
// что токены iPhone без ключа APNs по-прежнему не трогаются.
//
// Запуск: npm test (или node --test test/) в server/push-relay. Сеть не нужна.

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const GOOD = `good1:${'A'.repeat(150)}`;
const GONE = `gone1:${'B'.repeat(150)}`;
const BAD = `bad01:${'C'.repeat(150)}`;
const APNS = 'ab'.repeat(32);

function listen(handler) {
  return new Promise((resolve) => {
    const srv = http.createServer(handler);
    srv.listen(0, '127.0.0.1', () => resolve(srv));
  });
}

function readBody(req) {
  return new Promise((resolve) => {
    let d = '';
    req.on('data', (c) => { d += c; });
    req.on('end', () => resolve(d));
  });
}

function fromB64url(s) {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

// Не чаще 4 раз в секунду: у службы ограничение 60 запросов в минуту.
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

test('FCM: отправка, удаление недействительных токенов, регистрация Android', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'push-relay-test-'));
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

  const oauthCalls = [];
  const oauth = await listen(async (req, res) => {
    const form = new URLSearchParams(await readBody(req));
    const [h, c, s] = (form.get('assertion') || '').split('.');
    const ok = crypto.verify('sha256', Buffer.from(`${h}.${c}`), publicKey, fromB64url(s || ''));
    oauthCalls.push({ grant: form.get('grant_type'), head: JSON.parse(fromB64url(h)), claims: JSON.parse(fromB64url(c)), ok });
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(ok ? { access_token: 'test-access', expires_in: 3600 } : { error: 'invalid_grant' }));
  });

  const sent = [];
  const fcm = await listen(async (req, res) => {
    const body = JSON.parse(await readBody(req));
    sent.push({ url: req.url, auth: req.headers.authorization, body });
    const token = body.message.token;
    res.setHeader('content-type', 'application/json');
    if (token.startsWith('gone')) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }));
    } else if (token.startsWith('bad') || token.startsWith('probe')) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: { status: 'INVALID_ARGUMENT', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'INVALID_ARGUMENT' }] } }));
    } else {
      res.end(JSON.stringify({ name: 'projects/test-project/messages/1' }));
    }
  });

  const saFile = path.join(dir, 'sa.json');
  fs.writeFileSync(saFile, JSON.stringify({
    type: 'service_account',
    project_id: 'test-project',
    client_email: 'relay@test-project.iam.gserviceaccount.com',
    private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    token_uri: `http://127.0.0.1:${oauth.address().port}/token`,
  }));

  const dataFile = path.join(dir, 'tokens.json');
  const now = Date.now();
  fs.writeFileSync(dataFile, JSON.stringify({
    v: 1,
    tokens: {
      [GOOD]: { e: 'fcm', i: 15, m: 'high', l: 0, r: now },
      [GONE]: { e: 'fcm', i: 30, m: 'normal', l: 0, r: now },
      [BAD]: { e: 'fcm', i: 60, m: 'normal', l: 0, r: now },
      [APNS]: { e: 'production', i: 15, m: 'silent', l: 0, r: now },
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
      FCM_SERVICE_ACCOUNT_FILE: saFile,
      FCM_URL: `http://127.0.0.1:${fcm.address().port}`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (c) => { out += c; });
  child.stderr.on('data', (c) => { out += c; });
  t.after(() => {
    child.kill('SIGKILL');
    oauth.close();
    fcm.close();
    fs.rmSync(dir, { recursive: true, force: true });
  });

  assert.ok(await waitFor(async () => (await request(port, 'GET', '/healthz')).status === 200),
    `служба не запустилась:\n${out}`);

  // Снаружи (через прокси — X-Real-IP) — только готовность ключей.
  const h0 = await request(port, 'GET', '/healthz', undefined, { 'x-real-ip': '203.0.113.5' });
  assert.deepStrictEqual(h0.json, { ok: true, ready: false, fcm: true });

  // Шаг отправки: все три токена FCM, iPhone — нет (ключа APNs нет).
  assert.ok(await waitFor(() => sent.length >= 3), `сигналы не отправлены:\n${out}`);
  assert.ok(sent.every((s) => s.url === '/v1/projects/test-project/messages:send'));
  assert.ok(sent.every((s) => s.auth === 'Bearer test-access'));
  assert.ok(!sent.some((s) => s.body.message.token === APNS));
  const good = sent.find((s) => s.body.message.token === GOOD).body;
  assert.deepStrictEqual(good.message.data, { w: '1' });
  assert.strictEqual(good.message.notification, undefined);
  assert.deepStrictEqual(good.message.android, { priority: 'HIGH', ttl: '900s', collapse_key: 'ogneliss-wake' });
  assert.strictEqual(good.validate_only, undefined);
  assert.strictEqual(sent.find((s) => s.body.message.token === GONE).body.message.android.priority, 'NORMAL');

  // JWT: RS256, подпись ключом аккаунта, область FCM, получатель — token_uri.
  assert.ok(oauthCalls.length >= 1);
  const call = oauthCalls[0];
  assert.ok(call.ok, 'подпись JWT не сходится');
  assert.strictEqual(call.grant, 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  assert.strictEqual(call.head.alg, 'RS256');
  assert.strictEqual(call.claims.iss, 'relay@test-project.iam.gserviceaccount.com');
  assert.strictEqual(call.claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  assert.strictEqual(call.claims.aud, `http://127.0.0.1:${oauth.address().port}/token`);
  assert.ok(call.claims.exp - call.claims.iat <= 3600);

  // UNREGISTERED и INVALID_ARGUMENT — токены удалены, хороший и iPhone остались.
  assert.ok(await waitFor(async () => (await request(port, 'GET', '/healthz')).json.tokens.total === 2), out);
  const h1 = await request(port, 'GET', '/healthz');
  assert.strictEqual(h1.json.tokens.fcm, 1);
  assert.strictEqual(h1.json.tokens.production, 1);
  assert.strictEqual(h1.json.removed, 2);
  assert.strictEqual(h1.json.keys.fcm, true);
  assert.strictEqual(h1.json.fcmProject, 'test-project');

  // Регистрация Android: регистр букв сохраняется, окружение fcm.
  const fresh = `Fresh:${'aB_-'.repeat(40)}`;
  assert.strictEqual((await request(port, 'POST', '/register', { token: fresh, platform: 'android', env: 'fcm', interval: 30, mode: 'high' })).status, 204);
  assert.strictEqual((await request(port, 'POST', '/register', { token: 'short:1', platform: 'android', interval: 30 })).status, 400);
  // Токен FCM без platform — как токен iPhone: не принимается.
  assert.strictEqual((await request(port, 'POST', '/register', { token: fresh, interval: 30 })).status, 400);
  // iPhone — как раньше.
  assert.strictEqual((await request(port, 'POST', '/register', { token: 'CD'.repeat(32), env: 'sandbox', interval: 15, mode: 'silent' })).status, 204);

  // Проверка ключа изнутри: validate_only на пробный токен.
  const probe = await request(port, 'POST', '/probe');
  assert.deepStrictEqual(probe.json.fcm, { ready: true, status: 400, reason: 'INVALID_ARGUMENT', keyOk: true });
  assert.strictEqual(sent[sent.length - 1].body.validate_only, true);

  assert.strictEqual((await request(port, 'POST', '/unregister', { token: GOOD, platform: 'android' })).status, 204);

  // Сохранение на диск — при остановке службы.
  child.kill('SIGTERM');
  await new Promise((r) => child.once('exit', r));
  const saved = JSON.parse(fs.readFileSync(dataFile, 'utf8')).tokens;
  assert.deepStrictEqual(Object.keys(saved).sort(), [APNS, 'cd'.repeat(32), fresh].sort());
  assert.strictEqual(saved[fresh].e, 'fcm');
  assert.strictEqual(saved[fresh].m, 'high');
  assert.strictEqual(saved[fresh].i, 30);
  assert.strictEqual(saved['cd'.repeat(32)].e, 'sandbox');
});
