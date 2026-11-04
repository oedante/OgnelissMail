# «Что нового» — 1.11.0 (137)

Номер — просьба владельца 03.11.2026 («как всё закончим, версию поднимаем до
1.11.0 и выпускаем»). Архив 1.10.5 (136) отдан 03.11.2026; что вошло в
1.10.5 и раньше — `STORE_NOTES_1.10.5.md`.

Тексты для магазинов — общий список с 1.8.12 и 1.9.0 (у пользователей
магазинов пока они) и главное из 1.11.0: настройки организации (MDM), вид
как в Outlook на планшете и компьютере, перевод темы письма. Строки про
недоставленные письма, BIMI и ярлыки значка уступили им место.

Добавлено и исправлено в 1.11.0 (после архива 1.10.5):

- **Перевод писем на Mac** (просьба владельца 03.11.2026): как на iPhone —
  Apple Translation на устройстве, macOS 15 и новее; языки скачивает сама
  macOS. Свой файл окна `tool/desktop/macos/MainFlutterWindow.swift`
  сборка кладёт поверх созданного `flutter create` (проект Xcode не
  меняется). На Windows и Linux встроенного перевода на устройстве нет —
  перевода там по-прежнему нет.
- **Планшет и компьютер — как в Outlook** (просьба владельца 03.11.2026):
  - над письмом — панель команд с подписями: «Ответить», «Ответить
    всем», «Переслать» | «Удалить», «Архив», «Переместить» | «Флаг»,
    «Прочитано/Не прочитано», «Позже» | «Ещё». Подписи — пока помещаются
    (по важности), остальные — значками с подсказкой;
  - отправитель и дата — под темой письма, телефонной нижней панели нет;
    внизу — строка «Ответить…» со своей кнопкой;
  - «Переместить» — новое действие письма: выбор папки ящика;
  - в ленте при наведении мыши — кнопки «Удалить», «Архив»,
    «Прочитано», «Флаг» на месте даты;
  - поиск — полем «Поиск» в шапке ленты;
  - заголовок ленты и выбор папки — переведённым именем («Входящие», а не
    «INBOX» у Gmail).
  Телефон — без изменений. Снимки — `tool/shots` («лента и письмо —
  desktop/tablet»).
- **Порядок правил сортировки при перетаскивании вниз** вставал на одно
  место выше (после перехода на новое API перетаскивания индекс
  пересчитывался дважды). Перетаскивание в списках — снова через
  `onReorder`: код собирается и Flutter для ОС «Аврора» 3.41
  (`docs/guides/AURORA.md` — оценка и план версии для «Авроры»).
- **Управление со стороны организации (MDM)** (решение владельца
  03.11.2026): приложение принимает настройки организации — Android
  Enterprise (управляемые настройки) и iOS Managed App Configuration.
  Ящик заранее вписан на экране входа (адрес, сервер, логин, домен),
  только ящики разрешённых доменов, обязательный PIN приложения нужной
  длины, запрет снимков экрана (Android), «Поделиться», сохранения, PDF
  и печати, открытия вложений в других приложениях, копирования текста
  писем, уведомления без отправителя и темы. Что включено — в
  «Настройки → Управляется организацией» с контактом ИТ-поддержки;
  запрещённое действие — строка «Запрещено политикой вашей организации».
  Ключи для ИТ — `docs/guides/MDM.md`. Тесты
  `test/unit/managed_config_test.dart`,
  `test/widget/managed_policy_section_test.dart`.
- **Перевод письма — с темой; можно оставить оба текста** (просьба
  владельца 03.11.2026): тема переводится вместе с письмом («RE:/FW:»
  остаются как есть). «Настройки → Перевод → Показ перевода письма»:
  «Заменить текст» (по умолчанию, как было), «Оставить оба текста:
  сначала оригинал» или «…сначала перевод» — тема второй строкой мелко
  под первой, текст второй под тонкой линией с подписью («Переведено:
  английский → русский» или «Язык письма: английский»). Переписка
  (цитата) — после обоих ответов: в свёрнутом письме видны оба. Тесты
  `test/unit/mail_bilingual_test.dart`, `mail_translation_subject_test.dart`.
- **VIP в уведомлении — без жирной звёздочки** (замечание владельца
  03.11.2026: «звёздочка в уведомлении у VIP жирным шрифтом не очень
  выглядит»): в заголовке только имя. Акцент — золотое кольцо вокруг
  портрета и золотая звёздочка на нём внизу справа (Android и iPhone), на
  Android ещё золотые значок и название приложения в шапке. Вид «как в
  мессенджерах» выключен (портрета нет) — «VIP» мелко в шапке
  уведомления. Тесты `messenger_notifications_test.dart`,
  `notification_text_test.dart`.
- **В беседе не было черновика ответа** (замечание владельца 03.11.2026:
  «в ленте черновик видно, в папке черновик есть, а в беседе он
  отсутствует»): черновик хранится на сервере без заголовков ответа, и
  у него своя беседа. Экран беседы и блок «Беседа» под письмом теперь
  находят его так же, как «Черновик: …» в ленте, — по связи «письмо →
  черновик» и теме, а свой черновик на устройстве — по исходному письму.
  Карточка — «Черновик» красным и кому, справа, как свои письма; нажатие
  открывает редактор; свайпов и карточки действий у черновика нет.
  «Прочитать все» и «Удалить беседу» черновик не трогают. Тест
  `test/unit/conversation_drafts_test.dart`.
- **Блок «Беседа» под текстом письма** (просьба владельца 03.11.2026
  проверить его): нажатие на письмо только разворачивало превью — открыть
  соседнее письмо или черновик оттуда было нельзя. Теперь нажатие
  открывает письмо (черновик — в редакторе), стрелка справа — больше
  текста; портреты — как в шапке письма (фото из контактов, логотип
  BIMI); превью одной строкой («Hi Oedante, Congrats! …», а не одно «Hi
  Oedante,»); текущее письмо не разворачивается — его текст и так выше.
  Тест `test/widget/conversation_thread_view_test.dart`.
- **«Люди в цитатах» включены по умолчанию, имена — «Фамилия И.О.»**
  (решение владельца 03.11.2026): настройка перешла из «Экспериментального
  функционала» в «Настройки → Почта → Работа с письмами → Люди в цитатах»:
  «Фамилия И.О.» (по умолчанию; без отчества — «Фамилия И.»),
  «Полностью» или «Выключено». Порядок слов в письмах разный — «Имя
  Фамилия» («Олег Ермишин» → «Ермишин О.») и «Имя Отчество Фамилия»
  сокращаются верно; где не ясно, что фамилия («John Smith», «Нестор
  Махно»), — имя как в письме. Полное имя — в подсказке плашки и в
  карточке человека. Выключившие функцию в 1.10.3–1.10.4 вручную её
  выключенной и увидят. Раздел «Экспериментальный функционал» пока пуст
  («Сейчас на пробе ничего нет»). Тесты `test/unit/person_name_test.dart`,
  `quote_people_mode_test.dart`, `quote_people_test.dart`,
  `test/widget/quote_people_native_test.dart`.
- **Значок программы на компьютере был стандартным значком Flutter**
  (сборка Windows из GitHub Actions, замечание владельца 03.11.2026): папки
  windows/, macos/, linux/ создаёт при сборке `flutter create`, со своим
  значком. Теперь сборка кладёт поверх наш: Windows — exe, окно и панель
  задач (`assets/icons/tray_icon.ico`, скруглённая плитка 16–256), macOS —
  значки по сетке Big Sur (`assets/branding/macos/`), Linux — значок окна
  при запуске. Делают это CI, `scripts/build_windows.ps1`,
  `scripts/build_macos.sh`, `scripts/setup.ps1`; файлы собирает
  `tool/branding/make_icon_v5.py desktop`. Заодно `scripts/setup.ps1`
  больше не перезаписывает значки Android прежним синим вариантом и не
  заменяет значок трея квадратом.
- **Боковая панель на большом экране занимала слишком много места**
  (замечание владельца 03.11.2026): на окне от 1200 точек разделы стояли
  развёрнутой панелью ~230 точек. Теперь всегда узкая полоса — значок и
  подпись под ним (~72–90 точек), как у Outlook и Gmail на компьютере;
  панель папок по умолчанию 240 вместо 272 (ширина, заданная
  разделителем, сохраняется). Выбор темы внизу панели папок, если подписи
  не помещаются, — только значками с подсказкой (раньше «Светл…»; тест
  `test/widget/theme_quick_switch_test.dart`).
- **Ответ в панели чтения** (планшет и компьютер, как в Outlook; просьба
  владельца 03.11.2026): «Ответить», «Ответить всем» и «Переслать» — на
  панели команд, строке «Ответить…» внизу и клавишами Ctrl+R,
  Ctrl+Shift+R, Ctrl+F — открывают редактор прямо на месте письма, лента
  остаётся видна. Крестик или отправка — снова письмо
  (`lib/widgets/common/pane_navigator.dart`). На телефоне — как было,
  отдельным экраном. Снимок — `tool/shots` («лента и ответ в панели —
  desktop»).
- **«Избранное» — вверху панели папок** (планшет и компьютер): как
  «Избранное» в Outlook — над папками ящиков; выбор темы — внизу панели. На
  телефоне в выдвижном меню — как было.
- **Флажок выбора при наведении мыши** (компьютер): портрет в строке ленты
  под мышью становится флажком; нажатие выбирает письмо и включает выбор
  нескольких писем, как в Outlook.
- **Письмо Google Play по-русски предлагалось перевести «с болгарского»**
  (замечание владельца 03.11.2026): определитель языка ML Kit на Android
  путает русский с болгарским, когда в тексте много латиницы («Play
  Console», «non-trader»). Теперь кириллица, которую определитель назвал
  болгарским, македонским, сербским, украинским или белорусским, но с
  буквами «ы», «э», «ё» (около 2 % букв, как в русском тексте) и без букв,
  которых нет в русском («і», «ў», «ј» и др.), — русский. Проверка — на
  всех платформах (`refineCyrillicLang`, тест
  `test/unit/translation_test.dart`).
- **Пустое место вверху письма Google Play** (то же замечание): там стоит
  логотип Google Play высотой 64 точки с play.google.com; картинки письма
  были разрешены, но с телефона не загрузились — место под логотип
  осталось пустым. С этого же сервера картинки у письма Google Play,
  которое открывалось ~10 с. JavaScript в окне письма выключен (защита),
  поэтому узнать, что картинка зависла, окно само не может. Теперь
  незагрузившиеся картинки и другие ресурсы письма пишутся в журнал: сервер
  и ошибка, без пути (в пути бывают адрес и метки) — по журналу будет видно
  точную причину.
- **Беседы для всех писем** (Android; вопрос владельца 04.11.2026 «можно
  ли значок приложения заменить на портрет»): в свёрнутом уведомлении слева
  Android рисует портрет только у «беседы», у остальных уведомлений —
  значок приложения. Беседами были только письма VIP. Новый переключатель
  «Настройки → Уведомления → Беседы для всех писем» (по умолчанию
  выключен) делает беседой каждое письмо: слева портрет отправителя с
  маленьким значком приложения. Цена: все письма — в разделе «Беседы»
  шторки, выше уведомлений других приложений; на Android 11–12 недавние
  отправители видны и в меню долгого нажатия на значок приложения (на
  Android 13+ — нет). Выключение снимает ярлыки бесед; беседы VIP
  появятся снова со следующим письмом VIP. Тест
  `test/unit/messenger_notifications_test.dart`.

Файлы платформ в 1.11.0:

- Android: `MdmBridge.kt` (канал `ogneliss/mdm`), `res/xml/app_restrictions.xml`,
  `res/values{,-ru}/mdm_strings.xml`, строка `APP_RESTRICTIONS` в манифесте,
  регистрация в `MainActivity.kt`.
- iOS: `AppDelegate.swift` — чтение `com.apple.configuration.managed` и
  наблюдение за изменениями (без новых прав и возможностей Xcode).
- macOS: `tool/desktop/macos/MainFlutterWindow.swift` (перевод; сборка
  кладёт его в `macos/Runner/`).
- project.pbxproj и Runner.entitlements не менялись; в Xcode включать
  ничего не нужно.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Для компаний: настройки организации из MDM (Managed App Configuration)
• iPad в стиле Outlook: команды над письмом, ответ рядом с письмом
• Перевод писем вместе с темой и своего текста на устройстве (iOS 18 и новее)
• Темы оформления, плотность ленты, тёмные письма без инверсии
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
• For businesses: organisation settings via MDM (Managed App Configuration)
• iPad in Outlook style: commands above the message, reply right next to it
• Translate messages with their subject, and your own text, on the device (iOS 18 or later)
• Colour themes, list density, dark messages without inversion
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
• Für Unternehmen: Einstellungen der Organisation per MDM (Managed App Configuration)
• iPad im Outlook-Stil: Befehle über der Nachricht, Antwort direkt daneben
• Nachrichten samt Betreff und eigene Texte auf dem Gerät übersetzen (ab iOS 18)
• Farbschemata, Listendichte, dunkle Nachrichten ohne Invertierung
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
• Entreprises : réglages de l’organisation par MDM (Managed App Configuration)
• iPad façon Outlook : commandes au-dessus du message, réponse juste à côté
• Traduction des messages (objet compris) et de vos textes sur l’appareil (iOS 18 ou ultérieur)
• Thèmes de couleurs, densité de liste, messages sombres sans inversion
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
• Для компаний: настройки из MDM
• Планшет и компьютер в стиле Outlook
• Перевод писем с темой и своего текста на устройстве
• Темы оформления, плотность ленты, тёмные письма без инверсии
• Дата в письме — встреча или напоминание в одно касание
• Блокировка отправителя и чистка его писем
• Предупреждение о подделке отправителя
• Уведомления с фото отправителя
• Сигналы почты и без сервисов Google (UnifiedPush)
</ru-RU>
<en-US>
• For businesses: settings via MDM
• Outlook-style layout on tablets and computers
• Translate mail (subject too) and your own text on the device
• Colour themes, list density, dark mail without inversion
• Tap a date in a message to add a meeting or reminder
• Block a sender and sweep their mail
• Warnings about spoofed senders
• Notifications with the sender's photo
• Mail signals without Google services (UnifiedPush)
</en-US>
<de-DE>
• Für Unternehmen: Einstellungen per MDM
• Tablet und Computer im Outlook-Stil
• Mails samt Betreff und eigene Texte auf dem Gerät übersetzen
• Farbschemata, Listendichte, dunkle Mails ohne Invertierung
• Datum in Nachricht antippen: Termin oder Erinnerung anlegen
• Absender blockieren und seine Mails bereinigen
• Warnungen vor gefälschten Absendern
• Benachrichtigungen mit Foto des Absenders
• Mail-Signale ohne Google-Dienste (UnifiedPush)
</de-DE>
<fr-FR>
• Entreprises : réglages par MDM
• Tablette et ordinateur façon Outlook
• Traduction des e-mails (objet compris) et de vos textes sur l’appareil
• Thèmes de couleurs, densité de liste, e-mails sombres sans inversion
• Touchez une date du message : réunion ou rappel
• Bloquer un expéditeur et nettoyer ses e-mails
• Alertes d’usurpation d’expéditeur
• Notifications avec photo de l’expéditeur
• Signaux courrier sans services Google (UnifiedPush)
</fr-FR>
<ar>
• للشركات: إعدادات عبر MDM
• الجهاز اللوحي والكمبيوتر بأسلوب Outlook
• ترجمة الرسائل مع موضوعها ونصوصك على الجهاز
• أنساق ألوان وكثافة القائمة ورسائل داكنة بلا عكس للألوان
• اضغط على تاريخ في الرسالة لإضافة اجتماع أو تذكير
• حظر المرسل وتنظيف رسائله
• تحذيرات من انتحال هوية المرسل
• إشعارات مع صورة المرسل
• إشارات البريد بدون خدمات Google (UnifiedPush)
</ar>
<hu-HU>
• Cégeknek: beállítások MDM-ből
• Táblagépen és számítógépen Outlook-stílus
• Levelek (tárggyal együtt) és saját szövegek fordítása az eszközön
• Színsémák, listasűrűség, sötét levelek inverzió nélkül
• Koppintson egy dátumra: értekezlet vagy emlékeztető
• Feladó letiltása és leveleinek takarítása
• Figyelmeztetés hamisított feladóra
• Értesítések a feladó fotójával
• Levéljelzések Google-szolgáltatások nélkül (UnifiedPush)
</hu-HU>
<vi>
• Cho doanh nghiệp: cấu hình qua MDM
• Máy tính bảng và máy tính kiểu Outlook
• Dịch thư (cả tiêu đề) và văn bản của bạn ngay trên thiết bị
• Chủ đề màu, mật độ danh sách, thư tối không đảo màu
• Chạm vào ngày trong thư để thêm cuộc họp hoặc lời nhắc
• Chặn người gửi và dọn dẹp thư của họ
• Cảnh báo người gửi giả mạo
• Thông báo kèm ảnh người gửi
• Tín hiệu thư không cần dịch vụ Google (UnifiedPush)
</vi>
<da-DK>
• Til virksomheder: indstillinger via MDM
• Tablet og computer i Outlook-stil
• Oversæt mails med emne og din egen tekst på enheden
• Farvetemaer, listetæthed, mørke mails uden invertering
• Tryk på en dato i en besked for at tilføje et møde eller en påmindelse
• Blokér afsender og ryd op i vedkommendes mails
• Advarsler om falske afsendere
• Notifikationer med afsenderens foto
• Mailsignaler uden Google-tjenester (UnifiedPush)
</da-DK>
<iw-IL>
• לעסקים: הגדרות דרך MDM
• טאבלט ומחשב בסגנון Outlook
• תרגום הודעות כולל הנושא, וגם הטקסט שלך, במכשיר
• ערכות צבעים, צפיפות רשימת הדואר, הודעות כהות ללא היפוך צבעים
• הקשה על תאריך בהודעה מוסיפה פגישה או תזכורת
• חסימת שולח וניקוי כל ההודעות שלו
• אזהרות על שולחים מתחזים
• התראות עם תמונת השולח
• אותות דואר גם ללא שירותי Google (UnifiedPush)
</iw-IL>
<id>
• Untuk perusahaan: pengaturan lewat MDM
• Tablet dan komputer bergaya Outlook
• Terjemahkan email beserta subjeknya dan teks Anda di perangkat
• Tema warna, kerapatan daftar, email gelap tanpa inversi
• Ketuk tanggal di pesan untuk menambah rapat atau pengingat
• Blokir pengirim dan bersihkan emailnya
• Peringatan pengirim palsu
• Notifikasi dengan foto pengirim
• Sinyal email tanpa layanan Google (UnifiedPush)
</id>
<es-ES>
• Para empresas: ajustes mediante MDM
• Tableta y ordenador al estilo Outlook
• Traduce correos (también el asunto) y tu texto en el dispositivo
• Temas de color, densidad de lista, correo oscuro sin inversión
• Toca una fecha para crear una reunión o recordatorio
• Bloqueo de remitentes y limpieza de sus mensajes
• Avisos de remitentes suplantados
• Notificaciones con la foto del remitente
• Señales de correo sin servicios de Google (UnifiedPush)
</es-ES>
<it-IT>
• Per le aziende: impostazioni tramite MDM
• Tablet e computer in stile Outlook
• Traduci le email (anche l’oggetto) e il tuo testo sul dispositivo
• Temi colore, densità dell’elenco, posta scura senza inversione
• Tocca una data per creare riunione o promemoria
• Blocco dei mittenti e pulizia dei loro messaggi
• Avvisi sui mittenti falsificati
• Notifiche con la foto del mittente
• Segnali di posta anche senza servizi Google (UnifiedPush)
</it-IT>
<zh-CN>
• 企业：通过 MDM 下发设置
• 平板和电脑采用 Outlook 式布局
• 在设备上翻译邮件（含主题）和你写的文字
• 配色主题、列表密度、无需反色的深色邮件
• 点按邮件中的日期，即可添加会议或提醒
• 阻止发件人并清理其邮件
• 伪造发件人警告
• 通知显示发件人头像
• 没有 Google 服务也能收到邮件信号（UnifiedPush）
</zh-CN>
<ko-KR>
• 기업용: MDM으로 설정 배포
• 태블릿과 컴퓨터에서 Outlook 스타일
• 기기에서 메일(제목 포함)과 내 글 번역
• 색상 테마, 목록 밀도, 색 반전 없는 다크 메일
• 메일 속 날짜를 탭해 회의나 알림 추가
• 보낸 사람 차단 및 해당 메일 정리
• 보낸 사람 사칭 경고
• 보낸 사람 사진이 표시되는 알림
• Google 서비스 없이도 메일 신호 수신(UnifiedPush)
</ko-KR>
<nl-NL>
• Voor bedrijven: instellingen via MDM
• Tablet en computer in Outlook-stijl
• Vertaal mail (ook het onderwerp) en je eigen tekst op het apparaat
• Kleurthema’s, lijstdichtheid, donkere e-mail zonder inversie
• Tik op een datum voor een afspraak of herinnering
• Afzender blokkeren en zijn berichten opruimen
• Waarschuwingen voor vervalste afzenders
• Meldingen met de foto van de afzender
• E-mailsignalen ook zonder Google-services (UnifiedPush)
</nl-NL>
<no-NO>
• For bedrifter: innstillinger via MDM
• Nettbrett og datamaskin i Outlook-stil
• Oversett e-post med emne og din egen tekst på enheten
• Fargetemaer, listetetthet, mørk e-post uten invertering
• Trykk på en dato i en melding for å legge til møte eller påminnelse
• Blokker en avsender og rydd opp i meldingene deres
• Advarsler om forfalskede avsendere
• Varsler med avsenderens bilde
• E-postsignaler også uten Google-tjenester (UnifiedPush)
</no-NO>
<pl-PL>
• Dla firm: ustawienia z MDM
• Tablet i komputer w stylu Outlooka
• Tłumaczenie poczty (z tematem) i własnego tekstu na urządzeniu
• Motywy kolorów, gęstość listy, ciemne wiadomości bez inwersji
• Dotknij daty, by dodać spotkanie lub przypomnienie
• Blokowanie nadawców i porządkowanie ich wiadomości
• Ostrzeżenia o fałszywych nadawcach
• Powiadomienia ze zdjęciem nadawcy
• Sygnały poczty także bez usług Google (UnifiedPush)
</pl-PL>
<pt-BR>
• Para empresas: configurações via MDM
• Tablet e computador no estilo Outlook
• Traduza e-mails (com o assunto) e seu próprio texto no aparelho
• Temas de cor, densidade da lista, e-mails escuros sem inversão
• Toque em uma data para criar reunião ou lembrete
• Bloqueio de remetentes e limpeza de mensagens
• Alertas sobre remetentes falsificados
• Notificações com a foto do remetente
• Sinais de e-mail também sem serviços do Google (UnifiedPush)
</pt-BR>
<ro>
• Pentru companii: setări prin MDM
• Tabletă și computer în stil Outlook
• Traducerea e-mailurilor (cu subiect) și a textului tău pe dispozitiv
• Teme de culoare, densitatea listei, mesaje întunecate fără inversare
• Atinge o dată dintr-un mesaj pentru întâlnire sau memento
• Blocarea expeditorului și curățarea mesajelor lui
• Avertizări la expeditori falsificați
• Notificări cu fotografia expeditorului
• Semnale de e-mail și fără servicii Google (UnifiedPush)
</ro>
<sk>
• Pre firmy: nastavenia cez MDM
• Tablet a počítač v štýle Outlooku
• Preklad e-mailov aj s predmetom a vlastného textu v zariadení
• Farebné motívy, hustota zoznamu, tmavé správy bez inverzie
• Ťuknutím na dátum v správe pridáte stretnutie alebo pripomienku
• Blokovanie odosielateľa a čistenie jeho správ
• Varovania pred sfalšovanými odosielateľmi
• Upozornenia s fotkou odosielateľa
• Signály pošty aj bez služieb Google (UnifiedPush)
</sk>
<th>
• สำหรับองค์กร: ตั้งค่าผ่าน MDM
• แท็บเล็ตและคอมพิวเตอร์สไตล์ Outlook
• แปลอีเมลพร้อมหัวเรื่องและข้อความของคุณบนอุปกรณ์
• ธีมสี ความหนาแน่นของรายการ อีเมลโหมดมืดโดยไม่กลับสี
• แตะวันที่ในอีเมลเพื่อเพิ่มการประชุมหรือเตือนความจำ
• บล็อกผู้ส่งและล้างอีเมลของผู้ส่ง
• เตือนเมื่อผู้ส่งถูกปลอมแปลง
• การแจ้งเตือนพร้อมรูปของผู้ส่ง
• สัญญาณอีเมลแม้ไม่มีบริการ Google (UnifiedPush)
</th>
<tr-TR>
• Şirketler için: MDM ile ayarlar
• Tablet ve bilgisayarda Outlook tarzı
• Postaları (konu dahil) ve kendi metninizi cihazda çevirin
• Renk temaları, liste yoğunluğu, ters çevirmesiz koyu iletiler
• İletideki tarihe dokunup toplantı veya hatırlatıcı ekleyin
• Göndereni engelleme ve iletilerini temizleme
• Sahte göndericilere karşı uyarılar
• Gönderenin fotoğrafıyla bildirimler
• Google hizmetleri olmadan da posta sinyalleri (UnifiedPush)
</tr-TR>
<fi-FI>
• Yrityksille: asetukset MDM:n kautta
• Tabletti ja tietokone Outlook-tyyliin
• Käännä viestit aiheineen ja oma tekstisi laitteella
• Väriteemat, luettelon tiheys, tummat viestit ilman käänteisvärejä
• Napauta viestin päivämäärää ja lisää kokous tai muistutus
• Lähettäjän esto ja hänen viestiensä siivous
• Varoitukset väärennetyistä lähettäjistä
• Ilmoitukset lähettäjän kuvalla
• Postisignaalit ilman Google-palveluita (UnifiedPush)
</fi-FI>
<hi-IN>
• कंपनियों के लिए: MDM से सेटिंग्स
• टैबलेट और कंप्यूटर पर Outlook जैसा लेआउट
• मेल (विषय सहित) और अपना टेक्स्ट डिवाइस पर अनुवाद करें
• रंग थीम, सूची घनत्व, बिना इनवर्ज़न के डार्क मेल
• ईमेल में तारीख पर टैप करके मीटिंग या रिमाइंडर जोड़ें
• प्रेषक को ब्लॉक करें और उसके ईमेल की सफ़ाई करें
• नकली प्रेषकों की चेतावनियां
• प्रेषक की फ़ोटो के साथ सूचनाएं
• Google सेवाओं के बिना भी मेल सिग्नल (UnifiedPush)
</hi-IN>
<cs-CZ>
• Pro firmy: nastavení přes MDM
• Tablet a počítač ve stylu Outlooku
• Překlad e-mailů i s předmětem a vlastního textu v zařízení
• Barevné motivy, hustota seznamu, tmavé zprávy bez inverze
• Klepnutím na datum ve zprávě přidáte schůzku nebo připomenutí
• Blokování odesílatele a čištění jeho zpráv
• Varování před padělanými odesílateli
• Oznámení s fotkou odesílatele
• Signály pošty i bez služeb Google (UnifiedPush)
</cs-CZ>
<sv-SE>
• För företag: inställningar via MDM
• Surfplatta och dator i Outlook-stil
• Översätt mejl med ämnesrad och din egen text på enheten
• Färgteman, listtäthet, mörk e-post utan inversion
• Tryck på ett datum i meddelandet för möte eller påminnelse
• Blockera en avsändare och rensa dennes e-post
• Varningar för förfalskade avsändare
• Aviseringar med avsändarens foto
• E-postsignaler även utan Google-tjänster (UnifiedPush)
</sv-SE>
<ja-JP>
• 企業向け：MDM で設定を配布
• タブレットとパソコンで Outlook 風の画面
• メール（件名も）と自分の文章を端末内で翻訳
• カラーテーマ、リストの密度、反転しないダークメール
• メール内の日付をタップして会議やリマインダーを追加
• 差出人をブロックし、そのメールをクリーンアップ
• なりすましの差出人を警告
• 差出人の写真付き通知
• Google サービスなしでもメールのシグナルを受信 (UnifiedPush)
</ja-JP>
```
