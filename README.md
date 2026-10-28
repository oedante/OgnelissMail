# Ogneliss Mail

**Open-source email you can verify.** Mail, calendar, contacts and tasks for
Microsoft Exchange (ActiveSync and EWS) and IMAP/SMTP mailboxes, with
CalDAV/CardDAV calendars and contacts. Android, iPhone and iPad; Windows,
macOS and Linux builds are in preview.

> **Don't trust us — verify.** An email client sees your most private
> correspondence, so nothing below asks you to take our word for it: every
> claim can be checked in this repository.

Website: https://ogneliss.ru/mail/

## Principles

- **Open source.** The app, the mail engine and both servers are here, under
  the Apache License 2.0.
- **Direct connection.** Mail travels between your device and your mail
  server; it never passes through Ogneliss servers.
- **Local-first.** Mail is stored on the device in an encrypted database.
- **No ads, no analytics.** No advertising or tracking SDKs, no telemetry, no
  crash reporters.
- **Free.** No subscriptions, no premium tier, no paid features.

## Verify it yourself

| Claim | Where to look |
|---|---|
| No ads, analytics or tracking | `pubspec.yaml` and `android/app/build.gradle.kts` — the complete dependency list |
| Mail goes straight to your server | `packages/mail_engine` — Exchange ActiveSync, EWS, IMAP/SMTP; `lib/core/network` — HTTP clients and certificate checks |
| Encrypted local storage | `lib/data/database/app_database.dart` — SQLite3 Multiple Ciphers; the key is kept in the OS secure storage |
| What the author's servers do | `server/oauth-proxy` (OAuth code exchange, tokens kept in memory for at most 2 minutes) and `server/push-relay` (empty "check mail" signals for iPhone); [privacy policy, section 6](https://ogneliss.ru/mail/privacy#oauth) |
| Release files | GitHub Actions builds them from a tagged commit with a public log; each file has a signed build provenance attestation: `gh attestation verify <file> --repo oedante/OgnelissMail`, checksums in `SHA256SUMS.txt` |

The Google Play and App Store builds are made from the same code with the
author's signing keys and OAuth client IDs, which are not in this repository,
so they cannot be compared byte for byte.

## Features

- **Microsoft Exchange** via ActiveSync and EWS: mail, calendar, contacts,
  tasks and notes, meeting responses, automatic replies, the organisation
  address book, MailTips, shared and delegated mailboxes, server rules,
  device policies and remote wipe.
- **Any IMAP/SMTP mailbox** — Gmail, Outlook.com, Yandex, Mail.ru, iCloud and
  others; OAuth sign-in or app passwords; CalDAV and CardDAV.
- **Every day:** My Day, follow-ups and snooze, conversations, undo send,
  scheduled sending, rules, VIP and quiet hours, widgets.
- **Security:** S/MIME, phishing and external-sender warnings, tracker
  blocking, PIN and biometric lock.
- 27 interface languages.

## Building

Requirements: Flutter (stable), Android SDK / Xcode as needed.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define-from-file=config/dart_defines.json
```

`config/dart_defines.json` holds your own OAuth client IDs and server
addresses and is not part of the repository; see `docs/guides/OAUTH_SETUP.md`
and `docs/guides/QUICKSTART.md`. Platform guides: `docs/guides/`. Releasing
your own version under your own name: `docs/guides/OWN_VERSION.md`.

Interface strings live in `assets/l10n/<code>.xml`; tool: `tool/l10n/l10n.py`.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). The name
and icon are not covered by the license: [TRADEMARKS.md](TRADEMARKS.md).
Third-party components, Exchange protocols and app store builds:
[docs/LICENSING.md](docs/LICENSING.md).

Exchange protocols are implemented from Microsoft Open Specifications
(MS-ASCMD, MS-ASWBXML, MS-OXWS… ). Microsoft's Interoperability Principles
patent pledge for open source developers covers non-commercial distribution
of open source implementations of these specifications. Ogneliss Mail is
distributed free of charge: no paid version, subscriptions, in-app purchases
or ads. If you distribute a modified version commercially, the pledge does
not cover that distribution.

## Contributing

Issues and pull requests are welcome. By contributing you agree that your
contribution is licensed under the Apache License 2.0. Please report
security issues privately (see [SECURITY.md](SECURITY.md)).
