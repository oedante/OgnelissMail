#!/usr/bin/env python3
"""Тексты лицензий Rust-крейтов в ядре super_native_extensions (1.15.0).

Перетаскивание вложений (super_drag_and_drop) собирает своё ядро на Rust:
крейты из Cargo.lock пакета вкомпилированы в библиотеку приложения, а их
лицензии (MIT, Apache-2.0 и др.) требуют передавать тексты с программой.
Скрипт берёт Cargo.lock из кэша pub (версия — из pubspec.lock), скачивает
каждый крейт с crates.io и вынимает файлы LICENSE*/COPYING*/NOTICE*; пишет
assets/licenses/rust_crates.json — его показывает «Настройки → О
приложении → Тексты лицензий» (lib/core/platform/native_drag_drop.dart).

    python3 tool/dev/rust_licenses.py            # обновить файл
    python3 tool/dev/rust_licenses.py --check    # только сверить список крейтов

Запускать после обновления super_native_extensions.
"""

import argparse
import io
import json
import os
import re
import sys
import tarfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets', 'licenses', 'rust_crates.json')
PACKAGE = 'super_native_extensions'
LICENSE_FILE = re.compile(r'^(LICEN[CS]E|COPYING|NOTICE|UNLICENSE)([-._].*)?$', re.I)


def package_version() -> str:
    lock = open(os.path.join(ROOT, 'pubspec.lock'), encoding='utf-8').read()
    m = re.search(rf'\n  {PACKAGE}:\n(?:    .*\n)*?    version: "([^"]+)"', lock)
    if not m:
        sys.exit(f'{PACKAGE} нет в pubspec.lock — сначала flutter pub get')
    return m.group(1)


def cargo_lock(version: str) -> str:
    cache = os.environ.get('PUB_CACHE') or os.path.join(os.path.expanduser('~'), '.pub-cache')
    path = os.path.join(cache, 'hosted', 'pub.dev', f'{PACKAGE}-{version}', 'rust', 'Cargo.lock')
    return open(path, encoding='utf-8').read()


def crates(lock: str) -> list[tuple[str, str]]:
    out = []
    for block in lock.split('[[package]]')[1:]:
        name = re.search(r'^name = "([^"]+)"', block, re.M)
        ver = re.search(r'^version = "([^"]+)"', block, re.M)
        src = re.search(r'^source = "registry\+', block, re.M)
        if name and ver and src:
            out.append((name.group(1), ver.group(1)))
    return sorted(out)


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={'User-Agent': 'ogneliss-license-collector (tool/dev/rust_licenses.py)'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def crate_info(name: str, version: str) -> tuple[str, dict[str, str]]:
    meta = json.loads(fetch(f'https://crates.io/api/v1/crates/{name}/{version}'))
    license_id = meta['version'].get('license') or ''
    data = fetch(f'https://static.crates.io/crates/{name}/{name}-{version}.crate')
    texts = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar:
        for m in tar.getmembers():
            parts = m.name.split('/')
            # Только файлы в корне крейта: <name>-<version>/LICENSE-MIT.
            if len(parts) == 2 and m.isfile() and LICENSE_FILE.match(parts[1]):
                texts[parts[1]] = tar.extractfile(m).read().decode('utf-8', 'replace').strip()
    return license_id, texts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    version = package_version()
    lst = crates(cargo_lock(version))
    if args.check:
        have = json.load(open(OUT, encoding='utf-8'))
        names = sorted((c['name'], c['version']) for c in have['crates'])
        if names != lst or have.get('package') != f'{PACKAGE} {version}':
            print('Список крейтов изменился — запустите tool/dev/rust_licenses.py', file=sys.stderr)
            return 1
        return 0
    out = []
    for i, (name, ver) in enumerate(lst, 1):
        license_id, texts = crate_info(name, ver)
        out.append({'name': name, 'version': ver, 'license': license_id, 'texts': texts})
        print(f'{i}/{len(lst)} {name} {ver}: {license_id} ({len(texts)} файлов)', file=sys.stderr)
    # Одинаковые тексты (Apache-2.0, MIT многих крейтов) — один раз: у
    # крейта номера текстов в общем списке.
    pool: list[str] = []
    index: dict[str, int] = {}
    for c in out:
        ids = []
        for _, text in sorted(c.pop('texts').items()):
            if text not in index:
                index[text] = len(pool)
                pool.append(text)
            ids.append(index[text])
        c['texts'] = ids
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump({'package': f'{PACKAGE} {version}', 'crates': out, 'texts': pool}, f, ensure_ascii=False,
                  separators=(',', ':'))
        f.write('\n')
    missing = [c['name'] for c in out if not c['texts']]
    if missing:
        print('Без файла лицензии в крейте (в приложении — название лицензии и адрес крейта):', ', '.join(missing), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
