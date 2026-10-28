# Ogneliss Mail

Open source email client for Android, iOS, Windows, macOS and Linux, built
with Flutter. Works with Microsoft Exchange (Exchange ActiveSync and EWS) and
IMAP/SMTP mailboxes (Gmail, Outlook.com, Yandex, Mail.ru, iCloud and others),
with calendar, contacts, tasks and notes (CalDAV/CardDAV for IMAP accounts).

- No ads, no analytics, no generative AI. Data stays on the device
  (encrypted database).
- 27 interface languages.
- Website: https://ogneliss.ru

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Exchange protocols are implemented from Microsoft Open Specifications
(MS-ASCMD, MS-ASWBXML, MS-OXWS… ). Microsoft's Interoperability Principles
patent pledge for open source developers covers non-commercial distribution
of open source implementations of these specifications. Ogneliss Mail is
distributed free of charge.

## Building

Requirements: Flutter (stable), Android SDK / Xcode as needed.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define-from-file=config/dart_defines.json
```

`config/dart_defines.json` holds your own OAuth client IDs and server
addresses and is not part of the repository; see `docs/guides/OAUTH_SETUP.md`
and `docs/guides/QUICKSTART.md`. Platform guides: `docs/guides/`.

Interface strings live in `assets/l10n/<code>.xml`; tool: `tool/l10n/l10n.py`.

## Contributing

Issues and pull requests are welcome. By contributing you agree that your
contribution is licensed under the Apache License 2.0. Please report
security issues privately (see [SECURITY.md](SECURITY.md)).
