# «Что нового» — 2.6.0 (158), относительно 2.5.3

2.5.3 ушла тестировщикам, 2.5.5 не выходила — здесь всё, что сделано после
2.5.3: 2.5.4–2.5.5 (компьютер; вход напрямую у служб) и 2.6.0 (рабочая
почта, поручения, исправления). Если в магазин публикуется сборка после
2.4.0 впервые, добавьте к текстам ниже строки из `STORE_NOTES_2.5.3.md`.
Шаги владельца — `OWNER_STEPS_2.6.0.md`.

## Сделано в 2.6.0

### Рабочая почта

- **Окно входа — «Личная почта» и «Рабочая почта».** Под адресом — плитки
  личной почты (Google, Яндекс, Microsoft, Mail.ru, iCloud, IMAP) и строки
  рабочей с пояснением: Exchange, Microsoft 365, «IMAP организации», «Вход
  через систему организации».
- **IMAP организации.** Подсказка, что спросить у администратора; поле
  «Логин (если отличается от адреса)» — и при «Войти снова», и из политики
  MDM (`account_username`); отправка входит тем же логином.
- **Серверы находятся сами:** по записям DNS домена (MX — Google
  Workspace, Яндекс 360, VK WorkMail, Microsoft 365, iCloud+; SRV по
  RFC 6186 — серверы IMAP и отправки администратора) и настройкам для
  почтовых программ. Записи DNS спрашиваются у DNS самого устройства —
  без серверов Ogneliss и посторонних служб.
- **Порт и шифрование подбираются,** если сервер не ответил на указанных
  (IMAP 993/143, SMTP 465/587/25). Проверяется только доступность — без
  пароля, лишних попыток входа нет.
- **Календарь и контакты** с сервера организации (CalDAV/CardDAV по
  RFC 6764): ищутся сами; пароль уходит только серверам домена
  организации, ответившим как сервер DAV.
- **Вход через систему организации (SSO, OAuth)** в приложении нет: окно
  объясняет, что организация может сделать форк открытого кода или
  обратиться за консультацией.

### Поручения

- **Одна беседа на поручение:** все письма — с темой первого письма, даже
  после переноса срока; этапы проекта — в беседе проекта.
- **«Напомнить» без повторов:** после нажатия кнопка — «Напомнили в 18:07»
  и полчаса не нажимается (раньше её, не видя отклика, нажимали десятки
  раз — исполнителю приходили десятки писем).
- **«Вернуть на доработку» — с пояснением,** что исправить, отовсюду
  (из быстрого просмотра раньше уходило без текста).
- **Внешние адресаты рабочего ящика** — то же предупреждение, что у
  обычного письма (поручение на личную почту отклонялось правилом
  организации без предупреждения).
- **«Задать вопрос»** больше не открывает пустое письмо: ответ на
  последнее письмо поручения, которое есть в ящике, а если писем уже нет —
  новое письмо постановщику с темой беседы и номером поручения.
  Постановщику и контролирующему — «Написать исполнителю» (меню «⋮»).
- **Письма поручения после пересинхронизации Exchange** (новые номера
  писем): «Письмо-основание» и ответы в беседу не теряются, история не
  задваивается.
- **Ответ словами** («Принято», «Готово») из обычного редактора или другой
  почты меняет статус у обеих сторон.
- **Разбор почты поручений порциями:** при большом числе писем свежие
  ответы больше не пропускаются.

### Почта и исправления

- **Длинная беседа не вытесняет ленту:** беседа из 40+ писем занимала всё
  первое окно ленты — в «Всей почте» оставалась одна строка; теперь лента
  догружается сама.
- **«Поделиться» в закрытое приложение:** редактор больше не пропадает
  через пару секунд (приложение «выбрасывало» на рабочий стол).
- **Окно «Сервер» в настройках ящика:** подписи не налезают на заголовки,
  можно сменить шифрование.
- **Android: вылет при первом открытии после простоя** (форум, Samsung S24
  и realme): система выгружала свёрнутое приложение из памяти, а при
  открытии восстановленное окно искало движок Flutter раньше, чем тот
  создавался. Теперь движок создаётся первым.
- **Синхронизация не останавливается на одном письме:** структуру
  некоторых писем Mail.ru и Яндекса почтовая библиотека не разбирала, и
  проверка папки ждала 5 минут на каждом проходе. Теперь такое письмо
  загружается без структуры (открытое — целиком, с вложениями), остальные —
  как обычно.
- **Без ложного «Требуется вход»:** обрыв связи при входе в ящик OAuth
  больше не считается отказом и не обновляет токен принудительно.
- **Причина сбоя Android — в журнале** («Сбой (Java): …» при следующем
  запуске): раньше система сообщала только «сбой приложения».

### Быстродействие и безопасность

- **Тормоза после запуска и при длинной беседе.** После запуска и каждой
  синхронизации службы читали письма целиком, с текстами (сотни писем), и
  разбирали письма поручений в основном потоке. Теперь тексты читаются
  только там, где нужны, разбор поручений — только новых писем и в фоновом
  потоке (повторный разбор 300 писем: 260 мс → 20 мс).
- **Медленные кадры — в журнале** («Медленный кадр: … мс», сводка за
  минуту): по журналу видно, когда интерфейс замирал.
- **Записи SRV не подписаны:** сервер IMAP из SRV вне домена адреса
  показывается до входа, а сервер календаря и контактов из SRV вне домена
  организации не используется — пароль ему не уходит.
- **Журнал:** логин и идентификатор устройства в адресе запроса
  ActiveSync и в строке подключения скрываются.
- **Окно входа** проверено на узком телефоне, планшете и компьютере,
  обычном и крупном шрифте — убраны переполнения.

## Сделано в 2.5.4–2.5.5 (не выходили)

### Вход и данные

- **Вход в Google, Microsoft и Яндекс — напрямую у службы** (OAuth 2.0
  с PKCE): приложение само обменивает код на токены и обновляет их, токены
  хранятся только на устройстве. Сервер входа Ogneliss остался только для
  Яндекса на Windows и Linux; ключей Google и Microsoft на нём нет.
- **Ящики Google и Microsoft, добавленные через сервер входа,** один раз
  показывают «Требуется вход» — «Войти снова» входит уже напрямую.
- **Gmail паролем приложения.** Если Google не пускает новых
  пользователей (у непроверенного приложения предел — 100 человек) или в
  сборке нет клиента Google, вход объясняет причину и сразу предлагает
  пароль приложения: подсказка про двухэтапную проверку и ссылка на
  страницу паролей Google.
- **Права Google сокращены:** `gmail.settings.basic` больше не
  запрашивается (перенос подписи из Gmail при добавлении ящика убран).
- **Логотипы отправителей (BIMI)** ищет служба погоды на сервере Ogneliss;
  для писем ящиков Google логотипы не ищутся — домены отправителей из Gmail
  на сервер не уходят.

### Почта

- **«Ответить с вложениями»** — в меню письма: ответ с файлами исходного
  письма (например, «согласовано» с документом).
- **Файлы в письмо из «Вложений»**: при прикреплении можно выбрать файлы
  из всех вложений почты.
- **Свайпы по умолчанию:** слева — прочитано / не прочитано, справа —
  удалить (у тех, кто не менял свайпы сам).

### Компьютер (Windows, macOS, Linux)

- **Сложные письма — целиком, во встроенном окне браузера** (Windows —
  WebView2, Mac — WKWebView), по умолчанию. Нет WebView2 — письмо сразу
  показывается упрощённо, без ожидания. Данные WebView2 — в папке
  пользователя (из «Program Files» окно не открывалось).
- **Письмо во всю ширину окна** — без ограничения ширины текста.
- **Правая кнопка мыши — везде, где есть удержание**; у ссылок в письме —
  «Открыть / Копировать» (у адреса почты — «Написать / Копировать адрес»).
- **Двойной щелчок:** письмо — в отдельном окне, папка с подпапками —
  свернуть или развернуть.
- **Значок закрепления панели папок** больше не перескакивает.
- **Windows: ответ пишется в обычном поле** — в WebView2 не доходила
  клавиатура, курсора не было.
- **Окна редактора** (новое письмо, ответ, пересылка — отдельным окном,
  как в Outlook) — пробная возможность, по умолчанию выключена:
  Настройки → Почта → Открытие писем.

### Сборка (для владельца)

- Ключи сборки: клиенты Google (`GOOGLE_ANDROID_CLIENT_ID`,
  `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_ID` и `_SECRET`) и
  `MS_CLIENT_ID` обязательны для входа через Google и Microsoft;
  `OAUTH_PROXY_URL` и `OAUTH_PROXY_KEY` — как раньше.
- Windows: плагины в окнах писем и редактора
  (`tool/desktop/windows/multi_window.ps1` — запускается сборкой сама).

## Кратко (RU / EN)

**RU.** Рабочая почта: окно входа с разделами «Личная» и «Рабочая»; IMAP
организации — серверы, порты, календарь и контакты находятся сами, логин
может отличаться от адреса. Поручения — одной беседой, напоминание без
повторов, доработка с пояснением. Вход в Google, Microsoft и Яндекс —
напрямую у службы, токены остаются на устройстве; ящики Google и Microsoft
один раз попросят войти снова. Gmail можно подключить паролем приложения.
На компьютере — сложные письма целиком, правая кнопка и двойной щелчок как
в Outlook.

**EN.** Work email: the sign-in screen has Personal and Work sections;
organisation IMAP finds servers, ports, calendar and contacts automatically,
and the login may differ from the address. Assignments stay in one
conversation, reminders are no longer duplicated, rework requires a comment.
Sign in to Google, Microsoft and Yandex directly with the provider; tokens
stay on your device, and Google and Microsoft mailboxes ask you to sign in
again once. Gmail can be added with an app password. On desktop: complex
emails in full, right-click and double-click as in Outlook.

## App Store — Mac (ru, en, de, fr)

Версия macOS в App Store Connect, поле «Что нового в этой версии».

```
<ru-RU>
• Рабочая почта по IMAP: серверы, порты, календарь и контакты находятся сами; логин может отличаться от адреса
• Поручения: одна беседа на поручение, напоминание без повторов, доработка с пояснением
• Сложные письма — целиком во встроенном окне, письмо во всю ширину окна
• Правая кнопка мыши и двойной щелчок — как в Outlook; меню у ссылок
• Значок закрепления панели папок больше не перескакивает
• Вход в Google, Microsoft и Яндекс — напрямую у службы; ящики Google и Microsoft один раз попросят войти снова
• Gmail можно подключить паролем приложения
• «Ответить с вложениями» и файлы в письмо из «Вложений»
• Свайпы по умолчанию: слева — прочитано, справа — удалить
• Окна редактора отдельно — пробная возможность в настройках
</ru-RU>
<en-US>
• Work email over IMAP: servers, ports, calendar and contacts are found automatically; the login may differ from the address
• Assignments: one conversation per assignment, no duplicate reminders, rework with a comment
• Complex emails in full in a built-in view, messages use the full window width
• Right-click and double-click work as in Outlook; a menu for links
• The pin icon of the folder pane no longer jumps
• Sign in to Google, Microsoft and Yandex directly with the provider; Google and Microsoft mailboxes ask you to sign in again once
• Gmail can be added with an app password
• Reply with attachments; attach files from Attachments
• Default swipes: left — read/unread, right — delete
• Separate compose windows — a trial option in Settings
</en-US>
<de-DE>
• Geschäftliche E-Mail per IMAP: Server, Ports, Kalender und Kontakte werden automatisch gefunden; der Anmeldename darf abweichen
• Aufträge: eine Unterhaltung pro Auftrag, keine doppelten Erinnerungen, Nacharbeit mit Begründung
• Komplexe E-Mails vollständig in einer integrierten Ansicht, E-Mails in voller Fensterbreite
• Rechtsklick und Doppelklick wie in Outlook; ein Menü für Links
• Das Anheften-Symbol der Ordnerleiste springt nicht mehr
• Anmeldung bei Google, Microsoft und Yandex direkt beim Anbieter; Google- und Microsoft-Postfächer bitten einmal um erneute Anmeldung
• Gmail lässt sich mit einem App-Passwort hinzufügen
• „Antworten mit Anhängen“ und Dateien aus „Anhänge“
• Standard-Wischgesten: links – gelesen, rechts – löschen
• Eigene Fenster zum Schreiben – Testfunktion in den Einstellungen
</de-DE>
<fr-FR>
• Messagerie pro en IMAP : serveurs, ports, calendrier et contacts trouvés automatiquement ; l’identifiant peut différer de l’adresse
• Tâches confiées : une conversation par tâche, plus de relances en double, retour avec commentaire
• E-mails complexes affichés en entier dans une vue intégrée, messages sur toute la largeur
• Clic droit et double-clic comme dans Outlook ; un menu pour les liens
• L’icône d’épinglage du panneau des dossiers ne saute plus
• Connexion à Google, Microsoft et Yandex directement auprès du fournisseur ; les boîtes Google et Microsoft demandent une fois de se reconnecter
• Gmail peut être ajouté avec un mot de passe d’application
• « Répondre avec pièces jointes » et fichiers depuis « Pièces jointes »
• Balayages par défaut : à gauche — lu, à droite — supprimer
• Fenêtres de rédaction séparées — option d’essai dans les Réglages
</fr-FR>
```

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Рабочая почта по IMAP: серверы, порты, календарь и контакты находятся сами; логин может отличаться от адреса
• Поручения: одна беседа на поручение, напоминание без повторов, доработка с пояснением
• Вход в Google, Microsoft и Яндекс — напрямую у службы
• Ящики Google и Microsoft один раз попросят войти снова
• Gmail можно подключить паролем приложения
• «Ответить с вложениями» и файлы в письмо из «Вложений»
• Свайпы по умолчанию: слева — прочитано, справа — удалить
• Исправления и улучшения
</ru-RU>
<en-US>
• Work email over IMAP: servers, ports, calendar and contacts are found automatically; the login may differ from the address
• Assignments: one conversation per assignment, no duplicate reminders, rework with a comment
• Sign in to Google, Microsoft and Yandex directly with the provider
• Google and Microsoft mailboxes ask you to sign in again once
• Gmail can be added with an app password
• Reply with attachments; attach files from Attachments
• Default swipes: left — read/unread, right — delete
• Fixes and improvements
</en-US>
<de-DE>
• Geschäftliche E-Mail per IMAP: Server, Ports, Kalender und Kontakte werden automatisch gefunden; der Anmeldename darf abweichen
• Aufträge: eine Unterhaltung pro Auftrag, keine doppelten Erinnerungen, Nacharbeit mit Begründung
• Anmeldung bei Google, Microsoft und Yandex direkt beim Anbieter
• Google- und Microsoft-Postfächer bitten einmal um erneute Anmeldung
• Gmail lässt sich mit einem App-Passwort hinzufügen
• „Antworten mit Anhängen“ und Dateien aus „Anhänge“
• Standard-Wischgesten: links – gelesen, rechts – löschen
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Messagerie pro en IMAP : serveurs, ports, calendrier et contacts trouvés automatiquement ; l’identifiant peut différer de l’adresse
• Tâches confiées : une conversation par tâche, plus de relances en double, retour avec commentaire
• Connexion à Google, Microsoft et Yandex directement auprès du fournisseur
• Les boîtes Google et Microsoft demandent une fois de se reconnecter
• Gmail peut être ajouté avec un mot de passe d’application
• « Répondre avec pièces jointes » et fichiers depuis « Pièces jointes »
• Balayages par défaut : à gauche — lu, à droite — supprimer
• Corrections et améliorations
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков; самый длинный — 493).

```
<ru-RU>
• Рабочая почта по IMAP: серверы, порты, календарь и контакты находятся сами; логин может отличаться от адреса
• Поручения: одна беседа на поручение, напоминание без повторов, доработка с пояснением
• Вход в Google, Microsoft и Яндекс — напрямую у службы
• Ящики Google и Microsoft один раз попросят войти снова
• Gmail можно подключить паролем приложения
• «Ответить с вложениями» и файлы в письмо из «Вложений»
• Исправления и улучшения
</ru-RU>
<en-US>
• Work email over IMAP: servers, ports, calendar and contacts are found automatically; the login may differ from the address
• Assignments: one conversation per assignment, no duplicate reminders, rework with a comment
• Sign in to Google, Microsoft and Yandex directly with the provider
• Google and Microsoft mailboxes ask you to sign in again once
• Gmail can be added with an app password
• Reply with attachments; attach files from Attachments
• Fixes and improvements
</en-US>
<de-DE>
• Geschäftliche E-Mail per IMAP: Server, Ports, Kalender und Kontakte werden automatisch gefunden; der Anmeldename darf abweichen
• Aufträge: eine Unterhaltung pro Auftrag, keine doppelten Erinnerungen, Nacharbeit mit Begründung
• Anmeldung bei Google, Microsoft und Yandex direkt beim Anbieter
• Google- und Microsoft-Postfächer bitten einmal um erneute Anmeldung
• Gmail lässt sich mit einem App-Passwort hinzufügen
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Messagerie pro en IMAP : serveurs, ports, calendrier et contacts trouvés automatiquement ; l’identifiant peut différer de l’adresse
• Tâches confiées : une conversation par tâche, plus de relances en double, retour avec commentaire
• Connexion à Google, Microsoft et Yandex directement auprès du fournisseur
• Les boîtes Google et Microsoft demandent une fois de se reconnecter
• Gmail peut être ajouté avec un mot de passe d’application
• Corrections et améliorations
</fr-FR>
<ar>
• بريد العمل عبر IMAP: يُعثر على الخوادم والمنافذ والتقويم وجهات الاتصال تلقائيًا؛ ويمكن أن يختلف اسم المستخدم عن العنوان
• التكليفات: محادثة واحدة لكل تكليف، وتذكير بلا تكرار، وإعادة للتعديل مع توضيح
• تسجيل الدخول إلى Google وMicrosoft وYandex مباشرة لدى المزوّد
• تطلب صناديق Google وMicrosoft تسجيل الدخول مرة أخرى لمرة واحدة
• يمكن إضافة Gmail بكلمة مرور التطبيق
• «الرد مع المرفقات» وإرفاق ملفات من «المرفقات»
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Munkahelyi e-mail IMAP-on: a kiszolgálókat, portokat, naptárt és névjegyeket magától megtalálja; a felhasználónév eltérhet a címtől
• Feladatok: egy beszélgetés feladatonként, ismétlés nélküli emlékeztető, visszaküldés indoklással
• Bejelentkezés a Google-, Microsoft- és Yandex-fiókba közvetlenül a szolgáltatónál
• A Google- és Microsoft-postafiókok egyszer újbóli bejelentkezést kérnek
• A Gmail alkalmazásjelszóval is hozzáadható
• Javítások és fejlesztések
</hu-HU>
<vi>
• Email công việc qua IMAP: tự tìm máy chủ, cổng, lịch và danh bạ; tên đăng nhập có thể khác địa chỉ
• Giao việc: mỗi việc một cuộc hội thoại, nhắc nhở không trùng lặp, trả lại kèm ghi chú
• Đăng nhập Google, Microsoft và Yandex trực tiếp với nhà cung cấp
• Hộp thư Google và Microsoft sẽ yêu cầu đăng nhập lại một lần
• Có thể thêm Gmail bằng mật khẩu ứng dụng
• "Trả lời kèm tệp đính kèm" và đính kèm tệp từ "Tệp đính kèm"
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Arbejdsmail via IMAP: servere, porte, kalender og kontakter findes automatisk; login kan afvige fra adressen
• Opgaver: én samtale pr. opgave, ingen dobbelte påmindelser, returnering med kommentar
• Log ind hos Google, Microsoft og Yandex direkte hos udbyderen
• Google- og Microsoft-postkasser beder én gang om nyt login
• Gmail kan tilføjes med en app-adgangskode
• »Svar med vedhæftninger« og filer fra »Vedhæftede filer«
• Rettelser og forbedringer
</da-DK>
<iw-IL>
• דואר עבודה ב-IMAP: השרתים, הפורטים, היומן ואנשי הקשר נמצאים אוטומטית; שם המשתמש יכול להיות שונה מהכתובת
• משימות: שיחה אחת לכל משימה, תזכורת בלי כפילויות, החזרה לתיקון עם הסבר
• כניסה ל-Google, Microsoft ו-Yandex ישירות אצל הספק
• תיבות Google ו-Microsoft יבקשו פעם אחת להתחבר מחדש
• אפשר להוסיף Gmail עם סיסמה לאפליקציה
• ״השב עם קבצים מצורפים״ וקבצים מ״קבצים מצורפים״
• תיקונים ושיפורים
</iw-IL>
<id>
• Email kantor lewat IMAP: server, port, kalender, dan kontak ditemukan otomatis; nama login boleh berbeda dari alamat
• Penugasan: satu percakapan per tugas, pengingat tanpa duplikat, kembalikan untuk revisi dengan catatan
• Masuk ke Google, Microsoft, dan Yandex langsung di penyedia
• Kotak surat Google dan Microsoft meminta masuk ulang sekali
• Gmail bisa ditambahkan dengan sandi aplikasi
• "Balas dengan lampiran" dan file dari "Lampiran"
• Perbaikan dan peningkatan
</id>
<es-ES>
• Correo del trabajo por IMAP: servidores, puertos, calendario y contactos se encuentran solos; el usuario puede ser distinto de la dirección
• Encargos: una conversación por encargo, recordatorios sin duplicados, devolución con comentario
• Inicio de sesión en Google, Microsoft y Yandex directamente con el proveedor
• Los buzones de Google y Microsoft piden iniciar sesión de nuevo una vez
• Gmail se puede añadir con una contraseña de aplicación
• Correcciones y mejoras
</es-ES>
<it-IT>
• Posta di lavoro via IMAP: server, porte, calendario e contatti trovati da soli; il nome utente può differire dall’indirizzo
• Incarichi: una conversazione per incarico, promemoria senza doppioni, rinvio con commento
• Accesso a Google, Microsoft e Yandex direttamente presso il provider
• Le caselle Google e Microsoft chiedono una volta di accedere di nuovo
• Gmail si può aggiungere con una password per le app
• «Rispondi con allegati» e file dagli «Allegati»
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• IMAP 工作邮箱：自动查找服务器、端口、日历和联系人；登录名可与地址不同
• 任务委派：每项任务一个会话，提醒不再重复，退回修改需附说明
• 直接在服务提供商处登录 Google、Microsoft 和 Yandex
• Google 和 Microsoft 邮箱会要求重新登录一次
• 可使用应用专用密码添加 Gmail
• “带附件回复”，并可从“附件”中添加文件
• 修复与改进
</zh-CN>
<ko-KR>
• IMAP 업무용 메일: 서버, 포트, 캘린더, 연락처를 자동으로 찾음; 로그인 이름이 주소와 달라도 됨
• 업무 지시: 지시마다 하나의 대화, 중복 없는 알림, 사유와 함께 재작업 요청
• Google, Microsoft, Yandex 로그인을 서비스에서 직접 진행
• Google 및 Microsoft 메일함은 한 번 다시 로그인을 요청합니다
• Gmail을 앱 비밀번호로 추가 가능
• ‘첨부 파일과 함께 답장’ 및 ‘첨부 파일’에서 파일 첨부
• 수정 및 개선
</ko-KR>
<nl-NL>
• Zakelijke e-mail via IMAP: servers, poorten, agenda en contacten worden zelf gevonden; de inlognaam mag afwijken
• Opdrachten: één gesprek per opdracht, geen dubbele herinneringen, terugsturen met toelichting
• Inloggen bij Google, Microsoft en Yandex rechtstreeks bij de provider
• Google- en Microsoft-postvakken vragen één keer opnieuw in te loggen
• Gmail toevoegen kan met een app-wachtwoord
• ‘Beantwoorden met bijlagen’ en bestanden uit ‘Bijlagen’
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Jobb-e-post via IMAP: servere, porter, kalender og kontakter finnes automatisk; brukernavnet kan avvike fra adressen
• Oppdrag: én samtale per oppdrag, ingen doble påminnelser, retur med kommentar
• Pålogging hos Google, Microsoft og Yandex direkte hos leverandøren
• Google- og Microsoft-postbokser ber én gang om ny pålogging
• Gmail kan legges til med et apppassord
• «Svar med vedlegg» og filer fra «Vedlegg»
• Rettelser og forbedringer
</no-NO>
<pl-PL>
• Poczta służbowa przez IMAP: serwery, porty, kalendarz i kontakty znajdowane same; login może być inny niż adres
• Zlecenia: jedna rozmowa na zlecenie, przypomnienia bez powtórzeń, zwrot do poprawy z opisem
• Logowanie do Google, Microsoft i Yandex bezpośrednio u dostawcy
• Skrzynki Google i Microsoft raz poproszą o ponowne logowanie
• Gmail można dodać hasłem do aplikacji
• „Odpowiedz z załącznikami” i pliki z „Załączników”
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• E-mail corporativo por IMAP: servidores, portas, agenda e contatos encontrados sozinhos; o login pode ser diferente do endereço
• Atribuições: uma conversa por tarefa, lembretes sem duplicatas, devolução com comentário
• Login no Google, Microsoft e Yandex direto com o provedor
• Caixas do Google e da Microsoft pedem novo login uma vez
• O Gmail pode ser adicionado com uma senha de app
• "Responder com anexos" e arquivos de "Anexos"
• Correções e melhorias
</pt-BR>
<ro>
• E-mail de serviciu prin IMAP: servere, porturi, calendar și contacte găsite automat; numele de utilizator poate diferi de adresă
• Sarcini: o conversație pe sarcină, mementouri fără dubluri, retur pentru refacere cu explicație
• Conectare la Google, Microsoft și Yandex direct la furnizor
• Căsuțele Google și Microsoft cer o dată reconectarea
• Gmail poate fi adăugat cu o parolă pentru aplicații
• „Răspunde cu atașamente” și fișiere din „Atașamente”
• Corecturi și îmbunătățiri
</ro>
<sk>
• Pracovný e-mail cez IMAP: servery, porty, kalendár a kontakty sa nájdu samy; prihlasovacie meno sa môže líšiť od adresy
• Úlohy: jedna konverzácia na úlohu, pripomienky bez opakovania, vrátenie na prepracovanie s vysvetlením
• Prihlásenie do Googlu, Microsoftu a Yandexu priamo u poskytovateľa
• Schránky Google a Microsoft raz požiadajú o nové prihlásenie
• Gmail možno pridať heslom aplikácie
• „Odpovedať s prílohami“ a súbory z „Príloh“
• Opravy a vylepšenia
</sk>
<th>
• อีเมลที่ทำงานผ่าน IMAP: หาเซิร์ฟเวอร์ พอร์ต ปฏิทิน และรายชื่อติดต่อให้เอง ชื่อเข้าสู่ระบบต่างจากที่อยู่ได้
• งานมอบหมาย: หนึ่งการสนทนาต่อหนึ่งงาน เตือนไม่ซ้ำ ส่งกลับแก้ไขพร้อมคำอธิบาย
• ลงชื่อเข้าใช้ Google, Microsoft และ Yandex โดยตรงกับผู้ให้บริการ
• กล่องจดหมาย Google และ Microsoft จะขอให้ลงชื่อเข้าใช้ใหม่หนึ่งครั้ง
• เพิ่ม Gmail ด้วยรหัสผ่านสำหรับแอปได้
• “ตอบกลับพร้อมไฟล์แนบ” และแนบไฟล์จาก “ไฟล์แนบ”
• แก้ไขและปรับปรุง
</th>
<tr-TR>
• IMAP ile iş e-postası: sunucular, portlar, takvim ve kişiler kendiliğinden bulunur; kullanıcı adı adresten farklı olabilir
• Görevlendirmeler: görev başına tek konuşma, tekrarsız hatırlatma, açıklamalı düzeltmeye iade
• Google, Microsoft ve Yandex'e doğrudan hizmet sağlayıcıda giriş
• Google ve Microsoft posta kutuları bir kez yeniden giriş ister
• Gmail uygulama şifresiyle eklenebilir
• “Eklerle yanıtla” ve “Ekler”den dosya ekleme
• Düzeltmeler ve iyileştirmeler
</tr-TR>
<fi-FI>
• Työsähköposti IMAPilla: palvelimet, portit, kalenteri ja yhteystiedot löytyvät itse; käyttäjätunnus voi poiketa osoitteesta
• Toimeksiannot: yksi keskustelu toimeksiantoa kohden, ei toistuvia muistutuksia, palautus perustelulla
• Kirjautuminen Googleen, Microsoftiin ja Yandexiin suoraan palveluntarjoajalla
• Google- ja Microsoft-postilaatikot pyytävät kerran kirjautumaan uudelleen
• Gmailin voi lisätä sovellussalasanalla
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• IMAP से कार्यालय ईमेल: सर्वर, पोर्ट, कैलेंडर और संपर्क अपने-आप मिलते हैं; लॉगिन पते से अलग हो सकता है
• कार्य सौंपना: हर कार्य की एक बातचीत, दोहराव रहित अनुस्मारक, कारण सहित सुधार हेतु वापसी
• Google, Microsoft और Yandex में सीधे सेवा प्रदाता के पास साइन इन
• Google और Microsoft मेलबॉक्स एक बार फिर से साइन इन माँगेंगे
• Gmail को ऐप पासवर्ड से जोड़ा जा सकता है
• “अटैचमेंट के साथ जवाब दें” और “अटैचमेंट” से फ़ाइलें
• सुधार और बेहतरियाँ
</hi-IN>
<cs-CZ>
• Pracovní e-mail přes IMAP: servery, porty, kalendář a kontakty se najdou samy; přihlašovací jméno se může lišit od adresy
• Úkoly: jedna konverzace na úkol, připomínky bez opakování, vrácení k přepracování s vysvětlením
• Přihlášení ke Googlu, Microsoftu a Yandexu přímo u poskytovatele
• Schránky Google a Microsoft jednou požádají o nové přihlášení
• Gmail lze přidat heslem aplikace
• „Odpovědět s přílohami“ a soubory z „Příloh“
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Jobbmejl via IMAP: servrar, portar, kalender och kontakter hittas automatiskt; inloggningen kan skilja sig från adressen
• Uppdrag: en konversation per uppdrag, inga dubbla påminnelser, retur med kommentar
• Inloggning hos Google, Microsoft och Yandex direkt hos leverantören
• Google- och Microsoft-brevlådor ber en gång om ny inloggning
• Gmail kan läggas till med ett applösenord
• ”Svara med bilagor” och filer från ”Bilagor”
• Rättelser och förbättringar
</sv-SE>
<ja-JP>
• IMAP の仕事用メール：サーバー、ポート、カレンダー、連絡先を自動検出。ログイン名はアドレスと異なっても可
• 指示：指示ごとに 1 つの会話、催促の重複なし、理由付きで差し戻し
• Google、Microsoft、Yandex へのログインをサービスで直接実行
• Google と Microsoft のメールボックスは一度だけ再ログインを求めます
• Gmail をアプリ パスワードで追加可能
• 「添付ファイル付きで返信」と「添付ファイル」からの添付
• 修正と改善
</ja-JP>
```
