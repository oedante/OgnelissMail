"""Добавить или заменить строки интерфейса. Запуск: python3 tool/dev/l10n_set.py strings.json
JSON: {"key": {"ru": .., "en": .., "de": .., "fr": ..}} — можно и другие языки.
Множественное число — формы через «|» (ru: one|few|many; en/de/fr: one|other).

С 1.7.3 строки — в файлах assets/l10n/<код>.xml (формат strings.xml Android);
работу делает tool/l10n/l10n.py set."""
import os
import subprocess
import sys

tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'l10n', 'l10n.py')
sys.exit(subprocess.call([sys.executable, tool, 'set'] + sys.argv[1:]))
