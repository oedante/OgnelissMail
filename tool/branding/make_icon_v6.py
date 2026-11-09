#!/usr/bin/env python3
"""Иконка Ogneliss Mail, редакция 6 (08.11.2026): светлая.

Просьба владельца 08.11.2026: «иконку в светлых тонах, но лиса и пламя
должны остаться»; выбран вариант A «светлый» (build/out/icon_light, лист
сравнения): тёплый светлый фон с вертикальным градиентом, белый конверт с
графитовыми линиями и мягкой тенью, пламя с лисой — как в макете.

Мастер — прежний тёмный макет владельца
assets/branding/app-icon-source-dark.png (1024×1024, сланцевый фон,
светло-серый конверт, золотистое пламя с белой лисой). Из него светлый
вариант получается всегда одинаково:
  • фон — градиент BG_TOP → BG_BOTTOM;
  • конверт (скруглённый прямоугольник ENVELOPE) — по яркости макета:
    тёмное — LINE, светлое — PAPER, переходы — смешение;
  • пламя и лиса (золотистое: R−B > 45 и R > 110) — пиксели макета;
  • тень конверта — размытая форма конверта, сдвинутая вниз.

    python3 tool/branding/make_icon_v6.py build [тёмный макет.png]
    python3 tool/branding/make_icon_v6.py desktop [тёмный макет.png]
    python3 tool/branding/make_icon_v6.py preview [тёмный макет.png]

Пишет те же файлы, что make_icon_v5.py (список — там; светлый исходник —
assets/branding/app-icon-source.png). Отличие от v5: знак не вырезается по
цвету фона (белый конверт на светлом фоне так не отделить) — слои строятся
по форме конверта. Одноцветный слой (тематические значки Android 13+) —
как в v5, из тёмного макета: форма та же.

Иконки сайта (site/mail/*) — папка site/ в git не входит; после build они
лежат там же, их выкладывает владелец вместе с сайтом.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_icon_v5 as v5  # noqa: E402  (тот же каталог)

ROOT = v5.ROOT
SS = v5.SS

BG_TOP = (250, 248, 244)
BG_BOTTOM = (238, 234, 227)
PAPER = (255, 255, 255)
LINE = (74, 86, 100)
L_DARK, L_LIGHT = 62.0, 233.0  # яркость линий и бумаги в тёмном макете
SHADOW = 0.18
# Конверт в макете 1024×1024 (с запасом 2 точки на сглаженный край).
ENVELOPE = (132, 203, 891, 820)
ENVELOPE_R = 44
ENV_W = (ENVELOPE[2] - ENVELOPE[0]) / 1024  # доля ширины конверта (≈ 0,74)


def gradient(w, h):
    """Фон: вертикальный градиент BG_TOP → BG_BOTTOM."""
    g = Image.linear_gradient('L').resize((w, h), Image.BICUBIC)
    chans = [g.point(lambda v, a=a, b=b: round(a + (b - a) * v / 255)) for a, b in zip(BG_TOP, BG_BOTTOM)]
    return Image.merge('RGB', chans)


def envelope_mask(size):
    """Форма конверта со сглаженным краем (рисуется вдвое крупнее)."""
    k = size / 1024 * 2
    big = Image.new('L', (size * 2, size * 2), 0)
    x0, y0, x1, y1 = (round(v * k) for v in ENVELOPE)
    ImageDraw.Draw(big).rounded_rectangle([x0, y0, x1, y1], radius=round(ENVELOPE_R * k), fill=255)
    return big.resize((size, size), Image.BOX)


def light_layers(dark):
    """Светлый вариант из тёмного макета: (полный квадрат RGB, слой знака
    RGBA — конверт с тенью на прозрачном)."""
    size = dark.size[0]
    env = envelope_mask(size)
    # Конверт по яркости макета: тёмное — LINE, светлое — PAPER.
    lum = dark.convert('L', (1 / 3, 1 / 3, 1 / 3, 0))

    def lut(line, paper):
        def f(v):
            t = min(1.0, max(0.0, (v - L_DARK) / (L_LIGHT - L_DARK)))
            return round(line * (1 - t) + paper * t)
        return f

    paper = Image.merge('RGB', [lum.point(lut(a, b)) for a, b in zip(LINE, PAPER)])
    # Пламя и лиса — как в макете.
    r, _, b = dark.split()
    gold = ImageChops.multiply(
        ImageChops.subtract(r, b).point(lambda v: 255 if v > 45 else 0),
        r.point(lambda v: 255 if v > 110 else 0),
    )
    paper = Image.composite(dark, paper, gold)
    # Тень: размытая форма конверта, ниже на 14/1024.
    k = size / 1024
    blur = env.filter(ImageFilter.GaussianBlur(28 * k))
    sh = Image.new('L', (size, size), 0)
    sh.paste(blur, (0, round(14 * k)))
    sh = sh.point(lambda v: round(v * SHADOW))
    black = Image.new('RGB', (size, size), (0, 0, 0))
    full = Image.composite(paper, Image.composite(black, gradient(size, size), sh), env)
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    layer.paste(black, (0, 0), sh)
    mark = paper.convert('RGBA')
    mark.putalpha(env)
    layer.alpha_composite(mark)
    return full, layer


def shape_mask(size, shape, frac, radius=v5.TILE_R):
    mk = Image.new('L', (size * 2, size * 2), 0)
    inset = size * 2 * (1 - frac) / 2
    box = (inset, inset, size * 2 - inset, size * 2 - inset)
    d = ImageDraw.Draw(mk)
    if shape == 'circle':
        d.ellipse(box, fill=255)
    elif shape == 'rounded':
        d.rounded_rectangle(box, radius=(size * 2 - 2 * inset) * radius, fill=255)
    else:
        d.rectangle(box, fill=255)
    return mk.resize((size, size), Image.BOX)


def place(layer, width_frac, shape=None, shape_frac=1.0):
    """Конверт шириной [width_frac] холста по центру; с [shape] — на
    светлом фоне этой формы (градиент — по высоте формы)."""
    c = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
    if shape is not None:
        side = round(SS * shape_frac)
        off = (SS - side) // 2
        c.paste(gradient(side, side).convert('RGBA'), (off, off))
    n = round(SS * width_frac / ENV_W)
    m = layer.resize((n, n), Image.LANCZOS)
    if n > SS:
        cut = (n - SS) // 2
        m = m.crop((cut, cut, cut + SS, cut + SS))
        c.alpha_composite(m)
    else:
        c.alpha_composite(m, ((SS - n) // 2, (SS - n) // 2))
    if shape is not None:
        c.putalpha(ImageChops.multiply(c.getchannel('A'), shape_mask(SS, shape, shape_frac)))
    return c


def mac_tile(layer):
    """Значок macOS: плитка 824/1024 по центру и мягкая тень снизу (как v5)."""
    tile = place(layer, ENV_W * v5.MAC_TILE, 'rounded', v5.MAC_TILE)
    k = SS / 1024
    shadow = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
    a = tile.getchannel('A').point(lambda v: v * 0.22)
    shadow.paste(Image.new('RGBA', (SS, SS), (0, 0, 0, 255)), (0, round(10 * k)), a)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10 * k))
    shadow.alpha_composite(tile)
    return shadow


def masters(dark_path):
    dark = v5.load_source(dark_path)
    full, layer = light_layers(dark)
    # Одноцветный слой — из тёмного макета, как в v5 (форма знака та же).
    dark_mark = v5.extract_mark(dark, v5.background_of(dark))
    mid = tuple((a + b) // 2 for a, b in zip(BG_TOP, BG_BOTTOM))
    return {
        'bgc': mid,
        'full_sq': full.convert('RGBA'),
        'tile': place(layer, ENV_W, 'rounded'),
        'legacy': place(layer, ENV_W * (1 - 2 * v5.LEGACY_PAD), 'rounded', 1 - 2 * v5.LEGACY_PAD),
        'round': place(layer, v5.ROUND_W, 'circle', 0.92),
        'bg': gradient(SS, SS).convert('RGBA'),
        'fg': place(layer, v5.ADAPTIVE_W),
        'mono': v5.place(SS, v5.mono_of(dark_mark), v5.ADAPTIVE_W),
        'splash': place(layer, v5.SPLASH_W, 'circle', v5.SPLASH_CIRCLE),
        'mac': mac_tile(layer),
        'mark': layer,
    }


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    srcp = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / 'assets/branding/app-icon-source-dark.png')
    ms = masters(srcp)
    if cmd == 'build':
        for p in v5.build(ms):
            print(p)
    elif cmd == 'desktop':
        for p in v5.build_desktop(ms):
            print(p)
    v5.preview(ms, ROOT / 'tool/branding/preview_v6.png')
