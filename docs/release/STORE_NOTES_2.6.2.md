# «Что нового» — 2.6.2 (160), относительно 2.6.1

2.6.1 ушла в выпуск; 2.6.2 — поручения по замечаниям владельца 16.11.2026,
иконки организаций и переход между ящиками. Тексты ниже — для
тестировщиков, магазинов и страницы выпуска на GitHub. Шаги владельца —
`OWNER_STEPS_2.6.2.md`.

## Сделано в 2.6.2

- **Поручения → «Сводка» вокруг диаграммы Ганта** (решение владельца:
  «много отчётов, графиков и таблиц не нужно — нужно понимать общий ход
  работы, кто исполнители и на каком этапе; подсвечивать роль
  пользователя и сроки»). Главное на всех экранах, и на телефоне, —
  диаграмма «Ход работ»: поручения и проекты (этапы — под своим
  проектом), второй строкой — моя роль, исполнитель и стадия. Цвет строки
  — моя роль: исполняю — синий, контролирую — янтарный, поручил —
  зелёный, наблюдаю — серый. Срок — «до 14.11» у конца полосы,
  просроченный — красным. Сверху — фильтр по роли со счётчиками и по
  ящику, одна строка «Просрочено · На проверке · Срок на неделе». Плитки,
  полоса статусов и карточки людей убраны, «Отправить отчёт» остался.
- **План проекта**: мои этапы (исполняю, контролирую) подсвечены так же,
  срок — у конца полосы.
- **Календарь**: срок поручения — цветом моей роли и подписью
  «Исполняю · срок сегодня», «Поручил · …», «Контролирую · …».
- **Чек-лист в обычном поручении** (раньше — только в этапе проекта):
  кнопка «Чек-лист» в «Поручить», пункты уходят в письме.
- **Чек-лист и пояснение видят все участники.** Отметки и новые пункты
  раньше менялись только у себя; теперь через 20 секунд после изменения
  уходят письмом «Чек-лист изменён: ✓ пункт, + пункт» (подсказка под
  чек-листом). Пункты сливаются по тексту, а не по номеру. Пояснение
  приходит исполнителю и в обычном поручении. Файлы из писем по поручению
  больше не повторяются, номер OGN-… не попадает в текст ответа.
- **Иконки организаций**: значок сайта ищется и на `www.<домен>` (у
  некоторых сайтов, например ozon.ru, голый домен значка не отдаёт);
  иконка видна и в карточке отправителя (раньше там была только буква).
- **Настройки ящика**: сверху — ящики чипами, переход к другому ящику
  одним нажатием (и в «Расширенных настройках»).
- **Компьютер (Windows, macOS): сложные письма — в окне браузера.**
  Замечание владельца 16.11.2026: «не работает настройка отображения
  сложных писем». Причины и что сделано:
  - выбор применялся только к следующему открытому письму — теперь
    открытое письмо перерисовывается сразу;
  - выключатель «Простые письма без браузера» на компьютере ничего не
    менял — теперь, выключенный, отправляет в окно браузера и простые
    письма (как на телефоне);
  - Windows: окно WebView2 создавало папку данных рядом с ogneliss.exe и
    не создавалось вовсе, если архив распакован в папку без права записи
    (например, «Program Files»); теперь папка — в данных приложения, общая
    с переводом Bergamot;
  - настройка включается у всех один раз (новое имя ключа: выключенная
    до починки снова включена), дальше выбор сохраняется;
  - в диагностике — строка «Сложные письма в окне: …» (включено ли, есть
    ли WebView2, сколько писем показано, последний отказ).
- **Иконки организаций и логотипы BIMI — по умолчанию включены**
  (решение владельца 16.11.2026); выключенные вручную остаются
  выключенными, MDM `block_external_services` по-прежнему выключает.

## Кратко (RU / EN)

**RU.** Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и
сроки выделены цветом, и в календаре тоже. Чек-лист в обычном поручении;
отметки, пункты и пояснение видят все участники. Иконки организаций
включены по умолчанию, находятся и для сайтов с www. Компьютер: сложные
письма — в окне браузера. Переход между ящиками в настройках.

**EN.** Assignments: the Summary shows work progress on a Gantt chart with
your role and due dates highlighted, also in the calendar. Checklist in a
regular assignment; ticks, items and the description reach all
participants. Organisation icons are on by default and found for www
sites too. Desktop: complex emails in a browser view. Switch between
mailboxes in settings.

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и сроки выделены цветом (и в календаре)
• Чек-лист в обычном поручении; отметки, пункты и пояснение видят все участники
• Иконки организаций (логотип BIMI или значок сайта) включены по умолчанию и находятся и на сайтах с www
• Настройки ящика: переход к другому ящику одним нажатием
• Mac: письма со сложной вёрсткой — в окне браузера, настройка применяется сразу
</ru-RU>
<en-US>
• Assignments: the Summary shows work progress on a Gantt chart, with your role and due dates highlighted (also in the calendar)
• Checklist in a regular assignment; ticks, items and the description reach all participants
• Organisation icons (BIMI logo or site icon) are on by default and also found on www sites
• Mailbox settings: switch to another mailbox in one tap
• Mac: emails with complex layout open in a browser view; the setting applies at once
</en-US>
<de-DE>
• Aufträge: Die Übersicht zeigt den Arbeitsfortschritt als Gantt-Diagramm, Ihre Rolle und Fristen sind farbig hervorgehoben (auch im Kalender)
• Checkliste auch im einfachen Auftrag; Häkchen, Punkte und Beschreibung erreichen alle Beteiligten
• Symbole von Organisationen (BIMI-Logo oder Website-Symbol) sind standardmäßig an und werden auch auf www-Websites gefunden
• Postfacheinstellungen: mit einem Tippen zu einem anderen Postfach wechseln
• Mac: E-Mails mit komplexem Layout in einer Browseransicht; die Einstellung gilt sofort
</de-DE>
<fr-FR>
• Missions : la Synthèse montre l’avancement sur un diagramme de Gantt, votre rôle et les échéances en couleur (aussi dans l’agenda)
• Liste de contrôle dans une mission simple ; coches, points et description parviennent à tous les participants
• Icônes d’organisation (logo BIMI ou icône du site) activées par défaut, trouvées aussi sur les sites www
• Réglages de la boîte : passer à une autre boîte en un geste
• Mac : les e-mails à mise en page complexe s’affichent dans une vue navigateur ; le réglage s’applique aussitôt
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и сроки выделены цветом (и в календаре)
• Чек-лист в обычном поручении; отметки, пункты и пояснение видят все участники
• Иконки организаций (логотип BIMI или значок сайта) включены по умолчанию и находятся и на сайтах с www
• Настройки ящика: переход к другому ящику одним нажатием
</ru-RU>
<en-US>
• Assignments: the Summary shows work progress on a Gantt chart, with your role and due dates highlighted (also in the calendar)
• Checklist in a regular assignment; ticks, items and the description reach all participants
• Organisation icons (BIMI logo or site icon) are on by default and also found on www sites
• Mailbox settings: switch to another mailbox in one tap
</en-US>
<de-DE>
• Aufträge: Die Übersicht zeigt den Arbeitsfortschritt als Gantt-Diagramm, Ihre Rolle und Fristen sind farbig hervorgehoben (auch im Kalender)
• Checkliste auch im einfachen Auftrag; Häkchen, Punkte und Beschreibung erreichen alle Beteiligten
• Symbole von Organisationen (BIMI-Logo oder Website-Symbol) sind standardmäßig an und werden auch auf www-Websites gefunden
• Postfacheinstellungen: mit einem Tippen zu einem anderen Postfach wechseln
</de-DE>
<fr-FR>
• Missions : la Synthèse montre l’avancement sur un diagramme de Gantt, votre rôle et les échéances en couleur (aussi dans l’agenda)
• Liste de contrôle dans une mission simple ; coches, points et description parviennent à tous les participants
• Icônes d’organisation (logo BIMI ou icône du site) activées par défaut, trouvées aussi sur les sites www
• Réglages de la boîte : passer à une autre boîte en un geste
</fr-FR>
<ar>
• التكليفات: يعرض الملخص سير العمل على مخطط غانت مع إبراز دورك والمواعيد بالألوان (وفي التقويم أيضًا)
• قائمة تحقق في التكليف العادي؛ تصل العلامات والبنود والوصف إلى جميع المشاركين
• أيقونات المؤسسات (شعار BIMI أو أيقونة الموقع) مفعّلة افتراضيًا وتُعثر عليها في مواقع www أيضًا
• إعدادات صندوق البريد: الانتقال إلى صندوق آخر بلمسة واحدة
</ar>
<hu-HU>
• Megbízások: az Összesítő Gantt-diagramon mutatja a munka menetét, a szerepe és a határidők színnel kiemelve (a naptárban is)
• Ellenőrzőlista az egyszerű megbízásban is; a pipák, a tételek és a leírás minden résztvevőhöz eljutnak
• A szervezetek ikonjai (BIMI-logó vagy webhelyikon) alapból be vannak kapcsolva, és www-s webhelyeken is megtalálhatók
• Postafiók-beállítások: váltás másik postafiókra egy koppintással
</hu-HU>
<vi>
• Việc giao: Tổng quan hiển thị tiến độ trên biểu đồ Gantt, vai trò và hạn của bạn được tô màu (cả trong lịch)
• Danh sách kiểm trong việc giao thông thường; dấu tích, mục và mô tả đến được mọi người tham gia
• Biểu tượng tổ chức (logo BIMI hoặc biểu tượng trang) bật sẵn và tìm được cả trên trang có www
• Cài đặt hộp thư: chuyển sang hộp thư khác chỉ với một chạm
</vi>
<da-DK>
• Opgaver: Overblikket viser arbejdets forløb i et Gantt-diagram med din rolle og frister fremhævet i farver (også i kalenderen)
• Tjekliste i en almindelig opgave; flueben, punkter og beskrivelse når frem til alle deltagere
• Ikoner for organisationer (BIMI-logo eller webstedsikon) er slået til som standard og findes også på www-websteder
• Postkasseindstillinger: skift til en anden postkasse med ét tryk
</da-DK>
<iw-IL>
• משימות: הסיכום מציג את התקדמות העבודה בתרשים גאנט, והתפקיד והמועדים שלך מודגשים בצבע (גם ביומן)
• רשימת משימות גם במשימה רגילה; הסימונים, הפריטים והתיאור מגיעים לכל המשתתפים
• סמלי ארגונים (לוגו BIMI או סמל האתר) מופעלים כברירת מחדל ונמצאים גם באתרי www
• הגדרות תיבת הדואר: מעבר לתיבה אחרת בהקשה אחת
</iw-IL>
<id>
• Penugasan: Ringkasan menampilkan kemajuan kerja pada diagram Gantt, peran dan tenggat Anda ditandai warna (juga di kalender)
• Daftar periksa di penugasan biasa; centang, butir, dan deskripsi sampai ke semua peserta
• Ikon organisasi (logo BIMI atau ikon situs) aktif secara bawaan dan juga ditemukan di situs www
• Setelan kotak surat: pindah ke kotak surat lain dengan satu ketukan
</id>
<es-ES>
• Encargos: el Resumen muestra el avance en un diagrama de Gantt, con su rol y los plazos resaltados en color (también en el calendario)
• Lista de comprobación en un encargo normal; marcas, puntos y descripción llegan a todos los participantes
• Iconos de organizaciones (logotipo BIMI o icono del sitio) activados por defecto, también en sitios www
• Ajustes del buzón: cambiar a otro buzón con un toque
</es-ES>
<it-IT>
• Incarichi: il Riepilogo mostra l’andamento su un diagramma di Gantt, con il tuo ruolo e le scadenze evidenziati a colori (anche nel calendario)
• Checklist anche nell’incarico semplice; spunte, voci e descrizione arrivano a tutti i partecipanti
• Icone delle organizzazioni (logo BIMI o icona del sito) attive per impostazione predefinita, trovate anche sui siti www
• Impostazioni della casella: passa a un’altra casella con un tocco
</it-IT>
<zh-CN>
• 任务分派：汇总以甘特图展示工作进度，并用颜色突出您的角色和截止日期（日历中也是）
• 普通任务也可添加清单；勾选、条目和说明会同步给所有参与者
• 机构图标（BIMI 徽标或网站图标）默认开启，带 www 的网站也能找到
• 邮箱设置：一键切换到其他邮箱
</zh-CN>
<ko-KR>
• 업무 지시: 요약에서 간트 차트로 작업 진행을 보여 주고, 내 역할과 기한을 색으로 강조합니다(캘린더에서도)
• 일반 업무 지시에도 체크리스트; 체크, 항목, 설명이 모든 참여자에게 전달됩니다
• 기관 아이콘(BIMI 로고 또는 사이트 아이콘)이 기본으로 켜져 있으며 www 사이트에서도 찾습니다
• 편지함 설정: 한 번 눌러 다른 편지함으로 전환
</ko-KR>
<nl-NL>
• Opdrachten: het Overzicht toont de voortgang in een Gantt-diagram, met uw rol en deadlines in kleur (ook in de agenda)
• Checklist ook in een gewone opdracht; vinkjes, punten en omschrijving bereiken alle deelnemers
• Pictogrammen van organisaties (BIMI-logo of sitepictogram) staan standaard aan en worden ook op www-sites gevonden
• Postvakinstellingen: met één tik naar een ander postvak
</nl-NL>
<no-NO>
• Oppdrag: Oversikten viser arbeidets fremdrift i et Gantt-diagram, med din rolle og frister uthevet i farger (også i kalenderen)
• Sjekkliste også i et vanlig oppdrag; avkrysninger, punkter og beskrivelse når alle deltakerne
• Ikoner for organisasjoner (BIMI-logo eller nettstedsikon) er på som standard og finnes også på www-nettsteder
• Postboksinnstillinger: bytt til en annen postboks med ett trykk
</no-NO>
<pl-PL>
• Zlecenia: Podsumowanie pokazuje przebieg prac na wykresie Gantta, a Twoja rola i terminy są wyróżnione kolorem (także w kalendarzu)
• Lista kontrolna w zwykłym zleceniu; zaznaczenia, punkty i opis docierają do wszystkich uczestników
• Ikony organizacji (logo BIMI lub ikona strony) są domyślnie włączone i wyszukiwane także na stronach www
• Ustawienia skrzynki: przejście do innej skrzynki jednym dotknięciem
</pl-PL>
<pt-BR>
• Atribuições: o Resumo mostra o andamento em um gráfico de Gantt, com sua função e os prazos destacados em cores (também no calendário)
• Checklist em uma atribuição comum; marcações, itens e descrição chegam a todos os participantes
• Ícones de organizações (logotipo BIMI ou ícone do site) ativados por padrão, encontrados também em sites www
• Configurações da caixa: trocar para outra caixa com um toque
</pt-BR>
<ro>
• Sarcini: Rezumatul arată mersul lucrărilor pe o diagramă Gantt, cu rolul și termenele dvs. evidențiate color (și în calendar)
• Listă de verificare și în sarcina simplă; bifele, punctele și descrierea ajung la toți participanții
• Pictogramele organizațiilor (logo BIMI sau pictograma site-ului) sunt activate implicit și găsite și pe site-urile www
• Setările căsuței: treceți la altă căsuță cu o atingere
</ro>
<sk>
• Úlohy: Prehľad ukazuje priebeh prác na Ganttovom diagrame, vaša rola a termíny sú zvýraznené farbou (aj v kalendári)
• Kontrolný zoznam aj v bežnej úlohe; zaškrtnutia, položky a popis dostanú všetci účastníci
• Ikony organizácií (logo BIMI alebo ikona stránky) sú predvolene zapnuté a nájdu sa aj na stránkach www
• Nastavenia schránky: prechod na inú schránku jedným ťuknutím
</sk>
<th>
• งานมอบหมาย: หน้าสรุปแสดงความคืบหน้าบนแผนภูมิแกนต์ เน้นบทบาทและกำหนดส่งของคุณด้วยสี (ในปฏิทินด้วย)
• รายการตรวจสอบในงานมอบหมายทั่วไป เครื่องหมาย รายการ และคำอธิบายถึงผู้เข้าร่วมทุกคน
• ไอคอนองค์กร (โลโก้ BIMI หรือไอคอนเว็บไซต์) เปิดเป็นค่าเริ่มต้น และค้นหาจากเว็บไซต์ที่มี www ได้ด้วย
• การตั้งค่ากล่องจดหมาย: สลับไปกล่องอื่นได้ในแตะเดียว
</th>
<tr-TR>
• Görevlendirmeler: Özet, işin gidişatını Gantt şemasında gösterir; rolünüz ve son tarihler renkle vurgulanır (takvimde de)
• Basit görevlendirmede de kontrol listesi; işaretler, maddeler ve açıklama tüm katılımcılara ulaşır
• Kuruluş simgeleri (BIMI logosu veya site simgesi) varsayılan olarak açık, www’li sitelerde de bulunur
• Posta kutusu ayarları: tek dokunuşla başka bir kutuya geçin
</tr-TR>
<fi-FI>
• Toimeksiannot: Yhteenveto näyttää työn etenemisen Gantt-kaaviona, roolisi ja määräajat korostettuina väreillä (myös kalenterissa)
• Tarkistuslista myös tavallisessa toimeksiannossa; rastit, kohdat ja kuvaus välittyvät kaikille osallistujille
• Organisaatioiden kuvakkeet (BIMI-logo tai sivuston kuvake) ovat oletuksena päällä ja löytyvät myös www-sivustoilta
• Postilaatikon asetukset: vaihda toiseen laatikkoon yhdellä napautuksella
</fi-FI>
<hi-IN>
• सौंपे गए कार्य: सारांश गैंट चार्ट पर काम की प्रगति दिखाता है, आपकी भूमिका और समय-सीमा रंग से उभरी रहती हैं (कैलेंडर में भी)
• सामान्य कार्य में भी जाँच सूची; निशान, बिंदु और विवरण सभी प्रतिभागियों तक पहुँचते हैं
• संगठनों के आइकन (BIMI लोगो या साइट आइकन) डिफ़ॉल्ट रूप से चालू हैं और www वाली साइटों पर भी मिलते हैं
• मेलबॉक्स सेटिंग्स: एक टैप में दूसरे मेलबॉक्स पर जाएँ
</hi-IN>
<cs-CZ>
• Úkoly: Přehled ukazuje průběh prací na Ganttově diagramu, vaše role a termíny jsou zvýrazněny barvou (i v kalendáři)
• Kontrolní seznam i v běžném úkolu; zaškrtnutí, položky a popis dostanou všichni účastníci
• Ikony organizací (logo BIMI nebo ikona webu) jsou ve výchozím stavu zapnuté a najdou se i na webech s www
• Nastavení schránky: přechod na jinou schránku jedním klepnutím
</cs-CZ>
<sv-SE>
• Uppdrag: Översikten visar arbetets gång i ett Gantt-schema, med din roll och dina tidsfrister färgmarkerade (även i kalendern)
• Checklista även i ett vanligt uppdrag; bockar, punkter och beskrivning når alla deltagare
• Ikoner för organisationer (BIMI-logotyp eller webbplatsikon) är på som standard och hittas även på www-webbplatser
• Inställningar för brevlådan: byt till en annan brevlåda med ett tryck
</sv-SE>
<ja-JP>
• 依頼：サマリーで作業の進行をガントチャートで表示し、あなたの役割と期限を色で強調します（カレンダーでも）
• 通常の依頼にもチェックリスト。チェック、項目、説明が参加者全員に届きます
• 組織のアイコン（BIMI ロゴまたはサイトのアイコン）を既定でオンにし、www 付きのサイトからも取得します
• メールボックスの設定：ワンタップで別のメールボックスに切り替え
</ja-JP>
```
