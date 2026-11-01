#!/usr/bin/env python3
"""Лицензии зависимостей: пакеты Dart (pub) и npm-пакеты серверов.

Правило владельца 31.10.2026 (CLAUDE.md, docs/LICENSING.md, раздел 5):
ограничительные и неясные лицензии — GPL, LGPL, AGPL, SSPL, BUSL, «только
некоммерческое использование», нет лицензии — сначала обсуждаются с
владельцем. Скрипт проверяет это на каждом push (1.9.x, просьба владельца
31.10.2026), чтобы такая зависимость не пришла незаметно — например,
транзитивно с обновлением другого пакета.

    flutter pub get            # создаёт .dart_tool/package_config.json
    python3 tool/dev/license_check.py [--summary "$GITHUB_STEP_SUMMARY"]

Пакеты Dart — по файлу LICENSE в папке пакета (.dart_tool/package_config.json
→ rootUri), серверные — по полю "license" в server/*/package-lock.json.
Лицензия определяется по тексту (MIT, BSD-2/3-Clause, Apache-2.0, MPL-2.0,
ISC, Zlib, OFL, …). Пакеты Flutter SDK — лицензия SDK (BSD-3-Clause);
локальные пакеты проекта (packages/*) — лицензия проекта (Apache-2.0).

Задача падает (код 1), если лицензия не из разрешённых или не распознана —
кроме пакетов из tool/dev/license_allowlist.txt: там у каждого исключения
записана причина (двойная лицензия и т. п.). Остальное — предупреждения.
Без Python-зависимостей: только стандартная библиотека.
"""

import argparse
import json
import os
import re
import sys
from urllib.parse import unquote, urlparse

# Разрешённые лицензии (SPDX). MPL-2.0 — слабое копилефт на уровне файлов,
# совместимо с Apache 2.0 и уже используется (enough_mail, dbus, nm —
# docs/LICENSING.md, раздел 2).
ALLOWED = {
    'MIT', 'MIT-0', 'BSD-2-Clause', 'BSD-3-Clause', '0BSD', 'Apache-2.0',
    'MPL-2.0', 'ISC', 'Zlib', 'OFL-1.1', 'Unlicense', 'CC0-1.0', 'BSL-1.0',
    'BlueOak-1.0.0', 'Python-2.0', 'CC-BY-4.0', 'PSF-2.0', 'X11',
}

# Запрещённые без решения владельца: копилефт, «исходники доступны»,
# только некоммерческое использование.
FORBIDDEN_PREFIXES = ('GPL', 'LGPL', 'AGPL', 'SSPL', 'BUSL', 'CC-BY-NC', 'Elastic', 'Commons-Clause')

LICENSE_FILES = ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENCE', 'LICENCE.md', 'COPYING', 'COPYING.md',
                 'license', 'License', 'LICENSE-MIT', 'LICENSE.MIT', 'LICENSE-APACHE')


def norm(text: str) -> str:
    """Текст лицензии для сравнения: нижний регистр, одиночные пробелы,
    без маркеров комментариев (/* * // #) и кавычек-«ёлочек» Markdown."""
    t = text.lower()
    t = re.sub(r'[*#>`]|//', ' ', t)
    t = t.replace('’', "'").replace('“', '"').replace('”', '"')
    return re.sub(r'\s+', ' ', t).strip()


# Признаки полного текста лицензии (по нормализованному тексту).
def _has(t: str, *parts: str) -> bool:
    return all(p in t for p in parts)


def classify_text(text: str) -> tuple[list[str], list[str]]:
    """Лицензии в тексте файла: (найденные разрешённые, найденные
    ограничительные). Файл может содержать несколько лицензий (двойная
    лицензия, тексты зависимостей) — тогда найдены все."""
    t = norm(text)
    found: list[str] = []
    bad: list[str] = []

    if _has(t, 'apache license') and ('version 2.0' in t or 'apache-2.0' in t or 'licenses/license-2.0' in t):
        found.append('Apache-2.0')
    if 'mozilla public license' in t and ('2.0' in t):
        found.append('MPL-2.0')
    if _has(t, 'permission is hereby granted, free of charge') and \
            ('above copyright notice and this permission notice shall be included' in t or
             'the above copyright notice and this permission notice' in t):
        found.append('MIT')
    if 'redistribution and use in source and binary forms' in t:
        # Третий пункт BSD — запрет на использование имён авторов.
        if re.search(r'neither the name|names? of (its|the) (copyright holder|contributors|authors)'
                     r'|may not be used to endorse or promote', t):
            found.append('BSD-3-Clause')
        else:
            found.append('BSD-2-Clause')
    if re.search(r'permission to use, copy, modify, and(/or)? distribute this software for any purpose '
                 r'with or without fee is hereby granted', t):
        # ISC и 0BSD: у 0BSD нет требования сохранять уведомление.
        found.append('ISC' if 'provided that the above copyright notice' in t else '0BSD')
    if _has(t, "provided 'as-is', without any express or implied warranty",
            'altered source versions must be plainly marked'):
        found.append('Zlib')
    if 'sil open font license' in t:
        found.append('OFL-1.1')
    if 'this is free and unencumbered software released into the public domain' in t:
        found.append('Unlicense')
    if 'cc0 1.0' in t or 'creative commons zero' in t:
        found.append('CC0-1.0')
    if 'boost software license' in t:
        found.append('BSL-1.0')
    if 'blue oak model license' in t:
        found.append('BlueOak-1.0.0')

    # Ограничительные — по названию лицензии в тексте. Упоминание
    # «GPL-compatible» или «not GPL» само по себе — не лицензия: нужно
    # название лицензии целиком. Текст MPL-2.0 сам называет GPL, LGPL и AGPL
    # («Secondary License», п. 1.12) — это определение, а не вторая лицензия.
    t = re.sub(r'"?secondary license"? means either the gnu general public license.*?'
               r'(any )?later versions of those licenses\.?', ' ', t)
    if 'gnu affero general public license' in t:
        bad.append('AGPL')
    if re.search(r'gnu (lesser|library) general public license', t):
        bad.append('LGPL')
    if re.search(r'gnu general public license', t):
        bad.append('GPL')
    if 'server side public license' in t:
        bad.append('SSPL')
    if 'business source license' in t:
        bad.append('BUSL')
    if re.search(r'non-?commercial (use|purposes) only|for non-?commercial purposes|'
                 r'creative commons attribution-?non-?commercial|commercial use is (not permitted|prohibited)',
                 t):
        bad.append('non-commercial')
    if 'elastic license' in t:
        bad.append('Elastic')
    if 'commons clause' in t:
        bad.append('Commons-Clause')
    return found, bad


def spdx_verdict(expr: str) -> tuple[str, str]:
    """Выражение SPDX из package-lock.json → (лицензия, вердикт: ok / bad /
    unknown). «A OR B» — годится, если годится любой вариант (выбираем
    разрешённый); «A AND B» — только если годятся все."""
    e = (expr or '').strip()
    if not e:
        return '—', 'unknown'
    inner = e.strip('()').strip()
    if re.search(r'\sOR\s', inner, re.I):
        parts = [p.strip('() ') for p in re.split(r'\s+OR\s+', inner, flags=re.I)]
        verdicts = [spdx_verdict(p) for p in parts]
        for lic, v in verdicts:
            if v == 'ok':
                return lic, 'ok'
        return e, 'bad' if any(v == 'bad' for _, v in verdicts) else 'unknown'
    if re.search(r'\sAND\s', inner, re.I):
        parts = [p.strip('() ') for p in re.split(r'\s+AND\s+', inner, flags=re.I)]
        verdicts = [spdx_verdict(p)[1] for p in parts]
        if all(v == 'ok' for v in verdicts):
            return e, 'ok'
        return e, 'bad' if 'bad' in verdicts else 'unknown'
    lic = re.sub(r'\s+WITH\s+.*$', '', inner, flags=re.I)
    if lic in ALLOWED:
        return lic, 'ok'
    if lic.upper().startswith(tuple(p.upper() for p in FORBIDDEN_PREFIXES)) or \
            lic.upper().startswith('SEE LICENSE') or lic.upper() == 'UNLICENSED':
        return lic, 'bad' if not lic.upper().startswith('SEE LICENSE') else 'unknown'
    return lic, 'unknown'


def text_verdict(text: str | None) -> tuple[str, str]:
    """Текст файла лицензии → (лицензия, вердикт)."""
    if text is None:
        return 'нет файла LICENSE', 'unknown'
    found, bad = classify_text(text)
    if bad:
        # Двойная лицензия («MIT или GPL») тоже попадает сюда: решение —
        # исключением в license_allowlist.txt с причиной.
        lic = ' + '.join(found + bad)
        return lic, 'bad'
    if not found:
        return 'не распознана', 'unknown'
    return ' + '.join(dict.fromkeys(found)), 'ok'


def read_license(root: str) -> str | None:
    for name in LICENSE_FILES:
        p = os.path.join(root, name)
        if os.path.isfile(p):
            with open(p, encoding='utf-8', errors='replace') as f:
                return f.read()
    return None


def load_allowlist(path: str) -> tuple[dict[str, tuple[str, str]], list[str]]:
    """Исключения: строка «[pub:|npm:]пакет лицензия причина…». Без причины —
    ошибка (исключение должно объяснять, почему зависимость допустима)."""
    entries: dict[str, tuple[str, str]] = {}
    errors: list[str] = []
    if not os.path.isfile(path):
        return entries, errors
    with open(path, encoding='utf-8') as f:
        for n, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(None, 2)
            if len(parts) < 3 or not parts[2].strip():
                errors.append(f'{path}:{n}: нужно «пакет лицензия причина» — {raw.strip()}')
                continue
            key = parts[0] if ':' in parts[0] else f'pub:{parts[0]}'
            entries[key] = (parts[1], parts[2].strip())
    return entries, errors


def dev_only_pub(graph_path: str, root_name: str) -> set[str]:
    """Пакеты, которые нужны только для разработки (dev_dependencies и их
    зависимости): в сборку приложения они не попадают."""
    try:
        with open(graph_path, encoding='utf-8') as f:
            g = json.load(f)
    except (OSError, ValueError):
        return set()
    deps = {p['name']: p.get('dependencies', []) for p in g.get('packages', [])}
    root = next((p for p in g.get('packages', []) if p['name'] == root_name), None)
    if root is None:
        return set()

    def reach(starts: list[str]) -> set[str]:
        seen: set[str] = set()
        stack = list(starts)
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            stack.extend(deps.get(n, []))
        return seen

    runtime = reach(root.get('dependencies', []))
    dev = reach(root.get('devDependencies', []))
    return dev - runtime


def pub_packages(project: str) -> tuple[list[dict], list[str]]:
    cfg_path = os.path.join(project, '.dart_tool', 'package_config.json')
    if not os.path.isfile(cfg_path):
        return [], [f'нет {cfg_path}: сначала flutter pub get']
    with open(cfg_path, encoding='utf-8') as f:
        cfg = json.load(f)
    flutter_root = (cfg.get('flutterRoot') or '')
    flutter_root = unquote(urlparse(flutter_root).path) if flutter_root.startswith('file:') else flutter_root
    pubspec = os.path.join(project, 'pubspec.yaml')
    root_name = ''
    if os.path.isfile(pubspec):
        with open(pubspec, encoding='utf-8') as f:
            m = re.search(r'^name:\s*(\S+)', f.read(), re.M)
            root_name = m.group(1) if m else ''
    dev = dev_only_pub(os.path.join(project, '.dart_tool', 'package_graph.json'), root_name)
    project_real = os.path.realpath(project)
    with open(os.path.join(project, 'LICENSE'), encoding='utf-8', errors='replace') as f:
        own_license = f.read()
    out = []
    for p in cfg.get('packages', []):
        name = p['name']
        uri = p.get('rootUri', '')
        if uri.startswith('file:'):
            root = unquote(urlparse(uri).path)
        else:
            root = os.path.normpath(os.path.join(project, '.dart_tool', unquote(uri)))
        real = os.path.realpath(root)
        if name == root_name or real == project_real or real.startswith(project_real + os.sep):
            kind, text = 'own', own_license
        elif flutter_root and real.startswith(os.path.realpath(flutter_root) + os.sep):
            # Flutter SDK (flutter, flutter_test, sky_engine, …): лицензия SDK.
            # LICENSE у sky_engine — сводка лицензий движка (в том числе
            # двойных, вроде FreeType FTL/GPL): её показывает само приложение
            # (LicenseRegistry), а движок распространяется по лицензии SDK.
            kind = 'sdk'
            with open(os.path.join(flutter_root, 'LICENSE'), encoding='utf-8', errors='replace') as f:
                text = f.read()
        else:
            kind, text = 'pub', read_license(root)
        lic, verdict = text_verdict(text)
        out.append({'eco': 'pub', 'name': name, 'version': _pub_version(root), 'license': lic,
                    'verdict': verdict, 'kind': kind, 'dev': name in dev})
    return out, []


def _pub_version(root: str) -> str:
    """Версия пакета — из его pubspec.yaml (у пакетов SDK и локальных папка
    без версии в имени)."""
    try:
        with open(os.path.join(root, 'pubspec.yaml'), encoding='utf-8', errors='replace') as f:
            m = re.search(r'^version:\s*["\']?([^\s"\']+)', f.read(), re.M)
            return m.group(1) if m else ''
    except OSError:
        return ''


def npm_packages(project: str) -> tuple[list[dict], list[str]]:
    out: list[dict] = []
    notes: list[str] = []
    server = os.path.join(project, 'server')
    if not os.path.isdir(server):
        return out, notes
    for d in sorted(os.listdir(server)):
        pkg = os.path.join(server, d, 'package.json')
        lock = os.path.join(server, d, 'package-lock.json')
        if not os.path.isfile(pkg):
            continue
        if not os.path.isfile(lock):
            with open(pkg, encoding='utf-8') as f:
                deps = json.load(f).get('dependencies') or {}
            if deps:
                notes.append(f'server/{d}: зависимости есть, а package-lock.json нет — не проверено')
            continue
        with open(lock, encoding='utf-8') as f:
            data = json.load(f)
        for path, meta in sorted((data.get('packages') or {}).items()):
            if not path:
                continue
            name = path.split('node_modules/')[-1]
            lic, verdict = spdx_verdict(meta.get('license', ''))
            out.append({'eco': 'npm', 'name': name, 'version': meta.get('version', ''), 'license': lic,
                        'verdict': verdict, 'kind': f'server/{d}', 'dev': bool(meta.get('dev'))})
    return out, notes


def esc(s: str) -> str:
    return s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--project', default='.', help='корень проекта (по умолчанию текущая папка)')
    ap.add_argument('--allowlist', default=None, help='файл исключений (tool/dev/license_allowlist.txt)')
    ap.add_argument('--summary', default=None, help='дописать таблицу в файл (GITHUB_STEP_SUMMARY)')
    args = ap.parse_args(argv)
    project = args.project
    allow_path = args.allowlist or os.path.join(project, 'tool', 'dev', 'license_allowlist.txt')
    allow, allow_errors = load_allowlist(allow_path)

    pub, notes = pub_packages(project)
    npm, notes2 = npm_packages(project)
    notes += notes2
    rows = pub + npm
    if not pub:
        for n in notes:
            print(f'::error title=Лицензии::{esc(n)}')
        return 1

    failed = []
    used_allow = set()
    for r in rows:
        key = f"{r['eco']}:{r['name']}"
        if r['verdict'] != 'ok' and key in allow:
            used_allow.add(key)
            r['verdict'] = 'allowed'
            r['reason'] = f'{allow[key][0]}: {allow[key][1]}'
        if r['verdict'] in ('bad', 'unknown'):
            failed.append(r)
    stale = sorted(set(allow) - used_allow)

    # Сводка по лицензиям.
    counts: dict[str, int] = {}
    for r in rows:
        counts[r['license']] = counts.get(r['license'], 0) + 1
    width = max(len(r['name']) for r in rows)
    print(f'Лицензии: pub {len(pub)}, npm {len(npm)}; исключений {len(used_allow)}, проблем {len(failed)}')
    for lic, n in sorted(counts.items(), key=lambda x: (-x[1], x[0])):
        print(f'  {n:4d}  {lic}')
    print()
    for r in sorted(rows, key=lambda r: (r['eco'], r['name'])):
        mark = {'ok': '  ', 'allowed': '~ ', 'bad': '! ', 'unknown': '? '}[r['verdict']]
        dev = ' (dev)' if r['dev'] else ''
        print(f"{mark}{r['eco']:3} {r['name']:<{width}} {r['version']:<14} {r['license']}{dev}"
              + (f"  — {r['reason']}" if r.get('reason') else ''))

    for r in failed:
        what = 'не распознана' if r['verdict'] == 'unknown' else 'ограничительная'
        print(f"::error title=Лицензия {esc(r['name'])}::{r['eco']} {esc(r['name'])} {esc(r['version'])}: "
              f"{esc(r['license'])} ({what}). Правило владельца: сначала обсудить; если допустимо — строка в "
              f"tool/dev/license_allowlist.txt с причиной")
    for e in allow_errors:
        print(f'::error title=license_allowlist.txt::{esc(e)}')
    for k in stale:
        print(f'::warning title=license_allowlist.txt::{esc(k)}: исключение больше не нужно — убрать строку')
    for n in notes:
        print(f'::warning title=Лицензии::{esc(n)}')

    if args.summary:
        with open(args.summary, 'a', encoding='utf-8') as f:
            f.write('### Лицензии зависимостей\n\n')
            f.write(f'pub: {len(pub)}, npm (серверы): {len(npm)}, исключений: {len(used_allow)}, '
                    f'**проблем: {len(failed)}**\n\n')
            f.write('| Лицензия | Пакетов |\n|---|---:|\n')
            for lic, n in sorted(counts.items(), key=lambda x: (-x[1], x[0])):
                f.write(f'| {lic} | {n} |\n')
            if failed:
                f.write('\n**Требуют решения владельца:**\n\n| Пакет | Версия | Лицензия |\n|---|---|---|\n')
                for r in failed:
                    f.write(f"| {r['eco']}:{r['name']} | {r['version']} | {r['license']} |\n")
            if used_allow:
                f.write('\n**Исключения (tool/dev/license_allowlist.txt):**\n\n| Пакет | Причина |\n|---|---|\n')
                for r in rows:
                    if r['verdict'] == 'allowed':
                        f.write(f"| {r['eco']}:{r['name']} | {r['reason']} |\n")
            f.write('\n<details><summary>Все пакеты</summary>\n\n| Пакет | Версия | Лицензия | Где |\n'
                    '|---|---|---|---|\n')
            for r in sorted(rows, key=lambda r: (r['eco'], r['name'])):
                where = r['kind'] + (', dev' if r['dev'] else '')
                f.write(f"| {r['eco']}:{r['name']} | {r['version']} | {r['license']} | {where} |\n")
            f.write('\n</details>\n\n')
    return 1 if failed or allow_errors else 0


if __name__ == '__main__':
    sys.exit(main())
