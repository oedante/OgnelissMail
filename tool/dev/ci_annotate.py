#!/usr/bin/env python3
"""Аннотации GitHub Actions из вывода `flutter analyze` и `flutter test --machine`.

Журналы сборок GitHub отдаёт только со своих файловых серверов, а аннотации
видны через API (check-runs/<id>/annotations) — так ошибки анализатора и
упавшие тесты можно прочитать без журнала, в том числе из облачной среды
разработки, где Flutter нет.

    python3 tool/dev/ci_annotate.py analyze analyze.txt
    python3 tool/dev/ci_annotate.py test test-machine.jsonl

GitHub показывает не больше 10 аннотаций каждого вида на шаг, поэтому
первые ошибки и предупреждения — отдельными аннотациями (с файлом и
строкой), а полный список — одной заметкой «summary».
"""

import json
import re
import sys

ANALYZE_RX = re.compile(
    r'^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+(\S+?):(\d+):(\d+)\s+•\s+(\S+)\s*$')

MAX_EACH = 10
MAX_SUMMARY = 30000


def esc(s: str) -> str:
    return s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def esc_prop(s: str) -> str:
    return esc(s).replace(':', '%3A').replace(',', '%2C')


def cut(s: str, n: int) -> str:
    return s if len(s) <= n else s[:n] + ' …'


def analyze(path: str) -> None:
    issues = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = ANALYZE_RX.match(line.rstrip('\n'))
            if m:
                issues.append(m.groups())
    counts = {'error': 0, 'warning': 0, 'info': 0}
    shown = {'error': 0, 'warning': 0}
    for sev, msg, file, line, col, code in issues:
        counts[sev] += 1
        if sev in shown and shown[sev] < MAX_EACH:
            shown[sev] += 1
            print(f'::{sev} file={esc_prop(file)},line={line},col={col},title={esc_prop(code)}::{esc(msg)}')
    head = f"analyze: errors {counts['error']}, warnings {counts['warning']}, infos {counts['info']}"
    serious = [f'{sev} {file}:{line}:{col} [{code}] {msg}'
               for sev, msg, file, line, col, code in issues if sev != 'info']
    infos = [f'{file}:{line} [{code}] {msg}'
             for sev, msg, file, line, col, code in issues if sev == 'info']
    body = '\n'.join([head] + serious)
    print(f'::notice title=analyze summary::{esc(cut(body, MAX_SUMMARY))}')
    if infos:
        print(f'::notice title=analyze infos::{esc(cut(chr(10).join(infos), MAX_SUMMARY))}')


def test(path: str) -> None:
    suites = {}   # id → path
    tests = {}    # id → (name, suiteID, line)
    errors = {}   # testID → [text]
    failed = []   # (testID, result)
    passed = skipped = 0
    with open(path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            raw = raw.strip()
            if not raw.startswith('{'):
                continue
            try:
                ev = json.loads(raw)
            except ValueError:
                continue
            t = ev.get('type')
            if t == 'suite':
                s = ev.get('suite') or {}
                suites[s.get('id')] = s.get('path') or ''
            elif t == 'testStart':
                s = ev.get('test') or {}
                tests[s.get('id')] = (s.get('name') or '', s.get('suiteID'), s.get('root_line') or s.get('line'))
            elif t == 'error':
                text = (ev.get('error') or '').strip()
                stack = (ev.get('stackTrace') or '').strip()
                if stack:
                    text += '\n' + '\n'.join(stack.splitlines()[:8])
                errors.setdefault(ev.get('testID'), []).append(text)
            elif t == 'testDone':
                if ev.get('hidden'):
                    # Служебный «тест» загрузки: ошибка здесь — файл теста
                    # не скомпилировался.
                    if ev.get('result') != 'success':
                        failed.append((ev.get('testID'), ev.get('result')))
                    continue
                if ev.get('skipped'):
                    skipped += 1
                elif ev.get('result') == 'success':
                    passed += 1
                else:
                    failed.append((ev.get('testID'), ev.get('result')))
    lines = []
    for i, (tid, result) in enumerate(failed):
        name, suite_id, line = tests.get(tid, ('?', None, None))
        file = suites.get(suite_id, '')
        text = '\n'.join(errors.get(tid, []))
        lines.append(f'{file}: {name} — {result}\n{cut(text, 1500)}')
        if i < MAX_EACH:
            loc = f'file={esc_prop(file)}' + (f',line={line}' if line else '') if file else ''
            sep = ',' if loc else ''
            print(f'::error {loc}{sep}title={esc_prop(cut(name, 200))}::{esc(cut(text, 4000))}')
    head = f'test: passed {passed}, failed {len(failed)}, skipped {skipped}'
    print(f'::notice title=test summary::{esc(cut(chr(10).join([head] + lines), MAX_SUMMARY))}')


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ('analyze', 'test'):
        print(__doc__)
        sys.exit(2)
    (analyze if sys.argv[1] == 'analyze' else test)(sys.argv[2])


if __name__ == '__main__':
    main()
