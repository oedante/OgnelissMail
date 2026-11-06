# Round 2 (after 1.12.0) — rules shared by U2, T2, D2, O4, S2

Owner's decision (04.11.2026): "Все принимается, делаем" — notice chips instead of banners, better translation offer, Outlook-style tablet/desktop, old .doc/.xls/.ppt, search in attachment text. Read [common.md](common.md) and [o_common.md](o_common.md) first; this file overrides them where they differ.

## Setup
- You are in an isolated git worktree based on branch `claude/next` (= `main` after 1.12.0 + these briefs). Check `git log --oneline -3` shows "Round 2 briefs"; if not, `git merge claude/next`.
- `export PATH=/opt/flutter/bin:$PATH`; `flutter pub get`; `dart run build_runner build --delete-conflicting-outputs`; `git checkout analysis_options.yaml` after every flutter command.
- Four or five agents work in parallel on 4 CPUs. Run `flutter analyze lib test` and YOUR tests; do not run the whole suite (the lead does after merging).

## Strings (important — avoids 27-file merge conflicts)
- Do NOT commit changes to `assets/l10n/*.xml`. Put every new string into `tool/l10n/pending/<task>.json` (your task id, e.g. `u2.json`) in the `tool/l10n/l10n.py set` format: `{"key": {"ru": …, "en": …, "de": …, … all 27 languages}}`. Real translations: ru and en carefully, the rest natural and short (see existing keys for tone; Russian UI style — short, no "Пожалуйста").
- To run your tests locally, apply it: `python3 tool/l10n/l10n.py set tool/l10n/pending/<task>.json`, then before committing `git checkout assets/l10n` so only the JSON is committed. The lead applies all pending files after merging.
- Reuse existing keys where they fit (grep `assets/l10n/ru.xml`).

## Scope and conflicts
- Stay inside your task's files; the other tasks are listed below. If you must touch another task's file, keep the change minimal and mention it in the report.
  - U2 — message screen notices: `mail_detail_screen.dart` (the notices/banners block), banner widgets in `lib/features/mail/widgets/`, `MailTranslateStrip` (presentation only).
  - T2 — translation logic: `lib/services/translation/*`, `MailTranslationController` in `mail_translation.dart` (not the strip widget), translation settings section, native detect (Kotlin `TranslationBridge.kt`, `ios/Runner/AppDelegate.swift` TranslationBridge, `tool/desktop/macos/MainFlutterWindow.swift`).
  - D2 — tablet/desktop: mail list selection, reading pane position, attachment preview inside the reading pane (`openAttachment` in `attachment_preview_screen.dart`, `pane_navigator.dart`, `adaptive_layout.dart`, mail list screen/tile).
  - O4 — old Office formats: new readers in `lib/services/documents/`, `office_reader.dart`, `office_document.dart`, the legacy branch of `opensInApp`.
  - S2 — search in attachment text: extraction + FTS indexing.
- No new dependencies (pub, native, fonts) without stopping and reporting first (owner's licence rule in CLAUDE.md). Do not edit `docs/*` (the lead updates HANDOFF, LICENSING, FAQ, store notes). Do not change the version, `project.pbxproj`, entitlements.
- Database schema stays at version 27 unless your brief says otherwise.

## Code, tests, commits
- Comments in Russian, explain why, cite "(1.12.x, просьба владельца 04.11.2026)"; match neighbouring style; `dart format -l 120` only your new files.
- UI: reuse app components and tokens (`lib/widgets/ui/*`, `Space`, `AppIcons`, `BannerButton`, `showChoiceSheet`/`AppMenuButton`, ActionChip style of the message tags row). Phone, tablet and desktop must all work; light and dark theme; large font (text scale up to 2.0) must not overflow. For a visual self-check render to PNG in a widget test with Roboto loaded (`assets/fonts/pdf/Roboto-Regular.ttf`) and look at it; keep PNGs in your scratch dir.
- Commit in your worktree branch; every message ends with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01AU5HURx9BTVeVhTjPMppag
  Commit early and often (rate limits can stop you mid-task; uncommitted work is at risk). Do not push or merge.
- Final report (English): what and how, files, tests and results, pending l10n file, limitations, anything the owner must do, branch and final commit hash.
