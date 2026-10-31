# «Что нового» — 1.9.0 (130)

Замечания владельца 29–31.10.2026: письма с ящика Яндекса не уходили,
мелкий шрифт письма, рассылка Kaspersky прокручивалась в пустоту, картинки в
письме не увеличить и не сохранить, барабаны даты и времени, быстрые
ответы не в стиле приложения, странные подсказки «Вставить», избранные в
контактах, экран «О приложении», больше пяти ящиков в боковой панели.

Что изменилось (для разработчика):

- Отправка с ящика Яндекса (вход через Яндекс, OAuth): на `AUTH XOAUTH2`
  сервер отвечает голым «334», разбор в enough_mail падал (RangeError), вход
  висел до тайм-аута — письма не уходили. `TolerantSmtpClient` (приложение и
  mail_engine) дополняет код пробелом. Сбой подключения или входа SMTP —
  письмо точно не отправлено: очередь повторяет его, а не помечает «сервер
  мог принять».
- Размер текста письма: 15 px × шрифт приложения и системы ÷ масштаб
  интерфейса (было 14 px без системного шрифта) — одинаково в WebView,
  простом показе, простом тексте и архиве. Множитель системного шрифта — на
  15 px: на Android 14+ шрифт масштабируется нелинейно, и по 100 px письмо
  не увеличивалось вовсе.
- Окно письма (проверено в Chromium: масштаб интерфейса 0,85–1,1, ширина
  320–480 dp, плотность 2–3): «По ширине экрана», «Обычный размер» и щипок
  больше не оставляют пустое поле под письмом — высота уменьшается сразу
  (документ не бывает ниже окна, замер её не уменьшал), замеры при
  увеличении щипком на Android не удваивают высоту.
- Сложные письма: высоты в долях окна (`100vh`) — по содержимому (письмо
  росло после каждого замера); «прилипающие» блоки (`position: fixed` и
  `sticky`) — на своём месте в тексте; длинный адрес текстом ссылки
  переносится и не раздвигает колонку письма.
- Окно письма и редактор переживают падение процесса WebView (Android убивает
  его при нехватке памяти): письмо открывается в новом окне, редактор
  переходит в простое поле с набранным текстом. Раньше закрывалось всё
  приложение.
- Картинка в письме по нажатию — на весь экран (увеличение до ×6),
  «Копировать», «Сохранить», «Поделиться». Android: копия через FileProvider
  в буфер обмена; iPhone и iPad: UIPasteboard.
- Барабаны даты и времени: одна полоса выбора через все колонки, изгиб,
  крупная центральная строка, затухание к краям.
- Новое письмо на Android открывается быстрее: невидимое окно с уже
  запущенным редактором ждёт наготове (как окно письма). Подсказки «Вставить:»
  убраны вместе с обучением на отправленных; выученные фразы удаляются.
- Быстрые ответы — карточкой, как остальные выборы; «ответить всем» —
  переключатель в шапке.
- Письмо самому себе (копии в «Отправленных» и «Входящих») — одно письмо в
  беседе и в счётчике.
- Контакты: избранные (VIP) — среди закреплённых. «О приложении» — карточками,
  как настройки. Боковая панель: все ящики в прокручиваемом ряду (больше
  пяти уходили за край).
- Журнал: выбор интервала проверки почты больше не обращается к закрытому
  экрану; нажатие на уведомление пишется без темы и адреса.

Изменены файлы iOS (ios/Runner/AppDelegate.swift — копирование картинки) и
Android (FileOpenBridge.kt); project.pbxproj не менялся.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Яндекс: письма снова отправляются при входе через Яндекс
• Текст писем крупнее и следует размеру шрифта в системе
• Картинку из письма можно открыть на весь экран, скопировать и сохранить
• Новые барабаны выбора даты и времени
• Новое письмо открывается быстрее, подсказки «Вставить» убраны
• Быстрые ответы — карточкой, VIP — среди закреплённых контактов
• Длинные рассылки больше не прокручиваются в пустоту
</ru-RU>
<en-US>
• Yandex: sending works again when signed in with Yandex
• Larger message text that follows the system font size
• Open an image from a message full screen, copy or save it
• New date and time wheels
• Compose opens faster; "Insert" suggestions removed
• Quick replies as a card; VIP among pinned contacts
• Long newsletters no longer scroll into empty space
</en-US>
<de-DE>
• Yandex: Senden funktioniert wieder bei der Anmeldung mit Yandex
• Größerer Nachrichtentext, der der Systemschriftgröße folgt
• Bild aus einer E-Mail im Vollbild öffnen, kopieren oder speichern
• Neue Auswahlräder für Datum und Uhrzeit
• Verfassen öffnet schneller; Vorschläge für „Einfügen“ entfernt
• Schnellantworten als Karte; VIP unter den angehefteten Kontakten
• Lange Newsletter scrollen nicht mehr ins Leere
</de-DE>
<fr-FR>
• Yandex : l’envoi fonctionne de nouveau avec la connexion Yandex
• Texte des messages plus grand, selon la police du système
• Image d’un message : plein écran, copie et enregistrement
• Nouvelles molettes de date et d’heure
• Rédaction plus rapide ; suggestions « Insérer » supprimées
• Réponses rapides en carte ; VIP parmi les contacts épinglés
• Les longues newsletters ne défilent plus dans le vide
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Яндекс: письма снова отправляются при входе через Яндекс
• Текст писем крупнее и следует размеру шрифта в системе
• Картинку из письма можно открыть на весь экран, скопировать и сохранить
• Новые барабаны выбора даты и времени
• Новое письмо открывается быстрее, подсказки «Вставить» убраны
• Быстрые ответы — карточкой, VIP — среди закреплённых контактов
• Длинные рассылки больше не прокручиваются в пустоту
</ru-RU>
<en-US>
• Yandex: sending works again when signed in with Yandex
• Larger message text that follows the system font size
• Open an image from a message full screen, copy or save it
• New date and time wheels
• Compose opens faster; "Insert" suggestions removed
• Quick replies as a card; VIP among pinned contacts
• Long newsletters no longer scroll into empty space
</en-US>
<de-DE>
• Yandex: Senden funktioniert wieder bei der Anmeldung mit Yandex
• Größerer Nachrichtentext, der der Systemschriftgröße folgt
• Bild aus einer E-Mail im Vollbild öffnen, kopieren oder speichern
• Neue Auswahlräder für Datum und Uhrzeit
• Verfassen öffnet schneller; Vorschläge für „Einfügen“ entfernt
• Schnellantworten als Karte; VIP unter den angehefteten Kontakten
• Lange Newsletter scrollen nicht mehr ins Leere
</de-DE>
<fr-FR>
• Yandex : l’envoi fonctionne de nouveau avec la connexion Yandex
• Texte des messages plus grand, selon la police du système
• Image d’un message : plein écran, copie et enregistrement
• Nouvelles molettes de date et d’heure
• Rédaction plus rapide ; suggestions « Insérer » supprimées
• Réponses rapides en carte ; VIP parmi les contacts épinglés
• Les longues newsletters ne défilent plus dans le vide
</fr-FR>
<ar>
• Yandex: الإرسال يعمل من جديد عند تسجيل الدخول عبر Yandex
• نص الرسائل أكبر ويتبع حجم خط النظام
• يمكن فتح صورة من الرسالة بملء الشاشة ونسخها وحفظها
• عجلات جديدة لاختيار التاريخ والوقت
• كتابة رسالة جديدة تفتح أسرع، وأُزيلت اقتراحات «إدراج»
• الردود السريعة كبطاقة، وجهات VIP ضمن جهات الاتصال المثبّتة
• التمرير في النشرات البريدية الطويلة لم يعد ينتهي بفراغ
</ar>
<hu-HU>
• Yandex: a küldés ismét működik Yandex-bejelentkezéssel
• Nagyobb levélszöveg, amely követi a rendszer betűméretét
• A levélben lévő kép megnyitható teljes képernyőn, másolható és menthető
• Új dátum- és időválasztó görgők
• A levélírás gyorsabban nyílik, a „Beszúrás” javaslatok megszűntek
• Gyorsválaszok kártyán, a VIP-névjegyek a kitűzöttek között
• A hosszú hírleveleknél már nem lehet üres területre görgetni
</hu-HU>
<vi>
• Yandex: gửi thư hoạt động trở lại khi đăng nhập bằng Yandex
• Chữ trong thư lớn hơn và theo cỡ chữ hệ thống
• Mở ảnh trong thư toàn màn hình, sao chép hoặc lưu
• Bộ chọn ngày và giờ dạng cuộn mới
• Soạn thư mở nhanh hơn, đã bỏ gợi ý “Chèn”
• Trả lời nhanh dạng thẻ; VIP nằm trong liên hệ đã ghim
• Thư bản tin dài không còn cuộn ra khoảng trống
</vi>
<da-DK>
• Yandex: afsendelse virker igen ved login med Yandex
• Større mailtekst, der følger systemets skriftstørrelse
• Billeder i mails kan åbnes i fuld skærm, kopieres og gemmes
• Nye hjul til dato og klokkeslæt
• Skriv mail åbner hurtigere; forslag til “Indsæt” er fjernet
• Hurtige svar som kort; VIP blandt fastgjorte kontakter
• Lange nyhedsbreve ruller ikke længere ud i tomhed
</da-DK>
<iw-IL>
• Yandex: השליחה שוב פועלת בכניסה דרך Yandex
• טקסט ההודעות גדול יותר ועוקב אחר גודל הגופן של המערכת
• אפשר לפתוח תמונה מהודעה במסך מלא, להעתיק ולשמור
• גלגלי תאריך ושעה חדשים
• כתיבת הודעה נפתחת מהר יותר, הצעות “הוספה” הוסרו
• תשובות מהירות בכרטיס, ו VIP בין אנשי הקשר הנעוצים
• ניוזלטרים ארוכים כבר לא גוללים לשטח ריק
</iw-IL>
<id>
• Yandex: pengiriman kembali berfungsi saat masuk dengan Yandex
• Teks email lebih besar dan mengikuti ukuran font sistem
• Gambar di email bisa dibuka layar penuh, disalin, dan disimpan
• Roda pemilih tanggal dan waktu baru
• Tulis email terbuka lebih cepat; saran “Sisipkan” dihapus
• Balasan cepat berupa kartu; VIP di antara kontak yang disematkan
• Buletin panjang tidak lagi bergulir ke ruang kosong
</id>
<es-ES>
• Yandex: el envío vuelve a funcionar al iniciar sesión con Yandex
• Texto de los mensajes más grande, según el tamaño de fuente del sistema
• Abre una imagen de un mensaje a pantalla completa, cópiala o guárdala
• Nuevas ruedas de fecha y hora
• Redactar se abre más rápido; sin sugerencias de «Insertar»
• Respuestas rápidas en tarjeta; VIP entre los contactos fijados
• Los boletines largos ya no se desplazan hacia el vacío
</es-ES>
<it-IT>
• Yandex: l’invio torna a funzionare accedendo con Yandex
• Testo dei messaggi più grande, segue la dimensione del carattere di sistema
• Apri a schermo intero un’immagine di un messaggio, copiala o salvala
• Nuove ruote per data e ora
• Scrittura si apre più velocemente; rimossi i suggerimenti «Inserisci»
• Risposte rapide in una scheda; VIP tra i contatti fissati
• Le newsletter lunghe non scorrono più nel vuoto
</it-IT>
<zh-CN>
• Yandex：使用 Yandex 登录时可再次正常发送邮件
• 邮件文字更大，并跟随系统字体大小
• 邮件中的图片可全屏打开、复制和保存
• 全新的日期和时间滚轮
• 写邮件打开更快，已移除“插入”建议
• 快捷回复以卡片显示，VIP 位于置顶联系人中
• 较长的订阅邮件不再滚动出空白区域
</zh-CN>
<ko-KR>
• Yandex: Yandex로 로그인했을 때 다시 메일 전송 가능
• 메일 글자가 더 커지고 시스템 글꼴 크기를 따름
• 메일 속 이미지를 전체 화면으로 열고 복사 및 저장 가능
• 새로운 날짜 및 시간 휠
• 메일 작성이 더 빨리 열리고 “삽입” 제안 삭제
• 빠른 답장은 카드로, VIP는 고정된 연락처에 포함
• 긴 뉴스레터가 더 이상 빈 공간으로 스크롤되지 않음
</ko-KR>
<nl-NL>
• Yandex: verzenden werkt weer bij inloggen met Yandex
• Grotere berichttekst die de systeemlettergrootte volgt
• Afbeelding uit een bericht op volledig scherm openen, kopiëren of bewaren
• Nieuwe keuzewielen voor datum en tijd
• Opstellen opent sneller; “Invoegen”-suggesties verwijderd
• Snelle antwoorden als kaart; VIP bij de vastgezette contacten
• Lange nieuwsbrieven scrollen niet meer de leegte in
</nl-NL>
<no-NO>
• Yandex: sending fungerer igjen ved pålogging med Yandex
• Større e-posttekst som følger systemets skriftstørrelse
• Bilde i en e-post kan åpnes i fullskjerm, kopieres og lagres
• Nye hjul for dato og klokkeslett
• Skriv e-post åpnes raskere; «Sett inn»-forslag er fjernet
• Hurtigsvar som kort; VIP blant festede kontakter
• Lange nyhetsbrev ruller ikke lenger ut i tomrommet
</no-NO>
<pl-PL>
• Yandex: wysyłanie znów działa po zalogowaniu przez Yandex
• Większy tekst wiadomości, zgodny z rozmiarem czcionki systemu
• Obraz z wiadomości można otworzyć na pełnym ekranie, skopiować i zapisać
• Nowe bębny wyboru daty i godziny
• Nowa wiadomość otwiera się szybciej, podpowiedzi „Wstaw” usunięto
• Szybkie odpowiedzi jako karta; VIP wśród przypiętych kontaktów
• Długie newslettery nie przewijają się już w pustkę
</pl-PL>
<pt-BR>
• Yandex: o envio volta a funcionar ao entrar com o Yandex
• Texto dos e-mails maior, seguindo o tamanho da fonte do sistema
• Abra uma imagem do e-mail em tela cheia, copie ou salve
• Novas rodas de data e hora
• Escrever abre mais rápido; sugestões de “Inserir” removidas
• Respostas rápidas em cartão; VIP entre os contatos fixados
• Newsletters longas não rolam mais para o vazio
</pt-BR>
<ro>
• Yandex: trimiterea funcționează din nou la autentificarea cu Yandex
• Textul mesajelor este mai mare și urmează dimensiunea fontului din sistem
• O imagine dintr-un mesaj se deschide pe tot ecranul, se copiază și se salvează
• Roți noi pentru data și ora
• Scrierea se deschide mai repede; sugestiile „Inserare” au fost eliminate
• Răspunsuri rapide ca card; VIP printre contactele fixate
• Newsletterele lungi nu mai derulează în gol
</ro>
<sk>
• Yandex: odosielanie opäť funguje pri prihlásení cez Yandex
• Väčší text správ, ktorý sleduje veľkosť písma systému
• Obrázok zo správy otvoríte na celú obrazovku, skopírujete a uložíte
• Nové kolieska na výber dátumu a času
• Písanie sa otvára rýchlejšie, návrhy „Vložiť“ sú preč
• Rýchle odpovede ako karta, VIP medzi pripnutými kontaktmi
• Dlhé newslettery sa už neposúvajú do prázdna
</sk>
<th>
• Yandex: ส่งอีเมลได้อีกครั้งเมื่อเข้าสู่ระบบด้วย Yandex
• ข้อความอีเมลใหญ่ขึ้นและตามขนาดตัวอักษรของระบบ
• เปิดรูปภาพในอีเมลแบบเต็มหน้าจอ คัดลอก และบันทึกได้
• ตัวเลือกวันที่และเวลาแบบล้อใหม่
• เขียนอีเมลเปิดเร็วขึ้น ลบคำแนะนำ “แทรก” แล้ว
• ตอบกลับด่วนเป็นการ์ด VIP อยู่ในรายชื่อติดต่อที่ปักหมุด
• จดหมายข่าวฉบับยาวไม่เลื่อนไปสู่พื้นที่ว่างอีก
</th>
<tr-TR>
• Yandex: Yandex ile girişte gönderim yine çalışıyor
• Daha büyük ileti metni, sistem yazı tipi boyutunu izler
• İletideki görsel tam ekran açılabilir, kopyalanabilir ve kaydedilebilir
• Yeni tarih ve saat çarkları
• İleti yazma daha hızlı açılıyor, “Ekle” önerileri kaldırıldı
• Hızlı yanıtlar kart olarak, VIP sabitlenmiş kişiler arasında
• Uzun bültenler artık boşluğa kaydırılmıyor
</tr-TR>
<fi-FI>
• Yandex: lähetys toimii taas Yandex-kirjautumisella
• Suurempi viestin teksti, joka seuraa järjestelmän kirjasinkokoa
• Viestin kuvan voi avata koko näytölle, kopioida ja tallentaa
• Uudet päivämäärän ja kellonajan valintarullat
• Kirjoitus aukeaa nopeammin, “Lisää”-ehdotukset poistettu
• Pikavastaukset korttina, VIP kiinnitettyjen yhteystietojen joukossa
• Pitkät uutiskirjeet eivät enää vieri tyhjyyteen
</fi-FI>
<hi-IN>
• Yandex: Yandex से साइन इन करने पर भेजना फिर से काम करता है
• ईमेल का टेक्स्ट बड़ा और सिस्टम के फ़ॉन्ट आकार के अनुसार
• ईमेल की तस्वीर पूरी स्क्रीन पर खोलें, कॉपी करें और सेव करें
• तारीख़ और समय के नए व्हील
• ईमेल लिखना अब तेज़ खुलता है, “डालें” सुझाव हटाए गए
• त्वरित जवाब कार्ड में, VIP पिन किए संपर्कों में
• लंबे न्यूज़लेटर अब खाली जगह में स्क्रोल नहीं होते
</hi-IN>
<cs-CZ>
• Yandex: odesílání opět funguje při přihlášení přes Yandex
• Větší text zpráv, který se řídí velikostí písma systému
• Obrázek ze zprávy otevřete na celou obrazovku, zkopírujete a uložíte
• Nová kolečka pro výběr data a času
• Psaní se otevírá rychleji, návrhy „Vložit“ jsou pryč
• Rychlé odpovědi jako karta, VIP mezi připnutými kontakty
• Dlouhé newslettery se už neposouvají do prázdna
</cs-CZ>
<sv-SE>
• Yandex: sändning fungerar igen vid inloggning med Yandex
• Större brödtext i mejl som följer systemets teckenstorlek
• Bilden i ett mejl kan öppnas i helskärm, kopieras och sparas
• Nya hjul för datum och tid
• Skriva öppnas snabbare; förslagen ”Infoga” har tagits bort
• Snabbsvar som kort; VIP bland fästa kontakter
• Långa nyhetsbrev scrollar inte längre ut i tomma intet
</sv-SE>
<ja-JP>
• Yandex：Yandex でサインインしたときにメールを再び送信できるように
• メール本文の文字が大きくなり、システムのフォントサイズに連動
• メール内の画像を全画面で開き、コピー・保存が可能に
• 日付と時刻の新しいホイール
• メール作成が速く開き、「挿入」の候補を削除
• クイック返信をカード表示に。VIP は固定した連絡先に追加
• 長いニュースレターで空白部分までスクロールしなくなりました
</ja-JP>
```
