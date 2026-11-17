# «Что нового» — 2.6.3 (161), относительно 2.6.2

2.6.2 (160) ушла тестировщикам; 2.6.3 — исправления по журналам владельца
17.11.2026. Шаги владельца — `OWNER_STEPS_2.6.3.md`.

Тексты магазинов: если **2.6.2 в магазин не выходила** (2.6.3 — первая
сборка после 2.6.1 в магазине), берите полные тексты ниже — они те же, что
в `STORE_NOTES_2.6.2.md`, и покрывают 2.6.2 и 2.6.3. Если 2.6.2 уже
вышла — короткий текст «Исправления и улучшения» в конце файла.

## Сделано в 2.6.3

- **Фото собеседников Google — сразу после «Войти снова».** В 2.6.2 первый
  отказ («нет разрешения» у ящика, вошедшего до 2.6.2) откладывал
  следующий запрос на неделю, и повторный вход его не ускорял (журнал
  17.11.2026: вход в 09:25, запроса нет). Теперь отказ привязан ко входу:
  новый вход — запрос сразу; без него — раз в 6 часов.
- **Иконки организаций — причина в журнале.** На каждый домен без значка
  — строка, что ответил сайт (HTTP-код, тайм-аут, переход на чужой домен,
  нет значков в странице); в сводке диагностики — домены без значка и
  отправители без подтверждения DMARC с причиной (нет заголовка,
  заголовок чужого сервера, проверка не пройдена). Ответы «значка нет»
  прежних версий забыты один раз — сайты спрашиваются заново.

## Кратко (RU / EN)

**RU.** Фото собеседников из профилей Google появляются сразу после
повторного входа в ящик. Иконки организаций ищутся заново; причины, если
иконки нет, видны в журнале для поддержки.

**EN.** Photos of contacts from Google profiles appear right after you sign
in to the mailbox again. Organisation icons are looked up afresh; the
support log shows why an icon is missing.

## Короткий текст — если 2.6.2 уже в магазине (Google Play, 27 языков)

```
<ru-RU>
• Исправления и улучшения
</ru-RU>
<en-US>
• Bug fixes and improvements
</en-US>
<de-DE>
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Corrections et améliorations
</fr-FR>
<ar>
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• תיקונים ושיפורים
</iw-IL>
<id>
• Perbaikan dan peningkatan
</id>
<es-ES>
• Correcciones y mejoras
</es-ES>
<it-IT>
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 问题修复和改进
</zh-CN>
<ko-KR>
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• Correções e melhorias
</pt-BR>
<ro>
• Remedieri și îmbunătățiri
</ro>
<sk>
• Opravy a vylepšenia
</sk>
<th>
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• सुधार और बेहतरी
</hi-IN>
<cs-CZ>
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и сроки выделены цветом (и в календаре)
• Чек-лист в обычном поручении; отметки, пункты и пояснение видят все участники
• Иконки организаций (логотип BIMI или значок сайта) включены по умолчанию и находятся и на сайтах с www
• Фото собеседников из профилей Google
• Настройки ящика: переход к другому ящику одним нажатием
• Mac: письмо всегда открывается в программе
</ru-RU>
<en-US>
• Assignments: the Summary shows work progress on a Gantt chart, with your role and due dates highlighted (also in the calendar)
• Checklist in a regular assignment; ticks, items and the description reach all participants
• Organisation icons (BIMI logo or site icon) are on by default and also found on www sites
• Photos of contacts from Google profiles
• Mailbox settings: switch to another mailbox in one tap
• Mac: emails always open inside the app
</en-US>
<de-DE>
• Aufträge: Die Übersicht zeigt den Arbeitsfortschritt als Gantt-Diagramm, Ihre Rolle und Fristen sind farbig hervorgehoben (auch im Kalender)
• Checkliste auch im einfachen Auftrag; Häkchen, Punkte und Beschreibung erreichen alle Beteiligten
• Symbole von Organisationen (BIMI-Logo oder Website-Symbol) sind standardmäßig an und werden auch auf www-Websites gefunden
• Fotos von Kontakten aus Google-Profilen
• Postfacheinstellungen: mit einem Tippen zu einem anderen Postfach wechseln
• Mac: E-Mails öffnen sich immer in der App
</de-DE>
<fr-FR>
• Missions : la Synthèse montre l’avancement sur un diagramme de Gantt, votre rôle et les échéances en couleur (aussi dans l’agenda)
• Liste de contrôle dans une mission simple ; coches, points et description parviennent à tous les participants
• Icônes d’organisation (logo BIMI ou icône du site) activées par défaut, trouvées aussi sur les sites www
• Photos des contacts depuis les profils Google
• Réglages de la boîte : passer à une autre boîte en un geste
• Mac : les e-mails s’ouvrent toujours dans l’application
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Поручения: «Сводка» — ход работ на диаграмме Ганта, ваша роль и сроки выделены цветом (и в календаре)
• Чек-лист в обычном поручении; отметки, пункты и пояснение видят все участники
• Иконки организаций (логотип BIMI или значок сайта) включены по умолчанию и находятся и на сайтах с www
• Фото собеседников из профилей Google
• Настройки ящика: переход к другому ящику одним нажатием
</ru-RU>
<en-US>
• Assignments: the Summary shows work progress on a Gantt chart, with your role and due dates highlighted (also in the calendar)
• Checklist in a regular assignment; ticks, items and the description reach all participants
• Organisation icons (BIMI logo or site icon) are on by default and also found on www sites
• Photos of contacts from Google profiles
• Mailbox settings: switch to another mailbox in one tap
</en-US>
<de-DE>
• Aufträge: Die Übersicht zeigt den Arbeitsfortschritt als Gantt-Diagramm, Ihre Rolle und Fristen sind farbig hervorgehoben (auch im Kalender)
• Checkliste auch im einfachen Auftrag; Häkchen, Punkte und Beschreibung erreichen alle Beteiligten
• Symbole von Organisationen (BIMI-Logo oder Website-Symbol) sind standardmäßig an und werden auch auf www-Websites gefunden
• Fotos von Kontakten aus Google-Profilen
• Postfacheinstellungen: mit einem Tippen zu einem anderen Postfach wechseln
</de-DE>
<fr-FR>
• Missions : la Synthèse montre l’avancement sur un diagramme de Gantt, votre rôle et les échéances en couleur (aussi dans l’agenda)
• Liste de contrôle dans une mission simple ; coches, points et description parviennent à tous les participants
• Icônes d’organisation (logo BIMI ou icône du site) activées par défaut, trouvées aussi sur les sites www
• Photos des contacts depuis les profils Google
• Réglages de la boîte : passer à une autre boîte en un geste
</fr-FR>
<ar>
• التكليفات: يعرض الملخص سير العمل على مخطط غانت مع إبراز دورك والمواعيد بالألوان (وفي التقويم أيضًا)
• قائمة تحقق في التكليف العادي؛ تصل العلامات والبنود والوصف إلى جميع المشاركين
• أيقونات المؤسسات (شعار BIMI أو أيقونة الموقع) مفعّلة افتراضيًا وتُعثر عليها في مواقع www أيضًا
• صور جهات الاتصال من ملفات Google الشخصية
• إعدادات صندوق البريد: الانتقال إلى صندوق آخر بلمسة واحدة
</ar>
<hu-HU>
• Megbízások: az Összesítő Gantt-diagramon mutatja a munka menetét, a szerepe és a határidők színnel kiemelve (a naptárban is)
• Ellenőrzőlista az egyszerű megbízásban is; a pipák, a tételek és a leírás minden résztvevőhöz eljutnak
• A szervezetek ikonjai (BIMI-logó vagy webhelyikon) alapból be vannak kapcsolva, és www-s webhelyeken is megtalálhatók
• Partnerek fotói a Google-profilokból
• Postafiók-beállítások: váltás másik postafiókra egy koppintással
</hu-HU>
<vi>
• Việc giao: Tổng quan hiển thị tiến độ trên biểu đồ Gantt, vai trò và hạn của bạn được tô màu (cả trong lịch)
• Danh sách kiểm trong việc giao thông thường; dấu tích, mục và mô tả đến được mọi người tham gia
• Biểu tượng tổ chức (logo BIMI hoặc biểu tượng trang) bật sẵn và tìm được cả trên trang có www
• Ảnh người liên hệ từ hồ sơ Google
• Cài đặt hộp thư: chuyển sang hộp thư khác chỉ với một chạm
</vi>
<da-DK>
• Opgaver: Overblikket viser arbejdets forløb i et Gantt-diagram med din rolle og frister fremhævet i farver (også i kalenderen)
• Tjekliste i en almindelig opgave; flueben, punkter og beskrivelse når frem til alle deltagere
• Ikoner for organisationer (BIMI-logo eller webstedsikon) er slået til som standard og findes også på www-websteder
• Fotos af kontakter fra Google-profiler
• Postkasseindstillinger: skift til en anden postkasse med ét tryk
</da-DK>
<iw-IL>
• משימות: הסיכום מציג את התקדמות העבודה בתרשים גאנט, והתפקיד והמועדים שלך מודגשים בצבע (גם ביומן)
• רשימת משימות גם במשימה רגילה; הסימונים, הפריטים והתיאור מגיעים לכל המשתתפים
• סמלי ארגונים (לוגו BIMI או סמל האתר) מופעלים כברירת מחדל ונמצאים גם באתרי www
• תמונות אנשי קשר מפרופילי Google
• הגדרות תיבת הדואר: מעבר לתיבה אחרת בהקשה אחת
</iw-IL>
<id>
• Penugasan: Ringkasan menampilkan kemajuan kerja pada diagram Gantt, peran dan tenggat Anda ditandai warna (juga di kalender)
• Daftar periksa di penugasan biasa; centang, butir, dan deskripsi sampai ke semua peserta
• Ikon organisasi (logo BIMI atau ikon situs) aktif secara bawaan dan juga ditemukan di situs www
• Foto kontak dari profil Google
• Setelan kotak surat: pindah ke kotak surat lain dengan satu ketukan
</id>
<es-ES>
• Encargos: el Resumen muestra el avance en un diagrama de Gantt, con su rol y los plazos resaltados en color (también en el calendario)
• Lista de comprobación en un encargo normal; marcas, puntos y descripción llegan a todos los participantes
• Iconos de organizaciones (logotipo BIMI o icono del sitio) activados por defecto, también en sitios www
• Fotos de contactos de los perfiles de Google
• Ajustes del buzón: cambiar a otro buzón con un toque
</es-ES>
<it-IT>
• Incarichi: il Riepilogo mostra l’andamento su un diagramma di Gantt, con il tuo ruolo e le scadenze evidenziati a colori (anche nel calendario)
• Checklist anche nell’incarico semplice; spunte, voci e descrizione arrivano a tutti i partecipanti
• Icone delle organizzazioni (logo BIMI o icona del sito) attive per impostazione predefinita, trovate anche sui siti www
• Foto dei contatti dai profili Google
• Impostazioni della casella: passa a un’altra casella con un tocco
</it-IT>
<zh-CN>
• 任务分派：汇总以甘特图展示工作进度，并用颜色突出您的角色和截止日期（日历中也是）
• 普通任务也可添加清单；勾选、条目和说明会同步给所有参与者
• 机构图标（BIMI 徽标或网站图标）默认开启，带 www 的网站也能找到
• 来自 Google 个人资料的联系人照片
• 邮箱设置：一键切换到其他邮箱
</zh-CN>
<ko-KR>
• 업무 지시: 요약에서 간트 차트로 작업 진행을 보여 주고, 내 역할과 기한을 색으로 강조합니다(캘린더에서도)
• 일반 업무 지시에도 체크리스트; 체크, 항목, 설명이 모든 참여자에게 전달됩니다
• 기관 아이콘(BIMI 로고 또는 사이트 아이콘)이 기본으로 켜져 있으며 www 사이트에서도 찾습니다
• Google 프로필의 연락처 사진
• 편지함 설정: 한 번 눌러 다른 편지함으로 전환
</ko-KR>
<nl-NL>
• Opdrachten: het Overzicht toont de voortgang in een Gantt-diagram, met uw rol en deadlines in kleur (ook in de agenda)
• Checklist ook in een gewone opdracht; vinkjes, punten en omschrijving bereiken alle deelnemers
• Pictogrammen van organisaties (BIMI-logo of sitepictogram) staan standaard aan en worden ook op www-sites gevonden
• Foto’s van contacten uit Google-profielen
• Postvakinstellingen: met één tik naar een ander postvak
</nl-NL>
<no-NO>
• Oppdrag: Oversikten viser arbeidets fremdrift i et Gantt-diagram, med din rolle og frister uthevet i farger (også i kalenderen)
• Sjekkliste også i et vanlig oppdrag; avkrysninger, punkter og beskrivelse når alle deltakerne
• Ikoner for organisasjoner (BIMI-logo eller nettstedsikon) er på som standard og finnes også på www-nettsteder
• Bilder av kontakter fra Google-profiler
• Postboksinnstillinger: bytt til en annen postboks med ett trykk
</no-NO>
<pl-PL>
• Zlecenia: Podsumowanie pokazuje przebieg prac na wykresie Gantta, a Twoja rola i terminy są wyróżnione kolorem (także w kalendarzu)
• Lista kontrolna w zwykłym zleceniu; zaznaczenia, punkty i opis docierają do wszystkich uczestników
• Ikony organizacji (logo BIMI lub ikona strony) są domyślnie włączone i wyszukiwane także na stronach www
• Zdjęcia kontaktów z profili Google
• Ustawienia skrzynki: przejście do innej skrzynki jednym dotknięciem
</pl-PL>
<pt-BR>
• Atribuições: o Resumo mostra o andamento em um gráfico de Gantt, com sua função e os prazos destacados em cores (também no calendário)
• Checklist em uma atribuição comum; marcações, itens e descrição chegam a todos os participantes
• Ícones de organizações (logotipo BIMI ou ícone do site) ativados por padrão, encontrados também em sites www
• Fotos dos contatos dos perfis do Google
• Configurações da caixa: trocar para outra caixa com um toque
</pt-BR>
<ro>
• Sarcini: Rezumatul arată mersul lucrărilor pe o diagramă Gantt, cu rolul și termenele dvs. evidențiate color (și în calendar)
• Listă de verificare și în sarcina simplă; bifele, punctele și descrierea ajung la toți participanții
• Pictogramele organizațiilor (logo BIMI sau pictograma site-ului) sunt activate implicit și găsite și pe site-urile www
• Fotografiile contactelor din profilurile Google
• Setările căsuței: treceți la altă căsuță cu o atingere
</ro>
<sk>
• Úlohy: Prehľad ukazuje priebeh prác na Ganttovom diagrame, vaša rola a termíny sú zvýraznené farbou (aj v kalendári)
• Kontrolný zoznam aj v bežnej úlohe; zaškrtnutia, položky a popis dostanú všetci účastníci
• Ikony organizácií (logo BIMI alebo ikona stránky) sú predvolene zapnuté a nájdu sa aj na stránkach www
• Fotky kontaktov z profilov Google
• Nastavenia schránky: prechod na inú schránku jedným ťuknutím
</sk>
<th>
• งานมอบหมาย: หน้าสรุปแสดงความคืบหน้าบนแผนภูมิแกนต์ เน้นบทบาทและกำหนดส่งของคุณด้วยสี (ในปฏิทินด้วย)
• รายการตรวจสอบในงานมอบหมายทั่วไป เครื่องหมาย รายการ และคำอธิบายถึงผู้เข้าร่วมทุกคน
• ไอคอนองค์กร (โลโก้ BIMI หรือไอคอนเว็บไซต์) เปิดเป็นค่าเริ่มต้น และค้นหาจากเว็บไซต์ที่มี www ได้ด้วย
• รูปผู้ติดต่อจากโปรไฟล์ Google
• การตั้งค่ากล่องจดหมาย: สลับไปกล่องอื่นได้ในแตะเดียว
</th>
<tr-TR>
• Görevlendirmeler: Özet, işin gidişatını Gantt şemasında gösterir; rolünüz ve son tarihler renkle vurgulanır (takvimde de)
• Basit görevlendirmede de kontrol listesi; işaretler, maddeler ve açıklama tüm katılımcılara ulaşır
• Kuruluş simgeleri (BIMI logosu veya site simgesi) varsayılan olarak açık, www’li sitelerde de bulunur
• Google profillerinden kişi fotoğrafları
• Posta kutusu ayarları: tek dokunuşla başka bir kutuya geçin
</tr-TR>
<fi-FI>
• Toimeksiannot: Yhteenveto näyttää työn etenemisen Gantt-kaaviona, roolisi ja määräajat korostettuina väreillä (myös kalenterissa)
• Tarkistuslista myös tavallisessa toimeksiannossa; rastit, kohdat ja kuvaus välittyvät kaikille osallistujille
• Organisaatioiden kuvakkeet (BIMI-logo tai sivuston kuvake) ovat oletuksena päällä ja löytyvät myös www-sivustoilta
• Yhteystietojen kuvat Google-profiileista
• Postilaatikon asetukset: vaihda toiseen laatikkoon yhdellä napautuksella
</fi-FI>
<hi-IN>
• सौंपे गए कार्य: सारांश गैंट चार्ट पर काम की प्रगति दिखाता है, आपकी भूमिका और समय-सीमा रंग से उभरी रहती हैं (कैलेंडर में भी)
• सामान्य कार्य में भी जाँच सूची; निशान, बिंदु और विवरण सभी प्रतिभागियों तक पहुँचते हैं
• संगठनों के आइकन (BIMI लोगो या साइट आइकन) डिफ़ॉल्ट रूप से चालू हैं और www वाली साइटों पर भी मिलते हैं
• Google प्रोफ़ाइल से संपर्कों की तस्वीरें
• मेलबॉक्स सेटिंग्स: एक टैप में दूसरे मेलबॉक्स पर जाएँ
</hi-IN>
<cs-CZ>
• Úkoly: Přehled ukazuje průběh prací na Ganttově diagramu, vaše role a termíny jsou zvýrazněny barvou (i v kalendáři)
• Kontrolní seznam i v běžném úkolu; zaškrtnutí, položky a popis dostanou všichni účastníci
• Ikony organizací (logo BIMI nebo ikona webu) jsou ve výchozím stavu zapnuté a najdou se i na webech s www
• Fotky kontaktů z profilů Google
• Nastavení schránky: přechod na jinou schránku jedním klepnutím
</cs-CZ>
<sv-SE>
• Uppdrag: Översikten visar arbetets gång i ett Gantt-schema, med din roll och dina tidsfrister färgmarkerade (även i kalendern)
• Checklista även i ett vanligt uppdrag; bockar, punkter och beskrivning når alla deltagare
• Ikoner för organisationer (BIMI-logotyp eller webbplatsikon) är på som standard och hittas även på www-webbplatser
• Foton på kontakter från Google-profiler
• Inställningar för brevlådan: byt till en annan brevlåda med ett tryck
</sv-SE>
<ja-JP>
• 依頼：サマリーで作業の進行をガントチャートで表示し、あなたの役割と期限を色で強調します（カレンダーでも）
• 通常の依頼にもチェックリスト。チェック、項目、説明が参加者全員に届きます
• 組織のアイコン（BIMI ロゴまたはサイトのアイコン）を既定でオンにし、www 付きのサイトからも取得します
• Google プロフィールの連絡先の写真
• メールボックスの設定：ワンタップで別のメールボックスに切り替え
</ja-JP>
```
