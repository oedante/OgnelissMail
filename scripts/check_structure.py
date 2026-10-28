import re, pathlib, sys

def strip_comments_strings(src):
    """Удаляет комментарии и содержимое строк, сохраняя структуру кода.
    Возвращает код без строк/комментов для проверки баланса скобок."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i+1] if i+1 < n else ''
        # строчный комментарий
        if c == '/' and nxt == '/':
            while i < n and src[i] != '\n': i += 1
            continue
        # блочный комментарий
        if c == '/' and nxt == '*':
            i += 2
            while i < n-1 and not (src[i] == '*' and src[i+1] == '/'): i += 1
            i += 2
            continue
        # raw-строки r'...' r"..."
        if c == 'r' and nxt in ("'", '"'):
            q = nxt; i += 2
            # тройная raw?
            if src[i:i+2] == q*2:
                i += 2
                while i < n and src[i:i+3] != q*3: i += 1
                i += 3
            else:
                while i < n and src[i] != q:
                    if src[i] == '\n': break
                    i += 1
                i += 1
            out.append('""')
            continue
        # тройные строки
        if c in ("'", '"') and src[i:i+3] == c*3:
            q = c; i += 3
            while i < n and src[i:i+3] != q*3:
                if src[i] == '\\': i += 2
                else: i += 1
            i += 3
            out.append('""')
            continue
        # обычные строки (с интерполяцией — но интерполяция сбалансирована внутри,
        # поэтому вырезаем целиком вместе с ней)
        if c in ("'", '"'):
            q = c; i += 1
            depth = 0
            while i < n:
                if src[i] == '\\': i += 2; continue
                if src[i:i+2] == '${':
                    depth += 1; i += 2; continue
                if depth > 0 and src[i] == '}':
                    depth -= 1; i += 1; continue
                if depth > 0 and src[i] == '{':
                    depth += 1; i += 1; continue
                if depth == 0 and src[i] == q:
                    i += 1; break
                if depth == 0 and src[i] == '\n':
                    break  # незакрытая строка
                i += 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return ''.join(out)

problems = []
files = sorted(pathlib.Path('lib').rglob('*.dart'))
for p in files:
    if p.name.endswith('.g.dart') or p.name.endswith('.freezed.dart'):
        continue
    src = p.read_text(encoding='utf-8', errors='ignore')
    code = strip_comments_strings(src)
    for open_c, close_c, name in [('{','}','фигурные'), ('(',')','круглые'), ('[',']','квадратные')]:
        o = code.count(open_c); c = code.count(close_c)
        if o != c:
            problems.append(f"{p}: {name} скобки {o}/{c} (разница {o-c})")

print(f"Проверено файлов: {len([f for f in files if not f.name.endswith('.g.dart')])}")
print(f"Файлов с дисбалансом скобок: {len(problems)}")
for pr in problems:
    print("  ‼️", pr)
sys.exit(1 if problems else 0)

# ── Проверка путей импортов (битый путь = ошибка компиляции) ──────────────────
def check_imports():
    import re as _re
    lib = pathlib.Path('lib')
    broken, dupes = [], []
    for p in [x for x in lib.rglob('*.dart') if not x.name.endswith('.g.dart')]:
        src = p.read_text(encoding='utf-8', errors='ignore')
        seen = set()
        for imp in _re.findall(r"^import\s+'([^']+)'", src, _re.M):
            if imp in seen: dupes.append(f"{p}: дубль '{imp}'")
            seen.add(imp)
            if imp.startswith('dart:'): continue
            if imp.startswith('package:'):
                if imp.startswith('package:ogneliss/') and not (lib/imp[17:]).exists():
                    broken.append(f"{p}: '{imp}'")
                continue
            if not (p.parent/imp).resolve().exists():
                broken.append(f"{p}: '{imp}'")
    return broken, dupes

if __name__ == '__main__' and '--imports' in sys.argv:
    b, d = check_imports()
    print("Битых импортов:", len(b)); [print("  ‼️", x) for x in b]
    print("Дублей:", len(d)); [print("  ⚠️", x) for x in d]
