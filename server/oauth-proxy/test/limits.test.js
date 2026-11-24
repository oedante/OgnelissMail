'use strict';
// Лимиты частоты (limits.js, безопасность, этап 2): node --test

const test = require('node:test');
const assert = require('node:assert');
const { createLimits, ipKey } = require('../limits');

test('окно: max запросов, затем ожидание до конца окна', () => {
  let t = 0;
  const l = createLimits({ now: () => t });
  for (let i = 0; i < 3; i++) assert.strictEqual(l.hit('login', '1.2.3.4', 3, 60000), 0);
  assert.strictEqual(l.hit('login', '1.2.3.4', 3, 60000), 60);
  // Другой адрес и другой вид запроса — свои счётчики.
  assert.strictEqual(l.hit('login', '5.6.7.8', 3, 60000), 0);
  assert.strictEqual(l.hit('token', '1.2.3.4', 3, 60000), 0);
  t = 30000;
  assert.strictEqual(l.hit('login', '1.2.3.4', 3, 60000), 30);
  t = 60000;
  assert.strictEqual(l.hit('login', '1.2.3.4', 3, 60000), 0);
  assert.deepStrictEqual(l.stats().refused, { login: 2 });
});

test('пауза после неудач', () => {
  let t = 0;
  const l = createLimits({ now: () => t });
  for (let i = 0; i < 4; i++) assert.strictEqual(l.fail('exchange', 'ip', 5, 600000, 900000), false);
  assert.strictEqual(l.paused('exchange', 'ip'), 0);
  assert.strictEqual(l.fail('exchange', 'ip', 5, 600000, 900000), true);
  assert.strictEqual(l.paused('exchange', 'ip'), 900);
  assert.strictEqual(l.paused('exchange', 'other'), 0);
  t = 900000;
  assert.strictEqual(l.paused('exchange', 'ip'), 0);
  // После паузы счёт с нуля.
  assert.strictEqual(l.fail('exchange', 'ip', 5, 600000, 900000), false);
  assert.deepStrictEqual(l.stats().pauses, { exchange: 1 });
});

test('неудачи вне окна не копятся', () => {
  let t = 0;
  const l = createLimits({ now: () => t });
  for (let i = 0; i < 4; i++) l.fail('callback', 'ip', 5, 1000, 5000);
  t = 1000;
  assert.strictEqual(l.fail('callback', 'ip', 5, 1000, 5000), false);
  assert.strictEqual(l.paused('callback', 'ip'), 0);
});

test('уборка устаревших счётчиков', () => {
  let t = 0;
  const l = createLimits({ now: () => t });
  l.hit('a', 'x', 1, 1000);
  l.fail('b', 'y', 3, 1000, 1000);
  assert.strictEqual(l.size(), 2);
  t = 2000;
  l.sweep();
  assert.strictEqual(l.size(), 0);
});

test('ключ адреса: IPv4, IPv4 в IPv6, IPv6 по /64', () => {
  assert.strictEqual(ipKey('203.0.113.7'), '203.0.113.7');
  assert.strictEqual(ipKey('::ffff:203.0.113.7'), '203.0.113.7');
  assert.strictEqual(ipKey('2001:db8:1:2:aaaa::1'), '2001:db8:1:2::/64');
  assert.strictEqual(ipKey('2001:db8:1:2:bbbb:cccc:dddd:eeee'), '2001:db8:1:2::/64');
  assert.strictEqual(ipKey('2001:db8::1'), '2001:db8:0:0::/64');
  assert.strictEqual(ipKey(''), '');
  assert.strictEqual(ipKey(undefined), '');
});
