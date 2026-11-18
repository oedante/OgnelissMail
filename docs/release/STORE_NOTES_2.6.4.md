# «Что нового» — 2.6.4 (162), относительно 2.6.3

2.6.3 (161) ушла тестировщикам; 2.6.4 — исправления по журналу владельца
17.11.2026 (15:43) и пункты технического долга из плана после аудитов
(`docs/plan/PLAN_2026-11.md`). Шаги владельца — `OWNER_STEPS_2.6.4.md`.

Тексты магазинов: если в магазин ещё не выходили 2.6.2 и 2.6.3 (2.6.4 —
первая сборка после 2.6.1), берите полные тексты из `STORE_NOTES_2.6.2.md`
(они покрывают 2.6.2–2.6.4) и добавьте первые две строки ниже. Если 2.6.3
уже в магазине — короткий текст ниже.

Версия не менялась (2.6.4+162): в третьем архиве 2.6.4 добавлено то, что
сделано 17–18.11 (раздел «Добавлено 18.11.2026»). Если 2.6.4+162 уже
загружена в Google Play или App Store Connect, новой сборке нужен больший
номер — скажите, подниму до 2.6.5+163.

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

## Добавлено 18.11.2026 (третий архив 2.6.4)

**Корпоративная сеть (план 08.11.2026):**

- **Прокси и PAC.** В сети с обязательным прокси Exchange, IMAP и SMTP
  раньше не подключались. Теперь приложение находит прокси, как браузер:
  Android — прокси сети, PAC и политика устройства; iPhone, iPad и Mac —
  настройки сети и профиля; Windows — ручной прокси, PAC и WPAD (как Edge,
  в том числе групповой политикой); Linux — переменные окружения и
  настройки GNOME. Через прокси идёт туннель, шифрование остаётся до
  самого сервера почты, проверка и закрепление его сертификата — тоже.
  Прокси не ответил — соединение напрямую. Ключи MDM: `http_proxy`,
  `proxy_bypass`, `pac_url`; строка «Прокси организации» в «Управляется
  организацией».
- **Сертификаты клиента (mTLS)** — если сервер почты или обратный прокси
  требует сертификат устройства. «Безопасность → Сертификаты клиента»:
  файл .p12/.pfx с паролем (ключи RSA и EC, старые файлы Windows и новые)
  и домены серверов, которым его предъявлять. Работает для Exchange
  (ActiveSync, EWS, Graph), IMAP, SMTP и календарей, через прокси тоже.
  На Android — ещё и **сертификат устройства** из системного хранилища
  (установленный на телефон или выданный организацией через Intune и
  другие консоли) для Exchange ActiveSync. Файл и пароль хранятся в
  защищённом хранилище системы. Ключи MDM: `client_cert_pkcs12`,
  `client_cert_password`, `client_cert_domains`, `client_cert_alias`.

**Компьютер (замечание владельца 17.11: «сочетания клавиш не
реагировали»):**

- **Сочетания клавиш работают** на Windows и Mac: J/K и стрелки по ленте,
  Ctrl+R, Ctrl+Shift+R, Ctrl+F, Delete и другие — сразу после запуска и
  после закрытия письма, без щелчка мышью в ленту.
- **Mac — с ⌘**: ⌘R, ⇧⌘R, ⌘U, ⌘P, ⌘E, ⌘1…5, ⌘K; ⌘F — поиск в письме,
  ⌘J — переслать (как в Outlook для Mac), ⌘⌫ — удалить, ⌃Q — прочитано
  (⌘Q оставлен системе). Справка «Сочетания клавиш» — теми же значками.

**По журналу 18.11.2026:**

- **iCloud «требуется вход»** после того, как вход уже восстановился:
  отметка снималась только в базе, а проверки продолжали пропускать ящик.
  Теперь список ящиков перечитывается.
- **«Войти снова»** с паролем: сохранённый пароль уже стоит в поле
  (точками) — можно войти, ничего не вводя; показать сохранённый пароль
  нельзя, ввести новый — можно.
- **Названия ящиков** («Работа», «Семья») — при долгом нажатии на «Почту»
  и в выборе ящика в календаре, контактах, задачах и поручениях; адрес —
  под названием.
- **Exchange:** письмо, найденное поиском на сервере, удаляется без
  бесконечных повторов (сервер отвечал Status 4).

**Настройки — на ожидаемых местах (замечание владельца 18.11):**

- **«Картинки в письмах»** — в «Почта → Чтение»: загружать сразу или по
  кнопке, доверенные отправители.
- **«Синхронизация»** (проверка всех ящиков, расписание, конфликты) —
  отдельный пункт в «Аккаунтах», а не в «Дополнительно».
- **«Иконки организаций»** и **«Область чтения»** — в «Лента и письма»
  (было: «Антифишинг» и «Оформление»).
- Поиск по настройкам, подсказки и «Вопросы и ответы» ведут на новые
  места.

## Кратко (RU / EN)

**RU.** Работа в корпоративной сети: прокси и PAC, как у браузера, и
сертификаты клиента для серверов, которые их требуют (файл .p12, на
Android — и сертификат устройства), с ключами MDM. На компьютере работают
сочетания клавиш, на Mac — с ⌘. Значки компаний находятся у большего числа
писем, календарь Google не задерживает проверку почты, «Очистить корзину»
работает в Exchange и Gmail. Настройки — на ожидаемых местах, исправления
надёжности Exchange, IMAP и iCloud.

**EN.** Works in corporate networks: proxy and PAC the way your browser
uses them, and client certificates for servers that require them (a .p12
file, or a device certificate on Android), with MDM keys. Keyboard
shortcuts work on desktop, with ⌘ on Mac. Company icons are found for more
senders, Google Calendar no longer slows down mail checks, and Empty Trash
works in Exchange and Gmail. Settings are where you expect them, plus
reliability fixes for Exchange, IMAP and iCloud.

## Google Play — короткий текст, если 2.6.3 уже в магазине (27 языков)

```
<ru-RU>
• Корпоративная сеть: прокси, PAC и сертификаты клиента
• Значки компаний — у большего числа писем
• Исправления и улучшения
</ru-RU>
<en-US>
• Corporate networks: proxy, PAC and client certificates
• Company icons for more senders
• Bug fixes and improvements
</en-US>
<de-DE>
• Firmennetze: Proxy, PAC und Client-Zertifikate
• Firmensymbole bei mehr Absendern
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Réseaux d’entreprise : proxy, PAC et certificats client
• Icônes d’entreprise pour plus d’expéditeurs
• Corrections et améliorations
</fr-FR>
<ar>
• شبكات الشركات: الوكيل وPAC وشهادات العميل
• أيقونات الشركات لعدد أكبر من المرسلين
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Céges hálózatok: proxy, PAC és ügyféltanúsítványok
• Céges ikonok több feladónál
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Mạng doanh nghiệp: proxy, PAC và chứng chỉ máy khách
• Biểu tượng công ty cho nhiều người gửi hơn
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Firmanetværk: proxy, PAC og klientcertifikater
• Firmaikoner hos flere afsendere
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• רשתות ארגוניות: פרוקסי, PAC ותעודות לקוח
• סמלי חברות ליותר שולחים
• תיקונים ושיפורים
</iw-IL>
<id>
• Jaringan perusahaan: proxy, PAC, dan sertifikat klien
• Ikon perusahaan untuk lebih banyak pengirim
• Perbaikan dan peningkatan
</id>
<es-ES>
• Redes corporativas: proxy, PAC y certificados de cliente
• Iconos de empresas para más remitentes
• Correcciones y mejoras
</es-ES>
<it-IT>
• Reti aziendali: proxy, PAC e certificati client
• Icone aziendali per più mittenti
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 企业网络：代理、PAC 和客户端证书
• 更多发件人显示公司图标
• 问题修复和改进
</zh-CN>
<ko-KR>
• 회사 네트워크: 프록시, PAC 및 클라이언트 인증서
• 더 많은 발신자에 회사 아이콘 표시
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Bedrijfsnetwerken: proxy, PAC en clientcertificaten
• Bedrijfspictogrammen bij meer afzenders
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Bedriftsnettverk: proxy, PAC og klientsertifikater
• Firmaikoner for flere avsendere
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Sieci firmowe: proxy, PAC i certyfikaty klienta
• Ikony firm przy większej liczbie nadawców
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• Redes corporativas: proxy, PAC e certificados de cliente
• Ícones de empresas para mais remetentes
• Correções e melhorias
</pt-BR>
<ro>
• Rețele de companie: proxy, PAC și certificate client
• Pictograme de companie pentru mai mulți expeditori
• Remedieri și îmbunătățiri
</ro>
<sk>
• Firemné siete: proxy, PAC a klientske certifikáty
• Ikony firiem pri viacerých odosielateľoch
• Opravy a vylepšenia
</sk>
<th>
• เครือข่ายองค์กร: พร็อกซี, PAC และใบรับรองไคลเอนต์
• ไอคอนบริษัทสำหรับผู้ส่งมากขึ้น
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Kurumsal ağlar: proxy, PAC ve istemci sertifikaları
• Daha fazla gönderen için şirket simgeleri
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Yritysverkot: välityspalvelin, PAC ja asiakasvarmenteet
• Yrityskuvakkeet useammille lähettäjille
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• कॉर्पोरेट नेटवर्क: प्रॉक्सी, PAC और क्लाइंट प्रमाणपत्र
• अधिक प्रेषकों के लिए कंपनी आइकन
• सुधार और बेहतरी
</hi-IN>
<cs-CZ>
• Firemní sítě: proxy, PAC a klientské certifikáty
• Ikony firem u více odesílatelů
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Företagsnätverk: proxy, PAC och klientcertifikat
• Företagsikoner för fler avsändare
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• 企業ネットワーク：プロキシ、PAC、クライアント証明書
• より多くの差出人に会社のアイコンを表示
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Строка «Mac: …» — только в тексте для Mac; для iPhone и iPad её уберите.

```
<ru-RU>
• Корпоративная сеть: прокси, PAC и сертификаты клиента
• Значки компаний — у большего числа писем
• Mac: сочетания клавиш работают, и с ⌘
• Исправления и улучшения
</ru-RU>
<en-US>
• Corporate networks: proxy, PAC and client certificates
• Company icons for more senders
• Mac: keyboard shortcuts work, including ⌘
• Bug fixes and improvements
</en-US>
<de-DE>
• Firmennetze: Proxy, PAC und Client-Zertifikate
• Firmensymbole bei mehr Absendern
• Mac: Tastenkürzel funktionieren, auch mit ⌘
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Réseaux d’entreprise : proxy, PAC et certificats client
• Icônes d’entreprise pour plus d’expéditeurs
• Mac : les raccourcis clavier fonctionnent, aussi avec ⌘
• Corrections et améliorations
</fr-FR>
```
