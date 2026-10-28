#!/usr/bin/env python3
"""Проверка scope l10n после массовых замен локализации.

Ищет методы, где используется `l10n.`, но сам l10n не объявлен: ни локально,
ни параметром, ни полем класса. Именно так возникают ошибки компиляции после
автозамены `ru ? 'ru' : 'en'` → `l10n.tr('key')` в методах, которые принимали
только `bool ru`.
"""
import re, pathlib, sys

bad = []
for p in sorted(pathlib.Path('lib').rglob('*.dart')):
    if 'app_strings' in str(p) or 'app_localizations' in str(p):
        continue
    src = p.read_text(encoding='utf-8', errors='ignore')
    lines = src.split('\n')
    field = 'final AppLocalizations l10n;' in src
    if field:
        continue
    # Рискованные сигнатуры: параметр bool ru ИЛИ локальный ru из AppLocalizations.of
    for i, line in enumerate(lines):
        risky = re.search(r'\bbool ru[,)]', line) or \
                re.search(r'final ru = AppLocalizations\.of', line)
        if not risky:
            continue
        # тело метода: до следующего объявления метода того же уровня
        start = i
        end = min(start + 80, len(lines))
        for j in range(start + 1, end):
            if re.match(r'^  [A-Za-z_].*\(', lines[j]) and not lines[j].strip().startswith('//'):
                end = j
                break
        body = '\n'.join(lines[start:end])
        if 'l10n.' not in body:
            continue
        if re.search(r'final l10n\s*=|AppLocalizations l10n', body):
            continue
        bad.append((str(p), start + 1, lines[start].strip()[:70]))

print("=== l10n вне scope ===")
for f, l, t in bad:
    print(f"  {f.replace('lib/','')}:{l}  {t}")
print(f"\nПроблем: {len(bad)}" if bad else "\nПроблем нет ✓")
sys.exit(1 if bad else 0)
