#!/usr/bin/env python3
"""Иконка Ogneliss Mail, редакция 5 (09.10.2026): конверт с огненной лисой.

Исходник — растровый макет владельца (1024×1024, во всю площадь, без
скругления). 12.10.2026 (1.5.11) — новый макет: сланцевый фон #394450,
светло-серый конверт, в клапане — золотистое пламя с белой лисой (прежний:
графитовый фон #2E343A, белый конверт, жёлтое пламя). Из него собираются
все размеры:

    python3 tool/branding/make_icon_v5.py build [исходник.png]
    python3 tool/branding/make_icon_v5.py preview [исходник.png]

По умолчанию исходник — assets/branding/app-icon-source.png.

Что пишется в build:
  assets/icons/app_icon*.png               — исходники (трей Windows, web)
  assets/icons/tray_icon.ico               — значок трея Windows
  assets/brand/fox_icon.png                — знак внутри приложения (вход, «О программе»)
  android/.../drawable-*/ic_launcher_*.png — слои адаптивной иконки (108 dp)
  android/.../drawable-*/splash_fox.png    — заставка (круг со знаком)
  android/.../mipmap-*/ic_launcher*.png    — значок для Android < 8
  android/.../values/colors.xml            — ic_launcher_background
  ios/Runner/Assets.xcassets/AppIcon...    — значки iOS (без прозрачности)
  ios/.../LaunchImage.imageset             — заставка iOS
  site/mail/*                              — иконки сайта почты
  docs/store/icons/play-icon-512.png, docs/store/icons/app-store-icon-1024.png

Знак (конверт с пламенем) вырезается из фона по цвету: прозрачность —
по расстоянию до цвета фона, цвет краёв восстанавливается (сглаживание не
даёт тёмной каймы на светлом фоне). Внутренние тёмные линии конверта — цвета
фона — становятся прозрачными: на фоне адаптивной иконки они того же цвета.
"""
import base64
import io
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SS = 2048  # рабочий размер

ADAPTIVE_W = 0.46   # ширина знака на холсте 108 dp (вписан в безопасный круг 66 dp)
LEGACY_PAD = 0.06   # поля значка Android < 8
ROUND_W = 0.60      # ширина знака в круглом значке
SPLASH_CIRCLE = 0.66  # круг заставки Android 12 (видна середина 2/3 холста)
SPLASH_W = 0.40
TILE_R = 0.225

DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
IOS_ICONS = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167, 'Icon-App-1024x1024@1x.png': 1024,
}


def load_source(path):
    im = Image.open(path)
    if im.mode == 'CMYK':
        im = im.convert('RGB')
    return im.convert('RGB').resize((SS, SS), Image.LANCZOS)


def background_of(src):
    w, h = src.size
    pts = [(4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5), (w // 2, 6), (6, h // 2)]
    cs = [src.getpixel(p) for p in pts]
    return tuple(sorted(c[i] for c in cs)[len(cs) // 2] for i in range(3))


def extract_mark(src, bg):
    """Знак на прозрачном фоне, обрезанный по границам."""
    w, h = src.size
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    sp, op = src.load(), out.load()
    full = 90.0  # от этого расстояния до фона — полностью непрозрачно
    for y in range(h):
        for x in range(w):
            r, g, b = sp[x, y]
            d = math.dist((r, g, b), bg)
            if d < 12:
                continue
            a = min(1.0, d / full)
            # Восстановить цвет без примеси фона: c = (p - (1-a)·bg) / a.
            c = tuple(max(0, min(255, round((v - (1 - a) * bv) / a))) for v, bv in zip((r, g, b), bg))
            op[x, y] = (*c, round(a * 255))
    return out.crop(out.getbbox())


def mono_of(mark):
    """Одноцветный слой (тематические значки Android 13+): белый конверт,
    пламя — вырез, лиса в нём — белая."""
    m = Image.new('RGBA', mark.size, (0, 0, 0, 0))
    sp, op = mark.load(), m.load()
    for y in range(mark.size[1]):
        for x in range(mark.size[0]):
            r, g, b, a = sp[x, y]
            if a == 0:
                continue
            # Насыщенный жёлтый (пламя) — прозрачен; белое и светлое — нет.
            yellow = (r + g) / 2 - b
            k = 0.0 if yellow > 120 else (1.0 if yellow < 60 else (120 - yellow) / 60)
            op[x, y] = (255, 255, 255, round(a * k))
    return m


def place(canvas_size, mark, width_frac, bg=None, shape=None, shape_frac=1.0, radius=TILE_R):
    c = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    if bg is not None:
        mk = Image.new('L', (canvas_size, canvas_size), 0)
        d = ImageDraw.Draw(mk)
        inset = canvas_size * (1 - shape_frac) / 2
        box = (inset, inset, canvas_size - inset, canvas_size - inset)
        if shape == 'circle':
            d.ellipse(box, fill=255)
        elif shape == 'rounded':
            d.rounded_rectangle(box, radius=(canvas_size - 2 * inset) * radius, fill=255)
        else:
            d.rectangle(box, fill=255)
        c.paste(Image.new('RGBA', (canvas_size, canvas_size), (*bg, 255)), (0, 0), mk)
    mw = round(canvas_size * width_frac)
    mh = round(mark.size[1] * mw / mark.size[0])
    m = mark.resize((mw, mh), Image.LANCZOS)
    c.alpha_composite(m, ((canvas_size - mw) // 2, (canvas_size - mh) // 2))
    return c


def down(img, n):
    return img.resize((n, n), Image.LANCZOS)


def masters(src_path):
    src = load_source(src_path)
    bg = background_of(src)
    mark = extract_mark(src, bg)
    src_w = mark.size[0] / SS  # доля ширины знака в исходнике (≈ 0.74)
    return {
        'bgc': bg,
        'full_sq': src.convert('RGBA'),
        'tile': place(SS, mark, src_w, bg=bg, shape='rounded'),
        'legacy': place(SS, mark, src_w * (1 - 2 * LEGACY_PAD), bg=bg, shape='rounded', shape_frac=1 - 2 * LEGACY_PAD),
        'round': place(SS, mark, ROUND_W, bg=bg, shape='circle', shape_frac=0.92),
        'bg': Image.new('RGBA', (SS, SS), (*bg, 255)),
        'fg': place(SS, mark, ADAPTIVE_W),
        'mono': place(SS, mono_of(mark), ADAPTIVE_W),
        'splash': place(SS, mark, SPLASH_W, bg=bg, shape='circle', shape_frac=SPLASH_CIRCLE),
        'mark': mark,
    }


def hexc(c):
    return '#%02X%02X%02X' % c


def build(m):
    out = []

    def save(img, path, rgb=False):
        p = ROOT / path
        p.parent.mkdir(parents=True, exist_ok=True)
        (img.convert('RGB') if rgb else img).save(p, optimize=True)
        out.append(path)

    res = ROOT / 'android/app/src/main/res'
    for d, k in DENS.items():
        a, l = int(108 * k), int(48 * k)
        save(down(m['bg'], a), f'android/app/src/main/res/drawable-{d}/ic_launcher_background.png')
        save(down(m['fg'], a), f'android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png')
        save(down(m['mono'], a), f'android/app/src/main/res/drawable-{d}/ic_launcher_monochrome.png')
        save(down(m['splash'], a), f'android/app/src/main/res/drawable-{d}/splash_fox.png')
        save(down(m['legacy'], l), f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
        if (res / f'mipmap-{d}/ic_launcher_round.png').exists():
            save(down(m['round'], l), f'android/app/src/main/res/mipmap-{d}/ic_launcher_round.png')

    save(down(m['full_sq'], 1024), 'assets/icons/app_icon.png', rgb=True)
    save(down(m['bg'], 1024), 'assets/icons/app_icon_background.png')
    save(down(m['fg'], 1024), 'assets/icons/app_icon_foreground.png')
    save(down(m['mono'], 1024), 'assets/icons/app_icon_monochrome.png')
    save(down(m['full_sq'], 512), 'assets/brand/fox_icon.png', rgb=True)
    save(down(m['full_sq'], 1024), 'assets/branding/app-icon-source.png', rgb=True)
    save(down(m['full_sq'], 512), 'docs/store/icons/play-icon-512.png', rgb=True)
    save(down(m['full_sq'], 1024), 'docs/store/icons/app-store-icon-1024.png', rgb=True)
    save(down(m['tile'], 256), 'site/mail/app-icon.png')
    save(down(m['full_sq'], 180), 'site/mail/apple-touch-icon.png', rgb=True)
    save(down(m['tile'], 32), 'site/mail/favicon-32.png')
    save(down(m['full_sq'], 120), 'site/mail/logo-120.png', rgb=True)

    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    if ios.exists():
        for name, px in IOS_ICONS.items():
            save(down(m['full_sq'], px), f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}', rgb=True)
    launch = ROOT / 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    if launch.exists():
        for name, k in (('LaunchImage.png', 1), ('LaunchImage@2x.png', 2), ('LaunchImage@3x.png', 3)):
            w, h = 150 * k, 111 * k
            c = Image.new('RGBA', (w, h), (0, 0, 0, 0))
            t = down(m['tile'], h)
            c.alpha_composite(t, ((w - h) // 2, 0))
            save(c, f'ios/Runner/Assets.xcassets/LaunchImage.imageset/{name}')

    # favicon.svg — растровый знак внутри SVG (рисунок пламени и лисы
    # вектором не воспроизводится один в один).
    buf = io.BytesIO()
    down(m['tile'], 128).save(buf, 'PNG', optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'
           f'<image width="128" height="128" href="data:image/png;base64,{b64}"/></svg>\n')
    (ROOT / 'site/mail/favicon.svg').write_text(svg)
    (ROOT / 'assets/branding/ogneliss-mail-icon.svg').write_text(svg)
    out += ['site/mail/favicon.svg', 'assets/branding/ogneliss-mail-icon.svg']
    down(m['tile'], 256).save(ROOT / 'assets/icons/tray_icon.ico',
                              sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    colors = res / 'values/colors.xml'
    txt = colors.read_text()
    txt = re.sub(r'(<color name="ic_launcher_background">)#[0-9A-Fa-f]+(</color>)',
                 rf'\g<1>{hexc(m["bgc"])}\g<2>', txt)
    colors.write_text(txt)
    return out


def preview(m, path):
    comp = m['bg'].copy()
    comp.alpha_composite(m['fg'])
    tiles = []
    for shape in ('circle', 'squircle'):
        mk = Image.new('L', (SS, SS), 0)
        d = ImageDraw.Draw(mk)
        inset = SS * 18 / 108
        box = (inset, inset, SS - inset, SS - inset)
        if shape == 'circle':
            d.ellipse(box, fill=255)
        else:
            d.rounded_rectangle(box, radius=(SS - 2 * inset) * 0.3, fill=255)
        c = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
        c.paste(comp, (0, 0), mk)
        tiles.append(down(c, 256))
    mono = Image.new('RGBA', (SS, SS), (0x2A, 0x33, 0x40, 255))
    mono.alpha_composite(m['mono'])
    tiles += [down(mono, 256), down(m['legacy'], 256), down(m['round'], 256), down(m['splash'], 256)]
    sheet = Image.new('RGBA', (len(tiles) * 270 + 10, 276), (235, 235, 235, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t, (10 + i * 270, 10))
    sheet.save(path)


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    srcp = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / 'assets/branding/app-icon-source.png')
    ms = masters(srcp)
    if cmd == 'build':
        for p in build(ms):
            print(p)
    preview(ms, ROOT / 'tool/branding/preview_v5.png')
