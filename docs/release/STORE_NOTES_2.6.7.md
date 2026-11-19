# «Что нового» — 2.6.7 (167), относительно 2.6.5 (164)

Главное — **почта Gmail по паролю приложения** (письмо Google 19.11.2026:
доступ к почте через вход Google (`https://mail.google.com/`) требует
платной проверки безопасности CASA; приложение от него отказалось,
проверка продолжается для календаря и контактов). 2.6.6 (165) в магазины
не выходила — её изменения (свои приветствия, поля в подписи, фото
собеседников) входят в этот текст. Шаги владельца — `OWNER_STEPS_2.6.7.md`.

## Сделано в 2.6.7

Сборка 167 (19.11.2026) — после 166: отправка Gmail снова по 465 (SSL).
В 166 «Войти снова» ящика Google записывало порт SMTP 587, а в части сетей
он не отвечает — письма зависали в очереди. Теперь «Войти снова» серверы
ящика Google не меняет, а если 587 не отвечает, приложение само пробует
465. Текст магазинов тот же.

- **Gmail — по паролю приложения**, как iCloud. Плитка «Google» и адрес
  Gmail ведут к паролю приложения: на экране входа — что это и как его
  создать (двухэтапная проверка → «Пароли приложений»), кнопка «Создать
  пароль приложения» открывает страницу Google. Пароль можно вводить с
  пробелами, как его показывает Google. Вход через Google доступ к почте
  больше не запрашивает.
- **Календарь и контакты Google** для ящика Gmail — через вход Google (только
  календарь, контакты и фото собеседников): переключатель «Календарь и
  контакты Google» на экране входа (включён — страница Google открывается
  сразу после почты) или позже «Настройки → Аккаунты → ящик → Подключение →
  Календарь и контакты Google». Адрес аккаунта Google должен совпасть с
  адресом ящика — иначе подключение отменяется с объяснением.
- **Ящики Gmail, добавленные раньше через Google**, попросят пароль
  приложения один раз: «Войти снова» → пароль приложения (с той же
  инструкцией). Письма, папки и настройки ящика сохраняются; календарь и
  контакты Google такого ящика работают, как прежде.
- **Виджет «Календарь»** — всё, что в календаре приложения: задачи со
  сроком (✓), письма с напоминанием (✉), поручения (⚑) и приглашения без
  ответа (?); касание открывает задачу, письмо или поручение. В «Моём дне»
  — тоже. Выходные в сетке месяца и недели — красным, точки дней крупнее.
- **Вкладка «Мой день» в виджете «Календарь»** (Android): «День · Неделя ·
  Месяц · Мой день» — доска «Предстоит · В работе · Готово»; отдельный
  виджет можно не ставить.

## Из 2.6.6 (165, в магазины не выходила)

- **Свои приветствия с полями {…}** (просьба пользователей через владельца
  18.11.2026). «Настройки → Аккаунты → ящик → Подписи → Добавить своё
  приветствие»: текст и кнопки полей — адресат ({обращение} — «Иван
  Петрович», как в обычном приветствии; {имя_адресата},
  {фамилия_адресата}, {фио_адресата}), время ({время_суток} — «Доброе утро
  / Добрый день / Добрый вечер» по времени отправки; {дата}, {время}) и
  вы ({имя}, {должность}, {отдел}, {компания}, {телефон}, {почта}). Образец
  «В письме: …» показывает, как будет выглядеть. Новое приветствие сразу
  становится приветствием ящика; в письме все свои приветствия — в кнопке
  «Приветствие» над текстом; быстрый ответ и письма поручений — тоже по
  нему. Поле без значения пропадает вместе с лишней запятой
  («Здравствуйте, {обращение}!» без имени — «Здравствуйте!»). Работают и
  английские написания ({to_address}, {part_of_day}…), регистр не важен.
- **Кнопки полей в конструкторе подписи** — вставка в место курсора, и в
  редакторе с оформлением. Подпись понимает и русские написания полей
  ({имя}, {должность}, {телефон}).
- **Фото собеседников из профилей Google не пропадают** после
  сворачивания (замечание владельца 18.11): раньше фото по ссылке держались
  только в памяти и после каждого возврата в приложение скачивались заново
  — на их месте мелькал пустой кружок. Теперь фото скачивается один раз и
  хранится на телефоне, раз в неделю тихо обновляется; без сети —
  сохранённая копия.
- «Вопросы и ответы»: «Как сделать своё приветствие?» (27 языков); поиск
  по настройкам находит «Своё приветствие».

## Кратко (RU / EN)

**RU.** Почта Gmail подключается по паролю приложения — как iCloud: на
экране входа есть короткая инструкция и кнопка, открывающая страницу
Google. Календарь и контакты Google подключаются входом Google — сразу или
позже в настройках ящика. Уже добавленный ящик Gmail попросит пароль
приложения один раз («Войти снова»), письма и настройки сохраняются. Виджет календаря
показывает задачи, поручения и приглашения, выделяет выходные и получил
вкладку «Мой день». Свои приветствия с полями (обращение, время суток, ваши
имя и должность) и кнопки полей в конструкторе подписи; фото собеседников
из Google не пропадают после сворачивания.

**EN.** Gmail now connects with an app password, like iCloud: the sign-in
screen has short instructions and a button that opens the Google page. Google
Calendar and Contacts connect with Google sign-in — right away or later in
the account settings. A Gmail account added earlier asks for an app password once (“Sign in
again”); your mail and settings stay. The calendar widget shows tasks,
assignments and invitations, highlights weekends and has a new “My day”
tab. Custom greetings with fields (the recipient's name, the time of day,
your name and job title) and field buttons in the signature editor; contact
photos from Google no longer disappear after you switch apps.

## Google Play — короткий текст (27 языков)

```
<ru-RU>
• Gmail подключается по паролю приложения — инструкция на экране входа
• Свои приветствия с полями: обращение, время суток и другие
• Календарь в виджете: задачи, поручения и приглашения
• Вкладка «Мой день» в виджете календаря, выходные — цветом
• Фото собеседников не пропадают после сворачивания
• Исправления и улучшения
</ru-RU>
<en-US>
• Gmail now connects with an app password — steps on the sign-in screen
• Custom greetings with fields: name, time of day and more
• Calendar widget: tasks, assignments and invitations
• “My day” tab in the calendar widget, weekends highlighted
• Contact photos no longer vanish after switching apps
• Bug fixes and improvements
</en-US>
<de-DE>
• Gmail wird mit einem App-Passwort verbunden – Anleitung bei der Anmeldung
• Eigene Begrüßungen mit Feldern: Anrede, Tageszeit und mehr
• Kalender-Widget: Aufgaben, Aufträge und Einladungen
• Tab „Mein Tag“ im Kalender-Widget, Wochenenden hervorgehoben
• Kontaktfotos verschwinden nicht mehr nach dem App-Wechsel
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Gmail se connecte avec un mot de passe d’application — étapes à l’écran de connexion
• Salutations personnalisées avec champs : nom, moment de la journée…
• Widget Calendrier : tâches, missions et invitations
• Onglet « Ma journée » dans le widget Calendrier, week-ends en couleur
• Les photos des contacts ne disparaissent plus après un changement d’app
• Corrections et améliorations
</fr-FR>
<ar>
• يتصل Gmail بكلمة مرور التطبيق — الخطوات في شاشة تسجيل الدخول
• تحيات مخصصة بحقول: الاسم ووقت اليوم وغيرها
• أداة التقويم: المهام والتكليفات والدعوات
• علامة «يومي» في أداة التقويم، وعطلات نهاية الأسبوع ملونة
• لم تعد صور جهات الاتصال تختفي بعد التبديل بين التطبيقات
• إصلاحات وتحسينات
</ar>
<hu-HU>
• A Gmail alkalmazásjelszóval csatlakozik – útmutató a bejelentkezésnél
• Saját megszólítások mezőkkel: név, napszak és más
• Naptár widget: feladatok, megbízások és meghívók
• „Saját napom” lap a naptár widgetben, kiemelt hétvégék
• A partnerfotók nem tűnnek el alkalmazásváltás után
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Gmail kết nối bằng mật khẩu ứng dụng — hướng dẫn ở màn hình đăng nhập
• Lời chào riêng với trường: tên, buổi trong ngày và hơn thế
• Tiện ích Lịch: việc cần làm, giao việc và lời mời
• Thẻ “Ngày của tôi” trong tiện ích lịch, tô màu cuối tuần
• Ảnh liên hệ không còn biến mất sau khi chuyển ứng dụng
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Gmail forbindes med en app-adgangskode – vejledning ved login
• Egne hilsner med felter: navn, tid på dagen og mere
• Kalender-widget: opgaver, tildelinger og invitationer
• Fanen “Min dag” i kalender-widgetten, weekender fremhævet
• Kontaktbilleder forsvinder ikke længere efter appskift
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• Gmail מתחבר עם סיסמת אפליקציה — הוראות במסך הכניסה
• ברכות מותאמות עם שדות: שם, שעה ביום ועוד
• ווידג'ט היומן: משימות, הקצאות והזמנות
• לשונית "היום שלי" בווידג'ט היומן, סופי שבוע בצבע
• תמונות אנשי קשר כבר לא נעלמות אחרי מעבר בין אפליקציות
• תיקוני באגים ושיפורים
</iw-IL>
<id>
• Gmail terhubung dengan sandi aplikasi — langkahnya ada di layar masuk
• Salam khusus dengan kolom: nama, waktu hari, dan lainnya
• Widget Kalender: tugas, penugasan, dan undangan
• Tab “Hari saya” di widget kalender, akhir pekan berwarna
• Foto kontak tidak lagi hilang setelah berpindah aplikasi
• Perbaikan bug dan peningkatan
</id>
<es-ES>
• Gmail se conecta con una contraseña de aplicación: pasos en la pantalla de acceso
• Saludos personalizados con campos: nombre, momento del día y más
• Widget de calendario: tareas, encargos e invitaciones
• Pestaña «Mi día» en el widget de calendario, fines de semana destacados
• Las fotos de contactos ya no desaparecen al cambiar de app
• Correcciones y mejoras
</es-ES>
<it-IT>
• Gmail si collega con una password per le app: istruzioni nella schermata di accesso
• Saluti personalizzati con campi: nome, momento della giornata e altro
• Widget Calendario: attività, incarichi e inviti
• Scheda «Il mio giorno» nel widget Calendario, weekend evidenziati
• Le foto dei contatti non spariscono più dopo il cambio di app
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• Gmail 改用应用专用密码连接——登录界面有操作步骤
• 自定义问候语支持字段：称呼、时段等
• 日历小组件：任务、委派和邀请
• 日历小组件新增“我的一天”标签，周末以颜色标出
• 切换应用后联系人照片不再消失
• 错误修复和改进
</zh-CN>
<ko-KR>
• Gmail은 앱 비밀번호로 연결 — 로그인 화면에 안내
• 필드를 지원하는 사용자 인사말: 호칭, 시간대 등
• 캘린더 위젯: 할 일, 업무 지시, 초대
• 캘린더 위젯에 '나의 하루' 탭, 주말 색상 표시
• 앱 전환 후 연락처 사진이 더 이상 사라지지 않음
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Gmail maakt verbinding met een app-wachtwoord — stappen op het inlogscherm
• Eigen begroetingen met velden: naam, dagdeel en meer
• Agendawidget: taken, opdrachten en uitnodigingen
• Tabblad ‘Mijn dag’ in de agendawidget, weekenden gemarkeerd
• Contactfoto’s verdwijnen niet meer na wisselen van app
• Bugfixes en verbeteringen
</nl-NL>
<no-NO>
• Gmail kobles til med app-passord – veiledning på innloggingsskjermen
• Egne hilsener med felt: navn, tid på døgnet og mer
• Kalender-widget: oppgaver, oppdrag og invitasjoner
• Fanen «Min dag» i kalender-widgeten, helger fremhevet
• Kontaktbilder forsvinner ikke lenger etter appbytte
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Gmail łączy się za pomocą hasła do aplikacji — instrukcja na ekranie logowania
• Własne powitania z polami: zwrot, pora dnia i inne
• Widżet kalendarza: zadania, zlecenia i zaproszenia
• Karta „Mój dzień” w widżecie kalendarza, weekendy wyróżnione
• Zdjęcia kontaktów nie znikają już po przełączeniu aplikacji
• Poprawki błędów i ulepszenia
</pl-PL>
<pt-BR>
• O Gmail se conecta com senha de app — passos na tela de login
• Saudações personalizadas com campos: nome, período do dia e mais
• Widget de agenda: tarefas, atribuições e convites
• Aba “Meu dia” no widget de agenda, fins de semana destacados
• Fotos de contatos não somem mais ao trocar de app
• Correções e melhorias
</pt-BR>
<ro>
• Gmail se conectează cu o parolă pentru aplicație — pașii sunt pe ecranul de conectare
• Saluturi personalizate cu câmpuri: nume, moment al zilei și altele
• Widgetul Calendar: sarcini, însărcinări și invitații
• Fila „Ziua mea” în widgetul calendar, weekenduri evidențiate
• Fotografiile contactelor nu mai dispar după schimbarea aplicației
• Remedieri și îmbunătățiri
</ro>
<sk>
• Gmail sa pripája heslom aplikácie — postup na prihlasovacej obrazovke
• Vlastné pozdravy s poľami: oslovenie, časť dňa a ďalšie
• Miniaplikácia kalendára: úlohy, poverenia a pozvánky
• Karta „Môj deň“ v miniaplikácii kalendára, zvýraznené víkendy
• Fotky kontaktov už nemiznú po prepnutí aplikácie
• Opravy chýb a vylepšenia
</sk>
<th>
• Gmail เชื่อมต่อด้วยรหัสผ่านสำหรับแอป — ดูขั้นตอนที่หน้าลงชื่อเข้าใช้
• คำทักทายของคุณพร้อมช่องข้อมูล: ชื่อ ช่วงเวลา และอื่น ๆ
• วิดเจ็ตปฏิทิน: งาน งานที่มอบหมาย และคำเชิญ
• แท็บ "วันของฉัน" ในวิดเจ็ตปฏิทิน และวันหยุดสุดสัปดาห์แสดงสี
• รูปผู้ติดต่อไม่หายไปหลังสลับแอปอีกต่อไป
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Gmail uygulama şifresiyle bağlanır — adımlar giriş ekranında
• Alanlı özel selamlamalar: hitap, günün saati ve dahası
• Takvim widget'ı: görevler, atamalar ve davetler
• Takvim widget'ında "Günüm" sekmesi, renkli hafta sonları
• Kişi fotoğrafları uygulama değiştirince artık kaybolmuyor
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Gmail yhdistetään sovellussalasanalla – ohjeet kirjautumisnäytössä
• Omat tervehdykset kentillä: puhuttelu, vuorokaudenaika ja muuta
• Kalenteriwidget: tehtävät, toimeksiannot ja kutsut
• ”Oma päivä” -välilehti kalenteriwidgetissä, viikonloput korostettu
• Yhteystietojen kuvat eivät enää katoa sovellusta vaihtaessa
• Virheenkorjauksia ja parannuksia
</fi-FI>
<hi-IN>
• Gmail अब ऐप पासवर्ड से जुड़ता है — चरण साइन-इन स्क्रीन पर
• फ़ील्ड वाले अपने अभिवादन: संबोधन, दिन का समय और अधिक
• कैलेंडर विजेट: कार्य, असाइनमेंट और आमंत्रण
• कैलेंडर विजेट में "मेरा दिन" टैब, सप्ताहांत रंग में
• ऐप बदलने के बाद संपर्क फ़ोटो अब गायब नहीं होतीं
• बग फ़िक्स और सुधार
</hi-IN>
<cs-CZ>
• Gmail se připojuje heslem aplikace — postup na přihlašovací obrazovce
• Vlastní pozdravy s poli: oslovení, část dne a další
• Widget kalendáře: úkoly, pověření a pozvánky
• Karta „Můj den“ ve widgetu kalendáře, zvýrazněné víkendy
• Fotky kontaktů už po přepnutí aplikace nemizí
• Opravy chyb a vylepšení
</cs-CZ>
<sv-SE>
• Gmail ansluts med applösenord – steg på inloggningsskärmen
• Egna hälsningar med fält: tilltal, tid på dagen och mer
• Kalenderwidget: uppgifter, uppdrag och inbjudningar
• Fliken ”Min dag” i kalenderwidgeten, helger markerade
• Kontaktfoton försvinner inte längre efter appbyte
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• Gmail はアプリ パスワードで接続 — 手順はログイン画面に表示
• フィールド付きの自分の挨拶：宛名、時間帯など
• カレンダー ウィジェット：タスク、依頼、招待
• カレンダー ウィジェットに「今日の予定」タブ、週末を色分け
• アプリ切り替え後も連絡先の写真が消えなくなりました
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Gmail подключается по паролю приложения — инструкция на экране входа
• Свои приветствия с полями: обращение, время суток и другие
• Календарь в виджете: задачи, поручения и приглашения
• Выходные в виджетах календаря — цветом
• Фото собеседников не пропадают после сворачивания
• Исправления и улучшения
</ru-RU>
<en-US>
• Gmail now connects with an app password — steps on the sign-in screen
• Custom greetings with fields: name, time of day and more
• Calendar widget: tasks, assignments and invitations
• Weekends highlighted in calendar widgets
• Contact photos no longer vanish after switching apps
• Bug fixes and improvements
</en-US>
<de-DE>
• Gmail wird mit einem App-Passwort verbunden – Anleitung bei der Anmeldung
• Eigene Begrüßungen mit Feldern: Anrede, Tageszeit und mehr
• Kalender-Widget: Aufgaben, Aufträge und Einladungen
• Wochenenden in Kalender-Widgets hervorgehoben
• Kontaktfotos verschwinden nicht mehr nach dem App-Wechsel
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Gmail se connecte avec un mot de passe d’application — étapes à l’écran de connexion
• Salutations personnalisées avec champs : nom, moment de la journée…
• Widget Calendrier : tâches, missions et invitations
• Week-ends en couleur dans les widgets Calendrier
• Les photos des contacts ne disparaissent plus après un changement d’app
• Corrections et améliorations
</fr-FR>
```
