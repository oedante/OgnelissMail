# «Что нового» — 2.7.4 (175), после 2.7.2 (173)

Просьба владельца 26.11.2026: «Подними версию до 2.7.4». В 2.7.4 — всё,
что сделано после сборки 2.7.2 (номер 174 считаем занятым выпуском 2.7.3).
Шаги владельца — `OWNER_STEPS_2.7.4.md`. Зависимости, схема базы, ключи,
манифест Android и файлы Xcode не менялись; серверы — тоже.

## Сделано в 2.7.4

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

**RU.** Письмо сразу уходит в «Исходящие» и отправляется в фоне — и при
плохой связи; после отправки в «Черновиках» не остаётся копий; надёжнее на
мобильном интернете; погода в виджетах не пропадает; SMS и мессенджеры по
номеру из письма; исправления уведомлений и напоминания о вложении.

**EN.** Sent mail goes straight to the Outbox and is delivered in the
background, even on a poor connection; no leftover copies in Drafts; more
reliable on mobile data; weather in widgets no longer disappears; SMS and
messengers from a phone number in an email; fixes for notification actions
and the attachment reminder.

## Google Play — короткий текст (27 языков)

Самый длинный — 470 знаков (de-DE; предел — 500).

```
<ru-RU>
• Письмо сразу уходит в «Исходящие»: окно закрывается, отправка идёт в фоне, при плохой связи — повторы до суток
• После отправки в «Черновиках» не остаётся копий
• Надёжнее на мобильном интернете: меньше подключений, понятные ошибки
• Погода в виджетах больше не пропадает
• Номер телефона в письме: позвонить, SMS, мессенджеры
• Исправления уведомлений и напоминания о вложении
</ru-RU>
<en-US>
• Sent mail goes straight to the Outbox: the window closes and delivery continues in the background, retrying for up to a day on a poor connection
• No leftover copies in Drafts after sending
• More reliable on mobile data: fewer connections, clearer errors
• Weather in widgets no longer disappears
• Phone numbers in emails: call, SMS, messengers
• Fixes for notification actions and the attachment reminder
</en-US>
<de-DE>
• Gesendete E-Mails landen sofort im Postausgang: Das Fenster schließt sich, der Versand läuft im Hintergrund – bei schlechter Verbindung mit Wiederholungen bis zu einem Tag
• Nach dem Senden bleiben keine Kopien in den Entwürfen
• Zuverlässiger im Mobilfunknetz: weniger Verbindungen, klarere Fehler
• Das Wetter im Widget verschwindet nicht mehr
• Telefonnummern in E-Mails: anrufen, SMS, Messenger
• Korrekturen bei Benachrichtigungsaktionen und der Anhang-Erinnerung
</de-DE>
<fr-FR>
• Le message part aussitôt dans la boîte d’envoi : la fenêtre se ferme, l’envoi continue en arrière-plan, avec de nouvelles tentatives pendant 24 h si la connexion est mauvaise
• Plus de copie dans les brouillons après l’envoi
• Plus fiable en données mobiles : moins de connexions, erreurs plus claires
• La météo ne disparaît plus des widgets
• Numéros dans les e-mails : appel, SMS, messageries
• Corrections des actions de notification et du rappel de pièce jointe
</fr-FR>
<ar>
• تنتقل الرسالة فورًا إلى «صندوق الصادر»: تُغلق النافذة ويستمر الإرسال في الخلفية، مع إعادة المحاولة حتى يوم كامل عند ضعف الاتصال
• لا تبقى نسخ في «المسودات» بعد الإرسال
• موثوقية أعلى على بيانات الجوال: اتصالات أقل ورسائل خطأ أوضح
• لم يعد الطقس يختفي من الأدوات
• أرقام الهاتف في الرسائل: اتصال وSMS وتطبيقات المراسلة
• إصلاحات لإجراءات الإشعارات وتذكير المرفقات
</ar>
<hu-HU>
• Az elküldött levél azonnal a Postázandó mappába kerül: az ablak bezárul, a küldés a háttérben folytatódik, gyenge kapcsolatnál akár egy napig újrapróbálva
• Küldés után nem marad másolat a Piszkozatokban
• Megbízhatóbb mobilneten: kevesebb kapcsolódás, érthetőbb hibák
• Az időjárás már nem tűnik el a widgetekből
• Telefonszámok a levelekben: hívás, SMS, üzenetküldők
• Javítások az értesítési műveletekben és a mellékletemlékeztetőben
</hu-HU>
<vi>
• Thư gửi đi được chuyển ngay vào Hộp thư đi: cửa sổ đóng lại, việc gửi tiếp tục ở chế độ nền, thử lại đến một ngày khi kết nối kém
• Không còn bản sao trong Thư nháp sau khi gửi
• Ổn định hơn với dữ liệu di động: ít kết nối hơn, lỗi dễ hiểu hơn
• Thời tiết trong tiện ích không còn biến mất
• Số điện thoại trong thư: gọi, SMS, ứng dụng nhắn tin
• Sửa lỗi thao tác thông báo và lời nhắc tệp đính kèm
</vi>
<da-DK>
• Sendte mails går straks til Udbakken: vinduet lukkes, og afsendelsen fortsætter i baggrunden – ved dårlig forbindelse forsøges igen i op til et døgn
• Ingen kopier tilbage i Kladder efter afsendelse
• Mere pålidelig på mobildata: færre forbindelser, tydeligere fejl
• Vejret forsvinder ikke længere fra widgets
• Telefonnumre i mails: ring, sms, beskedapps
• Rettelser til handlinger i notifikationer og påmindelsen om vedhæftede filer
</da-DK>
<iw-IL>
• ההודעה עוברת מיד לדואר היוצא: החלון נסגר והשליחה ממשיכה ברקע, עם ניסיונות חוזרים עד יממה כשהחיבור חלש
• לא נשארים עותקים בטיוטות אחרי השליחה
• אמין יותר ברשת סלולרית: פחות התחברויות ושגיאות ברורות יותר
• מזג האוויר כבר לא נעלם מהווידג'טים
• מספרי טלפון בהודעות: שיחה, SMS ואפליקציות מסרים
• תיקונים לפעולות בהתראות ולתזכורת על קובץ מצורף
</iw-IL>
<id>
• Email terkirim langsung masuk ke Kotak Keluar: jendela tertutup dan pengiriman berlanjut di latar belakang, dicoba ulang hingga sehari saat koneksi buruk
• Tidak ada salinan tersisa di Draf setelah mengirim
• Lebih andal di data seluler: lebih sedikit koneksi, galat lebih jelas
• Cuaca di widget tidak lagi menghilang
• Nomor telepon di email: panggil, SMS, aplikasi pesan
• Perbaikan aksi notifikasi dan pengingat lampiran
</id>
<es-ES>
• El mensaje pasa al instante a la Bandeja de salida: la ventana se cierra y el envío sigue en segundo plano, con reintentos durante un día si la conexión es mala
• Ya no quedan copias en Borradores después de enviar
• Más fiable con datos móviles: menos conexiones y errores más claros
• El tiempo ya no desaparece de los widgets
• Números de teléfono en los correos: llamar, SMS, mensajería
• Correcciones en las acciones de notificación y el aviso de adjuntos
</es-ES>
<it-IT>
• Il messaggio passa subito in Posta in uscita: la finestra si chiude e l’invio prosegue in background, con nuovi tentativi fino a un giorno se la connessione è scarsa
• Dopo l’invio non restano copie nelle Bozze
• Più affidabile con i dati mobili: meno connessioni ed errori più chiari
• Il meteo non scompare più dai widget
• Numeri di telefono nelle email: chiamata, SMS, app di messaggistica
• Correzioni alle azioni delle notifiche e al promemoria degli allegati
</it-IT>
<zh-CN>
• 发送的邮件立即进入“发件箱”：窗口随即关闭，在后台继续发送，网络不佳时最多重试一天
• 发送后“草稿”中不再残留副本
• 移动网络下更稳定：连接更少，错误提示更清楚
• 小组件中的天气不再消失
• 邮件中的电话号码：拨打、短信、即时通讯应用
• 修复通知操作和附件提醒的问题
</zh-CN>
<ko-KR>
• 보낸 메일이 즉시 보낼 편지함으로 이동합니다. 창이 바로 닫히고 백그라운드에서 전송되며, 연결이 불안정하면 최대 하루 동안 다시 시도합니다
• 보낸 후 임시 보관함에 사본이 남지 않습니다
• 모바일 데이터에서 더 안정적: 연결 횟수 감소, 더 명확한 오류
• 위젯의 날씨가 더 이상 사라지지 않습니다
• 메일 속 전화번호: 통화, SMS, 메신저
• 알림 동작 및 첨부 파일 알림 수정
</ko-KR>
<nl-NL>
• Verzonden mail gaat direct naar Postvak UIT: het venster sluit en het verzenden gaat op de achtergrond door, bij een slechte verbinding tot een dag lang opnieuw geprobeerd
• Na verzenden blijven er geen kopieën in Concepten achter
• Betrouwbaarder op mobiele data: minder verbindingen, duidelijkere fouten
• Het weer verdwijnt niet meer uit widgets
• Telefoonnummers in e-mails: bellen, sms, chat-apps
• Verbeteringen in meldingsacties en de bijlageherinnering
</nl-NL>
<no-NO>
• Sendt e-post går straks til Utboksen: vinduet lukkes og sendingen fortsetter i bakgrunnen – ved dårlig forbindelse prøves det igjen i opptil et døgn
• Ingen kopier igjen i Utkast etter sending
• Mer pålitelig på mobildata: færre tilkoblinger, tydeligere feil
• Været forsvinner ikke lenger fra widgeter
• Telefonnumre i e-post: ring, SMS, meldingsapper
• Rettelser i varslingshandlinger og påminnelsen om vedlegg
</no-NO>
<pl-PL>
• Wysłana wiadomość od razu trafia do Skrzynki nadawczej: okno się zamyka, a wysyłanie trwa w tle – przy słabym połączeniu z ponawianiem do doby
• Po wysłaniu w Wersjach roboczych nie zostają kopie
• Niezawodniej w sieci komórkowej: mniej połączeń, czytelniejsze błędy
• Pogoda nie znika już z widżetów
• Numery telefonów w wiadomościach: połączenie, SMS, komunikatory
• Poprawki akcji w powiadomieniach i przypomnienia o załączniku
</pl-PL>
<pt-BR>
• A mensagem vai na hora para a Caixa de saída: a janela fecha e o envio continua em segundo plano, com novas tentativas por até um dia se a conexão estiver ruim
• Não ficam mais cópias em Rascunhos após o envio
• Mais confiável nos dados móveis: menos conexões e erros mais claros
• O clima não some mais dos widgets
• Números de telefone nos e-mails: ligar, SMS, mensageiros
• Correções nas ações de notificação e no lembrete de anexo
</pt-BR>
<ro>
• Mesajul trimis ajunge imediat în Mesaje de trimis: fereastra se închide, iar trimiterea continuă în fundal, cu reîncercări până la o zi dacă legătura e slabă
• După trimitere nu mai rămân copii în Ciorne
• Mai fiabil pe date mobile: mai puține conexiuni, erori mai clare
• Vremea nu mai dispare din widgeturi
• Numere de telefon în e-mailuri: apel, SMS, aplicații de mesagerie
• Corecturi la acțiunile din notificări și la memento-ul pentru atașamente
</ro>
<sk>
• Odoslaná správa ide hneď do priečinka Na odoslanie: okno sa zavrie a odosielanie pokračuje na pozadí, pri slabom pripojení s opakovaním až jeden deň
• Po odoslaní nezostávajú kópie v Konceptoch
• Spoľahlivejšie na mobilných dátach: menej pripojení, zrozumiteľnejšie chyby
• Počasie už nemizne z miniaplikácií
• Telefónne čísla v e-mailoch: hovor, SMS, komunikátory
• Opravy akcií v upozorneniach a pripomienky príloh
</sk>
<th>
• อีเมลที่ส่งจะย้ายไปที่กล่องขาออกทันที หน้าต่างปิดลงและส่งต่อในเบื้องหลัง เมื่อสัญญาณไม่ดีจะลองใหม่นานสูงสุดหนึ่งวัน
• ไม่มีสำเนาค้างในฉบับร่างหลังส่ง
• เสถียรขึ้นบนเน็ตมือถือ: เชื่อมต่อน้อยลง ข้อผิดพลาดชัดเจนขึ้น
• สภาพอากาศในวิดเจ็ตไม่หายไปอีกแล้ว
• หมายเลขโทรศัพท์ในอีเมล: โทร, SMS, แอปแชท
• แก้ไขการทำงานของการแจ้งเตือนและการเตือนไฟล์แนบ
</th>
<tr-TR>
• Gönderilen e-posta hemen Giden Kutusu’na geçer: pencere kapanır, gönderim arka planda sürer; bağlantı zayıfsa bir güne kadar yeniden denenir
• Gönderdikten sonra Taslaklar’da kopya kalmaz
• Mobil veride daha güvenilir: daha az bağlantı, daha anlaşılır hatalar
• Widget’lardaki hava durumu artık kaybolmuyor
• E-postadaki telefon numaraları: arama, SMS, mesajlaşma uygulamaları
• Bildirim işlemleri ve ek hatırlatıcısı için düzeltmeler
</tr-TR>
<fi-FI>
• Lähetetty viesti siirtyy heti Lähtevät-kansioon: ikkuna sulkeutuu ja lähetys jatkuu taustalla, heikolla yhteydellä uusintayrityksin jopa vuorokauden ajan
• Lähettämisen jälkeen Luonnoksiin ei jää kopioita
• Luotettavampi mobiilidatalla: vähemmän yhteyksiä, selkeämmät virheet
• Sää ei enää katoa widgeteistä
• Puhelinnumerot viesteissä: soitto, tekstiviesti, viestisovellukset
• Korjauksia ilmoitusten toimintoihin ja liitemuistutukseen
</fi-FI>
<hi-IN>
• भेजा गया ईमेल तुरंत आउटबॉक्स में जाता है: विंडो बंद हो जाती है और भेजना बैकग्राउंड में जारी रहता है; कमज़ोर कनेक्शन पर एक दिन तक दोबारा कोशिश होती है
• भेजने के बाद ड्राफ़्ट में कोई कॉपी नहीं बचती
• मोबाइल डेटा पर ज़्यादा भरोसेमंद: कम कनेक्शन, साफ़ त्रुटियाँ
• विजेट से मौसम अब गायब नहीं होता
• ईमेल में फ़ोन नंबर: कॉल, SMS, मैसेंजर
• नोटिफ़िकेशन कार्रवाइयों और अटैचमेंट रिमाइंडर में सुधार
</hi-IN>
<cs-CZ>
• Odeslaná zpráva jde hned do složky K odeslání: okno se zavře a odesílání pokračuje na pozadí, při slabém připojení s opakováním až jeden den
• Po odeslání nezůstávají kopie v Konceptech
• Spolehlivější na mobilních datech: méně připojení, srozumitelnější chyby
• Počasí už nemizí z widgetů
• Telefonní čísla v e-mailech: hovor, SMS, komunikátory
• Opravy akcí v oznámeních a připomínky přílohy
</cs-CZ>
<sv-SE>
• Skickad e-post hamnar direkt i Utkorgen: fönstret stängs och sändningen fortsätter i bakgrunden – vid dålig anslutning görs nya försök i upp till ett dygn
• Inga kopior blir kvar i Utkast efter sändning
• Pålitligare på mobildata: färre anslutningar, tydligare fel
• Vädret försvinner inte längre från widgetar
• Telefonnummer i e-post: ring, sms, meddelandeappar
• Rättningar av åtgärder i aviseringar och påminnelsen om bilagor
</sv-SE>
<ja-JP>
• 送信したメールはすぐに送信トレイへ。画面はすぐ閉じ、送信はバックグラウンドで続行。接続が悪いときは最大1日再試行します
• 送信後に下書きにコピーが残りません
• モバイルデータでより安定：接続回数が減り、エラーがわかりやすく
• ウィジェットの天気が消えなくなりました
• メール内の電話番号：通話、SMS、メッセンジャー
• 通知の操作と添付ファイルの確認の修正
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Письмо сразу уходит в «Исходящие»: окно закрывается, отправка идёт в фоне, при плохой связи — повторы до суток
• После отправки в «Черновиках» не остаётся копий
• Надёжнее на мобильном интернете: меньше подключений, понятные ошибки
• Погода в виджетах больше не пропадает
• Номер телефона в письме: позвонить, SMS, мессенджеры
• Исправления уведомлений и напоминания о вложении
</ru-RU>
<en-US>
• Sent mail goes straight to the Outbox: the window closes and delivery continues in the background, retrying for up to a day on a poor connection
• No leftover copies in Drafts after sending
• More reliable on mobile data: fewer connections, clearer errors
• Weather in widgets no longer disappears
• Phone numbers in emails: call, SMS, messengers
• Fixes for notification actions and the attachment reminder
</en-US>
<de-DE>
• Gesendete E-Mails landen sofort im Postausgang: Das Fenster schließt sich, der Versand läuft im Hintergrund – bei schlechter Verbindung mit Wiederholungen bis zu einem Tag
• Nach dem Senden bleiben keine Kopien in den Entwürfen
• Zuverlässiger im Mobilfunknetz: weniger Verbindungen, klarere Fehler
• Das Wetter im Widget verschwindet nicht mehr
• Telefonnummern in E-Mails: anrufen, SMS, Messenger
• Korrekturen bei Benachrichtigungsaktionen und der Anhang-Erinnerung
</de-DE>
<fr-FR>
• Le message part aussitôt dans la boîte d’envoi : la fenêtre se ferme, l’envoi continue en arrière-plan, avec de nouvelles tentatives pendant 24 h si la connexion est mauvaise
• Plus de copie dans les brouillons après l’envoi
• Plus fiable en données mobiles : moins de connexions, erreurs plus claires
• La météo ne disparaît plus des widgets
• Numéros dans les e-mails : appel, SMS, messageries
• Corrections des actions de notification et du rappel de pièce jointe
</fr-FR>
```
