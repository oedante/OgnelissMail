#!/usr/bin/env python3
"""Образцы старых форматов Office 97–2003 для тестов предпросмотра (.doc, .xls, .ppt).

1.12.x, старые форматы Office в предпросмотре, просьба владельца 04.11.2026 (задача O4).

Что получается в test/fixtures/office/ (LibreOffice: фильтры «MS Word 97»,
«MS Excel 97», «MS PowerPoint 97»):
  text_sample.doc   — text_sample.docx: заголовки, оформление, списки в два
                      уровня, таблица с объединениями, картинка, ссылки
                      (поле HYPERLINK), сноска, разрыв страницы, кириллица;
  sheet_sample.xls  — sheet_sample.xlsx: три листа (один скрытый), форматы
                      чисел и дат, объединение, заливка, скрытая строка;
  slides.ppt        — презентация как slides.pptx (slides.py), но только с
                      нужными макетами: заголовок, маркеры в два уровня,
                      картинка и фигуры, таблица, группа, скрытый слайд.

Потоки сводки (\\x05SummaryInformation и \\x05DocumentSummaryInformation:
автор, время, миниатюра — у презентации 600 КБ) из составного файла
убираются: файл пересобирается здесь же простым писателем MS-CFB.

Запуск из корня проекта: python3 tool/dev/office_fixtures/legacy_fixtures.py
LibreOffice — со своим профилем, чтобы не мешать другим запускам soffice.
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slides  # noqa: E402  (образец презентации — общий с slides.py)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(ROOT, 'test', 'fixtures', 'office')
PROFILE = 'file:///tmp/lo_o4'

END, FREE, FATSECT = 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFD


def soffice(src, fmt, outdir):
    subprocess.run(['soffice', f'-env:UserInstallation={PROFILE}', '--headless', '--convert-to', fmt,
                    '--outdir', outdir, src], check=True, stdout=subprocess.DEVNULL)
    base = os.path.splitext(os.path.basename(src))[0]
    return os.path.join(outdir, f'{base}.{fmt.split(":")[0]}')


# ── Составной файл: чтение (только то, что пишет LibreOffice) и запись ──

def cfb_read(data):
    """Потоки файла: путь «хранилище/поток» → байты."""
    shift = struct.unpack_from('<H', data, 0x1E)[0]
    size = 1 << shift
    n_fat, first_dir, first_mini, n_mini, first_difat = struct.unpack_from('<IIxxxxxxxxIII', data, 0x2C)[:5]
    fat_secs = [s for s in struct.unpack_from('<109I', data, 0x4C) if s not in (FREE, END)]
    s = first_difat
    while s not in (END, FREE) and len(fat_secs) < n_fat:
        vals = struct.unpack_from(f'<{size // 4}I', data, (s + 1) * size)
        fat_secs += [v for v in vals[:-1] if v not in (FREE, END)]
        s = vals[-1]
    fat = []
    for s in fat_secs[:n_fat]:
        fat += struct.unpack_from(f'<{size // 4}I', data, (s + 1) * size)

    def chain(start, table):
        out = []
        while start not in (END, FREE) and len(out) < len(table):
            out.append(start)
            start = table[start]
        return out

    def read(start, length):
        buf = b''.join(data[(c + 1) * size:(c + 2) * size] for c in chain(start, fat))
        return buf[:length]

    dirs = read(first_dir, len(chain(first_dir, fat)) * size)
    entries = []
    for i in range(len(dirs) // 128):
        e = dirs[i * 128:(i + 1) * 128]
        name_len = struct.unpack_from('<H', e, 0x40)[0]
        entries.append(dict(name=e[:max(0, name_len - 2)].decode('utf-16-le'), type=e[0x42],
                            left=struct.unpack_from('<I', e, 0x44)[0], right=struct.unpack_from('<I', e, 0x48)[0],
                            child=struct.unpack_from('<I', e, 0x4C)[0], start=struct.unpack_from('<I', e, 0x74)[0],
                            size=struct.unpack_from('<I', e, 0x78)[0]))
    root = entries[0]
    mini_stream = read(root['start'], root['size'])
    mini_fat = list(struct.unpack(f'<{n_mini * size // 4}I', read(first_mini, n_mini * size))) if n_mini else []
    streams = {}

    def walk(idx, prefix):
        if idx == FREE or idx >= len(entries):
            return
        e = entries[idx]
        walk(e['left'], prefix)
        walk(e['right'], prefix)
        path = prefix + e['name']
        if e['type'] == 1:
            walk(e['child'], path + '/')
        elif e['type'] == 2:
            if e['size'] < 4096:
                buf = b''.join(mini_stream[m * 64:(m + 1) * 64] for m in chain(e['start'], mini_fat))
                streams[path] = buf[:e['size']]
            else:
                streams[path] = read(e['start'], e['size'])

    walk(root['child'], '')
    return streams


def cfb_write(streams):
    """Файл версии 3 из потоков (как test/unit/cfb_writer.dart)."""
    size = 512

    class Node:
        def __init__(self, name, kind):
            self.name, self.kind, self.kids, self.start, self.size = name, kind, [], END, 0
            self.left = self.right = self.child = None
            self.id = 0

    root = Node('Root Entry', 5)
    by_path = {'': root}
    for path in streams:
        parts = path.split('/')
        parent = root
        for i, part in enumerate(parts):
            p = '/'.join(parts[:i + 1])
            if p not in by_path:
                by_path[p] = Node(part, 2 if i == len(parts) - 1 else 1)
                by_path[p].path = p
                parent.kids.append(by_path[p])
            parent = by_path[p]
    order, queue = [], [root]
    while queue:
        n = queue.pop(0)
        n.id = len(order)
        order.append(n)
        queue += n.kids

    mini, mini_fat = bytearray(), []
    for n in order:
        if n.kind != 2:
            continue
        data = streams[n.path]
        n.size = len(data)
        if len(data) >= 4096 or not data:
            continue
        n.start = len(mini) // 64
        count = (len(data) + 63) // 64
        mini_fat += [n.start + i + 1 for i in range(count - 1)] + [END]
        mini += data + b'\0' * (count * 64 - len(data))

    sectors, fat = [], []

    def put(data):
        if not data:
            return END
        start = len(sectors)
        count = (len(data) + size - 1) // size
        for i in range(count):
            sectors.append(data[i * size:(i + 1) * size].ljust(size, b'\0'))
            fat.append(start + i + 1 if i < count - 1 else END)
        return start

    for n in order:
        if n.kind == 2 and n.size >= 4096:
            n.start = put(streams[n.path])
    root.start, root.size = put(bytes(mini)), len(mini)
    mini_fat_start = put(struct.pack(f'<{len(mini_fat)}I', *mini_fat))

    def tree(nodes):
        if not nodes:
            return None
        mid = len(nodes) // 2
        nodes[mid].left, nodes[mid].right = tree(nodes[:mid]), tree(nodes[mid + 1:])
        return nodes[mid]

    for n in order:
        n.child = tree(sorted(n.kids, key=lambda k: (len(k.name), k.name.upper())))
    dirs = bytearray()
    for n in order:
        name = n.name.encode('utf-16-le')
        e = bytearray(128)
        e[:len(name)] = name
        struct.pack_into('<HBB', e, 0x40, len(name) + 2, n.kind, 1)
        struct.pack_into('<III', e, 0x44, *(x.id if x else FREE for x in (n.left, n.right, n.child)))
        if n.kind != 1:
            struct.pack_into('<II', e, 0x74, n.start, n.size)
        dirs += e
    while len(dirs) % size:
        dirs += bytearray(struct.pack('<64xH2xIII', 0, FREE, FREE, FREE)[:128]).ljust(128, b'\0')
    dir_start = put(bytes(dirs))

    per = size // 4
    n_fat = 1
    while len(sectors) + n_fat > n_fat * per:
        n_fat += 1
    fat_start = len(sectors)
    fat += [FATSECT] * n_fat
    fat += [FREE] * (n_fat * per - len(fat))
    fat_bytes = struct.pack(f'<{len(fat)}I', *fat)
    for i in range(n_fat):
        sectors.append(fat_bytes[i * size:(i + 1) * size])
    header = bytearray(size)
    header[:8] = bytes.fromhex('D0CF11E0A1B11AE1')
    struct.pack_into('<HHHHH', header, 0x18, 0x3E, 3, 0xFFFE, 9, 6)
    struct.pack_into('<III', header, 0x2C, n_fat, dir_start, 0)
    struct.pack_into('<IIIII', header, 0x38, 4096, mini_fat_start if mini_fat else END,
                     (len(mini_fat) * 4 + size - 1) // size if mini_fat else 0, END, 0)
    difat = [fat_start + i for i in range(n_fat)] + [FREE] * (109 - n_fat)
    struct.pack_into('<109I', header, 0x4C, *difat)
    return bytes(header) + b''.join(sectors)


def strip_summary(path):
    streams = cfb_read(open(path, 'rb').read())
    for name in ('\x05SummaryInformation', '\x05DocumentSummaryInformation'):
        streams.pop(name, None)
    with open(path, 'wb') as f:
        f.write(cfb_write(streams))


def small_pptx(path):
    """slides.pptx, но без неиспользуемых макетов: у LibreOffice каждый макет
    в .ppt становится образцом (~4 КБ каждый)."""
    slides.build(path)
    from pptx import Presentation
    prs = Presentation(path)
    used = {id(s.slide_layout) for s in prs.slides}
    for layout in list(prs.slide_layouts):
        if id(layout) not in used:
            prs.slide_layouts.remove(layout)
    prs.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        jobs = [(os.path.join(OUT, 'text_sample.docx'), 'doc', 'text_sample.doc'),
                (os.path.join(OUT, 'sheet_sample.xlsx'), 'xls', 'sheet_sample.xls')]
        pptx = os.path.join(tmp, 'slides.pptx')
        small_pptx(pptx)
        jobs.append((pptx, 'ppt', 'slides.ppt'))
        for src, fmt, name in jobs:
            out_dir = os.path.join(tmp, fmt)
            os.makedirs(out_dir)
            out = soffice(src, fmt, out_dir)
            strip_summary(out)
            shutil.copy(out, os.path.join(OUT, name))
            print(name, os.path.getsize(os.path.join(OUT, name)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
