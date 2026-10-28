#!/usr/bin/env python3
"""Иконка Ogneliss Mail, редакция 4 (октябрь 2026): конверт с лисьими ушками.

Та же строгая корпоративная геометрия, что в редакции 3: сланцево-синий
скруглённый квадрат (#46566C), светлый конверт (#F1F0EC), клапан остриём
вниз (#6A8293). Над верхними углами конверта — два заострённых уха цвета
конверта со скруглёнными вершинами и внутренней частью цвета клапана:
отсылка к лисе «Огнелисс» без отхода от корпоративного стиля.

    python3 tool/branding/make_icon_v4.py build    — записать все ресурсы
    python3 tool/branding/make_icon_v4.py preview  — только лист предпросмотра

Нужен только Pillow. Рисуем с суперсэмплингом (4096 px) и уменьшаем LANCZOS.

Что пишется в build:
  assets/icons/app_icon*.png               — исходники flutter_launcher_icons
  assets/icons/tray_icon.ico               — значок трея Windows
  android/.../drawable-*/ic_launcher_*.png — слои адаптивной иконки (108 dp)
  android/.../mipmap-*/ic_launcher*.png    — значок для Android < 8
  android/.../values/colors.xml            — цвет ic_launcher_background (заставка)
  assets/branding/ogneliss-mail-icon.svg   — знак в векторе
  site/mail/*                              — иконки сайта почты
  docs/store/icons/play-icon-512.png                  — значок для Google Play
  ios/Runner/Assets.xcassets/AppIcon...    — значки iOS (без прозрачности)
  docs/store/icons/app-store-icon-1024.png            — значок для App Store Connect
Заставку и «О программе» (знак с лисой) этот скрипт не трогает: assets/brand/.
Иконки в site/ (корень) — это лендинг «Огнелисс»/звонилки, их не трогаем.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SS = 4096  # холст суперсэмплинга

SLATE = (0x46, 0x56, 0x6C, 255)
PAPER = (0xF1, 0xF0, 0xEC, 255)
FLAP = (0x6A, 0x82, 0x93, 255)
HEX = {'slate': '#46566C', 'paper': '#F1F0EC', 'flap': '#6A8293'}

ASPECT = 1.45          # ширина/высота конверта
R_K = 0.04 / 0.62      # радиус углов конверта относительно его ширины
B_K = 0.015 / 0.62     # рамка вокруг клапана относительно ширины конверта
APEX = 0.55            # остриё клапана, доля высоты конверта
TILE_R = 0.225         # радиус скругления плитки, доля её стороны

ENV_FULL = 0.56        # ширина конверта на плитке (с ушами знак выше)
ENV_ADAPTIVE = 0.40    # ширина конверта на холсте 108 dp (безопасная зона 66 dp)

# Уши — доли ширины (w) и высоты (h) конверта.
EAR_H = 0.40           # высота уха над верхним краем, доля h
EAR_IN = 0.03          # отступ внешнего края основания от угла конверта, доля w
EAR_BASE = 0.40        # ширина основания уха, доля w
EAR_TIP = 0.07         # смещение вершины от внешнего края основания, доля w
EAR_R = 0.035          # скругление вершин уха, доля w
EAR_INNER = 0.50       # внутренняя часть уха относительно уха
LEGACY_PAD = 0.08      # поля значка для Android < 8 с каждой стороны
ROUND_PAD = 0.04       # поля круглого значка
ENV_ROUND = 0.58       # ширина конверта относительно диаметра круга


def env_geom(cx, cy, w):
    """Геометрия конверта; знак (конверт + уши) центрирован по вертикали."""
    h = w / ASPECT
    cy += h * EAR_H / 2
    x0, y0 = cx - w / 2, cy - h / 2
    return x0, y0, x0 + w, y0 + h, h, w * R_K, w * B_K


def ear_points(x0, y0, x1, w, h):
    """Треугольники ушей (левое, правое): основание чуть ниже верхнего края."""
    out = []
    base_y = y0 + h * 0.06
    tip_y = y0 - h * EAR_H
    for side in (-1, 1):
        if side < 0:
            a = (x0 + w * EAR_IN, base_y)
            b = (x0 + w * (EAR_IN + EAR_BASE), base_y)
            t = (x0 + w * (EAR_IN + EAR_TIP), tip_y)
            out.append((a, b, t))
        else:
            a = (x1 - w * EAR_IN, base_y)
            b = (x1 - w * (EAR_IN + EAR_BASE), base_y)
            t = (x1 - w * (EAR_IN + EAR_TIP), tip_y)
            out.append((b, a, t))
    return out


def _incenter(p):
    (ax, ay), (bx, by), (cx, cy) = p
    la = ((bx - cx) ** 2 + (by - cy) ** 2) ** 0.5
    lb = ((ax - cx) ** 2 + (ay - cy) ** 2) ** 0.5
    lc = ((ax - bx) ** 2 + (ay - by) ** 2) ** 0.5
    s = la + lb + lc
    ix, iy = (la * ax + lb * bx + lc * cx) / s, (la * ay + lb * by + lc * cy) / s
    area = abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) / 2
    return ix, iy, 2 * area / s


def scale_tri(p, k, dy=0.0):
    ix, iy, _ = _incenter(p)
    return [(ix + (x - ix) * k, iy + (y - iy) * k + dy) for x, y in p]


def rounded_tri(mask, p, r):
    """Треугольник со скруглёнными вершинами радиуса r (маска L)."""
    ix, iy, ir = _incenter(p)
    k = max(0.05, (ir - r) / ir)
    q = [(ix + (x - ix) * k, iy + (y - iy) * k) for x, y in p]
    d = ImageDraw.Draw(mask)
    d.polygon(q, fill=255)
    for i in range(3):
        d.line([q[i], q[(i + 1) % 3]], fill=255, width=max(1, round(2 * r)))
    for x, y in q:
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)


def draw_envelope(img, cx, cy, w, mono=False):
    """Конверт на RGBA-холсте img (координаты в пикселях img)."""
    x0, y0, x1, y1, h, r, b = env_geom(cx, cy, w)
    size = img.size
    body = Image.new('L', size, 0)
    ImageDraw.Draw(body).rounded_rectangle((x0, y0, x1, y1), radius=r, fill=255)
    ears = ear_points(x0, y0, x1, w, h)
    for e in ears:
        rounded_tri(body, e, w * EAR_R)
    apex = (cx, y0 + APEX * h)
    if mono:
        # Белый силуэт, клапан — вырезанная линия.
        m = w * 0.06
        t = w * 0.045
        cut = Image.new('L', size, 0)
        ImageDraw.Draw(cut).line([(x0 + m, y0 + m), apex, (x1 - m, y0 + m)],
                                 fill=255, width=round(t), joint='curve')
        for p in [(x0 + m, y0 + m), (x1 - m, y0 + m)]:
            ImageDraw.Draw(cut).ellipse((p[0] - t / 2, p[1] - t / 2, p[0] + t / 2, p[1] + t / 2), fill=255)
        alpha = ImageChops.subtract(body, cut)
        # Внутренняя часть ушей — вырез, как клапан.
        hole = Image.new('L', size, 0)
        for e in ears:
            rounded_tri(hole, scale_tri(e, EAR_INNER, dy=h * 0.05), w * EAR_R * 0.6)
        alpha = ImageChops.subtract(alpha, hole)
        layer = Image.new('RGBA', size, (255, 255, 255, 255))
        layer.putalpha(alpha)
        img.alpha_composite(layer)
        return img
    layer = Image.new('RGBA', size, PAPER)
    layer.putalpha(body)
    img.alpha_composite(layer)
    tri = Image.new('L', size, 0)
    ImageDraw.Draw(tri).polygon([(x0 + b, y0 + b), (x1 - b, y0 + b), apex], fill=255)
    inner = Image.new('L', size, 0)
    ImageDraw.Draw(inner).rounded_rectangle((x0 + b, y0 + b, x1 - b, y1 - b), radius=r - b, fill=255)
    flap = Image.new('RGBA', size, FLAP)
    flap.putalpha(ImageChops.multiply(tri, inner))
    img.alpha_composite(flap)
    inner_ear = Image.new('L', size, 0)
    for e in ears:
        rounded_tri(inner_ear, scale_tri(e, EAR_INNER, dy=h * 0.05), w * EAR_R * 0.6)
    ie = Image.new('RGBA', size, FLAP)
    ie.putalpha(inner_ear)
    img.alpha_composite(ie)
    return img


def tile(pad=0.0, shape='rounded', square_bg=False, env_k=ENV_FULL):
    """Значок целиком на холсте SS: плитка (скругл. квадрат / круг / квадрат) + конверт."""
    img = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    p = SS * pad
    side = SS - 2 * p
    if square_bg:
        d.rectangle((0, 0, SS, SS), fill=SLATE)
    elif shape == 'circle':
        d.ellipse((p, p, SS - p, SS - p), fill=SLATE)
    else:
        d.rounded_rectangle((p, p, SS - p, SS - p), radius=side * TILE_R, fill=SLATE)
    return draw_envelope(img, SS / 2, SS / 2, side * env_k)


def adaptive_bg():
    return Image.new('RGBA', (SS, SS), SLATE)


def adaptive_fg(mono=False):
    img = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
    return draw_envelope(img, SS / 2, SS / 2, SS * ENV_ADAPTIVE, mono=mono)


def down(img, n):
    return img.resize((n, n), Image.LANCZOS)


def svg_icon():
    s = 1024
    w = s * ENV_FULL
    x0, y0, x1, y1, h, r, b = env_geom(s / 2, s / 2, w)
    f = lambda v: f'{v:.1f}'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}">'
        f'<defs><clipPath id="in"><rect x="{f(x0 + b)}" y="{f(y0 + b)}" width="{f(w - 2 * b)}" '
        f'height="{f(h - 2 * b)}" rx="{f(r - b)}"/></clipPath></defs>'
        f'<rect width="{s}" height="{s}" rx="{f(s * TILE_R)}" fill="{HEX["slate"]}"/>'
        f'<rect x="{f(x0)}" y="{f(y0)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="{HEX["paper"]}"/>'
        f'<path clip-path="url(#in)" fill="{HEX["flap"]}" d="M{f(x0 + b)} {f(y0 + b)}H{f(x1 - b)}'
        f'L{f(s / 2)} {f(y0 + APEX * h)}Z"/>'
        + ''.join(
            f'<path fill="{HEX["paper"]}" stroke="{HEX["paper"]}" stroke-width="{f(2 * w * EAR_R)}" '
            f'stroke-linejoin="round" d="M{" L".join(f"{f(x)} {f(y)}" for x, y in scale_tri(e, 0.9))}Z"/>'
            f'<path fill="{HEX["flap"]}" stroke="{HEX["flap"]}" stroke-width="{f(1.2 * w * EAR_R)}" '
            f'stroke-linejoin="round" d="M{" L".join(f"{f(x)} {f(y)}" for x, y in scale_tri(e, EAR_INNER * 0.9, dy=h * 0.05))}Z"/>'
            for e in ear_points(x0, y0, x1, w, h))
        + '</svg>\n')


DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Значки iOS (имена — как в шаблоне Flutter, Contents.json там же).
IOS_ICONS = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167, 'Icon-App-1024x1024@1x.png': 1024,
}


def masters():
    return {
        'full_sq': tile(square_bg=True),                       # квадрат без прозрачности
        'tile': tile(),                                        # скругл. квадрат, во всю ширину
        'legacy': tile(pad=LEGACY_PAD),                        # Android < 8
        'round': tile(pad=ROUND_PAD, shape='circle', env_k=ENV_ROUND),
        'bg': adaptive_bg(),
        'fg': adaptive_fg(),
        'mono': adaptive_fg(mono=True),
    }


def build(m):
    res = ROOT / 'android/app/src/main/res'
    icons = ROOT / 'assets/icons'
    out = {}

    def save(img, path, rgb=False):
        path = ROOT / path
        (img.convert('RGB') if rgb else img).save(path, optimize=True)
        out[str(path.relative_to(ROOT))] = img

    for d, k in DENS.items():
        a, l = int(108 * k), int(48 * k)
        save(down(m['bg'], a), f'android/app/src/main/res/drawable-{d}/ic_launcher_background.png')
        save(down(m['fg'], a), f'android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png')
        save(down(m['mono'], a), f'android/app/src/main/res/drawable-{d}/ic_launcher_monochrome.png')
        save(down(m['legacy'], l), f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
        if (res / f'mipmap-{d}/ic_launcher_round.png').exists():
            save(down(m['round'], l), f'android/app/src/main/res/mipmap-{d}/ic_launcher_round.png')

    save(down(m['full_sq'], 1024), 'assets/icons/app_icon.png', rgb=True)
    save(down(m['bg'], 1024), 'assets/icons/app_icon_background.png')
    save(down(m['fg'], 1024), 'assets/icons/app_icon_foreground.png')
    save(down(m['mono'], 1024), 'assets/icons/app_icon_monochrome.png')
    # Google Play сам накладывает маску — квадрат без скругления и прозрачности.
    save(down(m['full_sq'], 512), 'docs/store/icons/play-icon-512.png', rgb=True)
    save(down(m['tile'], 256), 'site/mail/app-icon.png')
    # iOS сам скругляет apple-touch-icon; прозрачные углы он залил бы чёрным.
    save(down(m['full_sq'], 180), 'site/mail/apple-touch-icon.png', rgb=True)
    save(down(m['tile'], 32), 'site/mail/favicon-32.png')
    save(down(m['full_sq'], 120), 'site/mail/logo-120.png', rgb=True)
    save(down(m['full_sq'], 1024), 'docs/store/icons/app-store-icon-1024.png', rgb=True)
    # iOS: квадрат без прозрачности, система сама скругляет углы.
    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    if ios.exists():
        for name, px in IOS_ICONS.items():
            save(down(m['full_sq'], px), f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}', rgb=True)

    svg = svg_icon()
    (ROOT / 'site/mail/favicon.svg').write_text(svg)
    (ROOT / 'assets/branding/ogneliss-mail-icon.svg').write_text(svg)
    down(m['tile'], 256).save(icons / 'tray_icon.ico',
                              sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Цвет фона адаптивной иконки — он же фон заставки (launch_background.xml).
    colors = res / 'values/colors.xml'
    txt = colors.read_text()
    txt = re.sub(r'(<color name="ic_launcher_background">)#[0-9A-Fa-f]+(</color>)',
                 rf'\g<1>{HEX["slate"]}\g<2>', txt)
    colors.write_text(txt)
    return out


def preview(m, path):
    """Все размеры рядом + адаптивная иконка под масками + монохром."""
    sizes = [16, 32, 48, 72, 96, 120, 144, 180, 192, 256, 512]
    rows = []
    for key in ('legacy', 'round', 'tile', 'full_sq'):
        rows.append([down(m[key], s) for s in sizes])
    comp = m['bg'].copy()
    comp.alpha_composite(m['fg'])
    masks = []
    for shape in ('circle', 'squircle', 'square'):
        mk = Image.new('L', (SS, SS), 0)
        dd = ImageDraw.Draw(mk)
        inset = SS * 18 / 108  # видимая область 72 dp из 108
        box = (inset, inset, SS - inset, SS - inset)
        if shape == 'circle':
            dd.ellipse(box, fill=255)
        elif shape == 'squircle':
            dd.rounded_rectangle(box, radius=(SS - 2 * inset) * 0.3, fill=255)
        else:
            dd.rounded_rectangle(box, radius=(SS - 2 * inset) * 0.08, fill=255)
        c = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
        c.paste(comp, (0, 0), mk)
        masks.append(down(c, 432))
    mono = Image.new('RGBA', (SS, SS), (0x2A, 0x33, 0x40, 255))
    mono.alpha_composite(m['mono'])
    mk = Image.new('L', (SS, SS), 0)
    inset = SS * 18 / 108
    ImageDraw.Draw(mk).ellipse((inset, inset, SS - inset, SS - inset), fill=255)
    mc = Image.new('RGBA', (SS, SS), (0, 0, 0, 0))
    mc.paste(mono, (0, 0), mk)
    masks.append(down(mc, 432))
    fgraw = Image.new('RGBA', (SS, SS), (230, 230, 230, 255))
    fgraw.alpha_composite(m['fg'])
    d = ImageDraw.Draw(fgraw)
    s0 = SS * 21 / 108
    d.ellipse((s0, s0, SS - s0, SS - s0), outline=(255, 0, 0, 255), width=12)  # безопасная зона 66 dp
    masks.append(down(fgraw, 432))

    gap = 16
    W = max(sum(s for s in sizes) + gap * (len(sizes) + 1), 5 * 432 + 6 * gap)
    H = gap + sum(512 + gap for _ in rows) + 432 + gap
    sheet = Image.new('RGBA', (W, H), (250, 250, 250, 255))
    y = gap
    for i, row in enumerate(rows):
        x = gap
        if i % 2:
            ImageDraw.Draw(sheet).rectangle((0, y - gap // 2, W, y + 512 + gap // 2), fill=(40, 44, 52, 255))
        for im in row:
            sheet.alpha_composite(im, (x, y + 512 - im.size[1]))
            x += im.size[0] + gap
        y += 512 + gap
    x = gap
    for im in masks:
        sheet.alpha_composite(im, (x, y))
        x += 432 + gap
    sheet.convert('RGB').save(path)


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    m = masters()
    if cmd == 'build':
        for p in build(m):
            print('записан', p)
    prev = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / 'tool/branding/preview_v4.png')
    preview(m, prev)
    print('предпросмотр:', prev)
