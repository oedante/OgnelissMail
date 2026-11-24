'use strict';
// Проверка id_token (oidc.js, безопасность, этап 2): node --test
// Без сети: ключи провайдера подменяются.

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const { createIdTokenVerifier } = require('../oidc');

const CLIENT = 'client-123.apps.example';
const NOW = Date.UTC(2026, 10, 24, 9, 0, 0);
const SEC = Math.floor(NOW / 1000);

const rsa = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const rsaOther = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const ec = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });

function jwk(pub, kid, alg) {
  return { ...pub.export({ format: 'jwk' }), kid, alg, use: 'sig' };
}

function sign({ alg = 'RS256', kid = 'k1', key = rsa.privateKey, claims = {}, header = {} } = {}) {
  const h = Buffer.from(JSON.stringify({ alg, kid, typ: 'JWT', ...header })).toString('base64url');
  const c = Buffer.from(JSON.stringify({
    iss: 'https://accounts.google.com', aud: CLIENT, exp: SEC + 3600, iat: SEC, email: 'user@example.com', ...claims,
  })).toString('base64url');
  const data = Buffer.from(`${h}.${c}`);
  const sig = alg === 'ES256'
    ? crypto.sign('sha256', data, { key, dsaEncoding: 'ieee-p1363' })
    : crypto.sign('sha256', data, key);
  return `${h}.${c}.${sig.toString('base64url')}`;
}

function fakeFetch(keysByUrl, calls = []) {
  return async (url) => {
    calls.push(url);
    const keys = typeof keysByUrl === 'function' ? keysByUrl(url, calls.length) : keysByUrl[url];
    if (keys instanceof Error) throw keys;
    return {
      ok: true,
      status: 200,
      headers: { get: (n) => (n.toLowerCase() === 'cache-control' ? 'public, max-age=3600' : null) },
      json: async () => ({ keys }),
    };
  };
}

const GOOGLE = 'https://www.googleapis.com/oauth2/v3/certs';
const MS = 'https://login.microsoftonline.com/common/discovery/v2.0/keys';
const YAHOO = 'https://api.login.yahoo.com/openid/v1/certs';

function verifier(keys, calls, nowFn) {
  return createIdTokenVerifier({ fetchImpl: fakeFetch(keys, calls), now: nowFn || (() => NOW), log: () => {} });
}

test('Google: подлинный токен принят, адрес из claims', async () => {
  const v = verifier({ [GOOGLE]: [jwk(rsa.publicKey, 'k1', 'RS256')] });
  const r = await v.verify('google', sign(), CLIENT);
  assert.ok(r.claims, r.error);
  assert.strictEqual(r.claims.email, 'user@example.com');
  assert.deepStrictEqual(v.stats(), { ok: 1, rejected: 0, noKeys: 0 });
});

test('чужая подпись, чужой aud, истёкший срок, неверный издатель — не приняты', async () => {
  const v = verifier({ [GOOGLE]: [jwk(rsa.publicKey, 'k1', 'RS256')] });
  assert.strictEqual((await v.verify('google', sign({ key: rsaOther.privateKey }), CLIENT)).error, 'bad_signature');
  assert.strictEqual((await v.verify('google', sign({ claims: { aud: 'other-client' } }), CLIENT)).error, 'bad_aud');
  assert.strictEqual((await v.verify('google', sign({ claims: { exp: SEC - 3600 } }), CLIENT)).error, 'expired');
  assert.strictEqual((await v.verify('google', sign({ claims: { iss: 'https://evil.example' } }), CLIENT)).error, 'bad_iss');
  assert.strictEqual((await v.verify('google', sign({ claims: { nbf: SEC + 3600 } }), CLIENT)).error, 'not_yet_valid');
  // Подменённые claims при прежней подписи.
  const good = sign().split('.');
  const forged = Buffer.from(JSON.stringify({
    iss: 'https://accounts.google.com', aud: CLIENT, exp: SEC + 3600, email: 'boss@example.com',
  })).toString('base64url');
  assert.strictEqual((await v.verify('google', `${good[0]}.${forged}.${good[2]}`, CLIENT)).error, 'bad_signature');
});

test('alg none и HS256 не принимаются; мусор — malformed', async () => {
  const v = verifier({ [GOOGLE]: [jwk(rsa.publicKey, 'k1', 'RS256')] });
  const h = Buffer.from(JSON.stringify({ alg: 'none', kid: 'k1' })).toString('base64url');
  const c = Buffer.from(JSON.stringify({ iss: 'https://accounts.google.com', aud: CLIENT, exp: SEC + 60 })).toString('base64url');
  assert.match((await v.verify('google', `${h}.${c}.`, CLIENT)).error, /malformed|alg_none/);
  assert.match((await v.verify('google', `${h}.${c}.AAAA`, CLIENT)).error, /^alg_none/);
  const hs = Buffer.from(JSON.stringify({ alg: 'HS256', kid: 'k1' })).toString('base64url');
  const mac = crypto.createHmac('sha256', 'secret').update(`${hs}.${c}`).digest('base64url');
  assert.match((await v.verify('google', `${hs}.${c}.${mac}`, CLIENT)).error, /^alg_HS256/);
  assert.strictEqual((await v.verify('google', 'abc', CLIENT)).error, 'malformed');
  assert.strictEqual((await v.verify('google', 'a.b.c', CLIENT)).error, 'malformed');
});

test('ключ RSA с подписью ES256 в заголовке — не принят', async () => {
  const v = verifier({ [GOOGLE]: [{ ...rsa.publicKey.export({ format: 'jwk' }), kid: 'k1', use: 'sig' }] });
  const t = sign({ alg: 'ES256', key: ec.privateKey });
  assert.strictEqual((await v.verify('google', t, CLIENT)).error, 'bad_signature');
});

test('Microsoft: издатель с tid самого токена', async () => {
  const tid = '9188040d-6c67-4c5b-b112-36a304b66dad';
  const v = verifier({ [MS]: [jwk(rsa.publicKey, 'm1')] });
  const ok = sign({ kid: 'm1', claims: { iss: `https://login.microsoftonline.com/${tid}/v2.0`, tid, preferred_username: 'u@outlook.com' } });
  assert.ok((await v.verify('microsoft', ok, CLIENT)).claims);
  assert.ok((await v.verify('exchange', ok, CLIENT)).claims);
  const other = sign({ kid: 'm1', claims: { iss: `https://login.microsoftonline.com/${tid}/v2.0`, tid: '00000000-0000-0000-0000-000000000000' } });
  assert.strictEqual((await v.verify('microsoft', other, CLIENT)).error, 'bad_iss');
});

test('Yahoo: подпись ES256', async () => {
  const v = verifier({ [YAHOO]: [jwk(ec.publicKey, 'y1', 'ES256')] });
  const t = sign({ alg: 'ES256', kid: 'y1', key: ec.privateKey, claims: { iss: 'https://api.login.yahoo.com' } });
  assert.ok((await v.verify('yahoo', t, CLIENT)).claims);
});

test('новый ключ провайдера (смена kid) — ключи перечитываются, но не чаще раза в минуту', async () => {
  let t = NOW;
  const calls = [];
  const v = verifier((url, n) => (n === 1 ? [jwk(rsa.publicKey, 'k1', 'RS256')] : [jwk(rsa.publicKey, 'k1'), jwk(rsaOther.publicKey, 'k2')]), calls, () => t);
  assert.ok((await v.verify('google', sign(), CLIENT)).claims);
  // Сразу после загрузки неизвестный kid не перечитывает ключи.
  assert.strictEqual((await v.verify('google', sign({ kid: 'k2', key: rsaOther.privateKey }), CLIENT)).error, 'unknown_kid');
  assert.strictEqual(calls.length, 1);
  t += 61 * 1000;
  assert.ok((await v.verify('google', sign({ kid: 'k2', key: rsaOther.privateKey }), CLIENT)).claims);
  assert.strictEqual(calls.length, 2);
});

test('ключи недоступны — токен не принят (адрес не берётся); устаревший кэш выручает', async () => {
  let t = NOW;
  let down = true;
  const calls = [];
  const v = verifier(() => (down ? new Error('ECONNREFUSED') : [jwk(rsa.publicKey, 'k1', 'RS256')]), calls, () => t);
  const r = await v.verify('google', sign(), CLIENT);
  assert.match(r.error, /^keys_unavailable/);
  assert.strictEqual(v.stats().noKeys, 1);
  down = false;
  assert.ok((await v.verify('google', sign(), CLIENT)).claims);
  // Кэш устарел (max-age 1 ч), сеть снова недоступна — проверка по прежним ключам.
  down = true;
  t += 2 * 60 * 60 * 1000;
  assert.ok((await v.verify('google', sign({ claims: { exp: Math.floor(t / 1000) + 600 } }), CLIENT)).claims);
});

test('провайдер без ключей (Яндекс, Mail.ru) — id_token не принимается', async () => {
  const v = verifier({});
  assert.strictEqual((await v.verify('yandex', sign(), CLIENT)).error, 'no_keys_for_provider');
  assert.strictEqual((await v.verify('mailru', sign(), CLIENT)).error, 'no_keys_for_provider');
});
