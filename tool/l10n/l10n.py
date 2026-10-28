#!/usr/bin/env python3
"""Строки интерфейса Ogneliss Mail — файлы assets/l10n/<код>.xml (1.7.3).

Решение владельца 25.10.2026: все переводы — в одном виде, файлами XML на
каждый язык, с одними и теми же ключами («потом сами запутаемся»; один ключ
можно брать в разных окнах). Формат — ресурсы строк Android (strings.xml):

    <string name="ключ">Текст</string>
    <plurals name="ключ"><item quantity="one">…</item>…</plurals>

Экранирование — как в Android: \\' \\" \\n \\t \\\\, &amp; &lt; &gt;; пробелы в
начале и в конце — внутри кавычек "…". Такой файл понимают Play Console,
переводчики и их программы.

Главный язык — английский (en.xml): по нему порядок ключей и проверка
полноты. Ключи вопросов-ответов — faq_<раздел>_title, faq_<раздел>_<n>_q /
_a; тексты запросов разрешений iPhone — ios_<ключ Info.plist>.

Команды (из корня проекта):
  set FILE.json          добавить или заменить строки:
                         {"ключ": {"ru": …, "en": …, "de": …, "fr": …, …}};
                         множественное число — формы через «|» по порядку
                         языка (ru: one|few|many, en/de/fr: one|other).
  remove KEY [KEY…]      удалить ключи из всех языков.
  check-code             ключи l10n.tr('…') / plural('…'), которых нет в en.xml.
  status                 сколько строк в каждом языке (и чего не хватает).
  export --job DIR [--lang xx] [--chunk N] [--ru-max N]
                         строки на перевод (английский и русский) —
                         DIR/src/chunk_NN.json; с --lang — только недостающие;
                         --ru-max — русский только у строк до N знаков.
  check --job DIR --lang xx [--chunk N]
                         проверить перевод DIR/out/xx/*.json (или один кусок).
  build --job DIR --lang xx [--lang yy …]
                         перевод из DIR/out/xx — в assets/l10n/xx.xml.
  gen                    список языков lib/l10n/languages.g.dart, языки в
                         locales_config.xml (Android) и Info.plist (iPhone).
  migrate                (разово, 1.7.3) app_strings*.dart и faq_content.dart → XML.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
L10N = os.path.join(ROOT, 'assets', 'l10n')
MASTER = 'en'
CORE = ['ru', 'en', 'de', 'fr']

# Код → (название на этом языке, по-английски, формы множественного числа
# по порядку — категории CLDR для целых чисел; переводчик даёт столько форм
# через «|»). Форма «other» нужна всегда: если её нет в списке (ru, uk, pl —
# она для дробных чисел), берётся последняя. Правило выбора формы —
# lib/l10n/strings_store.dart (pluralCategory).
LANGS = {
    'ru': ('Русский', 'Russian', ['one', 'few', 'many']),
    'en': ('English', 'English', ['one', 'other']),
    'de': ('Deutsch', 'German', ['one', 'other']),
    'fr': ('Français', 'French', ['one', 'other']),
    'ar': ('العربية', 'Arabic', ['zero', 'one', 'two', 'few', 'many', 'other']),
    'bg': ('Български', 'Bulgarian', ['one', 'other']),
    'bn': ('বাংলা', 'Bengali', ['one', 'other']),
    'ca': ('Català', 'Catalan', ['one', 'other']),
    'cs': ('Čeština', 'Czech', ['one', 'few', 'other']),
    'da': ('Dansk', 'Danish', ['one', 'other']),
    'el': ('Ελληνικά', 'Greek', ['one', 'other']),
    'es': ('Español', 'Spanish', ['one', 'other']),
    'et': ('Eesti', 'Estonian', ['one', 'other']),
    'fa': ('فارسی', 'Persian', ['one', 'other']),
    'fi': ('Suomi', 'Finnish', ['one', 'other']),
    'gu': ('ગુજરાતી', 'Gujarati', ['one', 'other']),
    'he': ('עברית', 'Hebrew', ['one', 'two', 'other']),
    'hi': ('हिन्दी', 'Hindi', ['one', 'other']),
    'hr': ('Hrvatski', 'Croatian', ['one', 'few', 'other']),
    'hu': ('Magyar', 'Hungarian', ['one', 'other']),
    'id': ('Bahasa Indonesia', 'Indonesian', ['other']),
    'is': ('Íslenska', 'Icelandic', ['one', 'other']),
    'it': ('Italiano', 'Italian', ['one', 'other']),
    'ja': ('日本語', 'Japanese', ['other']),
    'kn': ('ಕನ್ನಡ', 'Kannada', ['one', 'other']),
    'ko': ('한국어', 'Korean', ['other']),
    'lt': ('Lietuvių', 'Lithuanian', ['one', 'few', 'other']),
    'lv': ('Latviešu', 'Latvian', ['zero', 'one', 'other']),
    'ml': ('മലയാളം', 'Malayalam', ['one', 'other']),
    'mr': ('मराठी', 'Marathi', ['one', 'other']),
    'nb': ('Norsk bokmål', 'Norwegian', ['one', 'other']),
    'nl': ('Nederlands', 'Dutch', ['one', 'other']),
    'pa': ('ਪੰਜਾਬੀ', 'Punjabi', ['one', 'other']),
    'pl': ('Polski', 'Polish', ['one', 'few', 'many']),
    'pt': ('Português (Brasil)', 'Portuguese (Brazil)', ['one', 'other']),
    'ro': ('Română', 'Romanian', ['one', 'few', 'other']),
    'sk': ('Slovenčina', 'Slovak', ['one', 'few', 'other']),
    'sl': ('Slovenščina', 'Slovenian', ['one', 'two', 'few', 'other']),
    'sv': ('Svenska', 'Swedish', ['one', 'other']),
    'sw': ('Kiswahili', 'Swahili', ['one', 'other']),
    'ta': ('தமிழ்', 'Tamil', ['one', 'other']),
    'te': ('తెలుగు', 'Telugu', ['one', 'other']),
    'th': ('ไทย', 'Thai', ['other']),
    'tr': ('Türkçe', 'Turkish', ['one', 'other']),
    'uk': ('Українська', 'Ukrainian', ['one', 'few', 'many']),
    'ur': ('اردو', 'Urdu', ['one', 'other']),
    'vi': ('Tiếng Việt', 'Vietnamese', ['other']),
    'zh': ('简体中文', 'Chinese (Simplified)', ['other']),
    'zu': ('isiZulu', 'Zulu', ['one', 'other']),
}
RTL = {'ar', 'he', 'fa', 'ur'}
# Языки, где кириллица в переводе — норма.
CYRILLIC = {'ru', 'uk', 'bg'}
PH = re.compile(r'\{[A-Za-z0-9_]+\}')

HEADER = '''<?xml version="1.0" encoding="utf-8"?>
<!--
  Ogneliss Mail: строки интерфейса. Язык: {name} ({code}).
  Формат — ресурсы строк Android (strings.xml). Ключи одни на все языки:
  assets/l10n/<код>.xml. Добавить или поправить строку —
  python3 tool/dev/l10n_set.py strings.json (tool/l10n/l10n.py).
-->
<resources>
'''


# ─────────────────────────── экранирование Android ───────────────────────────

def a_escape(s):
    quote = s != s.strip() or '  ' in s
    r = (s.replace('\\', '\\\\').replace('"', '\\"').replace("'", "\\'")
         .replace('\n', '\\n').replace('\t', '\\t'))
    r = r.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    if r.startswith('@') or r.startswith('?'):
        r = '\\' + r
    return f'"{r}"' if quote else r


def a_unescape(s):
    """Текст элемента (сущности XML уже раскрыты) → строка, как её видит
    Android: экранирование «\\», кавычки "…" сохраняют пробелы, вне кавычек
    пробелы и переводы строк схлопываются, края обрезаются."""
    out = []
    quoted = False
    i = 0
    n = len(s)
    lead = True
    while i < n:
        c = s[i]
        if c == '\\' and i + 1 < n:
            d = s[i + 1]
            if d == 'n':
                out.append('\n')
            elif d == 't':
                out.append('\t')
            elif d == 'u' and i + 5 < n:
                try:
                    out.append(chr(int(s[i + 2:i + 6], 16)))
                    i += 6
                    lead = False
                    continue
                except ValueError:
                    out.append(d)
            else:
                out.append(d)
            i += 2
            lead = False
            continue
        if c == '"':
            quoted = not quoted
            i += 1
            continue
        if not quoted and c in ' \t\r\n':
            if not lead and (not out or out[-1] != ' '):
                out.append(' ')
            i += 1
            continue
        out.append(c)
        lead = False
        i += 1
    # хвостовой пробел от схлопывания — убрать (кавычки сохраняют свои)
    text = ''.join(out)
    if not quoted and text.endswith(' ') and not s.rstrip().endswith('"'):
        text = text.rstrip(' ')
    return text


# ─────────────────────────── чтение и запись XML ───────────────────────────

def path_of(lang):
    return os.path.join(L10N, f'{lang}.xml')


def read_lang(lang):
    """→ (порядок ключей, {ключ: строка | {категория: строка}})"""
    p = path_of(lang)
    if not os.path.exists(p):
        return [], {}
    tree = ET.parse(p)
    order, vals = [], {}
    for el in tree.getroot():
        name = el.get('name')
        if not name:
            continue
        if el.tag == 'string':
            vals[name] = a_unescape(''.join(el.itertext()))
        elif el.tag == 'plurals':
            forms = {}
            for it in el:
                if it.tag == 'item' and it.get('quantity'):
                    forms[it.get('quantity')] = a_unescape(''.join(it.itertext()))
            vals[name] = forms
        else:
            continue
        if name not in order:
            order.append(name)
    return order, vals


def write_lang(lang, order, vals):
    os.makedirs(L10N, exist_ok=True)
    name = LANGS.get(lang, (lang, lang, []))[0]
    lines = [HEADER.format(name=name, code=lang)]
    seen = set()
    keys = ['language_name'] + [k for k in order if k != 'language_name']
    keys += [k for k in vals if k not in keys]
    for k in keys:
        if k in seen or k not in vals:
            continue
        seen.add(k)
        v = vals[k]
        if isinstance(v, dict):
            lines.append(f'    <plurals name="{k}">\n')
            cats = plural_cats(lang)
            for q in cats + [q for q in v if q not in cats]:
                if q in v:
                    lines.append(f'        <item quantity="{q}">{a_escape(v[q])}</item>\n')
            lines.append('    </plurals>\n')
        else:
            lines.append(f'    <string name="{k}">{a_escape(v)}</string>\n')
    lines.append('</resources>\n')
    with open(path_of(lang), 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(lines))


def all_langs():
    return sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(L10N, '*.xml')))


def plural_cats(lang):
    """Категории языка в файле: формы переводчика и «other»."""
    forms = LANGS.get(lang, (0, 0, ['one', 'other']))[2]
    return forms + ([] if 'other' in forms else ['other'])


def to_plural(lang, text):
    """«a|b|c» → {категория: форма} по порядку категорий языка."""
    cats = LANGS.get(lang, (0, 0, ['one', 'other']))[2]
    parts = text.split('|')
    forms = {}
    for i, part in enumerate(parts):
        if i < len(cats):
            forms[cats[i]] = part
    # «other» обязательна: у ru/uk/pl — как «many» (дробные числа).
    if 'other' not in forms:
        forms['other'] = parts[-1]
    return forms


def flat(v):
    """Строка для проверок: формы — через «|»."""
    if isinstance(v, dict):
        return '|'.join(v.values())
    return v


# ─────────────────────────── команды ───────────────────────────

def cmd_set(a):
    data = json.load(open(a.file, encoding='utf-8'))
    langs = {}
    master_order, _ = read_lang(MASTER)
    for k, per in data.items():
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', k):
            raise SystemExit(f'плохой ключ: {k}')
        for lang in CORE:
            if lang not in per:
                raise SystemExit(f'{k}: нет языка {lang}')
        for lang, text in per.items():
            if lang not in langs:
                langs[lang] = read_lang(lang)
            order, vals = langs[lang]
            vals[k] = to_plural(lang, text) if '|' in text else text
            if k not in order:
                order.append(k)
        if k not in master_order:
            master_order.append(k)
    for lang, (order, vals) in langs.items():
        write_lang(lang, master_order, vals)
    print(f'строк: {len(data)}, языков: {len(langs)}')


def cmd_remove(a):
    for lang in all_langs():
        order, vals = read_lang(lang)
        hit = [k for k in a.keys if k in vals]
        for k in hit:
            vals.pop(k, None)
        if hit:
            write_lang(lang, order, vals)
    print('удалено:', ', '.join(a.keys))


def cmd_check_code(a):
    _, en = read_lang(MASTER)
    used = {}
    for d, _, fs in os.walk(os.path.join(ROOT, 'lib')):
        for fn in fs:
            if not fn.endswith('.dart'):
                continue
            p = os.path.join(d, fn)
            s = open(p, encoding='utf-8').read()
            for m in re.finditer(r"\.(?:tr|plural)\(\s*'([A-Za-z0-9_]+)'", s):
                used.setdefault(m.group(1), set()).add(os.path.relpath(p, ROOT))
    missing = sorted(k for k in used if k not in en)
    print('строк', len(en), 'используется', len(used))
    for k in missing:
        print('MISSING', k, sorted(used[k]))
    sys.exit(1 if missing else 0)


def cmd_status(a):
    order, en = read_lang(MASTER)
    total = len(en)
    for lang in all_langs():
        _, vals = read_lang(lang)
        miss = [k for k in en if k not in vals]
        print(f'{lang}: {len(vals)}/{total}' + (f' (нет {len(miss)}: {", ".join(miss[:5])}…)' if miss else ''))


# ─────────────────────────── перевод ───────────────────────────

def cmd_export(a):
    order, en = read_lang(MASTER)
    _, ru = read_lang('ru')
    # Несколько языков (--lang es --lang pt …): выгружаются строки, которых нет
    # хотя бы у одного из них (одно задание на группу языков).
    langs = a.lang or []
    have = set.intersection(*(set(read_lang(l)[1]) for l in langs)) if langs else set()
    # Ключи, у которых английский текст изменился после перевода: выгружаются
    # заново и у языков, где перевод уже есть.
    also = set()
    if getattr(a, 'also', None):
        also = {x.split('#')[0].strip() for x in open(a.also, encoding='utf-8')} - {''}
    d = os.path.join(a.job, 'src')
    os.makedirs(d, exist_ok=True)
    for f in glob.glob(os.path.join(d, 'chunk_*.json')):
        os.remove(f)
    chunks, cur, size = [], [], 0
    n = 0
    for k in order:
        if k == 'language_name' or (k in have and k not in also):
            continue
        v = en[k]
        item = {'k': k, 'en': flat(v)}
        # Русский оригинал — подсказка смысла коротких строк (кнопки,
        # заголовки); у длинных хватает английского, а лишний текст —
        # лишняя работа переводчику.
        if a.ru_max <= 0 or len(item['en']) <= a.ru_max:
            item['ru'] = flat(ru.get(k, ''))
        if isinstance(v, dict):
            item['plural'] = True
        cur.append(item)
        n += 1
        size += len(item['en'])
        if size >= a.chunk:
            chunks.append(cur)
            cur, size = [], 0
    if cur:
        chunks.append(cur)
    for i, c in enumerate(chunks, 1):
        json.dump(c, open(os.path.join(d, f'chunk_{i:02d}.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'{n} строк, {len(chunks)} частей → {d}')


def load_src(job, chunk=None):
    items, order = {}, []
    pattern = f'chunk_{chunk:02d}.json' if chunk else 'chunk_*.json'
    for f in sorted(glob.glob(os.path.join(job, 'src', pattern))):
        for it in json.load(open(f, encoding='utf-8')):
            items[it['k']] = it
            order.append(it['k'])
    return items, order


def load_out(job, lang, chunk=None):
    out, bad = {}, []
    pattern = f'chunk_{chunk:02d}.json' if chunk else '*.json'
    for f in sorted(glob.glob(os.path.join(job, 'out', lang, pattern))):
        try:
            d = json.load(open(f, encoding='utf-8'))
        except Exception as e:  # noqa: BLE001
            bad.append(f'{os.path.basename(f)}: не JSON ({e})')
            continue
        if not isinstance(d, dict):
            bad.append(f'{os.path.basename(f)}: нужен объект {{ключ: перевод}}')
            continue
        out.update(d)
    return out, bad


def check(job, lang, chunk=None):
    if lang not in LANGS:
        return [f'неизвестный язык {lang}'], []
    cats = LANGS[lang][2]
    src, order = load_src(job, chunk)
    if chunk and not order:
        return [f'нет файла src/chunk_{chunk:02d}.json'], []
    out, errors = load_out(job, lang, chunk)
    warnings = []
    for k in order:
        it = src[k]
        en = it['en']
        tr = out.get(k)
        if k == 'language_name':
            continue
        if not isinstance(tr, str) or not tr.strip():
            errors.append(f'{k}: нет перевода')
            continue
        en_ph = set(PH.findall(en))
        if it.get('plural'):
            parts = tr.split('|')
            if len(parts) != len(cats):
                errors.append(f'{k}: форм {len(parts)}, нужно {len(cats)} ({"|".join(cats)})')
            if set(PH.findall(tr)) - en_ph:
                errors.append(f'{k}: лишние подстановки {sorted(set(PH.findall(tr)) - en_ph)}')
            if '{n}' in en and '{n}' not in parts[-1]:
                errors.append(f'{k}: в последней форме ({cats[-1]}) нет {{n}}')
        else:
            if '|' in tr and '|' not in en:
                errors.append(f'{k}: «|» в обычной строке')
            if sorted(en_ph) != sorted(set(PH.findall(tr))):
                errors.append(f'{k}: подстановки {sorted(set(PH.findall(tr)))}, нужно {sorted(en_ph)}')
        if '\n' in en and '\n' not in tr:
            warnings.append(f'{k}: в оригинале перенос строки')
        if lang not in CYRILLIC and re.search('[А-Яа-яЁё]', tr) and not re.search('[А-Яа-яЁё]', en):
            errors.append(f'{k}: кириллица в переводе')
        if len(en) > 24 and tr.strip() == en.strip() and re.search('[A-Za-z]{4}', en):
            warnings.append(f'{k}: не переведено (как в оригинале)')
    extra = set(out) - set(src)
    if extra:
        warnings.append(f'лишние ключи: {len(extra)} (пример: {sorted(extra)[:3]})')
    return errors, warnings


def cmd_check(a):
    errors, warnings = check(a.job, a.lang, a.chunk)
    for w in warnings[:80]:
        print('предупреждение:', w)
    for e in errors[:300]:
        print('ОШИБКА:', e)
    print(f'{a.lang}: ошибок {len(errors)}, предупреждений {len(warnings)}')
    sys.exit(1 if errors else 0)


def cmd_build(a):
    src, order = load_src(a.job)
    _, en_now = read_lang(MASTER)
    for lang in a.lang:
        errors, _ = check(a.job, lang)
        if a.partial:
            # Частичный перевод (1.8.0): непереведённые строки остаются
            # английскими (запасной язык), остальные ошибки — как обычно.
            errors = [e for e in errors if not e.endswith(': нет перевода')]
        if errors:
            print(f'{lang}: ошибок {len(errors)} — не собираю')
            for e in errors[:20]:
                print('  ', e)
            continue
        out, _ = load_out(a.job, lang)
        lorder, vals = read_lang(lang)
        vals['language_name'] = LANGS[lang][0]
        stale = 0
        for k in order:
            if k not in out or k not in en_now:
                continue
            # Английский текст изменился после выгрузки — перевод устарел.
            if flat(en_now[k]) != src[k]['en']:
                stale += 1
                continue
            vals[k] = to_plural(lang, out[k]) if src[k].get('plural') else out[k]
        master, _ = read_lang(MASTER)
        write_lang(lang, master, vals)
        print(f'{lang}: {len(vals)} из {len(master)} строк → assets/l10n/{lang}.xml'
              + (f' (устаревших пропущено: {stale})' if stale else ''))


# ─────────────────────────── список языков ───────────────────────────

def cmd_gen(a):
    langs = all_langs()
    core = [c for c in CORE if c in langs]
    rest = sorted((c for c in langs if c not in CORE), key=lambda c: LANGS.get(c, (c, c))[1])
    out = ['// lib/l10n/languages.g.dart',
           '// Создано tool/l10n/l10n.py gen по файлам assets/l10n/*.xml — не править',
           '// вручную: добавили язык (файл) — запустите gen.',
           '',
           "import 'strings_store.dart' show AppLanguage;",
           '',
           'const kAppLanguages = <AppLanguage>[']
    for c in core + rest:
        _, vals = read_lang(c)
        name = vals.get('language_name') or LANGS.get(c, (c,))[0]
        eng = LANGS.get(c, (c, c))[1]
        cats = plural_cats(c)
        def q(x):
            return "'" + x.replace('\\', '\\\\').replace("'", "\\'") + "'"
        args = [q(c), q(name), q(eng)]
        if c in RTL:
            args.append('rtl: true')
        if c not in CORE:
            args.append('machine: true')
        if cats != ['one', 'other']:
            args.append('plural: [' + ', '.join(q(x) for x in cats) + ']')
        out.append(f"  AppLanguage({', '.join(args)}),")
    out.append('];')
    open(os.path.join(ROOT, 'lib/l10n/languages.g.dart'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')

    # Android 13+: «Язык приложения» в настройках системы.
    tag = {'zh': 'zh-CN'}
    lc = ['<?xml version="1.0" encoding="utf-8"?>',
          '<!-- Языки приложения для системной настройки «Язык приложения» (Android 13+).',
          '     Создано tool/l10n/l10n.py gen по assets/l10n/*.xml. -->',
          '<locale-config xmlns:android="http://schemas.android.com/apk/res/android">']
    for c in core + rest:
        lc.append(f'    <locale android:name="{tag.get(c, c)}"/>')
    lc.append('</locale-config>')
    open(os.path.join(ROOT, 'android/app/src/main/res/xml/locales_config.xml'), 'w', encoding='utf-8').write('\n'.join(lc) + '\n')

    # iPhone: языки приложения (CFBundleLocalizations).
    plist = os.path.join(ROOT, 'ios/Runner/Info.plist')
    if os.path.exists(plist):
        s = open(plist, encoding='utf-8').read()
        itag = {'zh': 'zh-Hans'}
        arr = '\n'.join(f'\t\t<string>{itag.get(c, c)}</string>' for c in ['en'] + [c for c in core + rest if c != 'en'])
        s2 = re.sub(r'(<key>CFBundleLocalizations</key>\s*<array>)[\s\S]*?(\s*</array>)',
                    lambda m: m.group(1) + '\n' + arr + m.group(2), s, count=1)
        if s2 != s:
            open(plist, 'w', encoding='utf-8').write(s2)
    gen_platform_strings(core + rest)
    print('языков:', len(core + rest), ', '.join(core + rest))


# ─────────────────────────── строки вне приложения ───────────────────────────
#
# 1.8.0: тексты, которые показывает система, а не приложение, — тоже в
# assets/l10n/<код>.xml, и gen раскладывает их по файлам платформ:
#   android_<имя>  → android/app/src/main/res/values-<q>/strings.xml
#                    (виджеты, уведомление фоновой работы, администратор
#                    устройства); en — values/strings.xml (строки
#                    translatable="false" там сохраняются);
#   ios_<ключ>     → ios/Runner/<l>.lproj/InfoPlist.strings (название и
#                    запросы разрешений);
#   ioswidget_<ключ> → ios/OgnelissWidgets/<l>.lproj/Localizable.strings.
# Нет перевода — английский текст (Android берёт его сам из values/).
# Новые папки .lproj Xcode должен знать: scripts/ios_localizations.py
# (вызывает build_ios.sh) дописывает их в project.pbxproj.

ANDROID_Q = {'he': 'iw', 'id': 'in', 'zh': 'zh-rCN'}
IOS_LPROJ = {'zh': 'zh-Hans'}


def ios_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


def gen_platform_strings(langs):
    order, en = read_lang(MASTER)
    a_keys = [k for k in order if k.startswith('android_')]
    i_keys = [k for k in order if k.startswith('ios_')]
    w_keys = [k for k in order if k.startswith('ioswidget_')]
    res = os.path.join(ROOT, 'android/app/src/main/res')
    written = []
    for lang in langs:
        _, vals = read_lang(lang)
        # Android: только переведённое — остальное Android берёт из values/.
        if a_keys:
            if lang == MASTER:
                path = os.path.join(res, 'values', 'strings.xml')
                keep = []
                if os.path.exists(path):
                    for el in ET.parse(path).getroot():
                        if el.tag == 'string' and el.get('translatable') == 'false':
                            keep.append(f'    <string name="{el.get("name")}" translatable="false">'
                                        f'{a_escape(a_unescape("".join(el.itertext())))}</string>')
                have = [k for k in a_keys if isinstance(en.get(k), str)]
            else:
                path = os.path.join(res, f'values-{ANDROID_Q.get(lang, lang)}', 'strings.xml')
                keep = []
                have = [k for k in a_keys if isinstance(vals.get(k), str)]
            if have:
                lines = ['<?xml version="1.0" encoding="utf-8"?>',
                         '<!-- Создано tool/l10n/l10n.py gen из assets/l10n/' + lang + '.xml (ключи android_*) — не править вручную. -->',
                         '<resources>']
                src = en if lang == MASTER else vals
                for k in have:
                    lines.append(f'    <string name="{k[len("android_"):]}">{a_escape(src[k])}</string>')
                lines += keep
                lines.append('</resources>')
                os.makedirs(os.path.dirname(path), exist_ok=True)
                open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
                written.append(os.path.relpath(path, ROOT))
        # iPhone: файл на каждый язык приложения, недостающее — по-английски.
        lp = IOS_LPROJ.get(lang, lang)
        for keys, pre, rel, title in (
                (i_keys, 'ios_', f'ios/Runner/{lp}.lproj/InfoPlist.strings', 'Тексты Info.plist (название и запросы разрешений).'),
                (w_keys, 'ioswidget_', f'ios/OgnelissWidgets/{lp}.lproj/Localizable.strings', 'Виджеты Ogneliss Mail')):
            if not keys:
                continue
            out = [f'/* {title} Создано tool/l10n/l10n.py gen из assets/l10n/{lang}.xml — не править вручную. */']
            for k in keys:
                v = vals.get(k) if isinstance(vals.get(k), str) else en.get(k)
                if not isinstance(v, str):
                    continue
                out.append(f'"{k[len(pre):]}" = "{ios_escape(v)}";')
            path = os.path.join(ROOT, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
            written.append(rel)
    print('файлы платформ:', len(written))


# ─────────────────────────── миграция (разово) ───────────────────────────

STR = r"'((?:[^'\\]|\\.)*)'"


def dart_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            if n == 'n':
                out.append('\n'); i += 2; continue
            if n == 't':
                out.append('\t'); i += 2; continue
            if n == 'u':
                if s[i + 2:i + 3] == '{':
                    j = s.index('}', i + 3)
                    out.append(chr(int(s[i + 3:j], 16))); i = j + 1; continue
                out.append(chr(int(s[i + 2:i + 6], 16))); i += 6; continue
            out.append(n); i += 2; continue
        out.append(c); i += 1
    return ''.join(out)


def parse_dart_map_line(body):
    langs = {}
    for lm in re.finditer(r"'([a-z]{2})':\s*" + STR, body):
        langs[lm.group(1)] = dart_unescape(lm.group(2))
    return langs


def parse_dart_strings(path):
    src = open(path, encoding='utf-8').read()
    out = {}
    order = []
    for m in re.finditer(r"^\s*'([A-Za-z0-9_]+)'\s*:\s*\{(.*)\},\s*$", src, re.M):
        out[m.group(1)] = parse_dart_map_line(m.group(2))
        order.append(m.group(1))
    return order, out


def parse_map_at(text, pos):
    m = {}
    pat = re.compile(r"\s*'([a-z]{2})'\s*:\s*" + STR + r"\s*,?", re.S)
    while True:
        mm = pat.match(text, pos)
        if not mm:
            break
        m[mm.group(1)] = dart_unescape(mm.group(2))
        pos = mm.end()
    return m, text.index('}', pos) + 1


def faq_entries():
    t = open(os.path.join(ROOT, 'lib/features/help/faq_content.dart'), encoding='utf-8').read()
    out = []
    sec, idx = None, 0
    for m in re.finditer(r"FaqSection\(id:\s*'([a-z0-9_]+)'|FaqItem\(q:\s*\{", t):
        if m.group(1):
            sec, idx = m.group(1), 0
            tm = re.compile(r"title:\s*\{").search(t, m.end())
            title, _ = parse_map_at(t, tm.end())
            out.append((f'faq_{sec}_title', title))
        else:
            idx += 1
            q, pos = parse_map_at(t, m.end())
            am = re.compile(r"\s*,\s*a:\s*\{").match(t, pos)
            a, _ = parse_map_at(t, am.end())
            out.append((f'faq_{sec}_{idx}_q', q))
            out.append((f'faq_{sec}_{idx}_a', a))
    return out


def ios_entries():
    out = {}
    for lang in CORE:
        p = os.path.join(ROOT, f'ios/Runner/{lang}.lproj/InfoPlist.strings')
        if not os.path.exists(p):
            continue
        for m in re.finditer(r'^"([A-Za-z0-9_]+)"\s*=\s*"((?:[^"\\]|\\.)*)";', open(p, encoding='utf-8').read(), re.M):
            out.setdefault('ios_' + m.group(1), {})[lang] = m.group(2).replace('\\"', '"').replace('\\n', '\n')
    return list(out.items())


def cmd_migrate(a):
    order, main = parse_dart_strings(os.path.join(ROOT, 'lib/l10n/app_strings.dart'))
    _, defr = parse_dart_strings(os.path.join(ROOT, 'lib/l10n/app_strings_de_fr.dart'))
    entries = [(k, {**main[k], **{l: v for l, v in defr.get(k, {}).items() if l not in main[k]}}) for k in order]
    entries += faq_entries() + ios_entries()
    keys = [k for k, _ in entries]
    for lang in CORE:
        vals = {'language_name': LANGS[lang][0]}
        for k, per in entries:
            if lang not in per:
                continue
            text = per[lang]
            plural = '|' in per.get('en', '')
            vals[k] = to_plural(lang, text) if plural else text
        write_lang(lang, ['language_name'] + keys, vals)
        print(lang, len(vals))


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('set'); s.add_argument('file')
    r = sub.add_parser('remove'); r.add_argument('keys', nargs='+')
    sub.add_parser('check-code')
    sub.add_parser('status')
    e = sub.add_parser('export'); e.add_argument('--job', required=True); e.add_argument('--lang', action='append'); e.add_argument('--chunk', type=int, default=7000)
    e.add_argument('--ru-max', type=int, default=0, help='русский оригинал — только у строк до N знаков (0 — у всех)')
    e.add_argument('--also', help='файл со списком ключей, которые выгрузить заново, даже если перевод есть '
                   '(английский текст изменился после перевода), например tool/l10n/retranslate.txt')
    c = sub.add_parser('check'); c.add_argument('--job', required=True); c.add_argument('--lang', required=True)
    c.add_argument('--chunk', type=int, help='проверить один кусок (номер N из src/chunk_NN.json)')
    b = sub.add_parser('build'); b.add_argument('--job', required=True); b.add_argument('--lang', action='append', required=True)
    b.add_argument('--partial', action='store_true', help='собрать и неполный перевод (недостающие строки — по-английски)')
    sub.add_parser('gen')
    sub.add_parser('migrate')
    a = p.parse_args()
    {
        'set': cmd_set, 'remove': cmd_remove, 'check-code': cmd_check_code, 'status': cmd_status,
        'export': cmd_export, 'check': cmd_check, 'build': cmd_build, 'gen': cmd_gen, 'migrate': cmd_migrate,
    }[a.cmd](a)


if __name__ == '__main__':
    main()
