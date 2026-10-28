#!/usr/bin/env python3
"""Повторяемые проверки «написано, но не подключено».

Ловит классы багов, которые компилятор и `flutter analyze` НЕ видят, потому что
код синтаксически корректен — просто верхний слой (вызов) не доведён. Каждая
проверка выросла из реальной находки в проекте ogneliss.

Запуск:  python3 scripts/audit_checks.py
Выход:   0 — чисто; 1 — есть подозрения (для CI).

Дополняет scripts/find_unwired.py (несвязанные методы).
"""
import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"


def dart_files():
    return [p for p in LIB.rglob("*.dart") if not p.name.endswith(".g.dart")]


def read_all(exclude=()):
    out = {}
    for p in dart_files():
        if any(e in str(p) for e in exclude):
            continue
        out[p] = p.read_text(encoding="utf-8", errors="ignore")
    return out


# ── 1. MethodChannel в Dart без нативного обработчика ────────────────────────
def check_method_channels():
    problems = []
    dart = read_all()
    channels = set()
    for t in dart.values():
        channels |= set(re.findall(r"MethodChannel\(\s*'([^']+)'", t))
    native_blob = ""
    for ext in ("*.kt", "*.java", "*.swift"):
        for p in (ROOT / "android").rglob(ext):
            native_blob += p.read_text(encoding="utf-8", errors="ignore")
        for p in (ROOT / "ios").rglob(ext):
            native_blob += p.read_text(encoding="utf-8", errors="ignore")
    for ch in sorted(channels):
        if ch not in native_blob:
            problems.append(f"канал '{ch}' — нет нативного обработчика (Android/iOS)")
    return problems


# ── 2. Поля настроек, которые пишутся, но не читаются ────────────────────────
def check_dead_settings():
    problems = []
    sp = (LIB / "features/settings/providers/settings_provider.dart").read_text(
        encoding="utf-8", errors="ignore")
    fields = re.findall(r"final\s+\w+\s+(\w+);", sp)
    # карта поле → ключ prefs (static const field = 's_xxx';)
    keymap = dict(re.findall(r"static const\s+(\w+)\s*=\s*'([^']+)'", sp))
    blob = "\n".join(
        t for p, t in read_all().items()
        if "settings_provider.dart" not in str(p)
        and "/settings/screens/" not in str(p)
    )
    for f in fields:
        if len(f) < 3:
            continue
        # чтение через поле (settings.field) ИЛИ через ключ prefs (getBool('s_xxx'))
        read_field = re.search(r"\." + re.escape(f) + r"\b", blob)
        key = keymap.get(f)
        read_key = key and (f"'{key}'" in blob)
        if not read_field and not read_key:
            problems.append(f"настройка '{f}' пишется, но нигде не читается (мёртвый тумблер?)")
    return problems


# ── 3. Ключи локализации, которые используются, но не определены ─────────────
def check_l10n():
    problems = []
    # Строки интерфейса (1.7.3) — файлы assets/l10n/<код>.xml; главный —
    # английский.
    en = (LIB.parent / "assets/l10n/en.xml").read_text(encoding="utf-8", errors="ignore")
    defined = set(re.findall(r'<(?:string|plurals)\s+name="([^"]+)"', en))
    used = set()
    for t in read_all().values():
        used |= set(re.findall(r"\.tr\(\s*'([a-zA-Z0-9_]+)'", t))
    for k in sorted(used - defined):
        problems.append(f"l10n-ключ '{k}' используется в tr(), но не определён")
    return problems


# ── 4. Навигация на незарегистрированные маршруты ────────────────────────────
def check_routes():
    problems = []
    router = ""
    for p in LIB.rglob("*router*.dart"):
        router += p.read_text(encoding="utf-8", errors="ignore")
    defined = set(re.findall(r"path:\s*'(/[^']*)'", router))
    nested = set(re.findall(r"path:\s*'([^/'][^']*)'", router))  # вложенные без ведущего /
    patterns = []
    for d in defined | {"/" + n for n in nested}:
        patterns.append(re.compile("^" + re.sub(r":[^/]+", r"[^/]+", d) + "$"))

    def known(path):
        base = path.split("?")[0].rstrip("/") or "/"
        if any(p.match(base) for p in patterns):
            return True
        # интерполяция: путь вида '/mail/detail/' (дальше шёл ${id}) — считаем
        # известным, если есть маршрут, начинающийся с этого базового пути.
        all_paths = defined | {"/" + n for n in nested}
        # соберём полные вложенные пути: parent + child
        for d in all_paths:
            if d.startswith(base + "/") or d == base:
                return True
        # последний сегмент совпадает с вложенным путём
        for n in nested:
            if base.endswith("/" + n.split("/")[0]):
                return True
        return False

    for t in read_all().values():
        for path in re.findall(r"context\.(?:push|go|replace|pushReplacement)\(\s*'(/[^'$]*)", t):
            if not known(path):
                problems.append(f"навигация на '{path}' — маршрут не найден в роутере")
    return sorted(set(problems))


# ── 5. Провайдеры без единого read/watch/listen (с учётом алиасов) ───────────
def check_dead_providers():
    problems = []
    texts = read_all()
    blob = "\n".join(texts.values())
    # Известные безвредные сироты: функциональность покрыта другим (подключённым)
    # путём — разобрано в ROADMAP («Разбор 8 мёртвых провайдеров»). Кандидаты на
    # удаление ради чистоты, но НЕ пробелы. Держим в allowlist, чтобы аудит
    # сигналил только про НОВЫЕ мёртвые провайдеры.
    known_orphans = {
        'signatureServiceProvider',    # подписи → signaturesProvider
        'transportCapabilitiesProvider',  # → статический forAccount()
        'prefetchProvider',            # пагинация уже в списке; тело — при открытии
        'davContactsProvider',         # DAV идёт через sync_service → БД
        'davEventsProvider',           # то же
        'conversationProvider',        # threading-задел, не в UI
        'folderEmailCountProvider',    # счётчики берутся из модели папки/БД
        'selectedEmailProvider',       # split-view задел, не в UI
    }
    providers = set()
    for t in texts.values():
        providers |= set(re.findall(r"final\s+(\w+Provider)\s*=", t))
    # алиасы: final xProvider = yProvider;  → y считается использованным
    aliased = set(re.findall(r"final\s+\w+Provider\s*=\s*(\w+Provider)\s*;", blob))
    for pr in sorted(providers):
        if pr in aliased or pr in known_orphans:
            continue
        used = re.search(
            r"(?:read|watch|listen|invalidate|refresh)\(\s*" + re.escape(pr) + r"\b", blob)
        if not used:
            problems.append(f"провайдер '{pr}' нигде не read/watch (мёртвый или дубль-сирота?)")
    return problems


# ── 6. Dart-специфичные грабли regex (компилируются, но работают неверно) ─────
def check_dart_regex_pitfalls():
    import re as _re
    problems = []
    for p, t in read_all().items():
        for i, line in enumerate(t.splitlines(), 1):
            # replaceAll(RegExp(...), r'$1') — $N в Dart это ЛИТЕРАЛ, не backreference
            if 'replaceAll(' in line and 'replaceAllMapped' not in line:
                if _re.search(r"replaceAll\(\s*RegExp[^,]*,\s*r?['\"]\$\d", line):
                    problems.append(f"{p}:{i} replaceAll с $N — в Dart это литерал (нужен replaceAllMapped)")
            # \b рядом с кириллицей — ASCII-\b её не матчит. Флагаем только когда
            # СРАЗУ за \b (с учётом '(' и '(?:') идёт кириллица — \b(\d/\w валиден.
            if 'RegExp' in line and '\\b' in line and _re.search(r'[а-яёА-ЯЁ]', line):
                if _re.search(r'\\b\(?(?:\?:)?[а-яёА-ЯЁ]|[а-яёА-ЯЁ]\)?\\b', line):
                    problems.append(f"{p}:{i} \\b рядом с кириллицей — ASCII-\\b не сработает (нужен lookaround)")
    return problems


def main():
    checks = [
        ("MethodChannel без нативной части", check_method_channels),
        ("Мёртвые настройки (пишутся, не читаются)", check_dead_settings),
        ("Отсутствующие ключи локализации", check_l10n),
        ("Навигация на несуществующие маршруты", check_routes),
        ("Мёртвые провайдеры (без read/watch)", check_dead_providers),
        ("Dart-грабли regex ($N-литерал, ASCII-\\b по кириллице)", check_dart_regex_pitfalls),
    ]
    total = 0
    for title, fn in checks:
        try:
            problems = fn()
        except Exception as e:  # noqa: BLE001
            print(f"[!] {title}: проверка упала: {e}")
            continue
        mark = "OK" if not problems else f"{len(problems)} ⚠"
        print(f"\n=== {title}: {mark} ===")
        for p in problems:
            print(f"  • {p}")
        total += len(problems)
    print(f"\nИтого подозрений: {total}")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
