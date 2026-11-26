# «Что нового» — 2.7.4 (175), после 2.7.2 (173)

Просьба владельца 26.11.2026: «Подними версию до 2.7.4». В 2.7.4 — всё,
что сделано после сборки 2.7.2 (номер 174 считаем занятым выпуском 2.7.3).
Шаги владельца — `OWNER_STEPS_2.7.4.md`. Зависимости, схема базы, ключи,
манифест Android и файлы Xcode не менялись; серверы — тоже.

## Сделано в 2.7.4

- **Сводка ящиков** (предложение пользователя с 4PDA 25.11.2026, решение
  владельца 26.11.2026: «давай попробуем»; отдельный раздел, как «Мой
  день»). Карточка на каждый ящик: портрет и название, когда почта
  обновлялась, число непрочитанных во «Входящих», три последних
  непрочитанных письма («и ещё N»), папки, выбранные для сводки (удержание
  карточки или «⋮» → «Папки на сводке»), «Исходящие» — если там что-то
  ждёт (красным, если письмо не ушло), и «Вся почта» ящика с её числом.
  Наверху — «Все ящики». Нажатие на карточку — «Входящие» ящика в ленте,
  на папку — эта папка, на письмо — сразу письмо. Сводку можно поставить
  на нижнюю панель («Оформление → Нижняя панель»), она есть в «Избранном» меню и
  в боковой панели на компьютере.
- **Начальный экран на выбор** («Оформление → Начальный экран», решение
  владельца 26.11.2026): «Почта», «Мой день» или «Сводка ящиков» — один из
  трёх. С него приложение открывается; «Назад» с других разделов и из
  ленты ведёт на него (папки ленты при этом не перебираются), с него —
  выход. Раньше «Назад» всегда вёл в почту. «Мой день», выключенный в
  «Профиле», — снова почта.
- **«Мой день»: ящики кружками у нижней панели** (просьба владельца
  26.11.2026): портрет ящика с числом новых писем во «Входящих», первым —
  «Все ящики». Нажатие — «Входящие» ящика, удержание — «Сводка ящиков».

- **Отправка — сразу в «Исходящие»** (просьба владельца 25.11.2026 и
  журналы пользователя на мобильном интернете: «при отправке окно письма
  не закрывается, пока письмо не уйдёт или не придёт ошибка»; строка
  «Отправляется… Отменить» висела часами, «Отменить» не работало;
  «Ожидают отправки… SMTP: вход не выполнен (TimeoutException)»).
  «Отправить» всегда кладёт письмо в «Исходящие» и закрывает окно — и при
  отсчёте «Отменить» 0 с (раньше без отсчёта письмо отправлялось прямо из
  окна). Всё сетевое — в «Исходящих»: докачка файлов пересылаемого письма
  и картинок цитаты, отправка, повторы. При плохой связи письмо
  повторяется сутки — пауза растёт от 30 с до 10 мин (раньше — 10 попыток
  за ~20 минут, потом «не отправлено»); «Отправить сейчас» в «Исходящих»
  начинает сутки заново. Строка «Отправка через N с · Отменить» над лентой
  — только во время отсчёта; дальше письмо видно в «Исходящих», где
  «Отменить» и «Изменить» работают. Ответ и пересылка всегда собираются
  приложением (Exchange раньше иногда отвечал и пересылал сам, пока окно
  ждало ответа сервера), картинки цитаты — встроенными частями, как в
  2.7.2. На компьютере (письмо в отдельном окне) — так же.
- **«Черновики» после отправки** (замечание владельца: «про папку
  „Черновики“ не забыть»):
  - «Отправить позже» убирает черновик — раньше окно при закрытии
    сохраняло письмо черновиком, и оно оставалось в «Черновиках» (и на
    сервере), хотя уже ждало отправки;
  - черновик из серверной папки, файлы которого ещё не скачаны на
    телефон, сразу пропадает из «Черновиков», а на сервере удаляется
    после отправки (файлы «Исходящие» берут из него); раньше он оставался
    в «Черновиках» навсегда;
  - «Отменить» в «Исходящих» возвращает письмо в «Черновики», и при
    выгрузке оно заменяет ту серверную копию — без второго черновика.
- **Мобильный интернет** (журналы пользователя 25.11.2026: корпоративный
  сервер IMAP, письма приходили с опозданием на часы). Сервер или сеть
  обрывали защищённое соединение при установке, а приложение пробовало
  каждую из 14 папок отдельным подключением (263 обрыва за 3,5 часа) и
  писало «ошибка сертификата сервера». Теперь обрыв при установке
  соединения — одна повторная попытка через 2 с; нет подключения —
  остальные папки ждут следующей проверки; текст ошибки — «сеть или сервер
  обрывают защищённое подключение» (сертификат здесь ни при чём).
- **Виджеты: погода не пропадает** (замечание владельца 25.11.2026:
  «приходится заходить в приложение и в „Мой день“»). Прогноз обновлялся
  только при открытии «Моего дня», а виджет прятал прогноз старше 6 часов.
  Теперь после каждой проверки почты прогноз старше часа запрашивается
  заново; сохранённый виджет показывает до 12 часов (прогноз почасовой на
  двое суток).
- **Уведомления: «Прочитано» и «Удалить» в шторке** (замечание
  владельца): действие на предпоследнем письме ящика больше не убирает
  последнее. Когда в группе оставалось одно письмо, снималось сводное
  уведомление группы, а Android вместе со сводным снимает все письма
  группы.
- **Напоминание о вложении** (письмо владельца 25.11.2026): слова
  «встраивание в приложения» (о программах) больше не считаются
  упоминанием файла; «в приложении», «в приложенном файле» — как раньше.
  Цитата прошлой переписки и раньше не учитывалась.
- **Номер телефона в письме** (просьба пользователя): нажатие на номер в
  тексте письма (подпись) и удержание кнопки звонка в списке контактов
  организации — тот же лист, что у контакта: «Позвонить», «Написать SMS»,
  мессенджеры, «Копировать».

## Кратко (RU / EN)

**RU.** Сводка ящиков и начальный экран на выбор (почта, «Мой день» или
сводка), ящики кружками в «Моём дне»; письмо сразу уходит в «Исходящие» и
отправляется в фоне — и при плохой связи; после отправки в «Черновиках» не остаётся копий; надёжнее на
мобильном интернете; погода в виджетах не пропадает; SMS и мессенджеры по
номеру из письма; исправления уведомлений и напоминания о вложении.

**EN.** A mailboxes overview and a start screen of your choice (mail, My
day or the overview), mailbox circles in My day; sent mail goes straight to
the Outbox and is delivered in the background, even on a poor connection; no leftover copies in Drafts; more
reliable on mobile data; weather in widgets no longer disappears; SMS and
messengers from a phone number in an email; fixes for notification actions
and the attachment reminder.

## Google Play — короткий текст (27 языков)

Самый длинный — 499 знаков (hu-HU; предел — 500).

```
<ru-RU>
• Сводка ящиков: все ящики на одном экране — новые письма и папки каждого; ящики кружками внизу «Моего дня»
• Начальный экран на выбор: почта, «Мой день» или сводка ящиков
• Письмо сразу уходит в «Исходящие» и отправляется в фоне — при плохой связи повторы до суток
• Надёжнее на мобильном интернете; погода в виджетах больше не пропадает
• Номер телефона в письме: позвонить, SMS, мессенджеры
• Исправления: черновики после отправки, уведомления, напоминание о вложении
</ru-RU>
<en-US>
• Mailboxes overview: all mailboxes on one screen with new mail and folders; mailbox circles at the bottom of My day
• Choose the start screen: mail, My day or the overview
• Sent mail goes straight to the Outbox and is delivered in the background, retrying for up to a day on a poor connection
• More reliable on mobile data; weather in widgets no longer disappears
• Phone numbers in emails: call, SMS, messengers
• Fixes: drafts after sending, notifications, attachment reminder
</en-US>
<de-DE>
• Postfach-Übersicht: alle Postfächer auf einem Bildschirm mit neuen E-Mails und Ordnern; Postfach-Kreise unten in „Mein Tag“
• Startbildschirm wählbar: E-Mail, „Mein Tag“ oder Übersicht
• E-Mails gehen sofort in den Postausgang und im Hintergrund raus – bei schlechter Verbindung bis zu einem Tag
• Zuverlässiger im Mobilfunknetz; das Wetter im Widget bleibt
• Telefonnummern in E-Mails: anrufen, SMS, Messenger
• Korrekturen: Entwürfe nach dem Senden, Benachrichtigungen, Anhang-Erinnerung
</de-DE>
<fr-FR>
• Aperçu des boîtes : toutes vos boîtes sur un écran, nouveaux messages et dossiers ; cercles en bas de « Ma journée »
• Écran d’accueil au choix : e-mail, « Ma journée » ou aperçu
• Le message part aussitôt dans la boîte d’envoi, envoyé en arrière-plan ; nouvelles tentatives pendant 24 h si besoin
• Plus fiable en données mobiles ; la météo reste dans les widgets
• Numéros dans les e-mails : appel, SMS, messageries
• Corrections : brouillons après envoi, notifications, rappel de pièce jointe
</fr-FR>
<ar>
• ملخص صناديق البريد: كل الصناديق في شاشة واحدة مع الرسائل الجديدة والمجلدات، ودوائر الصناديق أسفل «يومي»
• اختر شاشة البدء: البريد أو «يومي» أو الملخص
• تنتقل الرسالة فورًا إلى «صندوق الصادر» وتُرسل في الخلفية، مع إعادة المحاولة حتى يوم كامل عند ضعف الاتصال
• موثوقية أعلى على بيانات الجوال، ولم يعد الطقس يختفي من الأدوات
• أرقام الهاتف في الرسائل: اتصال وSMS وتطبيقات المراسلة
• إصلاحات: المسودات بعد الإرسال والإشعارات وتذكير المرفقات
</ar>
<hu-HU>
• Postafiókok áttekintése: minden postafiók egy képernyőn, új levelekkel és mappákkal; postafiók-körök a „Saját napom” alján
• Választható kezdőképernyő: levelek, „Saját napom” vagy áttekintés
• A levél azonnal a Postázandó mappába kerül, és a háttérben megy el – gyenge kapcsolatnál egy napig újrapróbálva
• Megbízhatóbb mobilneten; az időjárás nem tűnik el a widgetekből
• Telefonszámok a levelekben: hívás, SMS, üzenetküldők
• Javítások: piszkozatok küldés után, értesítések, mellékletemlékeztető
</hu-HU>
<vi>
• Tổng quan hộp thư: mọi hộp thư trên một màn hình, kèm thư mới và thư mục; các hộp thư dạng vòng tròn ở cuối «Ngày của tôi»
• Chọn màn hình khởi động: thư, «Ngày của tôi» hoặc tổng quan
• Thư gửi đi được chuyển ngay vào Hộp thư đi và gửi ở chế độ nền, thử lại đến một ngày khi kết nối kém
• Ổn định hơn với dữ liệu di động; thời tiết trong tiện ích không còn biến mất
• Số điện thoại trong thư: gọi, SMS, ứng dụng nhắn tin
• Sửa lỗi: thư nháp sau khi gửi, thông báo, lời nhắc tệp đính kèm
</vi>
<da-DK>
• Oversigt over postkasser: alle postkasser på én skærm med nye mails og mapper; postkasser som cirkler nederst i „Min dag“
• Vælg startskærm: mail, „Min dag“ eller oversigten
• Sendte mails går straks til Udbakken og sendes i baggrunden – ved dårlig forbindelse forsøges igen i op til et døgn
• Mere pålidelig på mobildata; vejret forsvinder ikke fra widgets
• Telefonnumre i mails: ring, sms, beskedapps
• Rettelser: kladder efter afsendelse, notifikationer, påmindelse om vedhæftede filer
</da-DK>
<iw-IL>
• סקירת תיבות דואר: כל התיבות במסך אחד עם הודעות חדשות ותיקיות; התיבות כעיגולים בתחתית «היום שלי»
• בחירת מסך פתיחה: דואר, «היום שלי» או הסקירה
• ההודעה עוברת מיד לדואר היוצא ונשלחת ברקע, עם ניסיונות חוזרים עד יממה כשהחיבור חלש
• אמין יותר ברשת סלולרית; מזג האוויר כבר לא נעלם מהווידג'טים
• מספרי טלפון בהודעות: שיחה, SMS ואפליקציות מסרים
• תיקונים: טיוטות אחרי שליחה, התראות, תזכורת על קובץ מצורף
</iw-IL>
<id>
• Ringkasan kotak surat: semua kotak surat di satu layar dengan email baru dan folder; lingkaran kotak surat di bawah «Hari saya»
• Pilih layar awal: email, «Hari saya», atau ringkasan
• Email langsung masuk ke Kotak Keluar dan dikirim di latar belakang, dicoba ulang hingga sehari saat koneksi buruk
• Lebih andal di data seluler; cuaca di widget tidak lagi menghilang
• Nomor telepon di email: panggil, SMS, aplikasi pesan
• Perbaikan: draf setelah mengirim, notifikasi, pengingat lampiran
</id>
<es-ES>
• Resumen de buzones: todos en una pantalla, con correo nuevo y carpetas; buzones en círculos al pie de «Mi día»
• Elige la pantalla de inicio: correo, «Mi día» o el resumen
• El mensaje pasa al instante a la Bandeja de salida y se envía en segundo plano; con mala conexión, reintentos un día
• Más fiable con datos móviles; el tiempo ya no desaparece de los widgets
• Números de teléfono en los correos: llamar, SMS, mensajería
• Correcciones: borradores, notificaciones, aviso de adjuntos
</es-ES>
<it-IT>
• Riepilogo caselle: tutte in una schermata, con nuove email e cartelle; cerchi in fondo a «Il mio giorno»
• Scegli la schermata iniziale: posta, «Il mio giorno» o riepilogo
• Il messaggio passa subito in Posta in uscita e parte in background; con connessione scarsa, nuovi tentativi per un giorno
• Più affidabile con i dati mobili; il meteo resta nei widget
• Numeri di telefono nelle email: chiamata, SMS, app di messaggistica
• Correzioni: bozze dopo l’invio, notifiche, promemoria allegati
</it-IT>
<zh-CN>
• 邮箱概览：所有邮箱集中在一个画面，显示新邮件和文件夹；“我的一天”底部以圆形显示各邮箱
• 可选启动画面：邮件、“我的一天”或概览
• 发送的邮件立即进入“发件箱”并在后台发送，网络不佳时最多重试一天
• 移动网络下更稳定；小组件中的天气不再消失
• 邮件中的电话号码：拨打、短信、即时通讯应用
• 修复：发送后的草稿、通知、附件提醒
</zh-CN>
<ko-KR>
• 메일함 요약: 모든 메일함을 새 메일, 폴더와 함께 한 화면에서 확인. ‘오늘 일정’ 하단에도 메일함을 원형으로 표시
• 시작 화면 선택: 메일, ‘오늘 일정’ 또는 요약
• 보낸 메일이 즉시 보낼 편지함으로 이동해 백그라운드에서 전송되며, 연결이 불안정하면 최대 하루 동안 다시 시도합니다
• 모바일 데이터에서 더 안정적, 위젯의 날씨가 더 이상 사라지지 않음
• 메일 속 전화번호: 통화, SMS, 메신저
• 수정: 보낸 후 임시 보관함, 알림, 첨부 파일 알림
</ko-KR>
<nl-NL>
• Overzicht postvakken: alle postvakken op één scherm, met nieuwe e-mail en mappen; postvakken als cirkels onder in ‘Mijn dag’
• Kies het beginscherm: e-mail, ‘Mijn dag’ of het overzicht
• Mail gaat direct naar Postvak UIT en op de achtergrond de deur uit; bij slechte verbinding een dag lang opnieuw geprobeerd
• Betrouwbaarder op mobiele data; het weer blijft in widgets
• Telefoonnummers in e-mails: bellen, sms, chat-apps
• Verbeteringen: concepten na verzenden, meldingen, bijlageherinnering
</nl-NL>
<no-NO>
• Oversikt over postbokser: alle postbokser på én skjerm med ny e-post og mapper; postbokser som sirkler nederst i «Min dag»
• Velg startskjerm: e-post, «Min dag» eller oversikten
• Sendt e-post går straks til Utboksen og sendes i bakgrunnen – ved dårlig forbindelse prøves det igjen i opptil et døgn
• Mer pålitelig på mobildata; været forsvinner ikke fra widgeter
• Telefonnumre i e-post: ring, SMS, meldingsapper
• Rettelser: utkast etter sending, varsler, påminnelse om vedlegg
</no-NO>
<pl-PL>
• Przegląd skrzynek: wszystkie na jednym ekranie, z nowymi wiadomościami i folderami; kółka u dołu ekranu „Mój dzień”
• Wybór ekranu startowego: poczta, „Mój dzień” lub przegląd
• Wysłana wiadomość od razu trafia do Skrzynki nadawczej i wychodzi w tle – przy słabym połączeniu z ponawianiem do doby
• Niezawodniej w sieci komórkowej; pogoda nie znika z widżetów
• Numery telefonów w wiadomościach: połączenie, SMS, komunikatory
• Poprawki: wersje robocze, powiadomienia, przypomnienie o załączniku
</pl-PL>
<pt-BR>
• Resumo das caixas: todas as caixas em uma tela, com e-mails novos e pastas; caixas em círculos na parte de baixo de “Meu dia”
• Escolha a tela inicial: e-mail, “Meu dia” ou o resumo
• A mensagem vai na hora para a Caixa de saída e é enviada em segundo plano; com conexão ruim, novas tentativas por um dia
• Mais confiável nos dados móveis; o clima não some mais dos widgets
• Números de telefone nos e-mails: ligar, SMS, mensageiros
• Correções: rascunhos, notificações, lembrete de anexo
</pt-BR>
<ro>
• Rezumatul căsuțelor: toate pe un ecran, cu mesaje noi și dosare; cercuri în partea de jos a „Ziua mea”
• Alege ecranul de pornire: e-mail, „Ziua mea” sau rezumatul
• Mesajul ajunge imediat în Mesaje de trimis și pleacă în fundal; cu legătură slabă, reîncercări o zi
• Mai fiabil pe date mobile; vremea nu mai dispare din widgeturi
• Numere de telefon în e-mailuri: apel, SMS, aplicații de mesagerie
• Corecturi: ciorne după trimitere, notificări, memento pentru atașamente
</ro>
<sk>
• Prehľad schránok: všetky schránky na jednej obrazovke s novou poštou a priečinkami; schránky v krúžkoch v spodnej časti „Môj deň“
• Výber úvodnej obrazovky: pošta, „Môj deň“ alebo prehľad
• Správa ide hneď do priečinka Na odoslanie a odchádza na pozadí, pri slabom pripojení s opakovaním až deň
• Spoľahlivejšie na mobilných dátach; počasie už nemizne z miniaplikácií
• Telefónne čísla v e-mailoch: hovor, SMS, komunikátory
• Opravy: koncepty po odoslaní, upozornenia, pripomienka príloh
</sk>
<th>
• ภาพรวมกล่องจดหมาย: ทุกกล่องในหน้าจอเดียว พร้อมอีเมลใหม่และโฟลเดอร์ และกล่องจดหมายแบบวงกลมด้านล่าง «วันของฉัน»
• เลือกหน้าจอเริ่มต้นได้: อีเมล, «วันของฉัน» หรือภาพรวม
• อีเมลที่ส่งจะย้ายไปที่กล่องขาออกทันทีและส่งในเบื้องหลัง เมื่อสัญญาณไม่ดีจะลองใหม่นานสูงสุดหนึ่งวัน
• เสถียรขึ้นบนเน็ตมือถือ และสภาพอากาศในวิดเจ็ตไม่หายไปอีกแล้ว
• หมายเลขโทรศัพท์ในอีเมล: โทร, SMS, แอปแชท
• แก้ไข: ฉบับร่างหลังส่ง การแจ้งเตือน และการเตือนไฟล์แนบ
</th>
<tr-TR>
• Posta kutularına genel bakış: tüm kutular yeni e-posta ve klasörlerle tek ekranda; «Günüm» altında daireler
• Başlangıç ekranını seçin: posta, «Günüm» veya genel bakış
• E-posta hemen Giden Kutusu’na geçer ve arka planda gönderilir; bağlantı zayıfsa bir gün yeniden denenir
• Mobil veride daha güvenilir; widget’lardaki hava durumu artık kaybolmuyor
• E-postadaki telefon numaraları: arama, SMS, mesajlaşma uygulamaları
• Düzeltmeler: gönderim sonrası taslaklar, bildirimler, ek hatırlatıcısı
</tr-TR>
<fi-FI>
• Postilaatikoiden yhteenveto: kaikki laatikot yhdessä näkymässä uusine viesteineen ja kansioineen; ympyrät Oma päivä -näkymän alalaidassa
• Valitse aloitusnäkymä: posti, Oma päivä tai yhteenveto
• Viesti siirtyy heti Lähtevät-kansioon ja lähtee taustalla; heikolla yhteydellä uusintayritykset vuorokauden
• Luotettavampi mobiilidatalla; sää ei katoa widgeteistä
• Puhelinnumerot viesteissä: soitto, tekstiviesti, viestisovellukset
• Korjauksia: luonnokset, ilmoitukset, liitemuistutus
</fi-FI>
<hi-IN>
• मेलबॉक्स सारांश: सभी मेलबॉक्स एक स्क्रीन पर, नए मेल और फ़ोल्डर के साथ; «मेरा दिन» के नीचे मेलबॉक्स गोलों में
• प्रारंभ स्क्रीन चुनें: मेल, «मेरा दिन» या सारांश
• भेजा गया ईमेल तुरंत आउटबॉक्स में जाता है और बैकग्राउंड में भेजा जाता है; कमज़ोर कनेक्शन पर एक दिन तक दोबारा कोशिश होती है
• मोबाइल डेटा पर ज़्यादा भरोसेमंद; विजेट से मौसम अब गायब नहीं होता
• ईमेल में फ़ोन नंबर: कॉल, SMS, मैसेंजर
• सुधार: भेजने के बाद ड्राफ़्ट, नोटिफ़िकेशन, अटैचमेंट रिमाइंडर
</hi-IN>
<cs-CZ>
• Přehled schránek: všechny schránky na jedné obrazovce s novou poštou a složkami; schránky v kroužcích dole na obrazovce „Můj den“
• Výběr úvodní obrazovky: pošta, „Můj den“ nebo přehled
• Odeslaná zpráva jde hned do složky K odeslání a odchází na pozadí, při slabém připojení s opakováním až jeden den
• Spolehlivější na mobilních datech; počasí už nemizí z widgetů
• Telefonní čísla v e-mailech: hovor, SMS, komunikátory
• Opravy: koncepty po odeslání, oznámení, připomínka přílohy
</cs-CZ>
<sv-SE>
• Översikt över inkorgar: alla inkorgar på en skärm med ny e-post och mappar; inkorgar som cirklar längst ned i ”Min dag”
• Välj startskärm: e-post, ”Min dag” eller översikten
• Skickad e-post hamnar direkt i Utkorgen och skickas i bakgrunden – vid dålig anslutning görs nya försök i upp till ett dygn
• Pålitligare på mobildata; vädret försvinner inte från widgetar
• Telefonnummer i e-post: ring, sms, meddelandeappar
• Rättningar: utkast efter sändning, aviseringar, påminnelse om bilagor
</sv-SE>
<ja-JP>
• メールボックス一覧：すべてのメールボックスを新着メールやフォルダとともに1画面に表示。「今日の予定」の下部にも丸いアイコンで表示
• 起動時の画面を選択：メール、「今日の予定」または一覧
• 送信したメールはすぐに送信トレイへ移り、バックグラウンドで送信。接続が悪いときは最大1日再試行します
• モバイルデータでより安定。ウィジェットの天気が消えなくなりました
• メール内の電話番号：通話、SMS、メッセンジャー
• 修正：送信後の下書き、通知、添付ファイルの確認
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Сводка ящиков: все ящики на одном экране — новые письма и папки каждого; ящики кружками внизу «Моего дня»
• Начальный экран на выбор: почта, «Мой день» или сводка ящиков
• Письмо сразу уходит в «Исходящие» и отправляется в фоне — при плохой связи повторы до суток
• Надёжнее на мобильном интернете; погода в виджетах больше не пропадает
• Номер телефона в письме: позвонить, SMS, мессенджеры
• Исправления: черновики после отправки, уведомления, напоминание о вложении
</ru-RU>
<en-US>
• Mailboxes overview: all mailboxes on one screen with new mail and folders; mailbox circles at the bottom of My day
• Choose the start screen: mail, My day or the overview
• Sent mail goes straight to the Outbox and is delivered in the background, retrying for up to a day on a poor connection
• More reliable on mobile data; weather in widgets no longer disappears
• Phone numbers in emails: call, SMS, messengers
• Fixes: drafts after sending, notifications, attachment reminder
</en-US>
<de-DE>
• Postfach-Übersicht: alle Postfächer auf einem Bildschirm mit neuen E-Mails und Ordnern; Postfach-Kreise unten in „Mein Tag“
• Startbildschirm wählbar: E-Mail, „Mein Tag“ oder Übersicht
• E-Mails gehen sofort in den Postausgang und im Hintergrund raus – bei schlechter Verbindung bis zu einem Tag
• Zuverlässiger im Mobilfunknetz; das Wetter im Widget bleibt
• Telefonnummern in E-Mails: anrufen, SMS, Messenger
• Korrekturen: Entwürfe nach dem Senden, Benachrichtigungen, Anhang-Erinnerung
</de-DE>
<fr-FR>
• Aperçu des boîtes : toutes vos boîtes sur un écran, nouveaux messages et dossiers ; cercles en bas de « Ma journée »
• Écran d’accueil au choix : e-mail, « Ma journée » ou aperçu
• Le message part aussitôt dans la boîte d’envoi, envoyé en arrière-plan ; nouvelles tentatives pendant 24 h si besoin
• Plus fiable en données mobiles ; la météo reste dans les widgets
• Numéros dans les e-mails : appel, SMS, messageries
• Corrections : brouillons après envoi, notifications, rappel de pièce jointe
</fr-FR>
```
