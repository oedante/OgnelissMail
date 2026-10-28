# Сборка Ogneliss Mail для всех платформ (с 1.6.28)

Один исходный код — пять видов устройств: телефоны Android и iPhone,
планшеты Android и iPad, складные телефоны, Mac, компьютеры с Windows.
Интерфейс подстраивается под **ширину окна**, а не под тип устройства:
iPad в разделённом экране шириной с телефон выглядит как телефон, окно
Windows во весь экран — как большой планшет.

## 1. Что где собирается

| Платформа | Где собирать | Команда | Результат | Подробно |
|---|---|---|---|---|
| Android (телефоны, планшеты, складные) | Windows, Mac, Linux | Android Studio → Build, или `flutter build appbundle --release --dart-define-from-file=config/dart_defines.json` | `build/app/outputs/bundle/release/app-release.aab` → Google Play | `ANDROID_STUDIO.md`, `PRE_BUILD_CHECKLIST.md` |
| iPhone и iPad (одна сборка) | только Mac | `scripts/build_ios.sh` | `build/ios/ipa/*.ipa` → TestFlight / App Store | `BUILD_IOS.md`, `IOS_XCODE_SETUP.md`, `docs/store/APP_STORE.md` |
| Mac | только Mac | `scripts/build_macos.sh --setup` (один раз), затем `scripts/build_macos.sh` | `build/macos/Build/Products/Release/Ogneliss Mail.app` → Mac App Store (через Xcode) | раздел 3 ниже |
| Windows 10/11 | только Windows | `build_windows.bat` | папка `build\windows\x64\runner\Release` | `BUILD_WINDOWS.md` |

`config/dart_defines.json` (секреты входа через Google/Яндекс) — один и тот же
файл для всех платформ; в архив проекта он не входит, переносите его сами.

## 2. App Store: iPhone и iPad

Сборка **одна** на iPhone и iPad (в проекте уже `TARGETED_DEVICE_FAMILY = 1,2`,
все ориентации на iPad, без `UIRequiresFullScreen` — значит, работают
разделённый экран и Slide Over). Порядок, подпись, TestFlight и ответы в
App Store Connect — `docs/store/APP_STORE.md`. Что важно именно для iPad:

1. **Скриншоты iPad обязательны**: 13" (2064×2752). Симулятор «iPad Pro 13"»:
   ```bash
   open -a Simulator            # File → Open Simulator → iPad Pro 13-inch
   scripts/build_ios.sh --run   # выберите iPad в списке устройств
   ```
   Снимайте в **альбомной** ориентации: лента слева, письмо справа, папки
   панелью — это главное отличие от iPhone. Cmd+S — снимок.
2. **Проверка ширин на iPad**: разделённый экран 1/3, 1/2, 2/3 и полный —
   переход «одна колонка → две → три» без пустых мест и обрезанных строк.
3. **Клавиатура iPad** (Magic Keyboard или в симуляторе — клавиатура Mac):
   Cmd+N новое письмо, Cmd+R ответить, Cmd+K палитра, Delete удалить,
   Ctrl+1…5 разделы. Курсор трекпада: строки подсвечиваются, правая кнопка
   (два пальца) — меню письма.

## 3. Mac: два способа

### Способ А — приложение iPad на Mac (без отдельной сборки)

На Mac с Apple Silicon (M1 и новее) приложение iPhone/iPad запускается как
есть. Настройка — в App Store Connect: **Цены и доступность → Приложения
для iPhone и iPad на компьютерах Mac с Apple Silicon** (обычно разрешено по
умолчанию; проверьте, что отмечено «Сделать доступным»).
Плюсы — ноль работы, одна сборка. Минусы — окно в пропорциях iPad, нет
значка в строке меню, на Mac с Intel недоступно. Хорошо для первого шага.

### Способ Б — настоящее приложение для Mac (Mac App Store)

Один раз:
```bash
scripts/build_macos.sh --setup
open macos/Runner.xcworkspace   # Runner → Signing & Capabilities → Team
```
Скрипт создаёт папку `macos/` (в архиве проекта её нет — она живёт у вас и
новым архивом не затирается) и настраивает:
- песочницу Mac App Store: доступ в сеть, к выбранным файлам и «Загрузкам», печать;
- связку ключей (пароли ящиков) — своя группа `com.ogneliss.mail`;
  **без выбранной команды (Team) приложение с этой настройкой не запустится**;
- возврат из входа через Google/Яндекс (`com.ogneliss.mail://oauth`);
- имя «Ogneliss Mail», идентификатор `com.ogneliss.mail` (тот же, что у
  iPhone — в App Store Connect это одна карточка, покупка общая),
  категорию «Производительность», macOS 11+.

Каждая версия:
```bash
scripts/build_macos.sh --run    # проверить на этом Mac
scripts/build_macos.sh          # release-сборка
open macos/Runner.xcworkspace   # Product → Archive → Distribute App → App Store Connect
```
В App Store Connect: в карточке приложения **«+» платформа → macOS**,
скриншоты Mac (от 1280×800, лучше 2880×1800), та же политика и тексты.
«Экспортное соответствие» — как для iPhone (`APP_STORE.md`, §6).

Что на Mac пока отличается:
- нет фоновой проверки почты при закрытом окне (WorkManager/BGTask есть
  только на телефонах); пока окно открыто или свёрнуто в строку меню — почта
  приходит как на компьютере с Windows;
- **Exchange организации за шлюзом ServicePipe на Mac не проверен**: запросы
  идут сетевым стеком Dart, а на iPhone шлюз пропустил только запросы через
  NSURLSession в форме Почты iPhone. Если на Mac будет 403 — перенесём туда
  плагин `ogneliss_native_http` (тот же код Swift для macOS).

## 4. Windows

`BUILD_WINDOWS.md` — установка Visual Studio, Flutter и сборка одной
командой. Для Microsoft Store понадобится упаковка MSIX (пакет `msix`) и
учётная запись разработчика Microsoft — добавим отдельным шагом, когда
решите публиковать.

## 5. Как интерфейс зависит от ширины (с 1.6.28)

| Ширина окна | Вид |
|---|---|
| до 600 | телефон: нижняя панель разделов, письмо — отдельным экраном |
| 600–720 | боковая полоса разделов, одна колонка |
| от 720 (область ленты) | лента и письмо рядом; до выбора справа подсказка «Выберите письмо»; разделитель тянется мышью или пальцем (двойное нажатие — ширина по умолчанию), ширина запоминается |
| от 1040 (область ленты) | ещё и папки постоянной панелью слева; письмо можно перетащить мышью на папку (с «Отменить») |
| от 1200 | боковая полоса разделов с подписями |

Складные телефоны:
- раскрытый «книжкой» с вертикальным сгибом — лента слева от сгиба, письмо
  справа, на сгиб ничего не попадает;
- полураскрытый «ноутбуком» на столе (горизонтальный сгиб) — лента сверху,
  письмо снизу.

## 6. Как проверить без устройств

- **Складные Android**: Android Studio → Device Manager → «+» → Phone →
  *7.6" Fold-in with outer display*, *Pixel 9 Pro Fold* или *Resizable
  (Experimental)*. Положение сгиба: в эмуляторе ⋯ → Virtual sensors →
  Device Posture → *Half-open / Open / Closed*. В «Resizable» есть кнопка
  переключения «телефон / складной / планшет / компьютер».
- **Планшет Android**: *Pixel Tablet* или *Medium Tablet* в Device Manager.
- **iPad**: симулятор *iPad Pro 13"*, *iPad mini* (самый узкий iPad).
- **Windows и Mac**: тяните край окна — переходы на 720 и 1040 должны быть
  плавными, без «прыжков» ленты. Минимальный размер окна — 800×600.
