#!/usr/bin/env python3
"""Иконка Ogneliss Mail, редакция 2 (октябрь 2026): строгая корпоративная.

Пламя убрано. Знак — геометрический конверт; лиса осталась намёком в
варианте A (уши над клапаном конверта), в B — только конверт с янтарной
«искрой», в C — знак-монограмма «O».

    python3 tool/branding/make_icon_v2.py preview        — варианты рядом (preview.png)
    python3 tool/branding/make_icon_v2.py build [A|B|C]  — ресурсы выбранного варианта

Рендер — headless Chromium через Playwright (в отличие от make_icon.py не
нужен cairosvg). Холст 1024×1024, знак вписан в безопасную зону адаптивной
иконки Android (круг диаметром 66/108 ≈ 61 % стороны), поэтому маски
производителей (круг, сквиркл, капля) ничего не срезают.

Что пишется в build:
  assets/icons/app_icon*.png              — исходники flutter_launcher_icons
  android/.../drawable-*/ic_launcher_*.png — слои адаптивной иконки
  android/.../mipmap-*/ic_launcher*.png   — значок для Android < 8
  assets/branding/ogneliss-mail-icon.svg  — знак в векторе
  site/mail/app-icon.png, favicon.svg, favicon-32.png — сайт
  docs/store/icons/play-icon-512.png                 — значок для Google Play
"""
import asyncio
import base64
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]

# Цвета приложения (AppColors): тёмно-синий, синий, янтарный.
NAVY = '#0B2545'
BLUE = '#1D5BB8'
BLUE_HI = '#2F74D8'
AMBER = '#F2A33A'
PAPER = '#FFFFFF'
INK = '#123A6E'

C = 512  # центр холста


def background():
    """Фон адаптивной иконки: диагональный градиент синий → тёмно-синий."""
    return (
        '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{BLUE_HI}"/>'
        f'<stop offset="0.55" stop-color="{BLUE}"/>'
        f'<stop offset="1" stop-color="{NAVY}"/></linearGradient></defs>'
        '<rect width="1024" height="1024" fill="url(#bg)"/>'
    )


# ── Знаки (передний план). mono=True — одноцветный силуэт для тематических
#    значков Android 13+ (форма та же, детали вырезаны прозрачностью).

# Масштаб знаков: в видимой части лаунчера (72 из 108 dp) знак занимает
# ~2/3 ширины — как у значков Google (ключевые линии Material).
A_SCALE, B_SCALE, C_SCALE = 0.70, 0.68, 0.66


def _fit(inner, scale):
    """Масштаб знака вокруг центра холста."""
    return (f'<g transform="translate({C} {C}) scale({scale}) translate({-C} {-C})">'
            f'{inner}</g>')


def mark_a(mono=False):
    """Конверт-лиса: единый силуэт — конверт с ушками, клапан — мордочка,
    янтарный нос в вершине клапана."""
    w, h = 560, 380
    x0, y0 = C - w / 2, C - h / 2 + 46
    x1 = x0 + w
    r = 52
    paper = '#fff'
    # Уши — скруглённые треугольники, продолжающие верхние углы конверта.
    ear_l = f'M{x0 + 6} {y0 + 60} L{x0 + 44} {y0 - 96} L{x0 + 196} {y0 + 2} Z'
    ear_r = f'M{x1 - 6} {y0 + 60} L{x1 - 44} {y0 - 96} L{x1 - 196} {y0 + 2} Z'
    ears = ''.join(f'<path d="{d}" fill="{paper}" stroke="{paper}" stroke-width="44" '
                   'stroke-linejoin="round"/>' for d in (ear_l, ear_r))
    body = f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="{r}" fill="{paper}"/>'
    flap_d = f'M{x0 + 56} {y0 + 62} L{C} {y0 + 236} L{x1 - 56} {y0 + 62}'
    nose_r = 34
    if mono:
        inner = (
            '<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
            f'<path d="{flap_d}" fill="none" stroke="#000" stroke-width="42" '
            'stroke-linecap="round" stroke-linejoin="round"/></mask></defs>'
            f'<g mask="url(#m)">{ears}{body}</g>'
            f'<circle cx="{C}" cy="{y0 + 240}" r="{nose_r}" fill="#fff"/>'
        )
        return _fit(inner, A_SCALE)
    inner_ears = ''.join(
        f'<path d="{d}" fill="{AMBER}"/>' for d in (
            f'M{x0 + 52} {y0 + 30} L{x0 + 66} {y0 - 50} L{x0 + 150} {y0 + 4} Z',
            f'M{x1 - 52} {y0 + 30} L{x1 - 66} {y0 - 50} L{x1 - 150} {y0 + 4} Z'))
    flap = (f'<path d="{flap_d}" fill="none" stroke="{INK}" stroke-width="42" '
            'stroke-linecap="round" stroke-linejoin="round"/>')
    nose = f'<circle cx="{C}" cy="{y0 + 240}" r="{nose_r}" fill="{AMBER}"/>'
    return _fit(ears + body + inner_ears + flap + nose, A_SCALE)


def mark_b(mono=False):
    """Строгий конверт с янтарной точкой уведомления."""
    w, h = 560, 390
    x0, y0 = C - w / 2, C - h / 2 + 20
    x1 = x0 + w
    r = 52
    flap_d = f'M{x0 + 56} {y0 + 62} L{C} {y0 + 240} L{x1 - 56} {y0 + 62}'
    body = f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="{r}" fill="#fff"/>'
    sx, sy = x1 - 40, y0 + 30
    if mono:
        inner = (
            '<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
            f'<path d="{flap_d}" fill="none" stroke="#000" stroke-width="42" '
            'stroke-linecap="round" stroke-linejoin="round"/>'
            f'<circle cx="{sx}" cy="{sy}" r="92" fill="#000"/></mask></defs>'
            f'<g mask="url(#m)">{body}</g>'
            f'<circle cx="{sx}" cy="{sy}" r="64" fill="#fff"/>'
        )
        return _fit(inner, B_SCALE)
    flap = (f'<path d="{flap_d}" fill="none" stroke="{INK}" stroke-width="42" '
            'stroke-linecap="round" stroke-linejoin="round"/>')
    spark = (f'<circle cx="{sx}" cy="{sy}" r="92" fill="{BLUE}"/>'
             f'<circle cx="{sx}" cy="{sy}" r="64" fill="{AMBER}"/>')
    return _fit(body + flap + spark, B_SCALE)


def mark_c(mono=False):
    """Геометрическая голова лисы без пламени."""
    head = ('M512 812 L292 572 L262 312 L322 182 L432 318 L592 318 L702 182 '
            'L762 312 L732 572 Z')
    muzzle = 'M352 520 L512 600 L672 520 L512 812 Z'
    if mono:
        inner = (
            '<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
            f'<path d="{muzzle}" fill="#000" stroke="#000" stroke-width="24" stroke-linejoin="round"/>'
            '<circle cx="430" cy="470" r="26" fill="#000"/><circle cx="594" cy="470" r="26" fill="#000"/>'
            '</mask></defs>'
            f'<path d="{head}" fill="#fff" stroke="#fff" stroke-width="36" stroke-linejoin="round" mask="url(#m)"/>'
        )
        return _fit(inner, C_SCALE)
    inner = (f'<path d="{head}" fill="{AMBER}" stroke="{AMBER}" stroke-width="36" stroke-linejoin="round"/>'
             f'<path d="{muzzle}" fill="#fff" stroke="#fff" stroke-width="24" stroke-linejoin="round"/>'
             f'<circle cx="430" cy="470" r="26" fill="{NAVY}"/><circle cx="594" cy="470" r="26" fill="{NAVY}"/>'
             f'<circle cx="512" cy="790" r="30" fill="{NAVY}"/>')
    return _fit(inner, C_SCALE)


MARKS = {'A': mark_a, 'B': mark_b, 'C': mark_c}


def _envelope(mono, flap_color=None, scale=0.68, dy=20):
    """Конверт варианта B: тело и клапан. Возвращает (body, flap_d, геометрию)."""
    w, h = 560, 390
    x0, y0 = C - w / 2, C - h / 2 + dy
    x1 = x0 + w
    body = f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="52" fill="#fff"/>'
    flap_d = f'M{x0 + 56} {y0 + 62} L{C} {y0 + 240} L{x1 - 56} {y0 + 62}'
    return body, flap_d, (x0, y0, x1)


def _fox_head(cx, cy, r, fill, stroke=None):
    """Маленькая геометрическая голова лисы (уши, скулы, подбородок) радиуса r."""
    k = r / 100
    pts = [(0, 100), (-78, 18), (-88, -62), (-62, -100), (-28, -48), (28, -48),
           (62, -100), (88, -62), (78, 18)]
    d = 'M' + ' L'.join(f'{cx + x * k:.1f} {cy + y * k:.1f}' for x, y in pts) + ' Z'
    sw = f' stroke="{stroke}" stroke-width="{34 * k:.1f}" paint-order="stroke"' if stroke else ''
    return f'<path d="{d}" fill="{fill}"{sw} stroke-linejoin="round"/>'


def mark_d(mono=False):
    """Строгий конверт B, вместо точки — янтарная голова лисы-значок."""
    body, flap_d, (x0, y0, x1) = _envelope(mono)
    cx, cy, r = x1 - 40, y0 + 10, 135
    if mono:
        inner = (
            '<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
            f'<path d="{flap_d}" fill="none" stroke="#000" stroke-width="42" '
            'stroke-linecap="round" stroke-linejoin="round"/>'
            f'{_fox_head(cx, cy, r * 1.25, "#000")}</mask></defs>'
            f'<g mask="url(#m)">{body}</g>{_fox_head(cx, cy, r, "#fff")}'
        )
        return _fit(inner, 0.66)
    flap = (f'<path d="{flap_d}" fill="none" stroke="{INK}" stroke-width="42" '
            'stroke-linecap="round" stroke-linejoin="round"/>')
    badge = _fox_head(cx, cy, r, AMBER, stroke=BLUE)
    muzzle = (f'<path d="M{cx - 0.5 * r:.1f} {cy + 0.05 * r:.1f} L{cx:.1f} {cy + 0.35 * r:.1f} '
              f'L{cx + 0.5 * r:.1f} {cy + 0.05 * r:.1f} L{cx:.1f} {cy + r:.1f} Z" fill="#fff"/>')
    return _fit(body + flap + badge + muzzle, 0.66)


def mark_e(mono=False):
    """Конверт B с янтарным клапаном-«галочкой» и острыми ушками-уголками."""
    body, flap_d, (x0, y0, x1) = _envelope(mono)
    ear = lambda sx: (f'M{sx(x0 + 6)} {y0 + 70} L{sx(x0 + 30)} {y0 - 70} L{sx(x0 + 170)} {y0 + 4} Z')
    ears = ''.join(f'<path d="{ear(f)}" fill="#fff" stroke="#fff" stroke-width="40" stroke-linejoin="round"/>'
                   for f in (lambda v: v, lambda v: 2 * C - v))
    if mono:
        inner = ('<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
                 f'<path d="{flap_d}" fill="none" stroke="#000" stroke-width="46" '
                 'stroke-linecap="round" stroke-linejoin="round"/></mask></defs>'
                 f'<g mask="url(#m)">{ears}{body}</g>')
        return _fit(inner, 0.70)
    flap = (f'<path d="{flap_d}" fill="none" stroke="{AMBER}" stroke-width="46" '
            'stroke-linecap="round" stroke-linejoin="round"/>')
    return _fit(ears + body + flap, 0.70)


def mark_f(mono=False):
    """Конверт B: клапан — силуэт мордочки лисы (янтарный треугольник с носом)."""
    body, flap_d, (x0, y0, x1) = _envelope(mono)
    face = f'M{x0 + 40} {y0 + 52} L{C} {y0 + 250} L{x1 - 40} {y0 + 52} Z'
    if mono:
        inner = ('<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
                 f'<path d="{face}" fill="#000"/></mask></defs>'
                 f'<g mask="url(#m)">{body}</g>'
                 f'<circle cx="{C}" cy="{y0 + 222}" r="26" fill="#fff"/>')
        return _fit(inner, 0.68)
    inner = (body + f'<path d="{face}" fill="{AMBER}" stroke="{AMBER}" stroke-width="20" stroke-linejoin="round"/>'
             f'<path d="M{x0 + 120} {y0 + 52} L{C} {y0 + 170} L{x1 - 120} {y0 + 52} Z" fill="#fff"/>'
             f'<circle cx="{C}" cy="{y0 + 222}" r="26" fill="{NAVY}"/>')
    return _fit(inner, 0.68)


MARKS.update({'D': mark_d, 'E': mark_e, 'F': mark_f})


# ── Вариант G (07.10.2026, выбран): прежняя иконка — синий конверт с печатью
#    «огненный лис», крупнее и без жёстких линий: объём градиентами. ──
import re as _re
_MARK = (ROOT / 'assets/branding/ogneliss-mark.svg').read_text()
_FLAME_D = _re.findall(r' d="([^"]*)"', _MARK)[0].replace('&#xA;', ' ')
_FX0, _FY0, _FX1, _FY1 = 808, 192, 4208, 4768  # габарит пламени в единицах знака


def _flame(cx, top, height, fill):
    k = height / (_FY1 - _FY0)
    tx = cx - (_FX0 + _FX1) / 2 * k
    ty = top - _FY0 * k
    return (f'<g transform="translate({tx:.2f} {ty:.2f}) scale({k:.6f})">'
            f'<path d="{_FLAME_D}" fill="{fill}" fill-rule="evenodd"/></g>')


def background_light():
    return ('<defs><linearGradient id="bgl" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E2EBF7"/>'
            '</linearGradient></defs><rect width="1024" height="1024" fill="url(#bgl)"/>')


G_SCALE = 0.82


def mark_g(mono=False):
    w, h = 620, 430
    x0, y0 = C - w / 2, C - h / 2 + 10
    x1, y1 = x0 + w, y0 + h
    tip = y0 + 252
    r = 128
    if mono:
        inner = (
            '<defs><mask id="m"><rect width="1024" height="1024" fill="#fff"/>'
            f'<path d="M{x0 + 40} {y0 + 38} L{C} {tip} L{x1 - 40} {y0 + 38}" fill="none" stroke="#000" '
            'stroke-width="30" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<circle cx="{C}" cy="{tip}" r="{r + 22}" fill="#000"/></mask>'
            '<mask id="f"><rect width="1024" height="1024" fill="#fff"/>'
            f'{_flame(C, tip - r * 0.70, r * 1.40, "#000")}</mask></defs>'
            f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="54" fill="#fff" mask="url(#m)"/>'
            f'<circle cx="{C}" cy="{tip}" r="{r}" fill="#fff" mask="url(#f)"/>'
        )
        return _fit(inner, G_SCALE)
    defs = (
        '<defs>'
        # Тело: светлее сверху, глубже снизу.
        '<linearGradient id="gBody" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#2F6FC8"/><stop offset="1" stop-color="#143F7C"/></linearGradient>'
        # Клапан: от синего к тёмно-синему у вершины.
        '<linearGradient id="gFlap" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#1E4F92"/><stop offset="1" stop-color="#0E2F61"/></linearGradient>'
        # Кромка клапана — свет, тающий к вершине (вместо белой линии).
        '<linearGradient id="gEdge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.15"/></linearGradient>'
        # Нижние складки — мягкие блики вместо полос.
        '<linearGradient id="gFold" x1="0" y1="1" x2="0" y2="0">'
        '<stop offset="0" stop-color="#5B97E6" stop-opacity="0.55"/>'
        '<stop offset="1" stop-color="#5B97E6" stop-opacity="0"/></linearGradient>'
        '<radialGradient id="gSeal" cx="0.4" cy="0.35" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF3FA"/></radialGradient>'
        '<linearGradient id="gRing" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#FFC75A"/><stop offset="1" stop-color="#D9801C"/></linearGradient>'
        '<linearGradient id="gFlame" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFC24B"/><stop offset="1" stop-color="#E37B17"/></linearGradient>'
        '<filter id="sh" x="-20%" y="-20%" width="140%" height="160%">'
        '<feGaussianBlur stdDeviation="14"/></filter>'
        '<filter id="sh2" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur stdDeviation="8"/></filter>'
        f'<clipPath id="env"><rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="54"/></clipPath>'
        '</defs>'
    )
    body = (
        # Мягкая тень конверта
        f'<rect x="{x0 + 10}" y="{y0 + 26}" width="{w - 20}" height="{h}" rx="54" fill="#0F2742" '
        'fill-opacity="0.28" filter="url(#sh)"/>'
        f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="54" fill="url(#gBody)"/>'
        f'<g clip-path="url(#env)">'
        # Складки снизу
        f'<path d="M{x0} {y1} L{C} {tip - 10} L{x1} {y1} Z" fill="url(#gFold)"/>'
        # Клапан и его кромка
        f'<path d="M{x0 - 4} {y0 - 4} L{C} {tip} L{x1 + 4} {y0 - 4} Z" fill="url(#gFlap)"/>'
        f'<path d="M{x0 + 36} {y0 + 34} L{C} {tip} L{x1 - 36} {y0 + 34}" fill="none" '
        'stroke="url(#gEdge)" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>'
        '</g>'
    )
    seal = (
        f'<circle cx="{C}" cy="{tip + 10}" r="{r + 8}" fill="#0F2742" fill-opacity="0.30" filter="url(#sh2)"/>'
        f'<circle cx="{C}" cy="{tip}" r="{r}" fill="url(#gRing)"/>'
        f'<circle cx="{C}" cy="{tip}" r="{r - 13}" fill="url(#gSeal)"/>'
        + _flame(C, tip - r * 0.70, r * 1.40, 'url(#gFlame)')
    )
    return _fit(defs + body + seal, G_SCALE)


MARKS['G'] = mark_g
BACKGROUNDS = {'G': background_light}


def svg(inner, size=1024):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 1024 1024">{inner}</svg>')


def full_icon(v, rounded=False):
    """Готовый значок: фон + знак. rounded — со скруглением (сайт, Play)."""
    # Видимая часть адаптивной иконки — 72 из 108 dp: знак крупнее в 1.5 раза,
    # чтобы значок в Google Play и на сайте выглядел как в лаунчере.
    inner = BACKGROUNDS.get(v, background)() + _fit(MARKS[v](), 1.5)
    if rounded:
        inner = ('<defs><clipPath id="sq"><rect width="1024" height="1024" rx="230"/></clipPath></defs>'
                 f'<g clip-path="url(#sq)">{inner}</g>')
    return svg(inner)


async def render_all(jobs):
    """jobs: [(svg_text, size)] → [PIL.Image]. Прозрачный фон сохраняется."""
    from playwright.async_api import async_playwright
    out = []
    async with async_playwright() as p:
        b = await p.chromium.launch()
        page = await b.new_page(viewport={'width': 1024, 'height': 1024})
        for text, size in jobs:
            await page.set_viewport_size({'width': size, 'height': size})
            data = base64.b64encode(text.encode()).decode()
            await page.set_content(
                '<html><body style="margin:0;background:transparent">'
                f'<img src="data:image/svg+xml;base64,{data}" '
                f'style="width:{size}px;height:{size}px;display:block"></body></html>')
            await page.wait_for_timeout(50)
            png = await page.screenshot(omit_background=True,
                                        clip={'x': 0, 'y': 0, 'width': size, 'height': size})
            out.append(Image.open(io.BytesIO(png)).convert('RGBA'))
        await b.close()
    return out


def render(jobs):
    return asyncio.run(render_all(jobs))


def preview(which=None):
    which = which or list(MARKS)
    jobs = []
    for v in which:
        jobs.append((full_icon(v, rounded=True), 256))
        # Как в лаунчере с круглой маской
        jobs.append((svg(BACKGROUNDS.get(v, background)() + MARKS[v]()), 256))
        jobs.append((svg(MARKS[v](mono=True)), 256))
    imgs = render(jobs)
    sheet = Image.new('RGBA', (3 * 276 + 20, len(which) * 276 + 20), (238, 241, 246, 255))
    for i, im in enumerate(imgs):
        row, col = divmod(i, 3)
        if col == 1:  # как в лаунчере: видимая часть 72 из 108 dp, круглая маска
            k = 256 * 18 / 108
            im = im.crop((k, k, 256 - k, 256 - k)).resize((256, 256), Image.LANCZOS)
            m = Image.new('L', im.size, 0)
            from PIL import ImageDraw
            ImageDraw.Draw(m).ellipse((0, 0, 255, 255), fill=255)
            im.putalpha(m)
        if col == 2:  # монохром на тёмной теме
            bgk = Image.new('RGBA', im.size, (40, 44, 52, 255))
            bgk.alpha_composite(im)
            im = bgk
        sheet.alpha_composite(im, (20 + col * 276, 20 + row * 276))
    out = ROOT / 'tool/branding/preview_v2.png'
    sheet.save(out)
    print(out)


DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def build(v):
    res = ROOT / 'android/app/src/main/res'
    bg_svg = svg(BACKGROUNDS.get(v, background)())
    fg_svg = svg(MARKS[v]())
    mono_svg = svg(MARKS[v](mono=True))
    full_svg = full_icon(v)
    round_svg = full_icon(v, rounded=True)

    jobs = [(bg_svg, 1024), (fg_svg, 1024), (mono_svg, 1024), (full_svg, 1024), (round_svg, 1024)]
    for d, k in DENS.items():
        s = int(108 * k)  # слои адаптивной иконки — 108 dp
        jobs += [(bg_svg, s), (fg_svg, s), (mono_svg, s)]
        s = int(48 * k)  # обычный значок — 48 dp
        jobs += [(full_svg, s)]
    jobs += [(full_svg, 512), (round_svg, 256), (round_svg, 180), (round_svg, 32)]
    imgs = iter(render(jobs))

    bg, fg, mono, full, rnd = [next(imgs) for _ in range(5)]
    icons = ROOT / 'assets/icons'
    bg.save(icons / 'app_icon_background.png')
    fg.save(icons / 'app_icon_foreground.png')
    mono.save(icons / 'app_icon_monochrome.png')
    full.convert('RGB').save(icons / 'app_icon.png')

    for d in DENS:
        b, f, m, ic = [next(imgs) for _ in range(4)]
        b.save(res / f'drawable-{d}/ic_launcher_background.png')
        f.save(res / f'drawable-{d}/ic_launcher_foreground.png')
        m.save(res / f'drawable-{d}/ic_launcher_monochrome.png')
        ic.save(res / f'mipmap-{d}/ic_launcher.png')
        # Круглый значок для старых лаунчеров
        from PIL import ImageDraw
        mask = Image.new('L', ic.size, 0)
        ImageDraw.Draw(mask).ellipse((0, 0, ic.size[0] - 1, ic.size[1] - 1), fill=255)
        r = ic.copy()
        r.putalpha(mask)
        if (res / f'mipmap-{d}/ic_launcher_round.png').exists() or True:
            r.save(res / f'mipmap-{d}/ic_launcher_round.png')

    p512, p256, p180, p32 = [next(imgs) for _ in range(4)]
    store = ROOT / 'docs/store/icons'
    store.mkdir(parents=True, exist_ok=True)
    # Google Play сам накладывает маску — квадрат без скругления и прозрачности.
    p512.convert('RGB').save(store / 'play-icon-512.png')
    site = ROOT / 'site/mail'
    p256.save(site / 'app-icon.png')
    p180.save(site / 'apple-touch-icon.png')
    p32.save(site / 'favicon-32.png')
    (site / 'favicon.svg').write_text(round_svg.replace('width="1024" height="1024" ', ''))
    (ROOT / 'assets/branding/ogneliss-mail-icon.svg').write_text(
        round_svg.replace('width="1024" height="1024" ', ''))
    # Значок трея Windows
    full.resize((256, 256), Image.LANCZOS).save(
        icons / 'tray_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)])
    print(f'Вариант {v}: ресурсы записаны')


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    if cmd == 'preview':
        preview([c.upper() for c in sys.argv[2]] if len(sys.argv) > 2 else None)
    elif cmd == 'build':
        build((sys.argv[2] if len(sys.argv) > 2 else 'B').upper())
    else:
        print(__doc__)
