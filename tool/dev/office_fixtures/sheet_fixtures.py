#!/usr/bin/env python3
"""Fixtures for the spreadsheet preview tests (1.11.x, O2).

Writes into test/fixtures/office/:
  sheet_sample.xlsx  — openpyxl: two visible sheets and a hidden third,
                       Cyrillic, number formats (#,##0.00, 0%, dd.mm.yyyy,
                       [$₽-419]), a formula with a cached value (patched into
                       the XML: openpyxl writes none), merged cells, bold,
                       fill, colour, column width, frozen pane, hidden row.
  sheet_sample.ods   — the same converted by LibreOffice (recalculated).
  sheet_utf8.csv     — UTF-8 with BOM, commas, a quoted multi-line field.
  sheet_cp1251.csv   — Windows-1251, «sep=;» hint, ';' delimiter, numbers
                       with decimal comma (as Russian Excel saves it).
  sheet_tabs.tsv     — tab-separated, UTF-8 without BOM.

Usage: python3 tool/dev/office_fixtures/sheet_fixtures.py
Needs openpyxl and LibreOffice (soffice) with its own profile directory.
"""
import datetime
import os
import shutil
import subprocess
import tempfile
import zipfile

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(ROOT, 'test', 'fixtures', 'office')


def make_xlsx(path):
    wb = Workbook()
    ws = wb.active
    ws.title = 'Отчёт'
    ws['A1'] = 'Отчёт по продажам за ноябрь'
    ws['A1'].font = Font(bold=True, size=14)
    ws.merge_cells('A1:D1')
    ws.append(['Товар', 'Сумма', 'Доля', 'Дата'])
    for c in ws[2]:
        c.font = Font(bold=True, color='FFFFFFFF')
        c.fill = PatternFill('solid', fgColor='FF1F4E79')
    rows = [
        ('Бумага А4', 1234.5, 0.125, datetime.date(2026, 11, 5)),
        ('Картриджи', 98765.432, 0.5, datetime.date(2026, 11, 6)),
        ('Скрепки', 12.0, 0.375, datetime.date(2026, 11, 7)),
    ]
    for r in rows:
        ws.append(list(r))
    for row in ws.iter_rows(min_row=3, max_row=5):
        row[1].number_format = '#,##0.00'
        row[2].number_format = '0%'
        row[3].number_format = 'dd.mm.yyyy'
    ws['A6'] = 'Итого'
    ws['A6'].font = Font(bold=True, italic=True)
    ws['B6'] = '=SUM(B3:B5)'
    ws['B6'].number_format = '#,##0.00\\ [$₽-419]'
    ws['B6'].fill = PatternFill('solid', fgColor='FFFFFF99')
    ws['C6'] = 'красный'
    ws['C6'].font = Font(color='FFC00000')
    ws['A8'] = 'Длинный текст, который переносится по словам внутри ячейки'
    ws['A8'].alignment = Alignment(wrap_text=True, vertical='top')
    ws['A9'] = 'скрытая строка'
    ws.row_dimensions[9].hidden = True
    ws['A10'] = True
    ws['B10'] = -42.5
    ws['B10'].number_format = '0.00;[Red]-0.00'
    ws.column_dimensions['A'].width = 30
    ws.column_dimensions['B'].width = 16
    ws.freeze_panes = 'A3'

    ws2 = wb.create_sheet('Справочник')
    ws2.append(['Код', 'Название'])
    ws2.append([1, 'Единица'])
    ws2.append([2, 'Двойка'])

    ws3 = wb.create_sheet('Скрытый')
    ws3['A1'] = 'секрет'
    ws3.sheet_state = 'hidden'
    wb.save(path)

    # Кэшированное значение формулы: Excel пишет его рядом с <f>, openpyxl —
    # нет; без него ячейка «Итого» в предпросмотре пустая.
    total = sum(r[1] for r in rows)
    tmp = path + '.tmp'
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == 'xl/worksheets/sheet1.xml':
                s = data.decode('utf-8')
                s = s.replace('<f>SUM(B3:B5)</f><v></v>', '<f>SUM(B3:B5)</f><v>%r</v>' % total)
                s = s.replace('<f>SUM(B3:B5)</f><v />', '<f>SUM(B3:B5)</f><v>%r</v>' % total)
                assert ('<v>%r</v>' % total) in s, 'formula value not patched'
                data = s.encode('utf-8')
            zout.writestr(item, data)
    os.replace(tmp, path)


def make_ods(xlsx, out_dir):
    profile = 'file:///tmp/lo_o2'
    work = tempfile.mkdtemp()
    try:
        subprocess.run(['soffice', '-env:UserInstallation=' + profile, '--headless', '--convert-to', 'ods',
                        '--outdir', work, xlsx], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Без миниатюры (Thumbnails/thumbnail.png) — файл втрое меньше;
        # mimetype остаётся первой записью без сжатия, как требует ODF.
        src = os.path.join(work, 'sheet_sample.ods')
        dst = os.path.join(out_dir, 'sheet_sample.ods')
        with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename.startswith('Thumbnails/'):
                    continue
                data = zin.read(item.filename)
                if item.filename == 'META-INF/manifest.xml':
                    s = data.decode('utf-8')
                    s = '\n'.join(l for l in s.split('\n') if 'Thumbnails/' not in l)
                    data = s.encode('utf-8')
                zout.writestr(item, data, compress_type=item.compress_type)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def make_csv(out_dir):
    utf8 = ('Имя,Город,Сумма,Комментарий\r\n'
            'Пример один,Москва,"1,234.50","первая строка\r\nвторая строка"\r\n'
            'Пример два,"Санкт-Петербург, центр",99.9,"кавычки ""внутри"""\r\n'
            'Example,Berlin,-5,\r\n')
    with open(os.path.join(out_dir, 'sheet_utf8.csv'), 'wb') as f:
        f.write(b'\xef\xbb\xbf' + utf8.encode('utf-8'))
    cp = ('sep=;\r\n'
          'Наименование;Количество;Цена;Дата\r\n'
          'Бумага А4;10;1 234,56;05.11.2026\r\n'
          'Ручка «Шариковая»;250;12,5;06.11.2026\r\n'
          'Итого;260;;\r\n')
    with open(os.path.join(out_dir, 'sheet_cp1251.csv'), 'wb') as f:
        f.write(cp.encode('cp1251'))
    tsv = 'Колонка\tЗначение\nальфа\t1\nбета\t2,5\n"с\tтабом"\t3\n'
    with open(os.path.join(out_dir, 'sheet_tabs.tsv'), 'wb') as f:
        f.write(tsv.encode('utf-8'))


def main():
    os.makedirs(OUT, exist_ok=True)
    xlsx = os.path.join(OUT, 'sheet_sample.xlsx')
    make_xlsx(xlsx)
    make_ods(xlsx, OUT)
    make_csv(OUT)
    for n in sorted(os.listdir(OUT)):
        if n.startswith('sheet_'):
            print(n, os.path.getsize(os.path.join(OUT, n)))


if __name__ == '__main__':
    main()
