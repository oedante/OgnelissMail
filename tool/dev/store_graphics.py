#!/usr/bin/env python3
"""Графика магазинов: баннер Google Play и скриншоты с подписями.

25.10.2026 (сменил tool/dev/store_banners.py от 11.10.2026).

Запуск из корня проекта (нужны Playwright с Chromium и Pillow):
    python3 tool/dev/store_graphics.py              # всё
    python3 tool/dev/store_graphics.py banners      # только баннеры
    python3 tool/dev/store_graphics.py screens      # только скриншоты
    python3 tool/dev/store_graphics.py creative     # App Store: заголовок и поиск

Результат — docs/store/graphics/:
    feature_1024x500_{ru,en}.png   — баннер Google Play («Графический элемент»)
                                     в стиле заголовка App Store (1.7.3),
    feature_1386x500_{ru,en}.png   — тот же для широких мест (сайт, RuStore);
    appstore_6.9_{lang}_N.jpg      — App Store, iPhone 6,9" (1320 × 2868);
    play_phone_{lang}_N.jpg        — Google Play, телефон (1080 × 1920: у Play
                                     сторона не длиннее двух других — снимки
                                     1080 × 2400 как есть не принимаются).
    appstore_header_3840x1646_{lang}.png    — App Store, заголовок страницы (21:9);
    appstore_universal_5244x2950_{lang}.png — App Store, общая для заголовка и поиска (16:9);
    appstore_search_3840x2560_{lang}.png, appstore_search_1920x1280_{lang}.png
                                           — App Store, результаты поиска (3:2).
Без прозрачности (RGB) — оба магазина её не любят.

Скриншоты-исходники — docs/store/screens/<язык>/1_*.png … (снимки экрана
телефона как есть); подписи — SHOTS ниже. Для русской страницы нужны снимки
русского интерфейса в docs/store/screens/ru/ с теми же номерами.
"""
import glob
import html
import os
import sys
import tempfile

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'docs', 'store', 'graphics')
ICON = os.path.join(ROOT, 'docs', 'store', 'icons', 'app-store-icon-1024.png')

# Баннер Google Play (1.7.3, решение владельца 25.10.2026): в стиле заголовка
# App Store — значок, название, возможности с круглыми значками, тёплая волна
# и знак «лиса в пламени»; вместо карточки письма по удержанию — свайпы.
BANNER = {
    'ru': dict(
        tag='Ваш почтовый клиент для Android',
        items=[
            ('mail', 'Все ящики', 'Exchange, Gmail, Яндекс, Mail.ru, iCloud'),
            ('swipe', 'Свайпы', 'Удалить, в архив, позже — одним жестом'),
            ('ban', 'Без рекламы', 'Ни рекламы, ни аналитики, ни слежки'),
            ('battery', 'Бережёт батарею', 'Новые письма по сигналу сервера'),
            ('shield', 'Конфиденциальность', 'Письма только у вас и на сервере'),
            ('calendar', 'Календарь', 'Встречи, задачи и контакты'),
        ]),
    'en': dict(
        tag='Your mail client for Android',
        items=[
            ('mail', 'All your mailboxes', 'Exchange, Gmail, Outlook.com, iCloud'),
            ('swipe', 'Swipes', 'Delete, archive or snooze in one gesture'),
            ('ban', 'No ads', 'No ads, no analytics, no tracking'),
            ('battery', 'Easy on battery', 'New mail arrives on a server signal'),
            ('shield', 'Privacy', 'Mail stays on your phone and server'),
            ('calendar', 'Calendar', 'Meetings, tasks and contacts'),
        ]),
}

# Скриншоты: файл-исходник (номер) → заголовок и строка под ним.
SHOTS = {
    'en': [
        ('1', 'Hold a message', 'Reply, forward or follow up — without opening it'),
        ('2', 'All your mail, no ads', 'Deleted by mistake? Undo in one tap'),
        ('3', 'Folders and Favorites', 'Sync only the folders you need, easier on battery'),
        ('4', 'Calendar next to your mail', 'Month view, events and several reminders'),
        ('5', 'Any mailbox', 'Exchange ActiveSync and EWS, Microsoft 365, IMAP, Google, iCloud. Straight from your server'),
    ],
    'ru': [
        ('1', 'Удержите письмо', 'Ответить, переслать, взять на контроль — не открывая'),
        ('2', 'Вся почта — без рекламы', 'Удалили по ошибке? «Вернуть» одним касанием'),
        ('3', 'Папки и избранное', 'Синхронизируются только нужные папки — бережёт батарею'),
        ('4', 'Календарь рядом с почтой', 'Месяц, встречи и несколько напоминаний'),
        ('5', 'Любой ящик', 'Exchange ActiveSync и EWS, Microsoft 365, IMAP, Google, Яндекс, iCloud — напрямую с сервера'),
    ],
}

SIZES = {
    'appstore_6.9': (1320, 2868),
    'play_phone': (1080, 1920),
}

FONT = "Inter, 'DejaVu Sans', sans-serif"


def banner_html(lang, w, h=500):
    """Баннер Google Play в стиле заголовка App Store (creative_html):
    слева значок и название, справа шесть возможностей, внизу тёплая волна.
    1024 × 500 — две колонки по три, 1386 × 500 — три колонки по две."""
    t = BANNER[lang]
    e = html.escape
    cols = 2 if w < 1200 else 3
    rows = (len(t['items']) + cols - 1) // cols
    left_w = 370 if w < 1200 else 470
    row_h = 118 if rows == 3 else 150
    ci = 60 if cols == 2 else 64
    def item(ic, title, sub):
        return (f'<div class="it"><span class="ci"><svg viewBox="0 0 24 24" fill="none" stroke="#1E2A3B" '
                f'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{LUCIDE[ic]}</svg></span>'
                f'<span class="tx"><b>{e(title)}</b><i>{e(sub)}</i></span></div>')
    items = ''.join(item(*x) for x in t['items'])
    mark = _mark_uri('#F3C77E')
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:{w}px;height:{h}px;overflow:hidden}}
.page{{position:absolute;inset:0;font-family:{FONT};color:#1F2329;
background:linear-gradient(160deg,#F7F8FA 0%,#F1F3F7 45%,#F8F5EF 100%);overflow:hidden}}
.sh1{{position:absolute;left:-160px;top:-220px;width:620px;height:520px;border-radius:50%;
background:radial-gradient(circle,rgba(226,231,239,.9) 0%,rgba(226,231,239,0) 70%)}}
.sh2{{position:absolute;right:-160px;top:-180px;width:560px;height:440px;border-radius:50%;
background:radial-gradient(circle,rgba(250,236,210,.7) 0%,rgba(250,236,210,0) 70%)}}
.wave{{position:absolute;left:0;bottom:0;width:{w}px;height:{h * 0.40}px}}
.mark{{position:absolute;left:-46px;bottom:-26px;height:{h * 0.36}px;opacity:.9}}
.left{{position:absolute;left:0;top:47%;width:{left_w}px;transform:translateY(-50%);text-align:center}}
.left img{{width:150px;height:150px;border-radius:34px;box-shadow:0 12px 26px rgba(30,38,52,.30)}}
h1{{margin-top:20px;font-size:44px;font-weight:800;letter-spacing:-.8px;line-height:1}}
.tag{{margin:12px auto 0;max-width:{left_w - 40}px;font-size:21px;line-height:1.3;color:#6A7280;font-weight:500}}
.grid{{position:absolute;left:{left_w}px;right:28px;top:50%;transform:translateY(-50%);
display:grid;grid-template-columns:repeat({cols},1fr);grid-auto-rows:{row_h}px;column-gap:22px}}
.it{{display:flex;align-items:center;gap:{14 if cols == 2 else 16}px;min-width:0}}
.ci{{width:{ci}px;height:{ci}px;border-radius:50%;flex-shrink:0;
background:radial-gradient(circle at 40% 35%,#FCEBCB 0%,#F8DFAF 100%);display:flex;align-items:center;justify-content:center}}
.ci svg{{width:{ci * 0.5}px;height:{ci * 0.5}px}}
.tx{{display:flex;flex-direction:column;min-width:0}}
.tx b{{font-size:{20 if cols == 2 else 21}px;font-weight:700;color:#1E2A3B;line-height:1.15;white-space:nowrap}}
.tx i{{font-style:normal;font-size:{15 if cols == 2 else 16}px;line-height:1.3;color:#6F7785;margin-top:4px}}
</style></head><body><div class="page">
<div class="sh1"></div><div class="sh2"></div>
<svg class="wave" viewBox="0 0 2000 400" preserveAspectRatio="none"><defs>
<linearGradient id="g1" x1="0" x2="1"><stop offset="0" stop-color="#F6D9A6"/><stop offset="1" stop-color="#F9E6C4"/></linearGradient>
<linearGradient id="g2" x1="0" x2="1"><stop offset="0" stop-color="#FBEBD0"/><stop offset="1" stop-color="#F5D7A2"/></linearGradient></defs>
<path d="M0 230 C 420 120, 820 330, 1250 250 S 1800 120, 2000 170 L2000 400 L0 400 Z" fill="url(#g2)" opacity=".55"/>
<path d="M0 300 C 500 210, 900 380, 1350 310 S 1820 230, 2000 260 L2000 400 L0 400 Z" fill="url(#g1)" opacity=".75"/>
</svg>
<img class="mark" src="{mark}">
<div class="left"><img src="file://{ICON}"><h1>Ogneliss Mail</h1><div class="tag">{e(t['tag'])}</div></div>
<div class="grid">{items}</div>
</div></body></html>"""


def screen_html(w, h, shot, title, sub):
    e = html.escape
    k = w / 1320  # всё — от размера App Store
    cap_top = round((150 if h / w > 2 else 96) * k)
    title_px = round(96 * k)
    sub_px = round(44 * k)
    # Снимок 1080 × 2400 в рамке: ширина по месту под подписью.
    area_top = cap_top + round(title_px * 1.2) + round(sub_px * 2.6) + round(80 * k)
    bezel = round(18 * k)
    avail_h = h - area_top - round(70 * k)
    sh = avail_h - 2 * bezel
    sw = round(sh * 1080 / 2400)
    max_w = round(w * 0.78)
    if sw + 2 * bezel > max_w:
        sw = max_w - 2 * bezel
        sh = round(sw * 2400 / 1080)
    radius = round(64 * k)
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{width:{w}px;height:{h}px;overflow:hidden;font-family:{FONT};color:#1F2329;position:relative;
background:linear-gradient(170deg,#F5F7FA 0%,#E6EBF2 50%,#D3DCEA 100%)}}
.glow{{position:absolute;left:50%;top:{round(h * 0.42)}px;width:{round(w * 1.3)}px;height:{round(w * 1.3)}px;
transform:translate(-50%,-50%);border-radius:50%;background:radial-gradient(circle,#C3D1E6 0%,rgba(195,209,230,0) 65%)}}
.cap{{position:absolute;left:{round(80 * k)}px;right:{round(80 * k)}px;top:{cap_top}px;text-align:center}}
h1{{font-size:{title_px}px;font-weight:800;letter-spacing:{-1.5 * k:.2f}px;line-height:1.08}}
p{{margin-top:{round(22 * k)}px;font-size:{sub_px}px;font-weight:500;color:#4A5468;line-height:1.3}}
.phone{{position:absolute;left:50%;top:{area_top}px;transform:translateX(-50%);padding:{bezel}px;
background:#2E333B;border-radius:{radius + bezel}px;box-shadow:0 {round(40 * k)}px {round(90 * k)}px rgba(31,35,41,.32)}}
.phone img{{display:block;width:{sw}px;height:{sh}px;border-radius:{radius}px}}
</style></head><body><div class="glow"></div>
<div class="cap"><h1>{e(title)}</h1><p>{e(sub)}</p></div>
<div class="phone"><img src="file://{shot}"></div>
</body></html>'''


# ── App Store: заголовок страницы и результаты поиска (25.10.2026) ──
# Баннер приложения (образец владельца 25.10.2026): слева значок, название и
# строка «для iPhone и iPad», справа десять возможностей в две колонки со
# значками в персиковых кругах; внизу тёплая волна и знак «лиса в пламени».
# Размеры — App Store Connect → Creative assets. Без прозрачности.
CREATIVE = {
    'appstore_header_3840x1646': (3840, 1646),
    'appstore_universal_5244x2950': (5244, 2950),
    'appstore_search_3840x2560': (3840, 2560),
    'appstore_search_1920x1280': (1920, 1280),
}

# Значки Lucide (ISC), обводка 2 на сетке 24.
LUCIDE = {
    'mail': '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
    'calendar': '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M9 15l2 2 4-4"/>',
    'users': '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>'
             '<path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    'shield': '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
    'sync': '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/>'
            '<path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
    'widgets': '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/>'
               '<rect x="14" y="14" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/>',
    'ban': '<circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/>',
    'battery': '<rect x="2" y="7" width="16" height="10" rx="2"/><path d="M22 11v2M6 11v2M10 11v2"/>',
    'bell': '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    'cloud': '<path d="M4 14.9A7 7 0 1 1 15.7 8h1.8a4.5 4.5 0 0 1 2.5 8.2"/><path d="M12 12v9M16 16l-4-4-4 4"/>',
    'swipe': '<path d="m18 8 4 4-4 4"/><path d="M2 12h20"/><path d="m6 8-4 4 4 4"/>',
}

CREATIVE_TEXT = {
    'ru': dict(
        tag='Ваш почтовый клиент для iPhone и iPad',
        items=[
            ('mail', 'Все почтовые ящики', 'Exchange, Gmail, Яндекс, Mail.ru, iCloud и IMAP'),
            ('widgets', 'Виджеты', 'Почта и «Мой день» на экране «Домой»'),
            ('calendar', 'Календарь', 'Встречи, напоминания и занятость коллег'),
            ('ban', 'Без рекламы', 'Ни рекламы, ни аналитики, ни слежки'),
            ('users', 'Контакты', 'Ваши контакты и адресная книга организации'),
            ('battery', 'Бережёт батарею', 'Новые письма по сигналу сервера'),
            ('shield', 'Конфиденциальность', 'Письма только на телефоне и у вашей почты'),
            ('bell', 'Умные уведомления', 'Важные отправители и тихие часы'),
            ('sync', 'Синхронизация', 'ActiveSync, EWS, IMAP, CalDAV и CardDAV'),
            ('cloud', 'Резервные копии', 'Сохранение и перенос на новый телефон'),
        ]),
    'en': dict(
        tag='Your mail client for iPhone and iPad',
        items=[
            ('mail', 'All your mailboxes', 'Exchange, Gmail, Outlook.com, iCloud and IMAP'),
            ('widgets', 'Widgets', 'Mail and My Day on the Home Screen'),
            ('calendar', 'Calendar', 'Meetings, reminders and availability'),
            ('ban', 'No ads', 'No ads, no analytics, no tracking'),
            ('users', 'Contacts', 'Your contacts and the company directory'),
            ('battery', 'Easy on battery', 'New mail arrives on a server signal'),
            ('shield', 'Privacy', 'Mail stays on your phone and mail server'),
            ('bell', 'Smart notifications', 'Important senders and quiet hours'),
            ('sync', 'Sync', 'ActiveSync, EWS, IMAP, CalDAV and CardDAV'),
            ('cloud', 'Backups', 'Save and move to a new phone'),
        ]),
}

MARK = os.path.join(ROOT, 'assets', 'branding', 'ogneliss-mark.svg')


def _mark_uri(color):
    """Знак «лиса в пламени» без белого фона, нужного цвета — для фона баннера."""
    import base64
    import re
    svg = open(MARK, encoding='utf-8').read()
    svg = re.sub(r'<rect[^>]*/>', '', svg, count=1).replace('#fdba02', color)
    return 'data:image/svg+xml;base64,' + base64.b64encode(svg.encode()).decode()


def creative_html(lang, w, h):
    t = CREATIVE_TEXT[lang]
    e = html.escape
    # Макет в условных единицах ширины 2000, высота — по пропорциям холста.
    k = w / 2000
    H = h / k
    row = min(168, (H - 110) / 5)  # высота строки возможностей
    grid_h = row * 5
    icon = min(390, H * 0.43)
    def item(ic, title, sub):
        return (f'<div class="it"><span class="ci"><svg viewBox="0 0 24 24" fill="none" stroke="#1E2A3B" '
                f'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{LUCIDE[ic]}</svg></span>'
                f'<span class="tx"><b>{e(title)}</b><i>{e(sub)}</i></span></div>')
    items = ''.join(item(*x) for x in t['items'])
    mark = _mark_uri('#F3C77E')
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:{w}px;height:{h}px;overflow:hidden}}
.page{{position:absolute;left:0;top:0;width:2000px;height:{H}px;transform:scale({k:.5f});transform-origin:0 0;
font-family:{FONT};color:#1F2329;background:linear-gradient(160deg,#F7F8FA 0%,#F1F3F7 45%,#F8F5EF 100%);overflow:hidden}}
.sh1{{position:absolute;left:-200px;top:-300px;width:1100px;height:900px;border-radius:50%;
background:radial-gradient(circle,rgba(226,231,239,.9) 0%,rgba(226,231,239,0) 70%)}}
.sh2{{position:absolute;right:-250px;top:-250px;width:900px;height:700px;border-radius:50%;
background:radial-gradient(circle,rgba(250,236,210,.7) 0%,rgba(250,236,210,0) 70%)}}
.wave{{position:absolute;left:0;bottom:0;width:2000px;height:{H * 0.42}px}}
.mark{{position:absolute;left:-105px;bottom:{-H * 0.05}px;height:{H * 0.33}px;opacity:.9}}
.left{{position:absolute;left:40px;width:780px;top:47%;transform:translateY(-50%);text-align:center}}
.left img{{width:{icon}px;height:{icon}px;border-radius:{icon * 0.225}px;
box-shadow:0 {icon * 0.08}px {icon * 0.16}px rgba(30,38,52,.30)}}
h1{{margin-top:{icon * 0.12}px;font-size:{icon * 0.235}px;font-weight:800;letter-spacing:-1.5px;line-height:1}}
.tag{{margin:{icon * 0.1}px auto 0;max-width:620px;font-size:{icon * 0.12}px;line-height:1.3;color:#6A7280;font-weight:500}}
.grid{{position:absolute;left:800px;right:40px;top:50%;height:{grid_h}px;transform:translateY(-50%);
display:grid;grid-template-columns:1fr 1fr;grid-auto-rows:{row}px;column-gap:40px}}
.it{{display:flex;align-items:center;gap:{row * 0.2}px;min-width:0}}
.ci{{width:{row * 0.66}px;height:{row * 0.66}px;border-radius:50%;flex-shrink:0;
background:radial-gradient(circle at 40% 35%,#FCEBCB 0%,#F8DFAF 100%);display:flex;align-items:center;justify-content:center}}
.ci svg{{width:{row * 0.34}px;height:{row * 0.34}px}}
.tx{{display:flex;flex-direction:column;min-width:0;max-width:{row * 2.9}px}}
.tx b{{font-size:{row * 0.175}px;font-weight:700;color:#1E2A3B;white-space:nowrap}}
.tx i{{font-style:normal;font-size:{row * 0.14}px;line-height:1.3;color:#7A8290;margin-top:{row * 0.04}px}}
</style></head><body><div class="page">
<div class="sh1"></div><div class="sh2"></div>
<svg class="wave" viewBox="0 0 2000 400" preserveAspectRatio="none"><defs>
<linearGradient id="g1" x1="0" x2="1"><stop offset="0" stop-color="#F6D9A6"/><stop offset="1" stop-color="#F9E6C4"/></linearGradient>
<linearGradient id="g2" x1="0" x2="1"><stop offset="0" stop-color="#FBEBD0"/><stop offset="1" stop-color="#F5D7A2"/></linearGradient></defs>
<path d="M0 230 C 420 120, 820 330, 1250 250 S 1800 120, 2000 170 L2000 400 L0 400 Z" fill="url(#g2)" opacity=".55"/>
<path d="M0 300 C 500 210, 900 380, 1350 310 S 1820 230, 2000 260 L2000 400 L0 400 Z" fill="url(#g1)" opacity=".75"/>
</svg>
<img class="mark" src="{mark}">
<div class="left"><img src="file://{ICON}"><h1>Ogneliss Mail</h1><div class="tag">{e(t['tag'])}</div></div>
<div class="grid">{items}</div>
</div></body></html>"""


def render(page_html, w, h, out, tmp, jpeg=False):
    path = os.path.join(tmp, 'page.html')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(page_html)
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={'width': w, 'height': h})
        pg.goto('file://' + path)
        pg.wait_for_load_state('networkidle')
        pg.wait_for_timeout(200)
        png = os.path.join(tmp, 'shot.png')
        pg.screenshot(path=png)
        b.close()
    im = Image.open(png).convert('RGB')
    if jpeg:
        im.save(out, 'JPEG', quality=92, optimize=True)
    else:
        im.save(out, 'PNG', optimize=True)
    print('  ', os.path.relpath(out, ROOT), im.size)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        if what in ('all', 'banners'):
            for lang in ('ru', 'en'):
                for w in (1024, 1386):
                    render(banner_html(lang, w), w, 500, os.path.join(OUT, f'feature_{w}x500_{lang}.png'), tmp)
        if what in ('all', 'creative'):
            for lang in ('ru', 'en'):
                for name, (w, h) in CREATIVE.items():
                    render(creative_html(lang, w, h), w, h,
                           os.path.join(OUT, f'{name}_{lang}.png'), tmp)
        if what in ('all', 'screens'):
            for lang, shots in SHOTS.items():
                src = os.path.join(ROOT, 'docs', 'store', 'screens', lang)
                for n, title, sub in shots:
                    found = sorted(glob.glob(os.path.join(src, f'{n}_*.png')))
                    if not found:
                        print(f'   нет снимка {lang}/{n}_*.png — пропуск')
                        continue
                    for kind, (w, h) in SIZES.items():
                        render(screen_html(w, h, found[0], title, sub), w, h,
                               os.path.join(OUT, f'{kind}_{lang}_{n}.jpg'), tmp, jpeg=True)


if __name__ == '__main__':
    main()
