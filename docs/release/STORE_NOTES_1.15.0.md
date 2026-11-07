# «Что нового» — 1.15.0 (141)

Номер — просьба владельца 07.11.2026 («предыдущая версия ушла в тест, так
что поднимай версию»): 1.14.0 (140) — в тестировании. Что вошло в 1.14.0 и
раньше — `STORE_NOTES_1.14.0.md`.

Тексты для магазинов — только новое (решение владельца 04.11.2026). В App
Store перетаскивание — только для iPad: на iPhone система перетаскивание
между приложениями не включает.

Добавлено и исправлено в 1.15.0:

- **Перетаскивание вложения из письма наружу** (решение владельца
  07.11.2026: «Делаем. Пакет super_drag_and_drop: Rust вам не помеха»):
  плашку вложения под заголовком письма можно вытащить мышью или пальцем:
  - Windows и macOS — в Проводник, Finder, на рабочий стол, в другое
    приложение: скачанное вложение отдаётся файлом с именем из письма,
    не скачанное — скачивается, когда его отпустили («виртуальный файл»);
  - Linux — в файловый менеджер: вложение скачивается до начала
    перетаскивания (иначе система файл не примет);
  - Android — в приложение рядом (разделённый экран, окна, DeX):
    содержимое с типом файла через свой провайдер, скачивается по запросу;
  - iPad — в «Файлы» и другие приложения (на iPhone система перетаскивание
    между приложениями не включает — там долгое нажатие, как раньше,
    открывает лист действий).
  На Android и iPad перетаскивание начинает удержание; если вложение
  удержали и отпустили на месте — открывается прежний лист действий
  (открыть, сохранить, поделиться). Политика организации запрещает
  «Поделиться» или «Открыть в других приложениях» (MDM) — перетаскивания
  нет. Пакет сам называет себя экспериментальным: каждую платформу
  проверяем отдельно (`OWNER_STEPS_1.15.0.md`, шаг 4).
  `lib/features/mail/widgets/attachment_drag_out.dart`, тест
  `test/unit/attachment_drag_out_test.dart`.
- **Файлы с компьютера в новое письмо — тем же пакетом.** Прежний
  desktop_drop убран: оба пакета ставили на окно свой приёмник, и на Windows
  второй снимал первый — файлы перестали бы бросаться в письмо. Поведение
  прежнее (`file_drop_zone.dart`, тест `test/widget/desktop_d1_test.dart`).
- **«Переместить» в письме и в беседе** (замечание владельца 07.11.2026: «в
  беседах и в самом письме нет кнопки переместить письмо»): в «Ещё» письма
  — «Переместить» в разделе «Упорядочить» (раньше — только на панели команд
  компьютера); в карточке письма беседы — первым в разделе «Переместить».
  Выбор папки — один на ленту, письмо и беседу (`move_folder_picker.dart`):
  папки ящика этого письма, без той, где оно лежит. У черновиков пункта нет.

Зависимости и лицензии (правило CLAUDE.md, проверено 07.11.2026):

- super_drag_and_drop, super_clipboard, super_native_extensions
  0.10.0-dev.2, irondash_engine_context, irondash_message_channel,
  pixel_snap — MIT, бесплатно. Версия 0.10.0-dev: последняя стабильная
  0.9.1 не совместима с device_info_plus 13 (приложение на нём).
- Ядро на Rust собирается из исходников при сборке приложения
  (native_toolchain_rust, MIT; нужен rustup на машине сборки — шаг 1 в
  `OWNER_STEPS_1.15.0.md`). 201 крейт из Cargo.lock пакета: MIT,
  Apache-2.0 и подобные свободные лицензии, `colored` — MPL-2.0 (как
  enough_mail, без изменений). GPL нет. Тексты — в приложении
  («Настройки → О приложении → Тексты лицензий → super_native_extensions
  (Rust)»), собирает `tool/dev/rust_licenses.py`, CI сверяет список с
  Cargo.lock. Строки — `LICENSING.md`, раздел 2.
- desktop_drop (Apache-2.0) — убран.

Платформы: `project.pbxproj`, `Runner.entitlements`, `Info.plist` не
менялись; в Xcode включать ничего не нужно. Android: в манифесте —
провайдер данных перетаскивания пакета (`DataProvider`, закрытый,
`exported="false"`, без новых разрешений). Скрипты сборки проверяют
наличие rustup.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• iPad: вложение перетаскивается из письма в «Файлы» и другие приложения
• «Переместить в папку» — в меню письма и в карточке письма беседы
</ru-RU>
<en-US>
• iPad: drag an attachment from a message into Files and other apps
• “Move to folder” in the message menu and on message cards in conversations
</en-US>
<de-DE>
• iPad: Anhänge aus einer Nachricht in „Dateien“ und andere Apps ziehen
• „In Ordner verschieben“ im Nachrichtenmenü und in den Nachrichtenkarten von Unterhaltungen
</de-DE>
<fr-FR>
• iPad : glissez une pièce jointe d’un message vers Fichiers et d’autres apps
• « Déplacer vers un dossier » dans le menu du message et sur les cartes des conversations
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 480.

```
<ru-RU>
• Вложение можно перетащить из письма в другое приложение на разделённом экране
• «Переместить в папку» — в меню письма и в карточке письма беседы
</ru-RU>
<en-US>
• Drag an attachment from a message into another app in split screen
• “Move to folder” in the message menu and on message cards in conversations
</en-US>
<de-DE>
• Anhänge aus einer Nachricht in eine andere App im geteilten Bildschirm ziehen
• „In Ordner verschieben“ im Nachrichtenmenü und in den Nachrichtenkarten von Unterhaltungen
</de-DE>
<fr-FR>
• Glissez une pièce jointe d’un message vers une autre app en écran partagé
• « Déplacer vers un dossier » dans le menu du message et sur les cartes des conversations
</fr-FR>
<ar>
• اسحب المرفق من الرسالة إلى تطبيق آخر في وضع تقسيم الشاشة
• «نقل إلى مجلد» في قائمة الرسالة وفي بطاقات الرسائل داخل المحادثات
</ar>
<hu-HU>
• Melléklet áthúzása levélből egy másik alkalmazásba osztott képernyőn
• „Áthelyezés mappába” a levél menüjében és a beszélgetések levélkártyáin
</hu-HU>
<vi>
• Kéo tệp đính kèm từ thư sang ứng dụng khác khi chia đôi màn hình
• “Chuyển vào thư mục” trong menu thư và trên thẻ thư của cuộc trò chuyện
</vi>
<da-DK>
• Træk en vedhæftet fil fra en mail over i en anden app på delt skærm
• “Flyt til mappe” i mailmenuen og på mailkortene i samtaler
</da-DK>
<iw-IL>
• גוררים קובץ מצורף מהודעה לאפליקציה אחרת במסך מפוצל
• ״העברה לתיקייה״ בתפריט ההודעה ובכרטיסי ההודעות בשיחות
</iw-IL>
<id>
• Seret lampiran dari email ke aplikasi lain dalam layar terpisah
• “Pindahkan ke folder” di menu email dan di kartu email dalam percakapan
</id>
<es-ES>
• Arrastra un adjunto de un correo a otra app en pantalla dividida
• «Mover a carpeta» en el menú del correo y en las tarjetas de las conversaciones
</es-ES>
<it-IT>
• Trascina un allegato da un’email in un’altra app a schermo diviso
• «Sposta nella cartella» nel menu dell’email e nelle schede delle conversazioni
</it-IT>
<zh-CN>
• 分屏时可将附件从邮件拖到其他应用
• 邮件菜单和会话中的邮件卡片新增“移动到文件夹”
</zh-CN>
<ko-KR>
• 화면 분할에서 첨부파일을 메일에서 다른 앱으로 끌어다 놓기
• 메일 메뉴와 대화의 메일 카드에 “폴더로 이동” 추가
</ko-KR>
<nl-NL>
• Sleep een bijlage uit een mail naar een andere app in gesplitst scherm
• ‘Naar map verplaatsen’ in het mailmenu en op mailkaarten in gesprekken
</nl-NL>
<no-NO>
• Dra et vedlegg fra en e-post til en annen app på delt skjerm
• «Flytt til mappe» i e-postmenyen og på e-postkortene i samtaler
</no-NO>
<pl-PL>
• Przeciągnij załącznik z wiadomości do innej aplikacji na podzielonym ekranie
• „Przenieś do folderu” w menu wiadomości i na kartach wiadomości w rozmowach
</pl-PL>
<pt-BR>
• Arraste um anexo do e-mail para outro app na tela dividida
• “Mover para pasta” no menu do e-mail e nos cartões de e-mail das conversas
</pt-BR>
<ro>
• Trage un atașament din e-mail într-o altă aplicație pe ecran împărțit
• „Mută în dosar” în meniul e-mailului și pe cardurile e-mailurilor din conversații
</ro>
<sk>
• Prílohu môžete pretiahnuť z e-mailu do inej aplikácie na rozdelenej obrazovke
• „Presunúť do priečinka“ v ponuke e-mailu a na kartách e-mailov v konverzáciách
</sk>
<th>
• ลากไฟล์แนบจากอีเมลไปยังแอปอื่นในโหมดแบ่งหน้าจอ
• “ย้ายไปยังโฟลเดอร์” ในเมนูอีเมลและในการ์ดอีเมลของการสนทนา
</th>
<tr-TR>
• Ekleri bölünmüş ekranda iletiden başka bir uygulamaya sürükleyin
• “Klasöre taşı” ileti menüsünde ve sohbetlerdeki ileti kartlarında
</tr-TR>
<fi-FI>
• Vedä liite viestistä toiseen sovellukseen jaetulla näytöllä
• ”Siirrä kansioon” viestin valikossa ja keskustelujen viestikorteissa
</fi-FI>
<hi-IN>
• स्प्लिट स्क्रीन में अटैचमेंट को मेल से दूसरे ऐप में खींचें
• मेल मेनू और बातचीत के मेल कार्ड में “फ़ोल्डर में ले जाएं”
</hi-IN>
<cs-CZ>
• Přílohu přetáhnete z e-mailu do jiné aplikace na rozdělené obrazovce
• „Přesunout do složky“ v nabídce e-mailu a na kartách e-mailů v konverzacích
</cs-CZ>
<sv-SE>
• Dra en bilaga från ett mejl till en annan app på delad skärm
• ”Flytta till mapp” i mejlmenyn och på mejlkorten i konversationer
</sv-SE>
<ja-JP>
• 画面分割時に添付ファイルをメールから別のアプリへドラッグ
• メールのメニューと会話内のメールカードに「フォルダへ移動」
</ja-JP>
```
