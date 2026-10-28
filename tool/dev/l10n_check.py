"""Ключи l10n.tr('…') / plural('…'), которых нет в assets/l10n/en.xml.
С 1.7.3 работу делает tool/l10n/l10n.py check-code."""
import os
import subprocess
import sys

tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'l10n', 'l10n.py')
sys.exit(subprocess.call([sys.executable, tool, 'check-code']))
