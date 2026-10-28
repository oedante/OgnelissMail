#!/usr/bin/env python3
"""Повторно объявленные члены класса («'x' is already declared in this scope»).

Эвристика по отформатированному коду (dart format): классы начинаются с
нулевого отступа, члены — с отступа в 2 пробела. Геттер и сеттер с одним
именем — допустимы. Запуск: python3 tool/dev/dup_member_check.py [пути...]
"""
import re, sys, pathlib

CLASS = re.compile(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*(?:class|mixin|extension|enum)\s+(\w+)?')
MEMBER = re.compile(
    r'^  (?!return\b|if\b|for\b|while\b|switch\b|case\b|default\b|//|/\*|\*|@|}|\)|\]|assert\b|super\b|this\b|await\b|throw\b|try\b|else\b|yield\b)'
    r'(?P<pre>[\w<>?,\s\[\].]*?\s)?(?P<acc>get\s+|set\s+)?(?P<name>[A-Za-z_$][\w$]*)\s*(?P<tail>\(|=>|\{|=|;)')

def check(path):
    bad = []
    cls, seen = None, {}
    for no, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if line and not line[0].isspace():
            m = CLASS.match(line)
            if m:
                cls, seen = m.group(1) or '?', {}
            elif line.startswith('}'):
                cls, seen = None, {}
            continue
        if cls is None or line.startswith('   '):
            continue
        m = MEMBER.match(line)
        if not m:
            continue
        pre = (m.group('pre') or '').strip()
        name, tail, acc = m.group('name'), m.group('tail'), (m.group('acc') or '').strip()
        for a in ('get', 'set'):
            if pre == a or pre.endswith(' ' + a):
                acc, pre = a, pre[:-3].strip()
        if name in ('Function', 'static', 'final', 'late', 'const', 'var', 'operator'):
            continue
        # Тип-функция «void Function(int)? onTap;» — имя после скобок, пропускаем.
        if 'Function' in pre or '(' in line.split(name)[0]:
            continue
        # Без типа перед именем и не «(» — это не объявление (присваивание и т. п.).
        if not pre and not acc and tail != '(':
            continue
        if pre.endswith('.') or name == cls or pre.startswith('factory') or pre == 'const':
            continue
        if pre in ('new', 'return', 'await'):
            continue
        key = (acc if acc in ('set',) else '') + name
        if key in seen:
            bad.append(f'{path}:{no}: {cls}.{name} — уже объявлен в строке {seen[key]}')
        else:
            seen[key] = no
    return bad

def main(args):
    roots = [pathlib.Path(a) for a in (args or ['lib', 'packages'])]
    files = [f for r in roots for f in ([r] if r.is_file() else r.rglob('*.dart'))
             if not f.name.endswith(('.g.dart', '.freezed.dart'))]
    bad = [b for f in files for b in check(f)]
    print('\n'.join(bad))
    print(f'проверено {len(files)}, повторов {len(bad)}')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
