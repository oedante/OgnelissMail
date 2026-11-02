# «Что нового» — 1.10.0 (131)

Список владельца от 31.10.2026 (19 пунктов) и задание D1 (iPad и
компьютер). В сборке 1.9.0 (130) этого ещё не было.

Что изменилось (для разработчика):

- **Оформление** («Настройки → Оформление»): темы в духе Telegram, цвет
  акцента, оттенок ленты, скругление, плотность ленты (компактная, обычная,
  просторная), анимация открытия письма и закрытие свайпом вниз (по
  умолчанию выключены).
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
• Farbthemen, Listendichte, dunkle E-Mails ohne Invertierung
• E-Mails und eigenen Text auf dem Gerät übersetzen (ab iOS 18)
• Datum in einer E-Mail antippen: Termin oder Erinnerung anlegen
• Nicht zugestellte E-Mails sind markiert, mit Grund
• Mitteilungen mit dem Foto des Absenders
• Logos verifizierter Absender (BIMI)
• Siri und Kurzbefehle: neue E-Mail, Termin, Ungelesen, Mein Tag
• iPad: Ordnerleiste in der Breite anpassbar, E-Mails auf Ordner ziehen
• IMAP: schnelle Synchronisierung; neues Postfach lädt sofort
</de-DE>
<fr-FR>
• Thèmes de couleur, densité de la liste, messages sombres sans inversion
• Traduction des messages et de votre texte sur l’appareil (iOS 18 ou ultérieur)
• Touchez une date dans un message pour créer une réunion ou un rappel
• Les messages non distribués sont signalés, avec la raison
• Notifications avec la photo de l’expéditeur
• Logos des expéditeurs vérifiés (BIMI)
• Siri et Raccourcis : nouvel e-mail, réunion, non lus, Ma journée
• iPad : volet des dossiers redimensionnable, glisser les messages sur un dossier
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
• Nicht zugestellte Nachrichten sind markiert
• Benachrichtigungen mit Foto des Absenders
• Logos verifizierter Absender (BIMI)
• App-Verknüpfungen: Neue Nachricht, Neuer Termin, Mein Tag
• Tablet: Ordnerleiste verstellbar, Mails in Ordner ziehen
• Schnellere IMAP-Synchronisierung
</de-DE>
<fr-FR>
• Thèmes de couleurs, densité de liste, e-mails sombres sans inversion
• Traduction des e-mails et de vos textes sur l’appareil
• Touchez une date du message : réunion ou rappel
• Messages non distribués signalés
• Notifications avec photo de l’expéditeur
• Logos des expéditeurs vérifiés (BIMI)
• Raccourcis : Nouveau message, Nouvelle réunion, Ma journée
• Tablette : volet des dossiers ajustable, e-mails glissés vers un dossier
• Synchronisation IMAP plus rapide
</fr-FR>
<ar>
• أنساق ألوان وكثافة قائمة البريد ورسائل داكنة بلا عكس للألوان
• ترجمة الرسائل ونصوصك على الجهاز
• اضغط على تاريخ في الرسالة لإضافة اجتماع أو تذكير
• تمييز الرسائل التي لم يتم تسليمها
• إشعارات مع صورة المرسل
• شعارات المرسلين الموثوقين (BIMI)
• اختصارات الأيقونة: رسالة جديدة، اجتماع جديد، يومي
• الأجهزة اللوحية: عرض المجلدات قابل للتعديل وسحب الرسائل إلى المجلدات
• مزامنة IMAP أسرع
</ar>
<hu-HU>
• Színsémák, listasűrűség, sötét levelek inverzió nélkül
• Levelek és saját szövegek fordítása az eszközön
• Koppintson egy dátumra: értekezlet vagy emlékeztető
• A ki nem kézbesített üzenetek jelölve vannak
• Értesítések a feladó fotójával
• Ellenőrzött feladók logói (BIMI)
• Ikon-parancsikonok: Új üzenet, Új értekezlet, Saját napom
• Táblagép: átméretezhető mappasáv, levelek áthúzása mappába
• Gyorsabb IMAP-szinkronizálás
</hu-HU>
<vi>
• Chủ đề màu, mật độ danh sách thư, thư tối không đảo màu
• Dịch thư và văn bản của bạn ngay trên thiết bị
• Chạm vào ngày trong thư để thêm cuộc họp hoặc lời nhắc
• Thư không gửi được sẽ được đánh dấu
• Thông báo kèm ảnh người gửi
• Logo của người gửi đã xác minh (BIMI)
• Lối tắt ở biểu tượng: Thư mới, Cuộc họp mới, Ngày của tôi
• Máy tính bảng: đổi độ rộng ngăn thư mục, kéo thư vào thư mục
• Đồng bộ IMAP nhanh hơn
</vi>
<da-DK>
• Farvetemaer, tæthed i maillisten, mørke mails uden invertering
• Oversæt mails og din egen tekst på enheden
• Tryk på en dato i en besked for at oprette et møde eller en påmindelse
• Beskeder, der ikke blev leveret, er markeret
• Notifikationer med afsenderens foto
• Logoer fra verificerede afsendere (BIMI)
• Genveje på appikonet: Ny mail, Nyt møde, Min dag
• Tablet: mappepanel med justerbar bredde, træk mails over i mapper
• Hurtigere IMAP-synkronisering
</da-DK>
<iw-IL>
• ערכות צבעים, צפיפות רשימת הדואר והודעות כהות ללא היפוך צבעים
• תרגום הודעות והטקסט שלך במכשיר
• הקשה על תאריך בהודעה מוסיפה פגישה או תזכורת
• הודעות שלא נמסרו מסומנות
• התראות עם תמונת השולח
• לוגו של שולחים מאומתים (BIMI)
• קיצורי דרך בסמל האפליקציה: הודעה חדשה, פגישה חדשה, היום שלי
• טאבלט: רוחב חלונית התיקיות ניתן לשינוי, גרירת הודעות לתיקיות
• סנכרון IMAP מהיר יותר
</iw-IL>
<id>
• Tema warna, kerapatan daftar, email gelap tanpa inversi
• Terjemahkan email dan teks Anda sendiri di perangkat
• Ketuk tanggal di pesan untuk menambah rapat atau pengingat
• Pesan yang tidak terkirim diberi tanda
• Notifikasi dengan foto pengirim
• Logo pengirim terverifikasi (BIMI)
• Pintasan ikon aplikasi: Email baru, Rapat baru, Hari saya
• Tablet: lebar panel folder dapat diubah, seret email ke folder
• Sinkronisasi IMAP lebih cepat
</id>
<es-ES>
• Temas de color, densidad de lista y correo oscuro sin inversión
• Traduce correos y tu texto en el dispositivo
• Toca una fecha del mensaje para crear una reunión o recordatorio
• Los correos no entregados se marcan
• Notificaciones con la foto del remitente
• Logotipos de remitentes verificados (BIMI)
• Accesos directos: Nuevo mensaje, Nueva reunión, Mi día
• Tabletas: panel de carpetas ajustable y arrastrar correos a carpetas
• Sincronización IMAP más rápida
</es-ES>
<it-IT>
• Temi colori, densità dell'elenco e posta scura senza inversione
• Traduci email e testi che scrivi sul dispositivo
• Tocca una data nel messaggio per creare riunione o promemoria
• Messaggi non recapitati contrassegnati
• Notifiche con la foto del mittente
• Loghi dei mittenti verificati (BIMI)
• Scorciatoie: Nuovo messaggio, Nuova riunione, Il mio giorno
• Tablet: pannello cartelle regolabile, email trascinabili nelle cartelle
• Sincronizzazione IMAP più veloce
</it-IT>
<zh-CN>
• 配色主题、邮件列表密度，深色邮件不再反色
• 在设备上翻译邮件和您输入的文字
• 点按邮件中的日期，即可创建会议或提醒
• 未送达的邮件会有标记
• 通知显示发件人的照片
• 显示已验证发件人的标志 (BIMI)
• 图标快捷方式：新邮件、新会议、我的一天
• 平板：可拖动调整文件夹栏宽度，可将邮件拖入文件夹
• IMAP 同步更快
</zh-CN>
<ko-KR>
• 색상 테마, 메일 목록 밀도, 반전 없는 다크 메일
• 메일과 직접 쓴 글을 기기에서 번역
• 메일 속 날짜를 탭해 회의나 미리 알림 만들기
• 전달되지 않은 메일에 표시
• 발신자 사진이 보이는 알림
• 확인된 발신자의 로고(BIMI)
• 앱 아이콘 바로가기: 새 메일, 새 회의, 오늘 일정
• 태블릿: 폴더 창 너비 조절, 메일을 폴더로 드래그
• 더 빨라진 IMAP 동기화
</ko-KR>
<nl-NL>
• Kleurenthema's, maillijstdichtheid en donkere mail zonder inversie
• Vertaal mail en je eigen tekst op het apparaat
• Tik op een datum in een bericht voor een afspraak of herinnering
• Onbezorgde berichten zijn gemarkeerd
• Meldingen met de foto van de afzender
• Logo's van geverifieerde afzenders (BIMI)
• Snelkoppelingen: Nieuw bericht, Nieuwe vergadering, Mijn dag
• Tablets: mappenpaneel verstelbaar, berichten naar mappen slepen
• Snellere IMAP-synchronisatie
</nl-NL>
<no-NO>
• Fargetema, tetthet i e-postlisten og mørk e-post uten invertering
• Oversett e-post og din egen tekst på enheten
• Trykk på en dato i en melding for å lage et møte eller en påminnelse
• Meldinger som ikke er levert, er merket
• Varsler med avsenderens bilde
• Logoer for verifiserte avsendere (BIMI)
• Snarveier på ikonet: Ny melding, Nytt møte, Min dag
• Nettbrett: justerbar bredde på mappepanelet, dra meldinger til mapper
• Raskere IMAP-synkronisering
</no-NO>
<pl-PL>
• Motywy kolorów, gęstość listy i ciemne wiadomości bez inwersji
• Tłumaczenie wiadomości i własnego tekstu na urządzeniu
• Dotknij daty w wiadomości, aby dodać spotkanie lub przypomnienie
• Niedostarczone wiadomości są oznaczone
• Powiadomienia ze zdjęciem nadawcy
• Logo zweryfikowanych nadawców (BIMI)
• Skróty na ikonie: Nowa wiadomość, Nowe spotkanie, Mój dzień
• Tablet: regulowany panel folderów, przeciąganie wiadomości do folderów
• Szybsza synchronizacja IMAP
</pl-PL>
<pt-BR>
• Temas de cores, densidade da lista e e-mails escuros sem inversão
• Traduza e-mails e seu texto no dispositivo
• Toque em uma data na mensagem para criar reunião ou lembrete
• Mensagens não entregues ficam marcadas
• Notificações com a foto do remetente
• Logotipos de remetentes verificados (BIMI)
• Atalhos: Nova mensagem, Nova reunião, Meu dia
• Tablet: painel de pastas redimensionável, arraste mensagens para pastas
• Sincronização IMAP mais rápida
</pt-BR>
<ro>
• Teme de culori, densitatea listei, mod întunecat fără inversare
• Traducerea mesajelor și a textului scris, pe dispozitiv
• Atingeți o dată din mesaj pentru o întâlnire sau un memento
• Mesajele nelivrate sunt marcate
• Notificări cu fotografia expeditorului
• Siglele expeditorilor verificați (BIMI)
• Comenzi rapide pe pictogramă: Mesaj nou, Întâlnire nouă, Ziua mea
• Tabletă: panou de dosare redimensionabil, mesaje trase pe dosare
• Sincronizare IMAP mai rapidă
</ro>
<sk>
• Farebné motívy, hustota zoznamu, tmavé správy bez inverzie farieb
• Preklad správ a vlastného textu priamo v zariadení
• Ťuknite na dátum v správe a pridajte stretnutie alebo pripomienku
• Nedoručené správy sú označené
• Upozornenia s fotkou odosielateľa
• Logá overených odosielateľov (BIMI)
• Skratky na ikone: Nová správa, Nové stretnutie, Môj deň
• Tablety: nastaviteľná šírka panela priečinkov, presun správ ťahaním do priečinka
• Rýchlejšia synchronizácia IMAP
</sk>
<th>
• ธีมสี ความหนาแน่นของรายการ โหมดมืดของอีเมลโดยไม่กลับสี
• แปลอีเมลและข้อความที่คุณเขียนบนอุปกรณ์
• แตะวันที่ในข้อความเพื่อสร้างการประชุมหรือเตือนความจำ
• ทำเครื่องหมายอีเมลที่ส่งไม่สำเร็จ
• การแจ้งเตือนพร้อมรูปผู้ส่ง
• โลโก้ของผู้ส่งที่ยืนยันแล้ว (BIMI)
• ทางลัดบนไอคอนแอป: อีเมลใหม่ การประชุมใหม่ วันของฉัน
• แท็บเล็ต: ปรับความกว้างของแผงโฟลเดอร์ได้ ลากอีเมลไปวางบนโฟลเดอร์
• ซิงค์ IMAP เร็วขึ้น
</th>
<tr-TR>
• Renk temaları, liste yoğunluğu, renk tersine çevirmeden koyu iletiler
• İletileri ve yazdığınız metni cihazda çevirin
• İletideki tarihe dokunup toplantı veya hatırlatıcı ekleyin
• Teslim edilemeyen iletiler işaretlenir
• Bildirimlerde gönderenin fotoğrafı
• Doğrulanmış gönderen logoları (BIMI)
• Simge kısayolları: Yeni ileti, Yeni toplantı, Günüm
• Tablet: boyutu ayarlanabilir klasör paneli, iletileri klasöre sürükleme
• Daha hızlı IMAP senkronizasyonu
</tr-TR>
<fi-FI>
• Väriteemat, luettelon tiheys, tummat viestit ilman värien kääntöä
• Viestien ja oman tekstin käännös laitteella
• Napauta viestin päivämäärää ja lisää kokous tai muistutus
• Toimittamatta jääneet viestit merkitään
• Ilmoituksissa lähettäjän kuva
• Vahvistettujen lähettäjien logot (BIMI)
• Pikakuvakkeet: Uusi viesti, Uusi kokous, Oma päivä
• Tabletti: säädettävä kansiopaneelin leveys, viestien vetäminen kansioon
• Nopeampi IMAP-synkronointi
</fi-FI>
<hi-IN>
• रंग थीम, सूची का घनत्व, रंग उलटे बिना डार्क मोड में संदेश
• संदेश और अपने लिखे टेक्स्ट का डिवाइस पर अनुवाद
• संदेश में तारीख पर टैप करके मीटिंग या रिमाइंडर जोड़ें
• न पहुँचे संदेशों पर निशान
• सूचनाओं में प्रेषक की फ़ोटो
• सत्यापित प्रेषकों के लोगो (BIMI)
• ऐप आइकन शॉर्टकट: नया ईमेल, नई मीटिंग, मेरा दिन
• टैबलेट: फ़ोल्डर पैनल की चौड़ाई बदलें, संदेशों को खींचकर फ़ोल्डर में डालें
• तेज़ IMAP सिंक
</hi-IN>
<cs-CZ>
• Barevné motivy, hustota seznamu, tmavé zprávy bez inverze barev
• Překlad zpráv a vlastního textu přímo v zařízení
• Klepněte na datum ve zprávě a přidejte schůzku nebo připomenutí
• Nedoručené zprávy jsou označeny
• Oznámení s fotkou odesílatele
• Loga ověřených odesílatelů (BIMI)
• Zkratky na ikoně: Nová zpráva, Nová schůzka, Můj den
• Tablety: nastavitelná šířka panelu složek, přesun zpráv přetažením do složky
• Rychlejší synchronizace IMAP
</cs-CZ>
<sv-SE>
• Färgteman, listtäthet, mörka meddelanden utan färginvertering
• Översätt meddelanden och egen text på enheten
• Tryck på ett datum i meddelandet för att lägga till möte eller påminnelse
• Obeställbara meddelanden markeras
• Aviseringar med avsändarens bild
• Logotyper för verifierade avsändare (BIMI)
• Genvägar på appikonen: Nytt meddelande, Nytt möte, Min dag
• Surfplatta: justerbar bredd på mappanelen, dra meddelanden till mappar
• Snabbare IMAP-synkronisering
</sv-SE>
<ja-JP>
• カラーテーマ、一覧の密度、色反転なしのダークメール表示
• メールと入力した文章を端末内で翻訳
• メール内の日付をタップして会議やリマインダーを追加
• 配信できなかったメールにマーク表示
• 通知に送信者の写真を表示
• 認証済み送信者のロゴ (BIMI)
• アイコンのショートカット：新規メール、新しい会議、今日の予定
• タブレット：フォルダーペインの幅を変更、メールをフォルダーにドラッグ
• IMAP の同期が高速に
</ja-JP>
```
