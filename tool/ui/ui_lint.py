#!/usr/bin/env python3
"""Проверка единообразия интерфейса (этап 4, docs/plan/UI_REDESIGN.md, Ф0).

Считает в lib/ места, которые расходятся с токенами и палитрой:
  · отступы числами (EdgeInsets/SizedBox с числами вместо Space.*);
  · размеры шрифта числами (fontSize: 13) вместо стилей textTheme;
  · цвета Material (Colors.red, Colors.grey.shade300…) вместо ролей
    ColorScheme и AppColors — серый Material не меняется в тёмной теме.

Запуск из корня проекта:  python3 tool/ui/ui_lint.py [--top 20] [--files]
Цель — сокращать числа от выпуска к выпуску; новый код — без них.
"""
import argparse
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'lib')
SKIP = ('lib/l10n/', '.g.dart', 'lib/core/theme/', 'services/export/')

RULES = {
    'отступ числом': re.compile(r'(EdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^)]*\b\d+(?:\.\d+)?\b[^)]*\))|SizedBox\((?:width|height): *\d'),
    'fontSize числом': re.compile(r'fontSize: *\d'),
    'цвет Material': re.compile(r'\bColors\.(?!transparent\b|white\b|black\b|white\d|black\d)[a-z]+[A-Za-z]*'),
    'серый Material': re.compile(r'\bColors\.grey\b'),
    # Значки — Material Symbols через AppIcons (lib/core/theme/app_icons.dart).
    'значок Icons.* вместо AppIcons': re.compile(r'(?<![\w.])Icons\.[a-z]'),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--top', type=int, default=15)
    ap.add_argument('--files', action='store_true', help='список файлов по каждому правилу')
    a = ap.parse_args()
    totals = Counter()
    per = {k: Counter() for k in RULES}
    for d, _, files in os.walk(ROOT):
        for f in files:
            if not f.endswith('.dart'):
                continue
            path = os.path.normpath(os.path.join(d, f))
            rel = os.path.relpath(path, os.path.join(ROOT, '..')).replace(os.sep, '/')
            if any(s in rel for s in SKIP):
                continue
            text = open(path, encoding='utf-8').read()
            for name, rx in RULES.items():
                n = len(rx.findall(text))
                if n:
                    totals[name] += n
                    per[name][rel] += n
    for name in RULES:
        print(f'{name}: {totals[name]}')
        if a.files:
            for rel, n in per[name].most_common(a.top):
                print(f'    {n:4}  {rel}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
