# «Что нового» — 1.12.0 (138)

Номер — решение владельца 04.11.2026 (архив для Android и iOS, выпуск в
магазины). Архив 1.11.0 (137) — `STORE_NOTES_1.11.0.md`; что вошло в 1.11.0
и раньше — там.

Тексты для магазинов — тот же общий список с 1.8.12 (у пользователей
магазинов пока она) и главное из 1.12.0 первой строкой. В Google Play
строка «Уведомления с фото отправителя» уступила место документам (предел
— 500 знаков на язык, здесь не длиннее 480). На iPhone и iPad документы
Office, RTF и CSV по-прежнему показывает Просмотр iOS, поэтому в App Store
новое — документы OpenDocument и шапки цитат.

Добавлено и исправлено в 1.12.0 (после архива 1.11.0):

- **Предпросмотр документов во вложениях** (план владельца 04.11.2026):
  - DOCX, DOCM, DOTX, ODT, RTF — текстом в том же защищённом окне, что
    письмо (без сети и JavaScript, тёмная тема, масштаб; на компьютере —
    виджетами): заголовки, списки с нумерацией, таблицы с объединёнными
    ячейками, картинки, ссылки (через проверку домена), сноски; RTF из
    русского Word в Windows-1251;
  - XLSX, XLSM, ODS, CSV, TSV — сеткой листов: закреплённые заголовки
    столбцов и номера строк, листы внизу, объединения, заливка и шрифты,
    форматы чисел и дат по языку приложения, строка с полным текстом
    ячейки, масштаб; CSV из русского Excel (Windows-1251, «;»);
  - PPTX, PPSX, ODP — слайдами, по нажатию — во весь экран с масштабом;
  - формат — по содержимому: «.doc», который на деле RTF или DOCX, и
    таблица ODS с расширением .xlsx открываются правильно;
  - документ с паролем, старые .doc/.xls/.ppt, слишком большой файл —
    понятной строкой и кнопкой «Открыть во внешнем приложении»; большой
    документ — началом с плашкой;
  - iPhone и iPad: Office, RTF, CSV — по-прежнему Просмотр iOS;
    OpenDocument (его Просмотр не открывает) — приложение;
  - «Настройки → Почта → Просмотр документов»: общий выключатель и виды
    (текстовые документы, таблицы, CSV таблицей, презентации); выключенный
    вид открывается, как раньше;
  - защита от испорченных файлов: пределы на распакованное («ZIP-бомба»),
    разбор в отдельном потоке с остановкой через 30 с, макросы не
    выполняются;
  - FAQ: ответ «Какие вложения открываются прямо в приложении?» переписан,
    новый вопрос «Как выключить просмотр документов в приложении?» (27
    языков);
  - патентные условия форматов — `LICENSING.md`, раздел 6.
- **Перевод: язык письма по основному алфавиту** (журнал владельца
  04.11.2026: «язык письма не определён», «Не удалось перевести»): подпись
  на двух языках и письмо с переводом рядом сбивали ML Kit; короткое
  русское письмо больше не определяется как украинское.
- **Шапки цитат на языке приложения** (замечание владельца 04.11.2026):
  From / Sent / To / Cc / Subject — подписями приложения, английская дата —
  «четверг, 22 октября 2026 г. 14:48» (нажимается, как и раньше).
- **Календарь:** «Весь день» у встречи через полночь давал событие на два
  дня (замечание владельца 04.11.2026, события iCloud).

Платформы: новых разрешений, прав и возможностей нет; project.pbxproj,
Runner.entitlements и Info.plist не менялись; в Xcode включать ничего не
нужно.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Документы OpenDocument (ODT, ODS, ODP) — прямо в почте; просмотр отключается в настройках
• Шапки цитат и дата отправки — на языке приложения
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
• OpenDocument files (ODT, ODS, ODP) open right in the app; preview can be turned off in Settings
• Quoted message headers and dates in the app’s language
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
• OpenDocument-Dateien (ODT, ODS, ODP) direkt in der App; Vorschau in den Einstellungen abschaltbar
• Kopfzeilen zitierter Nachrichten samt Datum in der Sprache der App
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
• Fichiers OpenDocument (ODT, ODS, ODP) ouverts dans l’app ; aperçu désactivable dans les Réglages
• En-têtes et dates des messages cités dans la langue de l’app
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
• Документы DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF и CSV — прямо в почте
• Для компаний: настройки из MDM
• Планшет и компьютер в стиле Outlook
• Перевод писем с темой и своего текста на устройстве
• Темы оформления, плотность ленты, тёмные письма без инверсии
• Дата в письме — встреча или напоминание в одно касание
• Блокировка отправителя и чистка его писем
• Предупреждение о подделке отправителя
• Сигналы почты и без сервисов Google (UnifiedPush)
</ru-RU>
<en-US>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF and CSV files open right in the app
• For businesses: settings via MDM
• Outlook-style layout on tablets and computers
• Translate mail (subject too) and your own text on the device
• Colour themes, list density, dark mail without inversion
• Tap a date in a message to add a meeting or reminder
• Block a sender and sweep their mail
• Warnings about spoofed senders
• Mail signals without Google services (UnifiedPush)
</en-US>
<de-DE>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF und CSV direkt in der App
• Für Unternehmen: Einstellungen per MDM
• Tablet und Computer im Outlook-Stil
• Mails samt Betreff und eigene Texte auf dem Gerät übersetzen
• Farbschemata, Listendichte, dunkle Mails ohne Invertierung
• Datum in Nachricht antippen: Termin oder Erinnerung anlegen
• Absender blockieren und seine Mails bereinigen
• Warnungen vor gefälschten Absendern
• Mail-Signale ohne Google-Dienste (UnifiedPush)
</de-DE>
<fr-FR>
• Fichiers DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF et CSV ouverts dans l’app
• Entreprises : réglages par MDM
• Tablette et ordinateur façon Outlook
• Traduction des e-mails (objet compris) et de vos textes sur l’appareil
• Thèmes de couleurs, densité de liste, e-mails sombres sans inversion
• Touchez une date du message : réunion ou rappel
• Bloquer un expéditeur et nettoyer ses e-mails
• Alertes d’usurpation d’expéditeur
• Signaux courrier sans services Google (UnifiedPush)
</fr-FR>
<ar>
• فتح ملفات DOCX وXLSX وPPTX وODT وODS وODP وRTF وCSV داخل التطبيق
• للشركات: إعدادات عبر MDM
• الجهاز اللوحي والكمبيوتر بأسلوب Outlook
• ترجمة الرسائل مع موضوعها ونصوصك على الجهاز
• أنساق ألوان وكثافة القائمة ورسائل داكنة بلا عكس للألوان
• اضغط على تاريخ في الرسالة لإضافة اجتماع أو تذكير
• حظر المرسل وتنظيف رسائله
• تحذيرات من انتحال هوية المرسل
• إشارات البريد بدون خدمات Google (UnifiedPush)
</ar>
<hu-HU>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF és CSV fájlok az alkalmazásban
• Cégeknek: beállítások MDM-ből
• Táblagépen és számítógépen Outlook-stílus
• Levelek (tárggyal együtt) és saját szövegek fordítása az eszközön
• Színsémák, listasűrűség, sötét levelek inverzió nélkül
• Koppintson egy dátumra: értekezlet vagy emlékeztető
• Feladó letiltása és leveleinek takarítása
• Figyelmeztetés hamisított feladóra
• Levéljelzések Google-szolgáltatások nélkül (UnifiedPush)
</hu-HU>
<vi>
• Mở tệp DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF và CSV ngay trong ứng dụng
• Cho doanh nghiệp: cấu hình qua MDM
• Máy tính bảng và máy tính kiểu Outlook
• Dịch thư (cả tiêu đề) và văn bản của bạn ngay trên thiết bị
• Chủ đề màu, mật độ danh sách, thư tối không đảo màu
• Chạm vào ngày trong thư để thêm cuộc họp hoặc lời nhắc
• Chặn người gửi và dọn dẹp thư của họ
• Cảnh báo người gửi giả mạo
• Tín hiệu thư không cần dịch vụ Google (UnifiedPush)
</vi>
<da-DK>
• DOCX-, XLSX-, PPTX-, ODT-, ODS-, ODP-, RTF- og CSV-filer åbnes i appen
• Til virksomheder: indstillinger via MDM
• Tablet og computer i Outlook-stil
• Oversæt mails med emne og din egen tekst på enheden
• Farvetemaer, listetæthed, mørke mails uden invertering
• Tryk på en dato i en besked for at tilføje et møde eller en påmindelse
• Blokér afsender og ryd op i vedkommendes mails
• Advarsler om falske afsendere
• Mailsignaler uden Google-tjenester (UnifiedPush)
</da-DK>
<iw-IL>
• קובצי DOCX,‏ XLSX,‏ PPTX,‏ ODT,‏ ODS,‏ ODP,‏ RTF ו-CSV נפתחים באפליקציה
• לעסקים: הגדרות דרך MDM
• טאבלט ומחשב בסגנון Outlook
• תרגום הודעות כולל הנושא, וגם הטקסט שלך, במכשיר
• ערכות צבעים, צפיפות רשימת הדואר, הודעות כהות ללא היפוך צבעים
• הקשה על תאריך בהודעה מוסיפה פגישה או תזכורת
• חסימת שולח וניקוי כל ההודעות שלו
• אזהרות על שולחים מתחזים
• אותות דואר גם ללא שירותי Google (UnifiedPush)
</iw-IL>
<id>
• File DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, dan CSV terbuka di aplikasi
• Untuk perusahaan: pengaturan lewat MDM
• Tablet dan komputer bergaya Outlook
• Terjemahkan email beserta subjeknya dan teks Anda di perangkat
• Tema warna, kerapatan daftar, email gelap tanpa inversi
• Ketuk tanggal di pesan untuk menambah rapat atau pengingat
• Blokir pengirim dan bersihkan emailnya
• Peringatan pengirim palsu
• Sinyal email tanpa layanan Google (UnifiedPush)
</id>
<es-ES>
• Archivos DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF y CSV en la propia app
• Para empresas: ajustes mediante MDM
• Tableta y ordenador al estilo Outlook
• Traduce correos (también el asunto) y tu texto en el dispositivo
• Temas de color, densidad de lista, correo oscuro sin inversión
• Toca una fecha para crear una reunión o recordatorio
• Bloqueo de remitentes y limpieza de sus mensajes
• Avisos de remitentes suplantados
• Señales de correo sin servicios de Google (UnifiedPush)
</es-ES>
<it-IT>
• File DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF e CSV aperti nell’app
• Per le aziende: impostazioni tramite MDM
• Tablet e computer in stile Outlook
• Traduci le email (anche l’oggetto) e il tuo testo sul dispositivo
• Temi colore, densità dell’elenco, posta scura senza inversione
• Tocca una data per creare riunione o promemoria
• Blocco dei mittenti e pulizia dei loro messaggi
• Avvisi sui mittenti falsificati
• Segnali di posta anche senza servizi Google (UnifiedPush)
</it-IT>
<zh-CN>
• 直接在应用内打开 DOCX、XLSX、PPTX、ODT、ODS、ODP、RTF 和 CSV 文件
• 企业：通过 MDM 下发设置
• 平板和电脑采用 Outlook 式布局
• 在设备上翻译邮件（含主题）和你写的文字
• 配色主题、列表密度、无需反色的深色邮件
• 点按邮件中的日期，即可添加会议或提醒
• 阻止发件人并清理其邮件
• 伪造发件人警告
• 没有 Google 服务也能收到邮件信号（UnifiedPush）
</zh-CN>
<ko-KR>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, CSV 파일을 앱에서 바로 보기
• 기업용: MDM으로 설정 배포
• 태블릿과 컴퓨터에서 Outlook 스타일
• 기기에서 메일(제목 포함)과 내 글 번역
• 색상 테마, 목록 밀도, 색 반전 없는 다크 메일
• 메일 속 날짜를 탭해 회의나 알림 추가
• 보낸 사람 차단 및 해당 메일 정리
• 보낸 사람 사칭 경고
• Google 서비스 없이도 메일 신호 수신(UnifiedPush)
</ko-KR>
<nl-NL>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF en CSV direct in de app
• Voor bedrijven: instellingen via MDM
• Tablet en computer in Outlook-stijl
• Vertaal mail (ook het onderwerp) en je eigen tekst op het apparaat
• Kleurthema’s, lijstdichtheid, donkere e-mail zonder inversie
• Tik op een datum voor een afspraak of herinnering
• Afzender blokkeren en zijn berichten opruimen
• Waarschuwingen voor vervalste afzenders
• E-mailsignalen ook zonder Google-services (UnifiedPush)
</nl-NL>
<no-NO>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF og CSV rett i appen
• For bedrifter: innstillinger via MDM
• Nettbrett og datamaskin i Outlook-stil
• Oversett e-post med emne og din egen tekst på enheten
• Fargetemaer, listetetthet, mørk e-post uten invertering
• Trykk på en dato i en melding for å legge til møte eller påminnelse
• Blokker en avsender og rydd opp i meldingene deres
• Advarsler om forfalskede avsendere
• E-postsignaler også uten Google-tjenester (UnifiedPush)
</no-NO>
<pl-PL>
• Pliki DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF i CSV otwierane w aplikacji
• Dla firm: ustawienia z MDM
• Tablet i komputer w stylu Outlooka
• Tłumaczenie poczty (z tematem) i własnego tekstu na urządzeniu
• Motywy kolorów, gęstość listy, ciemne wiadomości bez inwersji
• Dotknij daty, by dodać spotkanie lub przypomnienie
• Blokowanie nadawców i porządkowanie ich wiadomości
• Ostrzeżenia o fałszywych nadawcach
• Sygnały poczty także bez usług Google (UnifiedPush)
</pl-PL>
<pt-BR>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF e CSV abertos no app
• Para empresas: configurações via MDM
• Tablet e computador no estilo Outlook
• Traduza e-mails (com o assunto) e seu próprio texto no aparelho
• Temas de cor, densidade da lista, e-mails escuros sem inversão
• Toque em uma data para criar reunião ou lembrete
• Bloqueio de remetentes e limpeza de mensagens
• Alertas sobre remetentes falsificados
• Sinais de e-mail também sem serviços do Google (UnifiedPush)
</pt-BR>
<ro>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, CSV în aplicație
• Pentru companii: setări prin MDM
• Tabletă și computer în stil Outlook
• Traducerea e-mailurilor (cu subiect) și a textului tău pe dispozitiv
• Teme de culoare, densitatea listei, mesaje întunecate fără inversare
• Atinge o dată dintr-un mesaj pentru întâlnire sau memento
• Blocarea expeditorului și curățarea mesajelor lui
• Avertizări la expeditori falsificați
• Semnale de e-mail și fără servicii Google (UnifiedPush)
</ro>
<sk>
• Súbory DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF a CSV priamo v aplikácii
• Pre firmy: nastavenia cez MDM
• Tablet a počítač v štýle Outlooku
• Preklad e-mailov aj s predmetom a vlastného textu v zariadení
• Farebné motívy, hustota zoznamu, tmavé správy bez inverzie
• Ťuknutím na dátum v správe pridáte stretnutie alebo pripomienku
• Blokovanie odosielateľa a čistenie jeho správ
• Varovania pred sfalšovanými odosielateľmi
• Signály pošty aj bez služieb Google (UnifiedPush)
</sk>
<th>
• เปิดไฟล์ DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF และ CSV ในแอปได้ทันที
• สำหรับองค์กร: ตั้งค่าผ่าน MDM
• แท็บเล็ตและคอมพิวเตอร์สไตล์ Outlook
• แปลอีเมลพร้อมหัวเรื่องและข้อความของคุณบนอุปกรณ์
• ธีมสี ความหนาแน่นของรายการ อีเมลโหมดมืดโดยไม่กลับสี
• แตะวันที่ในอีเมลเพื่อเพิ่มการประชุมหรือเตือนความจำ
• บล็อกผู้ส่งและล้างอีเมลของผู้ส่ง
• เตือนเมื่อผู้ส่งถูกปลอมแปลง
• สัญญาณอีเมลแม้ไม่มีบริการ Google (UnifiedPush)
</th>
<tr-TR>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF ve CSV dosyaları uygulamada açılır
• Şirketler için: MDM ile ayarlar
• Tablet ve bilgisayarda Outlook tarzı
• Postaları (konu dahil) ve kendi metninizi cihazda çevirin
• Renk temaları, liste yoğunluğu, ters çevirmesiz koyu iletiler
• İletideki tarihe dokunup toplantı veya hatırlatıcı ekleyin
• Göndereni engelleme ve iletilerini temizleme
• Sahte göndericilere karşı uyarılar
• Google hizmetleri olmadan da posta sinyalleri (UnifiedPush)
</tr-TR>
<fi-FI>
• DOCX-, XLSX-, PPTX-, ODT-, ODS-, ODP-, RTF- ja CSV-tiedostot sovelluksessa
• Yrityksille: asetukset MDM:n kautta
• Tabletti ja tietokone Outlook-tyyliin
• Käännä viestit aiheineen ja oma tekstisi laitteella
• Väriteemat, luettelon tiheys, tummat viestit ilman käänteisvärejä
• Napauta viestin päivämäärää ja lisää kokous tai muistutus
• Lähettäjän esto ja hänen viestiensä siivous
• Varoitukset väärennetyistä lähettäjistä
• Postisignaalit ilman Google-palveluita (UnifiedPush)
</fi-FI>
<hi-IN>
• DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF और CSV फ़ाइलें सीधे ऐप में
• कंपनियों के लिए: MDM से सेटिंग्स
• टैबलेट और कंप्यूटर पर Outlook जैसा लेआउट
• मेल (विषय सहित) और अपना टेक्स्ट डिवाइस पर अनुवाद करें
• रंग थीम, सूची घनत्व, बिना इनवर्ज़न के डार्क मेल
• ईमेल में तारीख पर टैप करके मीटिंग या रिमाइंडर जोड़ें
• प्रेषक को ब्लॉक करें और उसके ईमेल की सफ़ाई करें
• नकली प्रेषकों की चेतावनियां
• Google सेवाओं के बिना भी मेल सिग्नल (UnifiedPush)
</hi-IN>
<cs-CZ>
• Soubory DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF a CSV přímo v aplikaci
• Pro firmy: nastavení přes MDM
• Tablet a počítač ve stylu Outlooku
• Překlad e-mailů i s předmětem a vlastního textu v zařízení
• Barevné motivy, hustota seznamu, tmavé zprávy bez inverze
• Klepnutím na datum ve zprávě přidáte schůzku nebo připomenutí
• Blokování odesílatele a čištění jeho zpráv
• Varování před padělanými odesílateli
• Signály pošty i bez služeb Google (UnifiedPush)
</cs-CZ>
<sv-SE>
• DOCX-, XLSX-, PPTX-, ODT-, ODS-, ODP-, RTF- och CSV-filer öppnas i appen
• För företag: inställningar via MDM
• Surfplatta och dator i Outlook-stil
• Översätt mejl med ämnesrad och din egen text på enheten
• Färgteman, listtäthet, mörk e-post utan inversion
• Tryck på ett datum i meddelandet för möte eller påminnelse
• Blockera en avsändare och rensa dennes e-post
• Varningar för förfalskade avsändare
• E-postsignaler även utan Google-tjänster (UnifiedPush)
</sv-SE>
<ja-JP>
• DOCX・XLSX・PPTX・ODT・ODS・ODP・RTF・CSV ファイルをアプリ内で表示
• 企業向け：MDM で設定を配布
• タブレットとパソコンで Outlook 風の画面
• メール（件名も）と自分の文章を端末内で翻訳
• カラーテーマ、リストの密度、反転しないダークメール
• メール内の日付をタップして会議やリマインダーを追加
• 差出人をブロックし、そのメールをクリーンアップ
• なりすましの差出人を警告
• Google サービスなしでもメールのシグナルを受信 (UnifiedPush)
</ja-JP>
```
