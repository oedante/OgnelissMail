#!/usr/bin/env python3
"""Уязвимости зависимостей: отчёт OSV-Scanner → сводка сборки и аннотации.

OSV-Scanner (Google, Apache-2.0) сверяет lock-файлы — pubspec.lock,
server/*/package-lock.json — с базой OSV (osv.dev: GitHub Advisory Database,
бюллетени pub.dev и npm). Здесь его JSON превращается в таблицу в сводке
сборки и аннотации (1.9.x, просьба владельца 31.10.2026).

    python3 tool/dev/osv_report.py osv-results.json [--summary "$GITHUB_STEP_SUMMARY"]

Когда задача падает (код 1): уязвимость HIGH или CRITICAL, для которой уже
вышло исправление, — в пакете, который попадает в приложение или на сервер.
Обновление зависимости тогда — обычная работа, а выпуск с известной и
исправленной серьёзной уязвимостью был бы ошибкой. Остальное (LOW, MODERATE,
серьёзная без исправления, пакеты только для разработки — build_runner и
т. п., в сборку не входят) — предупреждения: на них не стоит останавливать
каждый push, их видно в сводке.

Уязвимость, которая к нам не относится (не та функция пакета), — в
tool/dev/osv-scanner.toml ([[IgnoredVulns]] с причиной и сроком).
Сканер не отработал (нет сети, нет файла) — предупреждение, не ошибка.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from license_check import dev_only_pub  # noqa: E402

SEVERITY_ORDER = {'CRITICAL': 4, 'HIGH': 3, 'MODERATE': 2, 'MEDIUM': 2, 'LOW': 1, 'UNKNOWN': 0}
MAX_EACH = 10


def esc(s: str) -> str:
    return s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def vkey(v: str) -> tuple:
    """Версия для сравнения: числа — числами, предварительная версия
    («-beta.3») — раньше выпуска. Достаточно для semver pub и npm."""
    v = v.strip().lstrip('v')
    main, _, pre = v.partition('-')
    main = main.split('+', 1)[0]
    nums = []
    for p in main.split('.'):
        m = re.match(r'\d+', p)
        nums.append(int(m.group(0)) if m else 0)
    while len(nums) < 3:
        nums.append(0)
    pre_key: tuple = (1,) if not pre else (0,) + tuple(
        (0, int(x), '') if x.isdigit() else (1, 0, x) for x in re.split(r'[.+]', pre))
    return tuple(nums) + (pre_key,)


def severity_of(score: str | None, vulns: list[dict]) -> str:
    """CVSS (max_severity группы) → уровень; без него — оценка базы
    (GitHub: LOW / MODERATE / HIGH / CRITICAL)."""
    try:
        s = float(score) if score not in (None, '') else None
    except ValueError:
        s = None
    if s is not None and s > 0:
        return 'CRITICAL' if s >= 9 else 'HIGH' if s >= 7 else 'MODERATE' if s >= 4 else 'LOW'
    best = 'UNKNOWN'
    for v in vulns:
        sev = str((v.get('database_specific') or {}).get('severity') or '').upper()
        if SEVERITY_ORDER.get(sev, 0) > SEVERITY_ORDER[best]:
            best = 'MODERATE' if sev == 'MEDIUM' else sev
    return best


def fixed_versions(vulns: list[dict], name: str, version: str) -> list[str]:
    """Версии с исправлением для диапазона, в который входит [version].
    Диапазон не определился (необычная схема версий) — любое известное
    исправление: лучше лишний раз остановить сборку, чем пропустить."""
    exact: list[str] = []
    any_fix: list[str] = []
    cur = vkey(version) if version else None
    for v in vulns:
        for a in v.get('affected') or []:
            if (a.get('package') or {}).get('name') != name:
                continue
            for r in a.get('ranges') or []:
                intro = None
                for e in r.get('events') or []:
                    if 'introduced' in e:
                        intro = e['introduced']
                    elif 'fixed' in e:
                        any_fix.append(e['fixed'])
                        try:
                            if cur is not None and intro is not None and \
                                    (intro == '0' or vkey(intro) <= cur) and cur < vkey(e['fixed']):
                                exact.append(e['fixed'])
                        except (ValueError, TypeError):
                            pass
                        intro = None
    out = exact or any_fix
    return sorted(set(out), key=lambda x: vkey(x) if re.match(r'v?\d', x) else (0,))


def npm_dev_packages(project: str) -> set[str]:
    out: set[str] = set()
    server = os.path.join(project, 'server')
    if not os.path.isdir(server):
        return out
    for d in os.listdir(server):
        lock = os.path.join(server, d, 'package-lock.json')
        if not os.path.isfile(lock):
            continue
        with open(lock, encoding='utf-8') as f:
            for path, meta in (json.load(f).get('packages') or {}).items():
                if path and meta.get('dev'):
                    out.add(path.split('node_modules/')[-1])
    return out


def findings(data: dict, project: str) -> list[dict]:
    dev_pub = dev_only_pub(os.path.join(project, '.dart_tool', 'package_graph.json'), 'ogneliss')
    dev_npm = npm_dev_packages(project)
    out = []
    for res in data.get('results') or []:
        src = ((res.get('source') or {}).get('path') or '').replace('/github/workspace/', '')
        if src.startswith(os.path.abspath(project) + os.sep):
            src = os.path.relpath(src, project)
        for p in res.get('packages') or []:
            pkg = p.get('package') or {}
            name, ver, eco = pkg.get('name', ''), pkg.get('version', ''), pkg.get('ecosystem', '')
            vulns = p.get('vulnerabilities') or []
            by_id = {v.get('id'): v for v in vulns}
            groups = p.get('groups') or [{'ids': [v.get('id')], 'max_severity': ''} for v in vulns]
            for g in groups:
                gv = [by_id[i] for i in g.get('ids') or [] if i in by_id]
                ids = sorted(set((g.get('ids') or []) + [a for a in (g.get('aliases') or [])]))
                summary = next((v.get('summary') for v in gv if v.get('summary')), '') or \
                    next((v.get('details', '')[:120] for v in gv), '')
                sev = severity_of(g.get('max_severity'), gv)
                fixes = fixed_versions(gv, name, ver)
                dev = (eco.lower() == 'pub' and name in dev_pub) or (eco.lower() == 'npm' and name in dev_npm)
                blocking = sev in ('HIGH', 'CRITICAL') and bool(fixes) and not dev
                out.append({'source': src, 'eco': eco, 'name': name, 'version': ver, 'ids': ids,
                            'severity': sev, 'fixed': fixes, 'summary': summary.strip(), 'dev': dev,
                            'blocking': blocking})
    out.sort(key=lambda f: (-SEVERITY_ORDER.get(f['severity'], 0), f['name']))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('results', help='JSON OSV-Scanner (--format=json)')
    ap.add_argument('--project', default='.')
    ap.add_argument('--summary', default=None, help='дописать таблицу в файл (GITHUB_STEP_SUMMARY)')
    args = ap.parse_args(argv)

    def summary(text: str) -> None:
        if args.summary:
            with open(args.summary, 'a', encoding='utf-8') as f:
                f.write(text)

    try:
        with open(args.results, encoding='utf-8') as f:
            raw = f.read()
        data = json.loads(raw) if raw.strip() else {'results': []}
    except (OSError, ValueError) as e:
        msg = f'OSV-Scanner не дал отчёта ({e}) — уязвимости в этой сборке не проверены'
        print(f'::warning title=OSV-Scanner::{esc(msg)}')
        summary(f'### Уязвимости зависимостей\n\n⚠️ {msg}\n\n')
        return 0

    found = findings(data, args.project)
    blocking = [f for f in found if f['blocking']]
    print(f'Уязвимости: {len(found)}, останавливают сборку: {len(blocking)}')
    for f in found:
        print(f"  {'!' if f['blocking'] else ' '} {f['severity']:<8} {f['eco']}:{f['name']} {f['version']} "
              f"({f['source']}) {', '.join(f['ids'])} → {', '.join(f['fixed']) or 'исправления нет'}"
              f"{' (dev)' if f['dev'] else ''} — {f['summary']}")
    shown = {'error': 0, 'warning': 0}
    for f in found:
        kind = 'error' if f['blocking'] else 'warning'
        if shown[kind] >= MAX_EACH:
            continue
        shown[kind] += 1
        fix = f"исправлено в {', '.join(f['fixed'])}" if f['fixed'] else 'исправления пока нет'
        print(f"::{kind} file={f['source']},title={f['severity']} {esc(f['name'])} {esc(f['version'])}::"
              f"{esc(', '.join(f['ids']))}: {esc(f['summary'])} ({fix})")

    lines = ['### Уязвимости зависимостей (OSV-Scanner)\n\n']
    if not found:
        lines.append('Известных уязвимостей нет.\n\n')
    else:
        lines.append(f'Найдено: {len(found)}; **останавливают сборку: {len(blocking)}** '
                     '(HIGH/CRITICAL с исправлением в пакете приложения или сервера).\n\n')
        lines.append('| | Уровень | Пакет | Версия | Файл | Бюллетень | Исправлено в | Описание |\n'
                     '|---|---|---|---|---|---|---|---|\n')
        for f in found:
            mark = '⛔' if f['blocking'] else ('dev' if f['dev'] else '⚠️')
            desc = f['summary'].replace('|', '\\|')
            lines.append(f"| {mark} | {f['severity']} | {f['eco']}:{f['name']} | {f['version']} | {f['source']} | "
                         f"{', '.join(f['ids'])} | {', '.join(f['fixed']) or '—'} | {desc} |\n")
        lines.append('\nНе относится к нам — `tool/dev/osv-scanner.toml` ([[IgnoredVulns]] с причиной и сроком).\n\n')
    summary(''.join(lines))
    return 1 if blocking else 0


if __name__ == '__main__':
    sys.exit(main())
