#!/usr/bin/env python3
"""Обновить tool/dev/removed_files.txt: файлы, удалённые из проекта и не
вернувшиеся. Запускать перед сборкой архива (это делает make_archive.sh).

Список удаляют scripts/remove_stale_files.ps1 (Windows) и
scripts/remove_stale_files.sh (Mac) — у владельца, после распаковки архива
поверх папки проекта. Поэтому:
  · записи не теряются: прежние строки остаются, пока файл не вернулся в
    проект (история git бывает короче, чем жизнь папки владельца);
  · никогда не попадают личные настройки и проект Xcode: .vscode/, .idea/,
    .github/, ios/ (проект Xcode владельца может ссылаться на файл — удалить
    его значит сломать сборку; лишний файл в ios/ ничему не мешает)."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[2]
target = root / 'tool/dev/removed_files.txt'
NEVER = ('.vscode/', '.idea/', '.github/', 'ios/', 'macos/', 'config/')


def keep(path: str) -> bool:
    return bool(path) and not path.startswith(NEVER) and '..' not in path \
        and not path.startswith('/') and not (root / path).exists()


out = subprocess.run(['git', 'log', '--diff-filter=D', '--name-only', '--format='],
                     cwd=root, capture_output=True, text=True, check=True).stdout
lines = target.read_text(encoding='utf-8').splitlines() if target.exists() else []
head = [l for l in lines if l.startswith('#')]
before = {l.strip() for l in lines if l.strip() and not l.startswith('#')}
gone = sorted({p for p in before | set(out.splitlines()) if keep(p.strip())})
target.write_text('\n'.join(head + gone) + '\n', encoding='utf-8')
print(f'{len(gone)} файлов в {target.relative_to(root)}')
