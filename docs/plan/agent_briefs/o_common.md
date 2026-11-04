# Office document preview (O1–O3) — rules shared by the three tasks

Owner's plan (04.11.2026), Ogneliss Mail 1.11.x: preview office attachments inside the app — DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, CSV. Read [common.md](common.md) first; this file adds to it and overrides it where they differ.

## What already exists (branch `claude/office-preview`, commit "Office preview groundwork")
- `lib/services/documents/office_package.dart` — `OfficeZip` (safe ZIP reader: limits on what is really inflated, `read`, `readHead` for the beginning of a huge part, `readText`, `readXml`, `rels(part)`, `officeDocumentPart()`, `odfMimeType`, `odfEncrypted`, `image(name)` within image budgets), `OfficeLimits`, `OfficeDocException`/`OfficeDocError`, `OfficeRel`, `OfficeImage` (sniffed PNG/JPEG/GIF/WebP/BMP only), extension `OfficeXml` on `XmlElement` (`local`, `attr(local, ns:)`, `kids`, `kid`, `descendant`) — match elements and attributes by LOCAL name, so Transitional and Strict OOXML both work.
- `lib/services/documents/office_document.dart` — `OfficeFormat`, abstract `OfficeDoc` (`truncated`), `OfficeTextDoc` (html + images cid→data URI + truncated), `OfficeFormats.of(fileName, mimeType:)`.
- Strings already in all 27 `assets/l10n/*.xml`: `docProtected`, `docLegacyFormat`, `docTooLarge`, `docTruncated`, `docEmpty`, `docSheetTruncated`, `docSheetEmpty`, `docSlideOf` ("Слайд {n} из {total}"). Plus older ones such as `fileDamaged`.
- First: check that `git log --oneline -5` in your worktree shows "Office preview groundwork". If not, run `git merge --ff-only claude/office-preview` (or `git merge claude/office-preview`).

## Scope rules (three agents work in parallel)
- Create only NEW files in your area. Do NOT edit: `office_package.dart`, `office_document.dart`, `assets/l10n/*`, `pubspec.yaml`/`pubspec.lock`, `attachment_preview_screen.dart`, `file_opener.dart`, `attachment_safety.dart`, `docs/*`. The lead integrates the screen, the dispatcher, iOS rules and docs. If you need something in a shared file or a new string, say so in your report (or keep the UI language-neutral).
- No new dependencies (pub, native, fonts). Allowed: Dart/Flutter SDK, packages already in pubspec (`xml`, `archive`, `enough_convert` for Windows code pages, `html`, `intl`, `collection`, `crypto`, …).
- Readers (`lib/services/documents/*`) are pure Dart: no `package:flutter` imports. They run in a background isolate and their results cross isolates, so models hold plain data only: `int` colours as 0xAARRGGBB, `double` geometry, `String`, `Uint8List`/`OfficeImage`. No `dart:ui` types.

## Security and robustness (the file comes from a stranger's e-mail)
- Everything in the file is untrusted. Respect `OfficeLimits` (use `OfficeZip` for every part; never inflate yourself). Cap recursion with `OfficeLimits.maxDepth`, cap loops and "repeated" counts (ODF `number-rows-repeated="1048576"`, XLSX `<dimension ref="A1:XFD1048576">`): never allocate from a declared count.
- Never fetch anything: external images are dropped; links become `href` only for `http:`, `https:`, `mailto:` (the screen opens them through LinkOpener with the phishing check). No file-system writes.
- `read(...)` throws only `OfficeDocException` (catch `FormatException`, `RangeError`, `XmlException`, `StateError` etc. inside and rethrow as `OfficeDocError.damaged`; password-protected ODF — `zip.odfEncrypted` → `OfficeDocError.encrypted`). A damaged sub-part (an image, styles.xml, one sheet) must not kill the whole preview: skip it and show the rest.
- Speed: a typical document should parse in well under a second on a phone. For parts that can be tens of MB (sheet XML, shared strings, big content.xml) use the event parser `parseEvents` from `package:xml/xml_events.dart` over `zip.readHead(...)` instead of a DOM; when `readHead` says `truncated` or a cap is hit, set `truncated` and show what you have.

## Code, tests, fixtures
- Comments in Russian, explaining why, citing "(1.11.x, предпросмотр документов, план владельца 04.11.2026)"; density like neighbouring files (see `zip_view.dart`, `eml_reader.dart`). `dart format` only your new files (line length 120 as in the project: `dart format -l 120`).
- Fixtures: `test/fixtures/office/` — small (prefer < 20 KB, never > 60 KB), Russian/Cyrillic text included, no real personal names. Generate them with a script you commit under `tool/dev/office_fixtures/` (python-docx, openpyxl, python-pptx are installed; LibreOffice too: `soffice --headless -env:UserInstallation=file:///tmp/lo_<your-area> --convert-to odt --outdir DIR FILE` — use your own profile dir, other agents run soffice at the same time). LibreOffice can also render a reference PNG/PDF of a fixture to compare with your output.
- Unit tests `test/unit/<name>_test.dart` on the fixtures AND on hand-made hostile inputs (huge repeat counts, deep nesting, malformed XML, missing parts, wrong mimetype, encrypted ODF manifest). Widget tests in `test/widget/`. For a visual self-check you may render your widget to PNG with `matchesGoldenFile` + `--update-goldens` (load `assets/fonts/pdf/Roboto-Regular.ttf` with `FontLoader` so text is readable), but put such PNGs in your scratch dir — do not commit goldens.
- Run `flutter analyze lib test` (must be "No issues found") and your own tests. Do NOT run the whole suite (three agents share 4 CPUs); the lead runs it after merging. `git checkout analysis_options.yaml` after flutter commands.
- Commit in your worktree branch; end every message with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01AU5HURx9BTVeVhTjPMppag
  Do NOT push, do NOT merge into other branches, do NOT touch the version.
- Final report (English): what you implemented, public API (exact signatures), files, tests and results, limitations (what is not rendered), anything that should go into shared files, branch name and final commit hash.
