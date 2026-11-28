# «Что нового» — 2.7.5 (176), после 2.7.4 (175)

Просьба владельца 28.11.2026: «И подними, пожалуйста, версию». В 2.7.5 —
всё, что сделано после сборки 2.7.4. Шаги владельца — `OWNER_STEPS_2.7.5.md`.
Зависимости, схема базы, ключи, манифест Android и серверы не менялись; в
`ios/Runner/Info.plist` — схема ссылки и группа приложений для расширения
«Поделиться» (файлы Xcode не менялись — расширение подключает владелец).

## Сделано в 2.7.5

- **Вложения: своего лимита 25 МБ больше нет** (просьба пользователей 4PDA
  27.11.2026: «снять лимит и ориентироваться на лимиты сервера»). Пока
  сервер лимит не назвал (политика Exchange или ответ «письмо слишком
  большое»), файлы добавляются без проверки, строка размера — «Письмо:
  N МБ» с пояснением «?». Сервер не примет — причина видна, лимит
  запоминается для ящика, дальше проверка по нему.
- **@-упоминания при написании** (просьбы владельца «доделать @ФИО» и
  28.11.2026: «@ганиев» — пусто): «@» и начало имени в тексте письма —
  строка подходящих людей прямо над клавиатурой (раньше она пряталась за
  клавиатурой): адресаты письма, контакты (избранные и частые), отправители
  писем, а у ящиков Exchange — и адресная книга организации (коллеги, с
  которыми ещё не переписывались). Выбор вставляет упоминание, как в Outlook
  (Outlook и веб-почта его узнают), и добавляет человека в «Кому». Входящие
  упоминания — как раньше (фильтр «Упоминания»).
- **Флаг и срок — одна кнопка везде** (замечания владельца 27 и 28.11.2026):
  «Флаг» в меню письма, в «Ещё» карточки по удержанию в ленте и в панели
  команд широкого экрана открывает выбор: сегодня, завтра, на этой неделе,
  на следующей неделе, без даты, «Снять флажок». Отдельной кнопки «Срок
  флажка» больше нет.
- **Категории с цветами вместо тегов** (замечания владельца 27 и 28.11.2026):
  - «Добавить тег» и «Категории Outlook» — одна кнопка «Категории»: у
    Exchange категории уходят на сервер (видны в Outlook), прежние теги
    переходят в категории; у остальных ящиков — на телефоне;
  - у каждой категории — цвет: категории ящика Exchange — цветом из Outlook
    (главный список категорий ящика), стандартные («Красная категория»…) —
    своим, остальные — постоянным цветом палитры; свой цвет — кружком слева
    (и «Цвет по умолчанию»). В ленте, в карточке по удержанию, в письме и в
    отборе «По категории» — категории их цветами;
  - **несколько писем сразу**: выделите письма → «Категории» (в «⋮» и в
    сводке выделения на планшете). Категория, которая есть у части писем,
    отмечена чертой: касание — поставить всем, ещё раз — снять у всех, ещё
    раз — оставить как было;
  - «Настройки → Категории»: цвет у каждой категории, ниже — категории
    Outlook ваших ящиков Exchange.
- **Контакты: звонок и SMS на полный номер** (просьба владельца
  28.11.2026). Полный номер — с кодом страны или города; короткий внутренний
  («39-397») — только звонок. Карточка контакта: кнопки «Звонок» и «SMS»
  (звонок — на полный номер, если он есть; SMS — на мобильный, иначе на
  рабочий), у полного номера в «Связи» — значок SMS; «Ещё» карточки по
  удержанию — «SMS»; карточка человека из письма — «Звонок» и «SMS».
  Удержание кнопки звонка в списке — SMS и мессенджеры номера.
- **Добавочные номера** (замечание владельца 28.11.2026: «39-397 — добавочный,
  позвонить можно, зная основной номер»). Звонок на добавочный (до 6 цифр)
  с мобильного: приложение один раз спрашивает основной номер организации
  (для домена почты контакта, например `yamalspg.ru`) и запоминает его;
  дальше набирает основной номер, а после ответа — добавочный (пауза в
  номере, как «доб.» в телефонной книге). «Набрать как есть» — для звонка
  с рабочего телефона. Сменить основной номер — удержание номера →
  «Основной номер организации». Номер с «доб. 123» набирается так же:
  основной, после ответа — добавочный (раньше цифры добавочного
  дописывались к номеру). На добавочные и номера с «доб.» SMS не
  предлагается.
- **Беседа под письмом — настройка** (просьба владельца 28.11.2026: «работает
  только при открытии из уведомления, из программы — нет»). Под письмом —
  цепочка беседы; при группировке бесед лента открывает беседу из
  нескольких писем экраном беседы, а письмо — с него, и там цепочка не
  показывалась (беседа на предыдущем экране). «Настройки → Почта → Беседа
  под письмом»: «Всегда» (и с экрана беседы), «При открытии из
  уведомления» (по умолчанию, как было: и из поиска, ссылки, виджета —
  когда письмо открыто не с экрана беседы), «Никогда».
- **Мобильный интернет** (журнал пользователя 27.11.2026):
  - **письмо не уходило, если сразу свернуть приложение** (Android): письмо
    начало уходить, через 3 с приложение свернули — Android 12+ его
    заморозил, и отправка встала до следующего открытия («прервана, статус
    неизвестен»). Теперь, пока идёт отправка или проверка почты, свёрнутое
    приложение ставит короткую задачу системе (до 3 минут) — его не
    замораживают, письмо уходит. На iPhone так было и раньше, но отправку
    из «Исходящих» (с 2.7.4 — все письма) защита не видела — исправлено;
  - **проверка ящика висела 90 с на входе**: ответ сервера Яндекса на вход
    потерялся, приложение ждало общий срок ответа — 3 минуты. Теперь на
    вход — 25 с, затем одно новое подключение;
  - **Gmail по паролю приложения**: на каждой проверке приложение ходило в
    календарь и контакты Google и получало отказ (161 запрос за сутки) —
    Google пускает туда только по входу через Google. Теперь не ходит;
  - в журнале — сколько этап синхронизации шёл на самом деле (было «не
    завершился за 180 с» при обрыве через 90).
- **Флажок «Сегодня» из Outlook во вчерашнем дне** (4PDA, 28.11.2026):
  срок брался из UtcDueDate (местная полночь в UTC — к востоку от Гринвича
  это вчерашний день по UTC). Теперь день — из плавающей DueDate. Так же
  исправлены флажки, поставленные самим приложением.
- **Задачи: «На этой неделе» — до конца календарной недели** и группа «На
  следующей неделе» (4PDA: в субботу задачи на понедельник–четверг стояли
  в «На этой неделе»).
- **Выбор адресатов** (4PDA: «нажимаю на значок человека — выбора контактов
  нет»): окно сразу показывает контакты всех ящиков и телефона —
  избранные, частые, затем по имени. **Импорт контактов с телефона** больше
  не создаёт дублей (ни с контактами Google и Exchange, ни при повторном
  импорте).
- **Погода в «Моём дне»** (просьбы владельца 27.11.2026): рисунок погоды
  фоном карточки «Сейчас» — солнце, луна ночью, облака, туман, дождь,
  снег, гроза (бледно, справа, за значком погоды; город — пролистанный).
  Окно погоды открывается на том городе, по которому нажали; нажатие на
  город в списке — его прогноз по часам. «В виджетах» — залитой кнопкой,
  заметно и в монохромной теме.
- **iPhone** (жалобы пользователей): при прикреплении — пункт «Фото и
  видео» (галерея; «Файл с устройства» на iPhone открывает «Файлы», где
  галереи нет). «Поделиться»: приложение появится в списке после
  подключения расширения в Xcode (шаги владельца, раздел 2) — код
  расширения готов.

## Кратко (RU / EN)

**RU.** @-упоминания с подсказками из контактов и адресной книги; категории с
цветами вместо тегов — и для нескольких писем сразу; флажок и срок одной
кнопкой; вложения — по лимиту сервера; звонок и SMS контактам, добавочные —
через основной номер; рисунок погоды в «Моём дне»; на iPhone — фото из
галереи; письмо уходит, даже если сразу свернуть приложение; исправления дат
флажков и группировки задач.

**EN.** @mentions with suggestions from contacts and the company directory;
colour categories instead of tags, also for several emails at once; flag and
due date in one button; attachments limited only by your server; call and
SMS for contacts, extensions via the main number; weather picture in My day;
iPhone: photos from the gallery; email is sent even if you minimize the app
right away; fixes for flag dates and task grouping.

## Google Play — короткий текст (27 языков)

Самый длинный — 498 знаков (de-DE; предел — 500).

```
<ru-RU>
• @-упоминания: «@» и имя — подсказки из контактов и адресной книги организации
• Категории с цветами вместо тегов, как в Outlook, — и сразу для нескольких писем
• Флажок и срок — одной кнопкой
• Вложения — по лимиту вашего сервера
• Контакты: звонок и SMS на полный номер; выбор адресатов — сразу список
• Рисунок погоды в «Моём дне»; на iPhone — фото из галереи
• Исправления: отправка после сворачивания, даты флажков Outlook, задачи по неделям
</ru-RU>
<en-US>
• @mentions: type @ and a name to get suggestions from contacts and the company directory
• Colour categories instead of tags, like in Outlook — also for several emails at once
• Flag and due date in one button
• Attachments are limited only by your server
• Contacts: call and SMS for full numbers; the recipient picker lists contacts right away
• Weather picture in My day; iPhone: photos from the gallery
• Fixes: sending after minimizing the app, Outlook flag dates, task groups by week
</en-US>
<de-DE>
• @-Erwähnungen: @ und Name eingeben – Vorschläge aus Kontakten und dem Firmenverzeichnis
• Farbkategorien statt Tags wie in Outlook – auch für mehrere E-Mails auf einmal
• Flagge und Fälligkeit mit einer Taste
• Anhänge nur noch durch Ihren Server begrenzt
• Kontakte: Anruf und SMS an vollständige Nummern; die Empfängerauswahl zeigt sofort Kontakte
• Wetterbild in „Mein Tag“; iPhone: Fotos aus der Galerie
• Korrekturen: Senden nach dem Minimieren, Flaggendaten aus Outlook, Aufgaben nach Woche
</de-DE>
<fr-FR>
• Mentions @ : tapez @ et un nom — suggestions des contacts et de l’annuaire
• Catégories de couleur au lieu des étiquettes, comme dans Outlook — aussi en lot
• Indicateur et échéance en un seul bouton
• Pièces jointes limitées seulement par votre serveur
• Contacts : appel et SMS vers les numéros complets ; choix des destinataires immédiat
• Image météo dans « Ma journée » ; iPhone : photos de la galerie
• Corrections : envoi après réduction de l’app, dates Outlook, tâches par semaine
</fr-FR>
<ar>
• الإشارات @: اكتب @ واسمًا لتظهر اقتراحات من جهات الاتصال ودليل المؤسسة
• فئات ملونة بدلًا من الوسوم كما في Outlook — ولعدة رسائل دفعة واحدة
• العلم وتاريخ الاستحقاق بزر واحد
• المرفقات محدودة بخادمك فقط
• جهات الاتصال: اتصال وSMS للأرقام الكاملة؛ اختيار المستلمين يعرض جهات الاتصال فورًا
• صورة الطقس في «يومي»؛ على iPhone: صور من المعرض
• إصلاحات: الإرسال بعد تصغير التطبيق، تواريخ أعلام Outlook، تجميع المهام حسب الأسبوع
</ar>
<hu-HU>
• @-említések: írjon @-ot és nevet – javaslatok a névjegyekből és a céges címjegyzékből
• Színes kategóriák címkék helyett, mint az Outlookban – egyszerre több levélre is
• Zászló és határidő egy gombbal
• A mellékletek korlátja csak a szerveré
• Névjegyek: hívás és SMS teljes számra; a címzettválasztó azonnal listáz
• Időjárás-kép a „Napom” nézetben; iPhone: fotók a galériából
• Javítások: küldés háttérbe tétel után, Outlook-zászlók dátuma, heti feladatok
</hu-HU>
<vi>
• Nhắc tên @: gõ @ và tên để có gợi ý từ danh bạ và danh bạ công ty
• Danh mục màu thay cho thẻ, như Outlook — áp dụng cho nhiều thư cùng lúc
• Cờ và hạn chót trong một nút
• Tệp đính kèm chỉ giới hạn theo máy chủ của bạn
• Danh bạ: gọi và SMS tới số đầy đủ; chọn người nhận hiện danh bạ ngay
• Hình thời tiết trong Ngày của tôi; iPhone: ảnh từ thư viện
• Sửa lỗi: gửi thư sau khi thu nhỏ ứng dụng, ngày cờ từ Outlook, nhóm công việc theo tuần
</vi>
<da-DK>
• @-omtaler: skriv @ og et navn – forslag fra kontakter og firmaets adressebog
• Farvekategorier i stedet for tags som i Outlook – også for flere mails på én gang
• Flag og forfaldsdato med én knap
• Vedhæftninger begrænses kun af din server
• Kontakter: opkald og sms til fulde numre; valg af modtagere viser kontakter med det samme
• Vejrbillede i Min dag; iPhone: fotos fra galleriet
• Rettelser: afsendelse efter minimering, flagdatoer fra Outlook, opgaver efter uge
</da-DK>
<iw-IL>
• אזכורים עם @: הקלידו @ ושם — הצעות מאנשי הקשר ומספר הכתובות של הארגון
• קטגוריות צבעוניות במקום תגיות, כמו ב-Outlook — גם לכמה הודעות בבת אחת
• דגל ותאריך יעד בכפתור אחד
• קבצים מצורפים מוגבלים רק לפי השרת שלכם
• אנשי קשר: שיחה ו-SMS למספרים מלאים; בחירת נמענים מציגה אנשי קשר מיד
• תמונת מזג אוויר ב„היום שלי”; ב-iPhone: תמונות מהגלריה
• תיקונים: שליחה אחרי מזעור האפליקציה, תאריכי דגלים מ-Outlook, משימות לפי שבוע
</iw-IL>
<id>
• Sebutan @: ketik @ dan nama — saran dari kontak dan direktori perusahaan
• Kategori berwarna menggantikan tag, seperti di Outlook — juga untuk beberapa email sekaligus
• Bendera dan tenggat dalam satu tombol
• Lampiran hanya dibatasi oleh server Anda
• Kontak: telepon dan SMS ke nomor lengkap; pemilih penerima langsung menampilkan kontak
• Gambar cuaca di Hari Saya; iPhone: foto dari galeri
• Perbaikan: kirim setelah aplikasi diminimalkan, tanggal bendera Outlook, tugas per minggu
</id>
<es-ES>
• Menciones con @: escribe @ y un nombre — sugerencias de contactos y del directorio
• Categorías de color en lugar de etiquetas, como en Outlook, también para varios correos a la vez
• Marca y vencimiento en un solo botón
• Adjuntos limitados solo por tu servidor
• Contactos: llamada y SMS a números completos; lista de destinatarios al instante
• Imagen del tiempo en Mi día; iPhone: fotos de la galería
• Correcciones: envío tras minimizar la app, fechas de marcas Outlook, tareas por semana
</es-ES>
<it-IT>
• Menzioni @: digita @ e un nome — suggerimenti da contatti e rubrica aziendale
• Categorie a colori al posto dei tag, come in Outlook, anche per più email insieme
• Contrassegno e scadenza in un solo pulsante
• Allegati limitati solo dal tuo server
• Contatti: chiamata e SMS ai numeri completi; la scelta dei destinatari mostra subito i contatti
• Immagine meteo in La mia giornata; iPhone: foto dalla galleria
• Correzioni: invio dopo aver ridotto l’app, date Outlook, attività per settimana
</it-IT>
<zh-CN>
• @提及：输入 @ 和姓名，即可从联系人和公司通讯录中获得建议
• 彩色类别取代标签，与 Outlook 一致，也可一次用于多封邮件
• 旗标与截止日期合为一个按钮
• 附件大小仅受您的服务器限制
• 联系人：可向完整号码拨打电话和发短信；选择收件人时立即显示联系人
• “我的一天”显示天气图；iPhone：可从相册添加照片
• 修复：最小化应用后的发送、Outlook 旗标日期、任务按周分组
</zh-CN>
<ko-KR>
• @멘션: @와 이름을 입력하면 연락처와 회사 주소록에서 추천
• 태그 대신 Outlook처럼 색상 범주 — 여러 메일에 한 번에 적용
• 플래그와 기한을 버튼 하나로
• 첨부 파일은 서버 한도만 적용
• 연락처: 전체 번호로 전화와 문자, 받는 사람 선택 시 연락처 바로 표시
• 내 하루에 날씨 그림, iPhone: 갤러리의 사진
• 수정: 앱을 내린 뒤 보내기, Outlook 플래그 날짜, 주별 작업 그룹
</ko-KR>
<nl-NL>
• @-vermeldingen: typ @ en een naam voor suggesties uit contacten en het bedrijfsadresboek
• Kleurcategorieën in plaats van tags, zoals in Outlook – ook voor meerdere mails tegelijk
• Vlag en vervaldatum in één knop
• Bijlagen alleen beperkt door je server
• Contacten: bellen en sms naar volledige nummers; ontvangers kiezen toont meteen contacten
• Weerafbeelding in Mijn dag; iPhone: foto's uit de galerij
• Oplossingen: verzenden na minimaliseren, vlagdatums uit Outlook, taken per week
</nl-NL>
<no-NO>
• @-omtaler: skriv @ og et navn – forslag fra kontakter og firmaets adressebok
• Fargekategorier i stedet for tagger, som i Outlook – også for flere e-poster samtidig
• Flagg og forfallsdato med én knapp
• Vedlegg begrenses bare av serveren din
• Kontakter: ring og send SMS til fullstendige numre; valg av mottakere viser kontakter med en gang
• Værbilde i Min dag; iPhone: bilder fra galleriet
• Rettelser: sending etter minimering, flaggdatoer fra Outlook, oppgaver per uke
</no-NO>
<pl-PL>
• Wzmianki @: wpisz @ i imię — podpowiedzi z kontaktów i książki adresowej firmy
• Kolorowe kategorie zamiast tagów, jak w Outlooku — także dla wielu wiadomości naraz
• Flaga i termin jednym przyciskiem
• Załączniki ogranicza tylko Twój serwer
• Kontakty: połączenie i SMS na pełne numery; wybór odbiorców od razu pokazuje kontakty
• Obraz pogody w Moim dniu; iPhone: zdjęcia z galerii
• Poprawki: wysyłanie po zminimalizowaniu, daty flag z Outlooka, zadania tygodniami
</pl-PL>
<pt-BR>
• Menções com @: digite @ e um nome — sugestões dos contatos e do diretório
• Categorias coloridas no lugar de marcadores, como no Outlook — também em vários e-mails
• Sinalizador e prazo em um só botão
• Anexos limitados apenas pelo seu servidor
• Contatos: ligação e SMS para números completos; escolha de destinatários mostra os contatos na hora
• Imagem do clima em Meu dia; iPhone: fotos da galeria
• Correções: envio após minimizar o app, datas do Outlook, tarefas por semana
</pt-BR>
<ro>
• Mențiuni @: tastați @ și un nume — sugestii din contacte și agenda companiei
• Categorii colorate în locul etichetelor, ca în Outlook — și pentru mai multe mesaje deodată
• Steag și termen într-un singur buton
• Atașamentele sunt limitate doar de serverul dvs.
• Contacte: apel și SMS către numere complete; destinatarii — imediat din listă
• Imagine meteo în Ziua mea; iPhone: fotografii din galerie
• Remedieri: trimiterea după minimizare, date Outlook, sarcini pe săptămâni
</ro>
<sk>
• Zmienky @: napíšte @ a meno – návrhy z kontaktov a firemného adresára
• Farebné kategórie namiesto štítkov ako v Outlooku – aj pre viac správ naraz
• Príznak a termín jedným tlačidlom
• Prílohy obmedzuje len váš server
• Kontakty: hovor a SMS na úplné čísla; výber príjemcov hneď ukáže kontakty
• Obrázok počasia v Mojom dni; iPhone: fotky z galérie
• Opravy: odosielanie po minimalizovaní, dátumy príznakov z Outlooku, úlohy podľa týždňov
</sk>
<th>
• กล่าวถึงด้วย @: พิมพ์ @ และชื่อ เพื่อดูคำแนะนำจากรายชื่อติดต่อและสมุดที่อยู่ขององค์กร
• หมวดหมู่สีแทนแท็ก เหมือน Outlook — ใช้กับหลายอีเมลพร้อมกันได้
• ธงและวันครบกำหนดในปุ่มเดียว
• ไฟล์แนบจำกัดตามเซิร์ฟเวอร์ของคุณเท่านั้น
• รายชื่อติดต่อ: โทรและส่ง SMS ไปยังหมายเลขเต็ม; เลือกผู้รับแล้วเห็นรายชื่อทันที
• ภาพสภาพอากาศใน วันของฉัน; iPhone: รูปจากคลังภาพ
• แก้ไข: การส่งหลังย่อแอป, วันที่ธงจาก Outlook, จัดกลุ่มงานตามสัปดาห์
</th>
<tr-TR>
• @ bahsetme: @ ve bir ad yazın — kişilerden ve şirket rehberinden öneriler
• Etiketler yerine Outlook'taki gibi renkli kategoriler — birden çok e-postaya aynı anda
• Bayrak ve son tarih tek düğmede
• Ekler yalnızca sunucunuzun sınırına bağlı
• Kişiler: tam numaralara arama ve SMS; alıcı seçimi kişileri hemen gösterir
• Günüm'de hava durumu resmi; iPhone: galeriden fotoğraflar
• Düzeltmeler: uygulama küçültülünce gönderim, Outlook bayrak tarihleri, haftalık görevler
</tr-TR>
<fi-FI>
• @-maininnat: kirjoita @ ja nimi – ehdotukset yhteystiedoista ja yrityksen osoitteistosta
• Väriluokat tunnisteiden tilalle kuten Outlookissa – myös useaan viestiin kerralla
• Lippu ja määräpäivä yhdellä painikkeella
• Liitteitä rajoittaa vain palvelimesi
• Yhteystiedot: puhelu ja tekstiviesti täydellisiin numeroihin; vastaanottajat näkyvät heti
• Sääkuva Minun päiväni -näkymässä; iPhone: kuvat galleriasta
• Korjaukset: lähetys pienentämisen jälkeen, Outlookin liput, tehtävät viikoittain
</fi-FI>
<hi-IN>
• @ उल्लेख: @ और नाम लिखें — संपर्कों और कंपनी निर्देशिका से सुझाव
• टैग की जगह Outlook जैसी रंगीन श्रेणियाँ — कई ईमेल पर एक साथ भी
• फ़्लैग और नियत तारीख एक ही बटन में
• अटैचमेंट की सीमा अब सिर्फ़ आपके सर्वर की
• संपर्क: पूरे नंबर पर कॉल और SMS; प्राप्तकर्ता चुनते ही संपर्क दिखते हैं
• मेरा दिन में मौसम का चित्र; iPhone: गैलरी से फ़ोटो
• सुधार: ऐप छोटा करने के बाद भेजना, Outlook फ़्लैग की तारीखें, हफ़्ते के हिसाब से कार्य
</hi-IN>
<cs-CZ>
• Zmínky @: napište @ a jméno – návrhy z kontaktů a firemního adresáře
• Barevné kategorie místo štítků jako v Outlooku – i pro více zpráv najednou
• Příznak a termín jedním tlačítkem
• Přílohy omezuje jen váš server
• Kontakty: hovor a SMS na úplná čísla; výběr příjemců hned ukáže kontakty
• Obrázek počasí v Mém dni; iPhone: fotky z galerie
• Opravy: odesílání po minimalizaci, data příznaků z Outlooku, úkoly podle týdnů
</cs-CZ>
<sv-SE>
• @-omnämnanden: skriv @ och ett namn – förslag från kontakter och företagets adressbok
• Färgkategorier i stället för taggar, som i Outlook – även för flera mejl på en gång
• Flagga och förfallodatum med en knapp
• Bilagor begränsas bara av din server
• Kontakter: samtal och sms till fullständiga nummer; mottagarvalet visar kontakter direkt
• Väderbild i Min dag; iPhone: foton från galleriet
• Rättelser: sändning efter minimering, flaggdatum från Outlook, uppgifter per vecka
</sv-SE>
<ja-JP>
• @メンション：@ と名前を入力すると、連絡先と社内アドレス帳から候補を表示
• タグに代わり Outlook と同じ色分類 — 複数のメールにまとめて設定
• フラグと期限を 1 つのボタンで
• 添付ファイルの上限はサーバーの制限のみ
• 連絡先：完全な番号へ電話と SMS、宛先の選択ですぐに連絡先を表示
• 「マイデイ」に天気のイラスト、iPhone はギャラリーの写真を添付
• 修正：アプリを閉じた後の送信、Outlook のフラグの日付、タスクの週ごとのグループ
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• @-упоминания: «@» и имя — подсказки из контактов и адресной книги организации
• Категории с цветами вместо тегов, как в Outlook, — и сразу для нескольких писем
• Флажок и срок — одной кнопкой
• Вложения — по лимиту вашего сервера
• Контакты: звонок и SMS на полный номер; выбор адресатов — сразу список
• Рисунок погоды в «Моём дне»; на iPhone — фото из галереи
• Исправления: отправка после сворачивания, даты флажков Outlook, задачи по неделям
</ru-RU>
<en-US>
• @mentions: type @ and a name to get suggestions from contacts and the company directory
• Colour categories instead of tags, like in Outlook — also for several emails at once
• Flag and due date in one button
• Attachments are limited only by your server
• Contacts: call and SMS for full numbers; the recipient picker lists contacts right away
• Weather picture in My day; iPhone: photos from the gallery
• Fixes: sending after minimizing the app, Outlook flag dates, task groups by week
</en-US>
<de-DE>
• @-Erwähnungen: @ und Name eingeben – Vorschläge aus Kontakten und dem Firmenverzeichnis
• Farbkategorien statt Tags wie in Outlook – auch für mehrere E-Mails auf einmal
• Flagge und Fälligkeit mit einer Taste
• Anhänge nur noch durch Ihren Server begrenzt
• Kontakte: Anruf und SMS an vollständige Nummern; die Empfängerauswahl zeigt sofort Kontakte
• Wetterbild in „Mein Tag“; iPhone: Fotos aus der Galerie
• Korrekturen: Senden nach dem Minimieren, Flaggendaten aus Outlook, Aufgaben nach Woche
</de-DE>
<fr-FR>
• Mentions @ : tapez @ et un nom — suggestions des contacts et de l’annuaire
• Catégories de couleur au lieu des étiquettes, comme dans Outlook — aussi en lot
• Indicateur et échéance en un seul bouton
• Pièces jointes limitées seulement par votre serveur
• Contacts : appel et SMS vers les numéros complets ; choix des destinataires immédiat
• Image météo dans « Ma journée » ; iPhone : photos de la galerie
• Corrections : envoi après réduction de l’app, dates Outlook, tâches par semaine
</fr-FR>
```
