import re, pathlib, collections

INLINE = re.compile(r"(?:isRussian|\bru)\s*\?\s*(['\"])(.+?)\1\s*:\s*(['\"])(.+?)\3")
# Голые строковые литералы в типичных UI-конструкциях (не через tr())
UI_CTX = re.compile(r"(?:Text|label:|hintText:|labelText:|title:|content:|tooltip:|SnackBar\(\s*content:\s*Text)\s*\(\s*(['\"])([^'\"]{2,}?)\1")
CYR = re.compile(r"[А-Яа-яЁё]")
LAT = re.compile(r"[A-Za-z]{3,}")

inline_by_file = collections.Counter()
hard_by_file = collections.Counter()
hard_samples = []

for p in sorted(pathlib.Path('lib').rglob('*.dart')):
    if 'l10n/app_localizations.dart' in str(p): continue
    src = p.read_text(encoding='utf-8', errors='ignore')
    inl = len(INLINE.findall(src))
    if inl: inline_by_file[str(p)] = inl
    # голые литералы: только строки в UI-контексте, содержащие буквы, НЕ tr(...)
    for m in UI_CTX.finditer(src):
        val = m.group(2)
        if 'tr(' in m.group(0): continue
        if not (CYR.search(val) or LAT.search(val)): continue
        # пропускаем очевидно нетекстовые
        if val.startswith('http') or val.startswith('/') or '.' in val and ' ' not in val: continue
        hard_by_file[str(p)] += 1
        if len(hard_samples) < 25: hard_samples.append((str(p).replace('lib/',''), val[:40]))

print("=== ИНЛАЙН isRussian?:/ru?: по файлам (топ) ===")
for f,c in inline_by_file.most_common(15):
    print(f"  {c:3}  {f.replace('lib/','')}")
print(f"ИТОГО инлайн: {sum(inline_by_file.values())} в {len(inline_by_file)} файлах")
print()
print("=== ГОЛЫЕ ЛИТЕРАЛЫ в UI (не через tr) по файлам (топ) ===")
for f,c in hard_by_file.most_common(15):
    print(f"  {c:3}  {f.replace('lib/','')}")
print(f"ИТОГО голых литералов (UI-контекст): {sum(hard_by_file.values())} в {len(hard_by_file)} файлах")
print()
print("=== примеры голых литералов ===")
for f,v in hard_samples[:20]:
    print(f"  [{f}] {v!r}")
