'use strict';
// Автотест прокси погоды: вместо MET Norway — локальная заглушка, вместо
// GeoNames — три города. Проверяется: координаты до сотых, один запрос к
// MET на город до Expires, If-Modified-Since, поиск по-русски и по-латински,
// ё/е, порядок по населению. Сеть не нужна: npm test.

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function listen(srv) {
  return new Promise((resolve) => srv.listen(0, '127.0.0.1', () => resolve(srv.address().port)));
}

const row = (id, name, alt, lat, lon, cc, a1, pop) =>
  [id, name, name, alt, lat, lon, 'P', 'PPLA', cc, '', a1, '', '', '', pop, '', '', 'Europe/Moscow', '2026-01-01'].join('\t');

test('прогноз через кэш и поиск городов', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wx'));
  fs.writeFileSync(path.join(dir, 'cities15000.txt'), [
    row(1, 'Kazan', 'Kazan’,Казань,Qazan', '55.78874', '49.12214', 'RU', '73', '1243500'),
    row(2, 'Kazanlak', 'Kazanlak,Казанлък', '42.61667', '25.4', 'BG', '61', '47000'),
    row(3, 'Korolyov', 'Korolev,Королёв', '55.91631', '37.82535', 'RU', '47', '220000'),
  ].join('\n'));
  fs.writeFileSync(path.join(dir, 'admin1CodesASCII.txt'), 'RU.73\tTatarstan Republic\nRU.47\tMoscow Oblast\nBG.61\tStara Zagora\n');
  fs.writeFileSync(path.join(dir, 'countryInfo.txt'), '#c\nRU\tRUS\t643\tRS\tRussia\nBG\tBGR\t100\tBU\tBulgaria\n');

  const metHits = [];
  const met = http.createServer((req, res) => {
    metHits.push({ url: req.url, ua: req.headers['user-agent'], ims: req.headers['if-modified-since'] });
    if (req.headers['if-modified-since']) {
      res.writeHead(304, { Expires: new Date(Date.now() + 3600e3).toUTCString() });
      return res.end();
    }
    res.writeHead(200, {
      'Content-Type': 'application/json',
      Expires: new Date(Date.now() + 3600e3).toUTCString(),
      'Last-Modified': 'Sat, 07 Nov 2026 17:00:00 GMT',
    });
    res.end('{"properties":{"timeseries":[]}}');
  });
  const metPort = await listen(met);
  process.env.MET_URL = `http://127.0.0.1:${metPort}/compact`;
  delete require.cache[require.resolve('../server.js')];
  const { createServer } = require('../server.js');
  const srv = createServer({ dataDir: dir });
  const port = await listen(srv);
  const get = async (p, headers = {}) => {
    const r = await fetch(`http://127.0.0.1:${port}/weather${p}`, { headers });
    return { status: r.status, text: r.status === 304 ? '' : await r.text(), headers: r.headers };
  };

  try {
    // Координаты — до сотых; второй запрос — из кэша, без MET.
    let r = await get('/forecast?lat=55.796127&lon=49.106405');
    assert.strictEqual(r.status, 200);
    assert.strictEqual(metHits.length, 1);
    assert.match(metHits[0].url, /lat=55\.8&lon=49\.11$/);
    assert.match(metHits[0].ua, /^OgnelissMailWeatherProxy\/.*github\.com\/oedante\/OgnelissMail/);
    r = await get('/forecast?lat=55.8&lon=49.11');
    assert.strictEqual(metHits.length, 1, 'до Expires — из кэша');
    assert.ok(r.headers.get('expires'));
    // Приложение с If-Modified-Since — 304 без тела.
    r = await get('/forecast?lat=55.8&lon=49.11', { 'If-Modified-Since': 'Sat, 07 Nov 2026 17:00:00 GMT' });
    assert.strictEqual(r.status, 304);
    // Неверные координаты.
    assert.strictEqual((await get('/forecast?lat=95&lon=1')).status, 400);

    // Поиск: по-русски — русское имя; «Казан» — сначала крупная Казань.
    let s = JSON.parse((await get('/search?q=' + encodeURIComponent('казан') + '&accept-language=ru')).text);
    assert.deepStrictEqual(s.map((x) => x.name), ['Казань', 'Казанлък']);
    assert.strictEqual(s[0].display_name, 'Казань, Tatarstan Republic, Russia');
    assert.strictEqual(s[0].lat, '55.7887');
    // По-латински — латинское имя; ё и е — одно и то же.
    s = JSON.parse((await get('/search?q=Kazan')).text);
    assert.strictEqual(s[0].name, 'Kazan');
    s = JSON.parse((await get('/search?q=' + encodeURIComponent('королев'))).text);
    assert.strictEqual(s[0].name, 'Королёв');
    // Слишком коротко — пусто.
    assert.deepStrictEqual(JSON.parse((await get('/search?q=k')).text), []);
  } finally {
    srv.close();
    met.close();
  }
});
