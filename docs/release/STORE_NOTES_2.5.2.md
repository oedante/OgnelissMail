# «Что нового» — 2.5.2 (154), относительно 2.4.0

Опубликована 2.4.0; 2.5.2 — всё, что сделано после неё: 2.5.0 (проекты с
этапами, сводка и отчёты, изменение поручений и права постановщика, срок со
временем, «На контроле» и «Позже» на всех устройствах, переносная версия
для Windows), 2.5.1 (отправка через серверы вроде Mercury, приветствие в
поручениях) и 2.5.2 (выбор движка рисования на Mac). Тексты для магазинов
ниже — от 2.4.0. Шаги владельца — `OWNER_STEPS_2.5.2.md`; по версиям —
`STORE_NOTES_2.5.0.md`, `STORE_NOTES_2.5.1.md`.

## Сделано с 2.4.0

### Поручения и проекты

- **Проекты с этапами.** У этапа — исполнитель, соисполнители, контролёр
  и наблюдатели; начало в свой день или «после этапа», чек-лист, файлы,
  шаблоны проектов. План — диаграммой Ганта (открывается на первом
  незавершённом этапе). Статус проекта — по этапам: все приняты — проект
  закрывается у постановщика; просроченный этап — проект в списке
  просрочен. Просроченные этапы можно сдвинуть вместе с последующими.
- **Общий план проекта** — «Все видят план и ход работ»: участники видят,
  кто что и после кого делает, и статусы этапов; по выбору постановщика —
  каждый видит только свои этапы.
- **Изменение поручений и проектов** — текст, этапы, сроки, файлы,
  удаление этапа; изменения доходят до всех участников.
- **Права постановщика другому человеку** — заместитель (оба могут
  принимать и изменять) или полная передача, например при смене.
- **Срок поручения — с временем**, не только днём: в карточке, в списке и
  в «Моём дне» — «до 18:00»; просрочено — с этой минуты.
- **Напоминания о сроке на телефоне**: в день срока, за час до срока со
  временем; постановщику — о просроченном поручении.
- **Статус доходит надёжнее.** У номера поручения в теме — код действия
  (`OGN-…-D` — принято, `-W` — взято в работу и т. д.): статус меняется,
  даже если почтовый сервер вырезал скрытую отметку из письма. Код
  проверяется по роли отправителя; ответы из других почтовых программ
  (без кода) разбираются по словам, как раньше.
- **Поручение закрывается у исполнителя**, когда постановщик принял работу
  (раньше могло остаться «На проверке»); зависшие «На проверке» закрываются
  сами при следующей проверке почты.
- **«Мой день»**: поручения, выполненные сегодня, — в колонке «Готово».

### Поручения: ящик, «Важное», результат, сводка и отчёты

Подобрано из Jira и Битрикс24 (`docs/architecture/ASSIGNMENT_UX_JIRA_BITRIX.md`).

- **Ящик поручения.** В карточке — «Отправлено с» или «Получено на»
  (портрет и адрес ящика); в «Поручить» и в редакторе проекта — выбор
  ящика, когда их несколько; в списке — значок ящика и фильтр «Все ящики /
  ящик»; в шапке проекта — ящик.
- **«Важное»** (как приоритет в Jira и «Важная задача» в Битрикс24): «!» в
  списке и карточке, важные — первыми, тема письма «Важное поручение»; у
  исполнителя поручение тоже «Важное».
- **Файлы при постановке** — вложениями письма и копией у себя.
- **«Готово» — с результатом и файлами**; в карточке блок «Результат»
  (текст, файлы, кто и когда). «Вернуть на доработку» — только с причиной;
  «Сообщить о ходе работ» — можно с файлами.
- **Фильтр «Помогаю»** (я соисполнитель); своя роль — в строке списка.
- **«Поручения → Сводка»**: действующие, просрочено, на проверке, выполнено
  за период, доля в срок, среднее время; полоса статусов; по людям;
  «Сроки» — диаграммой Ганта (просроченные первыми). Фильтры: «Я поручил /
  Мне поручили / Все», 30, 90 или 365 дней, ящик.
- **Сводка проекта**: этапы, просрочено, отклонение, дней до срока,
  статусы этапов, исполнители, план и факт по этапам.
- **«Отправить отчёт»** — новое письмо с кратким текстом и отчётом HTML во
  вложении (печатается в PDF).
- **Планшет и компьютер**: проект от 1000 точек — в две колонки (этапы
  слева; план, сводка, файлы и история справа); карточка этапа и редактор —
  колонкой читаемой ширины.

### Приветствие и имена

- **Приветствие в письмах поручений — как в ваших письмах** (то же, что в
  редакторе и быстром ответе): «Добрый день, Дмитрий Александрович,»,
  по настройке приветствия ящика («Настройки → Аккаунты → ящик → Подписи →
  Приветствие в письме»: нет, без имени, с именем) и на языке письма.
  Было «Ситников, добрый день!» — одна фамилия. Без имени (только адрес,
  организация) — «Добрый день!».
- **Обращение по имени и отчеству при любом порядке ФИО** — в редакторе,
  быстром ответе и поручениях: «Ситников Дмитрий» → «Дмитрий»,
  «Дмитрий Александрович Ситников» и «Ситников, Дмитрий Александрович»
  (Exchange) → «Дмитрий Александрович». Где имя — по списку частых имён
  (и в латинице: Dmitry, Dmitriy) и окончаниям фамилий; по-японски —
  фамилия, по-корейски и по-китайски — полное имя, вьетнамские и
  венгерские имена — в своём порядке.

### Почта

- **«На контроле» и «Позже» — на всех устройствах.** Gmail, Яндекс,
  Mail.ru и другие IMAP-ящики — отметкой на самом письме, без дат: срок
  контроля и время возврата «Позже» остаются на устройстве, где их
  поставили. Exchange — флажком «К исполнению» с датами; в Outlook
  это обычный флажок «На контроле · OGN-C», снимут его там — отметка
  снимется везде. Выключается: «Расширенные настройки → Разделы
  приложения → На контроле → Отметки на всех устройствах». Сервер, который
  не хранит свои отметки, — отметки остаются на устройстве, без сообщений.
- **Вложения в письмах IMAP**, загруженных до 2.4.0, — видны; «Загрузить
  заново» берёт письмо с сервера.
- **Встроенные фото без ссылки из текста** (Gmail, Яндекс) — в списке
  вложений; скрепка в ленте без списка вложений — повод уточнить у
  сервера.
- **Шапки цитат**: у человека, указанного только по имени, — фото и
  карточка контакта.
- **Отправка через Mercury (XAMPP) и похожие серверы.** Библиотека
  enough_mail считала ответом сервера всё, что пришло одним пакетом:
  многострочный ответ на EHLO, присланный несколькими пакетами, сбивал
  клиента на один ответ, и «354 OK, send data» принимался за ответ на конец
  письма — письмо доходило, а в очереди висело с этой ошибкой (повтор давал
  дубль). Теперь ответ собирается по правилам SMTP; EHLO с ответом из
  одной строки тоже завершается.
- **EHLO с адресом IP** — в квадратных скобках (`EHLO [192.168.1.67]`, RFC
  5321): Mercury отвечал «554 Invalid HELO format» на ящики вида
  `user@192.168.1.67`. После отказа соединение закрывается сразу, а не по
  тайм-ауту сервера.
- **Полное ФИО человека — с первого раза.** Справочник имён ждал сам себя:
  первый запрос не завершался, полное имя в карточке человека, у
  получателей письма и участников встречи появлялось только со второго
  раза.

### Платформы

- **Android 14+: новое встраивание окна письма (HCPP) — включено по
  умолчанию** (проверено владельцем). После сбоя в встраивании окон
  выключается само; включить снова — «Расширенные настройки → Графика».
- **Windows: переносная версия** — файл `portable.txt` рядом с
  `ogneliss.exe`: все данные — в папке `UserData` рядом с программой, а не
  в AppData. Сборка на GitHub выпускает `ogneliss-windows-portable.zip` с
  этим файлом. Ключи защищены Windows и привязаны к учётной записи.
- **Mac: выбор движка рисования — как на Android** («Настройки → Расширенные
  настройки → Графика»): «Автоматически» — прежний движок Skia на Mac с
  Intel и Impeller на Apple Silicon, «Совместимость (Skia)», «Новый движок
  (Impeller)»; кнопка «Перезапустить». Во Flutter 3.47 Impeller и новая
  отрисовка текста включены на Mac по умолчанию; на Mac с Intel часть букв
  рассыпалась в шум («Почт▒», «▒ерновики», список языков почти нечитаем),
  интерфейс дёргался. Flutter решает по ключу `FLTEnableImpeller` из
  `Info.plist`; приложение подменяет ответ на него при запуске (GraphicsBridge
  в `tool/desktop/macos/MainFlutterWindow.swift`). `false` в `Info.plist`
  (сборка пишет сама) — запасной вариант. В журнале и диагностике — чем
  рисует и видеокарта.

### Сборка (для владельца)

- **Сборка для iPhone:** `scripts/build_ios.sh` сам включает Swift Package
  Manager (новые версии `receive_sharing_intent` собираются только так),
  `scripts/build_macos.sh` — выключает (плагины Mac — через CocoaPods, как на
  GitHub). Настройка Flutter общая — переключать вручную не нужно.
- **Виджеты iPhone — инструкция** (`ios/OgnelissWidgets/README.md`): что
  заполнять (ничего, кроме цели и App Group), где права виджетов в архиве,
  шаги для Xcode 16+, подпись без зарегистрированных устройств (ручные
  профили App Store у обеих целей), «Cycle inside Runner» — порядок фаз.

Платформы с 2.4.0: манифест Android, `Info.plist` iPhone, `project.pbxproj`,
`Runner.entitlements`, Podfile не менялись (цель виджетов iPhone — по
желанию, `ios/OgnelissWidgets/README.md`). Новые прямые зависимости — только
для Windows (`path_provider_windows`, `shared_preferences_windows`, их
интерфейсы и `ffi`; BSD-3-Clause, уже были в сборке). База — схема 30,
обновляется сама при первом запуске.

## Кратко (RU / EN)

**RU.** Проекты с этапами: роли, общий план с диаграммой Ганта, шаблоны.
Сводка и отчёты по поручениям, «Важное», выбор ящика, результат с файлами.
Поручения и проекты можно изменять, у постановщика может быть заместитель.
Сроки — с точным временем и напоминаниями, статусы доходят надёжнее.
«На контроле» и «Позже» — на всех устройствах. Приветствие в поручениях — по
имени и отчеству. Исправлена отправка через серверы вроде Mercury. На Mac с
Intel текст больше не рассыпается; на Windows — переносная версия.

**EN.** Projects with stages: roles, a shared plan with a Gantt chart,
templates. Assignment summary and reports, Important, mailbox choice,
results with files. Assignments and projects can be edited, and assigners
can name a deputy. Deadlines with an exact time and reminders; statuses
arrive more reliably. Tracked and Later sync across all your devices.
Assignment emails greet people by first name. Fixed sending through servers
like Mercury. On Intel-based Macs, text no longer gets garbled; a portable
version for Windows.

## App Store — Mac (ru, en, de, fr)

Версия macOS в App Store Connect, поле «Что нового в этой версии».

```
<ru-RU>
• На Mac с процессором Intel текст больше не рассыпается, интерфейс не дёргается
• Выбор движка рисования: Настройки → Расширенные настройки → Графика
• Проекты с этапами: роли, общий план, диаграмма Ганта, шаблоны
• Сводка и отчёты по поручениям; «Важное», выбор ящика, результат с файлами
• Поручения и проекты можно изменять; у постановщика может быть заместитель
• Срок — с точным временем и напоминанием на телефоне; статусы доходят надёжнее
• «Позже» и «На контроле» — на всех ваших устройствах
• Приветствие в поручениях — по имени и отчеству
• Исправлена отправка через серверы вроде Mercury
</ru-RU>
<en-US>
• On Intel-based Macs, text no longer gets garbled and the interface no longer stutters
• Choose the rendering engine: Settings → Advanced settings → Graphics
• Projects with stages: roles, a shared plan, Gantt chart, templates
• Assignment summary and reports; Important, mailbox choice, results with files
• Edit assignments and projects; assigners can name a deputy
• Deadlines with an exact time and phone reminders; statuses arrive more reliably
• Later and Tracked sync across all your devices
• Assignment emails greet people by first name
• Fixed sending through servers like Mercury
</en-US>
<de-DE>
• Auf Macs mit Intel-Prozessor wird Text nicht mehr verstümmelt und die Oberfläche ruckelt nicht mehr
• Grafik-Engine wählbar: Einstellungen → Erweiterte Einstellungen → Grafik
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• Übersicht und Berichte zu Aufträgen; „Wichtig“, Postfachwahl, Ergebnis mit Dateien
• Aufträge und Projekte bearbeiten; Auftraggeber können einen Stellvertreter benennen
• Fristen mit genauer Uhrzeit und Erinnerung auf dem Telefon; Status kommt zuverlässiger an
• „Später“ und „Im Blick“ auf all Ihren Geräten
• Auftrags-E-Mails sprechen Personen mit Vornamen an
• Versand über Server wie Mercury behoben
</de-DE>
<fr-FR>
• Sur les Mac à processeur Intel, le texte ne se brouille plus et l’interface ne saccade plus
• Choix du moteur de rendu : Réglages → Réglages avancés → Graphismes
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• Synthèse et rapports des missions ; « Important », choix de la boîte, résultat avec fichiers
• Missions et projets modifiables ; le donneur d’ordre peut nommer un suppléant
• Échéances à l’heure près avec rappel sur le téléphone ; statuts plus fiables
• « Plus tard » et « Suivis » sur tous vos appareils
• Les e-mails de mission saluent par le prénom
• Envoi corrigé via des serveurs comme Mercury
</fr-FR>
```

## App Store — iPhone и iPad (ru, en, de, fr)

Первая строка — про виджеты: оставьте её, только если цель виджетов в этой
сборке подключена (на iPhone они выходят впервые).

```
<ru-RU>
• Виджеты на экране «Домой»: «Мой день», почта, календарь, заметки
• Проекты с этапами: роли, общий план, диаграмма Ганта, шаблоны
• Сводка и отчёты по поручениям; «Важное», выбор ящика, результат с файлами
• Поручения и проекты можно изменять; у постановщика может быть заместитель
• Срок — с точным временем и напоминанием на телефоне; статусы доходят надёжнее
• «Позже» и «На контроле» — на всех ваших устройствах
• Приветствие в поручениях — по имени и отчеству
• Исправлена отправка через серверы вроде Mercury
</ru-RU>
<en-US>
• Home Screen widgets: My day, Mail, Calendar, Notes
• Projects with stages: roles, a shared plan, Gantt chart, templates
• Assignment summary and reports; Important, mailbox choice, results with files
• Edit assignments and projects; assigners can name a deputy
• Deadlines with an exact time and phone reminders; statuses arrive more reliably
• Later and Tracked sync across all your devices
• Assignment emails greet people by first name
• Fixed sending through servers like Mercury
</en-US>
<de-DE>
• Widgets für den Home-Bildschirm: Mein Tag, E-Mail, Kalender, Notizen
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• Übersicht und Berichte zu Aufträgen; „Wichtig“, Postfachwahl, Ergebnis mit Dateien
• Aufträge und Projekte bearbeiten; Auftraggeber können einen Stellvertreter benennen
• Fristen mit genauer Uhrzeit und Erinnerung auf dem Telefon; Status kommt zuverlässiger an
• „Später“ und „Im Blick“ auf all Ihren Geräten
• Auftrags-E-Mails sprechen Personen mit Vornamen an
• Versand über Server wie Mercury behoben
</de-DE>
<fr-FR>
• Widgets d’écran d’accueil : Ma journée, E-mail, Calendrier, Notes
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• Synthèse et rapports des missions ; « Important », choix de la boîte, résultat avec fichiers
• Missions et projets modifiables ; le donneur d’ordre peut nommer un suppléant
• Échéances à l’heure près avec rappel sur le téléphone ; statuts plus fiables
• « Plus tard » et « Suivis » sur tous vos appareils
• Les e-mails de mission saluent par le prénom
• Envoi corrigé via des serveurs comme Mercury
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков; самый длинный — 490).

```
<ru-RU>
• Проекты с этапами: роли, общий план, диаграмма Ганта, шаблоны
• Сводка и отчёты по поручениям; «Важное», выбор ящика, результат с файлами
• Поручения и проекты можно изменять; у постановщика может быть заместитель
• Срок — с точным временем и напоминанием на телефоне; статусы доходят надёжнее
• «Позже» и «На контроле» — на всех ваших устройствах
• Приветствие в поручениях — по имени и отчеству
• Исправлена отправка через серверы вроде Mercury
</ru-RU>
<en-US>
• Projects with stages: roles, a shared plan, Gantt chart, templates
• Assignment summary and reports; Important, mailbox choice, results with files
• Edit assignments and projects; assigners can name a deputy
• Deadlines with an exact time and phone reminders; statuses arrive more reliably
• Later and Tracked sync across all your devices
• Assignment emails greet people by first name
• Fixed sending through servers like Mercury
</en-US>
<de-DE>
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• Übersicht und Berichte zu Aufträgen; „Wichtig“, Postfachwahl, Ergebnis mit Dateien
• Aufträge und Projekte bearbeiten; Auftraggeber können einen Stellvertreter benennen
• Fristen mit genauer Uhrzeit und Erinnerung auf dem Telefon; Status kommt zuverlässiger an
• „Später“ und „Im Blick“ auf all Ihren Geräten
• Auftrags-E-Mails sprechen Personen mit Vornamen an
• Versand über Server wie Mercury behoben
</de-DE>
<fr-FR>
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• Synthèse et rapports des missions ; « Important », choix de la boîte, résultat avec fichiers
• Missions et projets modifiables ; le donneur d’ordre peut nommer un suppléant
• Échéances à l’heure près avec rappel sur le téléphone ; statuts plus fiables
• « Plus tard » et « Suivis » sur tous vos appareils
• Les e-mails de mission saluent par le prénom
• Envoi corrigé via des serveurs comme Mercury
</fr-FR>
<ar>
• مشاريع على مراحل: أدوار، وخطة مشتركة، ومخطط جانت، وقوالب
• ملخص وتقارير للتكليفات؛ «مهم» واختيار البريد والنتيجة مع الملفات
• يمكن تعديل التكليفات والمشاريع؛ ويمكن لصاحب التكليف تعيين نائب
• مواعيد بالساعة الدقيقة مع تذكير على الهاتف؛ وتصل الحالات بموثوقية أكبر
• «لاحقًا» و«قيد المتابعة» على جميع أجهزتك
• رسائل التكليفات تحيّي الأشخاص بالاسم الأول
• إصلاح الإرسال عبر خوادم مثل Mercury
</ar>
<hu-HU>
• Szakaszokra bontott projektek: szerepek, közös terv, Gantt-diagram, sablonok
• Megbízások összesítője és jelentései; „Fontos”, postafiók-választás, eredmény fájlokkal
• A megbízások és projektek szerkeszthetők; a kiadónak lehet helyettese
• Határidő pontos időponttal és emlékeztetővel a telefonon; az állapot megbízhatóbban érkezik
• A „Később” és a „Követett” minden eszközén
• A megbízások levelei keresztnéven szólítanak meg
• Javítva a küldés Mercuryhoz hasonló szervereken
</hu-HU>
<vi>
• Dự án theo giai đoạn: vai trò, kế hoạch chung, biểu đồ Gantt, mẫu
• Tổng quan và báo cáo việc giao; «Quan trọng», chọn hộp thư, kết quả kèm tệp
• Sửa được việc giao và dự án; người giao có thể chỉ định người thay
• Hạn kèm giờ chính xác và nhắc trên điện thoại; trạng thái đến tin cậy hơn
• «Để sau» và «Đang theo dõi» trên mọi thiết bị của bạn
• Thư việc giao chào bằng tên gọi
• Sửa lỗi gửi qua máy chủ như Mercury
</vi>
<da-DK>
• Projekter med faser: roller, fælles plan, Gantt-diagram, skabeloner
• Overblik og rapporter over opgaver; "Vigtig", valg af postkasse, resultat med filer
• Tildelte opgaver og projekter kan redigeres; den, der tildeler, kan udpege en stedfortræder
• Frister med præcist klokkeslæt og påmindelse på telefonen; status når sikrere frem
• "Senere" og "Overvåget" på alle dine enheder
• Mails om opgaver hilser med fornavn
• Afsendelse via servere som Mercury rettet
</da-DK>
<iw-IL>
• פרויקטים בשלבים: תפקידים, תוכנית משותפת, תרשים גאנט ותבניות
• סיכום ודוחות למטלות; "חשוב", בחירת תיבה, תוצאה עם קבצים
• אפשר לערוך מטלות ופרויקטים; למקצה יכול להיות ממלא מקום
• מועדים עם שעה מדויקת ותזכורת בטלפון; סטטוסים מגיעים בצורה אמינה יותר
• "מאוחר יותר" ו"במעקב" בכל המכשירים שלך
• הודעות על מטלות פונות בשם הפרטי
• תוקנה שליחה דרך שרתים כמו Mercury
</iw-IL>
<id>
• Proyek bertahap: peran, rencana bersama, diagram Gantt, templat
• Ringkasan dan laporan penugasan; «Penting», pilihan kotak surat, hasil dengan file
• Penugasan dan proyek bisa diedit; pemberi tugas bisa menunjuk wakil
• Tenggat dengan jam tepat dan pengingat di ponsel; status sampai lebih andal
• «Nanti» dan «Dipantau» di semua perangkat Anda
• Email penugasan menyapa dengan nama depan
• Perbaikan pengiriman lewat server seperti Mercury
</id>
<es-ES>
• Proyectos por etapas: roles, plan compartido, diagrama de Gantt y plantillas
• Resumen e informes de encargos; «Importante», elección de buzón, resultado con archivos
• Encargos y proyectos editables; quien asigna puede nombrar un suplente
• Plazos con hora exacta y recordatorio en el teléfono; estados más fiables
• «Más tarde» y «En seguimiento» en todos tus dispositivos
• Los correos de encargos saludan por el nombre de pila
• Corregido el envío por servidores como Mercury
</es-ES>
<it-IT>
• Progetti a fasi: ruoli, piano condiviso, diagramma di Gantt, modelli
• Riepilogo e report degli incarichi; «Importante», scelta della casella, risultato con file
• Incarichi e progetti modificabili; chi assegna può nominare un vice
• Scadenze con l’ora esatta e promemoria sul telefono; stati più affidabili
• «Più tardi» e «Monitorati» su tutti i tuoi dispositivi
• Le email degli incarichi salutano per nome
• Corretto l’invio tramite server come Mercury
</it-IT>
<zh-CN>
• 分阶段项目：角色、共享计划、甘特图和模板
• 任务分派汇总与报告；“重要”、选择邮箱、附带文件的成果
• 任务分派和项目可编辑；分派人可设代理
• 截止时间精确到时刻并在手机上提醒；状态送达更可靠
• “稍后”和“跟进中”在你的所有设备上同步
• 任务分派邮件按名字称呼
• 修复通过 Mercury 等服务器发送的问题
</zh-CN>
<ko-KR>
• 단계별 프로젝트: 역할, 공유 계획, 간트 차트, 템플릿
• 업무 지시 요약과 보고서; '중요', 메일함 선택, 파일이 첨부된 결과
• 업무 지시와 프로젝트 편집 가능; 지시자 대리인 지정
• 정확한 시각까지 기한 지정, 휴대폰 알림; 상태가 더 확실하게 전달
• '나중에'와 '추적 중'을 모든 기기에서
• 업무 지시 메일이 이름으로 인사
• Mercury 같은 서버를 통한 발송 문제 수정
</ko-KR>
<nl-NL>
• Projecten met fasen: rollen, gedeeld plan, Gantt-diagram en sjablonen
• Overzicht en rapporten; ‘Belangrijk’, mailboxkeuze, resultaat met bestanden
• Opdrachten en projecten bewerken; de opdrachtgever kan een plaatsvervanger aanwijzen
• Deadlines met exacte tijd en herinnering op je telefoon; status komt betrouwbaarder aan
• ‘Later’ en ‘In de gaten’ op al je apparaten
• E-mails over opdrachten spreken mensen aan met de voornaam
• Verzenden via servers zoals Mercury hersteld
</nl-NL>
<no-NO>
• Prosjekter med faser: roller, felles plan, Gantt-diagram, maler
• Oversikt og rapporter for oppdrag; «Viktig», valg av postkasse, resultat med filer
• Oppdrag og prosjekter kan redigeres; oppdragsgiver kan utnevne en stedfortreder
• Frister med nøyaktig klokkeslett og påminnelse på telefonen; status kommer tryggere fram
• «Senere» og «Overvåket» på alle enhetene dine
• E-poster om oppdrag hilser med fornavn
• Retting av sending via servere som Mercury
</no-NO>
<pl-PL>
• Projekty z etapami: role, wspólny plan, wykres Gantta, szablony
• Podsumowanie i raporty zleceń; „Ważne”, wybór skrzynki, wynik z plikami
• Zlecenia i projekty można edytować; zlecający może wyznaczyć zastępcę
• Terminy z dokładną godziną i przypomnieniem w telefonie; statusy docierają pewniej
• „Później” i „Śledzone” na wszystkich Twoich urządzeniach
• Wiadomości o zleceniach zwracają się po imieniu
• Naprawiono wysyłkę przez serwery takie jak Mercury
</pl-PL>
<pt-BR>
• Projetos em etapas: papéis, plano compartilhado, gráfico de Gantt e modelos
• Resumo e relatórios; "Importante", escolha da caixa, resultado com arquivos
• Atribuições e projetos editáveis; quem atribui pode nomear um substituto
• Prazos com horário exato e lembrete no celular; status chegam com mais confiabilidade
• "Mais tarde" e "Em acompanhamento" em todos os seus dispositivos
• E-mails de atribuições cumprimentam pelo primeiro nome
• Corrigido o envio por servidores como Mercury
</pt-BR>
<ro>
• Proiecte pe etape: roluri, plan comun, diagramă Gantt, șabloane
• Rezumat și rapoarte pentru sarcini; „Important”, alegerea căsuței, rezultat cu fișiere
• Sarcinile și proiectele se pot modifica; cel care atribuie poate numi un înlocuitor
• Termene cu oră exactă și memento pe telefon; stările ajung mai sigur
• „Mai târziu” și „Urmărite” pe toate dispozitivele tale
• E-mailurile despre sarcini salută după prenume
• Remediată trimiterea prin servere precum Mercury
</ro>
<sk>
• Projekty s etapami: roly, spoločný plán, Ganttov diagram, šablóny
• Prehľad a správy úloh; „Dôležité“, výber schránky, výsledok so súbormi
• Zadané úlohy a projekty sa dajú upravovať; zadávateľ môže určiť zástupcu
• Termíny s presným časom a pripomenutím v telefóne; stavy prichádzajú spoľahlivejšie
• „Neskôr“ a „Sledované“ na všetkých vašich zariadeniach
• E-maily k úlohám oslovujú krstným menom
• Opravené odosielanie cez servery ako Mercury
</sk>
<th>
• โครงการแบบหลายขั้น: บทบาท แผนร่วม แผนภูมิแกนต์ และเทมเพลต
• สรุปและรายงานงานมอบหมาย «สำคัญ» เลือกกล่องจดหมาย ผลลัพธ์พร้อมไฟล์
• แก้ไขงานมอบหมายและโครงการได้ ผู้มอบหมายแต่งตั้งผู้แทนได้
• กำหนดส่งระบุเวลาได้ พร้อมเตือนบนโทรศัพท์ สถานะส่งถึงได้แน่นอนขึ้น
• «ภายหลัง» และ «กำลังติดตาม» บนทุกอุปกรณ์ของคุณ
• อีเมลงานมอบหมายทักทายด้วยชื่อต้น
• แก้ไขการส่งผ่านเซิร์ฟเวอร์อย่าง Mercury
</th>
<tr-TR>
• Aşamalı projeler: roller, ortak plan, Gantt şeması, şablonlar
• Görevlendirme özeti ve raporları; «Önemli», posta kutusu seçimi, dosyalı sonuç
• Görevlendirmeler ve projeler düzenlenebilir; görevlendiren bir vekil atayabilir
• Saatine kadar son tarih ve telefonda hatırlatma; durumlar daha güvenilir ulaşır
• «Daha sonra» ve «Takipte» tüm cihazlarınızda
• Görevlendirme e-postaları kişilere adıyla hitap eder
• Mercury gibi sunucularla gönderim düzeltildi
</tr-TR>
<fi-FI>
• Vaiheittaiset projektit: roolit, yhteinen suunnitelma, Gantt-kaavio, mallipohjat
• Toimeksiantojen yhteenveto ja raportit; ”Tärkeä”, postilaatikon valinta, tulos tiedostoineen
• Toimeksiantoja ja projekteja voi muokata; antaja voi nimetä sijaisen
• Määräajat kellonajalla ja muistutus puhelimeen; tila välittyy luotettavammin
• ”Myöhemmin” ja ”Seurannassa” kaikilla laitteillasi
• Toimeksiantoviestit tervehtivät etunimellä
• Korjattu lähetys Mercuryn kaltaisten palvelimien kautta
</fi-FI>
<hi-IN>
• चरणों वाले प्रोजेक्ट: भूमिकाएँ, साझा योजना, गैंट चार्ट और टेम्पलेट
• सौंपे गए कार्यों का सारांश और रिपोर्ट; «ज़रूरी», मेलबॉक्स चुनें, फ़ाइलों के साथ परिणाम
• सौंपे गए कार्य और प्रोजेक्ट संपादित करें; सौंपने वाला प्रतिनिधि चुन सकता है
• सटीक समय के साथ समय-सीमा और फ़ोन पर अनुस्मारक; स्थिति अधिक भरोसेमंद ढंग से पहुँचती है
• «बाद में» और «निगरानी में» आपके सभी डिवाइस पर
• सौंपे गए कार्यों के ईमेल में पहले नाम से अभिवादन
• Mercury जैसे सर्वर से भेजने की समस्या ठीक की गई
</hi-IN>
<cs-CZ>
• Projekty s etapami: role, společný plán, Ganttův diagram, šablony
• Přehled a zprávy úkolů; „Důležité“, výběr schránky, výsledek se soubory
• Zadané úkoly a projekty lze upravovat; zadavatel může určit zástupce
• Termíny s přesným časem a připomenutím v telefonu; stavy dorazí spolehlivěji
• „Později“ a „Sledované“ na všech vašich zařízeních
• E-maily k úkolům oslovují křestním jménem
• Opraveno odesílání přes servery jako Mercury
</cs-CZ>
<sv-SE>
• Projekt i etapper: roller, gemensam plan, Gantt-schema, mallar
• Översikt och rapporter för uppdrag; ”Viktigt”, val av brevlåda, resultat med filer
• Redigera uppdrag och projekt; uppdragsgivaren kan utse en ställföreträdare
• Deadlines med exakt tid och påminnelse i telefonen; status kommer fram säkrare
• ”Senare” och ”Bevakade” på alla dina enheter
• Mejl om uppdrag hälsar med förnamn
• Rättad sändning via servrar som Mercury
</sv-SE>
<ja-JP>
• 段階付きプロジェクト：役割、共有プラン、ガントチャート、テンプレート
• 依頼のサマリーとレポート。「重要」、メールボックスの選択、ファイル付きの成果
• 依頼とプロジェクトを編集可能。依頼者の代理も設定可能
• 期限を時刻まで指定し、スマートフォンでリマインド。ステータスがより確実に届く
• 「後で」と「追跡中」をすべてのデバイスで同期
• 依頼メールのあいさつを名前で
• Mercury などのサーバー経由の送信を修正
</ja-JP>
```
