# «Что нового» — 1.8.11 (127)

Два варианта — какой вставлять, зависит от того, что уже выложено в магазин.

**А. 1.8.10 (126) в магазин не выкладывалась** — полный блок от 1.8.7 (123):
то же, что в STORE_NOTES_1.8.10.md (1.8.8–1.8.11 вместе).

**Б. 1.8.10 уже выложена** — короткий блок ниже: новое только в 1.8.11.

Все 27 языков страницы магазина: блок копируется целиком в «Заметки о
выпуске» Play Console; в App Store — ru, en, de, fr. Каждый язык — не больше
500 знаков.

Что изменилось в 1.8.11 (для разработчика): Microsoft Graph перенесён в
почтовый движок (packages/mail_engine, GraphEngine) — как ActiveSync и EWS;
вход в Exchange Online и токен Graph — и через сервер входа (провайдер
exchange, сервер 1.8.11: server/oauth-proxy). Инструкция для сервера —
docs/release/SERVER_1.8.11.md.

Google Play: разрешений READ_MEDIA_IMAGES / READ_MEDIA_VIDEO в сборке нет —
отправьте выпуск во все дорожки, где ещё стоят прежние сборки (рабочая 119 и
тестовые), тогда предупреждение снимется.

## А. Полный блок (от 1.8.7)

```
<ru-RU>
• Вход одной кнопкой: Google, Яндекс, Microsoft и другие — без ввода адреса
• Exchange или IMAP — протокол виден и выбирается при входе
• «В архив Ogneliss» — из письма, свайпом и для папки целиком, с подпапками
• Шрифт интерфейса на выбор: Roboto или Medeo Sans
• Приложение больше не запрашивает доступ к фото и видео
• Меню, списки выбора и «Ещё» в письме — в едином стиле карточек
• Exchange Online: адресная книга, подсказки и правила сервера — через Microsoft Graph
</ru-RU>
<en-US>
• One-tap sign-in: Google, Yandex, Microsoft and more, no address needed
• Exchange or IMAP: the protocol is shown and can be changed at sign-in
• To Ogneliss archive from a message, by swipe, or a whole folder with subfolders
• Choose the interface font: Roboto or Medeo Sans
• The app no longer asks for access to photos and videos
• Menus, pickers and More in a message share one card style
• Exchange Online: directory, MailTips and server rules now use Microsoft Graph
</en-US>
<de-DE>
• Anmeldung mit einem Tipp: Google, Yandex, Microsoft u. a. – ohne Adresse
• Exchange oder IMAP: Protokoll sichtbar und bei der Anmeldung wählbar
• Ins Ogneliss-Archiv aus der E-Mail, per Wischen oder ganzer Ordner mit Unterordnern
• Schriftart wählbar: Roboto oder Medeo Sans
• Kein Zugriff mehr auf Fotos und Videos nötig
• Menüs, Auswahllisten und „Mehr“ in der E-Mail im einheitlichen Kartenstil
• Exchange Online: Adressbuch, E-Mail-Infos und Serverregeln über Microsoft Graph
</de-DE>
<fr-FR>
• Connexion en un geste : Google, Yandex, Microsoft et d’autres, sans adresse
• Exchange ou IMAP : le protocole est visible et modifiable à la connexion
• Vers l’archive Ogneliss depuis un message, par balayage ou tout un dossier
• Police de l’interface au choix : Roboto ou Medeo Sans
• L’app ne demande plus l’accès aux photos et vidéos
• Menus, listes de choix et « Plus » du message dans un même style de cartes
• Exchange Online : annuaire, infos-courrier et règles serveur via Microsoft Graph
</fr-FR>
<ar>
• تسجيل الدخول بلمسة: Google وYandex وMicrosoft وغيرها دون إدخال العنوان
• Exchange أو IMAP: البروتوكول ظاهر ويمكن تغييره عند الدخول
• إلى أرشيف Ogneliss من الرسالة أو بالسحب أو مجلد كامل بمجلداته الفرعية
• اختيار خط الواجهة: Roboto أو Medeo Sans
• لم يعد التطبيق يطلب الوصول إلى الصور والفيديو
• القوائم وقوائم الاختيار و«المزيد» في الرسالة بنمط بطاقات موحّد
• Exchange Online: دليل العناوين والتلميحات وقواعد الخادم عبر Microsoft Graph
</ar>
<hu-HU>
• Belépés egy koppintással: Google, Yandex, Microsoft és mások, cím nélkül
• Exchange vagy IMAP: a protokoll látható és belépéskor módosítható
• Ogneliss-archívumba levélből, húzással vagy egész mappát almappákkal
• Választható betűtípus: Roboto vagy Medeo Sans
• Az app már nem kér hozzáférést a fotókhoz és videókhoz
• Menük, választólisták és a levél „Továbbiak” gombja egységes kártyastílusban
• Exchange Online: címjegyzék, levéltippek és szabályok a Microsoft Graphon át
</hu-HU>
<vi>
• Đăng nhập một chạm: Google, Yandex, Microsoft và khác, không cần nhập địa chỉ
• Exchange hoặc IMAP: giao thức hiển thị và đổi được khi đăng nhập
• Vào kho lưu trữ Ogneliss từ thư, bằng vuốt hoặc cả thư mục kèm thư mục con
• Chọn phông chữ giao diện: Roboto hoặc Medeo Sans
• Ứng dụng không còn yêu cầu quyền truy cập ảnh và video
• Menu, danh sách chọn và mục Thêm trong thư theo cùng kiểu thẻ
• Exchange Online: danh bạ, gợi ý thư và quy tắc máy chủ qua Microsoft Graph
</vi>
<da-DK>
• Log ind med ét tryk: Google, Yandex, Microsoft m.fl. – uden adresse
• Exchange eller IMAP: protokollen vises og kan ændres ved login
• Til Ogneliss-arkivet fra en mail, med swipe eller en hel mappe med undermapper
• Vælg skrifttype: Roboto eller Medeo Sans
• Appen beder ikke længere om adgang til fotos og videoer
• Menuer, valglister og Mere i en mail i samme kortstil
• Exchange Online: adressebog, mailtip og serverregler via Microsoft Graph
</da-DK>
<iw-IL>
• כניסה בהקשה: Google,‏ Yandex,‏ Microsoft ועוד – בלי להקליד כתובת
• Exchange או IMAP: הפרוטוקול מוצג וניתן לשינוי בכניסה
• לארכיון Ogneliss מהודעה, בהחלקה או תיקייה שלמה עם תיקיות משנה
• בחירת גופן הממשק: Roboto או Medeo Sans
• האפליקציה כבר לא מבקשת גישה לתמונות ולסרטונים
• תפריטים, רשימות בחירה ו„עוד” בהודעה – בסגנון כרטיסים אחיד
• Exchange Online: ספר כתובות, עצות וכללי שרת דרך Microsoft Graph
</iw-IL>
<id>
• Masuk sekali ketuk: Google, Yandex, Microsoft, dan lainnya tanpa alamat
• Exchange atau IMAP: protokol terlihat dan bisa diganti saat masuk
• Ke arsip Ogneliss dari email, dengan geser, atau satu folder beserta subfolder
• Pilih font antarmuka: Roboto atau Medeo Sans
• Aplikasi tidak lagi meminta akses ke foto dan video
• Menu, daftar pilihan, dan Lainnya di email dengan gaya kartu yang sama
• Exchange Online: buku alamat, tips email, dan aturan server lewat Microsoft Graph
</id>
<es-ES>
• Acceso con un toque: Google, Yandex, Microsoft y más, sin escribir la dirección
• Exchange o IMAP: el protocolo se ve y se puede cambiar al iniciar sesión
• Al archivo de Ogneliss desde un mensaje, deslizando o una carpeta entera
• Fuente de la interfaz a elegir: Roboto o Medeo Sans
• La app ya no pide acceso a fotos y vídeos
• Menús, listas de selección y «Más» del mensaje con un mismo estilo de tarjetas
• Exchange Online: directorio, sugerencias y reglas del servidor con Microsoft Graph
</es-ES>
<it-IT>
• Accesso con un tocco: Google, Yandex, Microsoft e altri, senza indirizzo
• Exchange o IMAP: il protocollo è visibile e modificabile all’accesso
• Nell’archivio Ogneliss da un messaggio, con uno swipe o un’intera cartella
• Carattere dell’interfaccia a scelta: Roboto o Medeo Sans
• L’app non chiede più l’accesso a foto e video
• Menu, elenchi di scelta e «Altro» del messaggio con un unico stile a schede
• Exchange Online: rubrica, suggerimenti e regole del server con Microsoft Graph
</it-IT>
<zh-CN>
• 一键登录：Google、Yandex、Microsoft 等，无需输入地址
• Exchange 或 IMAP：登录时可见并可切换协议
• 存入 Ogneliss 归档：从邮件、滑动，或整个文件夹连同子文件夹
• 界面字体可选：Roboto 或 Medeo Sans
• 应用不再请求访问照片和视频
• 菜单、选择列表和邮件中的“更多”采用统一的卡片样式
• Exchange Online：通讯簿、邮件提示和服务器规则改用 Microsoft Graph
</zh-CN>
<ko-KR>
• 한 번에 로그인: Google, Yandex, Microsoft 등 주소 입력 없이
• Exchange 또는 IMAP: 로그인 시 프로토콜 표시 및 변경 가능
• 메일, 스와이프 또는 하위 폴더를 포함한 폴더 전체를 Ogneliss 보관함으로
• 인터페이스 글꼴 선택: Roboto 또는 Medeo Sans
• 앱이 더 이상 사진 및 동영상 접근을 요청하지 않음
• 메뉴, 선택 목록, 메일의 '더보기'를 같은 카드 스타일로 통일
• Exchange Online: 주소록, 메일 팁, 서버 규칙을 Microsoft Graph로
</ko-KR>
<nl-NL>
• Inloggen met één tik: Google, Yandex, Microsoft en meer, zonder adres
• Exchange of IMAP: het protocol is zichtbaar en te wijzigen bij inloggen
• Naar het Ogneliss-archief vanuit een bericht, met vegen of een hele map
• Kies het lettertype: Roboto of Medeo Sans
• De app vraagt geen toegang meer tot foto’s en video’s
• Menu’s, keuzelijsten en ‘Meer’ in een bericht in één kaartstijl
• Exchange Online: adresboek, e-mailtips en serverregels via Microsoft Graph
</nl-NL>
<no-NO>
• Logg inn med ett trykk: Google, Yandex, Microsoft m.fl. – uten adresse
• Exchange eller IMAP: protokollen vises og kan endres ved innlogging
• Til Ogneliss-arkivet fra en melding, med sveip eller en hel mappe
• Velg skrifttype: Roboto eller Medeo Sans
• Appen ber ikke lenger om tilgang til bilder og videoer
• Menyer, valglister og Mer i en melding i samme kortstil
• Exchange Online: adressebok, e-posttips og serverregler via Microsoft Graph
</no-NO>
<pl-PL>
• Logowanie jednym dotknięciem: Google, Yandex, Microsoft i inne – bez adresu
• Exchange lub IMAP: protokół widoczny i do zmiany przy logowaniu
• Do archiwum Ogneliss z wiadomości, przesunięciem lub cały folder z podfolderami
• Czcionka do wyboru: Roboto lub Medeo Sans
• Aplikacja nie prosi już o dostęp do zdjęć i filmów
• Menu, listy wyboru i „Więcej” w wiadomości w jednolitym stylu kart
• Exchange Online: książka adresowa, porady i reguły serwera przez Microsoft Graph
</pl-PL>
<pt-BR>
• Login com um toque: Google, Yandex, Microsoft e outros, sem digitar o endereço
• Exchange ou IMAP: o protocolo aparece e pode ser trocado no login
• Para o arquivo Ogneliss a partir da mensagem, deslizando ou uma pasta inteira
• Fonte da interface à escolha: Roboto ou Medeo Sans
• O app não pede mais acesso a fotos e vídeos
• Menus, listas de escolha e “Mais” na mensagem no mesmo estilo de cartões
• Exchange Online: diretório, dicas de e-mail e regras do servidor via Microsoft Graph
</pt-BR>
<ro>
• Conectare dintr-o atingere: Google, Yandex, Microsoft și altele, fără adresă
• Exchange sau IMAP: protocolul e vizibil și se poate schimba la conectare
• În arhiva Ogneliss din mesaj, prin glisare sau un dosar întreg cu subdosare
• Font la alegere: Roboto sau Medeo Sans
• Aplicația nu mai cere acces la fotografii și videoclipuri
• Meniurile, listele de alegere și „Mai multe” din mesaj în același stil de carduri
• Exchange Online: agendă, sfaturi și reguli de server prin Microsoft Graph
</ro>
<sk>
• Prihlásenie jedným ťuknutím: Google, Yandex, Microsoft a ďalšie – bez adresy
• Exchange alebo IMAP: protokol je viditeľný a dá sa zmeniť pri prihlásení
• Do archívu Ogneliss zo správy, potiahnutím alebo celý priečinok s podpriečinkami
• Písmo rozhrania na výber: Roboto alebo Medeo Sans
• Aplikácia už nežiada prístup k fotkám a videám
• Ponuky, zoznamy výberu a „Viac“ v správe v jednotnom štýle kariet
• Exchange Online: adresár, tipy a pravidlá servera cez Microsoft Graph
</sk>
<th>
• เข้าสู่ระบบแตะเดียว: Google, Yandex, Microsoft และอื่น ๆ ไม่ต้องพิมพ์ที่อยู่
• Exchange หรือ IMAP: เห็นโปรโตคอลและเปลี่ยนได้ตอนเข้าสู่ระบบ
• เก็บลงคลัง Ogneliss จากข้อความ ปัด หรือทั้งโฟลเดอร์พร้อมโฟลเดอร์ย่อย
• เลือกแบบอักษร: Roboto หรือ Medeo Sans
• แอปไม่ขอสิทธิ์เข้าถึงรูปภาพและวิดีโออีกต่อไป
• เมนู รายการตัวเลือก และ "เพิ่มเติม" ในข้อความเป็นการ์ดแบบเดียวกัน
• Exchange Online: สมุดที่อยู่ คำแนะนำ และกฎเซิร์ฟเวอร์ผ่าน Microsoft Graph
</th>
<tr-TR>
• Tek dokunuşla giriş: Google, Yandex, Microsoft ve diğerleri, adres gerekmez
• Exchange veya IMAP: protokol görünür ve girişte değiştirilebilir
• İletiden, kaydırarak veya alt klasörleriyle tüm klasörü Ogneliss arşivine
• Arayüz yazı tipi seçimi: Roboto veya Medeo Sans
• Uygulama artık fotoğraf ve video erişimi istemiyor
• Menüler, seçim listeleri ve iletideki Diğer aynı kart stilinde
• Exchange Online: adres defteri, ipuçları ve sunucu kuralları Microsoft Graph ile
</tr-TR>
<fi-FI>
• Kirjautuminen yhdellä napautuksella: Google, Yandex, Microsoft ym. ilman osoitetta
• Exchange tai IMAP: protokolla näkyy ja sen voi vaihtaa kirjautuessa
• Ogneliss-arkistoon viestistä, pyyhkäisyllä tai koko kansio alikansioineen
• Valittava fontti: Roboto tai Medeo Sans
• Sovellus ei enää pyydä pääsyä kuviin ja videoihin
• Valikot, valintaluettelot ja viestin Lisää samalla korttityylillä
• Exchange Online: osoitekirja, vihjeet ja palvelimen säännöt Microsoft Graphin kautta
</fi-FI>
<hi-IN>
• एक टैप में साइन-इन: Google, Yandex, Microsoft और अन्य, पता लिखे बिना
• Exchange या IMAP: साइन-इन पर प्रोटोकॉल दिखता है और बदला जा सकता है
• संदेश से, स्वाइप से या सबफ़ोल्डर सहित पूरा फ़ोल्डर Ogneliss संग्रह में
• इंटरफ़ेस फ़ॉन्ट चुनें: Roboto या Medeo Sans
• ऐप अब फ़ोटो और वीडियो की अनुमति नहीं माँगता
• मेनू, चयन सूचियाँ और संदेश में «और» — एक जैसी कार्ड शैली में
• Exchange Online: पता पुस्तिका, सुझाव और सर्वर नियम Microsoft Graph से
</hi-IN>
<cs-CZ>
• Přihlášení jedním klepnutím: Google, Yandex, Microsoft a další – bez adresy
• Exchange nebo IMAP: protokol je vidět a jde změnit při přihlášení
• Do archivu Ogneliss ze zprávy, přejetím nebo celou složku s podsložkami
• Písmo rozhraní na výběr: Roboto nebo Medeo Sans
• Aplikace už nežádá přístup k fotkám a videím
• Nabídky, seznamy výběru a „Další“ ve zprávě v jednotném stylu karet
• Exchange Online: adresář, tipy a pravidla serveru přes Microsoft Graph
</cs-CZ>
<sv-SE>
• Logga in med ett tryck: Google, Yandex, Microsoft m.fl. – utan adress
• Exchange eller IMAP: protokollet visas och kan ändras vid inloggning
• Till Ogneliss-arkivet från ett mejl, med svep eller en hel mapp med undermappar
• Välj typsnitt: Roboto eller Medeo Sans
• Appen ber inte längre om åtkomst till foton och videor
• Menyer, vallistor och Mer i ett mejl i samma kortstil
• Exchange Online: adressbok, e-posttips och serverregler via Microsoft Graph
</sv-SE>
<ja-JP>
• ワンタップでログイン：Google、Yandex、Microsoft などはアドレス入力不要
• Exchange か IMAP か：ログイン時にプロトコルを表示・変更できます
• メールから、スワイプで、またはサブフォルダーごとフォルダー全体を Ogneliss アーカイブへ
• 画面のフォントを選択：Roboto または Medeo Sans
• 写真と動画へのアクセスを要求しなくなりました
• メニュー、選択リスト、メールの「その他」をカード表示に統一
• Exchange Online：アドレス帳、メール ヒント、サーバーのルールを Microsoft Graph 経由に
</ja-JP>
```

## Б. Короткий блок (только 1.8.11)

```
<ru-RU>
• Exchange Online: адресная книга, подсказки и правила сервера через Microsoft Graph работают надёжнее
• Мелкие исправления
</ru-RU>
<en-US>
• Exchange Online: directory, MailTips and server rules via Microsoft Graph are more reliable
• Minor fixes
</en-US>
<de-DE>
• Exchange Online: Adressbuch, E-Mail-Infos und Serverregeln über Microsoft Graph sind zuverlässiger
• Kleinere Korrekturen
</de-DE>
<fr-FR>
• Exchange Online : annuaire, infos-courrier et règles du serveur via Microsoft Graph plus fiables
• Corrections mineures
</fr-FR>
<ar>
• Exchange Online: دليل العناوين وتلميحات البريد وقواعد الخادم عبر Microsoft Graph أكثر موثوقية
• إصلاحات بسيطة
</ar>
<hu-HU>
• Exchange Online: a címjegyzék, a levéltippek és a kiszolgálószabályok a Microsoft Graphon megbízhatóbbak
• Kisebb javítások
</hu-HU>
<vi>
• Exchange Online: danh bạ, mẹo thư và quy tắc máy chủ qua Microsoft Graph ổn định hơn
• Sửa lỗi nhỏ
</vi>
<da-DK>
• Exchange Online: adressebog, mailtips og serverregler via Microsoft Graph er mere pålidelige
• Mindre rettelser
</da-DK>
<iw-IL>
• Exchange Online: ספר הכתובות, עצות הדואר וכללי השרת דרך Microsoft Graph אמינים יותר
• תיקונים קטנים
</iw-IL>
<id>
• Exchange Online: buku alamat, tips email, dan aturan server lewat Microsoft Graph lebih andal
• Perbaikan kecil
</id>
<es-ES>
• Exchange Online: libreta de direcciones, sugerencias de correo y reglas del servidor vía Microsoft Graph, más fiables
• Correcciones menores
</es-ES>
<it-IT>
• Exchange Online: rubrica, suggerimenti posta e regole del server tramite Microsoft Graph più affidabili
• Correzioni minori
</it-IT>
<zh-CN>
• Exchange Online：通过 Microsoft Graph 的通讯簿、邮件提示和服务器规则更加稳定
• 小幅修复
</zh-CN>
<ko-KR>
• Exchange Online: Microsoft Graph를 통한 주소록, 메일 팁, 서버 규칙이 더 안정적입니다
• 사소한 수정
</ko-KR>
<nl-NL>
• Exchange Online: adresboek, e-mailtips en serverregels via Microsoft Graph zijn betrouwbaarder
• Kleine verbeteringen
</nl-NL>
<no-NO>
• Exchange Online: adressebok, e-posttips og serverregler via Microsoft Graph er mer pålitelige
• Mindre rettelser
</no-NO>
<pl-PL>
• Exchange Online: książka adresowa, porady pocztowe i reguły serwera przez Microsoft Graph działają pewniej
• Drobne poprawki
</pl-PL>
<pt-BR>
• Exchange Online: catálogo de endereços, dicas de e-mail e regras do servidor via Microsoft Graph mais confiáveis
• Pequenas correções
</pt-BR>
<ro>
• Exchange Online: agenda, sfaturile de e-mail și regulile serverului prin Microsoft Graph sunt mai fiabile
• Remedieri minore
</ro>
<sk>
• Exchange Online: adresár, tipy k pošte a pravidlá servera cez Microsoft Graph sú spoľahlivejšie
• Drobné opravy
</sk>
<th>
• Exchange Online: สมุดที่อยู่ คำแนะนำอีเมล และกฎของเซิร์ฟเวอร์ผ่าน Microsoft Graph เสถียรขึ้น
• แก้ไขเล็กน้อย
</th>
<tr-TR>
• Exchange Online: Microsoft Graph üzerinden adres defteri, posta ipuçları ve sunucu kuralları daha güvenilir
• Küçük düzeltmeler
</tr-TR>
<fi-FI>
• Exchange Online: osoitekirja, postivihjeet ja palvelimen säännöt Microsoft Graphin kautta toimivat luotettavammin
• Pieniä korjauksia
</fi-FI>
<hi-IN>
• Exchange Online: Microsoft Graph से पता पुस्तिका, मेल सुझाव और सर्वर नियम अब अधिक भरोसेमंद
• छोटे सुधार
</hi-IN>
<cs-CZ>
• Exchange Online: adresář, tipy k poště a pravidla serveru přes Microsoft Graph jsou spolehlivější
• Drobné opravy
</cs-CZ>
<sv-SE>
• Exchange Online: adressbok, e-posttips och serverregler via Microsoft Graph är mer tillförlitliga
• Mindre rättelser
</sv-SE>
<ja-JP>
• Exchange Online：Microsoft Graph 経由のアドレス帳、メール ヒント、サーバーのルールがより安定
• 細かな修正
</ja-JP>
```
