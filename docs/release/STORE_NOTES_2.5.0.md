# «Что нового» — 2.5.0 (152)

2.4.0 опубликована; 2.5.0 — всё, что сделано после неё: проекты с этапами
(PR #99), ящик поручения, «Важное», результат, сводка и отчёты (PR #100) и
работа 13.11.2026 (PR #102). Решение владельца 13.11.2026 — 2.5.0. Шаги
владельца — `OWNER_STEPS_2.5.0.md`.

## Сделано

### Поручения и проекты

- **Проекты с этапами.** У этапа — исполнитель, соисполнители, контролёр
  и наблюдатели; начало в свой день или «после этапа», чек-лист, файлы,
  шаблоны проектов. План — диаграммой Ганта (открывается на первом
  незавершённом этапе). Статус проекта — по этапам: все приняты — проект
  закрывается у постановщика; просроченный этап — проект в списке
  просрочен. Просроченные этапы можно сдвинуть вместе с последующими.
- **Общий план проекта** — «Все видят план и ход работ»: участники видят,
  кто что и после кого делает, и статусы этапов; по выбору постановщика —
  каждый видит только свои этапы.
- **Изменение поручений и проектов** — текст, этапы, сроки, файлы,
  удаление этапа; изменения доходят до всех участников.
- **Права постановщика другому человеку** — заместитель (оба могут
  принимать и изменять) или полная передача, например при смене.
- **Срок поручения — с временем**, не только днём: в карточке, в списке и
  в «Моём дне» — «до 18:00»; просрочено — с этой минуты.
- **Напоминания о сроке на телефоне**: в день срока, за час до срока со
  временем; постановщику — о просроченном поручении.
- **Статус доходит надёжнее.** У номера поручения в теме — код действия
  (`OGN-…-D` — принято, `-W` — взято в работу и т. д.): статус меняется,
  даже если почтовый сервер вырезал скрытую отметку из письма. Код
  проверяется по роли отправителя; ответы из других почтовых программ
  (без кода) разбираются по словам, как раньше.
- **Поручение закрывается у исполнителя**, когда постановщик принял работу
  (раньше могло остаться «На проверке»); зависшие «На проверке» закрываются
  сами при следующей проверке почты.
- **«Мой день»**: поручения, выполненные сегодня, — в колонке «Готово».

### Поручения: ящик, «Важное», результат, сводка и отчёты

Подобрано из Jira и Битрикс24 (`docs/architecture/ASSIGNMENT_UX_JIRA_BITRIX.md`).

- **Ящик поручения.** В карточке — «Отправлено с» или «Получено на»
  (портрет и адрес ящика); в «Поручить» и в редакторе проекта — выбор
  ящика, когда их несколько; в списке — значок ящика и фильтр «Все ящики /
  ящик»; в шапке проекта — ящик.
- **«Важное»** (как приоритет в Jira и «Важная задача» в Битрикс24): «!» в
  списке и карточке, важные — первыми, тема письма «Важное поручение»; у
  исполнителя поручение тоже «Важное».
- **Файлы при постановке** — вложениями письма и копией у себя.
- **«Готово» — с результатом и файлами**; в карточке блок «Результат»
  (текст, файлы, кто и когда). «Вернуть на доработку» — только с причиной;
  «Сообщить о ходе работ» — можно с файлами.
- **Фильтр «Помогаю»** (я соисполнитель); своя роль — в строке списка.
- **«Поручения → Сводка»**: действующие, просрочено, на проверке, выполнено
  за период, доля в срок, среднее время; полоса статусов; по людям;
  «Сроки» — диаграммой Ганта (просроченные первыми). Фильтры: «Я поручил /
  Мне поручили / Все», 30, 90 или 365 дней, ящик.
- **Сводка проекта**: этапы, просрочено, отклонение, дней до срока,
  статусы этапов, исполнители, план и факт по этапам.
- **«Отправить отчёт»** — новое письмо с кратким текстом и отчётом HTML во
  вложении (печатается в PDF).
- **Планшет и компьютер**: проект от 1000 точек — в две колонки (этапы
  слева; план, сводка, файлы и история справа); карточка этапа и редактор —
  колонкой читаемой ширины.

### Почта

- **«На контроле» и «Позже» — на всех устройствах.** Gmail, Яндекс,
  Mail.ru и другие IMAP-ящики — отметкой на самом письме, без дат: срок
  контроля и время возврата «Позже» остаются на устройстве, где их
  поставили. Exchange — флажком «К исполнению» с датами; в Outlook
  это обычный флажок «На контроле · OGN-C», снимут его там — отметка
  снимется везде. Выключается: «Расширенные настройки → Разделы
  приложения → На контроле → Отметки на всех устройствах». Сервер, который
  не хранит свои отметки, — отметки остаются на устройстве, без сообщений.
- **Вложения в письмах IMAP**, загруженных до 2.4.0, — видны; «Загрузить
  заново» берёт письмо с сервера.
- **Встроенные фото без ссылки из текста** (Gmail, Яндекс) — в списке
  вложений; скрепка в ленте без списка вложений — повод уточнить у
  сервера.
- **Шапки цитат**: у человека, указанного только по имени, — фото и
  карточка контакта.

### Платформы

- **Android 14+: новое встраивание окна письма (HCPP) — включено по
  умолчанию** (проверено владельцем). После сбоя в встраивании окон
  выключается само; включить снова — «Расширенные настройки → Графика».
- **Windows: переносная версия** — файл `portable.txt` рядом с
  `ogneliss.exe`: все данные — в папке `UserData` рядом с программой, а не
  в AppData. Сборка на GitHub выпускает `ogneliss-windows-portable.zip` с
  этим файлом. Ключи защищены Windows и привязаны к учётной записи.

Платформы: манифест Android, `Info.plist`, `project.pbxproj`,
`Runner.entitlements`, Podfile с 2.4.0 не менялись. Новые прямые
зависимости — только для Windows (`path_provider_windows`,
`shared_preferences_windows`, их интерфейсы и `ffi`; BSD-3-Clause, уже
были в сборке). База — схема 30, обновляется сама при первом запуске.

## Кратко (RU / EN)

**RU.** Проекты с этапами: роли, общий план с диаграммой Ганта, шаблоны.
Сводка и отчёты по поручениям, «Важное», выбор ящика, результат с файлами.
Поручения и проекты можно изменять, у постановщика может быть заместитель.
Сроки — с точным временем и напоминаниями на телефоне, статусы доходят
надёжнее. «На контроле» и «Позже» — на всех устройствах. На Windows —
переносная версия.

**EN.** Projects with stages: roles, a shared plan with a Gantt chart,
templates. Assignment summary and reports, Important, choice of mailbox, a
result with files. Assignments and projects can be edited, and assigners
can name a deputy. Deadlines with an exact time and phone reminders; statuses arrive
more reliably. Tracked and Later sync across all your devices. A portable
version for Windows.

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Поле «Что нового в этой версии» — для каждого языка своё.

```
<ru-RU>
• Проекты с этапами: роли, общий план, диаграмма Ганта, шаблоны
• «Сводка» поручений: сроки, просрочка, нагрузка по людям; отчёт письмом
• Поручения: «Важное», выбор ящика, «Результат» с файлами в ответе
• Поручения и проекты можно изменять; у постановщика может быть заместитель
• Срок — с точным временем и напоминанием на телефоне; статусы доходят надёжнее
• «Позже» и «На контроле» — на всех ваших устройствах
</ru-RU>
<en-US>
• Projects with stages: roles, a shared plan, Gantt chart, templates
• Assignment Summary: deadlines, overdue items, workload by person; reports by email
• Assignments: Important, choice of mailbox, a Result with files in replies
• Edit assignments and projects; assigners can name a deputy
• Deadlines with an exact time and phone reminders; statuses arrive more reliably
• Later and Tracked sync across all your devices
</en-US>
<de-DE>
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• „Übersicht“ der Aufträge: Fristen, Überfälliges, Auslastung je Person; Bericht per E-Mail
• Aufträge: „Wichtig“, Wahl des Postfachs, „Ergebnis“ mit Dateien in der Antwort
• Aufträge und Projekte bearbeiten; Auftraggeber können einen Stellvertreter benennen
• Fristen mit genauer Uhrzeit und Erinnerung auf dem Telefon; Status kommt zuverlässiger an
• „Später“ und „Im Blick“ auf all Ihren Geräten
</de-DE>
<fr-FR>
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• « Synthèse » des missions : échéances, retards, charge par personne ; rapport par e-mail
• Missions : « Important », choix de la boîte, « Résultat » avec fichiers dans la réponse
• Missions et projets modifiables ; le donneur d’ordre peut nommer un suppléant
• Échéances à l’heure près avec rappel sur le téléphone ; statuts plus fiables
• « Plus tard » et « Suivis » sur tous vos appareils
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков).

```
<ru-RU>
• Проекты с этапами: роли, общий план, диаграмма Ганта, шаблоны
• «Сводка» поручений: сроки, просрочка, нагрузка по людям; отчёт письмом
• Поручения: «Важное», выбор ящика, «Результат» с файлами в ответе
• Поручения и проекты можно изменять; у постановщика может быть заместитель
• Срок — с точным временем и напоминанием на телефоне; статусы доходят надёжнее
• «Позже» и «На контроле» — на всех ваших устройствах
</ru-RU>
<en-US>
• Projects with stages: roles, a shared plan, Gantt chart, templates
• Assignment Summary: deadlines, overdue items, workload by person; reports by email
• Assignments: Important, choice of mailbox, a Result with files in replies
• Edit assignments and projects; assigners can name a deputy
• Deadlines with an exact time and phone reminders; statuses arrive more reliably
• Later and Tracked sync across all your devices
</en-US>
<de-DE>
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• „Übersicht“ der Aufträge: Fristen, Überfälliges, Auslastung je Person; Bericht per E-Mail
• Aufträge: „Wichtig“, Wahl des Postfachs, „Ergebnis“ mit Dateien in der Antwort
• Aufträge und Projekte bearbeiten; Auftraggeber können einen Stellvertreter benennen
• Fristen mit genauer Uhrzeit und Erinnerung auf dem Telefon; Status kommt zuverlässiger an
• „Später“ und „Im Blick“ auf all Ihren Geräten
</de-DE>
<fr-FR>
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• « Synthèse » des missions : échéances, retards, charge par personne ; rapport par e-mail
• Missions : « Important », choix de la boîte, « Résultat » avec fichiers dans la réponse
• Missions et projets modifiables ; le donneur d’ordre peut nommer un suppléant
• Échéances à l’heure près avec rappel sur le téléphone ; statuts plus fiables
• « Plus tard » et « Suivis » sur tous vos appareils
</fr-FR>
<ar>
• مشاريع على مراحل: أدوار، وخطة مشتركة، ومخطط جانت، وقوالب
• «الملخص» للتكليفات: المواعيد والمتأخر وحِمل كل شخص؛ وتقرير بالبريد
• التكليفات: «مهم»، واختيار صندوق البريد، و«النتيجة» مع ملفات في الرد
• يمكن تعديل التكليفات والمشاريع؛ ويمكن لصاحب التكليف تعيين نائب
• مواعيد بالساعة الدقيقة مع تذكير على الهاتف؛ وتصل الحالات بموثوقية أكبر
• «لاحقًا» و«قيد المتابعة» على جميع أجهزتك
</ar>
<hu-HU>
• Szakaszokra bontott projektek: szerepek, közös terv, Gantt-diagram, sablonok
• A megbízások „Összesítő”-je: határidők, késések, terhelés személyenként; jelentés e-mailben
• Megbízások: „Fontos”, postafiók választása, „Eredmény” fájlokkal a válaszban
• A megbízások és projektek szerkeszthetők; a kiadónak lehet helyettese
• Határidő pontos időponttal és emlékeztetővel a telefonon; az állapot megbízhatóbban érkezik
• A „Később” és a „Követett” minden eszközén
</hu-HU>
<vi>
• Dự án theo giai đoạn: vai trò, kế hoạch chung, biểu đồ Gantt, mẫu
• «Tổng quan» việc giao: hạn, việc trễ, khối lượng theo người; gửi báo cáo qua email
• Việc giao: «Quan trọng», chọn hộp thư, «Kết quả» kèm tệp trong thư trả lời
• Sửa được việc giao và dự án; người giao có thể chỉ định người thay
• Hạn kèm giờ chính xác và nhắc trên điện thoại; trạng thái đến tin cậy hơn
• «Để sau» và «Đang theo dõi» trên mọi thiết bị của bạn
</vi>
<da-DK>
• Projekter med faser: roller, fælles plan, Gantt-diagram, skabeloner
• "Overblik" over opgaver: frister, forsinkelser, belastning pr. person; rapport på mail
• Opgaver: "Vigtig", valg af postkasse, "Resultat" med filer i svaret
• Tildelte opgaver og projekter kan redigeres; den, der tildeler, kan udpege en stedfortræder
• Frister med præcist klokkeslæt og påmindelse på telefonen; status når sikrere frem
• "Senere" og "Overvåget" på alle dine enheder
</da-DK>
<iw-IL>
• פרויקטים בשלבים: תפקידים, תוכנית משותפת, תרשים גאנט ותבניות
• "סיכום" מטלות: מועדים, איחורים, עומס לפי אדם; דוח במייל
• מטלות: "חשוב", בחירת תיבת דואר, "תוצאה" עם קבצים בתשובה
• אפשר לערוך מטלות ופרויקטים; למקצה יכול להיות ממלא מקום
• מועדים עם שעה מדויקת ותזכורת בטלפון; סטטוסים מגיעים בצורה אמינה יותר
• "מאוחר יותר" ו"במעקב" בכל המכשירים שלך
</iw-IL>
<id>
• Proyek bertahap: peran, rencana bersama, diagram Gantt, templat
• «Ringkasan» penugasan: tenggat, keterlambatan, beban per orang; laporan via email
• Penugasan: «Penting», pilihan kotak surat, «Hasil» dengan file di balasan
• Penugasan dan proyek bisa diedit; pemberi tugas bisa menunjuk wakil
• Tenggat dengan jam tepat dan pengingat di ponsel; status sampai lebih andal
• «Nanti» dan «Dipantau» di semua perangkat Anda
</id>
<es-ES>
• Proyectos por etapas: roles, plan compartido, diagrama de Gantt y plantillas
• «Resumen» de encargos: plazos, retrasos, carga por persona; informe por correo
• Encargos: «Importante», elección del buzón, «Resultado» con archivos en la respuesta
• Encargos y proyectos editables; quien asigna puede nombrar un suplente
• Plazos con hora exacta y recordatorio en el teléfono; estados más fiables
• «Más tarde» y «En seguimiento» en todos tus dispositivos
</es-ES>
<it-IT>
• Progetti a fasi: ruoli, piano condiviso, diagramma di Gantt, modelli
• «Riepilogo» degli incarichi: scadenze, ritardi, carico per persona; report via email
• Incarichi: «Importante», scelta della casella, «Risultato» con file nella risposta
• Incarichi e progetti modificabili; chi assegna può nominare un vice
• Scadenze con l’ora esatta e promemoria sul telefono; stati più affidabili
• «Più tardi» e «Monitorati» su tutti i tuoi dispositivi
</it-IT>
<zh-CN>
• 分阶段项目：角色、共享计划、甘特图和模板
• 任务分派“汇总”：截止时间、逾期、每人工作量；通过邮件发送报告
• 任务分派：“重要”标记、选择邮箱、回复中附带文件的“成果”
• 任务分派和项目可编辑；分派人可设代理
• 截止时间精确到时刻并在手机上提醒；状态送达更可靠
• “稍后”和“跟进中”在你的所有设备上同步
</zh-CN>
<ko-KR>
• 단계별 프로젝트: 역할, 공유 계획, 간트 차트, 템플릿
• 업무 지시 '요약': 기한, 지연, 사람별 업무량; 이메일로 보고서 전송
• 업무 지시: '중요' 표시, 메일함 선택, 답장에 파일과 함께 '결과'
• 업무 지시와 프로젝트 편집 가능; 지시자 대리인 지정
• 정확한 시각까지 기한 지정, 휴대폰 알림; 상태가 더 확실하게 전달
• '나중에'와 '추적 중'을 모든 기기에서
</ko-KR>
<nl-NL>
• Projecten met fasen: rollen, gedeeld plan, Gantt-diagram en sjablonen
• ‘Overzicht’ van opdrachten: deadlines, achterstand, werklast per persoon; rapport per e-mail
• Opdrachten: ‘Belangrijk’, keuze van mailbox, ‘Resultaat’ met bestanden in het antwoord
• Opdrachten en projecten bewerken; de opdrachtgever kan een plaatsvervanger aanwijzen
• Deadlines met exacte tijd en herinnering op je telefoon; status komt betrouwbaarder aan
• ‘Later’ en ‘In de gaten’ op al je apparaten
</nl-NL>
<no-NO>
• Prosjekter med faser: roller, felles plan, Gantt-diagram, maler
• «Oversikt» over oppdrag: frister, forsinkelser, belastning per person; rapport på e-post
• Oppdrag: «Viktig», valg av postkasse, «Resultat» med filer i svaret
• Oppdrag og prosjekter kan redigeres; oppdragsgiver kan utnevne en stedfortreder
• Frister med nøyaktig klokkeslett og påminnelse på telefonen; status kommer tryggere fram
• «Senere» og «Overvåket» på alle enhetene dine
</no-NO>
<pl-PL>
• Projekty z etapami: role, wspólny plan, wykres Gantta, szablony
• „Podsumowanie” zleceń: terminy, opóźnienia, obciążenie osób; raport e-mailem
• Zlecenia: „Ważne”, wybór skrzynki, „Wynik” z plikami w odpowiedzi
• Zlecenia i projekty można edytować; zlecający może wyznaczyć zastępcę
• Terminy z dokładną godziną i przypomnieniem w telefonie; statusy docierają pewniej
• „Później” i „Śledzone” na wszystkich Twoich urządzeniach
</pl-PL>
<pt-BR>
• Projetos em etapas: papéis, plano compartilhado, gráfico de Gantt e modelos
• "Resumo" das atribuições: prazos, atrasos, carga por pessoa; relatório por e-mail
• Atribuições: "Importante", escolha da caixa de e-mail, "Resultado" com arquivos na resposta
• Atribuições e projetos editáveis; quem atribui pode nomear um substituto
• Prazos com horário exato e lembrete no celular; status chegam com mais confiabilidade
• "Mais tarde" e "Em acompanhamento" em todos os seus dispositivos
</pt-BR>
<ro>
• Proiecte pe etape: roluri, plan comun, diagramă Gantt, șabloane
• „Rezumat” al sarcinilor: termene, întârzieri, încărcare pe persoană; raport pe e-mail
• Sarcini: „Important”, alegerea căsuței, „Rezultat” cu fișiere în răspuns
• Sarcinile și proiectele se pot modifica; cel care atribuie poate numi un înlocuitor
• Termene cu oră exactă și memento pe telefon; stările ajung mai sigur
• „Mai târziu” și „Urmărite” pe toate dispozitivele tale
</ro>
<sk>
• Projekty s etapami: roly, spoločný plán, Ganttov diagram, šablóny
• „Prehľad“ úloh: termíny, meškania, vyťaženie podľa ľudí; správa e-mailom
• Úlohy: „Dôležité“, výber schránky, „Výsledok“ so súbormi v odpovedi
• Zadané úlohy a projekty sa dajú upravovať; zadávateľ môže určiť zástupcu
• Termíny s presným časom a pripomenutím v telefóne; stavy prichádzajú spoľahlivejšie
• „Neskôr“ a „Sledované“ na všetkých vašich zariadeniach
</sk>
<th>
• โครงการแบบหลายขั้น: บทบาท แผนร่วม แผนภูมิแกนต์ และเทมเพลต
• «สรุป» งานมอบหมาย: กำหนดส่ง งานล่าช้า ภาระงานรายบุคคล ส่งรายงานทางอีเมล
• งานมอบหมาย: «สำคัญ» เลือกกล่องจดหมาย «ผลลัพธ์» พร้อมไฟล์ในการตอบกลับ
• แก้ไขงานมอบหมายและโครงการได้ ผู้มอบหมายแต่งตั้งผู้แทนได้
• กำหนดส่งระบุเวลาได้ พร้อมเตือนบนโทรศัพท์ สถานะส่งถึงได้แน่นอนขึ้น
• «ภายหลัง» และ «กำลังติดตาม» บนทุกอุปกรณ์ของคุณ
</th>
<tr-TR>
• Aşamalı projeler: roller, ortak plan, Gantt şeması, şablonlar
• Görevlendirme «Özet»i: son tarihler, gecikmeler, kişi başına iş yükü; e-postayla rapor
• Görevlendirmeler: «Önemli», posta kutusu seçimi, yanıtta dosyalarla «Sonuç»
• Görevlendirmeler ve projeler düzenlenebilir; görevlendiren bir vekil atayabilir
• Saatine kadar son tarih ve telefonda hatırlatma; durumlar daha güvenilir ulaşır
• «Daha sonra» ve «Takipte» tüm cihazlarınızda
</tr-TR>
<fi-FI>
• Vaiheittaiset projektit: roolit, yhteinen suunnitelma, Gantt-kaavio, mallipohjat
• Toimeksiantojen ”Yhteenveto”: määräajat, myöhästyneet, kuormitus henkilöittäin; raportti sähköpostilla
• Toimeksiannot: ”Tärkeä”, postilaatikon valinta, ”Tulos” ja tiedostot vastauksessa
• Toimeksiantoja ja projekteja voi muokata; antaja voi nimetä sijaisen
• Määräajat kellonajalla ja muistutus puhelimeen; tila välittyy luotettavammin
• ”Myöhemmin” ja ”Seurannassa” kaikilla laitteillasi
</fi-FI>
<hi-IN>
• चरणों वाले प्रोजेक्ट: भूमिकाएँ, साझा योजना, गैंट चार्ट और टेम्पलेट
• सौंपे गए कार्यों का «सारांश»: समय-सीमा, देरी, व्यक्ति के अनुसार काम; ईमेल से रिपोर्ट
• सौंपे गए कार्य: «ज़रूरी», मेलबॉक्स चुनें, जवाब में फ़ाइलों के साथ «परिणाम»
• सौंपे गए कार्य और प्रोजेक्ट संपादित करें; सौंपने वाला प्रतिनिधि चुन सकता है
• सटीक समय के साथ समय-सीमा और फ़ोन पर अनुस्मारक; स्थिति अधिक भरोसेमंद ढंग से पहुँचती है
• «बाद में» और «निगरानी में» आपके सभी डिवाइस पर
</hi-IN>
<cs-CZ>
• Projekty s etapami: role, společný plán, Ganttův diagram, šablony
• „Přehled“ úkolů: termíny, zpoždění, vytížení lidí; zpráva e-mailem
• Úkoly: „Důležité“, výběr schránky, „Výsledek“ se soubory v odpovědi
• Zadané úkoly a projekty lze upravovat; zadavatel může určit zástupce
• Termíny s přesným časem a připomenutím v telefonu; stavy dorazí spolehlivěji
• „Později“ a „Sledované“ na všech vašich zařízeních
</cs-CZ>
<sv-SE>
• Projekt i etapper: roller, gemensam plan, Gantt-schema, mallar
• ”Översikt” över uppdrag: deadlines, förseningar, belastning per person; rapport via mejl
• Uppdrag: ”Viktigt”, val av brevlåda, ”Resultat” med filer i svaret
• Redigera uppdrag och projekt; uppdragsgivaren kan utse en ställföreträdare
• Deadlines med exakt tid och påminnelse i telefonen; status kommer fram säkrare
• ”Senare” och ”Bevakade” på alla dina enheter
</sv-SE>
<ja-JP>
• 段階付きプロジェクト：役割、共有プラン、ガントチャート、テンプレート
• 依頼の「サマリー」：期限、遅延、担当者別の負荷。レポートをメールで送信
• 依頼：「重要」、送信メールボックスの選択、返信にファイル付きの「成果」
• 依頼とプロジェクトを編集可能。依頼者の代理も設定可能
• 期限を時刻まで指定し、スマートフォンでリマインド。ステータスがより確実に届く
• 「後で」と「追跡中」をすべてのデバイスで同期
</ja-JP>
```
