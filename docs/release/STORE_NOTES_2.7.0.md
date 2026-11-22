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

## Тексты магазинов

В текстах магазинов 2.6.9 не было пунктов, добавленных в 2.6.9 после них:
«Ответить» слева, приветствие по времени суток, свои группы рассылки в
подсказках адреса. Они — здесь, вместе с номером недели в виджете.
Приветствие по времени суток — только в языках, где оно меняется
(ru, de, fr, it, pl, ro, sk, cs): «Hello», «Hola», «こんにちは» от часа не
зависят. В арабском и иврите кнопка «Ответить» — первая (справа).

## Кратко (RU / EN)

**RU.** В виджете календаря — номер недели: в режиме «Неделя» всегда, в
«Месяце» — столбцом, как в приложении с «Номерами недель».

**EN.** The calendar widget shows week numbers: always in Week view and as
a column in Month view when Week numbers are on in the app.

## Google Play — короткий текст (27 языков)

Самый длинный — 290 знаков (предел — 500).

```
<ru-RU>
• Приветствие по времени суток: «Доброе утро», «Добрый день», «Добрый вечер»
• Свои группы рассылки — в подсказках при наборе адреса
• Кнопка «Ответить» под письмом — слева
• Виджет календаря: номер недели, как в приложении
• Исправления и улучшения
</ru-RU>
<en-US>
• Your own contact groups appear as you type an address
• The Reply button below a message is now on the left
• Calendar widget: week numbers, as in the app
• Bug fixes and improvements
</en-US>
<de-DE>
• Begrüßung nach Tageszeit: „Guten Morgen“, „Guten Tag“, „Guten Abend“
• Eigene Verteilerlisten erscheinen beim Eingeben einer Adresse
• Die Schaltfläche „Antworten“ unter der Nachricht steht jetzt links
• Kalender-Widget: Kalenderwochen wie in der App
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Salutation selon l’heure : « Bonjour » ou « Bonsoir »
• Vos groupes de contacts apparaissent pendant la saisie d’une adresse
• Le bouton « Répondre » sous le message est désormais à gauche
• Widget calendrier : numéros de semaine, comme dans l’application
• Corrections et améliorations
</fr-FR>
<ar>
• تظهر مجموعاتك البريدية أثناء كتابة العنوان
• زر «رد» أسفل الرسالة أصبح أولًا
• أداة التقويم: أرقام الأسابيع كما في التطبيق
• إصلاحات وتحسينات
</ar>
<hu-HU>
• A saját csoportjaid megjelennek a cím beírásakor
• Az üzenet alatti Válasz gomb mostantól balra van
• Naptár widget: a hét sorszáma, mint az alkalmazásban
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Nhóm liên hệ của bạn hiện ra khi nhập địa chỉ
• Nút Trả lời dưới thư nay nằm bên trái
• Tiện ích lịch: số tuần, như trong ứng dụng
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Dine egne kontaktgrupper vises, mens du skriver en adresse
• Knappen Svar under mailen står nu til venstre
• Kalenderwidget: ugenumre som i appen
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• קבוצות הקשר שלך מופיעות בזמן הקלדת כתובת
• כפתור השב מתחת להודעה מופיע עכשיו ראשון
• ווידג׳ט היומן: מספרי שבועות כמו באפליקציה
• תיקוני באגים ושיפורים
</iw-IL>
<id>
• Grup kontak Anda muncul saat mengetik alamat
• Tombol Balas di bawah email kini di kiri
• Widget kalender: nomor minggu, seperti di aplikasi
• Perbaikan bug dan peningkatan
</id>
<es-ES>
• Tus grupos de contactos aparecen al escribir una dirección
• El botón Responder bajo el mensaje ahora está a la izquierda
• Widget de calendario: números de semana, como en la app
• Correcciones y mejoras
</es-ES>
<it-IT>
• Saluto secondo l’ora: «Buongiorno» o «Buonasera»
• I tuoi gruppi di contatti compaiono mentre digiti un indirizzo
• Il pulsante Rispondi sotto il messaggio ora è a sinistra
• Widget calendario: numeri delle settimane, come nell’app
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 输入地址时会显示您自己的联系人组
• 邮件下方的“回复”按钮现在位于左侧
• 日历小组件：显示周数，与应用一致
• 错误修复和改进
</zh-CN>
<ko-KR>
• 주소를 입력할 때 내 연락처 그룹이 표시됩니다
• 메일 하단의 답장 버튼이 이제 왼쪽에 있습니다
• 캘린더 위젯: 앱처럼 주 번호 표시
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Je eigen contactgroepen verschijnen tijdens het typen van een adres
• De knop Beantwoorden onder het bericht staat nu links
• Agendawidget: weeknummers, zoals in de app
• Bugfixes en verbeteringen
</nl-NL>
<no-NO>
• Dine egne kontaktgrupper vises mens du skriver en adresse
• Svar-knappen under meldingen er nå til venstre
• Kalenderwidget: ukenumre som i appen
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Powitanie zależne od pory dnia: „Dzień dobry” lub „Dobry wieczór”
• Własne grupy kontaktów pojawiają się podczas wpisywania adresu
• Przycisk Odpowiedz pod wiadomością jest teraz po lewej
• Widżet kalendarza: numery tygodni, jak w aplikacji
• Poprawki błędów i ulepszenia
</pl-PL>
<pt-BR>
• Seus grupos de contatos aparecem ao digitar um endereço
• O botão Responder abaixo da mensagem agora fica à esquerda
• Widget de calendário: números das semanas, como no app
• Correções e melhorias
</pt-BR>
<ro>
• Salut după ora zilei: „Bună dimineața”, „Bună ziua”, „Bună seara”
• Grupurile tale de contacte apar când tastezi o adresă
• Butonul Răspunde de sub mesaj este acum în stânga
• Widgetul calendar: numărul săptămânii, ca în aplicație
• Remedieri și îmbunătățiri
</ro>
<sk>
• Pozdrav podľa dennej doby: „Dobré ráno“, „Dobrý deň“, „Dobrý večer“
• Vlastné skupiny kontaktov sa zobrazia pri písaní adresy
• Tlačidlo Odpovedať pod správou je teraz vľavo
• Miniaplikácia kalendára: čísla týždňov ako v aplikácii
• Opravy chýb a vylepšenia
</sk>
<th>
• กลุ่มผู้ติดต่อของคุณแสดงขึ้นขณะพิมพ์ที่อยู่
• ปุ่มตอบกลับใต้ข้อความอยู่ทางซ้ายแล้ว
• วิดเจ็ตปฏิทิน: แสดงหมายเลขสัปดาห์เหมือนในแอป
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Kendi kişi gruplarınız adres yazarken görünür
• İletinin altındaki Yanıtla düğmesi artık solda
• Takvim widget’ı: uygulamadaki gibi hafta numaraları
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Omat yhteystietoryhmäsi näkyvät osoitetta kirjoittaessa
• Viestin alla oleva Vastaa-painike on nyt vasemmalla
• Kalenteri-widget: viikkonumerot kuten sovelluksessa
• Virheenkorjauksia ja parannuksia
</fi-FI>
<hi-IN>
• पता लिखते समय आपके अपने संपर्क समूह दिखते हैं
• ईमेल के नीचे “जवाब दें” बटन अब बाईं ओर है
• कैलेंडर विजेट: ऐप की तरह सप्ताह संख्या
• बग फ़िक्स और सुधार
</hi-IN>
<cs-CZ>
• Pozdrav podle denní doby: „Dobré ráno“, „Dobrý den“, „Dobrý večer“
• Vlastní skupiny kontaktů se zobrazí při psaní adresy
• Tlačítko Odpovědět pod zprávou je nyní vlevo
• Widget kalendáře: čísla týdnů jako v aplikaci
• Opravy chyb a vylepšení
</cs-CZ>
<sv-SE>
• Dina egna kontaktgrupper visas medan du skriver en adress
• Knappen Svara under meddelandet är nu till vänster
• Kalenderwidget: veckonummer som i appen
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• アドレス入力中に自分の連絡先グループが表示されます
• メール下部の「返信」ボタンが左側になりました
• カレンダーウィジェット：アプリと同じく週番号を表示
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
• Исправления и улучшения
</ru-RU>
<en-US>
• Your own contact groups appear as you type an address
• The Reply button below a message is now on the left
• Bug fixes and improvements
</en-US>
<de-DE>
• Begrüßung nach Tageszeit: „Guten Morgen“, „Guten Tag“, „Guten Abend“
• Eigene Verteilerlisten erscheinen beim Eingeben einer Adresse
• Die Schaltfläche „Antworten“ unter der Nachricht steht jetzt links
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Salutation selon l’heure : « Bonjour » ou « Bonsoir »
• Vos groupes de contacts apparaissent pendant la saisie d’une adresse
• Le bouton « Répondre » sous le message est désormais à gauche
• Corrections et améliorations
</fr-FR>
```
