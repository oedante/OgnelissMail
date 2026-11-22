# «Что нового» — 2.6.9 (170), относительно 2.6.8 (169)

Просьба владельца 22.11.2026: «подними версию». Шаги владельца —
`OWNER_STEPS_2.6.9.md`. В 2.6.9 — всё, что сделано после архива 2.6.8
(коммит ade5443).

## Сделано в 2.6.9

- **Черновик — на сервере, пока письмо пишется** (IMAP и Exchange): не на
  каждое нажатие, а не чаще раза в 30 секунд, пока письмо меняется; сразу —
  по «Сохранить» и при сворачивании приложения. Новая версия заменяет
  прежнюю — в «Черновиках» один черновик; при закрытии письма та же версия
  второй раз не уходит. Раньше черновик уходил на сервер только при
  закрытии письма. Файлы больше 2 МБ — при сворачивании и закрытии.
- **Черновик ответа — с заголовками ответа** (In-Reply-To, References; IMAP
  и EWS): веб-почта, которая собирает беседы по заголовкам (Gmail), ставит
  его в беседу исходного письма, а ответ, отправленный из черновика на
  другом устройстве или в другой программе, встаёт в ту же переписку у
  получателя. Ogneliss на другом устройстве находит исходное письмо по этим
  заголовкам и после отправки отмечает его «Отвечено». ActiveSync таких
  полей у черновика не принимает.
- **Черновики с сервера** (папка «Черновики» Gmail и других ящиков IMAP) в
  беседе и на экране письма — черновики: нажатие открывает редактор, внизу
  «Редактировать», а не «Ответить» и «Переслать».
- **«Исходящие» — своя папка ящика.** У ящика своя папка «Исходящие» на
  сервере (Exchange, часть IMAP) — в меню она и есть «Исходящие» Ogneliss,
  на своём месте в списке, без второй строки; письма, которые лежат в ней
  на сервере, открываются строкой внизу. Exchange называет эту папку сам,
  у IMAP она узнаётся по названию на разных языках («Outbox», «Исходящие»,
  «Postausgang», «Boîte d'envoi», «Bandeja de salida», «送信トレイ» и др.;
  только папка верхнего уровня). Больше языков и у «Черновиков»,
  «Отправленных» и «Корзины».
- **Смена ящика, когда открыта папка**: открывается такая же папка нового
  ящика («Отправленные» → «Отправленные», своя — с тем же названием), а нет
  такой — «Входящие» или «Вся почта», как в «Открывать при запуске».
  Раньше оставалась папка прежнего ящика: заголовок «Входящие» и пустая
  лента.
- **Ответ и пересылка**: поле текста — по высоте текста (не выше половины
  экрана, дальше прокрутка внутри), свёрнутое «Исходное письмо» — сразу под
  подписью, а не внизу экрана под пустым полем.
- **Виджет календаря**: под месяцем вместо подписи «Календарь» — погода,
  как в виджете «Мой день» (если погода включена).
- **Календарь**: в «Расписании» у задачи на завтра — «Срок», а не «Срок
  сегодня».
- Черновик ответа не считается ответом в «должен ответить», списке
  ответивших и разборе поручений.

## Кратко (RU / EN)

**RU.** Черновик попадает на сервер уже во время набора — не чаще раза в
полминуты — и встаёт в ту же переписку; черновики с сервера открываются для
правки. У ящиков со своей папкой «Исходящие» используется она, названия
системных папок узнаются на многих языках. Смена ящика открывает ту же
папку, при ответе исходное письмо стоит сразу под подписью, виджет
календаря показывает погоду.

**EN.** Drafts reach the server while you are still typing — at most every
half minute — and stay in the same thread; drafts from the server open for
editing. Mailboxes with their own Outbox folder use it, and system folder
names are recognised in many languages. Switching mailboxes keeps the same
folder, the original message sits right below your signature when you
reply, and the calendar widget shows the weather.

## Google Play — короткий текст (27 языков)

Самый длинный — 367 знаков (предел — 500).

```
<ru-RU>
• Черновики — на сервере уже во время набора, в той же переписке
• Черновики с сервера — с кнопкой «Редактировать»
• Своя папка «Исходящие» ящика — без второй
• Смена ящика открывает ту же папку
• Ответ: исходное письмо сразу под подписью
• Виджет календаря — с погодой
• Исправления и улучшения
</ru-RU>
<en-US>
• Drafts are saved to the server as you type, in the same thread
• Drafts from the server open with an “Edit” button
• The mailbox’s own Outbox folder is used — no duplicate
• Switching mailboxes keeps the same folder open
• Reply: the original message sits right below your signature
• Calendar widget shows the weather
• Bug fixes and improvements
</en-US>
<de-DE>
• Entwürfe schon beim Schreiben auf dem Server, im selben Verlauf
• Entwürfe vom Server mit der Schaltfläche „Bearbeiten“
• Der eigene Postausgang des Postfachs wird verwendet – kein zweiter
• Beim Postfachwechsel bleibt derselbe Ordner geöffnet
• Antwort: Originalnachricht direkt unter der Signatur
• Kalender-Widget mit Wetter
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Brouillons enregistrés sur le serveur pendant la saisie, dans le même fil
• Brouillons du serveur avec le bouton « Modifier »
• La boîte d’envoi propre au compte est utilisée, sans doublon
• Changer de compte garde le même dossier ouvert
• Réponse : le message d’origine juste sous la signature
• Widget Agenda avec la météo
• Corrections et améliorations
</fr-FR>
<ar>
• تُحفظ المسودات على الخادم أثناء الكتابة، في نفس المحادثة
• مسودات الخادم تُفتح بزر «تعديل»
• يُستخدم مجلد «صندوق الصادر» الخاص بالحساب دون تكرار
• تبديل الحساب يُبقي المجلد نفسه مفتوحًا
• الرد: الرسالة الأصلية مباشرة أسفل التوقيع
• أداة التقويم تعرض الطقس
• إصلاحات وتحسينات
</ar>
<hu-HU>
• A piszkozatok már írás közben a szerveren, ugyanabban a szálban
• A szerveren lévő piszkozatok „Szerkesztés” gombbal nyílnak
• A fiók saját Postázandó mappáját használja – nincs második
• Fiókváltáskor ugyanaz a mappa marad nyitva
• Válasz: az eredeti levél közvetlenül az aláírás alatt
• Naptár widget időjárással
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Thư nháp được lưu lên máy chủ khi đang soạn, trong cùng chuỗi thư
• Thư nháp trên máy chủ mở với nút “Chỉnh sửa”
• Dùng thư mục Hộp thư đi sẵn có của tài khoản, không tạo thêm
• Đổi tài khoản vẫn giữ nguyên thư mục đang mở
• Trả lời: thư gốc nằm ngay dưới chữ ký
• Tiện ích lịch hiển thị thời tiết
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Kladder gemmes på serveren, mens du skriver, i samme tråd
• Kladder fra serveren åbnes med knappen “Rediger”
• Kontoens egen Udbakke bruges – ingen ekstra
• Skift af konto beholder samme mappe
• Svar: den oprindelige mail lige under signaturen
• Kalenderwidget med vejret
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• טיוטות נשמרות בשרת כבר בזמן הכתיבה, באותו שרשור
• טיוטות מהשרת נפתחות עם הלחצן „עריכה”
• נעשה שימוש בתיבת הדואר היוצא של החשבון – ללא כפילות
• החלפת חשבון שומרת על אותה תיקייה פתוחה
• תשובה: ההודעה המקורית ממש מתחת לחתימה
• וידג׳ט היומן מציג את מזג האוויר
• תיקוני באגים ושיפורים
</iw-IL>
<id>
• Draf tersimpan di server saat mengetik, dalam utas yang sama
• Draf dari server terbuka dengan tombol “Edit”
• Folder Kotak Keluar milik akun dipakai, tanpa duplikat
• Ganti akun tetap membuka folder yang sama
• Balasan: pesan asli tepat di bawah tanda tangan
• Widget kalender menampilkan cuaca
• Perbaikan bug dan peningkatan
</id>
<es-ES>
• Borradores guardados en el servidor mientras escribe, en el mismo hilo
• Borradores del servidor con el botón «Editar»
• Se usa la bandeja de salida propia de la cuenta, sin duplicados
• Al cambiar de cuenta se mantiene la misma carpeta
• Respuesta: el mensaje original justo bajo la firma
• Widget de calendario con el tiempo
• Correcciones y mejoras
</es-ES>
<it-IT>
• Bozze salvate sul server durante la scrittura, nella stessa conversazione
• Bozze dal server con il pulsante «Modifica»
• Viene usata la Posta in uscita dell’account, senza doppioni
• Cambiando account resta aperta la stessa cartella
• Risposta: messaggio originale subito sotto la firma
• Widget Calendario con il meteo
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 草稿在输入时即保存到服务器，并归入同一会话
• 服务器上的草稿可通过“编辑”打开
• 使用账户自带的发件箱，不再重复
• 切换账户时保持同一文件夹
• 回复：原始邮件紧接在签名下方
• 日历小组件显示天气
• 错误修复和改进
</zh-CN>
<ko-KR>
• 작성 중에도 임시 저장 메일이 서버에 저장되고 같은 대화에 연결
• 서버의 임시 저장 메일을 “편집” 버튼으로 열기
• 계정 자체의 보낼 편지함 사용, 중복 없음
• 계정을 바꿔도 같은 폴더 유지
• 답장: 원본 메일이 서명 바로 아래에
• 캘린더 위젯에 날씨 표시
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Concepten al tijdens het typen op de server, in hetzelfde gesprek
• Concepten van de server openen met de knop ‘Bewerken’
• De eigen Postvak UIT van het account wordt gebruikt, geen tweede
• Bij wisselen van account blijft dezelfde map open
• Antwoord: origineel bericht direct onder de handtekening
• Agendawidget met het weer
• Bugfixes en verbeteringen
</nl-NL>
<no-NO>
• Utkast lagres på serveren mens du skriver, i samme tråd
• Utkast fra serveren åpnes med knappen «Rediger»
• Kontoens egen Utboks brukes – ingen ekstra
• Bytte av konto beholder samme mappe
• Svar: den opprinnelige e-posten rett under signaturen
• Kalenderwidget med været
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Wersje robocze zapisywane na serwerze już podczas pisania, w tym samym wątku
• Wersje robocze z serwera z przyciskiem „Edytuj”
• Używana jest własna Skrzynka nadawcza konta – bez drugiej
• Zmiana konta zostawia ten sam folder
• Odpowiedź: oryginalna wiadomość tuż pod podpisem
• Widżet kalendarza z pogodą
• Poprawki błędów i ulepszenia
</pl-PL>
<pt-BR>
• Rascunhos salvos no servidor enquanto você digita, na mesma conversa
• Rascunhos do servidor abrem com o botão “Editar”
• A Caixa de saída da própria conta é usada, sem duplicar
• Trocar de conta mantém a mesma pasta aberta
• Resposta: mensagem original logo abaixo da assinatura
• Widget de calendário com o clima
• Correções e melhorias
</pt-BR>
<ro>
• Ciornele se salvează pe server în timp ce scrieți, în aceeași conversație
• Ciornele de pe server se deschid cu butonul „Editați”
• Se folosește dosarul Ieșiri al contului, fără dublură
• La schimbarea contului rămâne deschis același dosar
• Răspuns: mesajul original imediat sub semnătură
• Widgetul calendar afișează vremea
• Remedieri și îmbunătățiri
</ro>
<sk>
• Koncepty sa ukladajú na server už počas písania, v tom istom vlákne
• Koncepty zo servera sa otvárajú tlačidlom „Upraviť“
• Používa sa vlastný priečinok Pošta na odoslanie – bez druhého
• Pri zmene účtu zostane otvorený ten istý priečinok
• Odpoveď: pôvodná správa hneď pod podpisom
• Miniaplikácia kalendára s počasím
• Opravy chýb a vylepšenia
</sk>
<th>
• บันทึกฉบับร่างลงเซิร์ฟเวอร์ระหว่างพิมพ์ ในเธรดเดียวกัน
• ฉบับร่างจากเซิร์ฟเวอร์เปิดด้วยปุ่ม “แก้ไข”
• ใช้กล่องจดหมายออกของบัญชีเอง ไม่ซ้ำซ้อน
• สลับบัญชีแล้วยังอยู่ในโฟลเดอร์เดิม
• ตอบกลับ: ข้อความต้นฉบับอยู่ใต้ลายเซ็นทันที
• วิดเจ็ตปฏิทินแสดงสภาพอากาศ
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Taslaklar yazarken sunucuya kaydedilir, aynı yazışmada
• Sunucudaki taslaklar “Düzenle” düğmesiyle açılır
• Hesabın kendi Giden Kutusu kullanılır, ikincisi yok
• Hesap değiştirince aynı klasör açık kalır
• Yanıt: orijinal ileti imzanın hemen altında
• Takvim widget’ında hava durumu
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Luonnokset tallentuvat palvelimelle jo kirjoittaessa, samaan ketjuun
• Palvelimen luonnokset avautuvat Muokkaa-painikkeella
• Tilin omaa Lähtevät-kansiota käytetään – ei toista
• Tilin vaihto pitää saman kansion auki
• Vastaus: alkuperäinen viesti heti allekirjoituksen alla
• Kalenteriwidgetissä sää
• Virheenkorjauksia ja parannuksia
</fi-FI>
<hi-IN>
• ड्राफ़्ट लिखते समय ही सर्वर पर सहेजे जाते हैं, उसी थ्रेड में
• सर्वर के ड्राफ़्ट “संपादित करें” बटन के साथ खुलते हैं
• खाते का अपना आउटबॉक्स फ़ोल्डर इस्तेमाल होता है, दूसरा नहीं
• खाता बदलने पर वही फ़ोल्डर खुला रहता है
• जवाब: मूल ईमेल हस्ताक्षर के ठीक नीचे
• कैलेंडर विजेट में मौसम
• बग फ़िक्स और सुधार
</hi-IN>
<cs-CZ>
• Koncepty se ukládají na server už při psaní, ve stejném vlákně
• Koncepty ze serveru se otevírají tlačítkem „Upravit“
• Používá se vlastní složka Pošta k odeslání – bez druhé
• Při změně účtu zůstane otevřená stejná složka
• Odpověď: původní zpráva hned pod podpisem
• Widget kalendáře s počasím
• Opravy chyb a vylepšení
</cs-CZ>
<sv-SE>
• Utkast sparas på servern medan du skriver, i samma tråd
• Utkast från servern öppnas med knappen ”Redigera”
• Kontots egen Utkorg används – ingen extra
• Byte av konto behåller samma mapp
• Svar: originalmeddelandet direkt under signaturen
• Kalenderwidget med vädret
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• 下書きを入力中にサーバーへ保存、同じスレッドにまとめて表示
• サーバーの下書きは「編集」ボタンで開く
• アカウント自身の送信トレイを使用、重複なし
• アカウントを切り替えても同じフォルダーのまま
• 返信：元のメールを署名のすぐ下に表示
• カレンダーウィジェットに天気を表示
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Без строки о виджете календаря: он есть только на Android.

```
<ru-RU>
• Черновики — на сервере уже во время набора, в той же переписке
• Черновики с сервера — с кнопкой «Редактировать»
• Своя папка «Исходящие» ящика — без второй
• Смена ящика открывает ту же папку
• Ответ: исходное письмо сразу под подписью
• Исправления и улучшения
</ru-RU>
<en-US>
• Drafts are saved to the server as you type, in the same thread
• Drafts from the server open with an “Edit” button
• The mailbox’s own Outbox folder is used — no duplicate
• Switching mailboxes keeps the same folder open
• Reply: the original message sits right below your signature
• Bug fixes and improvements
</en-US>
<de-DE>
• Entwürfe schon beim Schreiben auf dem Server, im selben Verlauf
• Entwürfe vom Server mit der Schaltfläche „Bearbeiten“
• Der eigene Postausgang des Postfachs wird verwendet – kein zweiter
• Beim Postfachwechsel bleibt derselbe Ordner geöffnet
• Antwort: Originalnachricht direkt unter der Signatur
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Brouillons enregistrés sur le serveur pendant la saisie, dans le même fil
• Brouillons du serveur avec le bouton « Modifier »
• La boîte d’envoi propre au compte est utilisée, sans doublon
• Changer de compte garde le même dossier ouvert
• Réponse : le message d’origine juste sous la signature
• Corrections et améliorations
</fr-FR>
```
