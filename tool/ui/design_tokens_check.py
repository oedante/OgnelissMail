#!/usr/bin/env python3
"""
СВЕРКА ДИЗАЙН-ТОКЕНОВ OGNELISS (Dialer и Mail).

Один и тот же файл лежит в обоих репозиториях:
  Ogneliss Dialer — scripts/design_tokens_check.py
  Ogneliss Mail   — tool/ui/design_tokens_check.py

Источник правды — блок ```tokens в docs/OGNELISS_DESIGN_SYSTEM.md (тот же
документ в обоих репозиториях). Скрипт сам понимает, в каком приложении
запущен, читает значения из кода и сравнивает с документом. Расхождение —
код ≠ документ — замечание и код выхода 1.

  python3 scripts/design_tokens_check.py            # своё приложение
  python3 scripts/design_tokens_check.py --other ../OgnelissMail
                                                     # и второе рядом

Ключ документа с пометкой «# пока различается» — известное расхождение
из таблицы плана: о нём пишется, но выход не портится.
Только стандартная библиотека Python.
"""
import argparse
import re
import sys
from pathlib import Path


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8") if p.exists() else ""


def doc_tokens(root: Path):
    text = read(root / "docs" / "OGNELISS_DESIGN_SYSTEM.md")
    m = re.search(r"```tokens\n(.*?)```", text, re.S)
    if not m:
        sys.exit(f"{root}: нет блока ```tokens в docs/OGNELISS_DESIGN_SYSTEM.md")
    tokens, known = {}, set()
    for line in m.group(1).splitlines():
        # Комментарий — «# » с пробелом: у цвета после «#» идут цифры (#1D4F91)
        body = re.split(r"#\s", line, maxsplit=1)
        kv = body[0].strip()
        if not kv:
            continue
        k, v = (x.strip() for x in kv.split("=", 1))
        tokens[k] = v
        if len(body) > 1 and "пока различается" in body[1]:
            known.add(k)
    return tokens, known


def hexes(text: str):
    return [h.upper() for h in re.findall(r"0x(FF[0-9A-Fa-f]{6})", text)]


def dialer(root: Path) -> dict:
    t = root / "app/src/main/java/com/ogneliss/dialer/ui/theme"
    out = {}
    space = read(t / "Space.kt")
    for name, val in re.findall(r"val (xxs|xs|s|m|l|xl|xxl) = (\d+)\.dp", space):
        out[f"space.{name}"] = val
    shape = read(t / "Shape.kt")
    if m := re.search(r"CARD_RADIUS = (\d+)\.dp", shape):
        out["radius.card"] = m.group(1)
    if m := re.search(r"bottomPanel = RoundedCornerShape\((\d+)\.dp\)", shape):
        out["radius.bottomPanel"] = m.group(1)
    if m := re.search(r"MAX_SHEET_RADIUS = (\d+)\.dp", shape):
        out["radius.sheetMax"] = m.group(1)
    look = read(t / "LocalAppearance.kt")
    for name, val in re.findall(r"ListDensity\.(COMPACT|NORMAL|COMFORTABLE) -> (\d+)\.dp", look):
        key = "avatar" if int(val) >= 30 else "rowPadding"
        out[f"density.{name.lower()}.{key}"] = val
    dimens = read(t / "Dimens.kt")
    if m := re.search(r"val avatarSize = (\d+)\.dp", dimens):
        out["density.normal.avatar"] = m.group(1)
    math = read(t / "ThemePresetMath.kt")
    for name, hue, sat, acc in re.findall(r'"(\w+)" to Spec\(([\d.]+), ([\d.]+), 0x(FF[0-9A-Fa-f]{6})', math):
        out[f"preset.{name.lower()}"] = f"{float(hue):g} {float(sat):g} #{acc[2:].upper()}"
    if m := re.search(r"ACCENTS: IntArray = intArrayOf\((.*?)\n\s*\)", math, re.S):
        out["accents"] = " ".join("#" + h[2:] for h in hexes(m.group(1)))
    return out


def mail(root: Path) -> dict:
    t = root / "lib/core/theme"
    out = {}
    tokens = read(t / "tokens.dart")
    sp = tokens.split("abstract final class Radii")[0]
    for name, val in re.findall(r"static const (xxs|xs|s|m|l|xl|xxl) = ([\d.]+);", sp):
        out[f"space.{name}"] = f"{float(val):g}"
    if m := re.search(r"static const card = ([\d.]+);", tokens):
        out["radius.card"] = f"{float(m.group(1)):g}"
    if m := re.search(r"clamp\(0\.0, ([\d.]+)\)", tokens):
        out["radius.sheetMax"] = f"{float(m.group(1)):g}"
    out["radius.bottomPanel"] = "0"  # панель плоская: линия сверху (app_bottom_bar.dart)
    app = read(t / "appearance.dart")
    for name, pad, rad in re.findall(r"static const (compact|normal|comfortable) = DensitySpec\(padV: (\d+), avatarRadius: (\d+)", app):
        out[f"density.{name}.rowPadding"] = pad
        out[f"density.{name}.avatar"] = str(int(rad) * 2)
    for name, hue, sat, acc in re.findall(r"ThemePreset\.(\w+): PresetSpec\(([\d.]+), ([\d.]+), Color\(0x(FF[0-9A-Fa-f]{6})\)", app):
        out[f"preset.{name}"] = f"{float(hue):g} {float(sat):g} #{acc[2:].upper()}"
    if m := re.search(r"(?:accentSwatches|accents)\s*=\s*(?:<Color>)?\[(.*?)\];", app, re.S):
        out["accents"] = " ".join("#" + h[2:] for h in hexes(m.group(1)))
    return out


def detect(root: Path):
    if (root / "app/src/main/java/com/ogneliss/dialer").exists():
        return "Ogneliss Dialer", dialer(root)
    if (root / "lib/core/theme/tokens.dart").exists():
        return "Ogneliss Mail", mail(root)
    sys.exit(f"{root}: не похоже ни на Dialer, ни на Mail")


def check(root: Path) -> int:
    name, code = detect(root)
    tokens, known = doc_tokens(root)
    problems, notes = [], []
    for key, want in tokens.items():
        if key.startswith("dialer.") and name != "Ogneliss Dialer":
            continue
        if key.startswith("mail.") and name != "Ogneliss Mail":
            continue
        have = code.get(key)
        if have is None:
            continue  # значение вне кода (поведение) — проверяется глазами
        if have != want:
            (notes if key in known else problems).append(f"{key}: документ «{want}», код «{have}»")
    print(f"== {name} ({root}) — токенов в коде найдено: {len(code)}")
    for n in notes:
        print("   известное расхождение:", n)
    for p in problems:
        print("   РАСХОЖДЕНИЕ:", p)
    if not problems:
        print("   код совпадает с документом")
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--other", help="путь ко второму репозиторию (Dialer или Mail)")
    a = ap.parse_args()
    here = Path(__file__).resolve()
    root = next(p for p in here.parents if (p / "docs").is_dir())
    rc = check(root)
    if a.other:
        rc |= check(Path(a.other).resolve())
        da, _ = doc_tokens(root)
        db, _ = doc_tokens(Path(a.other).resolve())
        if da != db:
            print("РАСХОЖДЕНИЕ: блоки tokens в документах двух репозиториев различаются — документ должен быть один")
            rc = 1
    sys.exit(rc)


if __name__ == "__main__":
    main()
