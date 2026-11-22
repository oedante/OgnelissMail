# «Что нового» — 2.6.8 (169), относительно 2.6.7 (168)

Просьба владельца 21.11.2026: «поднимай версию и сборку». Шаги владельца —
`OWNER_STEPS_2.6.8.md`.

## Сделано в 2.6.8

- **Папка «Исходящие»** — в панели папок, открывается в ленте, как
  «Входящие» и «Черновики». Письмо попадает туда сразу после «Отправить» —
  и во время отсчёта перед отправкой («Отправка через 5 с»), и отложенное.
  «Отменить» — кнопкой на письме или одним свайпом влево: письмо не уходит
  и возвращается в «Черновики». «Изменить» — в редактор, «Отправить
  сейчас». Отправленное исчезает из папки сразу; не отправленное остаётся с
  причиной и «Отправить снова». Уведомление «Не отправлено» открывает
  «Исходящие». У ящика своя папка «Исходящие» на сервере (Exchange, часть
  IMAP) — она и есть эта папка, на своём месте в списке, без второй строки;
  письма, которые лежат в ней на сервере, открываются строкой внизу.
- **Пересланные контакты и группы контактов Outlook** — во вложенном
  письме (.eml, .msg) и файлом .vcf: «Сохранить группу» (в «Группы
  рассылки») и «Добавить контакт» у каждого участника и контакта.
- **Вложенное письмо уходит целым.** Раньше Ogneliss отправлял пересланное
  вложением письмо так, что получатель видел вместо него строки base64;
  уже пришедшие такие вложения теперь открываются.
- **Перевод вложенных писем** .eml и .msg — кнопка «Перевести» под
  заголовком письма.
- **Свои приветствия**: первым в конструкторе — «Доброе утро / Добрый день
  / Добрый вечер» (меняется по времени суток), кнопка «Новая строка» —
  приветствие в несколько строк (дата под приветствием), поля больше не
  склеиваются с текстом. Порядок своих приветствий — «Выше» и «Ниже»; в
  этом порядке они в выборе по умолчанию и в кнопке «Приветствие» письма.
- **Виджеты.** «Мой день» (и вкладка виджета «Календарь») — разделами
  сверху вниз, как список писем: «Предстоит», «В работе» (с письмами на
  контроле), «Готово»; погода в шапке. Задача на день с напоминанием — во
  время напоминания. «Почта» — название ящика, которое вы задали;
  «Прочитано» и «Архив» — значок с подписью.
- **Логотипы отправителей BIMI — и у писем Gmail и любых IMAP-ящиков**
  (решение владельца 21.11.2026). С 2.5.5 у ящиков Google логотип не
  искался (правила Google к данным, полученным входом Google); с 2.6.7
  почта Gmail идёт по паролю приложения, и это ограничение снято.
  Рабочая почта Exchange — по-прежнему без серверов Ogneliss. Логотип
  показывается, если сервер ящика подтвердил отправителя (DMARC) и домен
  публикует запись BIMI — чаще всего это крупные компании; у остальных —
  значок сайта, как раньше.
- **Длинные беседы открываются без подвисания** (владелец 21.11.2026).
  Блок «Беседа» под письмом строил все письма беседы сразу: на беседе из
  400 писем — 3,3 с до первого кадра и 1,6 с на каждую перерисовку
  письма. Теперь — 7 писем вокруг открытого, «Более новые» / «Более
  ранние» добавляют по 20, «Вся беседа» открывает экран беседы; 0,13 с.
  Поиск по беседе больше не тянет в память полные тексты всех писем.
- **Беседы без пустых карточек и без дублей** (владелец 21.11.2026).
  Только что отправленный ответ (быстрый и из редактора) сразу в беседе с
  текстом; временная строка убирается после каждой синхронизации — раньше
  она могла остаться рядом с серверной копией навсегда (письмо дважды: с
  приветствием и подписью и одним набранным текстом). Карточки, текст
  которых догружается в фоне, заполняются сами, без выхода из беседы.
- **Меньше расход батареи и трафика, синхронизация надёжнее** (владелец
  21–22.11.2026, по журналам). Exchange (ActiveSync): после обрыва
  push-соединения пропущенное догоняется одной проверкой ящика, а не
  запросом к каждой из 25 папок. Смена сети (Wi-Fi ↔ мобильная) —
  соединения IMAP закрываются сразу, синхронизация не ждёт тайм-аута
  (бывало по 3 минуты). Одни и те же вложения и картинки письма больше не
  скачиваются повторно. IMAP: список папок — не чаще раза в 30 минут
  («Обновить» — сразу), заметки не перечитываются, если не менялись, новое
  письмо — без сверки номеров всей папки (давало рывки ленты по
  300–400 мс). Календарь и контакты Gmail и iCloud — не чаще раза в
  15 минут и в фоновых проверках. Все выбранные папки проверяются по
  расписанию ящика, которое задал пользователь, и в свёрнутом приложении.
- **Журнал для разбора подтормаживаний**: у медленного кадра записано, что
  в это время шло («главный поток: письмо: разбор HTML 420 мс; шло:
  синхронизация: папка Входящие»); кадр на сворачивании приложения больше
  не считается подтормаживанием.
- **Уведомления VIP при выключенной категории «VIP-почта»** в настройках
  Android — приходят обычным уведомлением «Почта», а не пропадают.
- **«Календарь и контакты Google» в настройках ящика — честно**: если на
  странице входа Google не отмечены галочки (календарь, контакты, фото
  собеседников), пункт пишет, чего нет, и повторный вход по нажатию даёт
  их отметить. Раньше было «подключены», а календарь и фото молчали.
- **Android: базовый профиль запуска** снят на эмуляторе в CI и входит в
  сборку — быстрее холодный старт и первая прокрутка ленты.
- Компьютер и планшет: «Предстоящие» в календаре на пустые две недели —
  «Ближайшие 2 недели свободны»; кнопки письма в «Исходящих» не встают
  столбиком в узкой ленте.
- **Без «RE:», «FW:»** в списке писем, беседах и уведомлениях — только в
  самом письме.
- **Черновик — на сервере, пока письмо пишется** (IMAP и Exchange): не на
  каждое нажатие, а не чаще раза в 30 секунд, пока письмо меняется; сразу —
  по «Сохранить» и при сворачивании приложения. Новая версия заменяет прежнюю — в «Черновиках»
  один черновик; при закрытии письма та же версия второй раз не уходит.
  Раньше черновик уходил на сервер только при закрытии письма. Файлы
  больше 2 МБ — при сворачивании и закрытии, не каждые 30 секунд.
- **Черновик ответа — с заголовками ответа** (In-Reply-To, References;
  IMAP и EWS): веб-почта, которая собирает беседы по заголовкам (Gmail),
  ставит его в беседу исходного письма, а ответ, отправленный из
  черновика на другом устройстве или в другой программе, встаёт в ту же
  переписку у получателя. Ogneliss на другом устройстве находит
  исходное письмо по этим заголовкам и после отправки отмечает его
  «Отвечено». ActiveSync таких полей у черновика не принимает.
- **Черновики с сервера** (папка «Черновики» Gmail и других ящиков IMAP) в
  беседе и на экране письма — черновики: нажатие открывает редактор, внизу
  «Редактировать», а не «Ответить» и «Переслать»; в «Расписании»
  календаря у задачи на завтра — «Срок», а не «Срок сегодня».
- Имена вложений вида `utf-8''%D0%9A…` расшифровываются; iCloud:
  «Drafts» — «Черновики»; Корзина и Спам: «Очистить» первой; оформление
  шапки «Заливка» учитывает цвет значков, «Градиент» работает; на
  компьютере нет плашки «Открыть в браузере» над письмом, показанным
  целиком.

## Кратко (RU / EN)

**RU.** Папка «Исходящие»: письмо видно сразу после «Отправить», его можно
отменить кнопкой или свайпом, ошибки отправки остаются в папке. Пересланные
контакты и группы Outlook сохраняются себе в один шаг, вложенные письма
переводятся и пересылаются без искажений. Приветствия — в несколько строк и
в своём порядке. «Мой день» в виджетах — списком и с погодой, в виджете
почты — ваши названия ящиков. Длинные беседы открываются без подвисания,
синхронизация легче — меньше расход батареи и трафика.

**EN.** New Outbox folder: a message appears there as soon as you tap Send,
you can undo it with a button or a swipe, and sending errors stay visible.
Forwarded Outlook contacts and contact groups can be saved in one step;
attached messages can be translated and are forwarded intact. Greetings can
span several lines, in your own order. “My day” in widgets is a list with
the weather, and the mail widget shows your mailbox names. Long
conversations open without lag, and lighter syncing uses less battery and
data.

## Google Play — короткий текст (27 языков)

```
<ru-RU>
• Папка «Исходящие»: письма с отсчётом, «Отменить», ошибки отправки
• Пересланные контакты и группы Outlook — сохранить себе
• Перевод вложенных писем .eml и .msg
• «Мой день» в виджетах — списком и с погодой
• Приветствия в несколько строк, свой порядок вариантов
• Длинные беседы — без подвисаний, меньше расход батареи
• Исправления и улучшения
</ru-RU>
<en-US>
• Outbox folder: send countdown, “Undo”, sending errors
• Save forwarded Outlook contacts and contact groups
• Translate attached .eml and .msg messages
• “My day” in widgets — as a list, with the weather
• Multi-line greetings, your own order of greetings
• Long conversations open without lag; lower battery use
• Bug fixes and improvements
</en-US>
<de-DE>
• Ordner „Postausgang“: Countdown, „Rückgängig“, Sendefehler
• Weitergeleitete Outlook-Kontakte und -Gruppen speichern
• Angehängte .eml- und .msg-Nachrichten übersetzen
• „Mein Tag“ in Widgets – als Liste, mit Wetter
• Mehrzeilige Begrüßungen, eigene Reihenfolge
• Lange Unterhaltungen ohne Ruckeln, weniger Akkuverbrauch
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Dossier « Boîte d’envoi » : compte à rebours, « Annuler », erreurs d’envoi
• Enregistrer les contacts et groupes Outlook transférés
• Traduction des messages .eml et .msg joints
• « Ma journée » dans les widgets — en liste, avec la météo
• Salutations sur plusieurs lignes, ordre personnalisé
• Longues conversations sans ralentissement, moins de batterie consommée
• Corrections et améliorations
</fr-FR>
<ar>
• مجلد «البريد الصادر»: عد تنازلي للإرسال و«تراجع» وأخطاء الإرسال
• حفظ جهات اتصال ومجموعات Outlook المُعاد توجيهها
• ترجمة رسائل ‎.eml و‎.msg المرفقة
• «يومي» في الأدوات — كقائمة ومع الطقس
• تحيات متعددة الأسطر وترتيب خاص بك
• المحادثات الطويلة تُفتح دون تأخير، واستهلاك أقل للبطارية
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Postázandó mappa: visszaszámlálás, „Visszavonás”, küldési hibák
• Továbbított Outlook-névjegyek és -csoportok mentése
• Csatolt .eml és .msg üzenetek fordítása
• „Napom” a widgetekben – listaként, időjárással
• Többsoros üdvözlések, saját sorrend
• Hosszú beszélgetések akadás nélkül, kisebb akkumulátor-használat
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Thư mục Hộp thư đi: đếm ngược khi gửi, “Hoàn tác”, lỗi gửi
• Lưu danh bạ và nhóm Outlook được chuyển tiếp
• Dịch thư đính kèm .eml và .msg
• “Ngày của tôi” trong tiện ích — dạng danh sách, có thời tiết
• Lời chào nhiều dòng, tự sắp xếp thứ tự
• Cuộc trò chuyện dài mở không bị giật, tiết kiệm pin hơn
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Udbakke-mappe: nedtælling, “Fortryd”, afsendelsesfejl
• Gem videresendte Outlook-kontakter og -grupper
• Oversæt vedhæftede .eml- og .msg-beskeder
• “Min dag” i widgets – som liste, med vejret
• Hilsner på flere linjer, din egen rækkefølge
• Lange samtaler uden hak, lavere batteriforbrug
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• תיקיית דואר יוצא: ספירה לאחור, „ביטול”, שגיאות שליחה
• שמירת אנשי קשר וקבוצות Outlook שהועברו
• תרגום הודעות ‎.eml ו־‎.msg מצורפות
• „היום שלי” בווידג'טים — כרשימה, עם מזג האוויר
• ברכות בכמה שורות, סדר משלך
• שיחות ארוכות נפתחות בלי תקיעות, צריכת סוללה נמוכה יותר
• תיקוני באגים ושיפורים
</iw-IL>
<id>
• Folder Kotak Keluar: hitung mundur, “Urungkan”, galat pengiriman
• Simpan kontak dan grup Outlook yang diteruskan
• Terjemahkan pesan lampiran .eml dan .msg
• “Hari saya” di widget — berupa daftar, dengan cuaca
• Salam beberapa baris, urutan sendiri
• Percakapan panjang tanpa tersendat, lebih hemat baterai
• Perbaikan bug dan peningkatan
</id>
<es-ES>
• Carpeta Bandeja de salida: cuenta atrás, «Deshacer», errores de envío
• Guardar contactos y grupos de Outlook reenviados
• Traducción de mensajes .eml y .msg adjuntos
• «Mi día» en los widgets: en lista y con el tiempo
• Saludos de varias líneas, orden personalizado
• Conversaciones largas sin bloqueos, menor consumo de batería
• Correcciones y mejoras
</es-ES>
<it-IT>
• Cartella Posta in uscita: conto alla rovescia, «Annulla», errori di invio
• Salva contatti e gruppi Outlook inoltrati
• Traduzione dei messaggi .eml e .msg allegati
• «La mia giornata» nei widget: in elenco, con il meteo
• Saluti su più righe, ordine personalizzato
• Conversazioni lunghe senza rallentamenti, minor consumo di batteria
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 发件箱文件夹：发送倒计时、“撤销”、发送错误
• 保存转发的 Outlook 联系人和联系人组
• 翻译附件中的 .eml 和 .msg 邮件
• 小组件中的“我的一天”——列表显示，附天气
• 多行问候语，自定顺序
• 长会话打开不再卡顿，更省电
• 错误修复和改进
</zh-CN>
<ko-KR>
• 보낼 편지함 폴더: 전송 카운트다운, '실행 취소', 전송 오류
• 전달된 Outlook 연락처와 연락처 그룹 저장
• 첨부된 .eml 및 .msg 메일 번역
• 위젯의 '나의 하루' — 목록으로, 날씨와 함께
• 여러 줄 인사말, 순서 직접 지정
• 긴 대화도 끊김 없이 열림, 배터리 사용량 감소
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Map Postvak UIT: aftellen, ‘Ongedaan maken’, verzendfouten
• Doorgestuurde Outlook-contacten en -groepen opslaan
• Bijgevoegde .eml- en .msg-berichten vertalen
• ‘Mijn dag’ in widgets – als lijst, met het weer
• Begroetingen over meerdere regels, eigen volgorde
• Lange gesprekken zonder haperingen, lager batterijverbruik
• Bugfixes en verbeteringen
</nl-NL>
<no-NO>
• Utboks-mappe: nedtelling, «Angre», sendefeil
• Lagre videresendte Outlook-kontakter og -grupper
• Oversett vedlagte .eml- og .msg-meldinger
• «Min dag» i moduler – som liste, med været
• Hilsener over flere linjer, egen rekkefølge
• Lange samtaler uten hakking, lavere batteribruk
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Folder Skrzynka nadawcza: odliczanie, „Cofnij”, błędy wysyłki
• Zapisywanie przekazanych kontaktów i grup Outlook
• Tłumaczenie załączonych wiadomości .eml i .msg
• „Mój dzień” w widżetach — jako lista, z pogodą
• Powitania w kilku wierszach, własna kolejność
• Długie konwersacje bez zacięć, mniejsze zużycie baterii
• Poprawki błędów i ulepszenia
</pl-PL>
<pt-BR>
• Pasta Caixa de saída: contagem regressiva, “Desfazer”, erros de envio
• Salve contatos e grupos do Outlook encaminhados
• Tradução de mensagens .eml e .msg anexadas
• “Meu dia” nos widgets — em lista, com a previsão do tempo
• Saudações em várias linhas, ordem personalizada
• Conversas longas sem travamentos, menor consumo de bateria
• Correções e melhorias
</pt-BR>
<ro>
• Dosarul Mesaje de trimis: numărătoare inversă, „Anulează”, erori de trimitere
• Salvați contactele și grupurile Outlook redirecționate
• Traducerea mesajelor .eml și .msg atașate
• „Ziua mea” în widgeturi — ca listă, cu vremea
• Saluturi pe mai multe rânduri, ordine proprie
• Conversațiile lungi se deschid fără blocaje, consum mai mic de baterie
• Remedieri și îmbunătățiri
</ro>
<sk>
• Priečinok Pošta na odoslanie: odpočítavanie, „Späť“, chyby odoslania
• Uloženie preposlaných kontaktov a skupín Outlooku
• Preklad priložených správ .eml a .msg
• „Môj deň“ vo widgetoch – ako zoznam, s počasím
• Viacriadkové pozdravy, vlastné poradie
• Dlhé konverzácie bez sekania, nižšia spotreba batérie
• Opravy chýb a vylepšenia
</sk>
<th>
• โฟลเดอร์กล่องขาออก: นับถอยหลังก่อนส่ง “เลิกทำ” และข้อผิดพลาดการส่ง
• บันทึกรายชื่อและกลุ่มรายชื่อ Outlook ที่ส่งต่อมา
• แปลอีเมลแนบ .eml และ .msg
• “วันของฉัน” ในวิดเจ็ต — แบบรายการ พร้อมสภาพอากาศ
• คำทักทายหลายบรรทัด จัดลำดับเองได้
• การสนทนายาวเปิดได้ไม่สะดุด ประหยัดแบตเตอรี่มากขึ้น
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Giden Kutusu klasörü: geri sayım, “Geri al”, gönderme hataları
• İletilen Outlook kişilerini ve gruplarını kaydedin
• Ekli .eml ve .msg iletilerini çevirin
• Widget'larda “Günüm” — liste halinde, hava durumuyla
• Çok satırlı selamlar, kendi sıranız
• Uzun konuşmalar takılmadan açılır, daha az pil tüketimi
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Lähtevät-kansio: lähetyksen lähtölaskenta, ”Kumoa”, lähetysvirheet
• Tallenna edelleenlähetetyt Outlook-yhteystiedot ja -ryhmät
• Liitettyjen .eml- ja .msg-viestien käännös
• ”Oma päivä” pienoisohjelmissa – listana, säätiedon kanssa
• Monirivisiä tervehdyksiä, oma järjestys
• Pitkät keskustelut ilman nykimistä, pienempi akunkulutus
• Virheenkorjauksia ja parannuksia
</fi-FI>
<hi-IN>
• आउटबॉक्स फ़ोल्डर: भेजने की उलटी गिनती, “पूर्ववत करें”, भेजने की त्रुटियाँ
• अग्रेषित Outlook संपर्क और संपर्क समूह सहेजें
• संलग्न .eml और .msg ईमेल का अनुवाद
• विजेट में “मेरा दिन” — सूची के रूप में, मौसम के साथ
• कई पंक्तियों वाले अभिवादन, अपना क्रम
• लंबी बातचीत बिना अटके खुलती है, बैटरी की कम खपत
• बग फ़िक्स और सुधार
</hi-IN>
<cs-CZ>
• Složka K odeslání: odpočet, „Zpět“, chyby odeslání
• Uložení přeposlaných kontaktů a skupin z Outlooku
• Překlad přiložených zpráv .eml a .msg
• „Můj den“ ve widgetech – jako seznam, s počasím
• Víceřádkové pozdravy, vlastní pořadí
• Dlouhé konverzace bez zasekávání, nižší spotřeba baterie
• Opravy chyb a vylepšení
</cs-CZ>
<sv-SE>
• Mappen Utkorg: nedräkning, ”Ångra”, sändningsfel
• Spara vidarebefordrade Outlook-kontakter och -grupper
• Översätt bifogade .eml- och .msg-meddelanden
• ”Min dag” i widgetar – som lista, med vädret
• Hälsningar på flera rader, egen ordning
• Långa konversationer utan hack, lägre batteriförbrukning
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• 送信トレイ フォルダー：送信前のカウントダウン、「取り消し」、送信エラー
• 転送された Outlook の連絡先と連絡先グループを保存
• 添付された .eml / .msg メールを翻訳
• ウィジェットの「今日の予定」をリスト表示、天気付き
• 複数行の挨拶、並び順を自由に
• 長い会話もスムーズに表示、バッテリー消費を削減
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Виджеты iPhone в этой версии не менялись — вместо строки о виджетах строка о «RE:/FW:».

```
<ru-RU>
• Папка «Исходящие»: письма с отсчётом, «Отменить», ошибки отправки
• Пересланные контакты и группы Outlook — сохранить себе
• Перевод вложенных писем .eml и .msg
• Без «RE:» и «FW:» в списке писем и уведомлениях
• Приветствия в несколько строк, свой порядок вариантов
• Длинные беседы — без подвисаний, меньше расход батареи
• Исправления и улучшения
</ru-RU>
<en-US>
• Outbox folder: send countdown, “Undo”, sending errors
• Save forwarded Outlook contacts and contact groups
• Translate attached .eml and .msg messages
• No “RE:” and “FW:” in the message list and notifications
• Multi-line greetings, your own order of greetings
• Long conversations open without lag; lower battery use
• Bug fixes and improvements
</en-US>
<de-DE>
• Ordner „Postausgang“: Countdown, „Rückgängig“, Sendefehler
• Weitergeleitete Outlook-Kontakte und -Gruppen speichern
• Angehängte .eml- und .msg-Nachrichten übersetzen
• Kein „RE:“ und „FW:“ in der Nachrichtenliste und in Mitteilungen
• Mehrzeilige Begrüßungen, eigene Reihenfolge
• Lange Unterhaltungen ohne Ruckeln, weniger Akkuverbrauch
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Dossier « Boîte d’envoi » : compte à rebours, « Annuler », erreurs d’envoi
• Enregistrer les contacts et groupes Outlook transférés
• Traduction des messages .eml et .msg joints
• Plus de « RE: » ni « FW: » dans la liste des messages et les notifications
• Salutations sur plusieurs lignes, ordre personnalisé
• Longues conversations sans ralentissement, moins de batterie consommée
• Corrections et améliorations
</fr-FR>
```
