## Common rules (read carefully)

You work in an isolated git worktree of the Flutter app Ogneliss Mail (repo oedante/OgnelissMail). Another agent may work on other features in parallel in other worktrees; stay inside your scope to avoid merge conflicts.

Setup:
- `export PATH=/opt/flutter/bin:$PATH` (Flutter 3.47.8). Run `flutter pub get`, then generate drift code: `dart run build_runner build --delete-conflicting-outputs` (lib/data/database/app_database.g.dart is not in git).
- After any flutter command, run `git checkout analysis_options.yaml` (flutter rewrites it).
- Read CLAUDE.md in the repo root first. It contains the owner's licensing rule: before adding ANY new dependency (pub package, Gradle/CocoaPods lib, SDK, service/API, font) check its licence and terms. Paid functionality or restrictive/unclear terms (non-commercial only, patent conditions, GPL/LGPL/AGPL, no licence) → do NOT add it; stop and report it so the owner can decide. Free → add it, add a row to the table in docs/LICENSING.md section 2, make sure its licence text is shown in the app (pub packages are automatic via LicenseRegistry; native SDKs/assets need an entry like the ones in lib/main.dart around line 79).

Code conventions:
- Match the surrounding code: comments are in Russian, explain why, and cite the request like "(1.9.x, просьба владельца 31.10.2026)". Keep comment density similar to neighbouring code. Do not reformat whole files (do NOT run `dart format` on existing files; only format new files).
- UI: reuse existing components and tokens (lib/widgets/ui/*, SettingsGroup/SettingsItem in lib/widgets/ui/settings_group.dart, showChoiceSheet card-style sheets, AppIcons in lib/core/theme/app_icons.dart, Space constants). Phone, tablet and desktop layouts must keep working.
- Strings: every user-visible string goes through l10n (`l10n.tr('key')`, keys in assets/l10n/*.xml). Add each new key to ALL 27 xml files with real translations (ru and en carefully; others natural). Look at an existing key, e.g. grep quickRepliesCardHint assets/l10n/.
- Settings: existing provider lib/features/settings/providers/settings_provider.dart (see how fields like uiAnimations/reduceMotion are stored and exposed).
- Database: schema version is 26 in lib/data/database/app_database.dart. Only change the schema if your brief says so and use exactly the version number given there, with a migration and a test.
- Never change: pubspec version, ios/Runner.xcodeproj/project.pbxproj, Runner.entitlements, Signing.xcconfig. If iOS needs a capability/entitlement/target, write step-by-step owner instructions (Russian) in a doc under docs/guides/ and mention it in your report. Swift code may only go into Swift files that already exist in the Runner target (ios/Runner/*.swift that are already in project.pbxproj), so no Xcode project change is needed.
- No real personal names in files. No secrets.
- Tests: add focused unit/widget tests for your logic (test/unit, test/widget). Before finishing run `flutter analyze lib test` (must be "No issues found") and `flutter test --exclude-tags shots` (all must pass). Fix what you break.
- Commit your work in your worktree branch (several commits are fine) with clear English messages, each ending with these two lines:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01JiyfHMgXz6R1tb4aBR4g9H
  Do NOT push, do NOT merge into other branches, do NOT touch the version.
- Final report (concise, English is fine): what you implemented and how, files touched, tests added and results, new dependencies with licences, anything the owner must do (Xcode, Firebase, server), known limitations, what you could not do and why. Include your worktree branch name and the final commit hash.
