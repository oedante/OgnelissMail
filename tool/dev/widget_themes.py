#!/usr/bin/env python3
"""Варианты оформления виджетов Android: светлый и тёмный (1.7.0).

Зачем: виджет рисует лаунчер, и цвета из ресурсов (@color/widget_*, у которых
есть вариант values-night) он берёт по теме ТЕЛЕФОНА. Настройка приложения
«Тема виджетов» (как в системе / светлая / тёмная) требует ресурсов, которые от
темы телефона не зависят. Этот скрипт делает их из обычных:

  · values/colors_widget_themes.xml — widget_<имя>_lt (светлый, из values/)
    и widget_<имя>_dk (тёмный, из values-night/);
  · values/styles_widget_themes.xml — стили Widget<Имя>Lt / Widget<Имя>Dk;
  · drawable/widget_<имя>_lt.xml / _dk.xml — для фонов и значков с цветами;
  · layout/widget_<имя>_lt.xml / _dk.xml — разметка с этими ссылками;
  · kotlin/.../WidgetThemeRes.kt — таблицы «обычный ресурс → светлый/тёмный»
    для HomeWidgets.kt (WidgetUi.layout/color/drawable).

Запускать после любой правки разметки, стилей, цветов или фонов виджетов:
    python3 tool/dev/widget_themes.py
Созданные файлы руками не править — следующий запуск перезапишет их.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RES = os.path.join(ROOT, 'android/app/src/main/res')
KT = os.path.join(ROOT, 'android/app/src/main/kotlin/com/ogneliss/mail/WidgetThemeRes.kt')
SUF = {'lt': ('_lt', 'Lt'), 'dk': ('_dk', 'Dk')}
HEADER = 'Сгенерировано tool/dev/widget_themes.py — не править вручную.'


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def write(p, s):
    old = read(p) if os.path.exists(p) else None
    if old != s:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(s)
        return 1
    return 0


def colors(path):
    out = {}
    for m in re.finditer(r'<color\s+name="(widget_[a-z0-9_]+)"\s*>([^<]+)</color>', read(path)):
        out[m.group(1)] = m.group(2).strip()
    return out


def generated(name):
    return name.endswith('_lt') or name.endswith('_dk')


def main():
    changed = 0
    light = colors(os.path.join(RES, 'values/colors.xml'))
    night = colors(os.path.join(RES, 'values-night/colors.xml'))
    light = {k: v for k, v in light.items() if not generated(k)}

    # ── цвета ──
    lines = ['<?xml version="1.0" encoding="utf-8"?>', f'<!-- {HEADER} -->', '<resources>']
    for name, val in sorted(light.items()):
        lines.append(f'    <color name="{name}_lt">{val}</color>')
        lines.append(f'    <color name="{name}_dk">{night.get(name, val)}</color>')
    lines.append('</resources>')
    changed += write(os.path.join(RES, 'values/colors_widget_themes.xml'), '\n'.join(lines) + '\n')

    # ── фоны и значки: только те, где есть цвета виджета ──
    ddir = os.path.join(RES, 'drawable')
    drawables = {}
    for fn in sorted(os.listdir(ddir)):
        base = fn[:-4]
        if not fn.startswith('widget_') or not fn.endswith('.xml') or generated(base):
            continue
        drawables[base] = read(os.path.join(ddir, fn))
    themed_dr = {k for k, v in drawables.items() if '@color/widget_' in v}
    # Фон, ссылающийся на другой фон с цветами, — тоже свой вариант.
    grew = True
    while grew:
        grew = False
        for k, v in drawables.items():
            if k not in themed_dr and any(f'@drawable/{t}"' in v for t in themed_dr):
                themed_dr.add(k)
                grew = True

    styles_src = read(os.path.join(RES, 'values/styles.xml'))
    styles = {}
    for m in re.finditer(r'<style\s+name="(Widget[A-Za-z0-9]*)"([^>]*)>(.*?)</style>', styles_src, re.S):
        if generated(m.group(1)):
            continue
        styles[m.group(1)] = (m.group(2), m.group(3))

    def themed(text, key):
        suf, ssuf = SUF[key]
        text = re.sub(r'@color/(widget_[a-z0-9_]+)', lambda m: f'@color/{m.group(1)}{suf}'
                      if m.group(1) in light else m.group(0), text)
        text = re.sub(r'@drawable/(widget_[a-z0-9_]+)', lambda m: f'@drawable/{m.group(1)}{suf}'
                      if m.group(1) in themed_dr else m.group(0), text)
        text = re.sub(r'@style/(Widget[A-Za-z0-9]*)', lambda m: f'@style/{m.group(1)}{ssuf}'
                      if m.group(1) in styles else m.group(0), text)
        text = re.sub(r'@layout/(widget_[a-z0-9_]+)', lambda m: f'@layout/{m.group(1)}{suf}', text)
        return text

    def mark(xml):
        # Пометка «не править» — после строки <?xml …?>.
        if xml.startswith('<?xml'):
            i = xml.index('?>') + 2
            return xml[:i] + f'\n<!-- {HEADER} -->' + xml[i:]
        return f'<!-- {HEADER} -->\n' + xml

    for base in sorted(themed_dr):
        for key, (suf, _) in SUF.items():
            changed += write(os.path.join(ddir, f'{base}{suf}.xml'), mark(themed(drawables[base], key)))

    # ── стили ──
    lines = ['<?xml version="1.0" encoding="utf-8"?>', f'<!-- {HEADER} -->', '<resources>']
    for name, (attrs, body) in styles.items():
        for key, (_, ssuf) in SUF.items():
            a = re.sub(r'parent="(Widget[A-Za-z0-9]*)"', lambda m: f'parent="{m.group(1)}{ssuf}"'
                       if m.group(1) in styles else m.group(0), attrs)
            lines.append(f'    <style name="{name}{ssuf}"{a}>{themed(body, key)}</style>')
    lines.append('</resources>')
    changed += write(os.path.join(RES, 'values/styles_widget_themes.xml'), '\n'.join(lines) + '\n')

    # ── разметка ──
    ldir = os.path.join(RES, 'layout')
    layouts = []
    for fn in sorted(os.listdir(ldir)):
        base = fn[:-4]
        if not fn.startswith('widget_') or not fn.endswith('.xml') or generated(base):
            continue
        layouts.append(base)
        src = read(os.path.join(ldir, fn))
        for key, (suf, _) in SUF.items():
            changed += write(os.path.join(ldir, f'{base}{suf}.xml'), mark(themed(src, key)))

    # ── таблицы для Kotlin ──
    def table(kind, names):
        rows = ',\n'.join(f'        R.{kind}.{n} to (R.{kind}.{n}_lt to R.{kind}.{n}_dk)' for n in names)
        return f'    val {kind}s: Map<Int, Pair<Int, Int>> = mapOf(\n{rows},\n    )\n'

    kt = (
        '// ' + HEADER + '\n'
        '// Ресурсы виджетов в светлом (_lt) и тёмном (_dk) оформлении — для\n'
        '// настройки «Тема виджетов» (WidgetUi.layout / color / drawable).\n'
        'package com.ogneliss.mail\n\n'
        'internal object WidgetThemeRes {\n'
        + table('layout', layouts) + '\n'
        + table('color', sorted(light)) + '\n'
        + table('drawable', sorted(themed_dr))
        + '}\n'
    )
    changed += write(KT, kt)
    print(f'Цветов {len(light)}, стилей {len(styles)}, фонов {len(themed_dr)}, разметок {len(layouts)}; '
          f'изменено файлов: {changed}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
