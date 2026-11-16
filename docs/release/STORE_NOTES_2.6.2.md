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

## Кратко (RU / EN)

**RU.** Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и
сроки выделены цветом, и в календаре тоже. Чек-лист в обычном поручении;
отметки, пункты и пояснение видят все участники. Иконки организаций — и
для сайтов с www, и в карточке отправителя. Переход между ящиками в
настройках.

**EN.** Assignments: the Summary shows work progress on a Gantt chart with
your role and due dates highlighted, also in the calendar. Checklist in a
regular assignment; ticks, items and the description reach all
participants. Organisation icons for www sites and in the sender card.
Switch between mailboxes in settings.

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и сроки выделены цветом (и в календаре)
• Чек-лист в обычном поручении; отметки, пункты и пояснение видят все участники
• Иконки организаций находятся и на сайтах с www (например, Ozon) и видны в карточке отправителя
• Настройки ящика: переход к другому ящику одним нажатием
</ru-RU>
<en-US>
• Assignments: the Summary shows work progress on a Gantt chart, with your role and due dates highlighted (also in the calendar)
• Checklist in a regular assignment; ticks, items and the description reach all participants
• Organisation icons are also found on www sites (e.g. Ozon) and shown in the sender card
• Mailbox settings: switch to another mailbox in one tap
</en-US>
<de-DE>
• Aufträge: Die Übersicht zeigt den Arbeitsfortschritt als Gantt-Diagramm, Ihre Rolle und Fristen sind farbig hervorgehoben (auch im Kalender)
• Checkliste auch im einfachen Auftrag; Häkchen, Punkte und Beschreibung erreichen alle Beteiligten
• Symbole von Organisationen werden auch auf www-Websites gefunden (z. B. Ozon) und in der Absenderkarte angezeigt
• Postfacheinstellungen: mit einem Tippen zu einem anderen Postfach wechseln
</de-DE>
<fr-FR>
• Missions : la Synthèse montre l’avancement sur un diagramme de Gantt, votre rôle et les échéances en couleur (aussi dans l’agenda)
• Liste de contrôle dans une mission simple ; coches, points et description parviennent à tous les participants
• Les icônes d’organisation sont aussi trouvées sur les sites www (par ex. Ozon) et affichées dans la fiche de l’expéditeur
• Réglages de la boîte : passer à une autre boîte en un geste
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и сроки выделены цветом (и в календаре)
• Чек-лист в обычном поручении; отметки, пункты и пояснение видят все участники
• Иконки организаций находятся и на сайтах с www (например, Ozon) и видны в карточке отправителя
• Настройки ящика: переход к другому ящику одним нажатием
</ru-RU>
<en-US>
• Assignments: the Summary shows work progress on a Gantt chart, with your role and due dates highlighted (also in the calendar)
• Checklist in a regular assignment; ticks, items and the description reach all participants
• Organisation icons are also found on www sites (e.g. Ozon) and shown in the sender card
• Mailbox settings: switch to another mailbox in one tap
</en-US>
<de-DE>
• Aufträge: Die Übersicht zeigt den Arbeitsfortschritt als Gantt-Diagramm, Ihre Rolle und Fristen sind farbig hervorgehoben (auch im Kalender)
• Checkliste auch im einfachen Auftrag; Häkchen, Punkte und Beschreibung erreichen alle Beteiligten
• Symbole von Organisationen werden auch auf www-Websites gefunden (z. B. Ozon) und in der Absenderkarte angezeigt
• Postfacheinstellungen: mit einem Tippen zu einem anderen Postfach wechseln
</de-DE>
<fr-FR>
• Missions : la Synthèse montre l’avancement sur un diagramme de Gantt, votre rôle et les échéances en couleur (aussi dans l’agenda)
• Liste de contrôle dans une mission simple ; coches, points et description parviennent à tous les participants
• Les icônes d’organisation sont aussi trouvées sur les sites www (par ex. Ozon) et affichées dans la fiche de l’expéditeur
• Réglages de la boîte : passer à une autre boîte en un geste
</fr-FR>
<ar>
• التكليفات: يعرض الملخص سير العمل على مخطط غانت مع إبراز دورك والمواعيد بالألوان (وفي التقويم أيضًا)
• قائمة تحقق في التكليف العادي؛ تصل العلامات والبنود والوصف إلى جميع المشاركين
• تُعثر على أيقونات المؤسسات أيضًا في مواقع www (مثل Ozon) وتظهر في بطاقة المرسل
• إعدادات صندوق البريد: الانتقال إلى صندوق آخر بلمسة واحدة
</ar>
<hu-HU>
• Megbízások: az Összesítő Gantt-diagramon mutatja a munka menetét, a szerepe és a határidők színnel kiemelve (a naptárban is)
• Ellenőrzőlista az egyszerű megbízásban is; a pipák, a tételek és a leírás minden résztvevőhöz eljutnak
• A szervezetek ikonjai a www-s webhelyeken is megtalálhatók (pl. Ozon), és a feladó kártyáján is látszanak
• Postafiók-beállítások: váltás másik postafiókra egy koppintással
</hu-HU>
<vi>
• Việc giao: Tổng quan hiển thị tiến độ trên biểu đồ Gantt, vai trò và hạn của bạn được tô màu (cả trong lịch)
• Danh sách kiểm trong việc giao thông thường; dấu tích, mục và mô tả đến được mọi người tham gia
• Biểu tượng tổ chức được tìm cả trên trang có www (ví dụ Ozon) và hiện trong thẻ người gửi
• Cài đặt hộp thư: chuyển sang hộp thư khác chỉ với một chạm
</vi>
<da-DK>
• Opgaver: Overblikket viser arbejdets forløb i et Gantt-diagram med din rolle og frister fremhævet i farver (også i kalenderen)
• Tjekliste i en almindelig opgave; flueben, punkter og beskrivelse når frem til alle deltagere
• Ikoner for organisationer findes også på www-websteder (f.eks. Ozon) og vises på afsenderkortet
• Postkasseindstillinger: skift til en anden postkasse med ét tryk
</da-DK>
<iw-IL>
• משימות: הסיכום מציג את התקדמות העבודה בתרשים גאנט, והתפקיד והמועדים שלך מודגשים בצבע (גם ביומן)
• רשימת משימות גם במשימה רגילה; הסימונים, הפריטים והתיאור מגיעים לכל המשתתפים
• סמלי ארגונים נמצאים גם באתרי www (למשל Ozon) ומוצגים בכרטיס השולח
• הגדרות תיבת הדואר: מעבר לתיבה אחרת בהקשה אחת
</iw-IL>
<id>
• Penugasan: Ringkasan menampilkan kemajuan kerja pada diagram Gantt, peran dan tenggat Anda ditandai warna (juga di kalender)
• Daftar periksa di penugasan biasa; centang, butir, dan deskripsi sampai ke semua peserta
• Ikon organisasi juga ditemukan di situs www (misalnya Ozon) dan tampil di kartu pengirim
• Setelan kotak surat: pindah ke kotak surat lain dengan satu ketukan
</id>
<es-ES>
• Encargos: el Resumen muestra el avance en un diagrama de Gantt, con su rol y los plazos resaltados en color (también en el calendario)
• Lista de comprobación en un encargo normal; marcas, puntos y descripción llegan a todos los participantes
• Los iconos de organizaciones también se encuentran en sitios www (p. ej., Ozon) y se ven en la ficha del remitente
• Ajustes del buzón: cambiar a otro buzón con un toque
</es-ES>
<it-IT>
• Incarichi: il Riepilogo mostra l’andamento su un diagramma di Gantt, con il tuo ruolo e le scadenze evidenziati a colori (anche nel calendario)
• Checklist anche nell’incarico semplice; spunte, voci e descrizione arrivano a tutti i partecipanti
• Le icone delle organizzazioni si trovano anche sui siti www (ad es. Ozon) e compaiono nella scheda del mittente
• Impostazioni della casella: passa a un’altra casella con un tocco
</it-IT>
<zh-CN>
• 任务分派：汇总以甘特图展示工作进度，并用颜色突出您的角色和截止日期（日历中也是）
• 普通任务也可添加清单；勾选、条目和说明会同步给所有参与者
• 带 www 的网站（如 Ozon）也能找到机构图标，并显示在发件人卡片中
• 邮箱设置：一键切换到其他邮箱
</zh-CN>
<ko-KR>
• 업무 지시: 요약에서 간트 차트로 작업 진행을 보여 주고, 내 역할과 기한을 색으로 강조합니다(캘린더에서도)
• 일반 업무 지시에도 체크리스트; 체크, 항목, 설명이 모든 참여자에게 전달됩니다
• www 사이트(예: Ozon)에서도 기관 아이콘을 찾아 발신자 카드에 표시합니다
• 편지함 설정: 한 번 눌러 다른 편지함으로 전환
</ko-KR>
<nl-NL>
• Opdrachten: het Overzicht toont de voortgang in een Gantt-diagram, met uw rol en deadlines in kleur (ook in de agenda)
• Checklist ook in een gewone opdracht; vinkjes, punten en omschrijving bereiken alle deelnemers
• Pictogrammen van organisaties worden ook op www-sites gevonden (bijv. Ozon) en getoond op de afzenderkaart
• Postvakinstellingen: met één tik naar een ander postvak
</nl-NL>
<no-NO>
• Oppdrag: Oversikten viser arbeidets fremdrift i et Gantt-diagram, med din rolle og frister uthevet i farger (også i kalenderen)
• Sjekkliste også i et vanlig oppdrag; avkrysninger, punkter og beskrivelse når alle deltakerne
• Ikoner for organisasjoner finnes også på www-nettsteder (f.eks. Ozon) og vises på avsenderkortet
• Postboksinnstillinger: bytt til en annen postboks med ett trykk
</no-NO>
<pl-PL>
• Zlecenia: Podsumowanie pokazuje przebieg prac na wykresie Gantta, a Twoja rola i terminy są wyróżnione kolorem (także w kalendarzu)
• Lista kontrolna w zwykłym zleceniu; zaznaczenia, punkty i opis docierają do wszystkich uczestników
• Ikony organizacji są wyszukiwane także na stronach www (np. Ozon) i widoczne w karcie nadawcy
• Ustawienia skrzynki: przejście do innej skrzynki jednym dotknięciem
</pl-PL>
<pt-BR>
• Atribuições: o Resumo mostra o andamento em um gráfico de Gantt, com sua função e os prazos destacados em cores (também no calendário)
• Checklist em uma atribuição comum; marcações, itens e descrição chegam a todos os participantes
• Ícones de organizações também são encontrados em sites www (por exemplo, Ozon) e aparecem no cartão do remetente
• Configurações da caixa: trocar para outra caixa com um toque
</pt-BR>
<ro>
• Sarcini: Rezumatul arată mersul lucrărilor pe o diagramă Gantt, cu rolul și termenele dvs. evidențiate color (și în calendar)
• Listă de verificare și în sarcina simplă; bifele, punctele și descrierea ajung la toți participanții
• Pictogramele organizațiilor sunt găsite și pe site-urile www (de ex. Ozon) și apar în fișa expeditorului
• Setările căsuței: treceți la altă căsuță cu o atingere
</ro>
<sk>
• Úlohy: Prehľad ukazuje priebeh prác na Ganttovom diagrame, vaša rola a termíny sú zvýraznené farbou (aj v kalendári)
• Kontrolný zoznam aj v bežnej úlohe; zaškrtnutia, položky a popis dostanú všetci účastníci
• Ikony organizácií sa nájdu aj na stránkach www (napr. Ozon) a zobrazia sa na karte odosielateľa
• Nastavenia schránky: prechod na inú schránku jedným ťuknutím
</sk>
<th>
• งานมอบหมาย: หน้าสรุปแสดงความคืบหน้าบนแผนภูมิแกนต์ เน้นบทบาทและกำหนดส่งของคุณด้วยสี (ในปฏิทินด้วย)
• รายการตรวจสอบในงานมอบหมายทั่วไป เครื่องหมาย รายการ และคำอธิบายถึงผู้เข้าร่วมทุกคน
• ค้นหาไอคอนองค์กรจากเว็บไซต์ที่มี www ได้ด้วย (เช่น Ozon) และแสดงในการ์ดผู้ส่ง
• การตั้งค่ากล่องจดหมาย: สลับไปกล่องอื่นได้ในแตะเดียว
</th>
<tr-TR>
• Görevlendirmeler: Özet, işin gidişatını Gantt şemasında gösterir; rolünüz ve son tarihler renkle vurgulanır (takvimde de)
• Basit görevlendirmede de kontrol listesi; işaretler, maddeler ve açıklama tüm katılımcılara ulaşır
• Kuruluş simgeleri www’li sitelerde de bulunur (ör. Ozon) ve gönderen kartında görünür
• Posta kutusu ayarları: tek dokunuşla başka bir kutuya geçin
</tr-TR>
<fi-FI>
• Toimeksiannot: Yhteenveto näyttää työn etenemisen Gantt-kaaviona, roolisi ja määräajat korostettuina väreillä (myös kalenterissa)
• Tarkistuslista myös tavallisessa toimeksiannossa; rastit, kohdat ja kuvaus välittyvät kaikille osallistujille
• Organisaatioiden kuvakkeet löytyvät myös www-sivustoilta (esim. Ozon) ja näkyvät lähettäjän kortissa
• Postilaatikon asetukset: vaihda toiseen laatikkoon yhdellä napautuksella
</fi-FI>
<hi-IN>
• सौंपे गए कार्य: सारांश गैंट चार्ट पर काम की प्रगति दिखाता है, आपकी भूमिका और समय-सीमा रंग से उभरी रहती हैं (कैलेंडर में भी)
• सामान्य कार्य में भी जाँच सूची; निशान, बिंदु और विवरण सभी प्रतिभागियों तक पहुँचते हैं
• संगठनों के आइकन www वाली साइटों (जैसे Ozon) पर भी मिलते हैं और प्रेषक कार्ड में दिखते हैं
• मेलबॉक्स सेटिंग्स: एक टैप में दूसरे मेलबॉक्स पर जाएँ
</hi-IN>
<cs-CZ>
• Úkoly: Přehled ukazuje průběh prací na Ganttově diagramu, vaše role a termíny jsou zvýrazněny barvou (i v kalendáři)
• Kontrolní seznam i v běžném úkolu; zaškrtnutí, položky a popis dostanou všichni účastníci
• Ikony organizací se najdou i na webech s www (např. Ozon) a zobrazí se na kartě odesílatele
• Nastavení schránky: přechod na jinou schránku jedním klepnutím
</cs-CZ>
<sv-SE>
• Uppdrag: Översikten visar arbetets gång i ett Gantt-schema, med din roll och dina tidsfrister färgmarkerade (även i kalendern)
• Checklista även i ett vanligt uppdrag; bockar, punkter och beskrivning når alla deltagare
• Ikoner för organisationer hittas även på www-webbplatser (t.ex. Ozon) och visas på avsändarkortet
• Inställningar för brevlådan: byt till en annan brevlåda med ett tryck
</sv-SE>
<ja-JP>
• 依頼：サマリーで作業の進行をガントチャートで表示し、あなたの役割と期限を色で強調します（カレンダーでも）
• 通常の依頼にもチェックリスト。チェック、項目、説明が参加者全員に届きます
• 組織のアイコンを www 付きのサイト（例：Ozon）からも取得し、差出人カードにも表示します
• メールボックスの設定：ワンタップで別のメールボックスに切り替え
</ja-JP>
```
