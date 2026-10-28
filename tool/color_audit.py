#!/usr/bin/env python3
"""Аудит цветов Ogneliss Mail (docs/plan/COLOR_AUDIT.md).

    python3 tool/color_audit.py

1. Контраст пар «что рядом с чем» во всех темах (WCAG): текст ≥ 4.5:1,
   значки и рамки ≥ 3:1 (желательно), подложки/карточки к фону — заметно
   отличимы (≥ 1.08:1 или есть граница).
2. Яркие цвета в коде: HSV насыщенность > 0.6 и яркость > 0.75 — кандидаты
   на приглушение (фирменные цвета провайдеров на экране входа — исключение).
3. Цвета Material «из коробки» (Colors.red, Colors.green…) в интерфейсе.

Пары и значения обновлять вместе с lib/core/theme/app_theme.dart.
"""
import colorsys
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))


def lum(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


# (передний план, фон, что это, минимум)
PAIRS = [
    # ── Светлая ──
    ('#1A1F26', '#F6F8FB', 'светлая: текст на фоне', 4.5),
    ('#4D5664', '#FFFFFF', 'светлая: вторичный текст на карточке', 4.5),
    ('#FFFFFF', '#F6F8FB', 'светлая: карточка/группа к фону (+ граница #D5DBE3)', 1.05),
    ('#D5DBE3', '#FFFFFF', 'светлая: граница карточки', 1.3),
    ('#A9B3C1', '#F6F8FB', 'светлая: рамка фото к фону', 1.9),
    ('#A9B3C1', '#FFFFFF', 'светлая: рамка фото к белому', 1.9),
    ('#E9EDF2', '#F6F8FB', 'светлая: поле ввода к фону', 1.1),
    ('#E8ECF1', '#F6F8FB', 'светлая: нижняя панель к фону', 1.1),
    ('#DCE6F3', '#FFFFFF', 'светлая: выбранная строка к белому', 1.2),
    # ── Тёмная ──
    ('#E3E7ED', '#12161B', 'тёмная: текст на фоне', 4.5),
    ('#AEB7C4', '#1D232B', 'тёмная: вторичный текст на карточке', 4.5),
    ('#1D232B', '#12161B', 'тёмная: карточка к фону (+ граница #353E4A)', 1.1),
    ('#5A6575', '#12161B', 'тёмная: рамка фото к фону', 2.5),
    ('#232A33', '#12161B', 'тёмная: поле ввода к фону', 1.2),
    ('#2A3A50', '#12161B', 'тёмная: выбранная строка к фону', 1.3),
    # ── AMOLED ──
    ('#5A6575', '#000000', 'AMOLED: рамка фото', 2.5),
    ('#2E333A', '#000000', 'AMOLED: граница карточки', 1.4),
    ('#2A2A2A', '#000000', 'AMOLED: разделитель', 1.4),
    # ── Чтение ──
    ('#2B2620', '#F4EFE6', 'чтение: текст на фоне', 4.5),
    ('#5E564A', '#FBF8F2', 'чтение: вторичный текст на карточке', 4.5),
    ('#FFFFFF', '#3F5D84', 'чтение: текст на кнопке', 4.5),
    ('#A79D8C', '#F4EFE6', 'чтение: рамка фото к фону', 2.0),
    ('#D3C9B8', '#FBF8F2', 'чтение: граница карточки', 1.3),
]

AVATARS = ['#B0504B', '#467E59', '#456EA3', '#9E6B2A', '#7E5A9E', '#357F7A',
           '#A3536F', '#5F7A33', '#555FA0', '#8A7424', '#37789A', '#7D6456']

VIVID_SKIP = ('login_screen.dart',)  # фирменные цвета Google, Яндекса, Mail.ru, Microsoft


def main():
    bad = 0
    print('== Контраст пар ==')
    for fg, bg, what, need in PAIRS:
        r = ratio(fg, bg)
        ok = r >= need
        bad += 0 if ok else 1
        print(f'{"✓" if ok else "✗"} {r:5.2f}  (≥{need})  {what}  {fg} / {bg}')
    print('\n== Кружки с буквой: белая буква и фон тёмной темы ==')
    for c in AVATARS:
        w, d = ratio('#FFFFFF', c), ratio(c, '#12161B')
        ok = w >= 4.5 and d >= 3.0
        bad += 0 if ok else 1
        print(f'{"✓" if ok else "✗"} {c}: буква {w:4.2f}, к тёмному фону {d:4.2f}')

    print('\n== Яркие цвета в коде (s > 0.6, v > 0.75) ==')
    rx = re.compile(r'Color\(0x([0-9A-Fa-f]{8})\)')
    for dp, _, fs in os.walk(os.path.join(ROOT, 'lib')):
        for f in fs:
            if not f.endswith('.dart') or f in VIVID_SKIP:
                continue
            p = os.path.join(dp, f)
            for n, line in enumerate(open(p, encoding='utf-8'), 1):
                for m in rx.finditer(line):
                    v = int(m.group(1), 16)
                    r, g, b = ((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255
                    _, s, val = colorsys.rgb_to_hsv(r, g, b)
                    if s > 0.6 and val > 0.75:
                        print(f'  {os.path.relpath(p, ROOT)}:{n}  #{m.group(1)[2:]}  s={s:.2f} v={val:.2f}')

    print('\n== Colors.<цвет> Material ==')
    mrx = re.compile(r'Colors\.(red|green|blue|orange|amber|yellow|purple|pink|teal|cyan|lime|indigo|'
                     r'deepOrange|deepPurple|lightBlue|lightGreen|brown)\b')
    for dp, _, fs in os.walk(os.path.join(ROOT, 'lib')):
        for f in fs:
            if f.endswith('.dart'):
                p = os.path.join(dp, f)
                for n, line in enumerate(open(p, encoding='utf-8'), 1):
                    if mrx.search(line) and not line.strip().startswith('//'):
                        print(f'  {os.path.relpath(p, ROOT)}:{n}  {line.strip()[:80]}')
    print(f'\nнарушений контраста: {bad}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
