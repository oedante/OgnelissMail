# «Что нового» — 2.1.0 (145)

Номер — решение владельца 08.11.2026 (после исправления сборки, PR #59):
2.1.0 (145) — это 2.0.0 (144) с исправленной сборкой; у приложения для
пользователей нового нет. Тексты для магазинов — те же, что у 2.0.0
(решение владельца; подробный список изменений — `STORE_NOTES_2.0.0.md`).
Что сделать владельцу — `OWNER_STEPS_2.1.0.md`.

Добавлено в 2.1.0 (сборка, в приложении не видно):

- **Сборка у владельца**: `flutter analyze` и компиляция падали на
  `zip_view.dart` («writeRange isn't defined in a superclass») —
  `pubspec.lock` держал archive 4.5.2, а код написан под 4.6. Теперь
  `pubspec.yaml` требует archive ^4.6.0.
- **Скрипты сборки**: новый `build_android.bat` (`scripts/build_android.ps1`,
  на Mac и Linux — `scripts/build_android.sh`) — App Bundle и APK одной
  командой, копии в `build/out/`; скрипты Android, iPhone и Windows ставят
  пакеты тех же версий, что сборка на GitHub (`flutter pub upgrade`).
- «[SEVERE] RustBuilder: Failed to find lib.name» при сборке — не ошибка
  (native_toolchain_rust 1.0.6 берёт package.name и продолжает).

Зависимости: новых пакетов нет. Платформы: `project.pbxproj`,
`Runner.entitlements`, `Info.plist` и манифест Android не менялись.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Виджеты: «Прочитано» и «В архив» прямо в «Почте», галочка у задач (iOS 17)
• Новые виджеты: «Задачи» и «Почта: выбор» — свой ящик или фильтр (iOS 17)
• Экран блокировки: непрочитанные и последнее письмо
• Письма, полученные в фоне, сразу видны в списке
• Настройки — 8 понятных разделов
</ru-RU>
<en-US>
• Widgets: Read and Archive right in the Mail widget, a check for tasks (iOS 17)
• New widgets: Tasks and “Mail: choose” with its own mailbox or filter (iOS 17)
• Lock Screen: unread count and the latest email
• Mail received in the background shows up in the list right away
• Settings in 8 clear sections
</en-US>
<de-DE>
• Widgets: „Gelesen“ und „Archivieren“ direkt im E-Mail-Widget, Häkchen für Aufgaben (iOS 17)
• Neue Widgets: Aufgaben und „E-Mail: Auswahl“ mit eigenem Postfach oder Filter (iOS 17)
• Sperrbildschirm: Ungelesene und die neueste E-Mail
• Im Hintergrund empfangene E-Mails erscheinen sofort in der Liste
• Einstellungen in 8 klaren Bereichen
</de-DE>
<fr-FR>
• Widgets : « Lu » et « Archiver » directement dans le widget Courrier, case pour les tâches (iOS 17)
• Nouveaux widgets : Tâches et « Courrier : au choix » avec sa boîte ou son filtre (iOS 17)
• Écran verrouillé : non lus et dernier message
• Les messages reçus en arrière-plan apparaissent aussitôt dans la liste
• Réglages en 8 sections claires
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
