#!/usr/bin/env python3
"""Fixtures for the slide preview tests (1.11.x, office document preview).

Creates in test/fixtures/office/:
  slides.pptx     - python-pptx: title, two-level bullets, picture + coloured
                    shapes, table with a merged cell, group, hidden slide.
  slides.odp      - the same converted by LibreOffice.
  slides_lo.pptx  - the same saved back by LibreOffice (another producer).

Usage (from the repo root):
  python3 tool/dev/office_fixtures/slides.py
LibreOffice runs with its own profile so it does not clash with other
soffice processes.
"""

import io
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

from PIL import Image, ImageDraw
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Pt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
OUT = os.path.join(ROOT, 'test', 'fixtures', 'office')
PROFILE = 'file:///tmp/lo_o3'


def picture() -> bytes:
    """Small PNG: sky, sun and a hill (a few hundred bytes)."""
    im = Image.new('RGB', (160, 100), (120, 180, 230))
    d = ImageDraw.Draw(im)
    d.ellipse((110, 10, 145, 45), fill=(250, 210, 60))
    d.polygon([(0, 100), (0, 70), (60, 45), (160, 80), (160, 100)], fill=(70, 150, 80))
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def build(path: str) -> None:
    # Default template: 4:3, 10 x 7.5 in (9144000 x 6858000 EMU).
    prs = Presentation()

    # 1. Title slide.
    s = prs.slides.add_slide(prs.slide_layouts[0])
    s.shapes.title.text = 'Квартальный отчёт'
    s.placeholders[1].text = 'Отдел продаж · IV квартал 2026'

    # 2. Bullets, two levels.
    s = prs.slides.add_slide(prs.slide_layouts[1])
    s.shapes.title.text = 'Итоги квартала'
    tf = s.placeholders[1].text_frame
    tf.text = 'Выручка выросла на 12 %'
    for text, level in [('Москва — плюс 15 %', 1), ('Новосибирск — плюс 9 %', 1),
                        ('Новые клиенты: 48', 0), ('Планы на следующий год', 0)]:
        p = tf.add_paragraph()
        p.text = text
        p.level = level

    # 3. Picture and coloured shapes.
    s = prs.slides.add_slide(prs.slide_layouts[5])  # title only
    s.shapes.title.text = 'Картинка и фигуры'
    s.shapes.add_picture(io.BytesIO(picture()), Emu(457200), Emu(1600200), width=Emu(3800000))
    box = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Emu(4572000), Emu(1600200), Emu(4114800), Emu(1143000))
    box.fill.solid()
    box.fill.fore_color.rgb = RGBColor(0xE0, 0x6C, 0x2A)
    box.line.color.rgb = RGBColor(0x80, 0x30, 0x10)
    box.line.width = Pt(2)
    box.text_frame.text = 'Оранжевая плашка'
    box.text_frame.paragraphs[0].runs[0].font.bold = True
    box.text_frame.paragraphs[0].runs[0].font.size = Pt(24)
    oval = s.shapes.add_shape(MSO_SHAPE.OVAL, Emu(4572000), Emu(3200400), Emu(1600200), Emu(1600200))
    oval.fill.solid()
    oval.fill.fore_color.rgb = RGBColor(0x2A, 0x7A, 0xE0)
    tilted = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Emu(6400800), Emu(3429000), Emu(2057400), Emu(1028700))
    tilted.rotation = 30
    tilted.fill.solid()
    tilted.fill.fore_color.rgb = RGBColor(0x3C, 0xA0, 0x50)
    tilted.text_frame.text = 'Повёрнуто'

    # 4. Table with a merged header cell.
    s = prs.slides.add_slide(prs.slide_layouts[5])
    s.shapes.title.text = 'Продажи по городам'
    rows, cols = 4, 3
    gf = s.shapes.add_table(rows, cols, Emu(457200), Emu(1600200), Emu(8229600), Emu(2286000))
    t = gf.table
    data = [['Город', 'Квартал', ''], ['Москва', '120', '135'], ['Казань', '64', '70'], ['Итого', '184', '205']]
    for r in range(rows):
        for c in range(cols):
            t.cell(r, c).text = data[r][c]
    t.cell(0, 1).merge(t.cell(0, 2))
    t.cell(0, 1).text = 'Квартал'

    # 5. Group: two shapes inside a group.
    s = prs.slides.add_slide(prs.slide_layouts[6])  # blank
    g = s.shapes.add_group_shape()
    a = g.shapes.add_shape(MSO_SHAPE.RECTANGLE, Emu(1000000), Emu(1000000), Emu(2000000), Emu(1000000))
    a.fill.solid()
    a.fill.fore_color.rgb = RGBColor(0x99, 0x33, 0xCC)
    a.text_frame.text = 'В группе'
    b = g.shapes.add_shape(MSO_SHAPE.OVAL, Emu(3500000), Emu(1500000), Emu(1000000), Emu(1000000))
    b.fill.solid()
    b.fill.fore_color.rgb = RGBColor(0xCC, 0x33, 0x66)
    # The group is stretched 1.5 times: children (chOff/chExt 1000000,1000000
    # 3500000x1500000) land at off 600000,1200000 with ext 5250000x2250000.
    xfrm = g._element.grpSpPr.find(qn('a:xfrm'))
    xfrm.find(qn('a:off')).set('x', '600000')
    xfrm.find(qn('a:off')).set('y', '1200000')
    xfrm.find(qn('a:ext')).set('cx', '5250000')
    xfrm.find(qn('a:ext')).set('cy', '2250000')
    tb = s.shapes.add_textbox(Emu(1000000), Emu(4400000), Emu(7000000), Emu(800000))
    tb.text_frame.text = 'Надпись вне группы'
    tb.text_frame.paragraphs[0].alignment = PP_ALIGN.CENTER

    # 6. Hidden slide: must be skipped.
    s = prs.slides.add_slide(prs.slide_layouts[5])
    s.shapes.title.text = 'Скрытый слайд'
    s._element.set('show', '0')

    # 7. Last slide with a coloured background.
    s = prs.slides.add_slide(prs.slide_layouts[5])
    s.shapes.title.text = 'Спасибо!'
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = RGBColor(0xFF, 0xF4, 0xD6)

    prs.save(path)


def soffice(src: str, fmt: str, outdir: str) -> str:
    subprocess.run(['soffice', f'-env:UserInstallation={PROFILE}', '--headless', '--convert-to', fmt,
                    '--outdir', outdir, src], check=True, stdout=subprocess.DEVNULL)
    base = os.path.splitext(os.path.basename(src))[0]
    return os.path.join(outdir, f'{base}.{fmt.split(":")[0]}')


def repack(path: str) -> None:
    """Recompress a ZIP package at level 9 (LibreOffice's PPTX is ~60 KB otherwise)."""
    tmp = path + '.tmp'
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, 'w') as zout:
        for info in zin.infolist():
            zout.writestr(info.filename, zin.read(info.filename), compress_type=zipfile.ZIP_DEFLATED,
                          compresslevel=9)
    os.replace(tmp, path)


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    pptx = os.path.join(OUT, 'slides.pptx')
    build(pptx)
    with tempfile.TemporaryDirectory() as tmp:
        odp = soffice(pptx, 'odp', tmp)
        shutil.copy(odp, os.path.join(OUT, 'slides.odp'))
        # Back to PPTX from the ODP: LibreOffice writes its own structure
        # (custGeom, its own layouts and theme).
        lo_dir = os.path.join(tmp, 'lo')
        os.makedirs(lo_dir)
        lo = soffice(odp, 'pptx', lo_dir)
        shutil.copy(lo, os.path.join(OUT, 'slides_lo.pptx'))
    repack(os.path.join(OUT, 'slides_lo.pptx'))
    for n in ('slides.pptx', 'slides.odp', 'slides_lo.pptx'):
        print(n, os.path.getsize(os.path.join(OUT, n)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
