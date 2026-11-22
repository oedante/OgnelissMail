# «Что нового» — 2.7.0 (171), относительно 2.6.9 (170)

Просьба владельца 22.11.2026: «подними версию до 2.7.0». Шаги владельца —
`OWNER_STEPS_2.7.0.md`. 2.6.9 ушла архивом с коммита 0d13c81 — в 2.7.0 всё,
что сделано после.

## Сделано в 2.7.0

- **Виджет календаря (Android): номер недели, как в приложении.** В режиме
  «Неделя» — «Н47» слева от дней (в приложении — в том же месте над
  сеткой недели); в режиме «Месяц» — столбец номеров слева от строк, если в
  приложении включено «Настройки → Календарь → Номера недель» (как в сетке
  месяца приложения). Переключатель сразу обновляет виджет.
- **Номер недели при неделе с воскресенья** (приложение и виджет): номер
  берётся по середине строки — неделя «вс–сб» получает номер своих
  понедельника–субботы, а не прошлой недели. С понедельника — как было.

- **Файлы календаря .ics — в приложении** (вопрос владельца 22.11.2026:
  «А приложение не может такое открывать?» — бронирование гостиницы
  файлом). Вложение .ics (.vcs) открывается не сторонней программой, а
  здесь: название, время (событие на несколько дней — с датой конца),
  место, описание, адрес организатора и «В календарь» — окно новой встречи,
  заполненное из файла. Файл .ics, присланный через «Поделиться», — так же,
  а не новым письмом с вложением.
- **Бронирование — не приглашение.** Файл с METHOD:REQUEST без участников
  (бронирования, билеты) у ящиков IMAP показывался приглашением с «Принять /
  Отклонить» — ответ ушёл бы роботу брони. Теперь у такого — «Событие
  календаря» и «В календарь». Организатор без «mailto:» («Имя <адрес>»)
  читается; событие на весь день открывается в «В календарь» на весь день.

- **Настройки «сами»** (замечание владельца 22.11.2026: «сейчас не
  настройки, а пульт космического корабля» и уточнение «не убирать без
  потери функций, а автоматизировать выбор того, в чём пользователь не
  разберётся»):
  - **Проверка почты в фоне** выбирается сама: сигнал через сервисы Google,
    если они есть на телефоне; иначе — через приложение UnifiedPush
    (несколько — первое по названию, раньше выбирал человек); без них — по
    расписанию. «Работать в фоне» включается само для ящиков «Мгновенно» и
    «По расписанию». Ручной выбор (и «Автоматически» обратно) — «Расширенные
    настройки → Проверка почты в фоне»; из «Уведомлений» и «Разрешений»
    убрано.
  - **Уведомления** (владелец: «разграничить людей и коллег — там
    уведомления как в мессенджере, а рассылки сделаем простыми»): письма
    людей и коллег — как сообщение в мессенджере (Android — беседой с
    портретом отправителя и значком приложения на нём, iPhone — с фото
    отправителя), рассылки и служебные письма — простым уведомлением (на
    Android — со значком ящика, если ящиков несколько). Письмо от человека —
    не рассылка, вы в «Кому» или «Копии» (до 50 адресатов), отправитель —
    коллега, контакт, тот, с кем вы переписывались, или личный ящик (Gmail,
    Яндекс, Mail.ru…). Раньше личные ящики, которых нет в контактах, шли
    обычным видом. Тонкая настройка (VIP, письма людей, все письма) —
    «Расширенные настройки → Уведомления».
  - **Контакты и календарь ящиков в телефоне** — сами, по умолчанию, у всех
    ящиков, кроме Google (и iCloud на iPhone): их телефон синхронизирует сам.
    Переключатели у каждого ящика убраны; один выключатель — «Настройки →
    Контакты» и «→ Календарь». Разрешения на контакты и календарь
    спрашиваются при первой настройке (с пояснением, зачем), у тех, кто
    настроил приложение раньше, — один раз после обновления. Пояснения
    разрешений переписаны: что именно появится в телефоне и почему Google не
    дублируется.
  - **Подсказка «Проверка почты»** — без «Работать в фоне» (включается само).
- **Календарь Google** (журнал пользователя 22.11.2026: «создал встречу в
  календаре Google — в приложении нет»): жест «обновить» в календаре теперь
  проверяет календари сразу (раньше календари DAV ждали своих 15 минут), а
  открытие календаря подтягивает встречи, если их не проверяли больше 2
  минут.
- **Календарь на устройстве на Android 11+** (тот же журнал, Motorola,
  Android 16: «Unknown URL content://com.android.calendar/calendars»):
  системный календарь и контакты объявлены в манифесте — приложение их
  видит.

## Тексты магазинов

В текстах магазинов 2.6.9 не было пунктов, добавленных в 2.6.9 после них:
«Ответить» слева, приветствие по времени суток, свои группы рассылки в
подсказках адреса. Они — здесь, вместе с номером недели в виджете.
Приветствие по времени суток — только в языках, где оно меняется
(ru, de, fr, it, pl, ro, sk, cs): «Hello», «Hola», «こんにちは» от часа не
зависят. В арабском и иврите кнопка «Ответить» — первая (справа).

## Кратко (RU / EN)

**RU.** В виджете календаря — номер недели: в режиме «Неделя» всегда, в
«Месяце» — столбцом, как в приложении с «Номерами недель». Файлы событий
.ics открываются в приложении — с кнопкой «В календарь». Проверка почты в
фоне, контакты и календарь в телефоне настраиваются сами; письма людей и
коллег приходят как сообщения в мессенджере, рассылки — простыми
уведомлениями; встречи Google появляются сразу после «обновить».

**EN.** The calendar widget shows week numbers: always in Week view and as
a column in Month view when Week numbers are on in the app. .ics event files
open in the app with an “Add to calendar” button. Background mail checks and
the phone’s contacts and calendar are set up automatically; mail from people
and colleagues arrives like messenger messages, newsletters as plain
notifications; Google meetings appear right after a refresh.

## Google Play — короткий текст (27 языков)

Самый длинный — 370 знаков (предел — 500).

```
<ru-RU>
• Приветствие по времени суток: «Доброе утро», «Добрый день», «Добрый вечер»
• Свои группы рассылки — в подсказках при наборе адреса
• Кнопка «Ответить» под письмом — слева
• Виджет календаря: номер недели, как в приложении
• Файлы событий .ics открываются в приложении — с кнопкой «В календарь»
• Исправления и улучшения
</ru-RU>
<en-US>
• Your own contact groups appear as you type an address
• The Reply button below a message is now on the left
• Calendar widget: week numbers, as in the app
• .ics event files open in the app, with “Add to calendar”
• Bug fixes and improvements
</en-US>
<de-DE>
• Begrüßung nach Tageszeit: „Guten Morgen“, „Guten Tag“, „Guten Abend“
• Eigene Verteilerlisten erscheinen beim Eingeben einer Adresse
• Die Schaltfläche „Antworten“ unter der Nachricht steht jetzt links
• Kalender-Widget: Kalenderwochen wie in der App
• .ics-Termindateien öffnen sich in der App – mit „Zum Kalender“
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Salutation selon l’heure : « Bonjour » ou « Bonsoir »
• Vos groupes de contacts apparaissent pendant la saisie d’une adresse
• Le bouton « Répondre » sous le message est désormais à gauche
• Widget calendrier : numéros de semaine, comme dans l’application
• Les fichiers d’événement .ics s’ouvrent dans l’app, avec « Ajouter à l’agenda »
• Corrections et améliorations
</fr-FR>
<ar>
• تظهر مجموعاتك البريدية أثناء كتابة العنوان
• زر «رد» أسفل الرسالة أصبح أولًا
• أداة التقويم: أرقام الأسابيع كما في التطبيق
• تُفتح ملفات الأحداث ‎.ics داخل التطبيق مع زر «إضافة إلى التقويم»
• إصلاحات وتحسينات
</ar>
<hu-HU>
• A saját csoportjaid megjelennek a cím beírásakor
• Az üzenet alatti Válasz gomb mostantól balra van
• Naptár widget: a hét sorszáma, mint az alkalmazásban
• Az .ics eseményfájlok az alkalmazásban nyílnak meg, „Hozzáadás a naptárhoz” gombbal
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Nhóm liên hệ của bạn hiện ra khi nhập địa chỉ
• Nút Trả lời dưới thư nay nằm bên trái
• Tiện ích lịch: số tuần, như trong ứng dụng
• Tệp sự kiện .ics mở ngay trong ứng dụng, có nút “Thêm vào lịch”
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Dine egne kontaktgrupper vises, mens du skriver en adresse
• Knappen Svar under mailen står nu til venstre
• Kalenderwidget: ugenumre som i appen
• .ics-begivenhedsfiler åbnes i appen med “Føj til kalender”
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• קבוצות הקשר שלך מופיעות בזמן הקלדת כתובת
• כפתור השב מתחת להודעה מופיע עכשיו ראשון
• ווידג׳ט היומן: מספרי שבועות כמו באפליקציה
• קובצי אירוע ‎.ics נפתחים באפליקציה, עם הכפתור „הוסף ללוח השנה”
• תיקוני באגים ושיפורים
</iw-IL>
<id>
• Grup kontak Anda muncul saat mengetik alamat
• Tombol Balas di bawah email kini di kiri
• Widget kalender: nomor minggu, seperti di aplikasi
• File acara .ics terbuka di aplikasi, dengan tombol “Tambahkan ke kalender”
• Perbaikan bug dan peningkatan
</id>
<es-ES>
• Tus grupos de contactos aparecen al escribir una dirección
• El botón Responder bajo el mensaje ahora está a la izquierda
• Widget de calendario: números de semana, como en la app
• Los archivos de evento .ics se abren en la app, con «Añadir al calendario»
• Correcciones y mejoras
</es-ES>
<it-IT>
• Saluto secondo l’ora: «Buongiorno» o «Buonasera»
• I tuoi gruppi di contatti compaiono mentre digiti un indirizzo
• Il pulsante Rispondi sotto il messaggio ora è a sinistra
• Widget calendario: numeri delle settimane, come nell’app
• I file evento .ics si aprono nell’app, con «Aggiungi al calendario»
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 输入地址时会显示您自己的联系人组
• 邮件下方的“回复”按钮现在位于左侧
• 日历小组件：显示周数，与应用一致
• .ics 事件文件可在应用内打开，并可“添加到日历”
• 错误修复和改进
</zh-CN>
<ko-KR>
• 주소를 입력할 때 내 연락처 그룹이 표시됩니다
• 메일 하단의 답장 버튼이 이제 왼쪽에 있습니다
• 캘린더 위젯: 앱처럼 주 번호 표시
• .ics 일정 파일을 앱에서 열고 ‘캘린더에 추가’ 버튼으로 추가
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Je eigen contactgroepen verschijnen tijdens het typen van een adres
• De knop Beantwoorden onder het bericht staat nu links
• Agendawidget: weeknummers, zoals in de app
• .ics-afspraakbestanden openen in de app, met ‘Toevoegen aan agenda’
• Bugfixes en verbeteringen
</nl-NL>
<no-NO>
• Dine egne kontaktgrupper vises mens du skriver en adresse
• Svar-knappen under meldingen er nå til venstre
• Kalenderwidget: ukenumre som i appen
• .ics-hendelsesfiler åpnes i appen, med «Legg til i kalender»
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Powitanie zależne od pory dnia: „Dzień dobry” lub „Dobry wieczór”
• Własne grupy kontaktów pojawiają się podczas wpisywania adresu
• Przycisk Odpowiedz pod wiadomością jest teraz po lewej
• Widżet kalendarza: numery tygodni, jak w aplikacji
• Pliki wydarzeń .ics otwierają się w aplikacji, z przyciskiem „Dodaj do kalendarza”
• Poprawki błędów i ulepszenia
</pl-PL>
<pt-BR>
• Seus grupos de contatos aparecem ao digitar um endereço
• O botão Responder abaixo da mensagem agora fica à esquerda
• Widget de calendário: números das semanas, como no app
• Arquivos de evento .ics abrem no app, com “Adicionar ao calendário”
• Correções e melhorias
</pt-BR>
<ro>
• Salut după ora zilei: „Bună dimineața”, „Bună ziua”, „Bună seara”
• Grupurile tale de contacte apar când tastezi o adresă
• Butonul Răspunde de sub mesaj este acum în stânga
• Widgetul calendar: numărul săptămânii, ca în aplicație
• Fișierele de eveniment .ics se deschid în aplicație, cu „Adaugă în calendar”
• Remedieri și îmbunătățiri
</ro>
<sk>
• Pozdrav podľa dennej doby: „Dobré ráno“, „Dobrý deň“, „Dobrý večer“
• Vlastné skupiny kontaktov sa zobrazia pri písaní adresy
• Tlačidlo Odpovedať pod správou je teraz vľavo
• Miniaplikácia kalendára: čísla týždňov ako v aplikácii
• Súbory udalostí .ics sa otvárajú v aplikácii s tlačidlom „Pridať do kalendára“
• Opravy chýb a vylepšenia
</sk>
<th>
• กลุ่มผู้ติดต่อของคุณแสดงขึ้นขณะพิมพ์ที่อยู่
• ปุ่มตอบกลับใต้ข้อความอยู่ทางซ้ายแล้ว
• วิดเจ็ตปฏิทิน: แสดงหมายเลขสัปดาห์เหมือนในแอป
• ไฟล์กิจกรรม .ics เปิดในแอปได้ พร้อมปุ่ม “เพิ่มลงในปฏิทิน”
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Kendi kişi gruplarınız adres yazarken görünür
• İletinin altındaki Yanıtla düğmesi artık solda
• Takvim widget’ı: uygulamadaki gibi hafta numaraları
• .ics etkinlik dosyaları uygulamada açılır, “Takvime ekle” düğmesiyle
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Omat yhteystietoryhmäsi näkyvät osoitetta kirjoittaessa
• Viestin alla oleva Vastaa-painike on nyt vasemmalla
• Kalenteri-widget: viikkonumerot kuten sovelluksessa
• .ics-tapahtumatiedostot avautuvat sovelluksessa, painikkeella ”Lisää kalenteriin”
• Virheenkorjauksia ja parannuksia
</fi-FI>
<hi-IN>
• पता लिखते समय आपके अपने संपर्क समूह दिखते हैं
• ईमेल के नीचे “जवाब दें” बटन अब बाईं ओर है
• कैलेंडर विजेट: ऐप की तरह सप्ताह संख्या
• .ics इवेंट फ़ाइलें ऐप में खुलती हैं, “कैलेंडर में जोड़ें” बटन के साथ
• बग फ़िक्स और सुधार
</hi-IN>
<cs-CZ>
• Pozdrav podle denní doby: „Dobré ráno“, „Dobrý den“, „Dobrý večer“
• Vlastní skupiny kontaktů se zobrazí při psaní adresy
• Tlačítko Odpovědět pod zprávou je nyní vlevo
• Widget kalendáře: čísla týdnů jako v aplikaci
• Soubory událostí .ics se otevírají v aplikaci s tlačítkem „Přidat do kalendáře“
• Opravy chyb a vylepšení
</cs-CZ>
<sv-SE>
• Dina egna kontaktgrupper visas medan du skriver en adress
• Knappen Svara under meddelandet är nu till vänster
• Kalenderwidget: veckonummer som i appen
• .ics-händelsefiler öppnas i appen, med ”Lägg till i kalendern”
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• アドレス入力中に自分の連絡先グループが表示されます
• メール下部の「返信」ボタンが左側になりました
• カレンダーウィジェット：アプリと同じく週番号を表示
• .ics の予定ファイルをアプリで開き、「カレンダーに追加」で追加
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Без строки о виджете календаря: он есть только на Android.

```
<ru-RU>
• Приветствие по времени суток: «Доброе утро», «Добрый день», «Добрый вечер»
• Свои группы рассылки — в подсказках при наборе адреса
• Кнопка «Ответить» под письмом — слева
• Файлы событий .ics открываются в приложении — с кнопкой «В календарь»
• Исправления и улучшения
</ru-RU>
<en-US>
• Your own contact groups appear as you type an address
• The Reply button below a message is now on the left
• .ics event files open in the app, with “Add to calendar”
• Bug fixes and improvements
</en-US>
<de-DE>
• Begrüßung nach Tageszeit: „Guten Morgen“, „Guten Tag“, „Guten Abend“
• Eigene Verteilerlisten erscheinen beim Eingeben einer Adresse
• Die Schaltfläche „Antworten“ unter der Nachricht steht jetzt links
• .ics-Termindateien öffnen sich in der App – mit „Zum Kalender“
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Salutation selon l’heure : « Bonjour » ou « Bonsoir »
• Vos groupes de contacts apparaissent pendant la saisie d’une adresse
• Le bouton « Répondre » sous le message est désormais à gauche
• Les fichiers d’événement .ics s’ouvrent dans l’app, avec « Ajouter à l’agenda »
• Corrections et améliorations
</fr-FR>
```
