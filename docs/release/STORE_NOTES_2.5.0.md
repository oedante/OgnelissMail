# «Что нового» — 2.5.0 (152)

2.4.0 опубликована; 2.5.0 — всё, что сделано после неё: проекты с этапами
(PR #99) и работа 13.11.2026 (PR #102). Решение владельца 13.11.2026 —
2.5.0. Шаги владельца — `OWNER_STEPS_2.5.0.md`.

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

### Почта

- **«На контроле» и «Позже» — на всех устройствах.** Gmail, Яндекс,
  Mail.ru и другие IMAP-ящики — отметкой на самом письме, без дат: срок контроля и время возврата «Позже» остаются на устройстве,
  где их поставили. Exchange — флажком «К исполнению» с датами; в Outlook
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
Поручения и проекты можно изменять, у постановщика может быть заместитель.
Сроки — с точным временем и напоминаниями на телефоне, статусы доходят
надёжнее. «На контроле» и «Позже» — на всех устройствах. На Windows —
переносная версия.

**EN.** Projects with stages: roles, a shared plan with a Gantt chart,
templates. Assignments and projects can be edited, and assigners can name a
deputy. Deadlines with an exact time and phone reminders; statuses arrive
more reliably. Tracked and Later sync across all your devices. A portable
version for Windows.

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Поле «Что нового в этой версии» — для каждого языка своё.

```
<ru-RU>
• Проекты с этапами: роли участников, общий план, диаграмма Ганта, шаблоны
• Поручения и проекты можно изменять — изменения видят все; есть заместитель постановщика
• Срок поручения — с точным временем; напоминания о сроке на телефоне
• Статусы поручений доходят надёжнее; выполненные — в «Готово» «Моего дня»
• «Позже» и «На контроле» — на всех ваших устройствах
• Вложения и встроенные фото в письмах показываются надёжнее
</ru-RU>
<en-US>
• Projects with stages: participant roles, a shared plan, Gantt chart, templates
• Edit assignments and projects — everyone sees the changes; assigners can name a deputy
• Assignment deadlines with an exact time; deadline reminders on your phone
• Assignment statuses arrive more reliably; finished ones go to Done in My day
• Later and Tracked now sync across all your devices
• Attachments and inline photos in emails show up more reliably
</en-US>
<de-DE>
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• Aufträge und Projekte bearbeiten – alle sehen die Änderungen; Stellvertreter für Auftraggeber
• Fristen für Aufträge mit genauer Uhrzeit; Fristerinnerungen auf dem Telefon
• Auftragsstatus kommt zuverlässiger an; Erledigtes landet unter „Erledigt“ in „Mein Tag“
• „Später“ und „Im Blick“ auf all Ihren Geräten
• Anhänge und eingebettete Fotos werden zuverlässiger angezeigt
</de-DE>
<fr-FR>
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• Missions et projets modifiables : chacun voit les changements ; suppléant du donneur d’ordre
• Échéances des missions à l’heure près ; rappels d’échéance sur le téléphone
• Statuts des missions plus fiables ; les missions terminées vont dans « Terminé » de « Ma journée »
• « Plus tard » et « Suivis » sur tous vos appareils
• Pièces jointes et photos intégrées affichées de façon plus fiable
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков).

```
<ru-RU>
• Проекты с этапами: роли участников, общий план, диаграмма Ганта, шаблоны
• Поручения и проекты можно изменять — изменения видят все; есть заместитель постановщика
• Срок поручения — с точным временем; напоминания о сроке на телефоне
• Статусы поручений доходят надёжнее; выполненные — в «Готово» «Моего дня»
• «Позже» и «На контроле» — на всех ваших устройствах
• Вложения и встроенные фото в письмах показываются надёжнее
</ru-RU>
<en-US>
• Projects with stages: participant roles, a shared plan, Gantt chart, templates
• Edit assignments and projects — everyone sees the changes; assigners can name a deputy
• Assignment deadlines with an exact time; deadline reminders on your phone
• Assignment statuses arrive more reliably; finished ones go to Done in My day
• Later and Tracked now sync across all your devices
• Attachments and inline photos in emails show up more reliably
</en-US>
<de-DE>
• Projekte mit Phasen: Rollen, gemeinsamer Plan, Gantt-Diagramm, Vorlagen
• Aufträge und Projekte bearbeiten – alle sehen die Änderungen; Stellvertreter für Auftraggeber
• Fristen für Aufträge mit genauer Uhrzeit; Fristerinnerungen auf dem Telefon
• Auftragsstatus kommt zuverlässiger an; Erledigtes landet unter „Erledigt“ in „Mein Tag“
• „Später“ und „Im Blick“ auf all Ihren Geräten
• Anhänge und eingebettete Fotos werden zuverlässiger angezeigt
</de-DE>
<fr-FR>
• Projets par étapes : rôles, plan partagé, diagramme de Gantt, modèles
• Missions et projets modifiables : chacun voit les changements ; suppléant du donneur d’ordre
• Échéances des missions à l’heure près ; rappels d’échéance sur le téléphone
• Statuts des missions plus fiables ; les missions terminées vont dans « Terminé » de « Ma journée »
• « Plus tard » et « Suivis » sur tous vos appareils
• Pièces jointes et photos intégrées affichées de façon plus fiable
</fr-FR>
<ar>
• مشاريع على مراحل: أدوار، وخطة مشتركة، ومخطط جانت، وقوالب
• يمكن تعديل التكليفات والمشاريع — يرى الجميع التغييرات؛ ويمكن تعيين نائب لصاحب التكليف
• مواعيد التكليفات بالساعة الدقيقة؛ وتذكيرات بالموعد على الهاتف
• تصل حالات التكليفات بموثوقية أكبر؛ والمنجزة تظهر في «تم» ضمن «يومي»
• «لاحقًا» و«قيد المتابعة» على جميع أجهزتك
• تظهر المرفقات والصور المضمّنة بموثوقية أكبر
</ar>
<hu-HU>
• Szakaszokra bontott projektek: szerepek, közös terv, Gantt-diagram, sablonok
• A megbízások és projektek szerkeszthetők – mindenki látja a változást; a kiadónak lehet helyettese
• Határidő pontos időponttal; határidő-emlékeztető a telefonon
• A megbízások állapota megbízhatóbban érkezik; a teljesítettek a „Saját napom” „Kész” oszlopába kerülnek
• A „Később” és a „Követett” minden eszközén
• A mellékletek és a beágyazott fotók megbízhatóbban jelennek meg
</hu-HU>
<vi>
• Dự án theo giai đoạn: vai trò, kế hoạch chung, biểu đồ Gantt, mẫu
• Sửa việc giao và dự án — mọi người đều thấy thay đổi; người giao có thể có người thay
• Hạn việc giao kèm giờ chính xác; nhắc hạn trên điện thoại
• Trạng thái việc giao đến tin cậy hơn; việc đã xong vào mục «Xong» trong «Ngày của tôi»
• «Để sau» và «Đang theo dõi» trên mọi thiết bị của bạn
• Tệp đính kèm và ảnh nhúng hiển thị tin cậy hơn
</vi>
<da-DK>
• Projekter med faser: roller, fælles plan, Gantt-diagram, skabeloner
• Tildelte opgaver og projekter kan redigeres – alle ser ændringerne; stedfortræder for den, der tildeler
• Frister med præcist klokkeslæt; påmindelser om frist på telefonen
• Status for opgaver når frem mere pålideligt; udførte vises under "Færdig" i "Min dag"
• "Senere" og "Overvåget" på alle dine enheder
• Vedhæftede filer og indlejrede billeder vises mere pålideligt
</da-DK>
<iw-IL>
• פרויקטים בשלבים: תפקידים, תוכנית משותפת, תרשים גאנט ותבניות
• אפשר לערוך מטלות ופרויקטים — כולם רואים את השינויים; ממלא מקום למי שמקצה
• מועדי מטלות עם שעה מדויקת; תזכורות למועד בטלפון
• סטטוס המטלות מגיע בצורה אמינה יותר; מטלות שהושלמו עוברות ל"הושלם" ב"היום שלי"
• "מאוחר יותר" ו"במעקב" בכל המכשירים שלך
• קבצים מצורפים ותמונות מוטמעות מוצגים בצורה אמינה יותר
</iw-IL>
<id>
• Proyek bertahap: peran, rencana bersama, diagram Gantt, templat
• Penugasan dan proyek bisa diedit — semua melihat perubahannya; pemberi tugas bisa punya wakil
• Tenggat dengan jam yang tepat; pengingat tenggat di ponsel
• Status penugasan sampai lebih andal; yang selesai masuk ke «Selesai» di «Hari saya»
• «Nanti» dan «Dipantau» di semua perangkat Anda
• Lampiran dan foto tersemat tampil lebih andal
</id>
<es-ES>
• Proyectos por etapas: roles, plan compartido, diagrama de Gantt y plantillas
• Encargos y proyectos editables: todos ven los cambios; suplente de quien asigna
• Plazos de encargos con hora exacta; recordatorios del plazo en el teléfono
• Los estados de los encargos llegan con más fiabilidad; los terminados, en «Hecho» de «Mi día»
• «Más tarde» y «En seguimiento» en todos tus dispositivos
• Adjuntos y fotos insertadas se muestran con más fiabilidad
</es-ES>
<it-IT>
• Progetti a fasi: ruoli, piano condiviso, diagramma di Gantt, modelli
• Incarichi e progetti modificabili: tutti vedono le modifiche; un vice per chi assegna
• Scadenze degli incarichi con l’ora esatta; promemoria della scadenza sul telefono
• Gli stati degli incarichi arrivano in modo più affidabile; i conclusi in «Completati» di «Il mio giorno»
• «Più tardi» e «Monitorati» su tutti i tuoi dispositivi
• Allegati e foto incorporate si vedono in modo più affidabile
</it-IT>
<zh-CN>
• 分阶段项目：角色、共享计划、甘特图和模板
• 任务分派和项目可编辑，所有人都能看到更改；分派人可设代理
• 截止时间可精确到时刻；手机上提醒截止时间
• 任务分派状态送达更可靠；已完成的移至“我的一天”的“已完成”
• “稍后”和“跟进中”在你的所有设备上同步
• 附件和内嵌图片显示更可靠
</zh-CN>
<ko-KR>
• 단계별 프로젝트: 역할, 공유 계획, 간트 차트, 템플릿
• 업무 지시와 프로젝트 편집 가능 — 변경 내용은 모두에게 표시; 지시자 대리인 지정
• 기한을 정확한 시각까지 지정; 휴대폰에서 기한 알림
• 업무 지시 상태가 더 확실하게 전달; 완료된 항목은 '오늘 일정'의 '완료'로
• '나중에'와 '추적 중'을 모든 기기에서
• 첨부 파일과 본문 사진이 더 확실하게 표시
</ko-KR>
<nl-NL>
• Projecten met fasen: rollen, gedeeld plan, Gantt-diagram en sjablonen
• Opdrachten en projecten bewerken — iedereen ziet de wijzigingen; plaatsvervanger van de opdrachtgever
• Deadlines met exacte tijd; deadlineherinneringen op je telefoon
• Status van opdrachten komt betrouwbaarder aan; afgeronde staan onder ‘Klaar’ in ‘Mijn dag’
• ‘Later’ en ‘In de gaten’ op al je apparaten
• Bijlagen en ingesloten foto’s worden betrouwbaarder getoond
</nl-NL>
<no-NO>
• Prosjekter med faser: roller, felles plan, Gantt-diagram, maler
• Oppdrag og prosjekter kan redigeres – alle ser endringene; stedfortreder for oppdragsgiver
• Frister med nøyaktig klokkeslett; fristpåminnelser på telefonen
• Status for oppdrag kommer tryggere fram; fullførte havner under «Ferdig» i «Min dag»
• «Senere» og «Overvåket» på alle enhetene dine
• Vedlegg og innebygde bilder vises mer pålitelig
</no-NO>
<pl-PL>
• Projekty z etapami: role, wspólny plan, wykres Gantta, szablony
• Zlecenia i projekty można edytować — wszyscy widzą zmiany; zastępca zlecającego
• Terminy zleceń z dokładną godziną; przypomnienia o terminie w telefonie
• Statusy zleceń docierają pewniej; wykonane trafiają do „Gotowe” w „Mój dzień”
• „Później” i „Śledzone” na wszystkich Twoich urządzeniach
• Załączniki i osadzone zdjęcia wyświetlają się pewniej
</pl-PL>
<pt-BR>
• Projetos em etapas: papéis, plano compartilhado, gráfico de Gantt e modelos
• Atribuições e projetos editáveis — todos veem as mudanças; substituto de quem atribui
• Prazos com horário exato; lembretes de prazo no celular
• Status das atribuições chegam com mais confiabilidade; as concluídas vão para "Concluído" em "Meu dia"
• "Mais tarde" e "Em acompanhamento" em todos os seus dispositivos
• Anexos e fotos incorporadas aparecem com mais confiabilidade
</pt-BR>
<ro>
• Proiecte pe etape: roluri, plan comun, diagramă Gantt, șabloane
• Sarcinile și proiectele se pot modifica — toți văd schimbările; înlocuitor pentru cel care atribuie
• Termene cu oră exactă; mementouri de termen pe telefon
• Stările sarcinilor ajung mai sigur; cele terminate apar la „Finalizat” în „Ziua mea”
• „Mai târziu” și „Urmărite” pe toate dispozitivele tale
• Atașamentele și fotografiile încorporate se afișează mai sigur
</ro>
<sk>
• Projekty s etapami: roly, spoločný plán, Ganttov diagram, šablóny
• Zadané úlohy a projekty sa dajú upravovať — zmeny vidia všetci; zástupca zadávateľa
• Termíny úloh s presným časom; pripomenutia termínu v telefóne
• Stavy úloh prichádzajú spoľahlivejšie; splnené sú v „Hotovo“ v „Môj deň“
• „Neskôr“ a „Sledované“ na všetkých vašich zariadeniach
• Prílohy a vložené fotky sa zobrazujú spoľahlivejšie
</sk>
<th>
• โครงการแบบหลายขั้น: บทบาท แผนร่วม แผนภูมิแกนต์ และเทมเพลต
• แก้ไขงานมอบหมายและโครงการได้ ทุกคนเห็นการเปลี่ยนแปลง ผู้มอบหมายมีผู้แทนได้
• กำหนดส่งระบุเวลาได้ พร้อมการเตือนกำหนดส่งบนโทรศัพท์
• สถานะงานมอบหมายส่งถึงได้แน่นอนขึ้น งานที่เสร็จอยู่ใน «เสร็จแล้ว» ของ «วันของฉัน»
• «ภายหลัง» และ «กำลังติดตาม» บนทุกอุปกรณ์ของคุณ
• ไฟล์แนบและรูปภาพในเนื้อหาแสดงได้แน่นอนขึ้น
</th>
<tr-TR>
• Aşamalı projeler: roller, ortak plan, Gantt şeması, şablonlar
• Görevlendirmeler ve projeler düzenlenebilir — herkes değişiklikleri görür; görevlendirene vekil
• Saatine kadar son tarih; telefonda son tarih hatırlatıcıları
• Görev durumları daha güvenilir ulaşır; bitenler «Günüm» içinde «Tamamlandı» bölümüne geçer
• «Daha sonra» ve «Takipte» tüm cihazlarınızda
• Ekler ve gömülü fotoğraflar daha güvenilir görünür
</tr-TR>
<fi-FI>
• Vaiheittaiset projektit: roolit, yhteinen suunnitelma, Gantt-kaavio, mallipohjat
• Toimeksiantoja ja projekteja voi muokata – kaikki näkevät muutokset; antajalle sijainen
• Määräajat tarkalla kellonajalla; määräaikamuistutukset puhelimeen
• Toimeksiantojen tila välittyy luotettavammin; valmiit näkyvät ”Oma päivä” -näkymän ”Valmis”-kohdassa
• ”Myöhemmin” ja ”Seurannassa” kaikilla laitteillasi
• Liitteet ja upotetut kuvat näkyvät luotettavammin
</fi-FI>
<hi-IN>
• चरणों वाले प्रोजेक्ट: भूमिकाएँ, साझा योजना, गैंट चार्ट और टेम्पलेट
• सौंपे गए कार्य और प्रोजेक्ट संपादित करें — बदलाव सबको दिखते हैं; सौंपने वाले का प्रतिनिधि
• सटीक समय के साथ समय-सीमा; फ़ोन पर समय-सीमा अनुस्मारक
• सौंपे गए कार्यों की स्थिति अधिक भरोसेमंद ढंग से पहुँचती है; पूरे हुए कार्य «मेरा दिन» के «पूरा हुआ» में
• «बाद में» और «निगरानी में» आपके सभी डिवाइस पर
• अटैचमेंट और एम्बेड की गई फ़ोटो अधिक भरोसेमंद ढंग से दिखती हैं
</hi-IN>
<cs-CZ>
• Projekty s etapami: role, společný plán, Ganttův diagram, šablony
• Zadané úkoly a projekty lze upravovat — změny vidí všichni; zástupce zadavatele
• Termíny úkolů s přesným časem; připomenutí termínu v telefonu
• Stavy úkolů dorazí spolehlivěji; splněné jsou v „Hotovo“ v „Můj den“
• „Později“ a „Sledované“ na všech vašich zařízeních
• Přílohy a vložené fotky se zobrazují spolehlivěji
</cs-CZ>
<sv-SE>
• Projekt i etapper: roller, gemensam plan, Gantt-schema, mallar
• Redigera uppdrag och projekt – alla ser ändringarna; ställföreträdare för uppdragsgivaren
• Deadlines med exakt tid; påminnelser om deadline i telefonen
• Uppdragens status kommer fram säkrare; klara hamnar under ”Klart” i ”Min dag”
• ”Senare” och ”Bevakade” på alla dina enheter
• Bilagor och inbäddade foton visas säkrare
</sv-SE>
<ja-JP>
• 段階付きプロジェクト：役割、共有プラン、ガントチャート、テンプレート
• 依頼とプロジェクトを編集可能。変更は全員に反映。依頼者の代理も設定可能
• 期限を時刻まで指定。スマートフォンで期限をリマインド
• 依頼のステータスがより確実に届くように。完了した依頼は「今日の予定」の「完了」へ
• 「後で」と「追跡中」をすべてのデバイスで同期
• 添付ファイルと埋め込み写真がより確実に表示されるように
</ja-JP>
```
