#!/usr/bin/env python3
"""Замеры скорости на эмуляторе Android: сбор, сравнение с базой, база.

Интеграционные тесты (integration_test/perf_test.dart, задача «emulator» в
.github/workflows/ci.yml; 1.9.x, просьба владельца 31.10.2026) печатают по
строке на замер:

    OGN_PERF {"name": "mail_open_cold_ms", "ms": 812, "marks": {...}}

Строки попадают и в вывод `flutter test --machine` (события print), и в
журнал Android (logcat) — сбор берёт их из любого файла.

    # строки замеров → perf-results.json
    python3 tool/perf/perf_check.py extract test-machine.jsonl logcat.txt -o perf-results.json
    # сравнение с tool/perf/baseline.json; таблица — в сводку сборки
    python3 tool/perf/perf_check.py compare perf-results.json --summary "$GITHUB_STEP_SUMMARY"
    # новая база по замерам (×1,5 с запасом, шаг 50 мс)
    python3 tool/perf/perf_check.py baseline perf-results.json

Время на эмуляторе в облаке шумит (общие процессоры, программная графика,
отладочная сборка), поэтому ошибка — только если замер больше базы вдвое
(--factor): это уже не шум, а заметное замедление. Медленнее базы, но не
вдвое, — предупреждение.
"""

import argparse
import json
import math
import os
import sys

MARKER = 'OGN_PERF'
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BASELINE = os.path.join(HERE, 'baseline.json')


def esc(s: str) -> str:
    return s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def _payloads(line: str):
    """Строки замера в строке файла: обычный текст (logcat, вывод теста) или
    событие print из `flutter test --machine`."""
    texts = [line]
    s = line.strip()
    if s.startswith('{'):
        try:
            ev = json.loads(s)
            if isinstance(ev, dict) and isinstance(ev.get('message'), str):
                texts = ev['message'].splitlines()
        except ValueError:
            pass
    for t in texts:
        i = t.find(MARKER + ' ')
        if i < 0:
            continue
        try:
            obj = json.loads(t[i + len(MARKER) + 1:].strip())
        except ValueError:
            continue
        if isinstance(obj, dict) and isinstance(obj.get('name'), str):
            yield obj


def extract(paths: list[str]) -> dict:
    metrics: dict[str, float] = {}
    details: dict[str, dict] = {}
    info: dict = {}
    for p in paths:
        if not os.path.isfile(p):
            continue
        with open(p, encoding='utf-8', errors='replace') as f:
            for line in f:
                for obj in _payloads(line):
                    name = obj['name']
                    if name.startswith('_'):
                        info[name[1:]] = obj.get('info')
                        continue
                    ms = obj.get('ms')
                    if isinstance(ms, (int, float)):
                        metrics[name] = ms
                        if obj.get('marks') or obj.get('runs'):
                            details[name] = {k: obj[k] for k in ('marks', 'runs') if k in obj}
    return {'metrics': dict(sorted(metrics.items())), 'details': details, 'info': info}


def load_baseline(path: str) -> dict[str, float]:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    return {k: v for k, v in (data.get('metrics') or {}).items() if isinstance(v, (int, float))}


def compare(metrics: dict, base: dict, factor: float) -> tuple[list[dict], list[dict]]:
    rows = []
    for name in sorted(set(metrics) | set(base)):
        v, b = metrics.get(name), base.get(name)
        if v is None:
            rows.append({'metric': name, 'value': None, 'base': b, 'ratio': None, 'status': 'missing'})
            continue
        if b is None or b <= 0:
            rows.append({'metric': name, 'value': v, 'base': None, 'ratio': None, 'status': 'new'})
            continue
        r = v / b
        status = 'regression' if r > factor else 'slower' if r > 1 else 'ok'
        rows.append({'metric': name, 'value': v, 'base': b, 'ratio': r, 'status': status})
    return rows, [r for r in rows if r['status'] == 'regression']


def new_baseline(metrics: dict, headroom: float, step: int) -> dict[str, int]:
    return {k: int(max(step, math.ceil(v * headroom / step) * step)) for k, v in sorted(metrics.items())}


def cmd_extract(args) -> int:
    data = extract(args.inputs)
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f"Замеров: {len(data['metrics'])} → {args.output}")
    return 0


def cmd_compare(args) -> int:
    with open(args.results, encoding='utf-8') as f:
        data = json.load(f)
    metrics = data.get('metrics') or {}
    base = load_baseline(args.baseline)
    lines = ['### Скорость на эмуляторе (Android, отладочная сборка)\n\n']
    if not metrics:
        msg = 'замеров нет: тесты скорости не дошли до конца или их вывод не найден'
        print(f'::error title=Замеры скорости::{esc(msg)}')
        lines.append(f'⛔ {msg}\n\n')
        if args.summary:
            with open(args.summary, 'a', encoding='utf-8') as f:
                f.write(''.join(lines))
        return 1
    rows, bad = compare(metrics, base, args.factor)
    icon = {'ok': '✅', 'slower': '⚠️', 'regression': '⛔', 'new': '🆕', 'missing': '❔'}
    lines.append(f'Ошибка — медленнее базы (`tool/perf/baseline.json`) больше чем в {args.factor:g} раза.\n\n')
    lines.append('| | Замер | мс | База, мс | Отношение |\n|---|---|---:|---:|---:|\n')
    for r in rows:
        v = '—' if r['value'] is None else f"{r['value']:.0f}"
        b = '—' if r['base'] is None else f"{r['base']:.0f}"
        ratio = '—' if r['ratio'] is None else f"{r['ratio']:.2f}"
        lines.append(f"| {icon[r['status']]} | {r['metric']} | {v} | {b} | {ratio} |\n")
        print(f"{r['status']:<10} {r['metric']:<36} {v:>8} / {b:>8}  {ratio}")
    info = data.get('info') or {}
    if info:
        lines.append('\n<details><summary>Устройство и этапы</summary>\n\n```json\n'
                     + json.dumps({'info': info, 'details': data.get('details') or {}}, ensure_ascii=False,
                                  indent=1)[:60000] + '\n```\n</details>\n')
    lines.append('\nОбновить базу: скачать perf-results.json из Artifacts удачной сборки и выполнить '
                 '`python3 tool/perf/perf_check.py baseline perf-results.json` (README в tool/perf).\n\n')
    for r in bad:
        print(f"::error title=Замедление {esc(r['metric'])}::{r['value']:.0f} мс при базе {r['base']:.0f} мс "
              f"(×{r['ratio']:.2f}, предел ×{args.factor:g})")
    for r in rows:
        if r['status'] == 'missing':
            print(f"::warning title=Замер {esc(r['metric'])}::в этой сборке не измерен")
    if args.summary:
        with open(args.summary, 'a', encoding='utf-8') as f:
            f.write(''.join(lines))
    return 1 if bad else 0


def cmd_baseline(args) -> int:
    with open(args.results, encoding='utf-8') as f:
        metrics = json.load(f).get('metrics') or {}
    if not metrics:
        print('Замеров нет — база не изменена', file=sys.stderr)
        return 1
    try:
        with open(args.baseline, encoding='utf-8') as f:
            old = json.load(f)
    except (OSError, ValueError):
        old = {}
    old['metrics'] = new_baseline(metrics, args.headroom, args.step)
    with open(args.baseline, 'w', encoding='utf-8') as f:
        json.dump(old, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f"База: {len(old['metrics'])} замеров → {args.baseline}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    e = sub.add_parser('extract', help='строки OGN_PERF → JSON')
    e.add_argument('inputs', nargs='+')
    e.add_argument('-o', '--output', default='perf-results.json')
    c = sub.add_parser('compare', help='сравнить с базой')
    c.add_argument('results')
    c.add_argument('--baseline', default=DEFAULT_BASELINE)
    c.add_argument('--factor', type=float, default=2.0)
    c.add_argument('--summary', default=None)
    b = sub.add_parser('baseline', help='записать новую базу по замерам')
    b.add_argument('results')
    b.add_argument('--baseline', default=DEFAULT_BASELINE)
    b.add_argument('--headroom', type=float, default=1.5)
    b.add_argument('--step', type=int, default=50)
    args = ap.parse_args(argv)
    return {'extract': cmd_extract, 'compare': cmd_compare, 'baseline': cmd_baseline}[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
