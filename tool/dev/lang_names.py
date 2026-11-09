#!/usr/bin/env python3
"""Таблица названий языков для перевода на Windows (2.2.0).

На Android и iPhone названия языков («немецкий», «German») даёт система, у
Windows такого нет: перевод там — Bergamot (lib/services/translation/bergamot).
Названия берутся из Unicode CLDR через пакет babel (BSD-3, только для этого
скрипта, в приложение не входит) и пишутся в
lib/services/translation/language_names.g.dart вместе с текстом лицензии
Unicode (Unicode License v3 требует передавать её с данными).

Запуск (babel ставится в отдельную папку, не в систему):

    python3 -m pip install --target /tmp/babel babel==2.16.0
    PYTHONPATH=/tmp/babel python3 tool/dev/lang_names.py
"""

import os
import re
import sys

from babel import Locale  # noqa: E402  (PYTHONPATH — см. выше)
import babel

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'lib', 'services', 'translation', 'language_names.g.dart')
LANGS_G = os.path.join(ROOT, 'lib', 'l10n', 'languages.g.dart')

# Языки моделей Firefox Translations (сегодня и в новых наборах Mozilla) —
# коды как у normalizeLang: норвежский — «no».
CODES = [
    'ar', 'az', 'be', 'bg', 'bn', 'bs', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fa', 'fi', 'fr',
    'gu', 'he', 'hi', 'hr', 'hu', 'id', 'is', 'it', 'ja', 'kn', 'ko', 'lt', 'lv', 'ml', 'ms', 'mt', 'nl',
    'no', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sq', 'sr', 'sv', 'ta', 'te', 'th', 'tr', 'uk', 'vi', 'zh',
]

# Язык приложения → локаль CLDR.
CLDR = {'zh': 'zh_Hans', 'pt': 'pt_BR'}


def app_languages():
    with open(LANGS_G, encoding='utf-8') as f:
        return re.findall(r"AppLanguage\('([a-z]+)'", f.read())


def main():
    rows = []
    for app in app_languages():
        loc = Locale.parse(CLDR.get(app, app))
        names = []
        for c in CODES:
            n = loc.languages.get(c) or ''
            if '|' in n:
                sys.exit(f'«|» в названии {c} ({app})')
            names.append(n)
        rows.append((app, '|'.join(names)))
    lic_path = os.path.join(os.path.dirname(babel.__file__), 'locale-data', 'LICENSE.unicode')
    with open(lic_path, encoding='utf-8') as f:
        lic = f.read().strip()
    out = [
        '// lib/services/translation/language_names.g.dart',
        '// Создано tool/dev/lang_names.py из Unicode CLDR (babel ' + babel.__version__ + ') — не править',
        '// вручную. Названия языков для перевода на Windows: у Android и iPhone их',
        '// даёт система.',
        '',
        '// ignore_for_file: lines_longer_than_80_chars',
        '',
        '/// Коды языков — по порядку названий в [kLanguageNames].',
        'const kLanguageNameCodes = <String>[' + ', '.join(f"'{c}'" for c in CODES) + '];',
        '',
        '/// Язык приложения → названия языков [kLanguageNameCodes] через «|».',
        'const kLanguageNames = <String, String>{',
    ]
    for app, joined in rows:
        out.append(f"  '{app}': '{joined}',")
    out += [
        '};',
        '',
        '/// Лицензия данных CLDR (Unicode License v3) — «Тексты лицензий».',
        "const kCldrLicense = r'''",
        lic,
        "''';",
        '',
    ]
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print(f'{OUT}: {len(rows)} языков приложения × {len(CODES)} названий')


if __name__ == '__main__':
    main()
