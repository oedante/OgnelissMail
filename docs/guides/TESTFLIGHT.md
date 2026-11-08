# TestFlight: iPhone, iPad и Mac (Intel и Apple Silicon)

Просьба владельца 08.11.2026: «как отправить в TestFlight сборку и для iOS,
и для macOS (процессоры Intel и новые M) — или отдельно через Xcode и
скрипт». Ниже три пути: Xcode руками, скрипт одной командой, GitHub Actions
(пока не настроен — что для него нужно, в разделе 5).

Для Mac собирается **одна универсальная сборка**: внутри код и для Intel
(x86_64), и для Apple Silicon (arm64, M1 и новее). TestFlight и Mac App
Store сами ставят её на любой Mac. Отдельно «для Intel» и «для M» собирать
не нужно и нельзя (номер сборки один).

## 0. Один раз

1. Mac с Xcode, Flutter, CocoaPods и Rust (rustup). Проверка:
   `scripts/build_ios.sh --check`.
2. **Xcode → Settings → Accounts** — Apple ID вашей команды разработчика.
3. Команда (Team ID, 10 символов: developer.apple.com → Account →
   Membership details) — один раз, запоминается вне проекта и для iPhone, и
   для Mac:
   ```bash
   scripts/build_ios.sh --team ABCDE12345 --prepare
   ```
4. **Mac — папка `macos/`** (в архиве проекта её нет, она живёт у вас):
   ```bash
   scripts/build_macos.sh --setup
   open macos/Runner.xcworkspace   # Runner → Signing & Capabilities → Team
   ```
5. **App Store Connect → Приложения → Ogneliss Mail**: слева у «Приложение
   для iOS» нажмите **«+»** → **macOS** (одна карточка, тот же идентификатор
   `com.ogneliss.mail` — покупка общая). Создайте версию macOS **1.15.1**.
   Без платформы macOS в карточке выгрузка Mac-сборки не пройдёт.
6. *По желанию* — ключ App Store Connect API (тогда скрипты не зависят от
   входа в Xcode и работают по SSH): App Store Connect → **Пользователи и
   доступ → Интеграции → App Store Connect API → «+»**, роль **App Manager**
   → скачать `AuthKey_XXXXXXXXXX.p8` (скачивается **один раз**):
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   cp AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
   ```
   Key ID — в строке ключа, Issuer ID — над таблицей ключей. Если при
   выгрузке с ключом Xcode пишет, что не хватает прав на сертификаты, —
   роль **Admin** или запуск без ключа (тогда — учётная запись Xcode).

## 1. Через Xcode

**iPhone и iPad**
1. `scripts/build_ios.sh --prepare` — зависимости, код базы, версия и ключи
   сборки (`config/dart_defines.json`) в настройках Xcode.
2. `open ios/Runner.xcworkspace` → схема **Runner**, устройство **Any iOS
   Device (arm64)** → **Product → Archive**.
3. Откроется Organizer → **Distribute App → App Store Connect → Upload** →
   подпись автоматическая → **Upload**.

**Mac (Intel + Apple Silicon)**
1. `scripts/build_macos.sh` — обычная сборка: готовит настройки Flutter для
   Xcode (версия, ключи сборки).
2. `open macos/Runner.xcworkspace` → схема **Runner**, устройство **Any Mac
   (Apple Silicon, Intel)** → **Product → Archive**.
   Если выбрать «My Mac», архив будет только под процессор этого Mac.
3. Organizer → **Distribute App → App Store Connect → Upload**.
4. Проверить, что сборка универсальная (по желанию): Organizer → архив →
   Show in Finder → «Показать содержимое пакета» →
   `Products/Applications/Ogneliss Mail.app`, затем в Терминале:
   `lipo -archs ".../Ogneliss Mail.app/Contents/MacOS/Ogneliss Mail"` →
   `x86_64 arm64`.

## 2. Скриптом — одной командой

```bash
scripts/build_ios.sh --upload      # iPhone и iPad: архив, подпись, выгрузка
scripts/build_macos.sh --upload    # Mac: универсальный архив, подпись, выгрузка
```

С ключом API (шаг 0.6):
```bash
export ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
scripts/build_ios.sh --upload && scripts/build_macos.sh --upload
```

- `scripts/build_macos.sh --archive` — только архив, затем он открывается в
  Xcode (Distribute App вручную).
- Скрипт Mac после архива печатает «Архитектуры: x86_64 arm64» и
  останавливается, если одной нет.
- По SSH (например, из Windows): `KEYCHAIN_PASSWORD=<пароль входа на Mac>` —
  иначе связка ключей заблокирована и подпись не пройдёт.
- Не вышло — скрипт открывает готовый архив в Xcode (Distribute App), так
  что собирать заново не нужно.

## 3. Дальше в App Store Connect

- Сборка появляется в **TestFlight** через 10–30 минут; у iPhone и Mac —
  отдельные вкладки (iOS / macOS).
- **Экспортное соответствие** (вопрос о шифровании) — так же, как для
  прежних сборок iPhone: в приложении здесь ничего не менялось; для первой
  Mac-сборки — тот же ответ.
- **Внутренние тестировщики** (участники команды) получают сборку сразу,
  **внешние** — после бета-проверки Apple (обычно — первая сборка версии).
- **Открытая ссылка TestFlight** (группа External Testing, ссылка на сайте):
  группе добавляется сборка каждой платформы — **«+» Сборки** на вкладке iOS
  и на вкладке macOS; ссылка общая.
- На Mac тестировщику нужно приложение **TestFlight** из Mac App Store и
  **macOS 12 или новее**; Intel и M — одна и та же сборка.
- **Номер сборки** (число после «+» в `pubspec.yaml`) должен быть новым для
  каждой загрузки на одну платформу. iPhone и Mac считаются отдельно:
  1.15.1 (142) можно загрузить и туда, и туда.

## 4. Приложение iPad на Mac с M — без отдельной сборки

App Store Connect → **Цены и доступность → Приложения для iPhone и iPad на
компьютерах Mac с Apple Silicon** — «Сделать доступным». Тогда сборка iOS из
TestFlight ставится и на Mac с M (окно в пропорциях iPad). На Mac с Intel —
нет, для них только настоящая Mac-сборка (разделы 1–2).

## 5. Из GitHub Actions (без Mac) — что нужно

Можно: раннер macOS GitHub собирает и выгружает по кнопке (для открытого
репозитория минуты бесплатны). Сейчас не настроено, потому что нужно:

1. **Ключ App Store Connect API с ролью Admin** — Xcode на раннере сам
   получает облачный сертификат распространения и профили, файл
   сертификата (.p12) хранить не нужно. Секреты репозитория:
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (содержимое файла .p8),
   `APPLE_TEAM_ID`; `DART_DEFINES_JSON` уже есть.
2. **Файлы проекта Xcode в репозитории — такие же, как у вас**:
   `ios/Runner.xcodeproj/project.pbxproj`, `Runner.entitlements`, права
   виджетов и папка `macos/`. По правилам проекта их ведёте вы и в архив они
   не входят; для сборки на GitHub их нужно один раз положить в репозиторий
   и обновлять после изменений в Xcode. Иначе на GitHub соберётся приложение
   без ваших настроек (push, группы, виджеты) — Apple его примет, но
   работать оно будет не так, как ваша сборка.

Когда секреты и файлы будут готовы — workflow «TestFlight» (ручной запуск,
выбор: iPhone, Mac или оба) делается за один шаг.
