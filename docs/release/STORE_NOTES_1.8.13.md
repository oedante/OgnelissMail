# «Что нового» — 1.8.13 (129)

Замечания владельца 29.10.2026: уведомление в шторке («много жирного»),
пропадающие панели после письма из уведомления, беседы, которые не
складывались, события iCloud «на два дня», проверка окна письма и окна
нового письма, телефон, планшет и компьютер.

Что изменилось (для разработчика):

- Уведомление о письме: жирным — только отправитель, ниже тема, в раскрытом —
  тема и начало текста; сводка «N новых писем» — строки «Отправитель — тема»
  обычным шрифтом. iPhone: отправитель — заголовок, тема — подзаголовок.
  На macOS и Linux уведомления не запускались вовсе (нет настроек плагина) —
  исправлено.
- Письмо из уведомления, ярлыка, «Разобрать», «Файлов», встречи и карточки
  человека — отдельной страницей /message/… (раньше страница ленты внутри
  главного экрана поверх настроек или «Написать» создавала второй главный
  экран, и после «Назад» пропадали панели). Нажатие на уведомление при живом
  окне Android приходило дважды — второе пропускается.
- Беседы IMAP (iCloud, Gmail, Яндекс, Mail.ru…): письмо встаёт в беседу
  любого известного письма из References и In-Reply-To (Outlook пишет в
  References только родителя), связанные беседы сливаются, ответ без
  заголовков — по теме и собеседнику. Разово после обновления — пересборка
  бесед по ссылкам. Свои адреса: iCloud — @icloud.com, @me.com, @mac.com;
  Gmail — точки и «+метка»; Яндекс — его домены; у личных ящиков свой адрес
  узнаётся по «Отправленным» и с другим именем (алиасы iCloud). Быстрый
  ответ — с полной цепочкой References.
- «Без уведомлений» для беседы (как в Telegram и Почте iPhone): «⋮» беседы,
  «Ещё» письма и карточки по удержанию; в ленте — перечёркнутый колокольчик.
- iCloud и календарь телефона: на iPhone событие на весь день в «Календаре в
  телефоне» и при экспорте занимало два дня (EventKit считает конец
  включительно) — теперь один; экспорт на Android — полночь UTC. Напоминание
  «в момент начала» у события на весь день — утром в 9:00 (iCloud «в день
  события в 9:00» звенело в полночь). Адреса календарей CalDAV — от узла,
  который ответил; запросы DAV только по HTTPS.
- Новое письмо: «Имя <адрес>», mailto и проверка адресов (неверный остаётся в
  поле со строкой «Проверьте адрес»); двойное нажатие «Отправить» не отправляет
  письмо дважды; Ctrl/⌘+Enter — отправить, Ctrl/⌘+S — сохранить, Esc —
  закрыть (и в тексте письма); типы файлов HEIC, WebP, видео, ics, vcf…;
  предупреждение о внешних адресатах учитывает все домены организации.
- Письмо: уведомление о прочтении — от ящика письма; «Прочитать все» во «Всей
  почте» и группе — каждому письму в его ящике и папке (IMAP отмечал чужие
  письма); на планшете и компьютере текст — одной колонкой с шапкой, строка
  ответа и кнопки — не через весь экран.
- iPhone и iPad: свайп «назад» от левого края работает и без «Анимаций
  интерфейса». Боковая панель на низком окне прокручивается.
- Microsoft Graph: 429/503 — повтор по Retry-After. Тексты лицензий HugeRTE и
  DOMPurify — в приложении.

Изменены файлы iOS (ios/Runner/PhoneMirrorPlugin.swift,
ios/Runner/DeviceCalendarPlugin.swift) и Android
(DeviceCalendarPlugin.kt); project.pbxproj не менялся.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Уведомления понятнее: жирным только отправитель, ниже тема
• Письмо из уведомления больше не прячет панели приложения
• Беседы собираются надёжнее, в том числе ответы из Outlook
• Беседу можно оставить без уведомлений
• iCloud: события на весь день в календаре телефона снова на один день
• iPhone и iPad: свайп от левого края возвращает назад
• Новое письмо: проверка адресов, клавиши Ctrl+Enter и Ctrl+S
</ru-RU>
<en-US>
• Clearer notifications: only the sender in bold, subject below
• Opening a message from a notification no longer hides the app panels
• Conversations group more reliably, including replies from Outlook
• Mute notifications for a single conversation
• iCloud: all-day events in the phone calendar span one day again
• iPhone and iPad: swipe from the left edge to go back
• Compose: address check, Ctrl+Enter and Ctrl+S shortcuts
</en-US>
<de-DE>
• Klarere Mitteilungen: nur der Absender fett, darunter der Betreff
• Eine E-Mail aus einer Mitteilung blendet die App-Leisten nicht mehr aus
• Unterhaltungen zuverlässiger gruppiert, auch Antworten aus Outlook
• Einzelne Unterhaltungen stummschalten
• iCloud: Ganztägige Termine im Telefonkalender wieder nur an einem Tag
• iPhone und iPad: vom linken Rand wischen, um zurückzugehen
• Verfassen: Adressprüfung, Tastenkürzel Strg+Enter und Strg+S
</de-DE>
<fr-FR>
• Notifications plus claires : expéditeur en gras, objet dessous
• Un message ouvert depuis une notification ne masque plus les barres
• Conversations mieux regroupées, réponses Outlook comprises
• Notifications coupées pour une seule conversation
• iCloud : les événements journée entière tiennent de nouveau sur un jour
• iPhone et iPad : balayez depuis le bord gauche pour revenir
• Rédaction : adresses vérifiées, raccourcis Ctrl+Entrée et Ctrl+S
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Уведомления понятнее: жирным только отправитель, ниже тема
• Письмо из уведомления больше не прячет панели приложения
• Беседы собираются надёжнее, в том числе ответы из Outlook
• Беседу можно оставить без уведомлений
• iCloud: события на весь день в календаре телефона снова на один день
• iPhone и iPad: свайп от левого края возвращает назад
• Новое письмо: проверка адресов, клавиши Ctrl+Enter и Ctrl+S
</ru-RU>
<en-US>
• Clearer notifications: only the sender in bold, subject below
• Opening a message from a notification no longer hides the app panels
• Conversations group more reliably, including replies from Outlook
• Mute notifications for a single conversation
• iCloud: all-day events in the phone calendar span one day again
• iPhone and iPad: swipe from the left edge to go back
• Compose: address check, Ctrl+Enter and Ctrl+S shortcuts
</en-US>
<de-DE>
• Klarere Mitteilungen: nur der Absender fett, darunter der Betreff
• Eine E-Mail aus einer Mitteilung blendet die App-Leisten nicht mehr aus
• Unterhaltungen zuverlässiger gruppiert, auch Antworten aus Outlook
• Einzelne Unterhaltungen stummschalten
• iCloud: Ganztägige Termine im Telefonkalender wieder nur an einem Tag
• iPhone und iPad: vom linken Rand wischen, um zurückzugehen
• Verfassen: Adressprüfung, Tastenkürzel Strg+Enter und Strg+S
</de-DE>
<fr-FR>
• Notifications plus claires : expéditeur en gras, objet dessous
• Un message ouvert depuis une notification ne masque plus les barres
• Conversations mieux regroupées, réponses Outlook comprises
• Notifications coupées pour une seule conversation
• iCloud : les événements journée entière tiennent de nouveau sur un jour
• iPhone et iPad : balayez depuis le bord gauche pour revenir
• Rédaction : adresses vérifiées, raccourcis Ctrl+Entrée et Ctrl+S
</fr-FR>
<ar>
• إشعارات أوضح: المرسل وحده بخط عريض والموضوع تحته
• فتح رسالة من إشعار لم يعد يخفي أشرطة التطبيق
• تجميع المحادثات أدق، بما فيها الردود من Outlook
• كتم إشعارات محادثة واحدة
• iCloud: أحداث اليوم الكامل في تقويم الهاتف ليوم واحد من جديد
• iPhone وiPad: اسحب من الحافة اليسرى للرجوع
• كتابة رسالة: التحقق من العناوين واختصارا Ctrl+Enter وCtrl+S
</ar>
<hu-HU>
• Érthetőbb értesítések: csak a feladó félkövér, alatta a tárgy
• Értesítésből nyitott levélnél már nem tűnnek el a sávok
• Megbízhatóbb beszélgetés-csoportosítás, az Outlookos válaszokkal együtt
• Egyetlen beszélgetés értesítései némíthatók
• iCloud: az egész napos események a telefon naptárában ismét egy naposak
• iPhone és iPad: a bal szélről húzva vissza lehet lépni
• Levélírás: címellenőrzés, Ctrl+Enter és Ctrl+S billentyűparancs
</hu-HU>
<vi>
• Thông báo rõ hơn: chỉ người gửi in đậm, tiêu đề ở dưới
• Mở thư từ thông báo không còn ẩn các thanh của ứng dụng
• Gom cuộc trò chuyện chính xác hơn, kể cả thư trả lời từ Outlook
• Tắt thông báo cho từng cuộc trò chuyện
• iCloud: sự kiện cả ngày trong lịch điện thoại lại chỉ một ngày
• iPhone và iPad: vuốt từ mép trái để quay lại
• Soạn thư: kiểm tra địa chỉ, phím tắt Ctrl+Enter và Ctrl+S
</vi>
<da-DK>
• Tydeligere notifikationer: kun afsenderen med fed, emnet nedenunder
• En mail åbnet fra en notifikation skjuler ikke længere appens bjælker
• Samtaler grupperes mere pålideligt, også svar fra Outlook
• Slå notifikationer fra for en enkelt samtale
• iCloud: heldagsbegivenheder i telefonens kalender fylder igen én dag
• iPhone og iPad: stryg fra venstre kant for at gå tilbage
• Skriv mail: adressetjek, genveje Ctrl+Enter og Ctrl+S
</da-DK>
<iw-IL>
• התראות ברורות יותר: רק השולח מודגש, הנושא מתחתיו
• פתיחת הודעה מהתראה כבר לא מסתירה את סרגלי האפליקציה
• קיבוץ שיחות אמין יותר, כולל תשובות מ Outlook
• השתקת התראות לשיחה אחת
• iCloud: אירועים של יום שלם ביומן הטלפון שוב ליום אחד
• iPhone ו iPad: החלקה מהקצה השמאלי חוזרת אחורה
• כתיבת הודעה: בדיקת כתובות, קיצורי Ctrl+Enter ו Ctrl+S
</iw-IL>
<id>
• Notifikasi lebih jelas: hanya pengirim yang tebal, subjek di bawahnya
• Membuka email dari notifikasi tidak lagi menyembunyikan bilah aplikasi
• Percakapan dikelompokkan lebih andal, termasuk balasan dari Outlook
• Bisukan notifikasi untuk satu percakapan
• iCloud: acara seharian di kalender ponsel kembali hanya satu hari
• iPhone dan iPad: geser dari tepi kiri untuk kembali
• Tulis email: cek alamat, pintasan Ctrl+Enter dan Ctrl+S
</id>
<es-ES>
• Notificaciones más claras: remitente en negrita, asunto debajo
• Un mensaje abierto desde una notificación ya no oculta las barras
• Conversaciones mejor agrupadas, también respuestas de Outlook
• Silencia las notificaciones de una sola conversación
• iCloud: los eventos de todo el día vuelven a ocupar un solo día
• iPhone y iPad: desliza desde el borde izquierdo para volver
• Redactar: comprobación de direcciones, atajos Ctrl+Intro y Ctrl+S
</es-ES>
<it-IT>
• Notifiche più chiare: solo il mittente in grassetto, oggetto sotto
• Un messaggio aperto da una notifica non nasconde più le barre
• Conversazioni raggruppate meglio, anche le risposte da Outlook
• Silenzia le notifiche di una singola conversazione
• iCloud: gli eventi di tutto il giorno tornano su un solo giorno
• iPhone e iPad: scorri dal bordo sinistro per tornare indietro
• Scrittura: controllo indirizzi, scorciatoie Ctrl+Invio e Ctrl+S
</it-IT>
<zh-CN>
• 通知更清晰：仅发件人加粗，主题在下方
• 从通知打开邮件后，应用的栏不再消失
• 会话归组更可靠，包括来自 Outlook 的回复
• 可单独关闭某个会话的通知
• iCloud：手机日历中的全天事件重新只占一天
• iPhone 和 iPad：从左边缘轻扫即可返回
• 写邮件：检查地址，快捷键 Ctrl+Enter 和 Ctrl+S
</zh-CN>
<ko-KR>
• 더 명확한 알림: 보낸 사람만 굵게, 제목은 아래에
• 알림에서 메일을 열어도 앱 막대가 더 이상 사라지지 않음
• Outlook 답장을 포함해 대화가 더 정확하게 묶임
• 대화별로 알림 끄기
• iCloud: 휴대폰 캘린더의 종일 일정이 다시 하루로 표시
• iPhone 및 iPad: 왼쪽 가장자리에서 밀어 뒤로 가기
• 메일 작성: 주소 확인, Ctrl+Enter 및 Ctrl+S 단축키
</ko-KR>
<nl-NL>
• Duidelijkere meldingen: alleen de afzender vet, het onderwerp eronder
• Een bericht openen vanuit een melding verbergt de balken niet meer
• Gesprekken worden betrouwbaarder gegroepeerd, ook antwoorden uit Outlook
• Meldingen dempen voor één gesprek
• iCloud: hele-dag-afspraken in de agenda van de telefoon weer op één dag
• iPhone en iPad: veeg vanaf de linkerrand om terug te gaan
• Opstellen: adrescontrole, sneltoetsen Ctrl+Enter en Ctrl+S
</nl-NL>
<no-NO>
• Tydeligere varsler: bare avsenderen i fet skrift, emnet under
• En e-post åpnet fra et varsel skjuler ikke lenger appens linjer
• Samtaler grupperes mer pålitelig, også svar fra Outlook
• Demp varsler for én samtale
• iCloud: heldagshendelser i telefonens kalender varer igjen én dag
• iPhone og iPad: sveip fra venstre kant for å gå tilbake
• Skriv e-post: adressesjekk, snarveier Ctrl+Enter og Ctrl+S
</no-NO>
<pl-PL>
• Czytelniejsze powiadomienia: pogrubiony tylko nadawca, temat poniżej
• Wiadomość otwarta z powiadomienia nie ukrywa już pasków aplikacji
• Rozmowy grupują się pewniej, także odpowiedzi z Outlooka
• Wyciszanie powiadomień pojedynczej rozmowy
• iCloud: wydarzenia całodniowe w kalendarzu telefonu znów trwają jeden dzień
• iPhone i iPad: przesuń od lewej krawędzi, aby wrócić
• Nowa wiadomość: sprawdzanie adresów, skróty Ctrl+Enter i Ctrl+S
</pl-PL>
<pt-BR>
• Notificações mais claras: só o remetente em negrito, assunto abaixo
• Abrir um e-mail pela notificação não esconde mais as barras do app
• Conversas agrupadas com mais precisão, inclusive respostas do Outlook
• Silencie as notificações de uma única conversa
• iCloud: eventos de dia inteiro voltam a ocupar um só dia
• iPhone e iPad: deslize da borda esquerda para voltar
• Escrever: verificação de endereços, atalhos Ctrl+Enter e Ctrl+S
</pt-BR>
<ro>
• Notificări mai clare: doar expeditorul îngroșat, subiectul dedesubt
• Un mesaj deschis din notificare nu mai ascunde barele aplicației
• Conversații grupate mai sigur, inclusiv răspunsuri din Outlook
• Notificări dezactivate pentru o singură conversație
• iCloud: evenimentele de o zi întreagă ocupă din nou o singură zi
• iPhone și iPad: glisați de la marginea stângă pentru înapoi
• Scriere: verificarea adreselor, comenzi Ctrl+Enter și Ctrl+S
</ro>
<sk>
• Prehľadnejšie upozornenia: tučne len odosielateľ, predmet pod ním
• Správa otvorená z upozornenia už neskrýva lišty aplikácie
• Konverzácie sa zoskupujú spoľahlivejšie, aj odpovede z Outlooku
• Stlmenie upozornení jednej konverzácie
• iCloud: celodenné udalosti v kalendári telefónu opäť trvajú jeden deň
• iPhone a iPad: potiahnutím od ľavého okraja sa vrátite späť
• Písanie: kontrola adries, skratky Ctrl+Enter a Ctrl+S
</sk>
<th>
• การแจ้งเตือนชัดขึ้น: ตัวหนาเฉพาะผู้ส่ง หัวเรื่องอยู่ด้านล่าง
• เปิดอีเมลจากการแจ้งเตือนแล้วแถบของแอปไม่หายไปอีก
• จัดกลุ่มการสนทนาแม่นยำขึ้น รวมถึงคำตอบจาก Outlook
• ปิดเสียงการแจ้งเตือนของการสนทนาเดียว
• iCloud: กิจกรรมทั้งวันในปฏิทินโทรศัพท์กลับมาเป็นหนึ่งวัน
• iPhone และ iPad: ปัดจากขอบซ้ายเพื่อย้อนกลับ
• เขียนอีเมล: ตรวจสอบที่อยู่ ทางลัด Ctrl+Enter และ Ctrl+S
</th>
<tr-TR>
• Daha net bildirimler: yalnızca gönderen kalın, konu altında
• Bildirimden açılan ileti artık uygulama çubuklarını gizlemiyor
• Yazışmalar daha güvenilir gruplanıyor, Outlook yanıtları dahil
• Tek bir yazışmanın bildirimlerini sessize alma
• iCloud: telefon takvimindeki tüm gün etkinlikleri yine tek gün
• iPhone ve iPad: geri dönmek için sol kenardan kaydırın
• İleti yazma: adres denetimi, Ctrl+Enter ve Ctrl+S kısayolları
</tr-TR>
<fi-FI>
• Selkeämmät ilmoitukset: vain lähettäjä lihavoituna, aihe alla
• Ilmoituksesta avattu viesti ei enää piilota sovelluksen palkkeja
• Keskustelut ryhmitellään luotettavammin, myös Outlookin vastaukset
• Yksittäisen keskustelun ilmoitusten mykistys
• iCloud: koko päivän tapahtumat ovat taas yhden päivän pituisia
• iPhone ja iPad: pyyhkäise vasemmasta reunasta palataksesi
• Kirjoitus: osoitteiden tarkistus, pikanäppäimet Ctrl+Enter ja Ctrl+S
</fi-FI>
<hi-IN>
• साफ़ सूचनाएँ: केवल भेजने वाला बोल्ड, विषय नीचे
• सूचना से ईमेल खोलने पर ऐप की पट्टियाँ अब नहीं छिपतीं
• बातचीत अधिक भरोसेमंद ढंग से समूहित, Outlook के जवाब भी
• एक बातचीत की सूचनाएँ म्यूट करें
• iCloud: फ़ोन कैलेंडर में पूरे दिन के इवेंट फिर से एक दिन के
• iPhone और iPad: वापस जाने के लिए बाएँ किनारे से स्वाइप करें
• ईमेल लिखना: पतों की जाँच, Ctrl+Enter और Ctrl+S शॉर्टकट
</hi-IN>
<cs-CZ>
• Přehlednější oznámení: tučně jen odesílatel, předmět pod ním
• Zpráva otevřená z oznámení už neskrývá lišty aplikace
• Konverzace se seskupují spolehlivěji, i odpovědi z Outlooku
• Ztlumení oznámení jedné konverzace
• iCloud: celodenní události v kalendáři telefonu opět trvají jeden den
• iPhone a iPad: přejetím od levého okraje se vrátíte zpět
• Psaní: kontrola adres, zkratky Ctrl+Enter a Ctrl+S
</cs-CZ>
<sv-SE>
• Tydligare aviseringar: bara avsändaren i fetstil, ämnet under
• Ett mejl öppnat från en avisering döljer inte längre appens fält
• Konversationer grupperas mer pålitligt, även svar från Outlook
• Stäng av aviseringar för en enda konversation
• iCloud: heldagshändelser i telefonens kalender tar åter en dag
• iPhone och iPad: svep från vänsterkanten för att gå tillbaka
• Skriva: adresskontroll, kortkommandon Ctrl+Enter och Ctrl+S
</sv-SE>
<ja-JP>
• 通知が見やすく：太字は差出人のみ、件名はその下に
• 通知からメールを開いてもアプリのバーが消えなくなりました
• Outlook からの返信も含め、スレッドのまとまりがより正確に
• スレッドごとに通知をミュート
• iCloud：電話のカレンダーの終日予定が再び 1 日になりました
• iPhone と iPad：左端からスワイプで戻る
• メール作成：アドレスの確認、Ctrl+Enter と Ctrl+S のショートカット
</ja-JP>
```
