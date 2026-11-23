# «Что нового» — 2.7.1 (172), относительно 2.7.0 (171)

Просьба владельца 22.11.2026: «давай поднимем версию». Шаги владельца —
`OWNER_STEPS_2.7.1.md`. 2.7.0 ушла архивом с коммита 4006dc4 — в 2.7.1 всё,
что сделано после.

## Сделано в 2.7.1

- **Удаление одного повтора события Google** (журнал пользователя
  22.11.2026 18:48: «Удаление события …#20261220: Сервер не принял изменение
  (HTTP 400)»; просьба владельца «давай поправим»). У дня рождения из
  контактов Google даты не меняются, и сервер отклонял исключение одного
  года (EXDATE) — пользователь видел ошибку, повтор оставался. Теперь:
  - сервер не принял исключение даты — повтор убирается вторым способом,
    отменённым вхождением (RECURRENCE-ID, STATUS:CANCELLED, RFC 5545);
  - не принял и его (день рождения из контактов Google) — повтор скрывается
    в Ogneliss без ошибки и не возвращается при следующих синхронизациях;
    остальные годы и само событие в Google — на месте. Убрать день
    рождения совсем — в карточке контакта;
  - календарь только для чтения (праздники, чужой общий календарь) — то же:
    отказ сервера не ошибка, событие скрывается в приложении. Отказ в своём
    календаре (нет прав у входа) — по-прежнему ошибка: её исправляет
    пользователь.
- **Сигналы о новой почте через RuStore и другие магазины без Google** — не
  делаются (решение владельца 22.11.2026: сборку могут отклонить в
  магазине, публикация в RuStore ещё не согласована; после согласования,
  возможно, — отдельная сборка).

## Сделано после архива 2.7.1 (версия та же)

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

## Тексты магазинов

В текстах магазинов 2.7.0 не было пунктов, добавленных в 2.7.0 после них:
проверка почты в фоне, контакты и календарь в телефоне — сами; письма людей
и коллег — как в мессенджере, рассылки — простыми уведомлениями; встречи
Google — сразу после «обновить». Они — здесь, вместе с повтором события
Google.

## Кратко (RU / EN)

**RU.** Проверка почты в фоне, контакты и календарь в телефоне
настраиваются сами; письма людей и коллег приходят как сообщения в
мессенджере, рассылки — простыми уведомлениями; встречи Google появляются
сразу после «обновить»; один повтор события Google удаляется без ошибки.

**EN.** Background mail checks and the phone’s contacts and calendar set
themselves up; mail from people and colleagues arrives like messenger
messages, newsletters as plain notifications; Google meetings appear right
after a refresh; deleting a single occurrence of a Google event no longer
fails.

## Google Play — короткий текст (27 языков)

Самый длинный — 380 знаков (fr-FR; предел — 500).

```
<ru-RU>
• Проверка почты в фоне, контакты и календарь в телефоне настраиваются сами
• Письма людей и коллег — как сообщения в мессенджере, рассылки — простыми уведомлениями
• Встречи Google появляются сразу после обновления календаря
• Исправлено удаление одного повтора события Google
• Исправления и улучшения
</ru-RU>
<en-US>
• Background mail checks and the phone’s contacts and calendar set themselves up
• Mail from people and colleagues looks like messenger messages; newsletters arrive as plain notifications
• Google meetings appear right after refreshing the calendar
• Fixed deleting a single occurrence of a Google event
• Bug fixes and improvements
</en-US>
<de-DE>
• Hintergrundabruf sowie Kontakte und Kalender im Telefon richten sich selbst ein
• E-Mails von Personen und Kollegen erscheinen wie Messenger-Nachrichten, Newsletter als einfache Benachrichtigung
• Google-Termine erscheinen sofort nach dem Aktualisieren des Kalenders
• Löschen eines einzelnen Termins einer Google-Serie behoben
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• La relève en arrière-plan, les contacts et l’agenda du téléphone se configurent tout seuls
• Les e-mails de personnes et de collègues s’affichent comme des messages, les newsletters en notification simple
• Les réunions Google apparaissent dès l’actualisation de l’agenda
• Correction de la suppression d’une seule occurrence d’un événement Google
• Corrections et améliorations
</fr-FR>
<ar>
• فحص البريد في الخلفية وجهات الاتصال والتقويم في الهاتف تُضبط تلقائيًا
• رسائل الأشخاص والزملاء تظهر كرسائل المحادثة، والنشرات البريدية كإشعارات عادية
• اجتماعات Google تظهر فور تحديث التقويم
• إصلاح حذف تكرار واحد من حدث Google
• إصلاحات وتحسينات
</ar>
<hu-HU>
• A háttérben történő levélellenőrzés, valamint a telefon névjegyei és naptára magától beáll
• Az emberektől és kollégáktól érkező levelek üzenetként jelennek meg, a hírlevelek egyszerű értesítésként
• A Google-értekezletek a naptár frissítése után azonnal megjelennek
• Javítva: egy Google-esemény egyetlen ismétlődésének törlése
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Kiểm tra thư nền, danh bạ và lịch trên điện thoại tự thiết lập
• Thư từ mọi người và đồng nghiệp hiện như tin nhắn, bản tin là thông báo thường
• Cuộc họp Google xuất hiện ngay sau khi làm mới lịch
• Sửa lỗi xóa một lần lặp của sự kiện Google
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Baggrundstjek af mail samt telefonens kontakter og kalender sætter sig selv op
• Mail fra personer og kolleger vises som beskeder, nyhedsbreve som almindelige notifikationer
• Google-møder vises straks efter opdatering af kalenderen
• Rettet sletning af en enkelt gentagelse af en Google-begivenhed
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• בדיקת דואר ברקע, אנשי הקשר ולוח השנה בטלפון מוגדרים לבד
• דואר מאנשים ומעמיתים מוצג כמו הודעות, ניוזלטרים כהתראה רגילה
• פגישות Google מופיעות מיד לאחר רענון לוח השנה
• תוקנה מחיקה של מופע יחיד של אירוע Google
• תיקוני באגים ושיפורים
</iw-IL>
<id>
• Pemeriksaan email di latar belakang serta kontak dan kalender ponsel diatur otomatis
• Email dari orang dan rekan kerja tampil seperti pesan, buletin sebagai notifikasi biasa
• Rapat Google muncul segera setelah kalender diperbarui
• Perbaikan menghapus satu pengulangan acara Google
• Perbaikan bug dan peningkatan
</id>
<es-ES>
• La comprobación del correo en segundo plano y los contactos y el calendario del teléfono se configuran solos
• El correo de personas y compañeros aparece como mensajes; los boletines, como notificaciones simples
• Las reuniones de Google aparecen nada más actualizar el calendario
• Corregida la eliminación de una sola repetición de un evento de Google
• Correcciones y mejoras
</es-ES>
<it-IT>
• Controllo della posta in background, contatti e calendario del telefono si configurano da soli
• Le email di persone e colleghi appaiono come messaggi, le newsletter come notifiche semplici
• Le riunioni Google compaiono subito dopo l’aggiornamento del calendario
• Corretta l’eliminazione di una singola ricorrenza di un evento Google
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 后台收信以及手机中的联系人和日历自动设置
• 来自个人和同事的邮件以消息形式显示，新闻邮件以普通通知显示
• 刷新日历后 Google 会议立即显示
• 修复删除 Google 活动单次重复的问题
• 问题修复与改进
</zh-CN>
<ko-KR>
• 백그라운드 메일 확인, 휴대전화 연락처와 캘린더가 자동으로 설정됩니다
• 사람과 동료가 보낸 메일은 메시지처럼, 뉴스레터는 일반 알림으로 표시됩니다
• 캘린더를 새로 고치면 Google 회의가 바로 표시됩니다
• Google 일정의 반복 한 번 삭제 문제 수정
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Controle op de achtergrond en contacten en agenda op de telefoon stellen zichzelf in
• Mail van mensen en collega’s verschijnt als berichten, nieuwsbrieven als gewone melding
• Google-vergaderingen verschijnen direct na het vernieuwen van de agenda
• Verwijderen van één herhaling van een Google-afspraak opgelost
• Bugfixes en verbeteringen
</nl-NL>
<no-NO>
• Bakgrunnssjekk av e-post samt telefonens kontakter og kalender setter seg opp selv
• E-post fra personer og kolleger vises som meldinger, nyhetsbrev som vanlige varsler
• Google-møter vises straks etter oppdatering av kalenderen
• Rettet sletting av én gjentakelse av en Google-hendelse
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Sprawdzanie poczty w tle oraz kontakty i kalendarz w telefonie konfigurują się same
• Poczta od ludzi i współpracowników wygląda jak wiadomości, newslettery — jak zwykłe powiadomienia
• Spotkania Google pojawiają się zaraz po odświeżeniu kalendarza
• Naprawiono usuwanie jednego powtórzenia wydarzenia Google
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• A verificação de e-mail em segundo plano e os contatos e a agenda do telefone se configuram sozinhos
• E-mails de pessoas e colegas aparecem como mensagens; newsletters, como notificações simples
• Reuniões do Google aparecem logo após atualizar a agenda
• Corrigida a exclusão de uma única repetição de um evento do Google
• Correções e melhorias
</pt-BR>
<ro>
• Verificarea e-mailului în fundal, contactele și calendarul din telefon se configurează singure
• E-mailurile de la oameni și colegi apar ca mesaje, buletinele ca notificări simple
• Întâlnirile Google apar imediat după reîmprospătarea calendarului
• Remediată ștergerea unei singure repetări a unui eveniment Google
• Remedieri și îmbunătățiri
</ro>
<sk>
• Kontrola pošty na pozadí aj kontakty a kalendár v telefóne sa nastavia samy
• Pošta od ľudí a kolegov vyzerá ako správy, bulletiny ako obyčajné upozornenia
• Stretnutia Google sa zobrazia hneď po obnovení kalendára
• Opravené odstránenie jedného opakovania udalosti Google
• Opravy a vylepšenia
</sk>
<th>
• การตรวจอีเมลเบื้องหลัง รายชื่อติดต่อ และปฏิทินในโทรศัพท์ตั้งค่าเอง
• อีเมลจากบุคคลและเพื่อนร่วมงานแสดงเหมือนข้อความแชต จดหมายข่าวเป็นการแจ้งเตือนธรรมดา
• การประชุม Google แสดงทันทีหลังรีเฟรชปฏิทิน
• แก้ไขการลบการเกิดซ้ำครั้งเดียวของกิจกรรม Google
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Arka planda posta denetimi ile telefondaki kişiler ve takvim kendiliğinden ayarlanır
• Kişilerden ve iş arkadaşlarından gelen postalar mesaj gibi, bültenler basit bildirim olarak görünür
• Google toplantıları takvim yenilenir yenilenmez görünür
• Bir Google etkinliğinin tek bir tekrarını silme düzeltildi
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Taustalla tapahtuva postin tarkistus sekä puhelimen yhteystiedot ja kalenteri määrittyvät itsestään
• Ihmisten ja kollegoiden viestit näkyvät kuin pikaviestit, uutiskirjeet tavallisina ilmoituksina
• Google-kokoukset näkyvät heti kalenterin päivityksen jälkeen
• Korjattu Google-tapahtuman yksittäisen toistokerran poisto
• Virheenkorjauksia ja parannuksia
</fi-FI>
<hi-IN>
• बैकग्राउंड में मेल जाँच तथा फ़ोन के संपर्क और कैलेंडर अपने-आप सेट होते हैं
• लोगों और सहकर्मियों की मेल संदेशों की तरह, न्यूज़लेटर सामान्य सूचना के रूप में
• कैलेंडर रीफ़्रेश करते ही Google मीटिंग दिखती हैं
• Google इवेंट की एक पुनरावृत्ति हटाने की समस्या ठीक की गई
• बग फ़िक्स और सुधार
</hi-IN>
<cs-CZ>
• Kontrola pošty na pozadí i kontakty a kalendář v telefonu se nastaví samy
• Pošta od lidí a kolegů vypadá jako zprávy, zpravodaje jako obyčejná oznámení
• Schůzky Google se zobrazí hned po obnovení kalendáře
• Opraveno smazání jednoho opakování události Google
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Bakgrundskontroll av mejl samt telefonens kontakter och kalender ställs in automatiskt
• Mejl från personer och kollegor visas som meddelanden, nyhetsbrev som vanliga aviseringar
• Google-möten visas direkt efter att kalendern uppdaterats
• Åtgärdat borttagning av en enskild upprepning av en Google-händelse
• Buggfixar och förbättringar
</sv-SE>
<ja-JP>
• バックグラウンドのメール確認、端末の連絡先とカレンダーが自動で設定されます
• 人や同僚からのメールはメッセージのように、ニュースレターは通常の通知で表示
• カレンダーを更新するとすぐに Google の会議が表示されます
• Google の予定の 1 回分だけを削除できない問題を修正
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Проверка почты в фоне, контакты и календарь в телефоне настраиваются сами
• Письма людей и коллег — как сообщения в мессенджере, рассылки — простыми уведомлениями
• Встречи Google появляются сразу после обновления календаря
• Исправлено удаление одного повтора события Google
• Исправления и улучшения
</ru-RU>
<en-US>
• Background mail checks and the phone’s contacts and calendar set themselves up
• Mail from people and colleagues looks like messenger messages; newsletters arrive as plain notifications
• Google meetings appear right after refreshing the calendar
• Fixed deleting a single occurrence of a Google event
• Bug fixes and improvements
</en-US>
<de-DE>
• Hintergrundabruf sowie Kontakte und Kalender im Telefon richten sich selbst ein
• E-Mails von Personen und Kollegen erscheinen wie Messenger-Nachrichten, Newsletter als einfache Benachrichtigung
• Google-Termine erscheinen sofort nach dem Aktualisieren des Kalenders
• Löschen eines einzelnen Termins einer Google-Serie behoben
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• La relève en arrière-plan, les contacts et l’agenda du téléphone se configurent tout seuls
• Les e-mails de personnes et de collègues s’affichent comme des messages, les newsletters en notification simple
• Les réunions Google apparaissent dès l’actualisation de l’agenda
• Correction de la suppression d’une seule occurrence d’un événement Google
• Corrections et améliorations
</fr-FR>
```
