#!/usr/bin/env python3
"""Текст страницы выпуска на GitHub из «Что нового» (1.10.0, 01.11.2026).

Берёт из docs/release/STORE_NOTES_<версия>.md блоки Google Play <ru-RU> и
<en-US> и пишет Markdown для softprops/action-gh-release (body_path). Нет
файла или блоков — пишет только ссылку на исходники: выпуск не должен
падать из-за заметок.

    python3 tool/dev/release_body.py v1.10.0 -o release_body.md
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def version_of(tag: str) -> str:
    v = tag.strip()
    if v.startswith('refs/tags/'):
        v = v[len('refs/tags/'):]
    return v[1:] if v.startswith('v') else v


def blocks(text: str) -> dict[str, str]:
    # Блоки Google Play — после заголовка раздела; если его нет — любые.
    i = text.find('## Google Play')
    part = text[i:] if i >= 0 else text
    return {m.group(1): m.group(2).strip() for m in re.finditer(r'^<([a-zA-Z-]+)>\n(.*?)\n</\1>', part, re.S | re.M)}


def as_list(block: str) -> str:
    # «• » магазинов → список Markdown (иначе строки слились бы в абзац).
    return '\n'.join('- ' + l[2:] if l.startswith('• ') else l for l in block.splitlines())


def body(version: str, root: str = ROOT) -> str:
    path = os.path.join(root, 'docs', 'release', f'STORE_NOTES_{version}.md')
    out = []
    try:
        with open(path, encoding='utf-8') as f:
            b = blocks(f.read())
    except OSError:
        b = {}
    if b.get('ru-RU'):
        out += ['## Что нового', '', as_list(b['ru-RU']), '']
    if b.get('en-US'):
        out += ["## What's new", '', as_list(b['en-US']), '']
    out += [
        'Android: APK для своей архитектуры (чаще всего arm64-v8a). iOS и macOS — без подписи, '
        'для проверки сборки. Контрольные суммы — SHA256SUMS.txt.',
        '',
    ]
    return '\n'.join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tag', help='метка выпуска, например v1.10.0')
    ap.add_argument('-o', '--output', default='release_body.md')
    args = ap.parse_args(argv)
    text = body(version_of(args.tag))
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(text)
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
