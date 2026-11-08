# «Что нового» — 1.15.2 (143)

Номер — ответ владельца 08.11.2026 («Заканчивай виджеты и присылай архив
для сборки»; выбран 1.15.2 (143), 1.15.1 (142) остаётся как есть). Что
вошло в 1.15.1 и раньше — `STORE_NOTES_1.15.1.md`. Тексты для магазинов —
только новое.

Добавлено и исправлено в 1.15.2:

- **Виджеты** (план 08.11.2026, раздел 8, решение владельца «Виджеты —
  согласен»):
  - «Почта»: «Прочитано» и «В архив» у письма прямо в виджете (Android;
    iPhone — iOS 17+), строка текста письма, значки вложения, флажка, VIP;
  - свой фильтр у каждого виджета «Почта»: все, VIP, с флажком, «На
    контроле» или один ящик. Android — выбор при добавлении и «Настроить»
    в меню виджета; iPhone (iOS 17+) — новый виджет «Почта: выбор», обычный
    «Почта» показывает выбранное в «Настройки → Общие»;
  - новый виджет «Задачи»: открытые задачи, просроченные — первыми,
    галочка «Выполнено», «+» — новая задача (Android — окно «Создать» в
    режиме задачи);
  - «Мой день»: галочка «Выполнено» у задач;
  - Android: мини-виджет 1×1 «Непрочитанные»;
  - iPhone: виджеты экрана блокировки и StandBy (iOS 16+) — число
    непрочитанных и последнее письмо, скрываются по настройке «Данные на
    заблокированном экране».
- **Фоновая работа** (вопрос владельца 08.11: «не мешают ли друг другу
  пробуждение, сигнал сервера и Firebase»): письма, полученные фоновой
  задачей, сразу видны в открытом списке (раньше — только после
  перезапуска процесса); фоновая задача больше не «теряет» приложение,
  если то ответило медленно; проверка при открытии приложения больше не
  пропускается — ни из-за идущей фоновой задачи (ждёт её до минуты), ни
  из-за недавнего тика таймера или идущей плановой проверки; сторож EAS
  push не обрывает исправный долгий Ping. Подробно — PR и
  `docs/guides/BACKGROUND_WAKE.md`.
- **Закрепление сертификатов** (решение владельца 08.11): правила
  администратора («Безопасность → Закрепление сертификатов») проверяются
  всегда — и когда сертификат принят системой (ЦС из профиля на
  устройстве); сертификат, принятый пользователем в «Доверять?», — только
  при ошибке системной проверки.
- **Exchange**: Autodiscover больше не отправляет пароль в первом запросе
  (только серверу, который попросил вход); блокировка устройства, предел
  числа устройств и отключённый ActiveSync — понятной ошибкой при входе,
  без повторных Provision.
- **Для организаций (MDM)**: `allowed_domains` действует и на уже
  добавленные ящики — ящик чужого домена скрыт и не синхронизируется,
  данные остаются; в «Настройках» — пояснение (27 языков).
- **Безопасность**: подтверждение перед входом без шифрования; при
  PIN-коде — размытие содержимого в переключателе приложений iPhone;
  надёжнее чтение ключа PIN из хранилища Android.
- **Скорость**: крупные части писем IMAP разбираются вне главного потока.
- **Отображение писем** (08.11): длинная строка без пробелов в таблице
  (рамка «=====» у предупреждения Outlook о внешнем отправителе) больше не
  выводит письмо за правый край после «Показать цитируемую переписку» —
  разделитель одной строкой по ширине, длинное слово переносится; уже
  тёмные рассылки в тёмной теме не инвертируются, фоновые картинки из
  стилей письма — не негативом; цитата не сворачивается, если под ней
  ответ; в письмах без HTML свёрнуты строки «>» и длинная подпись «-- ».

Зависимости: новых пакетов нет. Платформы: `project.pbxproj`,
`Runner.entitlements`, `Info.plist` не менялись; в Xcode включать ничего не
нужно. Android: в манифесте — виджет «Задачи», мини-виджет и окно выбора
фильтра «Почты», новых разрешений нет.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Виджеты: «Прочитано» и «В архив» прямо в «Почте», галочка у задач (iOS 17)
• Новые виджеты: «Задачи» и «Почта: выбор» — свой ящик или фильтр (iOS 17)
• Экран блокировки: непрочитанные и последнее письмо
• Письма, полученные в фоне, сразу видны в списке
</ru-RU>
<en-US>
• Widgets: Read and Archive right in the Mail widget, a check for tasks (iOS 17)
• New widgets: Tasks and “Mail: choose” with its own mailbox or filter (iOS 17)
• Lock Screen: unread count and the latest email
• Mail received in the background shows up in the list right away
</en-US>
<de-DE>
• Widgets: „Gelesen“ und „Archivieren“ direkt im E-Mail-Widget, Häkchen für Aufgaben (iOS 17)
• Neue Widgets: Aufgaben und „E-Mail: Auswahl“ mit eigenem Postfach oder Filter (iOS 17)
• Sperrbildschirm: Ungelesene und die neueste E-Mail
• Im Hintergrund empfangene E-Mails erscheinen sofort in der Liste
</de-DE>
<fr-FR>
• Widgets : « Lu » et « Archiver » directement dans le widget Courrier, case pour les tâches (iOS 17)
• Nouveaux widgets : Tâches et « Courrier : au choix » avec sa boîte ou son filtre (iOS 17)
• Écran verrouillé : non lus et dernier message
• Les messages reçus en arrière-plan apparaissent aussitôt dans la liste
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 480.

```
<ru-RU>
• Виджеты: «Прочитано» и «В архив» прямо в «Почте», галочка у задач
• Новый виджет «Задачи» и мини-виджет «Непрочитанные» 1×1
• У каждого виджета «Почта» — свой фильтр: VIP, с флажком или один ящик
• Письма, полученные в фоне, сразу видны в списке
</ru-RU>
<en-US>
• Widgets: Read and Archive right in the Mail widget, a check for tasks
• New Tasks widget and a 1×1 Unread widget
• Each Mail widget can show its own filter: VIP, flagged or one mailbox
• Mail received in the background shows up in the list right away
</en-US>
<de-DE>
• Widgets: „Gelesen“ und „Archivieren“ direkt im E-Mail-Widget, Häkchen für Aufgaben
• Neues Aufgaben-Widget und 1×1-Widget „Ungelesen“
• Jedes E-Mail-Widget mit eigenem Filter: VIP, markiert oder ein Postfach
• Im Hintergrund empfangene E-Mails erscheinen sofort in der Liste
</de-DE>
<fr-FR>
• Widgets : « Lu » et « Archiver » directement dans le widget Courrier, case pour les tâches
• Nouveau widget Tâches et widget 1×1 Non lus
• Chaque widget Courrier peut avoir son filtre : VIP, suivis ou une boîte
• Les messages reçus en arrière-plan apparaissent aussitôt dans la liste
</fr-FR>
<ar>
• الأدوات: «مقروء» و«أرشفة» مباشرةً في أداة البريد، وعلامة إنجاز للمهام
• أداة «المهام» الجديدة وأداة «غير المقروءة» بحجم 1×1
• لكل أداة بريد عامل تصفية خاص: VIP أو المميَّزة أو صندوق واحد
• الرسائل المستلمة في الخلفية تظهر فورًا في القائمة
</ar>
<hu-HU>
• Modulok: „Olvasott” és „Archiválás” közvetlenül a Levelek modulban, pipa a feladatoknál
• Új Feladatok modul és 1×1-es Olvasatlan modul
• Minden Levelek modul saját szűrővel: VIP, megjelölt vagy egy fiók
• A háttérben érkezett levelek azonnal megjelennek a listában
</hu-HU>
<vi>
• Tiện ích: “Đã đọc” và “Lưu trữ” ngay trong tiện ích Thư, dấu tích cho công việc
• Tiện ích Công việc mới và tiện ích Chưa đọc 1×1
• Mỗi tiện ích Thư có bộ lọc riêng: VIP, gắn cờ hoặc một hộp thư
• Thư nhận ở chế độ nền hiện ngay trong danh sách
</vi>
<da-DK>
• Widgets: “Læst” og “Arkivér” direkte i Mail-widgetten, flueben ved opgaver
• Ny Opgaver-widget og 1×1-widget Ulæste
• Hver Mail-widget kan have sit eget filter: VIP, markeret eller én postkasse
• Mail modtaget i baggrunden vises straks på listen
</da-DK>
<iw-IL>
• ווידג׳טים: „נקרא” ו„העברה לארכיון” ישירות בווידג׳ט הדואר, סימון למשימות
• ווידג׳ט „משימות” חדש וווידג׳ט „לא נקראו” בגודל 1×1
• לכל ווידג׳ט דואר מסנן משלו: VIP, מסומן בדגל או תיבה אחת
• דואר שהתקבל ברקע מופיע מיד ברשימה
</iw-IL>
<id>
• Widget: “Dibaca” dan “Arsipkan” langsung di widget Email, centang untuk tugas
• Widget Tugas baru dan widget Belum dibaca 1×1
• Setiap widget Email bisa punya filter sendiri: VIP, ditandai, atau satu kotak surat
• Email yang diterima di latar belakang langsung muncul di daftar
</id>
<es-ES>
• Widgets: «Leído» y «Archivar» directamente en el widget Correo, casilla para tareas
• Nuevo widget Tareas y widget No leídos de 1×1
• Cada widget Correo con su propio filtro: VIP, marcados o un buzón
• El correo recibido en segundo plano aparece al instante en la lista
</es-ES>
<it-IT>
• Widget: «Letto» e «Archivia» direttamente nel widget Posta, spunta per le attività
• Nuovo widget Attività e widget Non letti 1×1
• Ogni widget Posta può avere il suo filtro: VIP, contrassegnati o una casella
• La posta ricevuta in background compare subito nell’elenco
</it-IT>
<zh-CN>
• 小组件：在“邮件”小组件中直接“已读”和“归档”，任务可直接勾选完成
• 新增“任务”小组件和 1×1“未读”小组件
• 每个“邮件”小组件可设置自己的筛选：VIP、已标记或单个邮箱
• 后台收到的邮件会立即显示在列表中
</zh-CN>
<ko-KR>
• 위젯: 메일 위젯에서 바로 '읽음'과 '보관', 할 일 체크
• 새 할 일 위젯과 1×1 읽지 않음 위젯
• 메일 위젯마다 필터 선택: VIP, 플래그 또는 메일함 하나
• 백그라운드에서 받은 메일이 목록에 바로 표시됩니다
</ko-KR>
<nl-NL>
• Widgets: ‘Gelezen’ en ‘Archiveren’ direct in de Mail-widget, vinkje bij taken
• Nieuwe Taken-widget en 1×1-widget Ongelezen
• Elke Mail-widget een eigen filter: VIP, gemarkeerd of één postvak
• Op de achtergrond ontvangen mail staat meteen in de lijst
</nl-NL>
<no-NO>
• Moduler: «Lest» og «Arkiver» rett i E-post-modulen, hake ved oppgaver
• Ny Oppgaver-modul og 1×1-modul Uleste
• Hver E-post-modul kan ha eget filter: VIP, flagget eller én postkasse
• E-post mottatt i bakgrunnen vises straks i listen
</no-NO>
<pl-PL>
• Widżety: „Przeczytane” i „Archiwizuj” wprost w widżecie Poczta, ptaszek przy zadaniach
• Nowy widżet Zadania i widżet 1×1 Nieprzeczytane
• Każdy widżet Poczta z własnym filtrem: VIP, oflagowane lub jedna skrzynka
• Poczta odebrana w tle od razu pojawia się na liście
</pl-PL>
<pt-BR>
• Widgets: “Lido” e “Arquivar” direto no widget E-mail, marcação de tarefas
• Novo widget Tarefas e widget Não lidos 1×1
• Cada widget E-mail com seu próprio filtro: VIP, sinalizados ou uma caixa
• E-mails recebidos em segundo plano aparecem na hora na lista
</pt-BR>
<ro>
• Widgeturi: „Citit” și „Arhivează” direct în widgetul E-mail, bifă pentru sarcini
• Widget nou Sarcini și widget 1×1 Necitite
• Fiecare widget E-mail cu propriul filtru: VIP, marcate sau o căsuță
• E-mailurile primite în fundal apar imediat în listă
</ro>
<sk>
• Widgety: „Prečítané“ a „Archivovať“ priamo vo widgete Pošta, zaškrtnutie úloh
• Nový widget Úlohy a widget 1×1 Neprečítané
• Každý widget Pošta s vlastným filtrom: VIP, označené alebo jedna schránka
• Pošta prijatá na pozadí sa hneď zobrazí v zozname
</sk>
<th>
• วิดเจ็ต: “อ่านแล้ว” และ “เก็บถาวร” ในวิดเจ็ตอีเมลโดยตรง ติ๊กงานได้
• วิดเจ็ตงานใหม่ และวิดเจ็ตยังไม่อ่านขนาด 1×1
• วิดเจ็ตอีเมลแต่ละอันมีตัวกรองของตัวเอง: VIP ติดธง หรือกล่องจดหมายเดียว
• อีเมลที่ได้รับในเบื้องหลังจะแสดงในรายการทันที
</th>
<tr-TR>
• Widget’lar: Posta widget’ında doğrudan “Okundu” ve “Arşivle”, görevler için onay
• Yeni Görevler widget’ı ve 1×1 Okunmamış widget’ı
• Her Posta widget’ı kendi filtresiyle: VIP, işaretli veya tek posta kutusu
• Arka planda gelen e-postalar listede hemen görünür
</tr-TR>
<fi-FI>
• Widgetit: ”Luettu” ja ”Arkistoi” suoraan Posti-widgetissä, valintamerkki tehtäville
• Uusi Tehtävät-widget ja 1×1-widget Lukemattomat
• Jokaiselle Posti-widgetille oma suodatin: VIP, liputetut tai yksi postilaatikko
• Taustalla saapunut posti näkyy heti luettelossa
</fi-FI>
<hi-IN>
• विजेट: मेल विजेट में सीधे “पढ़ा गया” और “संग्रहित करें”, कार्यों पर टिक
• नया कार्य विजेट और 1×1 अपठित विजेट
• हर मेल विजेट का अपना फ़िल्टर: VIP, फ़्लैग किए गए या एक मेलबॉक्स
• बैकग्राउंड में आई मेल सूची में तुरंत दिखती है
</hi-IN>
<cs-CZ>
• Widgety: „Přečteno“ a „Archivovat“ přímo ve widgetu Pošta, zaškrtnutí úkolů
• Nový widget Úkoly a widget 1×1 Nepřečtené
• Každý widget Pošta s vlastním filtrem: VIP, s příznakem nebo jedna schránka
• Pošta přijatá na pozadí se hned zobrazí v seznamu
</cs-CZ>
<sv-SE>
• Widgetar: ”Läst” och ”Arkivera” direkt i Mejl-widgeten, bock för uppgifter
• Ny Uppgifter-widget och 1×1-widget Olästa
• Varje Mejl-widget kan ha eget filter: VIP, flaggade eller en brevlåda
• Mejl som tagits emot i bakgrunden syns direkt i listan
</sv-SE>
<ja-JP>
• ウィジェット：メールウィジェットで直接「既読」「アーカイブ」、タスクにチェック
• 新しい「タスク」ウィジェットと 1×1「未読」ウィジェット
• メールウィジェットごとにフィルタを設定：VIP、フラグ付き、1つのメールボックス
• バックグラウンドで受信したメールがすぐ一覧に表示
</ja-JP>
```
