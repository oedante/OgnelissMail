# «Что нового» — 2.6.6 (165), относительно 2.6.5 (164)

2.6.5 (164) — в Google Play и App Store; 2.6.6 — свои приветствия с
полями и фото собеседников без повторной загрузки. Шаги владельца —
`OWNER_STEPS_2.6.6.md`.

## Сделано в 2.6.6

- **Свои приветствия с полями {…}** (просьба пользователей через владельца
  18.11.2026). «Настройки → Аккаунты → ящик → Подписи → Добавить своё
  приветствие»: текст и кнопки полей — адресат ({обращение} — «Иван
  Петрович», как в обычном приветствии; {имя_адресата},
  {фамилия_адресата}, {фио_адресата}), время ({время_суток} — «Доброе утро
  / Добрый день / Добрый вечер» по времени отправки; {дата}, {время}) и
  вы ({имя}, {должность}, {отдел}, {компания}, {телефон}, {почта}). Образец
  «В письме: …» показывает, как будет выглядеть. Новое приветствие сразу
  становится приветствием ящика; в письме все свои приветствия — в кнопке
  «Приветствие» над текстом; быстрый ответ и письма поручений — тоже по
  нему. Поле без значения пропадает вместе с лишней запятой
  («Здравствуйте, {обращение}!» без имени — «Здравствуйте!»). Работают и
  английские написания ({to_address}, {part_of_day}…), регистр не важен.
- **Кнопки полей в конструкторе подписи** — вставка в место курсора, и в
  редакторе с оформлением. Подпись понимает и русские написания полей
  ({имя}, {должность}, {телефон}).
- **Фото собеседников из профилей Google не пропадают** после
  сворачивания (замечание владельца 18.11): раньше фото по ссылке держались
  только в памяти и после каждого возврата в приложение скачивались заново
  — на их месте мелькал пустой кружок. Теперь фото скачивается один раз и
  хранится на телефоне, раз в неделю тихо обновляется; без сети —
  сохранённая копия.
- «Вопросы и ответы»: «Как сделать своё приветствие?» (27 языков); поиск
  по настройкам находит «Своё приветствие».

## Кратко (RU / EN)

**RU.** Свои приветствия с полями: обращение к адресату, время суток, ваши
имя и должность — с кнопками для вставки и образцом. Те же поля — в
конструкторе подписи. Фото собеседников из Google больше не пропадают
после сворачивания приложения.

**EN.** Custom greetings with fields: the recipient's name, the time of
day, your name and job title — with insert buttons and a preview. The same
fields are available in the signature editor. Contact photos from Google
no longer disappear after you switch apps.

## Google Play — короткий текст (27 языков)

```
<ru-RU>
• Свои приветствия с полями: обращение, время суток и другие
• Кнопки полей в конструкторе подписи
• Фото собеседников не пропадают после сворачивания
• Исправления и улучшения
</ru-RU>
<en-US>
• Custom greetings with fields: name, time of day and more
• Field buttons in the signature editor
• Contact photos no longer vanish after switching apps
• Bug fixes and improvements
</en-US>
<de-DE>
• Eigene Begrüßungen mit Feldern: Anrede, Tageszeit und mehr
• Feld-Schaltflächen im Signatur-Editor
• Kontaktfotos verschwinden nicht mehr nach dem App-Wechsel
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Salutations personnalisées avec champs : nom, moment de la journée…
• Boutons de champs dans l’éditeur de signature
• Les photos des contacts ne disparaissent plus après un changement d’app
• Corrections et améliorations
</fr-FR>
<ar>
• تحيات مخصصة بحقول: الاسم ووقت اليوم وغيرها
• أزرار الحقول في محرر التوقيع
• لم تعد صور جهات الاتصال تختفي بعد التبديل بين التطبيقات
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Saját megszólítások mezőkkel: név, napszak és más
• Mezőgombok az aláírásszerkesztőben
• A partnerfotók nem tűnnek el alkalmazásváltás után
• Hibajavítások és fejlesztések
</hu-HU>
<vi>
• Lời chào riêng với trường: tên, buổi trong ngày và hơn thế
• Nút chèn trường trong trình sửa chữ ký
• Ảnh liên hệ không còn biến mất sau khi chuyển ứng dụng
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Egne hilsner med felter: navn, tid på dagen og mere
• Feltknapper i signatureditoren
• Kontaktbilleder forsvinder ikke længere efter appskift
• Fejlrettelser og forbedringer
</da-DK>
<iw-IL>
• ברכות מותאמות עם שדות: שם, שעה ביום ועוד
• כפתורי שדות בעורך החתימה
• תמונות אנשי קשר כבר לא נעלמות אחרי מעבר בין אפליקציות
• תיקונים ושיפורים
</iw-IL>
<id>
• Salam khusus dengan kolom: nama, waktu hari, dan lainnya
• Tombol kolom di editor tanda tangan
• Foto kontak tidak lagi hilang setelah berpindah aplikasi
• Perbaikan dan peningkatan
</id>
<es-ES>
• Saludos personalizados con campos: nombre, momento del día y más
• Botones de campos en el editor de firmas
• Las fotos de contactos ya no desaparecen al cambiar de app
• Correcciones y mejoras
</es-ES>
<it-IT>
• Saluti personalizzati con campi: nome, momento della giornata e altro
• Pulsanti dei campi nell’editor della firma
• Le foto dei contatti non spariscono più dopo il cambio di app
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 自定义问候语支持字段：称呼、时段等
• 签名编辑器中的字段按钮
• 切换应用后联系人照片不再消失
• 问题修复和改进
</zh-CN>
<ko-KR>
• 필드를 지원하는 사용자 인사말: 호칭, 시간대 등
• 서명 편집기의 필드 버튼
• 앱 전환 후 연락처 사진이 더 이상 사라지지 않음
• 버그 수정 및 개선
</ko-KR>
<nl-NL>
• Eigen begroetingen met velden: naam, dagdeel en meer
• Veldknoppen in de handtekeningeditor
• Contactfoto’s verdwijnen niet meer na wisselen van app
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Egne hilsener med felt: navn, tid på døgnet og mer
• Feltknapper i signaturredigeringen
• Kontaktbilder forsvinner ikke lenger etter appbytte
• Feilrettinger og forbedringer
</no-NO>
<pl-PL>
• Własne powitania z polami: zwrot, pora dnia i inne
• Przyciski pól w edytorze podpisu
• Zdjęcia kontaktów nie znikają już po przełączeniu aplikacji
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• Saudações personalizadas com campos: nome, período do dia e mais
• Botões de campos no editor de assinatura
• Fotos de contatos não somem mais ao trocar de app
• Correções e melhorias
</pt-BR>
<ro>
• Saluturi personalizate cu câmpuri: nume, moment al zilei și altele
• Butoane de câmpuri în editorul de semnătură
• Fotografiile contactelor nu mai dispar după schimbarea aplicației
• Remedieri și îmbunătățiri
</ro>
<sk>
• Vlastné pozdravy s poľami: oslovenie, časť dňa a ďalšie
• Tlačidlá polí v editore podpisu
• Fotky kontaktov už nemiznú po prepnutí aplikácie
• Opravy a vylepšenia
</sk>
<th>
• คำทักทายของคุณพร้อมช่องข้อมูล: ชื่อ ช่วงเวลา และอื่น ๆ
• ปุ่มแทรกช่องในตัวแก้ไขลายเซ็น
• รูปผู้ติดต่อไม่หายไปหลังสลับแอปอีกต่อไป
• แก้ไขข้อบกพร่องและปรับปรุง
</th>
<tr-TR>
• Alanlı özel selamlamalar: hitap, günün saati ve dahası
• İmza düzenleyicide alan düğmeleri
• Kişi fotoğrafları uygulama değiştirince artık kaybolmuyor
• Hata düzeltmeleri ve iyileştirmeler
</tr-TR>
<fi-FI>
• Omat tervehdykset kentillä: puhuttelu, vuorokaudenaika ja muuta
• Kenttäpainikkeet allekirjoituseditorissa
• Yhteystietojen kuvat eivät enää katoa sovellusta vaihtaessa
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• फ़ील्ड वाले अपने अभिवादन: संबोधन, दिन का समय और अधिक
• हस्ताक्षर संपादक में फ़ील्ड बटन
• ऐप बदलने के बाद संपर्क फ़ोटो अब गायब नहीं होतीं
• सुधार और बेहतरी
</hi-IN>
<cs-CZ>
• Vlastní pozdravy s poli: oslovení, část dne a další
• Tlačítka polí v editoru podpisu
• Fotky kontaktů už po přepnutí aplikace nemizí
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Egna hälsningar med fält: tilltal, tid på dagen och mer
• Fältknappar i signaturredigeraren
• Kontaktfoton försvinner inte längre efter appbyte
• Felrättningar och förbättringar
</sv-SE>
<ja-JP>
• フィールド付きの自分の挨拶：宛名、時間帯など
• 署名エディタのフィールドボタン
• アプリ切り替え後も連絡先の写真が消えなくなりました
• 不具合の修正と改善
</ja-JP>
```

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Свои приветствия с полями: обращение, время суток и другие
• Кнопки полей в конструкторе подписи
• Фото собеседников не пропадают после сворачивания
• Исправления и улучшения
</ru-RU>
<en-US>
• Custom greetings with fields: name, time of day and more
• Field buttons in the signature editor
• Contact photos no longer vanish after switching apps
• Bug fixes and improvements
</en-US>
<de-DE>
• Eigene Begrüßungen mit Feldern: Anrede, Tageszeit und mehr
• Feld-Schaltflächen im Signatur-Editor
• Kontaktfotos verschwinden nicht mehr nach dem App-Wechsel
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Salutations personnalisées avec champs : nom, moment de la journée…
• Boutons de champs dans l’éditeur de signature
• Les photos des contacts ne disparaissent plus après un changement d’app
• Corrections et améliorations
</fr-FR>
```
