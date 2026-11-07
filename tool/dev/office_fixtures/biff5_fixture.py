#!/usr/bin/env python3
"""Книга Excel 95 (BIFF5) с кириллицей в кодовой странице 1251 (1.15.1).

LibreOffice формат Excel 95 больше не записывает, а у выгрузок 1С 7.7 и
старых бланков он русский: собираем книгу сами по [MS-XLS] (записи BIFF5)
и составному файлу OLE (cfb_write из legacy_fixtures.py).

    python3 tool/dev/office_fixtures/biff5_fixture.py test/fixtures/office

Пишет excel95_cp1251.xls: лист «Смета» (текст, числа с форматом «0.00»,
жирный заголовок, формула со строковым результатом) и лист «Склад».
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from legacy_fixtures import cfb_write  # noqa: E402  pylint: disable=wrong-import-position


def rec(t, data=b''):
    return struct.pack('<HH', t, len(data)) + data


def s8(text):
    b = text.encode('cp1251')
    return struct.pack('<B', len(b)) + b


def s16(text):
    b = text.encode('cp1251')
    return struct.pack('<H', len(b)) + b


def bof(dt):
    return rec(0x0809, struct.pack('<HHHH', 0x0500, dt, 0x0DBB, 0x07CC))


def font(bold):
    # Высота 10 pt, без курсива, цвет «авто», насыщенность, кодировка 204.
    return rec(0x0031, struct.pack('<HHHHHBBBB', 200, 0, 0x7FFF, 700 if bold else 400, 0, 0, 0, 204, 0) + s8('Arial'))


def xf(ifnt, ifmt, style):
    flags = 0xFFF5 if style else 0x0001
    # Выравнивание: общее; заливка: шаблон 0, цвета 64/65; рамок нет.
    fill = 64 | (65 << 7)
    return rec(0x00E0, struct.pack('<HHHBBII', ifnt, ifmt, flags, 0x20, 0, fill, 0))


def sheet(cells):
    out = bof(0x0010)
    for c in cells:
        out += c
    out += rec(0x023E, struct.pack('<HHHHH', 0x06B6, 0, 0, 0, 0))  # Window2 (BIFF5)
    out += rec(0x000A)
    return out


def label(r, c, ixfe, text):
    return rec(0x0204, struct.pack('<HHH', r, c, ixfe) + s16(text))


def number(r, c, ixfe, v):
    return rec(0x0203, struct.pack('<HHHd', r, c, ixfe, v))


def string_formula(r, c, ixfe, text):
    # Результат — строка: байты 6..13 = 0x00, …, 0xFFFF; затем запись String.
    res = bytes([0, 0, 0, 0, 0, 0, 0xFF, 0xFF])
    f = rec(0x0006, struct.pack('<HHH', r, c, ixfe) + res + struct.pack('<HIH', 0, 0, 0))
    return f + rec(0x0207, s16(text))


def book():
    s1 = sheet([
        label(0, 0, 16, 'Наименование'), label(0, 1, 16, 'Кол-во'), label(0, 2, 16, 'Цена'),
        label(1, 0, 15, 'Кирпич облицовочный'), number(1, 1, 15, 1200), number(1, 2, 17, 35.5),
        label(2, 0, 15, 'Цемент М500'), number(2, 1, 15, 40), number(2, 2, 17, 420),
        string_formula(3, 0, 15, 'Итого по смете'),
    ])
    s2 = sheet([label(0, 0, 15, 'Остатки на 01.11.2026')])
    globals_wo_bound = (
        bof(0x0005) + rec(0x0042, struct.pack('<H', 1251))
        + font(False) + font(True) + font(False) + font(False) + font(True)
        + rec(0x041E, struct.pack('<H', 164) + s8('0.00'))
        + b''.join(xf(0, 0, True) for _ in range(15))
        + xf(0, 0, False) + xf(5, 0, False) + xf(0, 164, False)  # шрифт 5 — пятая запись (номера 4 в BIFF нет)
    )
    bound_len = 2 * (4 + 4 + 2 + 1 + 6)  # два BoundSheet: смещение, флаги, имя (до 6 байт)
    names = ['Смета', 'Склад']
    # Размер записей BoundSheet зависит от длины имён.
    bounds_size = sum(4 + 6 + 1 + len(n.encode('cp1251')) for n in names)
    del bound_len
    start = len(globals_wo_bound) + bounds_size + 4  # + EOF
    bounds = b''
    pos = start
    for n, s in zip(names, [s1, s2]):
        bounds += rec(0x0085, struct.pack('<IBB', pos, 0, 0) + s8(n))
        pos += len(s)
    return globals_wo_bound + bounds + rec(0x000A) + s1 + s2


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'test/fixtures/office'
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'excel95_cp1251.xls'), 'wb') as f:
        f.write(cfb_write({'Book': book()}))
    print('excel95_cp1251.xls')
    return 0


if __name__ == '__main__':
    sys.exit(main())
