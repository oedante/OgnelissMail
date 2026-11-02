'use strict';
// Web Push для UnifiedPush (1.10.x): шифрование по примеру из RFC 8291
// (приложение A), VAPID, проверка адресов.

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const wp = require('../webpush');

// RFC 8291, приложение A.
const RFC = {
  plaintext: 'When I grow up, I want to be a watermelon',
  asPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  asPublic: 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  uaPrivate: 'q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94',
  uaPublic: 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  auth: 'BTBZMqHH6r4Tts7J_aSIgg',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  message:
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK' +
    '6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};

test('шифрование совпадает с примером RFC 8291', () => {
  const out = wp.encrypt(RFC.plaintext, RFC.uaPublic, RFC.auth, { salt: RFC.salt, asPrivate: RFC.asPrivate });
  assert.strictEqual(wp.b64url(out), RFC.message);
});

test('пример RFC расшифровывается', () => {
  const plain = wp.decrypt(wp.unb64url(RFC.message), RFC.uaPrivate, RFC.uaPublic, RFC.auth);
  assert.strictEqual(plain.toString(), RFC.plaintext);
});

test('свой ключ получателя: туда и обратно', () => {
  const ecdh = crypto.createECDH('prime256v1');
  ecdh.generateKeys();
  const pub = wp.b64url(ecdh.getPublicKey());
  const auth = wp.b64url(crypto.randomBytes(16));
  const msg = wp.encrypt('{"w":"1"}', pub, auth);
  assert.strictEqual(wp.decrypt(msg, wp.b64url(ecdh.getPrivateKey()), pub, auth).toString(), '{"w":"1"}');
});

test('VAPID: подпись проверяется открытым ключом', () => {
  const vapid = wp.loadVapid(wp.generateVapidPem());
  assert.strictEqual(wp.unb64url(vapid.publicKey).length, 65);
  const h = wp.vapidAuthorization('https://ntfy.example.org/upABC?up=1', vapid, 'https://www.ogneliss.ru', 1e12);
  const m = /^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/.exec(h);
  assert.ok(m, h);
  const claims = JSON.parse(wp.unb64url(m[2]).toString());
  assert.strictEqual(claims.aud, 'https://ntfy.example.org');
  assert.strictEqual(claims.sub, 'https://www.ogneliss.ru');
  const ok = crypto.verify('sha256', Buffer.from(`${m[1]}.${m[2]}`),
    { key: crypto.createPublicKey(vapid.key), dsaEncoding: 'ieee-p1363' }, wp.unb64url(m[3]));
  assert.ok(ok);
  assert.strictEqual(m[4], vapid.publicKey);
});

test('адрес: только https на публичный узел', async () => {
  assert.strictEqual(wp.endpointShape('https://ntfy.sh/upAbCdEf123?up=1'), null);
  assert.strictEqual(wp.endpointShape('http://ntfy.sh/up1'), 'https');
  assert.strictEqual(wp.endpointShape('https://127.0.0.1/up'), 'host');
  assert.strictEqual(wp.endpointShape('https://[::1]/up'), 'host');
  assert.strictEqual(wp.endpointShape('https://localhost/up'), 'host');
  assert.strictEqual(wp.endpointShape('https://push.example.org:8443/up'), 'port');
  assert.strictEqual(wp.endpointShape('https://user:pw@push.example.org/up'), 'userinfo');
  const pub = async () => [{ address: '159.69.10.1', family: 4 }];
  const priv = async () => [{ address: '10.0.0.5', family: 4 }];
  const mixed = async () => [{ address: '8.8.8.8', family: 4 }, { address: '::1', family: 6 }];
  assert.strictEqual(await wp.checkEndpoint('https://ntfy.example.org/up1', pub), null);
  assert.strictEqual(await wp.checkEndpoint('https://ntfy.example.org/up1', priv), 'private');
  assert.strictEqual(await wp.checkEndpoint('https://ntfy.example.org/up1', mixed), 'private');
  for (const ip of ['192.168.1.1', '172.20.0.1', '169.254.169.254', '100.64.0.1', 'fd00::1', '::ffff:10.0.0.1']) {
    assert.ok(wp.privateIp(ip), ip);
  }
  assert.ok(!wp.privateIp('1.1.1.1'));
});
