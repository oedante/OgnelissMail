# «Что нового» — 2.4.0 (151)

Оценка интерфейса 12.11.2026 и пункты владельца (телефон, планшет,
компьютер), исправления по письмам владельца и PR #94 (поручения в
календаре, значок ящика в напоминаниях, картинки в редакторе, имена после
почтовых шлюзов). Шаги владельца — `OWNER_STEPS_2.4.0.md`. Подробно об
интерфейсе — `docs/design/UI_REVIEW_2026-11-12.md`, раздел 6.

## Сделано

- **Картинки в рассылках.** Логотипы, баннеры и кнопки с серверов служб
  рассылок (Mindbox, SendGrid, Mailchimp и др.) больше не вырезаются как
  счётчики — блокируется только сам счётчик открытий. Чип «Трекеры» виден
  и при разрешённых картинках — оттуда службу можно разблокировать.
- **Вложения, пересланные из веб-почты Яндекса** (фото с iPhone,
  помеченное «встроенным» без ссылки из текста), — в списке вложений;
  скрепка в ленте — по тем же правилам; «Переслать как .eml» — с исходным
  телом письма.
- **Календарь**: шапка «Календарь» с периодом и переключателем видов; на
  широком экране — неделя по умолчанию и колонка ближайших событий;
  пустое расписание — «Ближайшие 2 месяца свободны» и «Новая встреча».
- **Поручения в календаре** — слоем, как задачи (слой можно выключить);
  нажатие — карточка, долгое нажатие — быстрые действия. **Подзадачи
  поручения**: раздел «Подзадачи» в карточке, «Часть поручения» у
  подзадачи; связь видна и на других устройствах.
- **Задачи и заметки** на планшете и компьютере — сразу две колонки;
  заметки — карточками.
- **«Мой день»** на широком экране — часы и встречи слева, доска справа;
  подсказка доски — со значками.
- **Поручения** на широком экране — «Я поручил» и «Мне поручили» рядом.
- **Поиск**: на компьютере — строка в шапке каждого раздела, на телефоне —
  значок. Шапки разделов одной высоты.
- **Несколько выбранных писем** — сводка с действиями в области чтения;
  стрелки и J/K листают письма; пустая область чтения — непрочитанные и
  подсказки клавиш; редактор письма на широком экране — колонкой.
- **Письмо**: «Кому: … вам» под отправителем; подписи под значками нижней
  панели.
- **«Позже»** — день и время возврата в ленте; **«На контроле»** — срок,
  просроченный — красным.
- **Уведомления**: при нескольких ящиках — значок ящика (его фото или
  кружок цвета ящика) у писем и у напоминаний о встречах и задачах, в
  шапке напоминания — ящик.
- **Ящики без фото** — разные буквы в меню.
- **Редактор (Android)**: картинка, вставленная в текст, видна сразу.
- **Имена, порезанные почтовым шлюзом** («Олег Ермиши? ?utf8?Q…»),
  восстанавливаются; в кружке контакта нет апострофа (`'адрес'` из
  Outlook).
- **Настройки**: «Настройки почты» — пятью экранами (лента и письма,
  написание и отправка, загрузка и вложения, перевод, антифишинг);
  шрифт, масштаб, панели телефона и вид виджетов — в «Оформлении».
- Меню: разделы приложения — строкой значков, тема — в меню «⋮» ленты.
- **Пробно, по умолчанию выключено** (включить для всех — после проверки
  на устройствах): «Сложные письма — в окне браузера» на Mac («Почта →
  Лента и письма → Открытие писем») и «Новое встраивание окна письма
  (HCPP)» на Android 14+ («Расширенные → Графика»).

Платформы: манифест Android, `Info.plist`, `project.pbxproj`,
`Runner.entitlements`, Podfile с 2.3.2 не менялись. Новых разрешений и
зависимостей нет.

## Кратко (RU / EN)

**RU.** Картинки в рассылках снова видны — блокируются только счётчики
открытий. Вложения из пересланных писем не теряются. Новый календарь с
неделей и ближайшими событиями на планшете и компьютере, поручения в
календаре и подзадачи, заметки карточками, задачи и поручения в две
колонки. Действия с несколькими письмами, сроки «На контроле» в ленте,
понятнее настройки почты и оформления.

**EN.** Newsletter images are back — only open-tracking counters are
blocked. Attachments in forwarded messages are no longer lost. A new
calendar with a week view and upcoming events on tablets and computers,
assignments in the calendar with subtasks, notes as cards, tasks and
assignments in two columns. Actions on several messages, follow-up
deadlines in the list, clearer mail and appearance settings.

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Поле «Что нового в этой версии» — для каждого языка своё.

```
<ru-RU>
• Картинки в рассылках снова видны — блокируются только счётчики открытий
• Вложения в пересланных письмах больше не теряются
• Календарь: неделя и ближайшие события на планшете и компьютере
• Заметки карточками, задачи и поручения в две колонки; поручения в календаре
• Действия сразу с несколькими письмами; в «Позже» и «На контроле» — время и срок
• Понятнее настройки: почта по разделам, шрифт и масштаб — в «Оформлении»
</ru-RU>
<en-US>
• Newsletter images are back — only open-tracking counters are blocked
• Attachments in forwarded emails are no longer lost
• Calendar: week view and upcoming events on tablets and computers
• Notes as cards, tasks and assignments in two columns; assignments in the calendar
• Actions on several emails at once; Later and Tracked show the time and deadline
• Clearer settings: mail in sections, font and scale under Appearance
</en-US>
<de-DE>
• Bilder in Newslettern sind zurück – blockiert werden nur Öffnungszähler
• Anhänge weitergeleiteter E-Mails gehen nicht mehr verloren
• Kalender: Wochenansicht und nächste Termine auf Tablet und Computer
• Notizen als Karten, Aufgaben und Aufträge in zwei Spalten; Aufträge im Kalender
• Aktionen für mehrere E-Mails; „Später“ und „Im Blick“ zeigen Zeit und Frist
• Klarere Einstellungen: E-Mail in Bereichen, Schrift und Größe unter „Darstellung“
</de-DE>
<fr-FR>
• Images des newsletters de retour : seuls les compteurs d’ouverture sont bloqués
• Les pièces jointes des e-mails transférés ne se perdent plus
• Calendrier : vue semaine et prochains événements sur tablette et ordinateur
• Notes en cartes, tâches et missions sur deux colonnes ; missions dans le calendrier
• Actions sur plusieurs e-mails ; « Plus tard » et « Suivis » affichent heure et échéance
• Réglages plus clairs : e-mail par sections, police et échelle dans « Apparence »
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков; самый длинный — 481).

```
<ru-RU>
• Картинки в рассылках снова видны — блокируются только счётчики открытий
• Вложения в пересланных письмах больше не теряются
• Календарь: неделя и ближайшие события на планшете и компьютере
• Заметки карточками, задачи и поручения в две колонки; поручения в календаре
• Действия сразу с несколькими письмами; в «Позже» и «На контроле» — время и срок
• Понятнее настройки: почта по разделам, шрифт и масштаб — в «Оформлении»
</ru-RU>
<en-US>
• Newsletter images are back — only open-tracking counters are blocked
• Attachments in forwarded emails are no longer lost
• Calendar: week view and upcoming events on tablets and computers
• Notes as cards, tasks and assignments in two columns; assignments in the calendar
• Actions on several emails at once; Later and Tracked show the time and deadline
• Clearer settings: mail in sections, font and scale under Appearance
</en-US>
<de-DE>
• Bilder in Newslettern sind zurück – blockiert werden nur Öffnungszähler
• Anhänge weitergeleiteter E-Mails gehen nicht mehr verloren
• Kalender: Wochenansicht und nächste Termine auf Tablet und Computer
• Notizen als Karten, Aufgaben und Aufträge in zwei Spalten; Aufträge im Kalender
• Aktionen für mehrere E-Mails; „Später“ und „Im Blick“ zeigen Zeit und Frist
• Klarere Einstellungen: E-Mail in Bereichen, Schrift und Größe unter „Darstellung“
</de-DE>
<fr-FR>
• Images des newsletters de retour : seuls les compteurs d’ouverture sont bloqués
• Les pièces jointes des e-mails transférés ne se perdent plus
• Calendrier : vue semaine et prochains événements sur tablette et ordinateur
• Notes en cartes, tâches et missions sur deux colonnes ; missions dans le calendrier
• Actions sur plusieurs e-mails ; « Plus tard » et « Suivis » affichent heure et échéance
• Réglages plus clairs : e-mail par sections, police et échelle dans « Apparence »
</fr-FR>
<ar>
• عادت صور الرسائل الإخبارية، ولا يُحظر إلا عدّاد الفتح
• لم تعد المرفقات في الرسائل المُعاد توجيهها تضيع
• التقويم: عرض الأسبوع والأحداث القادمة على الأجهزة اللوحية والحواسيب
• الملاحظات كبطاقات، والمهام والتكليفات في عمودين؛ التكليفات في التقويم
• إجراءات على عدة رسائل دفعة واحدة؛ «لاحقًا» و«قيد المتابعة» تعرضان الوقت والموعد
• إعدادات أوضح: البريد في أقسام، والخط والحجم ضمن «المظهر»
</ar>
<hu-HU>
• Újra látszanak a hírlevelek képei – csak a megnyitásszámlálók tiltottak
• A továbbított levelek mellékletei már nem vesznek el
• Naptár: heti nézet és közelgő események táblagépen és számítógépen
• Jegyzetek kártyaként, feladatok és megbízások két oszlopban; megbízások a naptárban
• Műveletek több levélen; a „Később” és a „Követett” mutatja az időt és a határidőt
• Átláthatóbb beállítások: levelezés részenként, betű és méret a „Megjelenés” alatt
</hu-HU>
<vi>
• Hình ảnh trong bản tin hiển thị trở lại — chỉ chặn bộ đếm lượt mở
• Tệp đính kèm trong thư chuyển tiếp không còn bị mất
• Lịch: xem theo tuần và sự kiện sắp tới trên máy tính bảng và máy tính
• Ghi chú dạng thẻ, tác vụ và việc giao chia hai cột; việc giao hiện trong lịch
• Thao tác với nhiều thư cùng lúc; «Để sau» và «Đang theo dõi» hiển thị giờ và hạn
• Cài đặt rõ ràng hơn: thư chia theo mục, phông chữ và tỷ lệ trong «Giao diện»
</vi>
<da-DK>
• Billeder i nyhedsbreve vises igen – kun åbningstællere blokeres
• Vedhæftninger i videresendte mails går ikke længere tabt
• Kalender: ugevisning og kommende begivenheder på tablet og computer
• Noter som kort, opgaver i to kolonner; tildelte opgaver vises i kalenderen
• Handlinger på flere mails på én gang; "Senere" og "Overvåget" viser tid og frist
• Mere overskuelige indstillinger: mail i afsnit, skrift og størrelse under "Udseende"
</da-DK>
<iw-IL>
• התמונות בניוזלטרים חזרו – נחסמים רק מוני הפתיחה
• קבצים מצורפים במיילים שהועברו כבר לא הולכים לאיבוד
• יומן: תצוגת שבוע ואירועים קרובים בטאבלט ובמחשב
• הערות ככרטיסים, משימות ומטלות בשתי עמודות; מטלות ביומן
• פעולות על כמה מיילים בבת אחת; "מאוחר יותר" ו"במעקב" מציגים שעה ומועד
• הגדרות ברורות יותר: דואר לפי חלקים, גופן וגודל תחת "מראה"
</iw-IL>
<id>
• Gambar di buletin tampil lagi — hanya penghitung pembukaan yang diblokir
• Lampiran di email yang diteruskan tidak hilang lagi
• Kalender: tampilan minggu dan acara mendatang di tablet dan komputer
• Catatan sebagai kartu, tugas dan penugasan dalam dua kolom; penugasan di kalender
• Tindakan untuk beberapa email sekaligus; «Nanti» dan «Dipantau» tampilkan waktu dan tenggat
• Pengaturan lebih jelas: email per bagian, font dan skala di «Tampilan»
</id>
<es-ES>
• Vuelven las imágenes de los boletines: solo se bloquean los contadores de apertura
• Los adjuntos de los correos reenviados ya no se pierden
• Calendario: vista semanal y próximos eventos en tableta y ordenador
• Notas como tarjetas, tareas y encargos en dos columnas; encargos en el calendario
• Acciones con varios correos; «Más tarde» y «En seguimiento» muestran hora y plazo
• Ajustes más claros: correo por secciones, fuente y escala en «Apariencia»
</es-ES>
<it-IT>
• Tornano le immagini delle newsletter: si bloccano solo i contatori di apertura
• Gli allegati delle email inoltrate non vanno più persi
• Calendario: vista settimanale e prossimi eventi su tablet e computer
• Note come schede, attività e incarichi in due colonne; incarichi nel calendario
• Azioni su più email insieme; «Più tardi» e «Monitorati» mostrano ora e scadenza
• Impostazioni più chiare: posta divisa in sezioni, carattere e scala in «Aspetto»
</it-IT>
<zh-CN>
• 新闻邮件中的图片恢复显示，只拦截打开计数器
• 转发邮件中的附件不再丢失
• 日历：平板和电脑上的周视图和即将发生的事件
• 笔记以卡片显示，任务和任务分派分两栏；任务分派显示在日历中
• 可同时处理多封邮件；“稍后”和“跟进中”显示时间和截止日期
• 设置更清晰：邮件设置分为多个部分，字体和缩放位于“外观”
</zh-CN>
<ko-KR>
• 뉴스레터 이미지가 다시 표시됩니다 — 열람 추적기만 차단
• 전달된 메일의 첨부 파일이 더 이상 사라지지 않습니다
• 캘린더: 태블릿과 컴퓨터에서 주 보기와 다가오는 일정
• 메모는 카드로, 작업과 업무 지시는 두 열로; 캘린더에 업무 지시 표시
• 여러 메일을 한 번에 처리; '나중에'와 '추적 중'에 시간과 기한 표시
• 더 명확한 설정: 메일 설정을 항목별로, 글꼴과 배율은 '모양'에서
</ko-KR>
<nl-NL>
• Afbeeldingen in nieuwsbrieven zijn terug – alleen open-tellers worden geblokkeerd
• Bijlagen in doorgestuurde e-mails gaan niet meer verloren
• Agenda: weekweergave en komende afspraken op tablet en computer
• Notities als kaarten, taken en opdrachten in twee kolommen; opdrachten in de agenda
• Acties voor meerdere e-mails; ‘Later’ en ‘In de gaten’ tonen tijd en deadline
• Duidelijkere instellingen: e-mail in onderdelen, lettertype en schaal onder ‘Weergave’
</nl-NL>
<no-NO>
• Bilder i nyhetsbrev vises igjen – bare åpningstellere blokkeres
• Vedlegg i videresendte e-poster går ikke lenger tapt
• Kalender: ukevisning og kommende hendelser på nettbrett og datamaskin
• Notater som kort, oppgaver og oppdrag i to kolonner; oppdrag i kalenderen
• Handlinger på flere e-poster samtidig; «Senere» og «Overvåket» viser tid og frist
• Ryddigere innstillinger: e-post i deler, skrift og skalering under «Utseende»
</no-NO>
<pl-PL>
• Obrazy w newsletterach znów widoczne – blokowane są tylko liczniki otwarć
• Załączniki w przekazanych wiadomościach już nie giną
• Kalendarz: widok tygodnia i nadchodzące wydarzenia na tablecie i komputerze
• Notatki jako karty, zadania i zlecenia w dwóch kolumnach; zlecenia w kalendarzu
• Działania na kilku wiadomościach naraz; „Później” i „Śledzone” pokazują czas i termin
• Czytelniejsze ustawienia: poczta w sekcjach, czcionka i skala w „Wygląd”
</pl-PL>
<pt-BR>
• As imagens das newsletters voltaram — só os contadores de abertura são bloqueados
• Anexos em e-mails encaminhados não se perdem mais
• Calendário: visão semanal e próximos eventos no tablet e no computador
• Notas como cartões, tarefas e atribuições em duas colunas; atribuições no calendário
• Ações em vários e-mails; "Mais tarde" e "Em acompanhamento" mostram hora e prazo
• Configurações mais claras: e-mail por seções, fonte e escala em "Aparência"
</pt-BR>
<ro>
• Imaginile din newslettere sunt înapoi – se blochează doar contoarele de deschidere
• Atașamentele din e-mailurile redirecționate nu se mai pierd
• Calendar: vizualizare pe săptămână și evenimente viitoare pe tabletă și computer
• Note ca fișe, activități și sarcini în două coloane; sarcinile apar în calendar
• Acțiuni pentru mai multe e-mailuri; „Mai târziu” și „Urmărite” arată ora și termenul
• Setări mai clare: e-mail pe secțiuni, font și scalare în „Aspect”
</ro>
<sk>
• Obrázky v newsletteroch sú späť – blokujú sa len počítadlá otvorení
• Prílohy v preposlaných e-mailoch sa už nestrácajú
• Kalendár: týždenné zobrazenie a nadchádzajúce udalosti na tablete a počítači
• Poznámky ako karty, úlohy v dvoch stĺpcoch; zadané úlohy v kalendári
• Akcie s viacerými e-mailmi naraz; „Neskôr“ a „Sledované“ ukazujú čas a termín
• Prehľadnejšie nastavenia: pošta po sekciách, písmo a mierka v časti „Vzhľad“
</sk>
<th>
• รูปภาพในจดหมายข่าวกลับมาแสดงแล้ว บล็อกเฉพาะตัวนับการเปิดอ่าน
• ไฟล์แนบในอีเมลที่ส่งต่อไม่หายอีกต่อไป
• ปฏิทิน: มุมมองรายสัปดาห์และกิจกรรมที่กำลังจะมาถึงบนแท็บเล็ตและคอมพิวเตอร์
• โน้ตแบบการ์ด งานและงานมอบหมายแบบสองคอลัมน์ งานมอบหมายในปฏิทิน
• จัดการหลายอีเมลพร้อมกัน «ภายหลัง» และ «กำลังติดตาม» แสดงเวลาและกำหนดส่ง
• การตั้งค่าชัดเจนขึ้น: อีเมลแยกเป็นหมวด แบบอักษรและขนาดอยู่ใน «รูปลักษณ์»
</th>
<tr-TR>
• Bültenlerdeki görseller geri döndü — yalnızca açılma sayaçları engellenir
• İletilen e-postalardaki ekler artık kaybolmuyor
• Takvim: tablet ve bilgisayarda haftalık görünüm ve yaklaşan etkinlikler
• Notlar kart olarak, görevler ve görevlendirmeler iki sütunda; takvimde görevlendirmeler
• Birden çok e-postada işlem; «Daha sonra» ve «Takipte» saati ve son tarihi gösterir
• Daha anlaşılır ayarlar: e-posta bölümlere ayrıldı, yazı tipi ve ölçek «Görünüm» altında
</tr-TR>
<fi-FI>
• Uutiskirjeiden kuvat näkyvät taas – vain avauslaskurit estetään
• Edelleen lähetettyjen viestien liitteet eivät enää katoa
• Kalenteri: viikkonäkymä ja tulevat tapahtumat tabletilla ja tietokoneella
• Muistiinpanot kortteina, tehtävät ja toimeksiannot kahdessa sarakkeessa
• Toiminnot useille viesteille; ”Myöhemmin” ja ”Seurannassa” näyttävät ajan ja määräajan
• Selkeämmät asetukset: sähköposti osioittain, fontti ja koko kohdassa ”Ulkoasu”
</fi-FI>
<hi-IN>
• न्यूज़लेटर की तस्वीरें फिर से दिखती हैं — सिर्फ़ खोलने के काउंटर रोके जाते हैं
• फ़ॉरवर्ड किए गए ईमेल के अटैचमेंट अब नहीं खोते
• कैलेंडर: टैबलेट और कंप्यूटर पर सप्ताह दृश्य और आने वाले कार्यक्रम
• नोट कार्ड के रूप में, कार्य और सौंपे गए कार्य दो कॉलम में; कैलेंडर में सौंपे गए कार्य
• एक साथ कई ईमेल पर कार्रवाई; «बाद में» और «निगरानी में» समय और समय-सीमा दिखाते हैं
• साफ़ सेटिंग्स: ईमेल अलग हिस्सों में, फ़ॉन्ट और आकार «रूप-रंग» में
</hi-IN>
<cs-CZ>
• Obrázky v newsletterech jsou zpět – blokují se jen počítadla otevření
• Přílohy v přeposlaných e-mailech se už neztrácejí
• Kalendář: týdenní zobrazení a nadcházející události na tabletu a počítači
• Poznámky jako karty, úkoly ve dvou sloupcích; zadané úkoly v kalendáři
• Akce s více e-maily najednou; „Později“ a „Sledované“ ukazují čas a termín
• Přehlednější nastavení: pošta po sekcích, písmo a měřítko v části „Vzhled“
</cs-CZ>
<sv-SE>
• Bilder i nyhetsbrev visas igen – bara öppningsräknare blockeras
• Bilagor i vidarebefordrade mejl försvinner inte längre
• Kalender: veckovy och kommande händelser på surfplatta och dator
• Anteckningar som kort, uppgifter och uppdrag i två kolumner; uppdrag i kalendern
• Åtgärder på flera mejl samtidigt; ”Senare” och ”Bevakade” visar tid och deadline
• Tydligare inställningar: e-post i avsnitt, typsnitt och skala under ”Utseende”
</sv-SE>
<ja-JP>
• ニュースレターの画像が再び表示されます（開封カウンターのみブロック）
• 転送されたメールの添付ファイルが失われなくなりました
• カレンダー：タブレットとパソコンで週表示と今後の予定
• メモはカード表示、タスクと依頼は2列表示。依頼はカレンダーにも表示
• 複数のメールをまとめて操作。「後で」と「追跡中」に時刻と期限を表示
• 設定を整理：メール設定を項目別に、フォントと拡大率は「外観」に
</ja-JP>
```
