# «Что нового» — 2.6.4 (162), относительно 2.6.3

2.6.3 (161) ушла тестировщикам; 2.6.4 — исправления по журналу владельца
17.11.2026 (15:43) и пункты технического долга из плана после аудитов
(`docs/plan/PLAN_2026-11.md`). Шаги владельца — `OWNER_STEPS_2.6.4.md`.

Тексты магазинов: если в магазин ещё не выходили 2.6.2 и 2.6.3 (2.6.4 —
первая сборка после 2.6.1), берите полные тексты из `STORE_NOTES_2.6.2.md`
(они покрывают 2.6.2–2.6.4) и добавьте первую строку ниже. Если 2.6.3 уже
в магазине — короткий текст ниже.

## Сделано в 2.6.4

**По журналу 17.11.2026** (из 46 сайтов значок нашёлся у 10):

- **Значки компаний — у большего числа писем.** Берутся любые картинки
  (.ico с BMP внутри — как у google.com, JPEG, GIF, WebP), а не только PNG;
  переход сайта на другой домен (statuspage.io → atlassian.com) больше не
  считается отказом; значки из манифеста сайта; «&amp;» в адресе значка;
  запрос как у браузера телефона (защита от роботов отвечала 418/503).
  Почему значка нет — в журнале («мал 16×16», «не картинка»). Сайты без
  значка спрашиваются заново один раз.
- **Календарь Google не тормозит проверку почты.** На тайм-аут календарь
  больше не перезапрашивается «за все годы» (запрос ещё больше), медленный
  календарь не заставляет перечитывать остальные каждые 15 минут (фоновая
  проверка доходила до 137 с).
- **«Очистить корзину»** — Exchange одной командой (по одному письму
  сервер отвечал Status 4); черновик, не ушедший на сервер, не ломает
  очистку в Gmail.
- **«Войти снова»** — после входа проверка сертификата выполняется (ошибка
  «ref … unmounted»).
- **Перевод**: движок телефона не назвал язык письма — язык определяется
  по алфавиту и частым словам (письмо со 100 % кириллицы было «не
  определён»).
- **Журнал для поддержки**: какие разрешения Google не выдал при входе;
  People API «не включён в проекте» отличается от «нет разрешения»;
  заголовок проверки DMARC (без адресов) у отправителей «нет pass»; строки
  о многодневных событиях календаря — только в подробном журнале.

**Технический долг (план после аудитов, п. 1–2):**

- **IMAP: папку пересоздали на сервере (сменился UIDVALIDITY)** —
  отложенные «прочитано», флаг, перенос и удаление по старым номерам
  отменяются: раньше они пришлись бы на другие письма.
- **Exchange: ящик переехал на другой сервер (451)** — новый адрес
  запоминается в сеансе, после перезапуска первый запрос идёт сразу туда.
- **Exchange: сервер следит за ограниченным числом папок (Ping Status 6)**
  — список папок push сокращается до разрешённого, а не считается сбоем.
- **Ссылка письма на «data:…»** не открывается: так письмо могло показать
  в окне приложения свою страницу.

**Компьютер (Windows, macOS, Linux; решение владельца 17.11.2026):**

- **Боковая панель**: «Папки» со значком закрепления — сразу под разделами
  (значок больше не сдвигается от высоты «Избранного»), «Избранное» — внизу,
  как на телефоне.
- **Настройки без телефонных пунктов**: нет «Вибрации» в уведомлениях и
  «Листать письма свайпом» в ленте; «Общие» — «Язык» (без поворота экрана и
  виджета), «Оформление» — без виджетов; «Загрузка и вложения» — «письма на
  устройстве».
- **«Сочетания клавиш»** — в «Спец. возможностях» вместо жестов и в
  командной палитре (Ctrl+K): все клавиши писем, поиска и разделов; на Mac —
  значками ⌘ ⌃ ⇧.

## Кратко (RU / EN)

**RU.** Значки компаний находятся у большего числа писем. Календарь Google
не задерживает проверку почты, «Очистить корзину» работает в Exchange и
Gmail, перевод определяет язык надёжнее. Исправления надёжности Exchange и
IMAP, защита от ссылок «data:».

**EN.** Company icons are found for more senders. Google Calendar no longer
slows down mail checks, Empty Trash works in Exchange and Gmail, and
translation detects the language more reliably. Reliability fixes for
Exchange and IMAP, and protection against "data:" links.

## Google Play — короткий текст, если 2.6.3 уже в магазине (27 языков)

```
<ru-RU>
• Значки компаний — у большего числа писем
• Исправления и улучшения
</ru-RU>
<en-US>
• Company icons for more senders
• Bug fixes and improvements
</en-US>
<de-DE>
• Firmensymbole bei mehr Absendern
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Icônes d’entreprise pour plus d’expéditeurs
• Corrections et améliorations
</fr-FR>
<ar>
• أيقونات الشركات لعدد أكبر من المرسلين
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Céges ikonok több feladónál
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Biểu tượng công ty cho nhiều người gửi hơn
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Firmaikoner hos flere afsendere
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• סמלי חברות ליותר שולחים
• תיקונים ושיפורים
</iw-IL>
<id>
• Ikon perusahaan untuk lebih banyak pengirim
• Perbaikan dan peningkatan
</id>
<es-ES>
• Iconos de empresas para más remitentes
• Correcciones y mejoras
</es-ES>
<it-IT>
• Icone aziendali per più mittenti
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 更多发件人显示公司图标
• 问题修复和改进
</zh-CN>
<ko-KR>
• 더 많은 발신자에 회사 아이콘 표시
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Bedrijfspictogrammen bij meer afzenders
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Firmaikoner for flere avsendere
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Ikony firm przy większej liczbie nadawców
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• Ícones de empresas para mais remetentes
• Correções e melhorias
</pt-BR>
<ro>
• Pictograme de companie pentru mai mulți expeditori
• Remedieri și îmbunătățiri
</ro>
<sk>
• Ikony firiem pri viacerých odosielateľoch
• Opravy a vylepšenia
</sk>
<th>
• ไอคอนบริษัทสำหรับผู้ส่งมากขึ้น
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Daha fazla gönderen için şirket simgeleri
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Yrityskuvakkeet useammille lähettäjille
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• अधिक प्रेषकों के लिए कंपनी आइकन
• सुधार और बेहतरी
</hi-IN>
<cs-CZ>
• Ikony firem u více odesílatelů
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Företagsikoner för fler avsändare
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• より多くの差出人に会社のアイコンを表示
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Значки компаний — у большего числа писем
• Исправления и улучшения
</ru-RU>
<en-US>
• Company icons for more senders
• Bug fixes and improvements
</en-US>
<de-DE>
• Firmensymbole bei mehr Absendern
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Icônes d’entreprise pour plus d’expéditeurs
• Corrections et améliorations
</fr-FR>
```
