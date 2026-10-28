#!/usr/bin/env python3
"""Заменить числовые отступы на токены Space (только точные значения шкалы).

EdgeInsets.all/symmetric/only/fromLTRB(...) и SizedBox(width|height: N):
4→Space.xs, 8→Space.s, 12→Space.m, 16→Space.l, 24→Space.xl, 32→Space.xxl.
Прочие числа не трогаются (они видны в ui_lint.py и правятся вручную).
Добавляет импорт core/theme/tokens.dart, если его не было.

Запуск из корня проекта: python3 tool/ui/apply_space_tokens.py [--dry]
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'lib')
TOKENS = os.path.normpath(os.path.join(ROOT, 'core', 'theme', 'tokens.dart'))
SCALE = {'4': 'Space.xs', '8': 'Space.s', '12': 'Space.m', '16': 'Space.l', '24': 'Space.xl', '32': 'Space.xxl'}
SKIP = (os.sep + 'l10n' + os.sep, os.sep + 'theme' + os.sep, '.g.dart', os.sep + 'export' + os.sep)
NUM = re.compile(r'(?<![\w.])(4|8|12|16|24|32)(?:\.0)?(?![\w.])')
EDGE = re.compile(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\(([^()]*)\)')
BOX = re.compile(r'(SizedBox\((?:width|height): *)(4|8|12|16|24|32)(?:\.0)?(?![\w.])')


def process(path, dry):
    src = open(path, encoding='utf-8').read()
    count = 0

    def edge(m):
        nonlocal count
        args = m.group(1)
        new, n = NUM.subn(lambda x: SCALE[x.group(1)], args)
        count += n
        return m.group(0).replace(args, new, 1) if n else m.group(0)

    out = EDGE.sub(edge, src)

    def box(m):
        nonlocal count
        count += 1
        return m.group(1) + SCALE[m.group(2)]

    out = BOX.sub(box, out)
    if not count:
        return 0
    if 'core/theme/tokens.dart' not in out:
        rel = os.path.relpath(TOKENS, os.path.dirname(path)).replace(os.sep, '/')
        m = re.search(r"^import 'package:flutter/(?:material|widgets|cupertino)\.dart';\n", out, re.M)
        if not m:
            return 0  # не виджет — пропускаем
        out = out[:m.end()] + f"import '{rel}';\n" + out[m.end():]
    if not dry:
        open(path, 'w', encoding='utf-8').write(out)
    return count


def main():
    dry = '--dry' in sys.argv
    total = files = 0
    for d, _, fs in os.walk(ROOT):
        for f in fs:
            p = os.path.join(d, f)
            if not f.endswith('.dart') or any(s in p for s in SKIP):
                continue
            n = process(p, dry)
            if n:
                total += n
                files += 1
    print(f'{"проверка: " if dry else ""}заменено {total} в {files} файлах')


if __name__ == '__main__':
    main()
