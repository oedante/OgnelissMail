# «Что нового» — 2.6.5 (163) вместе с 2.6.4 (162)

2.6.5 — исправления по журналам 18.11.2026 (фото собеседников Gmail,
шлюз организации и VPN) поверх 2.6.4. Номер поднят, чтобы новую сборку
можно было загрузить в Google Play и App Store Connect, даже если 2.6.4+162
туда уже попадала. Шаги владельца — `OWNER_STEPS_2.6.5.md`.

Тексты магазинов ниже — **общие для 2.6.4 и 2.6.5** (2.6.4 в магазин не
выходила). Если в магазин не выходили и 2.6.2–2.6.3, возьмите полные
тексты из `STORE_NOTES_2.6.2.md` и добавьте первые строки ниже.

## Сделано в 2.6.5

- **Фото собеседников Gmail — у всех, с кем вы переписывались** (журнал
  владельца 18.11, 15:37: «пользователи Gmail не отображаются»). Фото
  профилей Google приходили только у сохранённых контактов: у «Других
  контактов» Google по умолчанию отдаёт заглушку с буквой, а фото профиля
  надо просить отдельно — теперь приложение так и делает. Разрешения входа
  прежние, входить заново не нужно; после обновления фото проверяются
  сразу, а не через сутки, и после повторного входа — тоже сразу. Итог
  («в профилях N, поставлено M») — в журнале и в пакете диагностики.
  Человек, которому вы ни разу не писали, в «Других контактах» Google не
  появляется — его фото Google не отдаёт.
- **Шлюз организации и VPN** (журнал коллеги 18.11, 16:09: «EAS
  SendMail: HTTP 403»). Шлюз перед Exchange блокирует запросы с некоторых
  адресов — например, с VPN, — а письмо оставалось с непонятной ошибкой,
  и «Отправить снова» приходилось нажимать вручную. Теперь в «Ожидают
  отправки» — пояснение «Шлюз организации не пропустил письмо из этой сети
  (например, через VPN) — оно уйдёт само после смены сети», письмо уходит
  само сразу после смены сети или через 15 минут (чаще нельзя: такой шлюз
  считает частые повторы атакой). Около двух часов без успеха — «не
  отправлено» с уведомлением, как при других сбоях.

## 2.6.4 (162)

### Сделано в 2.6.4

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

### Добавлено 18.11.2026 (третий архив 2.6.4)

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
- **Уведомления VIP — беседой и из фоновой проверки** (Android, замечание
  владельца 18.11: «значок приложения сбоку от портрета»): письма, которые
  находила фоновая проверка или сигнал сервера, выходили без ярлыка
  беседы — Android рисовал обычный вид. Теперь, как в мессенджерах:
  портрет отправителя, значок приложения — на нём.
- **Беседы для писем от людей** (Android, ответ владельца 18.11, новый
  переключатель в «Уведомлениях», включён): портрет беседой — не только у
  VIP, а у всех писем от людей. «От человека» — не рассылка и не служебное
  письмо, адресатов в «Кому» и «Копии» не больше 50, вы среди них
  поимённо (не через общий список), отправитель — коллега (домен
  рабочего ящика) или есть в контактах. Рассылки, объявления на всех и
  письма незнакомых — обычным видом.

**Настройки — на ожидаемых местах (замечание владельца 18.11):**

- **«Картинки в письмах»** — в «Почта → Чтение»: загружать сразу или по
  кнопке, доверенные отправители.
- **«Синхронизация»** (проверка всех ящиков, расписание, конфликты) —
  отдельный пункт в «Аккаунтах», а не в «Дополнительно».
- **«Иконки организаций»** и **«Область чтения»** — в «Лента и письма»
  (было: «Антифишинг» и «Оформление»).
- Поиск по настройкам, подсказки и «Вопросы и ответы» ведут на новые
  места.
- **Справка по долгому нажатию** (просьба владельца 18.11): удержите
  пункт настроек (на компьютере — правая кнопка мыши) — откроется, что он
  делает и на что влияет, и ответы про него из «Вопросов и ответов» с
  кнопкой перехода к ним. Значок «?» у названия показывает то же. Новый
  вопрос «Как узнать, что делает настройка?» (27 языков).

**Погода в «Моём дне» (сервер, 18.11):**

- Поиск города находит и посёлки, и аэропорты: «Сабетта» не находилась —
  служба знала только города от 15 000 жителей. Теперь — города от 1000
  жителей по всему миру и все населённые пункты и аэропорты России.
  Работает после обновления службы погоды на сервере
  (`OWNER_STEPS_2.6.4.md`, раздел 4); приложение обновлять не нужно.

## Кратко (RU / EN)

**RU.** Работа в корпоративной сети: прокси и PAC, как у браузера, и
сертификаты клиента для серверов, которые их требуют (файл .p12, на
Android — и сертификат устройства), с ключами MDM. Фото собеседников
Gmail и значки компаний — у большего числа писем. Письмо, которое шлюз
организации не пропустил из сети (например, через VPN), уходит само после
смены сети. На компьютере работают сочетания клавиш, на Mac — с ⌘.
Настройки — на ожидаемых местах, а долгое нажатие на пункт объясняет, что
он делает. Исправления надёжности Exchange, IMAP и iCloud.

**EN.** Works in corporate networks: proxy and PAC the way your browser
uses them, and client certificates for servers that require them (a .p12
file, or a device certificate on Android), with MDM keys. Gmail contact
photos and company icons appear for more senders. A message your
organization's gateway blocked from the current network (for example, a
VPN) is sent automatically once the network changes. Keyboard shortcuts
work on desktop, with ⌘ on Mac. Settings are where you expect them, and a
long press on a setting explains what it does. Reliability fixes for
Exchange, IMAP and iCloud.

## Google Play — общий текст 2.6.4 и 2.6.5 (27 языков)

```
<ru-RU>
• Корпоративная сеть: прокси, PAC и сертификаты клиента
• Фото собеседников Gmail и значки компаний — у большего числа писем
• Справка по долгому нажатию на пункт настроек
• Исправления и улучшения
</ru-RU>
<en-US>
• Corporate networks: proxy, PAC and client certificates
• Gmail contact photos and company icons for more senders
• Long-press a setting to see what it does
• Bug fixes and improvements
</en-US>
<de-DE>
• Firmennetze: Proxy, PAC und Client-Zertifikate
• Gmail-Kontaktfotos und Firmensymbole bei mehr Absendern
• Lange auf eine Einstellung tippen, um zu sehen, was sie bewirkt
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Réseaux d’entreprise : proxy, PAC et certificats client
• Photos des contacts Gmail et icônes d’entreprise pour plus d’expéditeurs
• Appui long sur un réglage pour savoir ce qu’il fait
• Corrections et améliorations
</fr-FR>
<ar>
• شبكات الشركات: الوكيل وPAC وشهادات العميل
• صور جهات اتصال Gmail وأيقونات الشركات لعدد أكبر من المرسلين
• اضغط مطولًا على أي إعداد لمعرفة وظيفته
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Céges hálózatok: proxy, PAC és ügyféltanúsítványok
• Gmail-névjegyfotók és céges ikonok több feladónál
• Nyomja hosszan a beállítást, és megtudja, mire való
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Mạng doanh nghiệp: proxy, PAC và chứng chỉ máy khách
• Ảnh liên hệ Gmail và biểu tượng công ty cho nhiều người gửi hơn
• Nhấn giữ một mục cài đặt để xem nó làm gì
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Firmanetværk: proxy, PAC og klientcertifikater
• Gmail-kontaktbilleder og firmaikoner hos flere afsendere
• Tryk længe på en indstilling for at se, hvad den gør
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• רשתות ארגוניות: פרוקסי, PAC ותעודות לקוח
• תמונות אנשי קשר מ-Gmail וסמלי חברות ליותר שולחים
• לחיצה ארוכה על הגדרה מסבירה מה היא עושה
• תיקונים ושיפורים
</iw-IL>
<id>
• Jaringan perusahaan: proxy, PAC, dan sertifikat klien
• Foto kontak Gmail dan ikon perusahaan untuk lebih banyak pengirim
• Tekan lama pengaturan untuk melihat fungsinya
• Perbaikan dan peningkatan
</id>
<es-ES>
• Redes corporativas: proxy, PAC y certificados de cliente
• Fotos de contactos de Gmail e iconos de empresas para más remitentes
• Mantén pulsado un ajuste para ver qué hace
• Correcciones y mejoras
</es-ES>
<it-IT>
• Reti aziendali: proxy, PAC e certificati client
• Foto dei contatti Gmail e icone aziendali per più mittenti
• Tieni premuta un’impostazione per sapere cosa fa
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 企业网络：代理、PAC 和客户端证书
• 更多发件人显示 Gmail 联系人照片和公司图标
• 长按设置项即可查看其作用
• 问题修复和改进
</zh-CN>
<ko-KR>
• 회사 네트워크: 프록시, PAC 및 클라이언트 인증서
• 더 많은 발신자에 Gmail 연락처 사진과 회사 아이콘 표시
• 설정을 길게 누르면 어떤 기능인지 알려 줍니다
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Bedrijfsnetwerken: proxy, PAC en clientcertificaten
• Gmail-contactfoto’s en bedrijfspictogrammen bij meer afzenders
• Houd een instelling ingedrukt om te zien wat die doet
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Bedriftsnettverk: proxy, PAC og klientsertifikater
• Gmail-kontaktbilder og firmaikoner for flere avsendere
• Trykk lenge på en innstilling for å se hva den gjør
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Sieci firmowe: proxy, PAC i certyfikaty klienta
• Zdjęcia kontaktów Gmail i ikony firm przy większej liczbie nadawców
• Przytrzymaj ustawienie, aby zobaczyć, do czego służy
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• Redes corporativas: proxy, PAC e certificados de cliente
• Fotos de contatos do Gmail e ícones de empresas para mais remetentes
• Toque e segure uma configuração para ver o que ela faz
• Correções e melhorias
</pt-BR>
<ro>
• Rețele de companie: proxy, PAC și certificate client
• Fotografii ale contactelor Gmail și pictograme de companie pentru mai mulți expeditori
• Apăsați lung pe o setare ca să vedeți ce face
• Remedieri și îmbunătățiri
</ro>
<sk>
• Firemné siete: proxy, PAC a klientske certifikáty
• Fotky kontaktov z Gmailu a ikony firiem pri viacerých odosielateľoch
• Podržte nastavenie a zistíte, na čo slúži
• Opravy a vylepšenia
</sk>
<th>
• เครือข่ายองค์กร: พร็อกซี, PAC และใบรับรองไคลเอนต์
• รูปผู้ติดต่อ Gmail และไอคอนบริษัทสำหรับผู้ส่งมากขึ้น
• แตะค้างที่การตั้งค่าเพื่อดูว่าใช้ทำอะไร
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Kurumsal ağlar: proxy, PAC ve istemci sertifikaları
• Daha fazla gönderen için Gmail kişi fotoğrafları ve şirket simgeleri
• Ne işe yaradığını görmek için bir ayara uzun basın
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Yritysverkot: välityspalvelin, PAC ja asiakasvarmenteet
• Gmail-yhteystietojen kuvat ja yrityskuvakkeet useammille lähettäjille
• Paina asetusta pitkään, niin näet mitä se tekee
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• कॉर्पोरेट नेटवर्क: प्रॉक्सी, PAC और क्लाइंट प्रमाणपत्र
• अधिक प्रेषकों के लिए Gmail संपर्क फ़ोटो और कंपनी आइकन
• सेटिंग को देर तक दबाएँ और जानें कि वह क्या करती है
• सुधार और बेहतरी
</hi-IN>
<cs-CZ>
• Firemní sítě: proxy, PAC a klientské certifikáty
• Fotky kontaktů z Gmailu a ikony firem u více odesílatelů
• Podržením nastavení zjistíte, k čemu slouží
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Företagsnätverk: proxy, PAC och klientcertifikat
• Gmail-kontaktfoton och företagsikoner för fler avsändare
• Tryck länge på en inställning för att se vad den gör
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• 企業ネットワーク：プロキシ、PAC、クライアント証明書
• より多くの差出人に Gmail の連絡先写真と会社のアイコンを表示
• 設定を長押しすると、その働きが表示されます
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

Строка «Mac: …» — только в тексте для Mac; для iPhone и iPad её уберите.

```
<ru-RU>
• Корпоративная сеть: прокси, PAC и сертификаты клиента
• Фото собеседников Gmail и значки компаний — у большего числа писем
• Mac: сочетания клавиш работают, и с ⌘
• Справка по долгому нажатию на пункт настроек
• Исправления и улучшения
</ru-RU>
<en-US>
• Corporate networks: proxy, PAC and client certificates
• Gmail contact photos and company icons for more senders
• Mac: keyboard shortcuts work, including ⌘
• Long-press a setting to see what it does
• Bug fixes and improvements
</en-US>
<de-DE>
• Firmennetze: Proxy, PAC und Client-Zertifikate
• Gmail-Kontaktfotos und Firmensymbole bei mehr Absendern
• Mac: Tastenkürzel funktionieren, auch mit ⌘
• Lange auf eine Einstellung tippen, um zu sehen, was sie bewirkt
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Réseaux d’entreprise : proxy, PAC et certificats client
• Photos des contacts Gmail et icônes d’entreprise pour plus d’expéditeurs
• Mac : les raccourcis clavier fonctionnent, aussi avec ⌘
• Appui long sur un réglage pour savoir ce qu’il fait
• Corrections et améliorations
</fr-FR>
```
