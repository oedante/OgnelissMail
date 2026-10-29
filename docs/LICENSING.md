# Licensing

*Not legal advice. Updated 28 October 2026.*

## 1. Ogneliss Mail

Everything in this repository written for the project — the app (`lib/`),
the mail engine (`packages/mail_engine`), the native plugin
(`packages/ogneliss_native_http`), the sign-in server (`server/oauth-proxy`),
the push relay (`server/push-relay`), tools, tests and documentation — is
licensed under the [Apache License 2.0](../LICENSE).
Copyright 2025–2026 Oleg Andreevich Ermishin. See [NOTICE](../NOTICE).

If you distribute the code or your own build:

- include the text of the Apache License 2.0;
- keep the copyright notices and the text of the NOTICE file (the app already
  shows both under Settings → About → Licence texts);
- mark the files you changed;
- give your version its own name, icon and application ID —
  [TRADEMARKS.md](../TRADEMARKS.md).

Contributions are accepted under the same license (section 5 of the license).

## 2. Third-party components

| Component | License | Where |
|---|---|---|
| Flutter, Dart and most packages from pub.dev | BSD-3-Clause, BSD-2-Clause, MIT, Apache-2.0 | `pubspec.yaml` |
| enough_mail, enough_convert (IMAP/SMTP, MIME); dbus, nm (Linux network status) | MPL-2.0 | pub.dev, unmodified |
| HugeRTE message editor (includes DOMPurify) | MIT (DOMPurify: Apache-2.0 or MPL-2.0) | `assets/editor/` |
| SQLite3 Multiple Ciphers (encrypted database) | MIT; SQLite — public domain | built by the `sqlite3` package |
| Roboto font | Apache-2.0 | `assets/fonts/pdf/` |
| OpenDyslexic font | SIL OFL 1.1, Reserved Font Name "OpenDyslexic" | `assets/fonts/` |
| Medeo Sans font (unmodified, github.com/DNFDEVS/medeo-font) | SIL OFL 1.1 | `assets/fonts/medeo/` |
| Material Symbols icons | Apache-2.0 | `material_symbols_icons` |
| AndroidX, Kotlin, AppAuth | Apache-2.0 | Android and iOS builds |
| Russian Trusted Root CA certificates | public certificates | `assets/certs/` |

There are no GPL, LGPL or AGPL dependencies. MPL-2.0 is a file-level copyleft
compatible with Apache 2.0: the libraries are used unmodified and their
source is on pub.dev; if you change their files, publish those files under
MPL-2.0. The full list with every license text is generated from the
libraries and shown in the app (Settings → About → Licence texts).

The server dependencies (`server/oauth-proxy`: express and its dependencies)
are MIT, ISC and BSD-3-Clause.

## 3. Microsoft Exchange protocols

Exchange support is an independent implementation written from the
Microsoft Open Specifications: MS-ASHTTP, MS-ASCMD, MS-ASWBXML, MS-ASDTYPE,
MS-ASAIRS, MS-ASEMAIL, MS-ASCAL, MS-ASCNTC, MS-ASTASK, MS-ASNOTE, MS-ASPROV,
MS-ASMOV (Exchange ActiveSync), MS-OXWS* (EWS), MS-OXDISCO (Autodiscover),
MS-OXCICAL and MS-NLMP (NTLM). No Microsoft code is used.

- **Copyright.** The Open Specifications notice allows copying the
  documentation to develop implementations.
- **Patents.** Microsoft's *Interoperability Principles Patent Pledge for
  Open Source Developers*
  ([MS-DEVCENTLP](https://learn.microsoft.com/en-us/openspecs/dev_center/ms-devcentlp/d84cac00-b312-44ee-9156-23bde6477c3d))
  promises not to assert Microsoft Necessary Claims against open source
  developers for making, using, importing or distributing implementations of
  the covered specifications. Microsoft confirmed in writing (28 October 2026)
  that Exchange ActiveSync is covered, since it is implemented in Exchange and
  Office products.
- **Condition: no commercial distribution.** The pledge does not cover
  distribution from which the distributor derives revenue — sales,
  subscriptions, paid updates, user-based connection fees or services a
  customer must buy to get the current version or updates. Ogneliss Mail is
  therefore distributed free of charge: no paid version, subscriptions,
  in-app purchases, paid updates or advertising.
- **Forks.** The pledge is personal to developers of an open source project;
  rights under it are not passed on through distributors. If you distribute
  a modified version commercially, the pledge does not cover that
  distribution — check your own licensing with Microsoft.
- **Trademarks.** "Microsoft", "Exchange", "Exchange ActiveSync" and
  "Outlook" are used only to describe compatibility ("works with Microsoft
  Exchange"), without Microsoft logos.

## 4. App store builds

The builds published by the author in Google Play and the App Store are
built from this repository and are free. The App Store terms (Usage Rules)
apply to the copy downloaded from the App Store; they do not limit your
rights to the source code under the Apache License 2.0. The sign-in server
and the push relay run by the author serve only the author's builds;
your own version needs its own servers and OAuth registrations
([OWN_VERSION.md](guides/OWN_VERSION.md)).

---

# Лицензирование (кратко)

*Не юридическое заключение. 28.10.2026.*

- **Код проекта** — приложение, движок почты, плагин, серверы входа и
  сигналов, инструменты, тесты, документация — по лицензии **Apache 2.0**.
  Правообладатель — Ермишин Олег Андреевич, 2025–2026 (файл NOTICE).
- **Распространяете код или свою сборку** — приложите текст лицензии,
  сохраните NOTICE и уведомления об авторских правах, пометьте изменённые
  файлы, дайте версии своё название, значок и идентификатор (TRADEMARKS.md).
- **Сторонние компоненты** — BSD, MIT, Apache 2.0; enough_mail,
  enough_convert, dbus и nm — MPL 2.0 (используются без изменений); шрифты
  OpenDyslexic и Medeo Sans — OFL 1.1. GPL, LGPL и AGPL нет. Полный список с текстами
  лицензий — в приложении: «Настройки → О приложении → Тексты лицензий».
- **Протоколы Exchange (EAS, EWS)** реализованы самостоятельно по открытым
  спецификациям Microsoft (Open Specifications); кода Microsoft нет.
  Патенты: обещание Microsoft для разработчиков открытого ПО
  ([MS-DEVCENTLP]); Microsoft письменно подтвердил 28.10.2026, что EAS в него
  входит. **Условие — некоммерческое распространение:** без выручки от
  распространения (продажа, подписки, платные обновления, плата за
  подключение, обязательные платные услуги). Поэтому Ogneliss Mail
  бесплатен: без платной версии, подписок, встроенных покупок и рекламы.
  Обещание личное — для разработчиков открытого проекта; на тех, кто
  распространяет изменённую версию за деньги, оно не распространяется.
- **Товарные знаки Microsoft** — только словами «работает с Microsoft
  Exchange», без логотипов.
