import os, re, collections

# Собираем публичные методы сервисов и смотрим, вызывает ли их кто-то ИЗВНЕ файла.
SKIP_NAMES = {
    # переопределения и служебное — вызываются фреймворком
    'build','dispose','initState','didUpdateWidget','toString','copyWith',
    'toJson','fromJson','toMap','fromMap','createState','noSuchMethod',
    'call','close','init','main','wantKeepAlive','didChangeDependencies',
    'didChangeAppLifecycleState','deactivate','reassemble','debugFillProperties',
}
DEF_RE = re.compile(
    r'^\s{2}(?:@override\s+)?'
    r'(?:static\s+)?(?:late\s+)?(?:final\s+)?'
    r'(?:Future<[^>]*>|Stream<[^>]*>|List<[^>]*>|Map<[^,]*,[^>]*>|void|bool|int|'
    r'String|double|[A-Z]\w*\??)\s+'
    r'(?!_)([a-z]\w*)\s*\('
)

files = []
for root, dirs, fs in os.walk('lib'):
    if any(x in root for x in ['.dart_tool', 'build']): continue
    for f in fs:
        if f.endswith('.dart'):
            files.append(os.path.join(root, f))

sources = {p: open(p, encoding='utf-8', errors='ignore').read() for p in files}

# индекс: имя метода -> файлы, где определён
defs = collections.defaultdict(list)
for p, src in sources.items():
    if '/services/' not in p and '/data/' not in p: continue
    for line in src.split('\n'):
        m = DEF_RE.match(line)
        if not m: continue
        name = m.group(1)
        if name in SKIP_NAMES: continue
        if '@override' in line: continue
        defs[name].append(p)

unwired = []
for name, owners in defs.items():
    if len(name) < 4: continue
    pat = re.compile(r'[\.\s(]' + re.escape(name) + r'\s*\(')
    called_outside = False
    for p, src in sources.items():
        if p in owners: continue
        if pat.search(src):
            called_outside = True
            break
    if not called_outside:
        unwired.append((name, owners[0]))

by_file = collections.defaultdict(list)
for name, p in unwired:
    by_file[p].append(name)

print(f"Файлов проанализировано: {len(sources)}")
print(f"Публичных методов в services/data: {len(defs)}")
print(f"НЕ вызываются извне своего файла: {len(unwired)}\n")
print("═══ ПО ФАЙЛАМ (топ) ═══")
for p in sorted(by_file, key=lambda x: -len(by_file[x]))[:14]:
    print(f"\n{p}  ({len(by_file[p])})")
    for n in sorted(by_file[p])[:8]:
        print(f"    · {n}()")
