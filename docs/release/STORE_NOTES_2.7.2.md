# «Что нового» — 2.7.2 (173), относительно 2.7.1 (172)

Следующая версия — 2.7.4 (`STORE_NOTES_2.7.4.md`).

Просьба владельца 24.11.2026: «давай поднимем версию для выпуска». Шаги
владельца — `OWNER_STEPS_2.7.2.md`. В 2.7.2 — всё, что сделано после архива
2.7.1. Зависимости, схема базы, ключи и файлы Xcode не менялись; в
манифесте Android — только запросы приложений SMS и телефона (`<queries>`).

## Сделано в 2.7.2

- **Вложения при плохой связи** (журнал владельца 23.11.2026 05:29, nubia:
  «скачивание вложений идёт долго и не заканчивается, мешает
  синхронизации, при восстановлении интернета скачивание не начинается —
  пришлось закрывать приложение»). Причина: вложение IMAP качалось на общем
  соединении ящика, в его очереди и с потолком 20 минут; синхронизация
  ждала за ним (в журнале: проверка Gmail с 20:00 до 20:13, когда
  приложение закрыли). При смене сети соединение закрывалось, но почтовая
  библиотека не завершала ждущую команду — она висела до своих 20 минут.
  Теперь:
  - у вложений своё соединение и своя очередь — синхронизация их не ждёт;
    соединение закрывается, когда 2 минуты не нужно;
  - обрыв (смена сети, сервер закрыл соединение) команда узнаёт сразу и
    повторяется на новом соединении — уже в новой сети; так же и
    синхронизация;
  - минуту не пришло ни байта — соединение мертво: закрывается, повтор на
    новом;
  - скачивание, которое ждёт человек (нажал на вложение, переслал письмо
    с вложениями), при обрыве не падает ошибкой: ждёт, пока вернётся сеть
    (до 10 минут), и продолжается само — до трёх повторов. ActiveSync и
    EWS — так же.
- **Настройки: перегруппировка** (замечание владельца 23.11.2026:
  «антифишинг и блокировку можно объединить, размер фото — в "Загрузке и
  вложениях"»; «пользователь установил приложение, дал разрешения, добавил
  аккаунт — от него не должно что-то ещё требоваться»):
  - «Защита писем» — один экран: предупреждения о фишинге и блокировка
    трекеров (подробности — что заблокировано, доверенные отправители —
    по строке «Заблокировано трекеров»). Отдельной строки «Блокировка
    трекеров» в «Конфиденциальности» больше нет;
  - «Размер фото при отправке» — в «Загрузке и вложениях»;
  - то, что настраивает администратор или что решается само, — в
    «Расширенных настройках»: «Безопасность соединения» (сертификаты
    серверов), «Защита данных» (DLP), «Конфликты синхронизации». В
    «Конфиденциальности» остались код при входе, «Защита писем» и
    «Разрешения»;
  - поиск по настройкам ведёт на новые места (и «Проверка почты в фоне» —
    на её экран в «Расширенных»).

- **Виджет «Календарь», вид «Мой день»**: «1 непрочит. · 3 в работе» — строкой
  под переключателем вида; под датой — только погода (просьба пользователей:
  «место под погоду занято»).

- **Фото адресатов — того же размера, что фото отправителя** (замечание
  владельца 23.11.2026): в редакторе письма (строка «Кому» и плашки
  адресатов) и в полученном письме (адресаты внахлёст, строками и полным
  списком) — радиус 16, как у отправителя.

- **Микрофризы** (записи экрана и журналы владельца 24.11.2026: открытие
  письма и редактора, ответ, смена ящика):
  - смена ящика и любой настройки больше не запускает 350 мс «перетекания»
    темы в такую же тему (в каждом из 44 кадров перестраивался весь
    интерфейс) — расширения темы сравниваются по значению, темы — из кэша;
  - «Новое сообщение» не замирает (на записи — ~1,5 с без ответа на
    нажатия): словарь полных имён читал все контакты вместе с фото из
    Google и iCloud (они хранятся в базе текстом) и разбирал адресатов в
    главном потоке. Теперь — только адрес и имя, адресатов разбирает база,
    большой объём — в фоновом потоке; пересчёт — когда меняются контакты, а
    не после каждой синхронизации;
  - число непрочитанных ящика больше не пересобирает список ящиков (за ним
    следят десятки экранов) — после каждой синхронизации с новым письмом;
  - смена ящика или папки — без вспышки серых заготовок строк («немного
    моргает»): до 0,35 с остаётся прежний список;
  - журнал: медленные кадры от 100 мс — подробно и с открытым экраном;
    сторож главного потока (приложения и Android) пишет замирания, когда
    кадров нет вовсе.
- **Флажок «Сегодня», как в Outlook** (просьба владельца 24.11.2026):
  нажатие на флажок ставит срок «Сегодня»; удержание флажка в письме (и
  «Срок флажка» в меню) — сегодня, завтра, на этой неделе, на следующей
  неделе, без даты, снять флажок. В Exchange срок уходит датами флажка —
  Outlook показывает «Сегодня»; флажки со сроком, поставленные в Outlook,
  приходят с ним. В ленте — «срок сегодня» (просроченный, со следующего
  дня, — красным), в «Задачах» — «С флагом · Сегодня», в календаре и
  виджете — как письма с флажком.
- **Удержание номера телефона** (просьба пользователя): в карточке
  контакта и человека — позвонить, «Написать SMS» (приложение SMS по
  умолчанию), мессенджеры, с которыми номер связан в контактах телефона
  (WhatsApp, Telegram, Viber… — те же пункты, что в «Контактах» Android),
  скопировать номер.
- **«Мой день»: часы и погода до пяти городов** (просьба владельца
  24.11.2026): карточка «Сейчас» листается — первая страница — ваши часы и
  свой город, следующие — часы города в его поясе (разница с телефоном) и
  погода. В окне погоды — «Добавить город» (до пяти), «Сделать первым»,
  «Убрать» и «в виджетах»: виджеты «Мой день» и «Календарь» показывают
  погоду отмеченных городов (не больше двух) с названием города: «☁ −3°
  Екатеринбург · ☀ +5° Москва». Прежние два города (тестовые сборки)
  переносятся сами. Часовой пояс города присылает сервер поиска городов
  (GeoNames) — после его обновления (шаги владельца).
- **Черновик, исправленный на сервере, обновляется на телефоне**
  (замечание владельца 24.11.2026: «сохранил черновик с телефона, он
  появился на сервере; отредактировал его на сервере — на телефоне не
  обновился»). ActiveSync сообщает о правке письма только изменёнными
  свойствами, и приложение брало из них лишь «прочитано» и флажок. Теперь
  письмо, у которого на сервере изменили тему, адресатов, текст или файлы,
  перечитывается целиком при следующей синхронизации. Exchange (EWS):
  текст изменённого черновика загружается заново при открытии — раньше
  редактор открывал прежний текст и, сохранив, затирал им правку с
  сервера. IMAP так и работал (сервер сохраняет правку новым письмом).
- **Безопасность, этап 1 — приложение** (внешний обзор 23.11.2026,
  `docs/plan/SECURITY_AUDIT_2026-11-23.md`):
  - база почты — только зашифрованная: сборка, которая не может
    зашифровать базу, показывает понятный экран («установите заново»), а не
    хранит почту открытым текстом; старая открытая база переводится в
    зашифрованную без потери данных;
  - очистка HTML писем проверена 128 известными приёмами (обработчики,
    схемы javascript: с сущностями, SVG, мутационные XSS, CSS) — обходов
    нет;
  - вложения: опасное расширение больше не прячут символы направления
    текста и невидимые символы; список опасных расширений — по блокировке
    Outlook; имя при сохранении — без символов направления и имён,
    зарезервированных Windows;
  - Android: окно настройки виджета меняет только виджеты приложения;
    «Поделиться» не принимает файлы из хранилища до разблокировки.
- **Картинки в цитате ответа и пересылки** (замечание владельца
  24.11.2026: первый ответ ушёл с пустым местом вместо скриншота из
  исходного письма). Ответ и пересылка, которые собирает приложение (в том
  числе с окном «Отменить» и отложенные), ссылались на картинку исходного
  письма, но саму картинку не прикладывали. Теперь картинки цитаты берутся
  из памяти телефона (или с сервера) и уходят в письме встроенными частями
  с Content-ID — как у Outlook. Так же уходят и скриншоты, вставленные в
  текст: Outlook для Windows и Gmail картинки «внутри текста» (data:) не
  показывали. ActiveSync, Exchange (EWS) и IMAP.
- **Безопасность, этап 2 — серверы** (после обновления серверов, шаги
  владельца): вход только с PKCE, лимиты частоты на вход и обмен кода,
  проверка подписи id_token, хранение токенов на сервере убрано; «будильник»
  без ключа приложения не запускается.

## Кратко (RU / EN)

**RU.** До пяти городов в «Моём дне» — время и погода каждого; флажок
«Сегодня», как в Outlook; SMS и мессенджеры по номеру телефона; картинки
исходного письма не теряются в ответе; письма и редактор открываются
быстрее, вложения докачиваются после обрыва связи; защита данных.

**EN.** Up to five cities in My day with their local time and weather; a
“Today” flag like in Outlook; SMS and messengers from a phone number;
images from the original message are kept in replies; mail and the editor
open faster, attachments resume after a dropped connection; data
protection.

## Google Play — короткий текст (27 языков)

Самый длинный — 465 знаков (fr-FR; предел — 500).

```
<ru-RU>
• До пяти городов в «Моём дне»: время в их поясе и погода, два — в виджетах
• Флажок «Сегодня», как в Outlook: срок виден и в Exchange
• Номер телефона: SMS и мессенджеры, связанные с ним в контактах
• Картинки исходного письма не теряются в ответе и пересылке
• Письма и редактор открываются быстрее, вложения докачиваются после обрыва связи
• Защита данных и исправления
</ru-RU>
<en-US>
• Up to five cities in My day: local time and weather, two in widgets
• “Today” flag like in Outlook — the due date syncs with Exchange
• Phone numbers: SMS and the messengers linked to them in contacts
• Images from the original message are kept in replies and forwards
• Mail and the editor open faster; attachments resume after a dropped connection
• Data protection and bug fixes
</en-US>
<de-DE>
• Bis zu fünf Städte in „Mein Tag“: Ortszeit und Wetter, zwei im Widget
• Flagge „Heute“ wie in Outlook – das Fälligkeitsdatum wird mit Exchange synchronisiert
• Telefonnummern: SMS und die in den Kontakten verknüpften Messenger
• Bilder der Originalnachricht bleiben in Antworten und Weiterleitungen erhalten
• E-Mails und Editor öffnen schneller; Anhänge laden nach einem Verbindungsabbruch weiter
• Datenschutz und Fehlerbehebungen
</de-DE>
<fr-FR>
• Jusqu’à cinq villes dans « Ma journée » : heure locale et météo, deux dans les widgets
• Indicateur « Aujourd’hui » comme dans Outlook — l’échéance est synchronisée avec Exchange
• Numéros de téléphone : SMS et messageries associées dans les contacts
• Les images du message d’origine sont conservées dans les réponses et transferts
• E-mails et éditeur s’ouvrent plus vite ; les pièces jointes reprennent après une coupure
• Protection des données et corrections
</fr-FR>
<ar>
• حتى خمس مدن في «يومي»: الوقت المحلي والطقس، ومدينتان في الأدوات
• علامة «اليوم» كما في Outlook — يتزامن تاريخ الاستحقاق مع Exchange
• أرقام الهاتف: رسائل SMS وتطبيقات المراسلة المرتبطة بها في جهات الاتصال
• تبقى صور الرسالة الأصلية في الردود وإعادة التوجيه
• فتح أسرع للرسائل والمحرر، ويُستأنف تنزيل المرفقات بعد انقطاع الاتصال
• حماية البيانات وإصلاح الأخطاء
</ar>
<hu-HU>
• Akár öt város a „Saját napom” nézetben: helyi idő és időjárás, kettő a widgetekben
• „Ma” jelölő, mint az Outlookban – a határidő szinkronizálódik az Exchange-dzsel
• Telefonszámok: SMS és a névjegyekben hozzájuk kapcsolt üzenetküldők
• Az eredeti levél képei megmaradnak a válaszokban és továbbításokban
• Gyorsabban nyílnak a levelek és a szerkesztő; a mellékletek a kapcsolat megszakadása után folytatódnak
• Adatvédelem és hibajavítások
</hu-HU>
<vi>
• Tối đa năm thành phố trong «Ngày của tôi»: giờ địa phương và thời tiết, hai thành phố trong widget
• Cờ «Hôm nay» như trong Outlook — hạn được đồng bộ với Exchange
• Số điện thoại: SMS và ứng dụng nhắn tin liên kết trong danh bạ
• Hình ảnh của thư gốc được giữ lại khi trả lời và chuyển tiếp
• Mở thư và trình soạn thảo nhanh hơn; tệp đính kèm tiếp tục tải sau khi mất kết nối
• Bảo vệ dữ liệu và sửa lỗi
</vi>
<da-DK>
• Op til fem byer i “Min dag”: lokal tid og vejr, to i widgets
• Flaget “I dag” som i Outlook – forfaldsdatoen synkroniseres med Exchange
• Telefonnumre: sms og de beskedapps, der er knyttet til dem i kontakter
• Billeder fra den oprindelige mail bevares i svar og videresendelser
• Mails og editoren åbner hurtigere; vedhæftede filer fortsætter efter en afbrudt forbindelse
• Databeskyttelse og fejlrettelser
</da-DK>
<iw-IL>
• עד חמש ערים ב„היום שלי”: שעה מקומית ומזג אוויר, שתיים בווידג׳טים
• דגל „היום” כמו ב-Outlook — תאריך היעד מסונכרן עם Exchange
• מספרי טלפון: SMS ואפליקציות המסרים המקושרות אליהם באנשי הקשר
• תמונות מההודעה המקורית נשמרות בתשובות ובהעברות
• פתיחה מהירה יותר של הודעות ושל העורך; הורדת קבצים מצורפים ממשיכה אחרי ניתוק
• הגנת נתונים ותיקוני באגים
</iw-IL>
<id>
• Hingga lima kota di “Hari saya”: waktu setempat dan cuaca, dua di widget
• Bendera “Hari ini” seperti di Outlook — tenggat disinkronkan dengan Exchange
• Nomor telepon: SMS dan aplikasi pesan yang terhubung di kontak
• Gambar dari email asli tetap ada saat membalas dan meneruskan
• Email dan editor terbuka lebih cepat; lampiran dilanjutkan setelah koneksi terputus
• Perlindungan data dan perbaikan bug
</id>
<es-ES>
• Hasta cinco ciudades en «Mi día»: hora local y tiempo, dos en los widgets
• Marca «Hoy» como en Outlook: el vencimiento se sincroniza con Exchange
• Números de teléfono: SMS y las apps de mensajería vinculadas en los contactos
• Las imágenes del mensaje original se conservan al responder y reenviar
• Correos y editor se abren más rápido; los adjuntos se reanudan tras un corte de conexión
• Protección de datos y correcciones
</es-ES>
<it-IT>
• Fino a cinque città in «Il mio giorno»: ora locale e meteo, due nei widget
• Contrassegno «Oggi» come in Outlook: la scadenza si sincronizza con Exchange
• Numeri di telefono: SMS e app di messaggistica collegate nei contatti
• Le immagini del messaggio originale restano nelle risposte e negli inoltri
• Email ed editor si aprono più velocemente; gli allegati riprendono dopo un’interruzione
• Protezione dei dati e correzioni
</it-IT>
<zh-CN>
• “我的一天”最多五个城市：当地时间和天气，两个显示在小组件中
• 与 Outlook 相同的“今天”标记——截止日期与 Exchange 同步
• 电话号码：短信及通讯录中关联的即时通讯应用
• 回复和转发时保留原邮件中的图片
• 邮件和编辑器打开更快；连接中断后附件继续下载
• 数据保护和问题修复
</zh-CN>
<ko-KR>
• ‘오늘 일정’에 최대 5개 도시: 현지 시간과 날씨, 위젯에는 2개
• Outlook과 같은 ‘오늘’ 플래그 — 기한이 Exchange와 동기화
• 전화번호: 문자 메시지와 연락처에 연결된 메신저
• 답장과 전달 시 원본 메일의 이미지 유지
• 메일과 편집기가 더 빨리 열림, 연결이 끊긴 후 첨부 파일 다운로드 재개
• 데이터 보호 및 버그 수정
</ko-KR>
<nl-NL>
• Tot vijf steden in ‘Mijn dag’: lokale tijd en weer, twee in widgets
• Vlag ‘Vandaag’ zoals in Outlook – de vervaldatum wordt gesynchroniseerd met Exchange
• Telefoonnummers: sms en de berichtenapps die in contacten zijn gekoppeld
• Afbeeldingen uit het oorspronkelijke bericht blijven behouden bij beantwoorden en doorsturen
• Mails en editor openen sneller; bijlagen gaan verder na een verbroken verbinding
• Gegevensbescherming en oplossingen
</nl-NL>
<no-NO>
• Opptil fem byer i «Min dag»: lokal tid og vær, to i moduler
• Flagget «I dag» som i Outlook – forfallsdatoen synkroniseres med Exchange
• Telefonnumre: SMS og meldingsappene som er knyttet til dem i kontakter
• Bilder fra den opprinnelige e-posten beholdes i svar og videresendinger
• E-post og redigeringsverktøyet åpnes raskere; vedlegg fortsetter etter brudd i tilkoblingen
• Personvern og feilrettinger
</no-NO>
<pl-PL>
• Do pięciu miast w „Moim dniu”: czas lokalny i pogoda, dwa w widżetach
• Flaga „Dzisiaj” jak w Outlooku – termin synchronizuje się z Exchange
• Numery telefonów: SMS i komunikatory powiązane z nimi w kontaktach
• Obrazy z oryginalnej wiadomości zostają w odpowiedziach i przekazaniach
• Szybsze otwieranie wiadomości i edytora; załączniki pobierają się dalej po zerwaniu połączenia
• Ochrona danych i poprawki
</pl-PL>
<pt-BR>
• Até cinco cidades em “Meu dia”: hora local e clima, duas nos widgets
• Sinalizador “Hoje” como no Outlook — o prazo é sincronizado com o Exchange
• Números de telefone: SMS e apps de mensagens vinculados nos contatos
• Imagens da mensagem original são mantidas ao responder e encaminhar
• E-mails e editor abrem mais rápido; anexos continuam após a queda da conexão
• Proteção de dados e correções
</pt-BR>
<ro>
• Până la cinci orașe în „Ziua mea”: ora locală și vremea, două în widgeturi
• Marcajul „Astăzi” ca în Outlook – termenul se sincronizează cu Exchange
• Numere de telefon: SMS și aplicațiile de mesagerie asociate în contacte
• Imaginile din mesajul original se păstrează în răspunsuri și redirecționări
• E-mailurile și editorul se deschid mai repede; atașamentele continuă după o întrerupere
• Protecția datelor și remedieri
</ro>
<sk>
• Až päť miest v „Mojom dni“: miestny čas a počasie, dve vo widgetoch
• Príznak „Dnes“ ako v Outlooku – termín sa synchronizuje s Exchange
• Telefónne čísla: SMS a messengery, ktoré sú s nimi prepojené v kontaktoch
• Obrázky z pôvodnej správy zostávajú v odpovediach a preposlaniach
• Rýchlejšie otváranie správ a editora; prílohy pokračujú po výpadku spojenia
• Ochrana údajov a opravy
</sk>
<th>
• สูงสุดห้าเมืองใน “วันของฉัน”: เวลาท้องถิ่นและสภาพอากาศ สองเมืองในวิดเจ็ต
• ธง “วันนี้” แบบ Outlook — วันครบกำหนดซิงค์กับ Exchange
• หมายเลขโทรศัพท์: SMS และแอปแชทที่เชื่อมกับรายชื่อติดต่อ
• รูปภาพจากอีเมลต้นฉบับยังอยู่เมื่อตอบกลับและส่งต่อ
• เปิดอีเมลและตัวแก้ไขเร็วขึ้น ไฟล์แนบดาวน์โหลดต่อได้หลังการเชื่อมต่อขาด
• การปกป้องข้อมูลและแก้ไขข้อบกพร่อง
</th>
<tr-TR>
• “Günüm”de beş şehre kadar: yerel saat ve hava durumu, ikisi widget’larda
• Outlook’taki gibi “Bugün” bayrağı — son tarih Exchange ile eşitlenir
• Telefon numaraları: SMS ve kişilerde bağlı mesajlaşma uygulamaları
• Yanıtlarda ve iletmelerde orijinal iletinin görselleri korunur
• E-postalar ve düzenleyici daha hızlı açılır; ekler bağlantı kesildikten sonra devam eder
• Veri koruma ve hata düzeltmeleri
</tr-TR>
<fi-FI>
• Jopa viisi kaupunkia Oma päivä -näkymässä: paikallinen aika ja sää, kaksi pienoisohjelmissa
• ”Tänään”-merkintä kuten Outlookissa – määräpäivä synkronoidaan Exchangen kanssa
• Puhelinnumerot: tekstiviesti ja yhteystiedoissa niihin liitetyt viestisovellukset
• Alkuperäisen viestin kuvat säilyvät vastauksissa ja edelleenlähetyksissä
• Viestit ja editori avautuvat nopeammin; liitteiden lataus jatkuu yhteyskatkon jälkeen
• Tietosuoja ja korjaukset
</fi-FI>
<hi-IN>
• “मेरा दिन” में पाँच शहर तक: स्थानीय समय और मौसम, दो विजेट में
• Outlook जैसा “आज” फ़्लैग — नियत तिथि Exchange के साथ सिंक होती है
• फ़ोन नंबर: SMS और संपर्कों में जुड़े मैसेंजर
• उत्तर और फ़ॉरवर्ड में मूल ईमेल की छवियाँ बनी रहती हैं
• ईमेल और एडिटर तेज़ी से खुलते हैं; कनेक्शन टूटने के बाद अटैचमेंट डाउनलोड जारी रहता है
• डेटा सुरक्षा और सुधार
</hi-IN>
<cs-CZ>
• Až pět měst v „Mém dni“: místní čas a počasí, dvě ve widgetech
• Příznak „Dnes“ jako v Outlooku – termín se synchronizuje s Exchange
• Telefonní čísla: SMS a messengery, které jsou s nimi propojené v kontaktech
• Obrázky z původní zprávy zůstávají v odpovědích a přeposlání
• Rychlejší otevírání zpráv a editoru; přílohy pokračují po výpadku spojení
• Ochrana dat a opravy
</cs-CZ>
<sv-SE>
• Upp till fem städer i ”Min dag”: lokal tid och väder, två i widgetar
• Flaggan ”I dag” som i Outlook – förfallodatumet synkas med Exchange
• Telefonnummer: sms och de meddelandeappar som är kopplade i kontakter
• Bilder från det ursprungliga mejlet finns kvar i svar och vidarebefordringar
• Mejl och redigeraren öppnas snabbare; bilagor fortsätter efter avbrott i anslutningen
• Dataskydd och felrättningar
</sv-SE>
<ja-JP>
• 「今日の予定」に最大5都市：現地時刻と天気、ウィジェットには2都市
• Outlook と同じ「今日」フラグ — 期限は Exchange と同期
• 電話番号：SMS と連絡先で関連付けられたメッセンジャー
• 返信・転送で元のメールの画像を保持
• メールとエディターの表示が高速に。接続が切れても添付ファイルのダウンロードを再開
• データ保護と不具合修正
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• До пяти городов в «Моём дне»: время в их поясе и погода, два — в виджетах
• Флажок «Сегодня», как в Outlook: срок виден и в Exchange
• Номер телефона: SMS и мессенджеры, связанные с ним в контактах
• Картинки исходного письма не теряются в ответе и пересылке
• Письма и редактор открываются быстрее, вложения докачиваются после обрыва связи
• Защита данных и исправления
</ru-RU>
<en-US>
• Up to five cities in My day: local time and weather, two in widgets
• “Today” flag like in Outlook — the due date syncs with Exchange
• Phone numbers: SMS and the messengers linked to them in contacts
• Images from the original message are kept in replies and forwards
• Mail and the editor open faster; attachments resume after a dropped connection
• Data protection and bug fixes
</en-US>
<de-DE>
• Bis zu fünf Städte in „Mein Tag“: Ortszeit und Wetter, zwei im Widget
• Flagge „Heute“ wie in Outlook – das Fälligkeitsdatum wird mit Exchange synchronisiert
• Telefonnummern: SMS und die in den Kontakten verknüpften Messenger
• Bilder der Originalnachricht bleiben in Antworten und Weiterleitungen erhalten
• E-Mails und Editor öffnen schneller; Anhänge laden nach einem Verbindungsabbruch weiter
• Datenschutz und Fehlerbehebungen
</de-DE>
<fr-FR>
• Jusqu’à cinq villes dans « Ma journée » : heure locale et météo, deux dans les widgets
• Indicateur « Aujourd’hui » comme dans Outlook — l’échéance est synchronisée avec Exchange
• Numéros de téléphone : SMS et messageries associées dans les contacts
• Les images du message d’origine sont conservées dans les réponses et transferts
• E-mails et éditeur s’ouvrent plus vite ; les pièces jointes reprennent après une coupure
• Protection des données et corrections
</fr-FR>
```
