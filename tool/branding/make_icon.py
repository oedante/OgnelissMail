#!/usr/bin/env python3
"""Иконка Ogneliss Mail: огненный лис (знак из assets/branding/ogneliss-mark.svg)
и почтовый конверт в цветах приложения (AppColors: brandNavy, brandBlue,
brandAmber).

    python3 tool/branding/make_icon.py preview   — варианты для выбора
    python3 tool/branding/make_icon.py build A   — файлы выбранного варианта

Нужны cairosvg и Pillow. Холст 1024×1024; содержимое вписано в безопасную
зону адаптивной иконки Android (круг ≈ 61 % стороны), чтобы маски
производителей (круг, «сквиркл», капля) ничего не срезали.
"""
import io
import re
import sys
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
MARK = ROOT / 'assets/branding/ogneliss-mark.svg'

NAVY = '#0F2742'
BLUE = '#1D4F91'
AMBER = '#E39B2D'
AMBER_HI = '#F2B544'
PAPER = '#FFFFFF'
PAPER_SHADE = '#DCE6F3'
FOLD = '#B9CBE4'
FLAP = '#EEF3FA'

# Знак: путь с вырезом — лис образован фоном (как в прежнем логотипе, где
# белый лис — это белый фон под жёлтым пламенем). Цвет лиса = то, что позади
# пламени.
_d = re.findall(r' d="([^"]*)"', MARK.read_text())[0]
FLAME_D = _d
FLAME_OUTER = [p for p in re.split(r'(?=[Mm])', _d.strip()) if p.strip()][0]
FX0, FY0, FX1, FY1 = 808, 192, 4208, 4768  # габарит пламени в единицах знака


def flame(cx, top, height, fill=AMBER):
    """Пламя с лисом: центр по x, верх, высота — в пикселях холста 1024."""
    k = height / (FY1 - FY0)
    tx = cx - (FX0 + FX1) / 2 * k
    ty = top - FY0 * k
    g = f'<g transform="translate({tx:.2f} {ty:.2f}) scale({k:.6f})">'
    g += f'<path d="{FLAME_D}" fill="{fill}" fill-rule="evenodd"/></g>'
    return g


def bg(kind):
    if kind == 'light':
        return ('<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
                '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E7EEF7"/>'
                '</linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>')
    return ('<defs><linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
            f'<stop offset="0" stop-color="{BLUE}"/><stop offset="1" stop-color="{NAVY}"/>'
            '</linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>')


def variant_a():
    """Лис-пламя выходит из открытого конверта."""
    x0, x1, top, bot = 262, 762, 548, 800
    mid = (x0 + x1) / 2
    s = []
    # Открытый клапан (позади пламени) и внутренняя сторона конверта
    # Клапан высокий: лис (вырез в пламени) целиком на его светлом фоне —
    # светлый лис в огне, как в прежнем жёлтом логотипе.
    s.append(f'<path d="M{x0} {top} L{mid} {top-290} L{x1} {top} Z" fill="{FLAP}" '
             f'stroke="{FLAP}" stroke-width="22" stroke-linejoin="round"/>')
    s.append(f'<rect x="{x0}" y="{top}" width="{x1-x0}" height="{bot-top}" rx="18" fill="{FOLD}"/>')
    # Пламя внутри конверта
    s.append(flame(mid, 196, 470))
    # Передний карман с вырезом по центру
    s.append(f'<path d="M{x0} {top+24} Q{x0} {top} {x0+24} {top+8} L{mid} {top+104} '
             f'L{x1-24} {top+8} Q{x1} {top} {x1} {top+24} L{x1} {bot-18} Q{x1} {bot} {x1-18} {bot} '
             f'L{x0+18} {bot} Q{x0} {bot} {x0} {bot-18} Z" fill="{PAPER}"/>')
    # Нижние складки
    s.append(f'<path d="M{x0+20} {bot-14} L{mid} {top+150} L{x1-20} {bot-14}" fill="none" '
             f'stroke="{PAPER_SHADE}" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>')
    return ''.join(s)


def mono_a():
    """Одноцветный слой (тематические значки Android 13+): пламя с лисом-вырезом
    и карман конверта; клапан не рисуется, иначе лис слился бы с ним."""
    x0, x1, top, bot = 262, 762, 548, 800
    mid = (x0 + x1) / 2
    # Чёрное станет прозрачным (см. build): зазор вокруг кармана и складки.
    pocket = (f'M{x0} {top+24} Q{x0} {top} {x0+24} {top+8} L{mid} {top+104} '
              f'L{x1-24} {top+8} Q{x1} {top} {x1} {top+24} L{x1} {bot-18} Q{x1} {bot} {x1-18} {bot} '
              f'L{x0+18} {bot} Q{x0} {bot} {x0} {bot-18} Z')
    return (flame(mid, 196, 470, fill=PAPER) +
            f'<path d="{pocket}" fill="#000" stroke="#000" stroke-width="36" stroke-linejoin="round"/>'
            f'<path d="{pocket}" fill="{PAPER}"/>'
            f'<path d="M{x0+20} {bot-14} L{mid} {top+150} L{x1-20} {bot-14}" fill="none" '
            f'stroke="#000" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>')


def variant_b(mono=False):
    """Лис-пламя и крупный конверт внизу справа. Конверт крупный и с толстыми
    линиями, чтобы на 24–48 px он читался как письмо, а не как пятно.
    Окантовка цветом фона отделяет его от пламени."""
    # mono: одноцветный слой — белое знак, чёрное станет прозрачным (build).
    gap, line = ('#000', '#000') if mono else (NAVY, BLUE)
    s = [flame(452, 176, 548, fill=PAPER if mono else AMBER)]
    cx, cy, w, h = 628, 640, 318, 222
    x0, y0 = cx - w / 2, cy - h / 2
    s.append(f'<rect x="{x0-18}" y="{y0-18}" width="{w+36}" height="{h+36}" rx="46" fill="{gap}"/>')
    s.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="30" fill="{PAPER}"/>')
    s.append(f'<path d="M{x0+30} {y0+34} L{cx} {cy+26} L{x0+w-30} {y0+34}" fill="none" '
             f'stroke="{line}" stroke-width="26" stroke-linecap="round" stroke-linejoin="round"/>')
    return ''.join(s)


def variant_c():
    """Светлая иконка: синий конверт, на клапане — печать с огненным лисом."""
    x0, x1, y0, y1 = 232, 792, 330, 712
    mid = (x0 + x1) / 2
    s = [f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="40" fill="{BLUE}"/>',
         f'<path d="M{x0+30} {y1-26} L{mid-60} {y0+230} M{x1-30} {y1-26} L{mid+60} {y0+230}" '
         f'stroke="#2E64AC" stroke-width="16" stroke-linecap="round"/>',
         f'<path d="M{x0+18} {y0+22} L{mid} {y0+250} L{x1-18} {y0+22}" fill="{NAVY}" fill-opacity="0.35"/>',
         f'<path d="M{x0+18} {y0+22} L{mid} {y0+250} L{x1-18} {y0+22}" fill="none" stroke="#FFFFFF" '
         f'stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>',
         f'<circle cx="{mid}" cy="{y0+250}" r="128" fill="#FFFFFF"/>',
         flame(mid, y0 + 140, 210)]
    return ''.join(s)


def variant_d(mono=False):
    """Светлая иконка, письмо крупно: синий конверт почти во всю безопасную
    зону, на вершине клапана — печать с огненным лисом. На светлой теме не
    выглядит тёмным пятном и читается как «почта» даже на 24 px."""
    w, h = 540, 372
    x0, y0 = 512 - w / 2, 512 - h / 2 + 18
    x1, y1 = x0 + w, y0 + h
    mid = 512
    tip = y0 + 222  # вершина клапана
    if mono:
        # Одноцветный слой: конверт белый, линии клапана и печать — прорези.
        return (f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="46" fill="{PAPER}"/>'
                f'<path d="M{x0+34} {y0+34} L{mid} {tip} L{x1-34} {y0+34}" fill="none" stroke="#000" '
                f'stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>'
                f'<circle cx="{mid}" cy="{tip}" r="112" fill="#000"/>'
                f'<circle cx="{mid}" cy="{tip}" r="92" fill="{PAPER}"/>'
                + flame(mid, tip - 70, 140, fill='#000'))
    s = [
        # Тень под конвертом — мягкая, чтобы на белом фоне он не «плавал».
        f'<rect x="{x0}" y="{y0+14}" width="{w}" height="{h}" rx="46" fill="{NAVY}" fill-opacity="0.16"/>',
        f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="46" fill="{BLUE}"/>',
        # Нижние складки
        f'<path d="M{x0+40} {y1-34} L{mid-96} {tip-6} M{x1-40} {y1-34} L{mid+96} {tip-6}" '
        f'stroke="#3A74C2" stroke-width="22" stroke-linecap="round"/>',
        # Клапан
        f'<path d="M{x0+30} {y0+30} L{mid} {tip} L{x1-30} {y0+30} Z" fill="#163F77"/>',
        f'<path d="M{x0+34} {y0+34} L{mid} {tip} L{x1-34} {y0+34}" fill="none" stroke="{PAPER}" '
        f'stroke-width="26" stroke-linecap="round" stroke-linejoin="round"/>',
        # Печать с лисом-пламенем
        f'<circle cx="{mid}" cy="{tip}" r="104" fill="{PAPER}"/>',
        f'<circle cx="{mid}" cy="{tip}" r="104" fill="none" stroke="{AMBER}" stroke-width="10"/>',
        flame(mid, tip - 72, 144),
    ]
    return ''.join(s)


def variant_e(mono=False):
    """Светлая иконка: крупный белый конверт с синим контуром, лис-пламя
    выглядывает из-под клапана."""
    w, h = 556, 384
    x0, y0 = 512 - w / 2, 512 - h / 2 + 40
    x1, y1 = x0 + w, y0 + h
    mid = 512
    tip = y0 + 200
    s = [flame(mid, y0 - 196, 330, fill=PAPER if mono else AMBER)]
    if not mono:
        s.append(f'<rect x="{x0}" y="{y0+12}" width="{w}" height="{h}" rx="44" fill="{NAVY}" fill-opacity="0.14"/>')
    s.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="44" fill="{PAPER}" '
             f'stroke="{"#000" if mono else BLUE}" stroke-width="26"/>')
    s.append(f'<path d="M{x0+40} {y0+40} L{mid} {tip} L{x1-40} {y0+40}" fill="none" '
             f'stroke="{"#000" if mono else BLUE}" stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>')
    return ''.join(s)


VARIANTS = {
    'A': ('Из конверта', variant_a, 'dark'),
    'B': ('Знак и конверт', variant_b, 'dark'),
    'C': ('Печать на конверте', variant_c, 'light'),
    'D': ('Светлая, письмо крупно', variant_d, 'light'),
    'E': ('Белый конверт, лис над ним', variant_e, 'light'),
}
MONO = {
    'A': mono_a,
    'B': lambda: variant_b(mono=True),
    'D': lambda: variant_d(mono=True),
    'E': lambda: variant_e(mono=True),
}


def svg(content, background=None, scale=1.0):
    b = bg(background) if background else ''
    if scale != 1.0:
        o = 512 * (1 - scale)
        content = f'<g transform="translate({o:.1f} {o:.1f}) scale({scale})">{content}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{b}{content}</svg>')


# Иконка без маски адаптивной (до Android 8, iOS, сайт, «О приложении»):
# фон занимает весь квадрат, поэтому знак можно сделать крупнее.
FULL_SCALE = 1.16


def png(svg_text, size=1024):
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg_text.encode(),
                                                   output_width=size, output_height=size))).convert('RGBA')


def masked(im, shape):
    m = Image.new('L', im.size, 0)
    d = ImageDraw.Draw(m)
    w, h = im.size
    if shape == 'circle':
        d.ellipse((0, 0, w - 1, h - 1), fill=255)
    else:
        d.rounded_rectangle((0, 0, w - 1, h - 1), radius=int(w * 0.23), fill=255)
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def preview(out):
    cell, small = 300, 96
    sheet = Image.new('RGBA', (len(VARIANTS) * (cell + 40) + 40, cell + cell // 2 + 140), '#F3F4F6')
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 22)
    except OSError:
        font = None
    for i, (key, (title, fn, kind)) in enumerate(VARIANTS.items()):
        im = png(svg(fn(), kind), cell)
        x = 40 + i * (cell + 40)
        sheet.paste(masked(im, 'squircle'), (x, 60), masked(im, 'squircle'))
        c = masked(im, 'circle').resize((cell // 2, cell // 2), Image.LANCZOS)
        sheet.paste(c, (x, 60 + cell + 30), c)
        s = masked(im, 'squircle').resize((small, small), Image.LANCZOS)
        sheet.paste(s, (x + cell // 2 + 30, 60 + cell + 30), s)
        s2 = masked(im, 'squircle').resize((48, 48), Image.LANCZOS)
        sheet.paste(s2, (x + cell // 2 + 30 + small + 20, 60 + cell + 30), s2)
        s3 = masked(im, 'squircle').resize((32, 32), Image.LANCZOS)
        sheet.paste(s3, (x + cell // 2 + 30 + small + 20, 60 + cell + 30 + 60), s3)
        # Безопасная зона адаптивной иконки (круг 66/108) — пунктиром.
        r = cell * 0.3056
        d.ellipse((x + cell / 2 - r, 60 + cell / 2 - r, x + cell / 2 + r, 60 + cell / 2 + r),
                  outline='#FF4D4D', width=1)
        d.text((x, 18), f'{key}. {title}', fill='#1A1F26', font=font)
    sheet.save(out)
    print(out)


def fit_safe(im, radius=322):
    """Передний план адаптивной иконки: Android показывает центральные 72 из
    108 dp (683 px из 1024) и обрезает их маской — у круглой маски радиус
    341 px. Если содержимое выходит за [radius] от центра, уменьшаем его."""
    a = im.getchannel('A').point(lambda v: 255 if v > 24 else 0)
    w, h = im.size
    px = a.load()
    far = 0
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            if px[x, y]:
                far = max(far, ((x - w / 2) ** 2 + (y - h / 2) ** 2) ** 0.5)
    if far <= radius:
        return im
    k = radius / far
    n = round(w * k)
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    small = im.resize((n, n), Image.LANCZOS)
    out.paste(small, ((w - n) // 2, (h - n) // 2), small)
    return out


def adaptive_preview(fg, back, size):
    """Как Android покажет адаптивную иконку под круглой маской."""
    im = back.copy()
    im.alpha_composite(fg)
    c = (1024 - 683) // 2
    return masked(im.crop((c, c, c + 683, c + 683)), 'circle').resize((size, size), Image.LANCZOS)


def build(key):
    """Все файлы иконки выбранного варианта: assets (для flutter_launcher_icons и
    экрана «О приложении»), ресурсы Android, значок в трее Windows, сайт."""
    title, fn, kind = VARIANTS[key]
    icons = ROOT / 'assets/icons'
    res = ROOT / 'android/app/src/main/res'
    bgc = '#FFFFFF' if kind == 'light' else BLUE

    full = png(svg(fn(), kind, FULL_SCALE))
    full.convert('RGB').save(icons / 'app_icon.png')
    fg = fit_safe(png(svg(fn())))
    fg.save(icons / 'app_icon_foreground.png')
    mono_fn = MONO.get(key)
    mono = png(svg(mono_fn())) if mono_fn else fg
    if mono_fn:
        # Одноцветный слой: белое — знак, чёрное — прозрачные зазоры.
        lum = mono.convert('L')
        a = Image.composite(lum, Image.new('L', mono.size, 0), mono.getchannel('A'))
        mono = fit_safe(Image.merge('RGBA', (*[Image.new('L', mono.size, 255)] * 3, a)))
    else:
        # Без отдельного рисунка — силуэт переднего плана.
        mono = Image.merge('RGBA', (*[Image.new('L', fg.size, 255)] * 3, fg.getchannel('A')))
    mono.save(icons / 'app_icon_monochrome.png')
    back = png(svg('', kind))
    back.convert('RGB').save(icons / 'app_icon_background.png')
    (ROOT / 'assets/branding/ogneliss-mail-icon.svg').write_text(svg(fn(), kind, FULL_SCALE))

    adaptive_preview(fg, back, 256).save(ROOT / 'docs/plan/icon_adaptive_preview.png')
    # Android: обычная и круглая иконка (до Android 8), слои адаптивной (108 dp).
    for dpi, n in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        sq = masked(full, 'squircle').resize((n, n), Image.LANCZOS)
        sq.save(res / f'mipmap-{dpi}/ic_launcher.png')
        masked(full, 'circle').resize((n, n), Image.LANCZOS).save(res / f'mipmap-{dpi}/ic_launcher_round.png')
        f = n * 108 // 48
        fg.resize((f, f), Image.LANCZOS).save(res / f'drawable-{dpi}/ic_launcher_foreground.png')
        mono.resize((f, f), Image.LANCZOS).save(res / f'drawable-{dpi}/ic_launcher_monochrome.png')
        # Фон адаптивной иконки — градиент, как у полной иконки (цветом — плоско).
        back.convert('RGB').resize((f, f), Image.LANCZOS).save(res / f'drawable-{dpi}/ic_launcher_background.png')
    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        (res / 'mipmap-anydpi-v26' / name).write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
            '</adaptive-icon>\n')
    colors = res / 'values/colors.xml'
    colors.write_text(re.sub(r'(<color name="ic_launcher_background">)[^<]*(</color>)',
                             rf'\g<1>{bgc}\g<2>', colors.read_text()))

    # Windows: значок в трее.
    full.save(icons / 'tray_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)])
    # Сайт: страница Mail.
    site = ROOT / 'site/mail/app-icon.png'
    if site.exists():
        masked(full, 'squircle').resize((512, 512), Image.LANCZOS).save(site)

    print(f'{key}: {title}; фон адаптивной иконки {bgc}. '
          'Файлы для flutter_launcher_icons: assets/icons/app_icon*.png')
    return bgc


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'build':
        build(sys.argv[2])
    else:
        preview(sys.argv[2] if len(sys.argv) > 2 else 'icon_variants.png')
