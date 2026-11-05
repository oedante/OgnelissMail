# «Что нового» — 1.14.0 (139)

Номер — решение владельца 05.11.2026 («Давай версию 1.14.0 сделаем»; 1.13
не выпускалась). Архив 1.12.0 (138) — `STORE_NOTES_1.12.0.md`; что вошло в
1.12.0 и раньше — там.

Тексты для магазинов — только то, что действительно ново в 1.14.0
(решение владельца 04.11.2026: «не копируй старый текст»). На iPhone и iPad
документы Office (новые и старые) по-прежнему показывает Просмотр iOS,
поэтому в App Store из вложений — письма .msg, текстовые файлы и Markdown.

Добавлено и исправлено в 1.14.0 (после архива 1.12.0):

- **Свайпы в ленте** (замечание владельца 05.11.2026: «Свайпы зависают на
  середине. И так у нескольких писем»): при одном действии на стороне
  строка, отпущенная до порога, возвращается на место; при двух кнопки ждут
  выбора, но открыта только одна строка — свайп другой или касание ленты
  закрывает прежнюю (`slidable_spring_back.dart`, `SlidableAutoCloseBehavior`).
- **Сведения о письме значками** (U2, просьба владельца 04.11.2026 вместо
  нескольких плашек): перевод, отписка, скрытые картинки, уведомление о
  прочтении, «Позже», доставка, S/MIME, важность, спам, метки и категории —
  одной строкой под шапкой; нажатие раскрывает прежнюю плашку с кнопками,
  «▾» или долгое нажатие — остальные действия; на телефоне строка
  прокручивается вбок, на планшете переносится. Предупреждение о подделке
  отправителя и приглашения — полными карточками.
- **Перевод** (T2, замечание владельца «предлагает другие языки»):
  предложение — только при уверенном определении языка; языки телефона не
  предлагаются (переключатель); «Всегда переводить с языка …» — письмо
  открывается сразу в переводе; «Указать язык письма»; без движка перевода
  значка и пункта меню нет.
- **Планшет и компьютер как Outlook** (D2): область чтения справа, снизу
  (разделитель запоминается) или скрыта — «Оформление → Область чтения» и
  меню «⋮»; выбор писем Ctrl/Cmd+нажатие, Shift — подряд, Ctrl/Cmd+A, Esc,
  Delete; вложение открывается в области чтения.
- **Старые документы Office 97–2003** (O4): .doc (текст, списки, таблицы,
  сноски, картинки), .xls (листы, форматы чисел, объединения, закрепление),
  .ppt (слайды, текст, картинки) — по содержимому, без сторонних библиотек;
  на iPhone и iPad — Просмотр iOS, как раньше. Office 95 и книги Excel с
  паролем — строкой «откройте в другом приложении».
- **Письма Outlook .msg** (O4): открываются как письмо на всех устройствах —
  отправитель, получатели, тело (HTML, RTF или текст, русские кодировки),
  вложения и вложенные письма.
- **Текстовые файлы и Markdown** (просьба владельца 05.11.2026): .txt и .md
  — в приложении на всех устройствах; кодировка по содержимому (UTF-8,
  UTF-16, Windows-1251, KOI8-R, DOS 866); Markdown — оформленным
  документом (пакет `markdown`, BSD-3-Clause); .log, .json и другие — тоже
  в своей кодировке.
- **Поиск по тексту вложений** (S2): скачанные документы, таблицы,
  презентации, текстовые файлы, вложенные письма (.eml и .msg) — в поисковом
  индексе; в результатах — «Во вложении: …»; «Настройки → Почта → Искать в
  тексте вложений» (включено). PDF — пока нет.
- **Работа на любых телефонах** (A2, аудит 05.11.2026): после добавления
  ящика — один шаг с тем, чего не хватает этому телефону для уведомлений
  (разрешение, батарея, точные напоминания, автозапуск оболочки,
  сигналы); без сервисов Google — UnifiedPush или проверка по расписанию
  без ошибок, Huawei/Honor и прошивки без Google; экраны автозапуска только
  своего производителя, LineageOS и др. не принимаются за оболочку
  производителя; выгрузка встреч на телефон без календарей создаёт
  календарь «Ogneliss Mail»; запрет «больше не спрашивать» для контактов и
  календаря ведёт в настройки; напоминания «Посмотреть позже» скрывают
  текст по правилу MDM; убрано ненужное разрешение READ_EXTERNAL_STORAGE;
  iPhone: вопрос об уведомлениях — не на заставке, а в шаге настройки.
- **FAQ** (27 языков): новые вопросы — поиск во вложениях, значки под
  заголовком, экран как в Outlook, «всегда переводить»; ответы о вложениях,
  просмотре документов и уведомлениях на Android обновлены.

Платформы: `project.pbxproj`, `Runner.entitlements`, `Info.plist` не
менялись; в Xcode включать ничего не нужно. Android: убрано разрешение
READ_EXTERNAL_STORAGE, добавлены `<queries>` (сервисы Google, приложения
UnifiedPush). Новая зависимость — `markdown` 7.3.1 (BSD-3-Clause).

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Сведения о письме — строкой значков под заголовком: перевод, отписка, картинки, метки
• Поиск находит слова и в скачанных вложениях
• Письма Outlook (.msg), текстовые файлы и Markdown — прямо в почте
• Перевод: «Всегда переводить с языка», без предложений для языков телефона
• iPad: область чтения справа, снизу или скрыта; выбор писем с Cmd и Shift; вложения — в области чтения
• Разрешение на уведомления — после добавления ящика, в одном шаге настройки
• Исправлено: свайп по письму мог застрять на середине
</ru-RU>
<en-US>
• Message details as a row of chips under the header: translation, unsubscribe, images, tags
• Search also finds words inside downloaded attachments
• Outlook messages (.msg), text files and Markdown right in the app
• Translation: “Always translate from” a language, no offers for your device languages
• iPad: reading pane on the right, at the bottom or hidden; select messages with Cmd and Shift; attachments open in the reading pane
• Notification permission is asked after you add a mailbox, in one setup step
• Fixed: swiping a message could get stuck halfway
</en-US>
<de-DE>
• Nachrichtendetails als Symbolzeile unter dem Nachrichtenkopf: Übersetzung, Abbestellen, Bilder, Tags
• Die Suche findet Wörter auch in heruntergeladenen Anhängen
• Outlook-Nachrichten (.msg), Textdateien und Markdown direkt in der App
• Übersetzung: „Immer aus … übersetzen“, keine Vorschläge für die Sprachen des Geräts
• iPad: Lesebereich rechts, unten oder ausgeblendet; Nachrichten mit Cmd und Shift auswählen; Anhänge im Lesebereich
• Erlaubnis für Benachrichtigungen nach dem Hinzufügen eines Kontos, in einem Einrichtungsschritt
• Behoben: Wischen über eine Nachricht konnte auf halbem Weg hängen bleiben
</de-DE>
<fr-FR>
• Détails du message en une rangée d’icônes sous l’en-tête : traduction, désabonnement, images, balises
• La recherche trouve aussi les mots dans les pièces jointes téléchargées
• Messages Outlook (.msg), fichiers texte et Markdown directement dans l’app
• Traduction : « Toujours traduire depuis » une langue, aucune proposition pour les langues de l’appareil
• iPad : volet de lecture à droite, en bas ou masqué ; sélection des messages avec Cmd et Shift ; pièces jointes dans le volet de lecture
• Autorisation des notifications après l’ajout d’un compte, en une seule étape de configuration
• Corrigé : le balayage d’un message pouvait se bloquer à mi-chemin
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 480.

```
<ru-RU>
• Сведения о письме — строкой значков под заголовком
• Поиск по тексту вложений
• Старые DOC, XLS, PPT, а также TXT и Markdown — прямо в почте
• Письма Outlook (.msg) открываются как обычные
• Перевод: «всегда переводить с языка», без лишних предложений
• Планшет: область чтения снизу или скрыта, выбор писем как в Outlook
• Уведомления настраиваются в один шаг, и без сервисов Google
• Исправлено: свайп по письму застревал на середине
</ru-RU>
<en-US>
• Message details as a row of chips under the header
• Search finds text inside attachments
• Old DOC, XLS, PPT files, plus TXT and Markdown, right in the app
• Outlook messages (.msg) open like any other message
• Translation: “always translate from” a language, fewer needless offers
• Tablet: reading pane at the bottom or hidden, Outlook-style selection
• One-step notification setup, also without Google services
• Fixed: swiping a message could get stuck halfway
</en-US>
<de-DE>
• Nachrichtendetails als Symbolzeile unter dem Kopf
• Suche im Text von Anhängen
• Alte DOC, XLS, PPT sowie TXT und Markdown direkt in der App
• Outlook-Nachrichten (.msg) öffnen sich wie jede andere
• Übersetzung: „Immer aus … übersetzen“, weniger unnötige Vorschläge
• Tablet: Lesebereich unten oder ausgeblendet, Auswahl wie in Outlook
• Benachrichtigungen in einem Schritt einrichten, auch ohne Google-Dienste
• Behoben: Wischgeste blieb manchmal auf halbem Weg hängen
</de-DE>
<fr-FR>
• Infos du message en une rangée d’icônes sous l’en-tête
• Recherche dans le texte des pièces jointes
• Anciens DOC, XLS, PPT, plus TXT et Markdown, dans l’app
• Messages Outlook (.msg) ouverts comme les autres
• Traduction : « Toujours traduire depuis… », sans propositions inutiles
• Tablette : volet de lecture en bas ou masqué, sélection façon Outlook
• Notifications réglées en une étape, même sans services Google
• Corrigé : un balayage pouvait se bloquer à mi-chemin
</fr-FR>
<ar>
• تفاصيل الرسالة في صف من الرموز أسفل الترويسة
• البحث في نص المرفقات
• ملفات DOC وXLS وPPT القديمة، وكذلك TXT وMarkdown، داخل التطبيق مباشرةً
• تُفتح رسائل Outlook ‏(.msg) كأي رسالة أخرى
• الترجمة: خيار «الترجمة دائمًا من» لغة معيّنة، مع تقليل الاقتراحات غير الضرورية
• الجهاز اللوحي: جزء القراءة في الأسفل أو مخفي، وتحديد الرسائل كما في Outlook
• إعداد الإشعارات بخطوة واحدة، حتى بدون خدمات Google
• تم الإصلاح: كان التمرير السريع على الرسالة قد يتوقف في المنتصف
</ar>
<hu-HU>
• Az üzenet adatai ikonsorként a fejléc alatt
• Keresés a mellékletek szövegében
• Régi DOC, XLS, PPT, valamint TXT és Markdown az alkalmazásban
• Az Outlook-üzenetek (.msg) normál üzenetként nyílnak meg
• Fordítás: „Mindig fordítson erről: …”, kevesebb fölösleges felajánlás
• Táblagép: olvasóablak alul vagy elrejtve, kijelölés, mint az Outlookban
• Értesítések beállítása egy lépésben, Google-szolgáltatások nélkül is
• Javítva: az üzenet elhúzása félúton elakadhatott
</hu-HU>
<vi>
• Thông tin thư thành một hàng biểu tượng dưới phần đầu thư
• Tìm trong nội dung tệp đính kèm
• Tệp DOC, XLS, PPT cũ cùng TXT và Markdown mở ngay trong ứng dụng
• Thư Outlook (.msg) mở như thư thông thường
• Dịch: tùy chọn “Luôn dịch từ” một ngôn ngữ, bớt gợi ý dịch không cần thiết
• Máy tính bảng: ngăn đọc ở dưới hoặc ẩn, chọn thư như trong Outlook
• Thiết lập thông báo trong một bước, kể cả khi không có dịch vụ Google
• Đã sửa: thao tác vuốt thư có thể bị kẹt giữa chừng
</vi>
<da-DK>
• Beskedens detaljer som en række ikoner under mailhovedet
• Søgning i tekst i vedhæftede filer
• Gamle DOC, XLS, PPT samt TXT og Markdown direkte i appen
• Outlook-beskeder (.msg) åbnes som almindelige beskeder
• Oversættelse: „Oversæt altid fra“ et sprog, færre unødvendige forslag
• Tablet: læserude nederst eller skjult, markering som i Outlook
• Notifikationer sættes op i ét trin, også uden Google-tjenester
• Rettet: stryg på en besked kunne gå i stå halvvejs
</da-DK>
<iw-IL>
• פרטי ההודעה כשורת סמלים מתחת לכותרת ההודעה
• חיפוש בטקסט של קבצים מצורפים
• קובצי DOC,‏ XLS,‏ PPT ישנים, וגם TXT ו-Markdown, ישירות באפליקציה
• הודעות Outlook ‏(.msg) נפתחות כמו כל הודעה אחרת
• תרגום: אפשרות לתרגם תמיד משפה מסוימת, ופחות הצעות תרגום מיותרות
• טאבלט: חלונית הקריאה למטה או מוסתרת, בחירת הודעות כמו ב-Outlook
• הגדרת התראות בשלב אחד, גם ללא שירותי Google
• תוקן: החלקה על הודעה עלולה הייתה להיתקע באמצע
</iw-IL>
<id>
• Info pesan sebagai deretan ikon di bawah header
• Pencarian di teks lampiran
• File DOC, XLS, PPT lama, serta TXT dan Markdown, langsung di aplikasi
• Pesan Outlook (.msg) terbuka seperti pesan biasa
• Terjemahan: opsi “Selalu terjemahkan dari”, tanpa tawaran yang tidak perlu
• Tablet: panel baca di bawah atau tersembunyi, pilih pesan ala Outlook
• Notifikasi diatur dalam satu langkah, juga tanpa layanan Google
• Diperbaiki: geser pesan bisa macet di tengah jalan
</id>
<es-ES>
• Detalles del mensaje en una fila de iconos bajo el encabezado
• Búsqueda en el texto de adjuntos
• DOC, XLS y PPT antiguos, más TXT y Markdown, en la app
• Los mensajes de Outlook (.msg) se abren como los demás
• Traducción: «Traducir siempre del…», sin sugerencias innecesarias
• Tableta: panel de lectura abajo u oculto, selección como en Outlook
• Notificaciones en un solo paso, también sin servicios de Google
• Corregido: deslizar un mensaje podía atascarse a medias
</es-ES>
<it-IT>
• Dettagli del messaggio in una riga di icone sotto l’intestazione
• Ricerca nel testo degli allegati
• Vecchi DOC, XLS, PPT, oltre a TXT e Markdown, nell’app
• I messaggi Outlook (.msg) si aprono come gli altri
• Traduzione: «Traduci sempre da…», niente proposte superflue
• Tablet: riquadro di lettura in basso o nascosto, selezione come in Outlook
• Notifiche in un solo passaggio, anche senza servizi Google
• Corretto: lo scorrimento di un messaggio si bloccava a metà
</it-IT>
<zh-CN>
• 邮件信息以一排小图标显示在邮件头下方
• 搜索附件中的文字
• 旧版 DOC、XLS、PPT 文件以及 TXT 和 Markdown 可直接在应用内打开
• Outlook 邮件（.msg）像普通邮件一样打开
• 翻译：可对某种语言选择“始终翻译”，减少不必要的翻译提示
• 平板：阅读窗格可置于底部或隐藏，像 Outlook 一样选择邮件
• 一步完成通知设置，没有 Google 服务也可以
• 修复：滑动邮件时可能卡在一半的问题
</zh-CN>
<ko-KR>
• 메일 정보를 헤더 아래 아이콘 한 줄로 표시
• 첨부 파일 텍스트에서도 검색
• 이전 형식의 DOC, XLS, PPT 파일과 TXT, Markdown을 앱에서 바로 열기
• Outlook 메일(.msg)을 일반 메일처럼 열기
• 번역: 특정 언어는 ‘항상 번역’ 옵션, 불필요한 번역 제안 감소
• 태블릿: 읽기 창을 아래에 두거나 숨기기, Outlook처럼 메일 선택
• 알림을 한 단계로 설정, Google 서비스 없이도 가능
• 수정: 메일을 스와이프하면 중간에 멈출 수 있던 문제
</ko-KR>
<nl-NL>
• Berichtinfo als rij pictogrammen onder de kop
• Zoeken in de tekst van bijlagen
• Oude DOC, XLS, PPT, plus TXT en Markdown, direct in de app
• Outlook-berichten (.msg) openen als gewone berichten
• Vertaling: ‘Altijd vertalen uit het …’, minder onnodige voorstellen
• Tablet: leesvenster onderaan of verborgen, selecteren zoals in Outlook
• Meldingen in één stap instellen, ook zonder Google-services
• Opgelost: vegen over een bericht kon halverwege blijven hangen
</nl-NL>
<no-NO>
• Meldingsdetaljer som en rad ikoner under meldingshodet
• Søk i tekst i vedlegg
• Gamle DOC-, XLS- og PPT-filer samt TXT og Markdown rett i appen
• Outlook-meldinger (.msg) åpnes som vanlige meldinger
• Oversettelse: «Oversett alltid fra» et språk, færre unødvendige forslag
• Nettbrett: leserute nederst eller skjult, markering som i Outlook
• Varsler settes opp i ett trinn, også uten Google-tjenester
• Rettet: sveip på en melding kunne stoppe opp halvveis
</no-NO>
<pl-PL>
• Informacje o wiadomości jako rząd ikon pod nagłówkiem
• Wyszukiwanie w tekście załączników
• Stare DOC, XLS, PPT, a także TXT i Markdown w aplikacji
• Wiadomości Outlook (.msg) otwierają się jak każde inne
• Tłumaczenie: „Zawsze tłumacz z języka…”, mniej zbędnych propozycji
• Tablet: okienko odczytu na dole lub ukryte, zaznaczanie jak w Outlooku
• Powiadomienia w jednym kroku, także bez usług Google
• Naprawiono: przesunięcie wiadomości mogło utknąć w połowie
</pl-PL>
<pt-BR>
• Detalhes da mensagem em uma linha de ícones abaixo do cabeçalho
• Pesquisa no texto dos anexos
• DOC, XLS e PPT antigos, além de TXT e Markdown, no app
• Mensagens do Outlook (.msg) abrem como qualquer outra
• Tradução: “Traduzir sempre de” um idioma, menos sugestões desnecessárias
• Tablet: painel de leitura embaixo ou oculto, seleção como no Outlook
• Notificações em uma etapa, também sem serviços do Google
• Corrigido: deslizar uma mensagem podia travar no meio
</pt-BR>
<ro>
• Detaliile mesajului într-un rând de pictograme sub antet
• Căutare în textul atașamentelor
• DOC, XLS, PPT vechi, plus TXT și Markdown, direct în aplicație
• Mesajele Outlook (.msg) se deschid ca oricare altele
• Traducere: „Tradu întotdeauna din” o limbă, fără propuneri inutile
• Tabletă: panoul de citire jos sau ascuns, selectare ca în Outlook
• Notificări configurate într-un pas, și fără serviciile Google
• Corectat: glisarea unui mesaj se putea bloca la jumătate
</ro>
<sk>
• Informácie o správe ako rad ikon pod hlavičkou
• Hľadanie v texte príloh
• Staré súbory DOC, XLS, PPT, ako aj TXT a Markdown priamo v aplikácii
• Správy Outlook (.msg) sa otvoria ako bežné správy
• Preklad: „Vždy prekladať z jazyka…“, menej zbytočných ponúk
• Tablet: tabla na čítanie dole alebo skrytá, výber ako v Outlooku
• Upozornenia nastavíte v jednom kroku, aj bez služieb Google
• Opravené: potiahnutie správy sa mohlo zaseknúť v polovici
</sk>
<th>
• ข้อมูลของอีเมลแสดงเป็นไอคอนแถวเดียวใต้ส่วนหัว
• ค้นหาในข้อความของไฟล์แนบ
• เปิดไฟล์ DOC, XLS, PPT รุ่นเก่า รวมถึง TXT และ Markdown ในแอปได้ทันที
• อีเมล Outlook (.msg) เปิดได้เหมือนอีเมลทั่วไป
• การแปล: ตัวเลือก “แปลจากภาษานี้เสมอ” และเสนอแปลเฉพาะเมื่อจำเป็น
• แท็บเล็ต: บานหน้าต่างการอ่านอยู่ด้านล่างหรือซ่อนได้ เลือกอีเมลแบบ Outlook
• ตั้งค่าการแจ้งเตือนได้ในขั้นตอนเดียว แม้ไม่มีบริการ Google
• แก้ไข: การปัดอีเมลอาจค้างอยู่กลางทาง
</th>
<tr-TR>
• İleti bilgileri, başlığın altında tek sıra simge hâlinde
• Ek metinlerinde arama
• Eski DOC, XLS, PPT dosyaları ile TXT ve Markdown doğrudan uygulamada
• Outlook iletileri (.msg) normal iletiler gibi açılır
• Çeviri: “Bu dilden her zaman çevir” seçeneği, daha az gereksiz öneri
• Tablet: okuma bölmesi altta veya gizli, Outlook’taki gibi seçim
• Bildirimler tek adımda ayarlanır, Google hizmetleri olmadan da
• Düzeltildi: iletiyi kaydırma yarı yolda takılabiliyordu
</tr-TR>
<fi-FI>
• Viestin tiedot kuvakerivinä otsikkotietojen alla
• Haku liitteiden tekstistä
• Vanhat DOC, XLS, PPT sekä TXT ja Markdown suoraan sovelluksessa
• Outlook-viestit (.msg) avautuvat kuten muutkin viestit
• Käännös: ”Käännä aina kielestä …”, ei turhia käännösehdotuksia
• Tabletti: lukuruutu alhaalla tai piilossa, valinta kuten Outlookissa
• Ilmoitusten asetukset yhdessä vaiheessa, myös ilman Google-palveluita
• Korjattu: viestin pyyhkäisy saattoi jäädä puolitiehen
</fi-FI>
<hi-IN>
• ईमेल की जानकारी हेडर के नीचे आइकन की एक पंक्ति में
• अटैचमेंट के टेक्स्ट में खोज
• पुरानी DOC, XLS, PPT फ़ाइलें, साथ ही TXT और Markdown, सीधे ऐप में
• Outlook ईमेल (.msg) सामान्य ईमेल की तरह खुलते हैं
• अनुवाद: किसी भाषा से “हमेशा अनुवाद करें” विकल्प, बेवजह के सुझाव कम
• टैबलेट: पठन फलक नीचे या छिपा हुआ, Outlook की तरह ईमेल का चयन
• एक ही चरण में सूचनाओं का सेटअप, Google सेवाओं के बिना भी
• ठीक किया गया: ईमेल पर स्वाइप बीच में अटक सकता था
</hi-IN>
<cs-CZ>
• Informace o zprávě jako řada ikon pod záhlavím
• Hledání v textu příloh
• Staré soubory DOC, XLS, PPT a také TXT a Markdown přímo v aplikaci
• Zprávy Outlook (.msg) se otevírají jako běžné zprávy
• Překlad: „Vždy překládat z jazyka…“, méně zbytečných nabídek
• Tablet: podokno čtení dole nebo skryté, výběr jako v Outlooku
• Oznámení nastavíte v jednom kroku, i bez služeb Google
• Opraveno: přejetí zprávy se mohlo zaseknout v polovině
</cs-CZ>
<sv-SE>
• Meddelandeinfo som en rad ikoner under meddelandehuvudet
• Sökning i bilagornas text
• Gamla DOC, XLS, PPT samt TXT och Markdown direkt i appen
• Outlook-meddelanden (.msg) öppnas som vanliga meddelanden
• Översättning: ”Översätt alltid från” ett språk, färre onödiga förslag
• Surfplatta: läsfönster nederst eller dolt, markering som i Outlook
• Aviseringar ställs in i ett steg, även utan Google-tjänster
• Åtgärdat: svep på ett meddelande kunde fastna halvvägs
</sv-SE>
<ja-JP>
• メールの情報をヘッダーの下に小さなアイコンの列で表示
• 添付ファイルのテキストも検索
• 旧形式の DOC・XLS・PPT と TXT・Markdown をアプリ内で表示
• Outlook のメール（.msg）を通常のメールと同様に表示
• 翻訳：言語ごとに「常に翻訳する」を設定可能、不要な翻訳の提案を削減
• タブレット：閲覧ウィンドウを下に表示または非表示、Outlook のようにメールを選択
• 通知の設定がワンステップで完了、Google サービスなしでも可能
• 修正：メールのスワイプが途中で止まることがある問題
</ja-JP>
```
