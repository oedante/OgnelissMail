# «Что нового» — 2.5.1 (153)

2.5.0 и исправления 14.11.2026: отправка через серверы вроде Mercury
(жалоба пользователя), приветствие в письмах поручений (замечание
владельца). Решение владельца 14.11.2026 — 2.5.1, в релиз. Шаги
владельца — `OWNER_STEPS_2.5.1.md`.

## Сделано

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
- **Полное ФИО человека — с первого раза.** Справочник имён ждал сам себя:
  первый запрос не завершался, полное имя в карточке человека, у
  получателей письма и участников встречи появлялось только со второго
  раза.

Платформы: манифест Android, `Info.plist`, `project.pbxproj`,
`Runner.entitlements`, Podfile, зависимости и схема базы (30) с 2.5.0 не
менялись.

## Кратко (RU / EN)

**RU.** Письма через серверы вроде Mercury больше не зависают в очереди с
ошибкой «354». Письма поручений начинаются с того же приветствия, что и
ваши письма, — по имени и отчеству при любом порядке ФИО.

**EN.** Messages sent through servers like Mercury no longer get stuck in
the outbox with a “354” error. Assignment emails start with the same
greeting as your messages, using the first name whatever the order of the
name.

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Поле «Что нового в этой версии» — для каждого языка своё.

```
<ru-RU>
• Отправка через серверы вроде Mercury (XAMPP): письма больше не зависают в очереди с ошибкой «354»
• Письма поручений начинаются с того же приветствия, что и ваши письма
• В приветствии — имя и отчество при любом порядке слов в ФИО
• Полное имя человека в карточке и у получателей — сразу
</ru-RU>
<en-US>
• Sending through servers like Mercury (XAMPP): messages no longer get stuck in the outbox with a “354” error
• Assignment emails start with the same greeting as your messages
• Greetings use the first name whatever the order of the name
• A person’s full name appears right away on their card and among recipients
</en-US>
<de-DE>
• Versand über Server wie Mercury (XAMPP): E-Mails bleiben nicht mehr mit Fehler „354“ im Postausgang hängen
• Auftrags-E-Mails beginnen mit derselben Anrede wie Ihre E-Mails
• Die Anrede nutzt den Vornamen – egal in welcher Reihenfolge der Name steht
• Der volle Name erscheint sofort auf der Kontaktkarte und bei den Empfängern
</de-DE>
<fr-FR>
• Envoi via des serveurs comme Mercury (XAMPP) : les e-mails ne restent plus bloqués avec l’erreur « 354 »
• Les e-mails de mission commencent par la même formule d’appel que vos e-mails
• La formule d’appel utilise le prénom, quel que soit l’ordre du nom
• Le nom complet s’affiche tout de suite sur la fiche et parmi les destinataires
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков; самый длинный — 336).

```
<ru-RU>
• Отправка через серверы вроде Mercury (XAMPP): письма больше не зависают в очереди с ошибкой «354»
• Письма поручений начинаются с того же приветствия, что и ваши письма
• В приветствии — имя и отчество при любом порядке слов в ФИО
• Полное имя человека в карточке и у получателей — сразу
</ru-RU>
<en-US>
• Sending through servers like Mercury (XAMPP): messages no longer get stuck in the outbox with a “354” error
• Assignment emails start with the same greeting as your messages
• Greetings use the first name whatever the order of the name
• A person’s full name appears right away on their card and among recipients
</en-US>
<de-DE>
• Versand über Server wie Mercury (XAMPP): E-Mails bleiben nicht mehr mit Fehler „354“ im Postausgang hängen
• Auftrags-E-Mails beginnen mit derselben Anrede wie Ihre E-Mails
• Die Anrede nutzt den Vornamen – egal in welcher Reihenfolge der Name steht
• Der volle Name erscheint sofort auf der Kontaktkarte und bei den Empfängern
</de-DE>
<fr-FR>
• Envoi via des serveurs comme Mercury (XAMPP) : les e-mails ne restent plus bloqués avec l’erreur « 354 »
• Les e-mails de mission commencent par la même formule d’appel que vos e-mails
• La formule d’appel utilise le prénom, quel que soit l’ordre du nom
• Le nom complet s’affiche tout de suite sur la fiche et parmi les destinataires
</fr-FR>
<ar>
• الإرسال عبر خوادم مثل Mercury (XAMPP): لم تعد الرسائل تعلق في صندوق الصادر مع الخطأ «354»
• تبدأ رسائل التكليفات بالتحية نفسها التي تبدأ بها رسائلك
• تستخدم التحية الاسم الأول أيًا كان ترتيب الاسم
• يظهر الاسم الكامل فورًا في البطاقة وبين المستلمين
</ar>
<hu-HU>
• Küldés a Mercuryhoz (XAMPP) hasonló szervereken: a levelek már nem ragadnak a kimenőben „354” hibával
• A megbízásokról szóló levelek ugyanazzal a megszólítással kezdődnek, mint a leveleid
• A megszólítás a keresztnevet használja, bármilyen sorrendben áll a név
• A teljes név azonnal megjelenik a névjegyen és a címzetteknél
</hu-HU>
<vi>
• Gửi qua máy chủ như Mercury (XAMPP): thư không còn kẹt trong hộp thư đi với lỗi «354»
• Thư việc giao mở đầu bằng cùng lời chào như thư của bạn
• Lời chào dùng tên gọi, dù họ tên được viết theo thứ tự nào
• Họ tên đầy đủ hiện ngay trên thẻ và trong danh sách người nhận
</vi>
<da-DK>
• Afsendelse via servere som Mercury (XAMPP): mails sidder ikke længere fast i udbakken med fejlen "354"
• Mails om tildelte opgaver starter med samme hilsen som dine mails
• Hilsenen bruger fornavnet, uanset rækkefølgen i navnet
• Det fulde navn vises med det samme på kortet og blandt modtagerne
</da-DK>
<iw-IL>
• שליחה דרך שרתים כמו Mercury (XAMPP): הודעות כבר לא נתקעות בדואר היוצא עם השגיאה "354"
• הודעות על מטלות נפתחות באותה ברכה כמו ההודעות שלך
• הברכה משתמשת בשם הפרטי, בכל סדר של השם
• השם המלא מופיע מיד בכרטיס ובין הנמענים
</iw-IL>
<id>
• Kirim lewat server seperti Mercury (XAMPP): email tidak lagi tertahan di kotak keluar dengan galat «354»
• Email penugasan dibuka dengan salam yang sama seperti email Anda
• Salam memakai nama depan, apa pun urutan namanya
• Nama lengkap langsung tampil di kartu dan daftar penerima
</id>
<es-ES>
• Envío por servidores como Mercury (XAMPP): los correos ya no se quedan en la bandeja de salida con el error «354»
• Los correos de encargos empiezan con el mismo saludo que tus correos
• El saludo usa el nombre de pila, sea cual sea el orden del nombre
• El nombre completo aparece al momento en la ficha y en los destinatarios
</es-ES>
<it-IT>
• Invio tramite server come Mercury (XAMPP): le email non restano più bloccate con l’errore «354»
• Le email degli incarichi iniziano con lo stesso saluto delle tue email
• Il saluto usa il nome di battesimo, in qualunque ordine sia scritto il nome
• Il nome completo appare subito nella scheda e tra i destinatari
</it-IT>
<zh-CN>
• 通过 Mercury（XAMPP）等服务器发送：邮件不再因“354”错误卡在发件箱
• 任务分派邮件使用与普通邮件相同的问候语
• 无论姓名顺序如何，都能正确识别称呼
• 联系人卡片和收件人中立即显示全名
</zh-CN>
<ko-KR>
• Mercury(XAMPP) 같은 서버로 발송: 메일이 더 이상 '354' 오류로 보낼 편지함에 남지 않음
• 업무 지시 메일도 일반 메일과 같은 인사말로 시작
• 이름 순서와 관계없이 호칭을 올바르게 판별
• 연락처 카드와 받는 사람에 전체 이름을 바로 표시
</ko-KR>
<nl-NL>
• Verzenden via servers zoals Mercury (XAMPP): e-mails blijven niet meer hangen met fout ‘354’
• E-mails over opdrachten beginnen met dezelfde aanhef als je e-mails
• De aanhef gebruikt de voornaam, in welke volgorde de naam ook staat
• De volledige naam verschijnt meteen op de kaart en bij de ontvangers
</nl-NL>
<no-NO>
• Sending via servere som Mercury (XAMPP): e-poster blir ikke lenger stående i utboksen med feilen «354»
• E-poster om oppdrag starter med samme hilsen som e-postene dine
• Hilsenen bruker fornavnet, uansett rekkefølge i navnet
• Hele navnet vises med en gang på kortet og blant mottakerne
</no-NO>
<pl-PL>
• Wysyłka przez serwery takie jak Mercury (XAMPP): wiadomości nie utykają już w skrzynce nadawczej z błędem „354”
• Wiadomości o zleceniach zaczynają się tym samym powitaniem co Twoje wiadomości
• Powitanie używa imienia bez względu na kolejność w nazwisku
• Pełne imię i nazwisko od razu na karcie osoby i wśród odbiorców
</pl-PL>
<pt-BR>
• Envio por servidores como Mercury (XAMPP): os e-mails não ficam mais presos na caixa de saída com o erro "354"
• Os e-mails de atribuições começam com a mesma saudação dos seus e-mails
• A saudação usa o primeiro nome, em qualquer ordem do nome
• O nome completo aparece na hora no cartão e entre os destinatários
</pt-BR>
<ro>
• Trimitere prin servere precum Mercury (XAMPP): e-mailurile nu mai rămân blocate cu eroarea „354”
• E-mailurile despre sarcini încep cu același salut ca e-mailurile tale
• Salutul folosește prenumele, oricare ar fi ordinea numelui
• Numele complet apare imediat pe fișă și la destinatari
</ro>
<sk>
• Odosielanie cez servery ako Mercury (XAMPP): e-maily už neuviaznu vo fronte s chybou „354“
• E-maily k zadaným úlohám začínajú rovnakým oslovením ako vaše e-maily
• Oslovenie používa krstné meno bez ohľadu na poradie mena
• Celé meno sa hneď zobrazí na karte a pri príjemcoch
</sk>
<th>
• ส่งผ่านเซิร์ฟเวอร์อย่าง Mercury (XAMPP): อีเมลไม่ค้างในกล่องขาออกพร้อมข้อผิดพลาด «354» อีกต่อไป
• อีเมลงานมอบหมายขึ้นต้นด้วยคำทักทายเดียวกับอีเมลของคุณ
• คำทักทายใช้ชื่อต้น ไม่ว่าชื่อจะเรียงลำดับแบบใด
• ชื่อเต็มแสดงทันทีในการ์ดและในรายชื่อผู้รับ
</th>
<tr-TR>
• Mercury (XAMPP) gibi sunucularla gönderim: e-postalar artık «354» hatasıyla giden kutusunda takılmıyor
• Görevlendirme e-postaları, e-postalarınızla aynı selamlamayla başlıyor
• Selamlama, ad hangi sırayla yazılmış olursa olsun ilk adı kullanır
• Kişinin tam adı kartında ve alıcılarda hemen görünür
</tr-TR>
<fi-FI>
• Lähetys Mercuryn (XAMPP) kaltaisten palvelimien kautta: viestit eivät enää jää lähtevien jonoon virheellä ”354”
• Toimeksiantoviestit alkavat samalla tervehdyksellä kuin muut viestisi
• Tervehdyksessä on etunimi, oli nimi missä järjestyksessä tahansa
• Koko nimi näkyy heti kortissa ja vastaanottajissa
</fi-FI>
<hi-IN>
• Mercury (XAMPP) जैसे सर्वर से भेजना: ईमेल अब «354» त्रुटि के साथ आउटबॉक्स में नहीं अटकते
• सौंपे गए कार्यों के ईमेल उसी अभिवादन से शुरू होते हैं जैसे आपके ईमेल
• अभिवादन में पहला नाम आता है, नाम का क्रम कुछ भी हो
• व्यक्ति का पूरा नाम कार्ड और प्राप्तकर्ताओं में तुरंत दिखता है
</hi-IN>
<cs-CZ>
• Odesílání přes servery jako Mercury (XAMPP): e-maily už neuvíznou ve frontě s chybou „354“
• E-maily k zadaným úkolům začínají stejným oslovením jako vaše e-maily
• Oslovení používá křestní jméno bez ohledu na pořadí jména
• Celé jméno se hned zobrazí na kartě a u příjemců
</cs-CZ>
<sv-SE>
• Skicka via servrar som Mercury (XAMPP): mejl fastnar inte längre i utkorgen med felet ”354”
• Mejl om uppdrag börjar med samma hälsning som dina mejl
• Hälsningen använder förnamnet oavsett namnordning
• Hela namnet visas direkt på kortet och bland mottagarna
</sv-SE>
<ja-JP>
• Mercury（XAMPP）などのサーバー経由の送信：「354」エラーで送信トレイに残らなくなりました
• 依頼メールの冒頭も通常のメールと同じあいさつに
• 名前の順序に関係なく、宛名を正しく判別
• 連絡先カードと宛先にフルネームをすぐ表示
</ja-JP>
```
