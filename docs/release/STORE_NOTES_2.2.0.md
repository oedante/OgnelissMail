# «Что нового» — 2.2.0 (146)

Номер — просьба владельца 08.11.2026: 2.1.0 ушла в тестирование, «Подними
версию и продолжаем по плану». Выпуск — просьба владельца 09.11.2026.
Тексты для магазинов — в конце (App Store — ru, en, de, fr; Google Play —
27 языков); ниже — полный список изменений.

## Сделано (08.11.2026)

- **Подпись Outlook в две колонки** (письмо владельца «FW: Объявление»):
  колонка таблицы не уже своего самого длинного слова — слова больше не
  рвутся по буквам; все таблицы простого показа — одной раскладкой
  (рамки — одной линией, фон ячейки — на всю строку).
- **«+» в быстром ответе**: фото, файл или шаблон; ответ может быть без
  текста; размер фото — как в редакторе письма.
- **«Файлы и ссылки» беседы** (меню «⋮» беседы): все вложения и ссылки
  писем беседы, самые новые — первыми.
- **Поиск в письме** («⋮ → Найти в письме», F4 на компьютере): подсветка,
  «3 из 12», переход по совпадениям. **Поиск по беседе** — значок поиска в
  беседе: письма с совпадением выделены, открытое письмо — с тем же поиском.

## Сделано (09.11.2026)

- **Часы «Моего дня»**: полоска карточки цифры — ровно посередине
  (замечание владельца со снимком).
- **@-упоминания**: значок «@» в строке ленты у писем, где вас упомянули
  (ссылка-упоминание Outlook и Gmail или «@Имя Фамилия»; цитата прежней
  переписки не считается), фильтр «Упоминания».
- **✓ и ✓✓ у своих писем**: ✓ — доставлено (отчёт о доставке), ✓✓ —
  прочитано (отчёт о прочтении); в «Отправленных» и в беседе, в письме —
  «Прочитано: адрес». Уведомления о самих отчётах о прочтении не приходят.
- **Запрос уведомления о прочтении** (решение владельца 09.11.2026): для
  всех писем — «Настройки → Почта → Отправка → Уведомление о прочтении
  для всех писем» (по умолчанию выключено), для одного письма — меню «⋮»
  редактора «Запросить уведомление о прочтении»; быстрый ответ — по
  настройке. Обычная почта и ActiveSync — заголовок
  Disposition-Notification-To, Exchange (EWS) — IsReadReceiptRequested.

- **Беседа как чат**: кнопка «к последнему письму», когда беседа прокручена
  назад, и число писем, пришедших за это время.
- **Письма с адаптивной вёрсткой** (`@media`) — простым видом, а не окном
  браузера, если в них ничего не скрыто стилями.
- **Приглашение на встречу в письме**: повторение («Еженедельно: пн, ср»),
  участники и ваш календарь в это время — «Пересекается: «Планёрка»,
  10:00–10:45» или «В это время вы свободны».
- **«Обычный размер» после увеличения щипком** — пилюлей в строке с
  переводом и предупреждениями, а не кнопкой над письмом, которая
  смещалась при перемещении по письму (просьба владельца 09.11.2026).
- **Свайп у края**: полоса края, от которой свайп открывает меню, — уже
  (свайп строки у края больше не открывает меню).

- **«Мой день» — доска и шкала** (решения владельца 09.11.2026): доска —
  вид по умолчанию, второй вид — шкала дня (встречи блоками, задачи со
  своим временем, свободные окна, линия «сейчас»); задачу перетаскивают из
  «Без времени» на шкалу — время хранится только в приложении. Прежний
  список убран. На доске — «Просрочено» (несделанное со вчера и раньше) с
  кнопкой «Всё на сегодня»; долгое нажатие на задачу — «Сегодня»,
  «Завтра», «На следующей неделе», «Выбрать дату», «Без срока»,
  «Выполнено», «Удалить» (и в «Задачах»).
- **Поручения** — отдельный раздел меню: «Я поручил» и «Мне поручили»,
  статусы «Новое → В работе → На проверке → Выполнено», карточка с
  историей, быстрые действия по долгому нажатию. Поручить можно из
  письма, из календаря и в самом разделе; исполнитель получает обычное
  письмо и отвечает из любой почты — «Принято» и «Готово» на 27 языках
  меняют статус сами; с Ogneliss Mail — кнопками над письмом. Текущие
  поручения — и в «Моём дне».
- **Для ИТ-служб — новые ключи MDM** (docs/guides/MDM.md): почта на
  устройстве не дольше N дней, запрет вложений на устройстве, блокировка
  после бездействия, без входа по отпечатку и лицу, без внешних служб
  (погода, логотипы BIMI, сигналы и вход через сервер Ogneliss),
  закреплённый ящик организации, протокол Exchange (ActiveSync или EWS),
  только шифрованные соединения, корневые сертификаты организации, запрет
  доверять сертификатам самому, запрет переноса контактов и встреч в
  устройство. На Android — отчёт для консоли MDM: настройки приняты,
  какие значения не распознаны, добавлен ли ящик, задан ли PIN.
- **Свайпы — видно, что сделано**: после «Прочитано», «Флаг», «На
  контроль» (свайпом или кнопкой) поверх строки — результат («Прочитано»,
  «Флажок снят», «На контроле», «Снято с контроля») и «Отменить», в ленте и
  в беседе; у края при свайпе — подпись действия; не дотянули — строка
  возвращается. Логика прежняя (решение владельца 10.11.2026): одно
  действие на стороне срабатывает сразу, два — кнопки на выбор. По желанию
  — «Настройки → Свайпы → Короткий и длинный свайп»: короткий свайп —
  первое действие, длинный — второе. При первом запуске строка один раз сама
  слегка отъезжает — подсказка. В беседе у письма — отметка «На контроле»;
  подписи папок — только когда письмо не на обычном месте (без «Входящих»
  на каждом письме), названия папок — на языке приложения.
- **Прехедер рассылок** (вопрос владельца 10.11.2026): строка превью в
  ленте и в уведомлении — скрытый текст, который отправитель задумал как
  превью (как в Gmail и Почте Apple), а не «Если письмо не отображается,
  откройте его в браузере». В уведомлении — тоже прехедер вместо начала
  письма (и у Exchange, и при «больше строк в уведомлении»). Для уже
  загруженных писем превью пересчитается один раз после обновления. В самом
  письме прехедер по-прежнему скрыт.
- **Текст письма в уведомлении — и у ящиков IMAP** (Яндекс, Mail.ru, Gmail
  по IMAP; журнал владельца 10.11.2026): синхронизация берёт заголовки, а
  текст новых писем загружался на полсекунды позже уведомления — в нём были
  только отправитель и тема. Теперь текст — до уведомления (не дольше 8 с).
- **Уведомления о новом письме — полное имя отправителя**, без сокращения
  до «Фамилия И.О.» (просьба владельца 10.11.2026); «Фамилия, Имя» из
  Exchange — без запятой.
- **Совместимость со шлюзом на всех платформах**: приложение
  представляется штатной почтой своей платформы — Windows (Почта Windows и
  Outlook), Mac (Почта Apple), Linux (Thunderbird), как раньше на iPhone и
  Android.
- **Нижняя панель — свои разделы** (просьба пользователя 10.11.2026):
  «Настройки → Общие → Нижняя панель» — по два места слева и справа от
  «Создать» (она всегда в центре); на выбор Почта, Календарь, Контакты,
  Задачи, Мой день, Заметки, Поручения, Вложения (файловый хаб) и Меню.
  Раздел, убранный с панели, сам появляется в «Избранном» меню; в
  «Избранное» можно добавить и Календарь, и Контакты. «Почта» и «Меню» на
  панели всегда (решение владельца 10.11.2026): «Почту» можно поставить на
  любое место, «Меню» — с левого или правого края (нажатием на его место
  или в «Меню ящиков и папок»), с той же стороны выезжает меню. Поручения и
  Вложения открываются с нижней панелью.
- **Вход в Яндекс без сервера Ogneliss** (телефон и Mac, решение владельца
  10.11.2026): браузер Яндекса → выбор учётной записи → обратно в
  приложение по схеме `yx<ClientID>`, как у LoginSDK Яндекса (сам SDK не
  подключали); токен обновляется прямо у Яндекса. Windows и Linux — как
  раньше, через сервер входа. Уже добавленные ящики Яндекса работают как
  были; «Войти снова» переводит ящик на новый вход.
- **Перевод писем на Windows**: на компьютере, как на телефоне — плашка
  «Перевести», перевод своего письма, «Всегда переводить с …». Движок —
  Bergamot (Mozilla), текст писем не покидает компьютер; языки (~45 МБ)
  скачиваются с сервера Ogneliss при первом переводе.

Зависимости: новых пакетов pub.dev нет. Android: androidx.enterprise:enterprise-feedback 1.1.0
(Apache-2.0) — отчёт консоли MDM; текст лицензии — в «Текстах лицензий»,
строка — в docs/LICENSING.md. Windows: движок перевода Bergamot 0.4.9 (npm,
MPL-2.0; скачивается при сборке, `tool/bergamot`), модели Firefox Translations
(MPL-2.0) — с сервера Ogneliss (`server/translate-models`, развернуть до
выпуска), названия языков — Unicode CLDR; тексты — в «Текстах лицензий».
База: версия схемы 28 (колонка `mentions_me`, добавляется при обновлении).
Платформы: `project.pbxproj`, `Runner.entitlements`, `Info.plist` и
манифест Android не менялись. Иконка — прежняя, тёмная (светлую вернули
обратно по просьбе владельца 09.11.2026).

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• «Мой день»: доска и шкала дня, перенос задач долгим нажатием
• Поручения из письма и календаря: статус меняется по ответам
• Свайпы: на строке видно, что сделано, и есть «Отменить»
• ✓ и ✓✓ у своих писем, «@» там, где вас упомянули
• Поиск в письме и в беседе, «+» в быстром ответе
• Нижняя панель на свой вкус: например, «Мой день» вместо «Контактов»
</ru-RU>
<en-US>
• My day: board and day timeline, move tasks with a long press
• Assignments from an email or the calendar: status follows the replies
• Swipes: the row shows what was done, with Undo
• ✓ and ✓✓ on your sent emails, “@” where you are mentioned
• Find in an email and in a conversation, “+” in quick reply
• Customizable bottom bar: for example, My day instead of Contacts
</en-US>
<de-DE>
• Mein Tag: Board und Tagesleiste, Aufgaben per langem Tippen verschieben
• Aufträge aus E-Mail oder Kalender: Status folgt den Antworten
• Wischgesten: die Zeile zeigt, was erledigt wurde, mit „Rückgängig“
• ✓ und ✓✓ bei eigenen E-Mails, „@“ wo Sie erwähnt werden
• Suche in E-Mail und Unterhaltung, „+“ in der Schnellantwort
• Untere Leiste nach Wunsch: zum Beispiel Mein Tag statt Kontakte
</de-DE>
<fr-FR>
• Ma journée : tableau et frise du jour, déplacer les tâches par appui long
• Missions depuis un e-mail ou le calendrier : le statut suit les réponses
• Balayages : la ligne indique ce qui a été fait, avec « Annuler »
• ✓ et ✓✓ sur vos e-mails envoyés, « @ » là où l’on vous mentionne
• Recherche dans un e-mail et une conversation, « + » dans la réponse rapide
• Barre du bas au choix : Ma journée au lieu de Contacts, par exemple
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 450.

```
<ru-RU>
• «Мой день»: доска и шкала дня, перенос задач долгим нажатием
• Поручения из письма и календаря: статус меняется по ответам
• Свайпы: на строке видно, что сделано, и есть «Отменить»
• ✓ и ✓✓ у своих писем, «@» там, где вас упомянули
• Поиск в письме и в беседе, «+» в быстром ответе
• Нижняя панель на свой вкус: например, «Мой день» вместо «Контактов»
</ru-RU>
<en-US>
• My day: board and day timeline, move tasks with a long press
• Assignments from an email or the calendar: status follows the replies
• Swipes: the row shows what was done, with Undo
• ✓ and ✓✓ on your sent emails, “@” where you are mentioned
• Find in an email and in a conversation, “+” in quick reply
• Customizable bottom bar: for example, My day instead of Contacts
</en-US>
<de-DE>
• Mein Tag: Board und Tagesleiste, Aufgaben per langem Tippen verschieben
• Aufträge aus E-Mail oder Kalender: Status folgt den Antworten
• Wischgesten: die Zeile zeigt, was erledigt wurde, mit „Rückgängig“
• ✓ und ✓✓ bei eigenen E-Mails, „@“ wo Sie erwähnt werden
• Suche in E-Mail und Unterhaltung, „+“ in der Schnellantwort
• Untere Leiste nach Wunsch: zum Beispiel Mein Tag statt Kontakte
</de-DE>
<fr-FR>
• Ma journée : tableau et frise du jour, déplacer les tâches par appui long
• Missions depuis un e-mail ou le calendrier : le statut suit les réponses
• Balayages : la ligne indique ce qui a été fait, avec « Annuler »
• ✓ et ✓✓ sur vos e-mails envoyés, « @ » là où l’on vous mentionne
• Recherche dans un e-mail et une conversation, « + » dans la réponse rapide
• Barre du bas au choix : Ma journée au lieu de Contacts, par exemple
</fr-FR>
<ar>
• «يومي»: لوحة ومخطط زمني لليوم، ونقل المهام بضغطة مطوّلة
• التكليفات من رسالة أو من التقويم: تتغير الحالة حسب الردود
• السحب: يُظهر الصف ما تم مع زر «تراجع»
• ✓ و✓✓ على رسائلك المرسلة، و«@» حيث تمت الإشارة إليك
• البحث في الرسالة وفي المحادثة، و«+» في الرد السريع
• شريط سفلي كما تريد: مثلًا «يومي» بدل «جهات الاتصال»
</ar>
<hu-HU>
• Napom: tábla és napi idővonal, feladatok áthelyezése hosszú nyomással
• Megbízások levélből vagy naptárból: az állapot a válaszokat követi
• Húzás: a sor mutatja, mi történt, Visszavonással
• ✓ és ✓✓ az elküldött leveleken, „@” ahol megemlítették
• Keresés levélben és beszélgetésben, „+” a gyors válaszban
• Testreszabható alsó sáv: például Napom a Névjegyek helyett
</hu-HU>
<vi>
• Ngày của tôi: bảng và dòng thời gian trong ngày, nhấn giữ để dời việc
• Giao việc từ thư hoặc lịch: trạng thái cập nhật theo thư trả lời
• Vuốt: dòng hiển thị việc đã làm, kèm Hoàn tác
• ✓ và ✓✓ trên thư đã gửi, “@” ở nơi bạn được nhắc tên
• Tìm trong thư và trong cuộc hội thoại, “+” trong trả lời nhanh
• Thanh dưới cùng tùy chỉnh: ví dụ Ngày của tôi thay cho Danh bạ
</vi>
<da-DK>
• Min dag: tavle og tidslinje for dagen, flyt opgaver med langt tryk
• Opgaver fra en mail eller kalenderen: status følger svarene
• Swipe: rækken viser, hvad der skete, med Fortryd
• ✓ og ✓✓ på dine sendte mails, “@” hvor du er nævnt
• Søg i en mail og i en samtale, “+” i hurtigsvar
• Nederste bjælke efter ønske: f.eks. Min dag i stedet for Kontakter
</da-DK>
<iw-IL>
• היום שלי: לוח וציר זמן יומי, העברת משימות בלחיצה ארוכה
• מטלות ממייל או מהיומן: הסטטוס משתנה לפי התשובות
• החלקה: השורה מציגה מה בוצע, עם „ביטול”
• ✓ ו-✓✓ במיילים ששלחת, „@” היכן שהזכירו אותך
• חיפוש במייל ובשיחה, „+” בתשובה המהירה
• סרגל תחתון לפי בחירתכם: למשל „היום שלי” במקום „אנשי קשר”
</iw-IL>
<id>
• Hari Saya: papan dan linimasa hari, pindahkan tugas dengan tekan lama
• Penugasan dari email atau kalender: status mengikuti balasan
• Usap: baris menunjukkan apa yang dilakukan, dengan Urungkan
• ✓ dan ✓✓ pada email terkirim, “@” saat Anda disebut
• Cari dalam email dan percakapan, “+” di balasan cepat
• Bilah bawah sesuai selera: misalnya Hari Saya, bukan Kontak
</id>
<es-ES>
• Mi día: tablero y línea del día, mueve tareas con una pulsación larga
• Encargos desde un correo o el calendario: el estado sigue las respuestas
• Deslizar: la fila muestra lo que se hizo, con Deshacer
• ✓ y ✓✓ en tus correos enviados, «@» donde te mencionan
• Búsqueda en un correo y en una conversación, «+» en la respuesta rápida
• Barra inferior a tu gusto: por ejemplo, Mi día en lugar de Contactos
</es-ES>
<it-IT>
• La mia giornata: bacheca e linea del giorno, sposta le attività con pressione prolungata
• Incarichi da un’email o dal calendario: lo stato segue le risposte
• Scorrimento: la riga mostra cosa è stato fatto, con Annulla
• ✓ e ✓✓ sulle email inviate, «@» dove vieni menzionato
• Cerca in un’email e in una conversazione, «+» nella risposta rapida
• Barra inferiore a piacere: ad esempio La mia giornata al posto di Contatti
</it-IT>
<zh-CN>
• 我的一天：看板和当日时间轴，长按即可调整任务
• 从邮件或日历分派任务：状态随回复自动更新
• 滑动：行上显示已完成的操作，并可“撤销”
• 已发邮件显示 ✓ 和 ✓✓，被提及处显示“@”
• 在邮件和会话中查找，快速回复中的“+”
• 底部栏可自定义：例如用“我的一天”替换“联系人”
</zh-CN>
<ko-KR>
• 나의 하루: 보드와 하루 타임라인, 길게 눌러 할 일 옮기기
• 메일이나 캘린더에서 업무 지시: 답장에 따라 상태가 바뀜
• 밀기: 행에 수행된 작업과 실행 취소가 표시됨
• 보낸 메일에 ✓ 및 ✓✓, 내가 언급된 곳에 “@”
• 메일과 대화 안에서 찾기, 빠른 답장의 “+”
• 하단 바 맞춤 설정: 예를 들어 연락처 대신 나의 하루
</ko-KR>
<nl-NL>
• Mijn dag: bord en tijdlijn van de dag, taken verplaatsen met lang drukken
• Opdrachten vanuit een e-mail of de agenda: status volgt de antwoorden
• Vegen: de rij toont wat er is gedaan, met Ongedaan maken
• ✓ en ✓✓ bij je verzonden e-mails, ‘@’ waar je wordt genoemd
• Zoeken in een e-mail en een gesprek, ‘+’ in snel antwoord
• Onderbalk naar wens: bijvoorbeeld Mijn dag in plaats van Contacten
</nl-NL>
<no-NO>
• Min dag: tavle og tidslinje for dagen, flytt oppgaver med langt trykk
• Oppdrag fra en e-post eller kalenderen: status følger svarene
• Sveip: raden viser hva som ble gjort, med Angre
• ✓ og ✓✓ på sendte e-poster, «@» der du er nevnt
• Søk i en e-post og i en samtale, «+» i hurtigsvar
• Nederste linje etter ønske: for eksempel Min dag i stedet for Kontakter
</no-NO>
<pl-PL>
• Mój dzień: tablica i oś dnia, przenoszenie zadań długim naciśnięciem
• Zlecenia z wiadomości lub kalendarza: status zmienia się według odpowiedzi
• Przesunięcia: wiersz pokazuje, co zrobiono, z przyciskiem Cofnij
• ✓ i ✓✓ przy wysłanych wiadomościach, „@” tam, gdzie Cię wspomniano
• Szukanie w wiadomości i w rozmowie, „+” w szybkiej odpowiedzi
• Dolny pasek według uznania: np. Mój dzień zamiast Kontaktów
</pl-PL>
<pt-BR>
• Meu dia: quadro e linha do tempo do dia, mova tarefas com toque longo
• Atribuições a partir de um e-mail ou do calendário: o status segue as respostas
• Deslizar: a linha mostra o que foi feito, com Desfazer
• ✓ e ✓✓ nos seus e-mails enviados, “@” onde você é mencionado
• Busca no e-mail e na conversa, “+” na resposta rápida
• Barra inferior do seu jeito: por exemplo, Meu dia no lugar de Contatos
</pt-BR>
<ro>
• Ziua mea: panou și axa zilei, mutați sarcinile cu apăsare lungă
• Sarcini atribuite din e-mail sau calendar: starea urmează răspunsurile
• Glisare: rândul arată ce s-a făcut, cu Anulează
• ✓ și ✓✓ la e-mailurile trimise, „@” unde sunteți menționat
• Căutare în e-mail și în conversație, „+” în răspunsul rapid
• Bara de jos după preferințe: de exemplu Ziua mea în loc de Contacte
</ro>
<sk>
• Môj deň: nástenka a časová os dňa, presun úloh dlhým stlačením
• Zadania z e-mailu alebo kalendára: stav sa mení podľa odpovedí
• Potiahnutie: riadok ukáže, čo sa stalo, aj s tlačidlom Späť
• ✓ a ✓✓ pri odoslaných e-mailoch, „@“ tam, kde vás spomenuli
• Hľadanie v e-maile a v konverzácii, „+“ v rýchlej odpovedi
• Spodná lišta podľa vás: napríklad Môj deň namiesto Kontaktov
</sk>
<th>
• วันของฉัน: บอร์ดและไทม์ไลน์ของวัน กดค้างเพื่อย้ายงาน
• มอบหมายงานจากอีเมลหรือปฏิทิน: สถานะเปลี่ยนตามคำตอบ
• ปัด: แถวแสดงสิ่งที่ทำ พร้อมปุ่มเลิกทำ
• ✓ และ ✓✓ ที่อีเมลที่ส่ง และ “@” ตรงที่มีการกล่าวถึงคุณ
• ค้นหาในอีเมลและในบทสนทนา “+” ในการตอบกลับด่วน
• ปรับแถบด้านล่างได้: เช่น วางวันของฉันแทนผู้ติดต่อ
</th>
<tr-TR>
• Günüm: pano ve gün zaman çizelgesi, görevleri uzun basarak taşıyın
• E-postadan veya takvimden görevlendirme: durum yanıtlara göre değişir
• Kaydırma: satırda ne yapıldığı ve Geri al görünür
• Gönderdiğiniz e-postalarda ✓ ve ✓✓, anıldığınız yerde “@”
• E-postada ve konuşmada arama, hızlı yanıtta “+”
• Alt çubuk istediğiniz gibi: örneğin Kişiler yerine Günüm
</tr-TR>
<fi-FI>
• Oma päivä: taulu ja päivän aikajana, siirrä tehtäviä pitkällä painalluksella
• Toimeksiannot viestistä tai kalenterista: tila seuraa vastauksia
• Pyyhkäisy: rivi näyttää, mitä tehtiin, ja Kumoa
• ✓ ja ✓✓ lähettämissäsi viesteissä, ”@” kun sinut mainitaan
• Haku viestissä ja keskustelussa, ”+” pikavastauksessa
• Muokattava alapalkki: esimerkiksi Oma päivä Yhteystietojen tilalle
</fi-FI>
<hi-IN>
• मेरा दिन: बोर्ड और दिन की टाइमलाइन, लंबा दबाकर काम खिसकाएँ
• ईमेल या कैलेंडर से काम सौंपें: स्थिति जवाबों के अनुसार बदलती है
• स्वाइप: पंक्ति पर दिखता है कि क्या हुआ, साथ में «पूर्ववत करें»
• भेजे गए ईमेल पर ✓ और ✓✓, जहाँ आपका ज़िक्र हो वहाँ “@”
• ईमेल और बातचीत में खोज, त्वरित जवाब में “+”
• नीचे की पट्टी अपनी पसंद से: जैसे संपर्क की जगह मेरा दिन
</hi-IN>
<cs-CZ>
• Můj den: nástěnka a časová osa dne, přesun úkolů dlouhým stiskem
• Úkoly zadané z e-mailu nebo kalendáře: stav se mění podle odpovědí
• Přejetí: řádek ukáže, co se stalo, i s tlačítkem Zpět
• ✓ a ✓✓ u odeslaných e-mailů, „@“ tam, kde vás zmínili
• Hledání v e-mailu a v konverzaci, „+“ v rychlé odpovědi
• Spodní lišta podle vás: například Můj den místo Kontaktů
</cs-CZ>
<sv-SE>
• Min dag: tavla och tidslinje för dagen, flytta uppgifter med långt tryck
• Uppdrag från mejl eller kalendern: status följer svaren
• Svep: raden visar vad som gjordes, med Ångra
• ✓ och ✓✓ på skickade mejl, ”@” där du nämns
• Sök i ett mejl och i en konversation, ”+” i snabbsvar
• Nedre fält efter önskan: till exempel Min dag i stället för Kontakter
</sv-SE>
<ja-JP>
• マイデイ：ボードと1日のタイムライン、長押しでタスクを移動
• メールやカレンダーから依頼：返信に応じて状態が変わります
• スワイプ：行に実行結果と「元に戻す」を表示
• 送信したメールに ✓ と ✓✓、自分が言及された所に「@」
• メール内と会話内の検索、クイック返信の「+」
• 下部バーをカスタマイズ：たとえば連絡先の代わりにマイデイ
</ja-JP>
```
