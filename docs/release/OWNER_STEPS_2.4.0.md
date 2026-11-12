# 2.4.0 — что сделать владельцу (12.11.2026)

2.4.0 (151) — решение владельца 12.11.2026: всё, что сделано 12.11
(оценка интерфейса, картинки рассылок, вложения, настройки) и PR #94
(поручения в календаре, значок ящика в напоминаниях, картинки в редакторе,
имена после почтовых шлюзов). Список изменений и тексты для магазинов —
`STORE_NOTES_2.4.0.md`.

Пробные режимы — «Новое встраивание окна письма (HCPP)» на Android 14+ и
«Сложные письма — в окне браузера» на Mac — в сборке есть, но **по умолчанию
выключены**: на устройствах не проверены, включать для всех — после
проверки (раздел 5).

Что нужно отдельно от сборки:

| | Нужно? |
|---|---|
| Xcode: `project.pbxproj`, `Runner.entitlements`, `Info.plist`, Podfile | не менялись — ничего не включать |
| Android: манифест, разрешения, Play Console | не менялись — ничего не заполнять |
| Сервер (вход, сигналы, погода, перевод) | не менялся |
| Сайт и NPM | обновить — раздел 1 |

## 1. Сайт и Nginx Proxy Manager

Файлы: `ogneliss-site-2026-11-12.zip` (каталог `site/` целиком, страницы уже
собраны — Python не нужен) и `nginx-landing.conf` (тот же, что в архиве
сайта).

1. **Страницы.** Распаковать архив поверх каталога статики (тот, что
   смонтирован в контейнер `dialer-static`), без удаления старых файлов:

   ```bash
   STATIC=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/usr/share/nginx/html"}}{{.Source}}{{end}}{{end}}' dialer-static)
   cd /tmp && rm -rf ogn-site && mkdir ogn-site && cd ogn-site
   unzip -q /root/ogneliss-site-2026-11-12.zip
   sudo cp -a site/. "$STATIC"/
   ```

   Контейнер перезапускать не нужно. Главную и страницы Dialer больше не
   собирать копией `build_site.py` из проекта Dialer — она убирала ссылку на
   Share (подробно — `site/README.md`, «Кто собирает какие страницы»).

2. **NPM.** Хост `ogneliss.ru` → Edit → **Advanced** → сначала скопировать
   текущее содержимое поля себе (вернуть за минуту, если NPM не сохранит),
   затем заменить его **целиком** содержимым `nginx-landing.conf` → Save.
   Новое в файле — раздел `location ^~ /mail/translate/` (модели перевода
   для Windows): раньше его добавляли вручную, и при замене поля целиком он
   бы потерялся. Вход `/oauth` настроен в «Custom locations» — замена поля
   Advanced его не трогает. Файл проверен `nginx -t`.

3. **Проверить** (все строки — `200`; `/push/healthz` — `{"ok":true,…}`):

   ```bash
   for u in "" ru/ mail/ mail/ru/ mail/privacy mail/services.json dialer/ dialer/ru/ numtouch/ \
            share/ share/ru/ share/join/ share/get/ services/ about/ sitemap.xml robots.txt; do
     curl -s -o /dev/null -w "%{http_code} /$u\n" https://ogneliss.ru/$u
   done
   curl -s https://www.ogneliss.ru/push/healthz; echo
   curl -s -o /dev/null -w "%{http_code} /mail/translate/v1/index.json\n" https://ogneliss.ru/mail/translate/v1/index.json
   ```

   В браузере: на главной, на страницах Mail, Dialer, NumTouch и Share в
   шапке — все четыре приложения; в подвале у каждого — «GitHub» и
   «Релизы».

## 2. Сборка

Архив исходников — `ogneliss-mail-2.4.0+151.zip`: распаковать **поверх**
папки проекта (в нём нет `project.pbxproj`, `Runner.entitlements`,
`Signing.xcconfig` и кода базы — ваши настройки Xcode не затираются).
`config/dart_defines.json` в архиве нет — он остаётся ваш.

### 2.1. Android (Windows)

```bat
build_android.bat
```

Собирает App Bundle для Google Play и APK. Нужен Flutter stable (тот же,
что в сборке на GitHub, 3.50) — `flutter upgrade`, если старше.

### 2.2. iPhone и iPad

**Вариант 1 — из Windows по SSH** (один раз настроен `scripts\ios_remote.json`):

```powershell
.\scripts\ios_remote_build.ps1 -Check     # Xcode, Flutter, CocoaPods на Mac
.\scripts\ios_remote_build.ps1 -Upload    # IPA и сразу в TestFlight
```

`config/dart_defines.json` скрипт копирует на Mac сам.

**Вариант 2 — прямо на Mac**: распаковать архив поверх папки проекта,
положить `config/dart_defines.json` (тот же, что на Windows), затем:

```bash
chmod +x scripts/*.sh
scripts/build_ios.sh --check      # окружение
scripts/build_ios.sh --upload     # IPA и выгрузка в TestFlight
#   или: scripts/build_ios.sh --prepare → Xcode: Product → Archive
```

### 2.3. Mac

На том же Mac, в той же папке:

```bash
scripts/build_macos.sh --run       # проверить на этом Mac
scripts/build_macos.sh --upload    # архив и выгрузка в TestFlight (App Store)
#   или: scripts/build_macos.sh --archive → Xcode Organizer
```

Ключ App Store Connect (по желанию): `export ASC_KEY_ID=… ASC_ISSUER_ID=…`,
файл `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`; без него —
учётная запись Xcode. Подробно — `docs/guides/BUILD_IOS.md`,
`docs/guides/TESTFLIGHT.md`.

### 2.4. Выпуск на GitHub

Метка `v2.4.0` на main (коммит слияния PR #97 и этого файла) запускает
сборку всех платформ; текст страницы выпуска («Что нового» RU и EN) берётся
из `STORE_NOTES_2.4.0.md` сам.

## 3. Магазины — «Что нового»

Тексты — в `STORE_NOTES_2.4.0.md`:

- **Google Play** → выпуск → «Что нового» → вставить блок «Google Play —
  все 27 языков» целиком (с тегами `<ru-RU>…</ru-RU>` — Play разложит по
  языкам сам).
- **App Store Connect** (iPhone, iPad и Mac) → версия 2.4.0 → «Что нового в
  этой версии» — для русского, английского, немецкого и французского
  свой блок из раздела «App Store» (без тегов).

## 4. Проверить на устройствах

1. **Рассылка** (например, от еАптеки): после «Показать изображения» видны
   логотип и баннер; чип «Трекеры» показывает только счётчик.
2. **Письмо «Fwd: Занавеси»**: открыть — `image0.jpeg` в списке вложений
   (если нет — долгое нажатие → «Загрузить заново»).
3. **Календарь** на телефоне: шапка «Календарь», переключатель видов,
   пустой период — «Ближайшие 2 месяца свободны»; на компьютере или
   планшете — неделя и колонка ближайших событий; поручения со сроком — в
   календаре.
4. **Настройки**: в «Почте» — «Лента и письма», «Написание и отправка»,
   «Загрузка и вложения», «Перевод»; «Антифишинг» — в «Конфиденциальности»;
   шрифт и масштаб — в «Оформлении».
5. **Уведомления** (два ящика и больше): у письма и у напоминания о встрече
   — значок ящика и его название.
6. **Редактор (Android)**: вставить картинку в текст письма — видна сразу.

## 5. Пробные режимы — решить, включать ли для всех

- **Android 14+ — «Расширенные → Графика → Новое встраивание окна письма
  (HCPP)»**, затем «Перезапустить». Что проверить — `docs/guides/GRAPHICS.md`
  (раздел HCPP): листание сложного письма, шторки поверх письма, редактор,
  поворот. Всё в порядке — скажите, включу по умолчанию в следующей версии.
- **Mac — «Почта → Лента и письма → Открытие писем → Сложные письма — в
  окне браузера»**: рассылка с таблицами должна выглядеть как в браузере;
  окно письма листается внутри себя. Если удобно — включу по умолчанию.
