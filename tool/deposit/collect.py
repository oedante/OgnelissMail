#!/usr/bin/env python3
"""Депонируемые материалы для регистрации программы в Роспатенте.

Собирает фрагменты исходного текста «Ogneliss Mail» в один файл: не больше
50 страниц по 50 строк, с заголовками «файл, строки» и номерами страниц.
План и требования — docs/plan/REGISTRATION_ROSPATENT.md, раздел 5.

Запуск из корня проекта:
    python3 tool/deposit/collect.py            # → build/deposit/
    python3 tool/deposit/collect.py --pages 40

Результат:
    build/deposit/deposit.pdf   — титульный лист и страницы кода (если есть
                                  reportlab: pip install reportlab; 24.10.2026);
    build/deposit/deposit.txt   — текст для печати/конвертации (страницы — \\f);
    build/deposit/deposit.html  — то же для браузера (разрывы страниц при печати);
    build/deposit/report.txt    — что вошло, сколько строк и что вычищено.

Титульный лист (название, правообладатель, автор — требование ФИПС) —
константы TITLE ниже; он идёт первой страницей во всех трёх файлах.

PDF/A из текста (LibreOffice):
    soffice --headless --convert-to \\
      'pdf:writer_pdf_Export:{"SelectPdfVersion":{"type":"long","value":"1"}}' \\
      build/deposit/deposit.txt --outdir build/deposit
Затем открыть PDF и проверить: шрифт моноширинный, ≤ 50 страниц, номера страниц.

Обезличивание: строки с секретами и адресами внутренних серверов заменяются
на «[удалено]», и это пишется в report.txt — проверьте его перед подачей.
"""
import argparse
import html
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..'))
LINES_PER_PAGE = 50

# Титульный лист депонируемых материалов.
TITLE = [
    'Программа для ЭВМ',
    '',
    '«Ogneliss Mail»',
    '',
    'Правообладатель: Ермишин Олег Андреевич',
    'Автор: Ермишин Олег Андреевич',
    '',
    'Фрагменты исходного текста',
    'Языки программирования: Dart, Kotlin, Swift',
]

# Моноширинный шрифт с кириллицей для PDF (первый найденный) или --font.
FONTS = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
    '/Library/Fonts/DejaVuSansMono.ttf',
    os.path.expanduser('~/Library/Fonts/DejaVuSansMono.ttf'),
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    r'C:\Windows\Fonts\consola.ttf',
    r'C:\Windows\Fonts\cour.ttf',
]
WIDTH = 100  # длинные строки переносятся

# Модули и сколько страниц на каждый (оригинальная часть программы).
# Для каждого — начало файла (заголовок с описанием) и ключевые функции.
PLAN = [
    ('lib/main.dart', 3, None),
    ('packages/mail_engine/lib/src/transport/eas_engine.dart', 8, [r'Future<ConnectResult> connect\(', r'Future<bool> _provisionAttempt\(']),
    ('lib/services/sync/sync_service.dart', 6, [r'Future<void> _notifyNewMail\(']),
    ('lib/services/security/mail_classification.dart', 4, None),
    ('lib/services/rules/device_rules_service.dart', 5, [r'Future<Map<String, RuleOutcome>> apply\(']),
    ('lib/services/mail/control_service.dart', 4, None),
    ('lib/services/mail/own_addresses.dart', 2, None),
    ('lib/services/mail/own_identity_service.dart', 3, None),
    ('lib/services/sync/sync_schedule.dart', 2, None),
    ('lib/services/sync/imap_push_service.dart', 4, [r'Future<void> ensureAlive\(']),
    ('android/app/src/main/kotlin/com/ogneliss/mail/SyncHeartbeat.kt', 2, None),
    ('android/app/src/main/kotlin/com/ogneliss/mail/HomeWidgets.kt', 3, None),
    ('lib/main.dart#end', 1, None),
]

# Что вычищается (строка целиком заменяется).
SECRET = re.compile(
    r'(client_?secret|api[_-]?key|password\s*[:=]\s*[\'"][^\'"]+[\'"]|BEGIN (RSA |EC )?PRIVATE KEY|'
    r'AIza[0-9A-Za-z_\-]{20,}|sha256/[A-Za-z0-9+/=]{20,}|DeviceId=[A-Z]{4}[0-9A-F]{24})',
    re.IGNORECASE)


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8') as f:
        return f.read().split('\n')


def pick(lines, pages, anchors):
    """Начало файла и фрагменты от якорей — всего не больше pages страниц."""
    budget = pages * LINES_PER_PAGE
    if not anchors:
        return [(0, min(len(lines), budget))]
    head = min(len(lines), budget // 3)
    ranges = [(0, head)]
    rest = (budget - head) // len(anchors)
    for a in anchors:
        rx = re.compile(a)
        i = next((n for n, l in enumerate(lines) if rx.search(l)), None)
        if i is None:
            print(f'  ! якорь не найден: {a}', file=sys.stderr)
            continue
        ranges.append((max(i - 3, 0), min(i - 3 + rest, len(lines))))
    # слить пересечения
    ranges.sort()
    out = []
    for s, e in ranges:
        if out and s <= out[-1][1]:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out


def wrap(line):
    line = line.replace('\t', '    ')
    if len(line) <= WIDTH:
        return [line]
    return [line[i:i + WIDTH] for i in range(0, len(line), WIDTH)]


def version():
    """Версия из pubspec.yaml — на титульный лист."""
    try:
        with open(os.path.join(ROOT, 'pubspec.yaml'), encoding='utf-8') as f:
            m = re.search(r'^version:\s*(\S+)', f.read(), re.M)
        return m.group(1) if m else ''
    except OSError:
        return ''


def write_pdf(path, head, title, pages, font=None):
    """PDF: титульный лист и страницы по 50 строк. None — готово, иначе причина."""
    try:
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.units import mm
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        from reportlab.pdfgen import canvas
    except ImportError:
        return 'PDF не собран: нет reportlab (pip install reportlab) — есть deposit.txt и deposit.html'
    font = next((f for f in ([font] if font else FONTS) if f and os.path.exists(f)), None)
    if not font:
        return 'PDF не собран: нет моноширинного шрифта с кириллицей (--font путь.ttf)'
    pdfmetrics.registerFont(TTFont('Mono', font))
    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle(head)
    w, h = A4
    c.setFont('Mono', 12)
    y = h - 90 * mm
    for t in title:
        c.drawCentredString(w / 2, y, t)
        y -= 7 * mm
    c.showPage()
    step = (h - 30 * mm) / LINES_PER_PAGE
    for i, p in enumerate(pages, 1):
        c.setFont('Mono', 7)
        c.drawString(12 * mm, h - 12 * mm, f'{head}    стр. {i} из {len(pages)}')
        c.line(12 * mm, h - 13.5 * mm, w - 12 * mm, h - 13.5 * mm)
        c.setFont('Mono', 8.2)
        y = h - 13.5 * mm - step
        for ln in p:
            c.drawString(12 * mm, y, ln)
            y -= step
        c.showPage()
    c.save()
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--font', help='моноширинный TTF с кириллицей для PDF')
    ap.add_argument('--pages', type=int, default=50, help='предел страниц (по умолчанию 50)')
    ap.add_argument('--out', default=os.path.join(ROOT, 'build', 'deposit'))
    a = ap.parse_args()

    body = []      # строки итогового текста (без нумерации страниц)
    report = []
    removed = 0
    for path, pages, anchors in PLAN:
        tail = path.endswith('#end')
        real = path[:-4] if tail else path
        lines = read(real)
        if tail:
            ranges = [(max(len(lines) - pages * LINES_PER_PAGE, 0), len(lines))]
        else:
            ranges = pick(lines, pages, anchors)
        for s, e in ranges:
            body.append(f'===== {real}, строки {s + 1}–{e} =====')
            for n in range(s, e):
                l = lines[n]
                if SECRET.search(l):
                    removed += 1
                    report.append(f'  вычищено: {real}:{n + 1}')
                    l = re.sub(r'\S.*', '[удалено]', l, count=1)
                body.extend(wrap(l))
            body.append('')
        report.append(f'{real}: {sum(e - s for s, e in ranges)} строк')

    limit = a.pages * (LINES_PER_PAGE - 2)  # 2 строки — колонтитул
    if len(body) > limit:
        report.append(f'обрезано до {a.pages} страниц (было {len(body)} строк)')
        body = body[:limit]

    pages = [body[i:i + LINES_PER_PAGE - 2] for i in range(0, len(body), LINES_PER_PAGE - 2)]
    total = len(pages)
    os.makedirs(a.out, exist_ok=True)
    head = 'Ogneliss Mail — фрагменты исходного текста программы для ЭВМ'
    ver = version()
    title = TITLE + ([f'Версия: {ver}'] if ver else []) + [f'Страниц исходного текста: {total}']
    with open(os.path.join(a.out, 'deposit.txt'), 'w', encoding='utf-8') as f:
        f.write('\n' * 12 + '\n'.join(t.center(WIDTH).rstrip() for t in title) + '\n\f')
        for i, p in enumerate(pages, 1):
            f.write(f'{head}    стр. {i} из {total}\n\n')
            f.write('\n'.join(p))
            f.write('\n\f' if i < total else '\n')
    with open(os.path.join(a.out, 'deposit.html'), 'w', encoding='utf-8') as f:
        f.write('<!doctype html><meta charset="utf-8"><title>Ogneliss Mail — депонирование</title>'
                '<style>body{font:9pt/1.25 "DejaVu Sans Mono",monospace}'
                '.p{page-break-after:always;white-space:pre-wrap}h6{font-size:8pt;margin:0 0 6pt}'
                '.t{page-break-after:always;text-align:center;padding-top:70mm;font-size:12pt;line-height:1.6}</style>')
        f.write('<div class="t">' + '<br>'.join(html.escape(t) for t in title) + '</div>')
        for i, p in enumerate(pages, 1):
            f.write(f'<div class="p"><h6>{html.escape(head)} — стр. {i} из {total}</h6>'
                    f'{html.escape(chr(10).join(p))}</div>')
    note = write_pdf(os.path.join(a.out, 'deposit.pdf'), head, title, pages, a.font)
    if note:
        report.append(note)
    report.insert(0, f'страниц: {total} + титульный лист, строк кода: {len(body)}, вычищено строк: {removed}')
    with open(os.path.join(a.out, 'report.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(report) + '\n')
    print('\n'.join(report[:1] + [r for r in report if r.startswith(('обрезано', 'PDF'))]))
    print(f'готово: {a.out}/{"" if note else "deposit.pdf, "}deposit.txt, deposit.html, report.txt')
    return 0


if __name__ == '__main__':
    sys.exit(main())
