#!/usr/bin/env python3
"""Ogneliss Mail: языки iPhone в файле проекта Xcode (1.8.0).

tool/l10n/l10n.py gen раскладывает тексты на каждый язык приложения:
  ios/Runner/<язык>.lproj/InfoPlist.strings — название и запросы разрешений;
  ios/OgnelissWidgets/<язык>.lproj/Localizable.strings — подписи виджетов.
Xcode кладёт в приложение только файлы, которые знает проект. Скрипт
дописывает недостающие языки в группы InfoPlist.strings и
Localizable.strings файла project.pbxproj и в список языков проекта
(knownRegions). Остальное в файле не трогается; повторный запуск ничего не
меняет. Прежний файл сохраняется рядом: project.pbxproj.bak.

Запуск (из папки проекта; scripts/build_ios.sh вызывает сам):
    python3 scripts/ios_localizations.py [ios/Runner.xcodeproj/project.pbxproj]
"""
import hashlib
import os
import re
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

# Группа файла → папка с переводами.
GROUPS = {
    'InfoPlist.strings': 'ios/Runner',
    'Localizable.strings': 'ios/OgnelissWidgets',
}


def langs_in(folder, name):
    d = os.path.join(ROOT, folder)
    if not os.path.isdir(d):
        return []
    out = []
    for e in sorted(os.listdir(d)):
        if e.endswith('.lproj') and e != 'Base.lproj' and os.path.isfile(os.path.join(d, e, name)):
            out.append(e[:-len('.lproj')])
    return out


def new_id(text, seed):
    for i in range(100):
        v = hashlib.md5(f'{seed}:{i}'.encode()).hexdigest()[:24].upper()
        if v not in text:
            return v
    raise SystemExit('не удалось подобрать id')


def patch(text):
    """→ (новый текст, что добавлено)."""
    added = []
    vg = re.search(r'/\* Begin PBXVariantGroup section \*/\n(.*?)/\* End PBXVariantGroup section \*/', text, re.S)
    if not vg:
        return text, added
    fr_end = text.find('/* End PBXFileReference section */')
    if fr_end < 0:
        return text, added
    new_refs = []
    section = vg.group(1)
    new_section = section
    # Группы вида: ID /* InfoPlist.strings */ = { isa = PBXVariantGroup; children = ( ... ); name = InfoPlist.strings; ... };
    for m in re.finditer(r'(\t\t([0-9A-F]{24}) /\* ([^*]+?) \*/ = \{\n\t\t\tisa = PBXVariantGroup;\n'
                         r'\t\t\tchildren = \(\n)(.*?)(\t\t\t\);\n)(.*?\n\t\t\};\n)', section, re.S):
        head, gid, name, children, close, tail = m.group(1), m.group(2), m.group(3).strip(), m.group(4), m.group(5), m.group(6)
        if name not in GROUPS:
            continue
        have = set(re.findall(r'/\* ([A-Za-z\-]+) \*/', children))
        folder = GROUPS[name]
        extra = ''
        for lang in langs_in(folder, name):
            if lang in have:
                continue
            fid = new_id(text + ''.join(new_refs), f'{gid}:{lang}')
            # Как пишет сам Xcode: значения с дефисом («zh-Hans») — в кавычках.
            qn = f'"{lang}"' if '-' in lang else lang
            qp = f'"{lang}.lproj/{name}"' if '-' in lang else f'{lang}.lproj/{name}'
            new_refs.append(f'\t\t{fid} /* {lang} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; '
                            f'name = {qn}; path = {qp}; sourceTree = "<group>"; }};\n')
            extra += f'\t\t\t\t{fid} /* {lang} */,\n'
            added.append(f'{name}: {lang}')
        if extra:
            new_section = new_section.replace(m.group(0), head + children + extra + close + tail, 1)
    if not added:
        return text, added
    text = text[:vg.start(1)] + new_section + text[vg.end(1):]
    fr_end = text.find('/* End PBXFileReference section */')
    text = text[:fr_end] + ''.join(new_refs) + text[fr_end:]
    # Языки проекта.
    kr = re.search(r'(knownRegions = \(\n)(.*?)(\t\t\t\);)', text, re.S)
    if kr:
        known = set(x.strip().strip(',').strip('"') for x in kr.group(2).splitlines() if x.strip())
        langs = sorted({a.split(': ')[1] for a in added})
        more = ''
        for lang in langs:
            if lang not in known:
                q = f'"{lang}"' if '-' in lang else lang
                more += f'\t\t\t\t{q},\n'
        if more:
            text = text[:kr.end(2)] + more + text[kr.end(2):]
    return text, added


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'ios/Runner.xcodeproj/project.pbxproj')
    if not os.path.isfile(path):
        print(f'Нет файла проекта: {path}')
        return
    text = open(path, encoding='utf-8').read()
    new, added = patch(text)
    if not added:
        print('Языки iPhone: все уже в проекте Xcode')
        return
    shutil.copyfile(path, path + '.bak')
    open(path, 'w', encoding='utf-8').write(new)
    print(f'Языки iPhone: добавлено в проект Xcode — {len(added)} (копия прежнего: project.pbxproj.bak)')
    for a in added:
        print('  ', a)


if __name__ == '__main__':
    main()
