# «Что нового» — 1.10.4 (135)

1.10.1 (132) 02.11.2026 ушла в тестирование Google Play и TestFlight, для
всех не выпускалась. 1.10.2 (133), 1.10.3 (134) и 1.10.4 (135) — она же с
исправлениями ниже (замечания владельца 02–03.11.2026 после проверки на
телефоне; номера 1.10.3 и 1.10.4 — просьбы владельца). Тексты для магазинов
— те же, что для 1.10.1: пользователи 1.8.12 и 1.9.0 увидят полный список.

Исправлено в 1.10.4 (03.11.2026):

- **Рассылки с резиновой вёрсткой открывались уменьшенными** («По ширине
  экрана» вместо обычного масштаба; письмо Google Cloud): ширина вёрстки
  бралась из атрибута картинки width="640", хотя стиль width:100% делает
  её резиновой, и из условия «@media (min-width:950px)». Теперь ширина в
  стиле важнее атрибута, проценты и auto — не ширина, блоки @media не
  учитываются (тест `test/unit/mail_html_trim_test.dart`).
- **«Закрепить» и «Открепить» в контактах** ничего видимо не меняли у VIP:
  закреплённые и VIP были одним разделом «Закреплённые». Теперь это два
  раздела — «Закреплённые» и под ними «VIP»; у закреплённого — значок
  булавки после имени (тест `test/unit/contacts_top_test.dart`).
- **Ответ на приглашение не доходил организатору при обрыве связи:**
  первый запрос не дошёл до сервера, и приложение сочло, что сервер не
  умеет отправлять ответ, — повтор уходил без отправки, встреча
  принималась только в календаре. Теперь при обрыве повторяется тот же
  запрос; отказ от отправки — только по ответу сервера.
- **Адресная книга Exchange:** встреча со 120 участниками открывала 120
  запросов поиска разом — шлюз перед Exchange отвечал 502 (журнал
  владельца). Теперь не больше трёх запросов сразу; после 502–504 или
  обрыва — пауза 5 минут, и адрес не помечается «без фото» на неделю
  (тест `test/unit/eas_gal_limit_test.dart`).
- **Сбои из журнала:** «Using ref when a widget is unmounted» в настройках
  ящика (выбор проверки почты и уведомлений) и обновление листа языков
  перевода после его закрытия.

Исправлено в 1.10.3:

- **Встречи Exchange не создавались** («Status=6», потом «Status=3» при
  каждой попытке): встреча на весь день уходила с часовым поясом и
  полуночью в UTC, а Exchange по ActiveSync 16 ждёт её без пояса и с датами
  без времени (MS-ASCAL 2.2.2.1) — теперь так; если сервер не примет, один
  повтор в прежнем виде. После отказа сервера приложение теряло новый ключ
  синхронизации календаря, и все следующие встречи получали «Status=3»;
  теперь ключ сохраняется и при ошибке, а отклонённый ключ заменяется новым
  с одним повтором записи. Тест `test/unit/eas_calendar_write_test.dart`.
- **Очередь после удаления ящика:** переносы писем, которые ждали сервер,
  пока ящик удаляли, вставали в очередь удалённого ящика — значок очереди
  показывал 7, а в списке отменять было нечего. Теперь для удалённого ящика
  в очередь ничего не ставится, счётчик считает только существующие ящики,
  старые «сироты» убираются (тест `test/unit/sync_queue_test.dart`).
- **Папка «Шаблоны» Яндекса** (Drafts|template) — служебная, сервер её не
  удаляет («[UNAVAILABLE] DELETE Backend error»): пунктов «Удалить»,
  «Переименовать» и «Переместить» у неё больше нет. Отказ сервера при
  удалении и переименовании папки — понятным текстом, без кода ответа и
  номера запроса.
- **Сбой при отпускании пальца** после долгого нажатия на строку, если
  список уже перестроился (в журнале — «Null check operator» в
  `quick_long_press.dart`).
- **Плотность ленты и «Строк текста»:** плотность больше не перебивает
  число строк; «Компактная» при одной строке ставит тему и текст в одну
  строку.
- **Сообщения и ошибки синхронизации** — плашкой поверх окна сверху; лента
  и письмо больше не сдвигаются вниз и обратно.
- **Задача одной фразой** («Завтра в 15 позвонить Иванову») — предпросмотр,
  потом карточка задачи с заполненными полями. Встреча открывает полный
  редактор, как раньше (просьба владельца).

Добавлено в 1.10.3 (просьбы владельца 02.11.2026):

- **Строк текста в уведомлении** («Настройки → Уведомления»): 3, 5, 8 или
  12 строк — отдельно для рабочих и личных ящиков (рабочий или личный —
  по выбору в настройках ящика). 5 — как было. Для 8 и 12 строк текст
  берётся из письма, если оно уже на телефоне (превью — около 200 знаков).
- **Выбор ящика с портретами:** фото ящика (или логотип службы) с кольцом
  его цвета — в «От» нового письма, строке «Календарь» встречи и её выборе,
  в задачах, контактах, общем ящике, фильтре ящиков календаря, переключателе
  ящиков на нижней панели и в «Проверке почты» (`account_avatar.dart`).
- **Избранное плитками** в стиле «Пуска» Windows 10: широкая плитка
  (значок слева вверху, число справа, подпись внизу) или маленькая —
  только значок; выбор — кнопкой перед переключателем в настройке
  избранного, и для избранных папок (`tile_grid.dart`).
- **Свайп:** у порога срабатывания значок действия становится залитым, за
  ним проступает мягкий круг цвета действия — по положению пальца, без
  вспышек и вибрации. Выключается «Живым свайпом» и «Уменьшить движение».
- **«Экспериментальный функционал»** («Настройки», внизу): функции на
  пробе, по умолчанию выключены. Первая — «Люди в цитатах»: «От», «Кому»,
  «Копия» в шапках цитат Outlook и пересылках Gmail — плашками с портретом,
  нажатие — карточка человека. Разбор — только когда цитата раскрыта
  (`quote_people.dart`, тест `test/unit/quote_people_test.dart`).

Исправлено в 1.10.2:

- **Перевод ответа с цитатой** («Не удалось перевести» в переписке из
  нескольких писем): язык письма определялся по тексту вместе с цитатой;
  цитата на другом языке (или русские строки «От: … Отправлено: …»)
  сбивала ML Kit — он отвечал «und». Теперь язык определяется по свежему
  тексту без цитаты (`replyPartOfPlain`, `splitQuotedHtml`), не вышло —
  по первым строкам; тест `test/unit/translation_sample_test.dart`.
- **Логотипы BIMI в диагностике:** строка «Логотипы BIMI» в пакете
  диагностики — включены ли, сколько доменов с подписью DMARC было в
  ленте, сколько запросов к серверу и что он ответил (только числа, без
  доменов). Раньше удачный логотип в журнал не попадал, и проверить, работает
  ли BIMI, было не по чему.
- **Имена файлов в архивах ZIP по-русски:** «Сжатая папка» Windows и
  7-Zip пишут имена в кодировке DOS (CP866) без флага UTF-8 — имя
  показывалось как «Ŕà¬¨è¨ …». Сырые байты имён читаются из центрального
  каталога архива и распознаются: UTF-8, CP866, CP1251 или CP437
  (`zip_names.dart`); распакованный файл получает правильное имя. Тест
  `test/unit/zip_names_test.dart`.
- **Шрифт интерфейса:** Medeo Sans убран (просьба владельца). На выбор —
  Roboto (по умолчанию), системный шрифт устройства и стандартные
  многоязычные шрифты платформы: Android — Noto Serif, Roboto Condensed;
  iPhone и Mac — Helvetica Neue, Arial, Georgia; Windows — Arial, Calibri,
  Verdana, Georgia; Linux — Noto Sans, DejaVu Sans, Noto Serif
  (`ui_fonts.dart`). Шрифты системные — приложение их не распространяет.
  Кто выбрал Medeo Sans, получает Roboto.
- **Виджеты календаря и «Мой день»:** встреча на весь день — значок
  календаря в колонке времени вместо надписи «Весь день», которая в 52 dp
  обрезалась до «Весь де…» (Android и iPhone; подпись значка — для TalkBack
  и VoiceOver).
- **Замер открытия письма:** этапы «тело в базе / с сервера», «тело
  готово», «цитата», «документ»; если письмо показалось позже 2,5 с, журнал
  окна письма уходит в диагностику одной строкой.

Ниже — что вошло в 1.10.1 и 1.10.0.

Что изменилось (для разработчика):

- **Оформление** («Настройки → Оформление»): темы в духе Telegram, цвет
  акцента, оттенок ленты, скругление, плотность ленты (компактная, обычная,
  просторная), анимация открытия письма и закрытие свайпом вниз (с 1.10.1
  включены по умолчанию).
- **Окно письма:** тёмная тема без инверсии — своё тёмное оформление
  письма, картинки и логотипы в исходных цветах. Очень длинное письмо
  показывается началом, ниже — «Показать письмо целиком».
- **Даты в тексте письма** нажимаются (WebView, простой показ и простой
  текст): карточка «Встреча», «Напоминание», «Копировать», «Открыть в
  календаре». Встреча создаётся из одной фразы с предпросмотром
  («завтра в 15:00 созвон на час»). Разбор фраз — русский и английский;
  настройка — «Почта → Даты в тексте письма».
- **Доставка:** у SMTP-серверов с DSN (RFC 3461) запрашивается отчёт о
  доставке; возвраты (bounce, DSN) связываются с отправленным письмом —
  красная отметка в ленте, строка состояния и отчёт в письме, своё
  уведомление. Схема базы 27 (таблица delivery_status).
- **Уведомления как в мессенджерах:** отправитель с фото или инициалами.
  Android — канал ogneliss/messenger, ярлыки бесед
  для VIP-отправителей. iPhone — Communication Notifications
  (INSendMessageIntent); возможность включает владелец в Xcode.
- **Сигналы сервера на Android (FCM):** будильник на сервере будит
  приложение через Firebase Cloud Messaging без плагинов Flutter Firebase.
  Без Firebase и ключа на сервере выключено, остальное работает.
- **Перевод на устройстве:** входящие письма (полоса «Перевести», переведённый
  вид) и свой текст в письме (заменить или оставить оба). Android — Google
  ML Kit, iPhone и iPad — Apple Translation (iOS 18+). Текст писем в
  интернет не уходит.
- **Логотипы отправителей (BIMI):** логотип домена с проверенной политикой
  DMARC — через сервер владельца (`/bimi` в OAuth-прокси; на сервер уходит
  только домен), SVG очищается, ответы кэшируются. Настройка — «Почта →
  Логотипы отправителей (BIMI)».
- **Siri и «Команды» (iOS), ярлыки и App Actions (Android):** новое письмо
  (с адресатом и темой), встреча, напоминание, «Мой день», непрочитанные,
  VIP, поиск.
- **IMAP:** быстрая синхронизация по CONDSTORE/QRESYNC, мгновенные
  уведомления по NOTIFY. Новый ящик синхронизируется сразу после
  добавления.
- **iPad и компьютер (D1):**
  - ширина панели папок меняется перетаскиванием;
  - выбранные письма перетаскиваются на папку разом, мышью сразу, пальцем и
    пером — удержанием выбранной строки;
  - файлы из Проводника или Finder на окне письма становятся вложениями;
  - на компьютере письмо открывается в отдельном окне.

  Новые зависимости: desktop_drop 0.8.4 и desktop_multi_window 0.3.1, обе
  Apache-2.0.
- **Блокировка отправителя** (меню письма и карточка в ленте): письма с
  адреса или домена — в «Спам» без уведомления, уже полученные — по выбору;
  где сервер умеет (Sieve, Exchange через Graph или EWS) — ещё и правилом на
  сервере. Домен общей почтовой службы (gmail.com и т. п.) заблокировать
  нельзя — только адрес.
- **Чистка по отправителю** (как Sweep в Outlook): удалить все письма из
  «Входящих», удалять и будущие, оставлять только последнее, удалять старше
  10 дней. Список блокировок и правил чистки — «VIP и правила».
- **Предупреждение о подделке отправителя:** похожие домены и у личных
  ящиков (домены контактов, банки, магазины, госслужбы, почтовые службы;
  punycode и кириллица в домене), имя как у контакта с чужого адреса, ответ
  (Reply-To) на адрес другой организации.
- **Сигналы на Android без сервисов Google — UnifiedPush:** распространитель
  на телефоне (ntfy и др.), выбор в «Уведомления → Как приходят сигналы»;
  сервер шлёт сигнал, зашифрованный по Web Push (RFC 8291), с подписью
  VAPID. Новые зависимости — UnifiedPush connector 3.3.5 (Apache-2.0) с
  Google Tink (Apache-2.0) и protobuf-java (BSD-3-Clause).
- **Клавиши на компьютере — как в Outlook:** Ctrl+Q/U, Insert, Backspace,
  Ctrl+P, F3, F9, Ctrl+Shift+M, Ctrl+Shift+I (к прежним Ctrl+N/R/F,
  Ctrl+Enter, Delete).
- **IMAP по проверке на настоящем сервере:** удаление открытой папки больше
  не рвёт соединение; в режиме «Полное письмо с вложениями» есть список
  вложений; Message-ID черновика сохраняется.
- **CI:** проверка лицензий зависимостей и уязвимостей (OSV-Scanner); по
  запросу — тесты и замеры скорости на эмуляторе Android.
- **Сервер:** OAuth-прокси с body-parser 1.20.9 и qs 6.16.2 (уязвимости
  GHSA-27r3-jxmh-p828, GHSA-6pq8-jhm2-2vcw), точка `/bimi`; служба сигналов
  умеет FCM (`install-push-relay.sh install --fcm-service-account …`) и UnifiedPush (Web Push, ключ VAPID создаёт установщик).

Исправлено в 1.10.1:

- **Письмо не показывалось при выключенной строке «Ответить…»:** панель
  кнопок (bottomNavigationBar) растягивалась на весь экран — кнопки стояли
  вверху, под строкой состояния, белая панель закрывала письмо. Причина —
  `ReadableWidth` (Align) в панели с 1.8.13: без `heightFactor` он
  занимает всю данную высоту. Теперь `heightFactor: 1`; тест
  `test/widget/mail_bar_layout_test.dart`.
- **Backspace и Delete при наборе ответа:** горячие клавиши письма
  (Backspace — в архив, Delete — удалить, Insert — флажок) срабатывали, пока
  стирали текст в строке «Ответить…» — с клавиатуры компьютера и с экранной
  клавиатуры Android, которая шлёт Backspace клавишей, когда поле пусто.
  Теперь клавиши без Ctrl не действуют, пока в фокусе поле ввода
  (`TypingAwareShortcuts`); Delete в общих сочетаниях компьютера больше не
  забирает клавишу у полей ввода.
- **Анимация открытия письма включена по умолчанию** (просьба владельца
  02.11.2026 после проверки на телефоне): портрет и тема перелетают в
  письмо, на телефоне письмо закрывается свайпом вниз. Выключается в
  «Настройки → Оформление»; «Уменьшить движение» и системное «Убрать
  анимацию» выключают её, как и раньше. Кто выключил её сам — у того
  остаётся выключенной.
- **Тест скорости дат** — лучший из пяти замеров (при полном прогоне
  `flutter test` на Windows один замер выходил за предел).

Файлы iOS: AppDelegate.swift (перевод, App Intents), Info.plist. Файлы
Android: манифест, shortcuts.xml, приёмник FCM, TranslationBridge.kt.
Файлы project.pbxproj и Runner.entitlements не менялись. Что включить в
Xcode — `guides/IOS_COMMUNICATION_NOTIFICATIONS.md`, `guides/IOS_SHORTCUTS.md`,
`guides/TRANSLATION_SETUP.md`.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Темы оформления, плотность ленты, тёмные письма без инверсии
• Перевод писем и своего текста на устройстве (iOS 18 и новее)
• Даты в письме нажимаются: встреча или напоминание в одно касание
• Заблокировать отправителя и «Чистка» его писем
• Предупреждение о подделке отправителя и похожих доменах
• Недоставленные письма отмечены, видна причина
• Уведомления с фото отправителя, логотипы проверенных отправителей (BIMI)
• Siri и «Команды»: новое письмо, встреча, непрочитанные, «Мой день»
• iPad: панель папок своей ширины, письма перетаскиваются на папку
• IMAP: быстрая синхронизация, новый ящик загружается сразу
</ru-RU>
<en-US>
• Colour themes, list density, dark messages without inversion
• Translate messages and your own text on the device (iOS 18 or later)
• Tap a date in a message to create a meeting or reminder
• Block a sender and Sweep their messages
• Warnings about spoofed senders and lookalike domains
• Undelivered messages are marked, with the reason
• Notifications with the sender's photo; logos of verified senders (BIMI)
• Siri and Shortcuts: new email, meeting, unread, My Day
• iPad: resizable folder pane, drag messages onto a folder
• IMAP: fast sync; a new mailbox loads right away
</en-US>
<de-DE>
• Farbschemata, Listendichte, dunkle Nachrichten ohne Invertierung
• Nachrichten und eigene Texte auf dem Gerät übersetzen (ab iOS 18)
• Datum in einer Nachricht antippen: Termin oder Erinnerung anlegen
• Absender blockieren und seine Nachrichten bereinigen
• Warnungen vor gefälschten Absendern und ähnlich aussehenden Domänen
• Nicht zugestellte Nachrichten werden samt Grund markiert
• Benachrichtigungen mit Foto des Absenders; Logos verifizierter Absender (BIMI)
• Siri und Kurzbefehle: Neue E-Mail, Termin, Ungelesen, Mein Tag
• iPad: Ordnerleiste in verstellbarer Breite, Nachrichten auf Ordner ziehen
• IMAP: schnelle Synchronisierung; neues Postfach wird sofort geladen
</de-DE>
<fr-FR>
• Thèmes de couleurs, densité de liste, messages sombres sans inversion
• Traduction des messages et de vos textes sur l’appareil (iOS 18 ou ultérieur)
• Touchez une date dans un message : réunion ou rappel en un geste
• Bloquer un expéditeur et nettoyer ses messages
• Alertes contre l’usurpation d’expéditeur et les domaines trompeurs
• Messages non distribués marqués, avec la cause
• Notifications avec photo de l’expéditeur ; logos des expéditeurs vérifiés (BIMI)
• Siri et Raccourcis : nouveau message, événement, non lus, Ma journée
• iPad : volet des dossiers ajustable, glisser un message vers un dossier
• IMAP : synchronisation rapide ; une nouvelle boîte se charge aussitôt
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 480.

```
<ru-RU>
• Темы оформления, плотность ленты, тёмные письма без инверсии
• Перевод писем и своего текста на устройстве
• Дата в письме — встреча или напоминание в одно касание
• Блокировка отправителя и чистка его писем
• Предупреждение о подделке отправителя
• Отметка у недоставленных писем, логотипы BIMI
• Уведомления с фото отправителя
• Сигналы почты и без сервисов Google (UnifiedPush)
• Ярлыки на значке; на планшете — панели и перетаскивание
</ru-RU>
<en-US>
• Colour themes, list density, dark mail without inversion
• Translate mail and your own text on the device
• Tap a date in a message to add a meeting or reminder
• Block a sender and sweep their mail
• Warnings about spoofed senders
• Undelivered mail is marked; BIMI sender logos
• Notifications with the sender's photo
• Mail signals without Google services (UnifiedPush)
• App icon shortcuts; tablets: panes and drag and drop
</en-US>
<de-DE>
• Farbschemata, Listendichte, dunkle Mails ohne Invertierung
• Mails und eigene Texte auf dem Gerät übersetzen
• Datum in Nachricht antippen: Termin oder Erinnerung anlegen
• Absender blockieren und seine Mails bereinigen
• Warnungen vor gefälschten Absendern
• Nicht zugestellte Mails markiert; BIMI-Absenderlogos
• Benachrichtigungen mit Foto des Absenders
• Mail-Signale ohne Google-Dienste (UnifiedPush)
• App-Verknüpfungen; Tablet: Bereiche, Drag-and-drop
</de-DE>
<fr-FR>
• Thèmes de couleurs, densité de liste, e-mails sombres sans inversion
• Traduction des e-mails et de vos textes sur l’appareil
• Touchez une date du message : réunion ou rappel
• Bloquer un expéditeur et nettoyer ses e-mails
• Alertes d’usurpation d’expéditeur
• Messages non distribués marqués ; logos BIMI
• Notifications avec photo de l’expéditeur
• Signaux courrier sans services Google (UnifiedPush)
• Raccourcis de l’icône ; tablette : volets, glisser-déposer
</fr-FR>
<ar>
• أنساق ألوان وكثافة القائمة ورسائل داكنة بلا عكس للألوان
• ترجمة الرسائل ونصوصك على الجهاز
• اضغط على تاريخ في الرسالة لإضافة اجتماع أو تذكير
• حظر المرسل وتنظيف رسائله
• تحذيرات من انتحال هوية المرسل
• تمييز الرسائل غير المسلَّمة؛ شعارات BIMI للمرسلين
• إشعارات مع صورة المرسل
• إشارات البريد بدون خدمات Google (UnifiedPush)
• اختصارات الأيقونة؛ الأجهزة اللوحية: الألواح والسحب والإفلات
</ar>
<hu-HU>
• Színsémák, listasűrűség, sötét levelek inverzió nélkül
• Levelek és saját szövegek fordítása az eszközön
• Koppintson egy dátumra: értekezlet vagy emlékeztető
• Feladó letiltása és leveleinek takarítása
• Figyelmeztetés hamisított feladóra
• Ki nem kézbesített levelek jelölve; BIMI-logók
• Értesítések a feladó fotójával
• Levéljelzések Google-szolgáltatások nélkül (UnifiedPush)
• Ikon-parancsikonok; táblagép: panelek, húzás
</hu-HU>
<vi>
• Chủ đề màu, mật độ danh sách, thư tối không đảo màu
• Dịch thư và văn bản của bạn ngay trên thiết bị
• Chạm vào ngày trong thư để thêm cuộc họp hoặc lời nhắc
• Chặn người gửi và dọn dẹp thư của họ
• Cảnh báo người gửi giả mạo
• Đánh dấu thư chưa gửi được; logo người gửi BIMI
• Thông báo kèm ảnh người gửi
• Tín hiệu thư không cần dịch vụ Google (UnifiedPush)
• Lối tắt ở biểu tượng; máy tính bảng: ngăn, kéo thả
</vi>
<da-DK>
• Farvetemaer, listetæthed, mørke mails uden invertering
• Oversæt mails og din egen tekst på enheden
• Tryk på en dato i en besked for at tilføje et møde eller en påmindelse
• Blokér afsender og ryd op i vedkommendes mails
• Advarsler om falske afsendere
• Ikke-leverede mails markeres; BIMI-logoer
• Notifikationer med afsenderens foto
• Mailsignaler uden Google-tjenester (UnifiedPush)
• Genveje på appikonet; tablet: paneler, træk og slip
</da-DK>
<iw-IL>
• ערכות צבעים, צפיפות רשימת הדואר, הודעות כהות ללא היפוך צבעים
• תרגום הודעות והטקסט שלך ישירות במכשיר
• הקשה על תאריך בהודעה מוסיפה פגישה או תזכורת
• חסימת שולח וניקוי כל ההודעות שלו
• אזהרות על שולחים מתחזים
• הודעות שלא נמסרו מסומנות; לוגו BIMI של שולחים
• התראות עם תמונת השולח
• אותות דואר גם ללא שירותי Google (UnifiedPush)
• קיצורי דרך בסמל האפליקציה; בטאבלט: חלוניות וגרירה
</iw-IL>
<id>
• Tema warna, kerapatan daftar, email gelap tanpa inversi
• Terjemahkan email dan teks Anda sendiri di perangkat
• Ketuk tanggal di pesan untuk menambah rapat atau pengingat
• Blokir pengirim dan bersihkan emailnya
• Peringatan pengirim palsu
• Email tak terkirim ditandai; logo pengirim BIMI
• Notifikasi dengan foto pengirim
• Sinyal email tanpa layanan Google (UnifiedPush)
• Pintasan ikon aplikasi; tablet: panel, seret-lepas
</id>
<es-ES>
• Temas de color, densidad de lista, correo oscuro sin inversión
• Traducción de correos y textos en el dispositivo
• Toca una fecha para crear una reunión o recordatorio
• Bloqueo de remitentes y limpieza de sus mensajes
• Avisos de remitentes suplantados
• Mensajes no entregados marcados; logotipos BIMI
• Notificaciones con la foto del remitente
• Señales de correo sin servicios de Google (UnifiedPush)
• Atajos del icono; en tablets: paneles y arrastrar
</es-ES>
<it-IT>
• Temi colore, densità dell’elenco, posta scura senza inversione
• Traduzione di posta e testi sul dispositivo
• Tocca una data per creare riunione o promemoria
• Blocco dei mittenti e pulizia dei loro messaggi
• Avvisi sui mittenti falsificati
• Messaggi non recapitati contrassegnati; loghi BIMI
• Notifiche con la foto del mittente
• Segnali di posta anche senza servizi Google (UnifiedPush)
• Scorciatoie sull’icona; su tablet: pannelli e trascinamento
</it-IT>
<zh-CN>
• 配色主题、列表密度、无需反色的深色邮件
• 在设备上翻译邮件和你自己输入的文字
• 点按邮件中的日期，即可添加会议或提醒
• 阻止发件人并清理其邮件
• 伪造发件人警告
• 未送达的邮件会有标记；BIMI 发件人徽标
• 通知显示发件人头像
• 没有 Google 服务也能收到邮件信号（UnifiedPush）
• 应用图标快捷方式；平板：分栏和拖放
</zh-CN>
<ko-KR>
• 색상 테마, 목록 밀도, 색 반전 없는 다크 메일
• 기기에서 메일과 직접 쓴 글 번역
• 메일 속 날짜를 탭해 회의나 알림 추가
• 보낸 사람 차단 및 해당 메일 정리
• 보낸 사람 사칭 경고
• 전달되지 않은 메일 표시, BIMI 보낸 사람 로고
• 보낸 사람 사진이 표시되는 알림
• Google 서비스 없이도 메일 신호 수신(UnifiedPush)
• 앱 아이콘 바로가기, 태블릿은 패널과 끌어서 놓기
</ko-KR>
<nl-NL>
• Kleurthema’s, lijstdichtheid, donkere e-mail zonder inversie
• E-mail en eigen tekst vertalen op het apparaat
• Tik op een datum voor een afspraak of herinnering
• Afzender blokkeren en zijn berichten opruimen
• Waarschuwingen voor vervalste afzenders
• Onbezorgde berichten gemarkeerd; BIMI-logo’s
• Meldingen met de foto van de afzender
• E-mailsignalen ook zonder Google-services (UnifiedPush)
• Snelkoppelingen op het pictogram; tablet: deelvensters, slepen
</nl-NL>
<no-NO>
• Fargetemaer, listetetthet, mørk e-post uten invertering
• Oversett e-post og egen tekst på enheten
• Trykk på en dato i en melding for å legge til møte eller påminnelse
• Blokker en avsender og rydd opp i meldingene deres
• Advarsler om forfalskede avsendere
• Uleverte meldinger merkes; BIMI-logoer for avsendere
• Varsler med avsenderens bilde
• E-postsignaler også uten Google-tjenester (UnifiedPush)
• Snarveier på app-ikonet; nettbrett: ruter og dra og slipp
</no-NO>
<pl-PL>
• Motywy kolorów, gęstość listy, ciemne wiadomości bez inwersji
• Tłumaczenie wiadomości i tekstów na urządzeniu
• Dotknij daty, by dodać spotkanie lub przypomnienie
• Blokowanie nadawców i porządkowanie ich wiadomości
• Ostrzeżenia o fałszywych nadawcach
• Niedostarczone wiadomości oznaczone; logotypy BIMI
• Powiadomienia ze zdjęciem nadawcy
• Sygnały poczty także bez usług Google (UnifiedPush)
• Skróty na ikonie; na tabletach: panele i przeciąganie
</pl-PL>
<pt-BR>
• Temas de cor, densidade da lista, e-mails escuros sem inversão
• Tradução de e-mails e textos no dispositivo
• Toque em uma data para criar reunião ou lembrete
• Bloqueio de remetentes e limpeza de mensagens
• Alertas sobre remetentes falsificados
• Mensagens não entregues marcadas; logotipos BIMI
• Notificações com a foto do remetente
• Sinais de e-mail também sem serviços do Google (UnifiedPush)
• Atalhos no ícone; em tablets: painéis e arrastar e soltar
</pt-BR>
<ro>
• Teme de culoare, densitatea listei, mesaje întunecate fără inversare
• Traducere pe dispozitiv: mesaje și textul tău
• Atinge o dată dintr-un mesaj pentru întâlnire sau memento
• Blocarea expeditorului și curățarea mesajelor lui
• Avertizări la expeditori falsificați
• Mesaje nelivrate marcate; sigle BIMI
• Notificări cu fotografia expeditorului
• Semnale de e-mail și fără servicii Google (UnifiedPush)
• Comenzi rapide pe pictogramă; tabletă: panouri, tragere
</ro>
<sk>
• Farebné motívy, hustota zoznamu, tmavé správy bez inverzie
• Preklad správ a vášho textu v zariadení
• Ťuknutím na dátum v správe pridáte stretnutie alebo pripomienku
• Blokovanie odosielateľa a čistenie jeho správ
• Varovania pred sfalšovanými odosielateľmi
• Nedoručené správy sú označené; logá odosielateľov BIMI
• Upozornenia s fotkou odosielateľa
• Signály pošty aj bez služieb Google (UnifiedPush)
• Skratky na ikone aplikácie; na tablete: panely a presúvanie
</sk>
<th>
• ธีมสี ความหนาแน่นของรายการ อีเมลโหมดมืดโดยไม่กลับสี
• แปลอีเมลและข้อความของคุณบนอุปกรณ์
• แตะวันที่ในอีเมลเพื่อเพิ่มการประชุมหรือเตือนความจำ
• บล็อกผู้ส่งและล้างอีเมลของผู้ส่ง
• เตือนเมื่อผู้ส่งถูกปลอมแปลง
• ทำเครื่องหมายอีเมลที่ส่งไม่สำเร็จ โลโก้ผู้ส่ง BIMI
• การแจ้งเตือนพร้อมรูปของผู้ส่ง
• สัญญาณอีเมลแม้ไม่มีบริการ Google (UnifiedPush)
• ทางลัดบนไอคอนแอป บนแท็บเล็ต: แผงและการลาก
</th>
<tr-TR>
• Renk temaları, liste yoğunluğu, ters çevirmesiz koyu iletiler
• İletileri ve kendi metninizi cihazda çevirme
• İletideki tarihe dokunup toplantı veya hatırlatıcı ekleyin
• Göndereni engelleme ve iletilerini temizleme
• Sahte göndericilere karşı uyarılar
• Teslim edilemeyen iletiler işaretlenir; BIMI logoları
• Gönderenin fotoğrafıyla bildirimler
• Google hizmetleri olmadan da posta sinyalleri (UnifiedPush)
• Simge kısayolları; tablette: paneller ve sürükle-bırak
</tr-TR>
<fi-FI>
• Väriteemat, luettelon tiheys, tummat viestit ilman käänteisvärejä
• Viestien ja oman tekstin kääntäminen laitteella
• Napauta viestin päivämäärää ja lisää kokous tai muistutus
• Lähettäjän esto ja hänen viestiensä siivous
• Varoitukset väärennetyistä lähettäjistä
• Toimittamattomat viestit merkitään; BIMI-logot
• Ilmoitukset lähettäjän kuvalla
• Postisignaalit ilman Google-palveluita (UnifiedPush)
• Kuvakkeen pikavalinnat; tabletilla: ruudut, vetäminen
</fi-FI>
<hi-IN>
• रंग थीम, सूची घनत्व, बिना इनवर्ज़न के डार्क मेल
• डिवाइस पर ईमेल और अपने टेक्स्ट का अनुवाद
• ईमेल में तारीख पर टैप करके मीटिंग या रिमाइंडर जोड़ें
• प्रेषक को ब्लॉक करें और उसके ईमेल की सफ़ाई करें
• नकली प्रेषकों की चेतावनियां
• न पहुंचे ईमेल पर निशान; BIMI प्रेषक लोगो
• प्रेषक की फ़ोटो के साथ सूचनाएं
• Google सेवाओं के बिना भी मेल सिग्नल (UnifiedPush)
• ऐप आइकन शॉर्टकट; टैबलेट पर: पैनल और ड्रैग-ड्रॉप
</hi-IN>
<cs-CZ>
• Barevné motivy, hustota seznamu, tmavé zprávy bez inverze
• Překlad zpráv a vašeho textu v zařízení
• Klepnutím na datum ve zprávě přidáte schůzku nebo připomenutí
• Blokování odesílatele a čištění jeho zpráv
• Varování před padělanými odesílateli
• Nedoručené zprávy jsou označené; loga odesílatelů BIMI
• Oznámení s fotkou odesílatele
• Signály pošty i bez služeb Google (UnifiedPush)
• Zkratky na ikoně aplikace; na tabletu: panely a přetahování
</cs-CZ>
<sv-SE>
• Färgteman, listtäthet, mörk e-post utan inversion
• Översätt e-post och din egen text på enheten
• Tryck på ett datum i meddelandet för möte eller påminnelse
• Blockera en avsändare och rensa dennes e-post
• Varningar för förfalskade avsändare
• Ej levererad e-post markeras; BIMI-logotyper
• Aviseringar med avsändarens foto
• E-postsignaler även utan Google-tjänster (UnifiedPush)
• Genvägar på appikonen; på surfplatta: paneler och dra och släpp
</sv-SE>
<ja-JP>
• カラーテーマ、リストの密度、反転しないダークメール
• メールと入力したテキストをデバイス上で翻訳
• メール内の日付をタップして会議やリマインダーを追加
• 差出人をブロックし、そのメールをクリーンアップ
• なりすましの差出人を警告
• 未配信のメールにマーク、BIMI の差出人ロゴ
• 差出人の写真付き通知
• Google サービスなしでもメールのシグナルを受信 (UnifiedPush)
• アプリアイコンのショートカット、タブレットではペインとドラッグ＆ドロップ
</ja-JP>
```
