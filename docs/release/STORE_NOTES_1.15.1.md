# «Что нового» — 1.15.1 (142)

Номер — просьба владельца 08.11.2026 («после завершения всех доработок
пришли архив для сборки и файл „что нового“»): 1.15.0 (141) — на
согласовании в App Store. Что вошло в 1.15.0 и раньше —
`STORE_NOTES_1.15.0.md`. Тексты для магазинов — только новое.

Добавлено и исправлено в 1.15.1 (подробно — PR #53 и
`docs/plan/PLAN_2026-11.md`, раздел «Сделано»):

- «Мой день»: часы-перевёртыши; погода MET Norway через прокси на сервере
  Ogneliss (`server/weather-proxy`) — сторонние службы не видят ни
  человека, ни его IP; поиск города по списку GeoNames на сервере.
  **Работает после установки прокси** (`OWNER_STEPS_1.15.1.md`, шаг 1).
- Просмотр: поворот картинок (все платформы) и страниц PDF (Android:
  текущая или все страницы); поворот в окне картинки письма.
- Фото ящика: обрезка и поворот с видом в круге.
- Без анимации открытия письма.
- Свайпы: при двух действиях длинный свайп выполняет первое; вопросы — до
  ухода строки; в режиме выбора свайпа нет; RTL; «Вернуть» в беседе.
- Складные: список и письмо по сгибу (Z Fold в крупном масштабе).
- Только критические ошибки на экране (правило владельца, `docs/guides/ERRORS.md`);
  временные сбои — молча, с повтором.
- Если ogneliss.ru недоступен — `docs/guides/SERVER_DOWN.md`: вход
  предупреждает сразу, обновление токенов с растущей паузой, логотипы
  BIMI не ждут.
- Безопасность: сертификат сервера входа проверяется как у любого сайта;
  обход очистки CSS закрыт; ключ S/MIME удаляется с ящиком.
- Exchange: имя для входа, отличное от адреса; один ClientId на письмо
  (без дублей при обрыве VPN).
- Скорость: лента не перестраивается без изменений, синхронизация уступает
  прокрутке.
- По журналу владельца: «Коллеги из адресной книги» после фона; понятная
  строка для вложения письма, удалённого на сервере.

Зависимости: новых пакетов нет. Внешние данные: MET Norway (CC BY 4.0,
NLOD 2.0 — условия приняты владельцем 07.11.2026) и GeoNames (CC BY 4.0) —
на сервере; подписи и ссылки — в окнах погоды и поиска города, тексты — в
«Тексты лицензий»; `LICENSING.md`, раздел 2.

Платформы: `project.pbxproj`, `Runner.entitlements`, `Info.plist` не
менялись; в Xcode включать ничего не нужно.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• «Мой день»: часы-перевёртыши и погода — через сервер Ogneliss, без ваших данных
• Поворот картинок при просмотре
• Фото ящика: обрезка и поворот с видом в круге
• Длинный свайп сразу выполняет первое действие
• Меньше лишних сообщений об ошибках, лента плавнее
</ru-RU>
<en-US>
• My Day: flip clock and weather — via the Ogneliss server, without your data
• Rotate images in preview
• Mailbox photo: crop and rotate with a circle preview
• A long swipe runs the first action at once
• Fewer needless error messages, smoother list
</en-US>
<de-DE>
• „Mein Tag“: Klappuhr und Wetter – über den Ogneliss-Server, ohne Ihre Daten
• Bilder in der Vorschau drehen
• Postfachfoto: zuschneiden und drehen mit Kreisvorschau
• Langes Wischen führt sofort die erste Aktion aus
• Weniger unnötige Fehlermeldungen, flüssigere Liste
</de-DE>
<fr-FR>
• « Ma journée » : horloge à volets et météo – via le serveur Ogneliss, sans vos données
• Rotation des images dans l’aperçu
• Photo de la boîte : recadrer et pivoter avec aperçu en cercle
• Un balayage long exécute aussitôt la première action
• Moins de messages d’erreur inutiles, liste plus fluide
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 480.

```
<ru-RU>
• «Мой день»: часы-перевёртыши и погода — через сервер Ogneliss, без ваших данных
• Поворот картинок и страниц PDF при просмотре
• Фото ящика: обрезка и поворот с видом в круге
• Длинный свайп сразу выполняет первое действие
• Складные телефоны: список и письмо по сгибу экрана
• Меньше лишних сообщений об ошибках, лента плавнее
</ru-RU>
<en-US>
• My Day: flip clock and weather — via the Ogneliss server, without your data
• Rotate images and PDF pages in preview
• Mailbox photo: crop and rotate with a circle preview
• A long swipe runs the first action at once
• Foldable phones: list and message split at the fold
• Fewer needless error messages, smoother list
</en-US>
<de-DE>
• „Mein Tag“: Klappuhr und Wetter – über den Ogneliss-Server, ohne Ihre Daten
• Bilder und PDF-Seiten in der Vorschau drehen
• Postfachfoto: zuschneiden und drehen mit Kreisvorschau
• Langes Wischen führt sofort die erste Aktion aus
• Faltbare Telefone: Liste und Nachricht am Falz geteilt
• Weniger unnötige Fehlermeldungen, flüssigere Liste
</de-DE>
<fr-FR>
• « Ma journée » : horloge à volets et météo – via le serveur Ogneliss, sans vos données
• Rotation des images et des pages PDF dans l’aperçu
• Photo de la boîte : recadrer et pivoter avec aperçu en cercle
• Un balayage long exécute aussitôt la première action
• Téléphones pliables : liste et message de part et d’autre du pli
• Moins de messages d’erreur inutiles, liste plus fluide
</fr-FR>
<ar>
• «يومي»: ساعة قلّابة وطقس — عبر خادم Ogneliss دون بياناتك
• تدوير الصور وصفحات PDF أثناء المعاينة
• صورة صندوق البريد: قص وتدوير مع معاينة دائرية
• السحب الطويل ينفّذ الإجراء الأول فورًا
• الهواتف القابلة للطي: القائمة والرسالة على جانبي الطي
• رسائل خطأ أقل وقائمة أكثر سلاسة
</ar>
<hu-HU>
• „Napom”: lapozós óra és időjárás – az Ogneliss szerverén át, az ön adatai nélkül
• Képek és PDF-oldalak forgatása előnézetben
• Postafiók fotója: vágás és forgatás kör alakú előnézettel
• A hosszú húzás azonnal végrehajtja az első műveletet
• Összehajtható telefonok: lista és levél a hajtás két oldalán
• Kevesebb fölösleges hibaüzenet, gördülékenyebb lista
</hu-HU>
<vi>
• “Ngày của tôi”: đồng hồ lật và thời tiết — qua máy chủ Ogneliss, không dùng dữ liệu của bạn
• Xoay ảnh và trang PDF khi xem trước
• Ảnh hộp thư: cắt và xoay với khung tròn xem trước
• Vuốt dài để thực hiện ngay thao tác đầu tiên
• Điện thoại gập: danh sách và thư chia theo nếp gập
• Ít thông báo lỗi thừa hơn, danh sách mượt hơn
</vi>
<da-DK>
• “Min dag”: vippeur og vejr – via Ogneliss-serveren, uden dine data
• Rotér billeder og PDF-sider i forhåndsvisning
• Postkassefoto: beskær og rotér med cirkelvisning
• Et langt stryg udfører straks den første handling
• Foldbare telefoner: liste og mail delt ved folden
• Færre unødvendige fejlbeskeder, glattere liste
</da-DK>
<iw-IL>
• ״היום שלי״: שעון מתהפך ומזג אוויר — דרך שרת Ogneliss, בלי הנתונים שלכם
• סיבוב תמונות ועמודי PDF בתצוגה המקדימה
• תמונת תיבה: חיתוך וסיבוב עם תצוגה בעיגול
• החלקה ארוכה מבצעת מיד את הפעולה הראשונה
• טלפונים מתקפלים: רשימה והודעה משני צדי הקפל
• פחות הודעות שגיאה מיותרות, רשימה חלקה יותר
</iw-IL>
<id>
• “Hari Saya”: jam balik dan cuaca — lewat server Ogneliss, tanpa data Anda
• Putar gambar dan halaman PDF saat pratinjau
• Foto kotak surat: potong dan putar dengan pratinjau lingkaran
• Usapan panjang langsung menjalankan tindakan pertama
• Ponsel lipat: daftar dan email terbagi di lipatan
• Lebih sedikit pesan galat yang tidak perlu, daftar lebih mulus
</id>
<es-ES>
• «Mi día»: reloj de paletas y tiempo — a través del servidor de Ogneliss, sin sus datos
• Girar imágenes y páginas PDF en la vista previa
• Foto del buzón: recortar y girar con vista en círculo
• Un deslizamiento largo ejecuta al instante la primera acción
• Plegables: lista y correo a cada lado del pliegue
• Menos mensajes de error innecesarios, lista más fluida
</es-ES>
<it-IT>
• «La mia giornata»: orologio a palette e meteo — tramite il server Ogneliss, senza i tuoi dati
• Ruota immagini e pagine PDF nell’anteprima
• Foto della casella: ritaglia e ruota con anteprima nel cerchio
• Uno scorrimento lungo esegue subito la prima azione
• Pieghevoli: elenco ed email ai due lati della piega
• Meno messaggi di errore inutili, elenco più fluido
</it-IT>
<zh-CN>
• “我的一天”：翻页时钟和天气——经由 Ogneliss 服务器，不使用您的数据
• 预览时可旋转图片和 PDF 页面
• 邮箱头像：裁剪和旋转，带圆形预览
• 长滑立即执行第一个操作
• 折叠屏手机：列表和邮件沿折痕分开
• 更少多余的错误提示，列表更流畅
</zh-CN>
<ko-KR>
• “나의 하루”: 플립 시계와 날씨 — Ogneliss 서버를 거쳐, 사용자 데이터 없이
• 미리보기에서 이미지와 PDF 페이지 회전
• 메일함 사진: 원형 미리보기로 자르기와 회전
• 길게 밀면 첫 번째 동작을 바로 실행
• 폴더블 휴대폰: 접는 부분을 기준으로 목록과 메일 분할
• 불필요한 오류 메시지 감소, 더 부드러운 목록
</ko-KR>
<nl-NL>
• ‘Mijn dag’: klapklok en weer – via de Ogneliss-server, zonder uw gegevens
• Afbeeldingen en PDF-pagina’s draaien in de voorvertoning
• Mailboxfoto: bijsnijden en draaien met cirkelvoorbeeld
• Lang vegen voert meteen de eerste actie uit
• Vouwbare telefoons: lijst en mail aan weerszijden van de vouw
• Minder onnodige foutmeldingen, soepelere lijst
</nl-NL>
<no-NO>
• «Min dag»: vippeklokke og vær – via Ogneliss-serveren, uten dine data
• Roter bilder og PDF-sider i forhåndsvisning
• Postkassebilde: beskjær og roter med sirkelvisning
• Et langt sveip utfører straks den første handlingen
• Sammenleggbare telefoner: liste og e-post delt ved bretten
• Færre unødvendige feilmeldinger, jevnere liste
</no-NO>
<pl-PL>
• „Mój dzień”: zegar z klapkami i pogoda — przez serwer Ogneliss, bez Twoich danych
• Obracanie obrazów i stron PDF w podglądzie
• Zdjęcie skrzynki: przycinanie i obracanie z podglądem w kole
• Długie przesunięcie od razu wykonuje pierwszą akcję
• Składane telefony: lista i wiadomość po obu stronach zgięcia
• Mniej zbędnych komunikatów o błędach, płynniejsza lista
</pl-PL>
<pt-BR>
• “Meu dia”: relógio de palhetas e clima — pelo servidor Ogneliss, sem seus dados
• Gire imagens e páginas de PDF na visualização
• Foto da caixa: recorte e gire com prévia em círculo
• Um deslize longo executa na hora a primeira ação
• Celulares dobráveis: lista e e-mail divididos na dobra
• Menos mensagens de erro desnecessárias, lista mais fluida
</pt-BR>
<ro>
• „Ziua mea”: ceas cu palete și vremea — prin serverul Ogneliss, fără datele tale
• Rotirea imaginilor și a paginilor PDF în previzualizare
• Fotografia căsuței: decupare și rotire cu previzualizare în cerc
• O glisare lungă execută imediat prima acțiune
• Telefoane pliabile: listă și e-mail de o parte și de alta a pliului
• Mai puține mesaje de eroare inutile, listă mai fluidă
</ro>
<sk>
• „Môj deň“: preklápacie hodiny a počasie – cez server Ogneliss, bez vašich údajov
• Otáčanie obrázkov a strán PDF v náhľade
• Fotka schránky: orezanie a otočenie s náhľadom v kruhu
• Dlhé potiahnutie hneď vykoná prvú akciu
• Skladacie telefóny: zoznam a e-mail rozdelené pri ohybe
• Menej zbytočných chybových hlásení, plynulejší zoznam
</sk>
<th>
• “วันของฉัน”: นาฬิกาพลิกและสภาพอากาศ — ผ่านเซิร์ฟเวอร์ Ogneliss ไม่ใช้ข้อมูลของคุณ
• หมุนรูปภาพและหน้า PDF ขณะดูตัวอย่าง
• รูปกล่องจดหมาย: ครอปและหมุนพร้อมตัวอย่างวงกลม
• ปัดยาวเพื่อทำการกระทำแรกทันที
• โทรศัพท์พับได้: รายการและอีเมลแบ่งตามรอยพับ
• ข้อความข้อผิดพลาดที่ไม่จำเป็นน้อยลง รายการลื่นขึ้น
</th>
<tr-TR>
• “Günüm”: çevirmeli saat ve hava durumu — Ogneliss sunucusu üzerinden, verileriniz olmadan
• Önizlemede resimleri ve PDF sayfalarını döndürün
• Posta kutusu fotoğrafı: daire önizlemeyle kırpma ve döndürme
• Uzun kaydırma ilk işlemi hemen yapar
• Katlanabilir telefonlar: liste ve ileti katın iki yanında
• Daha az gereksiz hata mesajı, daha akıcı liste
</tr-TR>
<fi-FI>
• ”Oma päivä”: kääntölehtikello ja sää – Ogneliss-palvelimen kautta, ilman tietojasi
• Kierrä kuvia ja PDF-sivuja esikatselussa
• Postilaatikon kuva: rajaa ja kierrä ympyräesikatselulla
• Pitkä pyyhkäisy suorittaa heti ensimmäisen toiminnon
• Taitettavat puhelimet: lista ja viesti taitoksen eri puolilla
• Vähemmän turhia virheilmoituksia, sujuvampi lista
</fi-FI>
<hi-IN>
• “मेरा दिन”: फ़्लिप घड़ी और मौसम — Ogneliss सर्वर से, आपके डेटा के बिना
• प्रीव्यू में चित्र और PDF पेज घुमाएँ
• मेलबॉक्स फ़ोटो: गोल प्रीव्यू के साथ काटें और घुमाएँ
• लंबा स्वाइप पहली कार्रवाई तुरंत करता है
• फ़ोल्ड होने वाले फ़ोन: मोड़ पर सूची और मेल अलग
• कम अनावश्यक त्रुटि संदेश, सूची अधिक सहज
</hi-IN>
<cs-CZ>
• „Můj den“: překlápěcí hodiny a počasí – přes server Ogneliss, bez vašich dat
• Otáčení obrázků a stránek PDF v náhledu
• Fotka schránky: oříznutí a otočení s náhledem v kruhu
• Dlouhé přejetí hned provede první akci
• Skládací telefony: seznam a e-mail rozdělené v ohybu
• Méně zbytečných chybových hlášení, plynulejší seznam
</cs-CZ>
<sv-SE>
• ”Min dag”: vippklocka och väder – via Ogneliss-servern, utan dina data
• Rotera bilder och PDF-sidor i förhandsvisningen
• Brevlådefoto: beskär och rotera med cirkelvisning
• Ett långt svep utför direkt den första åtgärden
• Vikbara telefoner: lista och mejl delade vid vecket
• Färre onödiga felmeddelanden, smidigare lista
</sv-SE>
<ja-JP>
• 「マイデイ」: パタパタ時計と天気 — Ogneliss サーバー経由、あなたのデータは使いません
• プレビューで画像と PDF ページを回転
• メールボックスの写真: 円形プレビューで切り抜きと回転
• 長くスワイプすると最初の操作をすぐに実行
• 折りたたみスマホ: 折り目で一覧とメールを分割
• 不要なエラー表示を減らし、一覧がよりなめらかに
</ja-JP>
```
