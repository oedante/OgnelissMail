# Licensing

*Not legal advice. Updated 7 November 2026.*

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
| MET Norway Locationforecast 2.0 — weather in My Day (external service, off until a city is chosen, 1.15.1) | data NLOD 2.0 and CC BY 4.0 (credit «MET Norway» + link to the licence); free, no SLA. Terms of Service (rev. 05.11.2026) **accepted by the owner 07.11.2026** on the condition that no user data goes to third parties: the app calls only the Ogneliss server (`server/weather-proxy`), the server calls MET with its own User-Agent and caches by Expires / If-Modified-Since (one request per city for all users, ≤ 4 decimals, pause after 429, well under 20 req/s) | `lib/services/weather/weather_service.dart`, `server/weather-proxy/server.js`; attribution «Data: MET Norway (CC BY 4.0)» with the licence link in the weather sheet and in the licence texts |
| GeoNames (cities15000, admin1CodesASCII, countryInfo) — city search for the weather (data on the Ogneliss server, 1.15.1) | CC BY 4.0, free; downloaded by `server/weather-proxy/install-weather-proxy.sh`; the search runs on the server, nothing goes to GeoNames from the app. Nominatim (OpenStreetMap) was considered and dropped: its policy needs a separate developer decision and limits the number of users | `server/weather-proxy/server.js`; attribution «Cities: GeoNames (CC BY 4.0)» with a link in the city search sheet and in the licence texts |
| OpenDyslexic font | SIL OFL 1.1, Reserved Font Name "OpenDyslexic" | `assets/fonts/` |
| System fonts of the platform (interface font option, 1.10.2: Noto Serif and Roboto Condensed on Android; Helvetica Neue, Arial, Georgia on iOS and macOS; Arial, Calibri, Verdana, Georgia on Windows; Noto Sans, DejaVu Sans, Noto Serif on Linux) | not distributed — used from the OS | — |
| Material Symbols icons | Apache-2.0 | `material_symbols_icons` |
| flutter_svg (sender logos, BIMI) with vector_graphics, vector_graphics_codec, vector_graphics_compiler | MIT; vector_graphics*: BSD-3-Clause | pub.dev |
| AndroidX, Kotlin, AppAuth | Apache-2.0 | Android and iOS builds |
| AndroidX Enterprise Feedback 1.1.0 (`androidx.enterprise:enterprise-feedback`; checked 09.11.2026) — report to the MDM console (KeyedAppStates, 2.2.0) | Apache-2.0, free | Android build only (`android/app/build.gradle.kts`, `MdmBridge.kt`); text in the app: "AndroidX Enterprise Feedback" |
| Firebase Cloud Messaging Android SDK (`com.google.firebase:firebase-messaging`, BoM 35.1.0; checked 01.11.2026) | Apache-2.0; pulls in Google Play services client libraries (proprietary, free of charge, Android SDK / Google APIs terms) | Android build only (`android/app/build.gradle.kts`); text in the app: "Firebase Cloud Messaging" |
| Firebase Cloud Messaging service (Google) | free of charge, no paid tier or quota fees (Firebase Spark plan); Firebase / Google APIs Terms of Service | Android server signals: app and `server/push-relay` (HTTP v1 API) |
| UnifiedPush android-connector 3.3.5 (`org.unifiedpush.android:connector`; checked 01.11.2026) — server signals on Android without Google services | Apache-2.0, free | Android build only (`android/app/build.gradle.kts`, `PushWakeUnifiedPush.kt`); text in the app: "UnifiedPush connector" |
| Google Tink 1.23.0, Android build (`com.google.crypto.tink:tink-android`, used by the UnifiedPush connector for Web Push decryption; the JVM build `tink` that the connector declares is excluded to avoid duplicate classes) with bundled protobuf lite (BSD-3-Clause) and its dependencies gson, error_prone_annotations (Apache-2.0), jsr305 (BSD-3-Clause) | Apache-2.0 / BSD-3-Clause, free | Android build only; texts in the app: "Tink", "Protocol Buffers" |
| UnifiedPush distributors and push servers (ntfy, NextPush, Sunup and others) — chosen and installed by the user | the user's own apps and servers; the developer's relay only sends encrypted signals to the address they issue | not part of the app |
| Google ML Kit Translation and Language ID (`com.google.mlkit:translate` 17.0.3, `com.google.mlkit:language-id` 17.0.6) — on-device message translation | Free; ML Kit Terms of Service and Google APIs Terms of Service (closed-source binaries). Conditions: Google attribution next to translated text and in the app description/help ("Translated by Google"); no use in embedded devices (cars, TVs, appliances, speakers); ML Kit sends usage metrics (not text) to Google — mention in the privacy policy | Android build (`android/app/build.gradle.kts`) |
| Apple Translation, NaturalLanguage, SwiftUI — on-device message translation (iOS 18+) | Part of the iOS SDK (Apple Developer Program License Agreement), free, no attribution | iOS build (`ios/Runner/AppDelegate.swift`) |
| super_drag_and_drop 0.10.0-dev.2 with super_clipboard and super_native_extensions 0.10.0-dev.2 (Superlist, Matej Knopp), irondash_engine_context 0.6.0-dev.0, irondash_message_channel 0.8.0-dev.0, pixel_snap 0.1.5 (Matej Knopp); checked 07.11.2026 — dragging an attachment out of a message (Explorer, Finder, another app) and files dropped onto the message window (replaces desktop_drop since 1.15.0) | MIT, free | pub.dev, unmodified; licence texts in the app come from the packages |
| Rust crates compiled into the native core of super_native_extensions (201 crates from its `Cargo.lock`: Rust standard ecosystem, gtk-rs, windows-rs, objc2, jni and others; checked 07.11.2026) | MIT, Apache-2.0, MIT OR Apache-2.0, Unlicense OR MIT, Zlib, BSL-1.0 (ryu: Apache-2.0 OR BSL-1.0), Unicode-DFS-2016 (unicode-ident), Apache-2.0 WITH LLVM-exception (target-lexicon, build step only); `colored` 2.1.0 — MPL-2.0 (used unmodified, by the package's logger); free | built from source at app build time (needs rustup); texts in the app: "super_native_extensions (Rust)", collected by `tool/dev/rust_licenses.py` into `assets/licenses/rust_crates.json` |
| native_toolchain_rust 1.0.6 (Gregory Conrad), hooks (Dart team) — build tooling for the Rust core, not shipped in the app | MIT; hooks: BSD-3-Clause | pub.dev, build time only |
| Rust toolchain (rustup, rustc, cargo) — compiler used at build time, not shipped | MIT OR Apache-2.0, free | installed by the developer (https://rustup.rs) |
| desktop_multi_window 0.3.1 (MixinNetwork; checked 01.11.2026) — a message in a separate window on Windows, macOS and Linux | Apache-2.0, free | pub.dev, unmodified; desktop only |
| markdown 7.3.1 (Dart team, dart-lang/tools; checked 05.11.2026) — Markdown attachments (.md) shown as formatted documents in the attachment preview | BSD-3-Clause, free | pub.dev, unmodified; licence text in the app (Settings → About → Licence texts) comes from the package |
| Russian Trusted Root CA certificates | public certificates | `assets/certs/` |

There are no GPL, LGPL or AGPL dependencies. MPL-2.0 is a file-level copyleft
compatible with Apache 2.0: the libraries are used unmodified and their
source is on pub.dev; if you change their files, publish those files under
MPL-2.0. The full list with every license text is generated from the
libraries and shown in the app (Settings → About → Licence texts).

The server dependencies (`server/oauth-proxy`: express and its dependencies)
are MIT, ISC and BSD-3-Clause. `server/push-relay` has no dependencies (Node.js
built-ins only, including the FCM OAuth2 JWT signing).

Firebase on Android (1.9.x, server signals) is used through the Android SDK
directly, not through the FlutterFire plugins `firebase_core` /
`firebase_messaging` (BSD-3-Clause, also free): those would add the Firebase
SDK to the iOS build (where the messaging plugin takes over the app delegate
push callbacks used by the APNs relay) and download the Firebase C++ SDK in
the Windows build. No `google-services.json` and no google-services Gradle
plugin: the project options come from build-time dart-defines; without them
nothing Firebase-related runs. The Play services dependency is the reason
the feature needs Google Play services on the phone; phones without them
get the same signals through UnifiedPush (1.10.x, rows above).

Every push checks these licences automatically (`tool/dev/license_check.py`
in CI): GPL, LGPL, AGPL, SSPL, BUSL, non-commercial or unrecognised licences
fail the build unless `tool/dev/license_allowlist.txt` lists the package with
a reason.

Tools used only by the build on GitHub Actions (not part of the app or the
servers): OSV-Scanner and osv-scanner-action (Google, Apache-2.0) with the
free OSV database (osv.dev) for dependency vulnerabilities, and
android-emulator-runner (ReactiveCircus, Apache-2.0) for the Android
emulator tests.

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

## 5. Adding a dependency

Before any new dependency is added — a pub.dev package, a Gradle or
CocoaPods library, a platform SDK or framework, a server npm package, a
font, icons, an external service or API — its licence and terms of use are
checked (owner's rule, 31 October 2026, after the Exchange ActiveSync patent
pledge turned out to forbid commercial distribution):

- **Paid functionality** — a paid licence, a subscription, payment per
  request above a free quota, commercial-only terms — is not added until it
  has been discussed with the owner.
- **Restrictive or unclear terms** — non-commercial only, field-of-use or
  patent conditions, copyleft (GPL, LGPL, AGPL), no licence at all — are
  discussed with the owner too.
- **Free functionality** is used with the licence requirements met: the
  licence text and NOTICE shipped in the app (Settings → About → Licence
  texts), attribution where required, and a row in the table in section 2.

## 6. Document formats (attachment preview, 1.11.x; old formats and .msg — 1.14.0)

Since 1.11.x the app shows attachments in DOCX, XLSX, PPTX (and their
macro-enabled, template and slide-show variants), ODT, ODS, ODP, RTF and CSV
read-only, inside the app. The readers (`lib/services/documents/`) are
written for the project from the public format specifications: no code of
Microsoft, Oracle, LibreOffice or anyone else and no new libraries. Macros
are never run (the macro part is not even read). Checked 4 November 2026:

- **Office Open XML** (ECMA-376, ISO/IEC 29500; Microsoft's notes
  [MS-OE376], [MS-OI29500]) is on the list of specifications covered by the
  **Microsoft Open Specification Promise** (OSP,
  [MS-DEVCENTLP](https://learn.microsoft.com/en-us/openspecs/dev_center/ms-devcentlp/1c24c7c8-28b0-4ce1-a47d-95fe1ff504bc)):
  "Microsoft irrevocably promises not to assert any Microsoft Necessary
  Claims against you for making, using, selling, offering for sale,
  importing or distributing any implementation to the extent it conforms to
  a Covered Specification." The OSP FAQ: it "applies whether you have a full
  or partial implementation" (a viewer is a partial one) and applies
  "without regard to the development model … the type of copyright licenses
  … or the business model of distributors/implementers"; it is a personal
  promise to every implementer, including users and forks. The only
  condition is defensive: it stops for someone who sues Microsoft over its
  implementation of the same specification. **Unlike the Interoperability
  Principles pledge that covers Exchange ActiveSync (section 3), the OSP has
  no restriction on commercial distribution** — store builds, forks and
  paid redistribution are all covered.
- **OpenDocument** (OASIS ODF 1.0–1.3, ISO/IEC 26300) is on the same OSP
  list. In addition the OASIS ODF TC works under the "RF on Limited Terms"
  mode of the OASIS IPR Policy (royalty-free licences from the participants),
  and the *Sun Microsystems OpenDocument Patent Statement* (29 September
  2005, [oasis-open.org](https://www.oasis-open.org/committees/office/ipr.php))
  irrevocably covenants not to enforce Sun's patents against any
  implementation of OpenDocument (reciprocity condition only).
- **RTF** (Microsoft Rich Text Format Specification 1.9.1) appears as
  "[RTF]: Rich Text Format" in the Office file formats part of the OSP list.
- **CSV** — RFC 4180 (informational); no IETF patent disclosures were found;
  the format is decades older than any such patent.
- **Old binary formats** (preview since 1.14.0): [MS-DOC] (.doc), [MS-XLS]
  (.xls), [MS-PPT] (.ppt, text first), their pictures [MS-ODRAW] (OfficeArt)
  and their container [MS-CFB] (Compound File Binary) are on the OSP list ("Office Binary File Formats"), checked
  05.11.2026 by copies of the list (SheetJS references, Wikipedia mirror of
  the OSP article) — the same terms as above, no commercial restriction.
- **Outlook messages (.msg)** — [MS-OXMSG] with compressed RTF [MS-OXRTFCP]
  and the property numbers of [MS-OXPROPS] (preview since 1.14.0,
  `lib/services/mail/msg_reader.dart`): the owner's information of 05.11.2026 — MS-OXMSG
  is on the OSP list in "Office Binary and other File Formats"
  ([OSP page](https://learn.microsoft.com/en-us/openspecs/dev_center/ms-devcentlp/1c24c7c8-28b0-4ce1-a47d-95fe1ff504bc),
  [MS-OXMSG](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxmsg/b812bc47-4397-4a15-b03d-84aa20be866f)).
  The Library of Congress format description also says Microsoft claims no
  patents in the MSG format. Decision of the owner: implement.
- **Encrypted old Excel books (1.15.1)** — [MS-OFFCRYPTO] RC4 and RC4
  CryptoAPI, used to open books protected with Excel's default password
  "VelvetSweatshop" (`lib/services/documents/xls_crypt.dart`; MD5, SHA-1
  and RC4 from the `crypto` and `pointycastle` packages already in the
  app). MS-OFFCRYPTO is listed under the Open Specification Promise in the
  SheetJS references page and in a 2011 LibreOffice list post quoting
  Microsoft's Office file formats page (checked 07.11.2026 by search
  extracts; learn.microsoft.com was blocked) — confirm on the OSP page
  together with the entries above.
- **PDF text for search (1.15.1)** — `lib/services/documents/pdf_text.dart`
  reads text streams, fonts and the standard security handler (RC4,
  AES-128, AES-256) after ISO 32000-1 (PDF 1.7). Adobe's *Public Patent
  License* for ISO 32000-1:2008 grants a royalty-free licence under Adobe's
  essential claims to compliant implementations (defensive termination
  only). The AES-256 "revision 6" key derivation comes from ISO 32000-2
  (PDF 2.0); its patent declarations were not checked — to confirm. No
  library is used; nothing of the PDF is rendered.
- **Test files from Apache POI** — four .xls and five Outlook .msg files
  from the Apache POI test data (Apache License 2.0) are used only by the
  tests and are not in the app (`test/fixtures/office/README.md`,
  `test/fixtures/msg/README.md`, attribution there).
- **Specification texts.** The Microsoft Open Specifications notice and the
  Ecma and OASIS copyright policies allow using the documents to write
  implementations. No specification text or schema is copied into the app.
- **Trademarks.** "Microsoft", "Word", "Excel", "PowerPoint" — only in text
  that truthfully states compatibility ("previews documents in DOCX, XLSX,
  PPTX…", "works with documents created in Microsoft Word, Excel and
  PowerPoint"), never in the app name, icon or screenshots, and without
  "official" or "certified" (Microsoft trademark guidelines).
- **How it was checked.** The cloud session's network policy blocked
  learn.microsoft.com, oasis-open.org and ecma-international.org, so the
  quotes above come from search-engine extracts of those primary pages, not
  from the pages read in full. Before announcing the feature, open the OSP
  page (covered list: Office Open XML, OpenDocument, RTF) and the Sun
  statement by the links above and confirm.
- **Accepted by the owner (06.11.2026: checked, widely used in open
  source):** [MS-OXRTFEX] (HTML that Outlook encapsulates in RTF, `\fromhtml1`)
  — the .msg reader uses it to show such bodies as HTML
  (`MsgReader.htmlFromRtf`, one call site in `msg_reader.dart`). Its
  document says it "might be covered by" the OSP or the Community Promise;
  learn.microsoft.com was blocked in the cloud session and search results
  did not confirm it (05.11.2026). If it is not covered, drop that call:
  such bodies are then shown through the RTF reader (RTF is on the OSP
  list). [MS-OXPROPS] is used only as a table of property numbers. Also
  unchecked: [MS-OXTNEF] (winmail.dat — the app already extracts files from
  it, `lib/services/mail/tnef/tnef_decoder.dart`).

---

# Лицензирование (кратко)

*Не юридическое заключение. 28.10.2026.*

- **Код проекта** — приложение, движок почты, плагин, серверы входа и
  сигналов, инструменты, тесты, документация — по лицензии **Apache 2.0**.
  Правообладатель — Ермишин Олег Андреевич, 2025–2026 (файл NOTICE).
- **Распространяете код или свою сборку** — приложите текст лицензии,
  сохраните NOTICE и уведомления об авторских правах, пометьте изменённые
  файлы, дайте версии своё название, значок и идентификатор (TRADEMARKS.md).
- **Firebase Cloud Messaging** (сигналы сервера на Android, 1.9.x) — сервис
  Google бесплатный (план Spark, без платы за сообщения); библиотека Android
  — Apache 2.0, зависит от бесплатных проприетарных сервисов Google Play.
  Только в сборке Android; Flutter-плагины Firebase не используются.
- **UnifiedPush** (сигналы сервера на Android без сервисов Google, 1.10.x) —
  библиотека android-connector (Apache 2.0) с Google Tink в Android-сборке
  tink-android (Apache 2.0, внутри protobuf lite — BSD-3-Clause). Распространитель (ntfy и др.) человек ставит
  сам; сервер разработчика шлёт на выданный им адрес только зашифрованный
  сигнал.
- **Перевод писем на устройстве** (1.9.x): на Android — Google ML Kit
  (бесплатно, условия ML Kit и Google APIs: подпись «Переведено Google» у
  перевода и упоминание Google Translate в описании и справке; ML Kit
  отправляет в Google статистику работы, не текст писем — указать в
  политике конфиденциальности); на iPhone и iPad — Apple Translation из iOS
  SDK (бесплатно, без условий атрибуции). Подробности —
  docs/guides/TRANSLATION_SETUP.md.
- **Сторонние компоненты** — BSD, MIT, Apache 2.0; enough_mail,
  enough_convert, dbus и nm — MPL 2.0 (используются без изменений); шрифты
  OpenDyslexic — OFL 1.1 (Medeo Sans убран в 1.10.2; другие шрифты на
  выбор — системные, приложение их не распространяет). GPL, LGPL и AGPL нет. Полный список с текстами
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
- **Предпросмотр документов** (1.11.x: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF,
  CSV — только чтение, макросы не выполняются) написан самостоятельно по
  открытым спецификациям, без чужого кода и новых библиотек. Патенты:
  Office Open XML, OpenDocument и RTF — в списке **Open Specification
  Promise** Microsoft (бесповоротное обещание не предъявлять патенты к любой,
  в том числе частичной, реализации; **без условия о некоммерческом
  распространении** — в отличие от обещания для Exchange ActiveSync; одно
  условие — не судиться с Microsoft из-за той же спецификации); для
  OpenDocument ещё — патентное обещание Sun (2005) и режим OASIS без
  отчислений. CSV (RFC 4180) — патентных заявлений нет. Товарные знаки Word,
  Excel, PowerPoint — только словами о совместимости. Цитаты сверены по
  выдержкам поисковика: сами страницы Microsoft и OASIS сеть облачного
  сеанса не открыла — перед объявлением функции открыть их по ссылкам из
  раздела 6 и подтвердить. Старые .doc, .xls, .ppt (1.14.0; контейнер
  MS-CFB, рисунки MS-ODRAW) — тоже в списке OSP (по копиям списка,
  05.11.2026); письма Outlook .msg (MS-OXMSG, сжатый RTF MS-OXRTFCP) — в
  списке OSP по данным владельца (05.11.2026, решение — делать). MS-OXRTFEX (HTML
  внутри RTF у писем .msg) — владелец проверил 06.11.2026 («многие
  используют в open source»), решение — оставить. Отдельно проверить
  TNEF (winmail.dat — его приложение уже разбирает).
- **Новые зависимости** (пакеты, библиотеки, SDK, шрифты, внешние сервисы и
  API) — только после проверки лицензии и условий (правило владельца
  31.10.2026, после истории с Exchange ActiveSync). Платный функционал и
  ограничительные или неясные условия (только некоммерческое использование,
  патентные условия, GPL/LGPL/AGPL, нет лицензии) — сначала обсудить с
  владельцем. Бесплатный — используем, соблюдая требования лицензии: текст
  лицензии в приложении, атрибуция, строка в таблице раздела 2.
