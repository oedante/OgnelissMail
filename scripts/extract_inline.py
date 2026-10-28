import re, sys
INLINE = re.compile(r"(isRussian|\bru)\s*\?\s*(['\"])(.+?)\2\s*:\s*(['\"])(.+?)\4")
for path in sys.argv[1:]:
    src = open(path, encoding='utf-8').read()
    print(f"\n=== {path} ===")
    for i,m in enumerate(INLINE.finditer(src),1):
        ru, en = m.group(3), m.group(5)
        interp = '$' in ru or '$' in en
        print(f"{i:2}. {'⚠INTERP ' if interp else ''}ru={ru!r}  en={en!r}")
