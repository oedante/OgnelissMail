#!/usr/bin/env python3
"""Баннер для магазинов: иконка Ogneliss Mail, название и подзаголовок.

    python3 tool/branding/make_banner.py

Размеры:
  1024×500 — «Графика для описания» (Feature graphic) Google Play;
  1386×500 — широкий баннер (по запросу), та же композиция.
Языки: ru и en. Результат — docs/store/graphics/.

Google Play может обрезать края и накладывать кнопку воспроизведения в
центре, поэтому важное держится в средней полосе и не ближе 60 px к краям.
"""
import io
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import make_icon as mi

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/store/graphics'
FONT_B = ROOT / 'assets/fonts/pdf/Roboto-Bold.ttf'
FONT_R = ROOT / 'assets/fonts/pdf/Roboto-Regular.ttf'

TEXT = {
    'ru': ('Ogneliss Mail', 'Почта, календарь и контакты', 'Exchange · Gmail · Яндекс · Mail.ru'),
    'en': ('Ogneliss Mail', 'Mail, calendar and contacts', 'Exchange · Gmail · Yandex · Mail.ru'),
}


def background(w, h):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}">'
           '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
           '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#DCE7F5"/>'
           '</linearGradient></defs>'
           f'<rect width="{w}" height="{h}" fill="url(#g)"/>'
           # Мягкая дуга бренда справа внизу
           f'<circle cx="{w + 40}" cy="{h + 120}" r="{h * 0.95:.0f}" fill="{mi.BLUE}" fill-opacity="0.07"/>'
           f'<circle cx="{w + 40}" cy="{h + 120}" r="{h * 0.70:.0f}" fill="{mi.AMBER}" fill-opacity="0.07"/>'
           '</svg>')
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA')


def icon(size):
    full = mi.png(mi.svg(mi.variant_d(), 'light', mi.FULL_SCALE), 1024)
    im = mi.masked(full, 'squircle').resize((size, size), Image.LANCZOS)
    # Тень под иконкой
    pad = 60  # запас под размытие: иначе у тени виден край холста
    sh = Image.new('RGBA', (size + 2 * pad, size + 2 * pad), (15, 39, 66, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + 12, pad + size, pad + size + 12),
                                         radius=int(size * 0.23), fill=(15, 39, 66, 46))
    sh = sh.filter(ImageFilter.GaussianBlur(16))
    sh.alpha_composite(im, (pad, pad))
    return sh


def banner(w, h, lang):
    im = background(w, h)
    d = ImageDraw.Draw(im)
    isz = 250
    ic = icon(isz)
    x = 70 if w <= 1100 else 140
    im.alpha_composite(ic, (x - 60, (h - isz) // 2 - 60))
    tx = x + isz + 56
    title, sub, svc = TEXT[lang]
    ft = ImageFont.truetype(str(FONT_B), 78)
    fs = ImageFont.truetype(str(FONT_R), 38)
    fv = ImageFont.truetype(str(FONT_R), 28)
    # Подзаголовок не должен выйти за край: уменьшаем шрифт при нужде.
    while d.textlength(sub, font=fs) > w - tx - 50 and fs.size > 26:
        fs = ImageFont.truetype(str(FONT_R), fs.size - 2)
    while d.textlength(svc, font=fv) > w - tx - 50 and fv.size > 20:
        fv = ImageFont.truetype(str(FONT_R), fv.size - 2)
    y = h // 2 - 92
    d.text((tx, y), title, font=ft, fill=mi.NAVY)
    d.text((tx, y + 100), sub, font=fs, fill=mi.BLUE)
    d.rounded_rectangle((tx, y + 160, tx + 64, y + 166), radius=3, fill=mi.AMBER)
    d.text((tx, y + 182), svc, font=fv, fill='#4A5A70')
    return im.convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for lang in TEXT:
        for w, h in ((1024, 500), (1386, 500)):
            p = OUT / f'feature_{w}x{h}_{lang}.png'
            banner(w, h, lang).save(p, optimize=True)
            print(p)


if __name__ == '__main__':
    main()
