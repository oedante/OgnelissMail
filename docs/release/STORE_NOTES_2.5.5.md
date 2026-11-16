# «Что нового» — 2.5.5 (157), относительно 2.5.3

2.5.3 ушла тестировщикам; здесь — всё, что сделано после неё: 2.5.4
(компьютер: письма, мышь, окна) и 2.5.5 (вход напрямую у служб). Если в
магазин публикуется сборка после 2.4.0 впервые, добавьте к текстам ниже
строки из `STORE_NOTES_2.5.3.md`. Шаги владельца — `OWNER_STEPS_2.5.5.md`.

## Сделано с 2.5.3

### Вход и данные

- **Вход в Google, Microsoft и Яндекс — напрямую у службы** (OAuth 2.0
  с PKCE): приложение само обменивает код на токены и обновляет их, токены
  хранятся только на устройстве. Сервер входа Ogneliss остался только для
  Яндекса на Windows и Linux; ключей Google и Microsoft на нём нет.
- **Ящики Google и Microsoft, добавленные через сервер входа,** один раз
  показывают «Требуется вход» — «Войти снова» входит уже напрямую.
- **Gmail паролем приложения.** Если Google не пускает новых
  пользователей (у непроверенного приложения предел — 100 человек) или в
  сборке нет клиента Google, вход объясняет причину и сразу предлагает
  пароль приложения: подсказка про двухэтапную проверку и ссылка на
  страницу паролей Google.
- **Права Google сокращены:** `gmail.settings.basic` больше не
  запрашивается (перенос подписи из Gmail при добавлении ящика убран).
- **Логотипы отправителей (BIMI)** ищет служба погоды на сервере Ogneliss;
  для писем ящиков Google логотипы не ищутся — домены отправителей из Gmail
  на сервер не уходят.

### Почта

- **«Ответить с вложениями»** — в меню письма: ответ с файлами исходного
  письма (например, «согласовано» с документом).
- **Файлы в письмо из «Вложений»**: при прикреплении можно выбрать файлы
  из всех вложений почты.
- **Свайпы по умолчанию:** слева — прочитано / не прочитано, справа —
  удалить (у тех, кто не менял свайпы сам).

### Компьютер (Windows, macOS, Linux)

- **Сложные письма — целиком, во встроенном окне браузера** (Windows —
  WebView2, Mac — WKWebView), по умолчанию. Нет WebView2 — письмо сразу
  показывается упрощённо, без ожидания. Данные WebView2 — в папке
  пользователя (из «Program Files» окно не открывалось).
- **Письмо во всю ширину окна** — без ограничения ширины текста.
- **Правая кнопка мыши — везде, где есть удержание**; у ссылок в письме —
  «Открыть / Копировать» (у адреса почты — «Написать / Копировать адрес»).
- **Двойной щелчок:** письмо — в отдельном окне, папка с подпапками —
  свернуть или развернуть.
- **Значок закрепления панели папок** больше не перескакивает.
- **Windows: ответ пишется в обычном поле** — в WebView2 не доходила
  клавиатура, курсора не было.
- **Окна редактора** (новое письмо, ответ, пересылка — отдельным окном,
  как в Outlook) — пробная возможность, по умолчанию выключена:
  Настройки → Почта → Открытие писем.

### Сборка (для владельца)

- Ключи сборки: клиенты Google (`GOOGLE_ANDROID_CLIENT_ID`,
  `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_ID` и `_SECRET`) и
  `MS_CLIENT_ID` обязательны для входа через Google и Microsoft;
  `OAUTH_PROXY_URL` и `OAUTH_PROXY_KEY` — как раньше.
- Windows: плагины в окнах писем и редактора
  (`tool/desktop/windows/multi_window.ps1` — запускается сборкой сама).

## Кратко (RU / EN)

**RU.** Вход в Google, Microsoft и Яндекс — напрямую у службы, токены
остаются на устройстве; ящики Google и Microsoft один раз попросят войти
снова. Gmail можно подключить паролем приложения. «Ответить с вложениями» и
файлы из «Вложений». На компьютере — сложные письма целиком во встроенном
окне, письмо во всю ширину, правая кнопка мыши и двойной щелчок как в
Outlook. Свайпы по умолчанию: слева — прочитано, справа — удалить.

**EN.** Sign in to Google, Microsoft and Yandex directly with the provider;
tokens stay on your device, and Google and Microsoft mailboxes ask you to
sign in again once. Gmail can be added with an app password. Reply with
attachments and attach files from Attachments. On desktop: complex emails in
full in a built-in view, full-width messages, right-click and double-click
as in Outlook. Default swipes: left — read, right — delete.

## App Store — Mac (ru, en, de, fr)

Версия macOS в App Store Connect, поле «Что нового в этой версии».

```
<ru-RU>
• Сложные письма — целиком во встроенном окне, письмо во всю ширину окна
• Правая кнопка мыши и двойной щелчок — как в Outlook; меню у ссылок
• Значок закрепления панели папок больше не перескакивает
• Вход в Google, Microsoft и Яндекс — напрямую у службы; ящики Google и Microsoft один раз попросят войти снова
• Gmail можно подключить паролем приложения
• «Ответить с вложениями» и файлы в письмо из «Вложений»
• Свайпы по умолчанию: слева — прочитано, справа — удалить
• Окна редактора отдельно — пробная возможность в настройках
</ru-RU>
<en-US>
• Complex emails in full in a built-in view, messages use the full window width
• Right-click and double-click work as in Outlook; a menu for links
• The pin icon of the folder pane no longer jumps
• Sign in to Google, Microsoft and Yandex directly with the provider; Google and Microsoft mailboxes ask you to sign in again once
• Gmail can be added with an app password
• Reply with attachments; attach files from Attachments
• Default swipes: left — read/unread, right — delete
• Separate compose windows — a trial option in Settings
</en-US>
<de-DE>
• Komplexe E-Mails vollständig in einer integrierten Ansicht, E-Mails in voller Fensterbreite
• Rechtsklick und Doppelklick wie in Outlook; ein Menü für Links
• Das Anheften-Symbol der Ordnerleiste springt nicht mehr
• Anmeldung bei Google, Microsoft und Yandex direkt beim Anbieter; Google- und Microsoft-Postfächer bitten einmal um erneute Anmeldung
• Gmail lässt sich mit einem App-Passwort hinzufügen
• „Antworten mit Anhängen“ und Dateien aus „Anhänge“
• Standard-Wischgesten: links – gelesen, rechts – löschen
• Eigene Fenster zum Schreiben – Testfunktion in den Einstellungen
</de-DE>
<fr-FR>
• E-mails complexes affichés en entier dans une vue intégrée, messages sur toute la largeur
• Clic droit et double-clic comme dans Outlook ; un menu pour les liens
• L’icône d’épinglage du panneau des dossiers ne saute plus
• Connexion à Google, Microsoft et Yandex directement auprès du fournisseur ; les boîtes Google et Microsoft demandent une fois de se reconnecter
• Gmail peut être ajouté avec un mot de passe d’application
• « Répondre avec pièces jointes » et fichiers depuis « Pièces jointes »
• Balayages par défaut : à gauche — lu, à droite — supprimer
• Fenêtres de rédaction séparées — option d’essai dans les Réglages
</fr-FR>
```

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Вход в Google, Microsoft и Яндекс — напрямую у службы
• Ящики Google и Microsoft один раз попросят войти снова
• Gmail можно подключить паролем приложения
• «Ответить с вложениями» и файлы в письмо из «Вложений»
• Свайпы по умолчанию: слева — прочитано, справа — удалить
• Исправления и улучшения
</ru-RU>
<en-US>
• Sign in to Google, Microsoft and Yandex directly with the provider
• Google and Microsoft mailboxes ask you to sign in again once
• Gmail can be added with an app password
• Reply with attachments; attach files from Attachments
• Default swipes: left — read/unread, right — delete
• Fixes and improvements
</en-US>
<de-DE>
• Anmeldung bei Google, Microsoft und Yandex direkt beim Anbieter
• Google- und Microsoft-Postfächer bitten einmal um erneute Anmeldung
• Gmail lässt sich mit einem App-Passwort hinzufügen
• „Antworten mit Anhängen“ und Dateien aus „Anhänge“
• Standard-Wischgesten: links – gelesen, rechts – löschen
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Connexion à Google, Microsoft et Yandex directement auprès du fournisseur
• Les boîtes Google et Microsoft demandent une fois de se reconnecter
• Gmail peut être ajouté avec un mot de passe d’application
• « Répondre avec pièces jointes » et fichiers depuis « Pièces jointes »
• Balayages par défaut : à gauche — lu, à droite — supprimer
• Corrections et améliorations
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Каждый язык короче предела Google Play (500 знаков).

```
<ru-RU>
• Вход в Google, Microsoft и Яндекс — напрямую у службы
• Ящики Google и Microsoft один раз попросят войти снова
• Gmail можно подключить паролем приложения
• «Ответить с вложениями» и файлы в письмо из «Вложений»
• Свайпы по умолчанию: слева — прочитано, справа — удалить
• Исправления и улучшения
</ru-RU>
<en-US>
• Sign in to Google, Microsoft and Yandex directly with the provider
• Google and Microsoft mailboxes ask you to sign in again once
• Gmail can be added with an app password
• Reply with attachments; attach files from Attachments
• Default swipes: left — read/unread, right — delete
• Fixes and improvements
</en-US>
<de-DE>
• Anmeldung bei Google, Microsoft und Yandex direkt beim Anbieter
• Google- und Microsoft-Postfächer bitten einmal um erneute Anmeldung
• Gmail lässt sich mit einem App-Passwort hinzufügen
• „Antworten mit Anhängen“ und Dateien aus „Anhänge“
• Standard-Wischgesten: links – gelesen, rechts – löschen
• Fehlerbehebungen und Verbesserungen
</de-DE>
<fr-FR>
• Connexion à Google, Microsoft et Yandex directement auprès du fournisseur
• Les boîtes Google et Microsoft demandent une fois de se reconnecter
• Gmail peut être ajouté avec un mot de passe d’application
• « Répondre avec pièces jointes » et fichiers depuis « Pièces jointes »
• Balayages par défaut : à gauche — lu, à droite — supprimer
• Corrections et améliorations
</fr-FR>
<ar>
• تسجيل الدخول إلى Google وMicrosoft وYandex مباشرة لدى المزوّد
• تطلب صناديق Google وMicrosoft تسجيل الدخول مرة أخرى لمرة واحدة
• يمكن إضافة Gmail بكلمة مرور التطبيق
• «الرد مع المرفقات» وإرفاق ملفات من «المرفقات»
• السحب الافتراضي: يسارًا — مقروء، يمينًا — حذف
• إصلاحات وتحسينات
</ar>
<hu-HU>
• Bejelentkezés a Google-, Microsoft- és Yandex-fiókba közvetlenül a szolgáltatónál
• A Google- és Microsoft-postafiókok egyszer újbóli bejelentkezést kérnek
• A Gmail alkalmazásjelszóval is hozzáadható
• „Válasz mellékletekkel” és fájlok a „Mellékletek” közül
• Alapértelmezett húzás: balra — olvasott, jobbra — törlés
• Javítások és fejlesztések
</hu-HU>
<vi>
• Đăng nhập Google, Microsoft và Yandex trực tiếp với nhà cung cấp
• Hộp thư Google và Microsoft sẽ yêu cầu đăng nhập lại một lần
• Có thể thêm Gmail bằng mật khẩu ứng dụng
• "Trả lời kèm tệp đính kèm" và đính kèm tệp từ "Tệp đính kèm"
• Vuốt mặc định: trái — đã đọc, phải — xóa
• Sửa lỗi và cải tiến
</vi>
<da-DK>
• Log ind hos Google, Microsoft og Yandex direkte hos udbyderen
• Google- og Microsoft-postkasser beder én gang om nyt login
• Gmail kan tilføjes med en app-adgangskode
• »Svar med vedhæftninger« og filer fra »Vedhæftede filer«
• Standardstryg: venstre — læst, højre — slet
• Rettelser og forbedringer
</da-DK>
<iw-IL>
• כניסה ל-Google, Microsoft ו-Yandex ישירות אצל הספק
• תיבות Google ו-Microsoft יבקשו פעם אחת להתחבר מחדש
• אפשר להוסיף Gmail עם סיסמה לאפליקציה
• ״השב עם קבצים מצורפים״ וקבצים מ״קבצים מצורפים״
• החלקות ברירת מחדל: שמאלה — נקרא, ימינה — מחיקה
• תיקונים ושיפורים
</iw-IL>
<id>
• Masuk ke Google, Microsoft, dan Yandex langsung di penyedia
• Kotak surat Google dan Microsoft meminta masuk ulang sekali
• Gmail bisa ditambahkan dengan sandi aplikasi
• "Balas dengan lampiran" dan file dari "Lampiran"
• Geser bawaan: kiri — dibaca, kanan — hapus
• Perbaikan dan peningkatan
</id>
<es-ES>
• Inicio de sesión en Google, Microsoft y Yandex directamente con el proveedor
• Los buzones de Google y Microsoft piden iniciar sesión de nuevo una vez
• Gmail se puede añadir con una contraseña de aplicación
• «Responder con adjuntos» y archivos desde «Adjuntos»
• Deslizamientos por defecto: izquierda — leído, derecha — eliminar
• Correcciones y mejoras
</es-ES>
<it-IT>
• Accesso a Google, Microsoft e Yandex direttamente presso il provider
• Le caselle Google e Microsoft chiedono una volta di accedere di nuovo
• Gmail si può aggiungere con una password per le app
• «Rispondi con allegati» e file dagli «Allegati»
• Scorrimenti predefiniti: sinistra — letto, destra — elimina
• Correzioni e miglioramenti
</it-IT>
<zh-CN>
• 直接在服务提供商处登录 Google、Microsoft 和 Yandex
• Google 和 Microsoft 邮箱会要求重新登录一次
• 可使用应用专用密码添加 Gmail
• “带附件回复”，并可从“附件”中添加文件
• 默认滑动：左滑 — 已读，右滑 — 删除
• 修复与改进
</zh-CN>
<ko-KR>
• Google, Microsoft, Yandex 로그인을 서비스에서 직접 진행
• Google 및 Microsoft 메일함은 한 번 다시 로그인을 요청합니다
• Gmail을 앱 비밀번호로 추가 가능
• ‘첨부 파일과 함께 답장’ 및 ‘첨부 파일’에서 파일 첨부
• 기본 스와이프: 왼쪽 — 읽음, 오른쪽 — 삭제
• 수정 및 개선
</ko-KR>
<nl-NL>
• Inloggen bij Google, Microsoft en Yandex rechtstreeks bij de provider
• Google- en Microsoft-postvakken vragen één keer opnieuw in te loggen
• Gmail toevoegen kan met een app-wachtwoord
• ‘Beantwoorden met bijlagen’ en bestanden uit ‘Bijlagen’
• Standaardvegen: links — gelezen, rechts — verwijderen
• Oplossingen en verbeteringen
</nl-NL>
<no-NO>
• Pålogging hos Google, Microsoft og Yandex direkte hos leverandøren
• Google- og Microsoft-postbokser ber én gang om ny pålogging
• Gmail kan legges til med et apppassord
• «Svar med vedlegg» og filer fra «Vedlegg»
• Standard sveip: venstre — lest, høyre — slett
• Rettelser og forbedringer
</no-NO>
<pl-PL>
• Logowanie do Google, Microsoft i Yandex bezpośrednio u dostawcy
• Skrzynki Google i Microsoft raz poproszą o ponowne logowanie
• Gmail można dodać hasłem do aplikacji
• „Odpowiedz z załącznikami” i pliki z „Załączników”
• Domyślne przesunięcia: w lewo — przeczytane, w prawo — usuń
• Poprawki i ulepszenia
</pl-PL>
<pt-BR>
• Login no Google, Microsoft e Yandex direto com o provedor
• Caixas do Google e da Microsoft pedem novo login uma vez
• O Gmail pode ser adicionado com uma senha de app
• "Responder com anexos" e arquivos de "Anexos"
• Deslizes padrão: esquerda — lido, direita — excluir
• Correções e melhorias
</pt-BR>
<ro>
• Conectare la Google, Microsoft și Yandex direct la furnizor
• Căsuțele Google și Microsoft cer o dată reconectarea
• Gmail poate fi adăugat cu o parolă pentru aplicații
• „Răspunde cu atașamente” și fișiere din „Atașamente”
• Glisări implicite: stânga — citit, dreapta — șterge
• Corecturi și îmbunătățiri
</ro>
<sk>
• Prihlásenie do Googlu, Microsoftu a Yandexu priamo u poskytovateľa
• Schránky Google a Microsoft raz požiadajú o nové prihlásenie
• Gmail možno pridať heslom aplikácie
• „Odpovedať s prílohami“ a súbory z „Príloh“
• Predvolené potiahnutia: vľavo — prečítané, vpravo — odstrániť
• Opravy a vylepšenia
</sk>
<th>
• ลงชื่อเข้าใช้ Google, Microsoft และ Yandex โดยตรงกับผู้ให้บริการ
• กล่องจดหมาย Google และ Microsoft จะขอให้ลงชื่อเข้าใช้ใหม่หนึ่งครั้ง
• เพิ่ม Gmail ด้วยรหัสผ่านสำหรับแอปได้
• “ตอบกลับพร้อมไฟล์แนบ” และแนบไฟล์จาก “ไฟล์แนบ”
• การปัดเริ่มต้น: ซ้าย — อ่านแล้ว ขวา — ลบ
• แก้ไขและปรับปรุง
</th>
<tr-TR>
• Google, Microsoft ve Yandex'e doğrudan hizmet sağlayıcıda giriş
• Google ve Microsoft posta kutuları bir kez yeniden giriş ister
• Gmail uygulama şifresiyle eklenebilir
• “Eklerle yanıtla” ve “Ekler”den dosya ekleme
• Varsayılan kaydırma: sol — okundu, sağ — sil
• Düzeltmeler ve iyileştirmeler
</tr-TR>
<fi-FI>
• Kirjautuminen Googleen, Microsoftiin ja Yandexiin suoraan palveluntarjoajalla
• Google- ja Microsoft-postilaatikot pyytävät kerran kirjautumaan uudelleen
• Gmailin voi lisätä sovellussalasanalla
• ”Vastaa liitteiden kanssa” ja tiedostot ”Liitteistä”
• Oletuspyyhkäisyt: vasen — luettu, oikea — poista
• Korjauksia ja parannuksia
</fi-FI>
<hi-IN>
• Google, Microsoft और Yandex में सीधे सेवा प्रदाता के पास साइन इन
• Google और Microsoft मेलबॉक्स एक बार फिर से साइन इन माँगेंगे
• Gmail को ऐप पासवर्ड से जोड़ा जा सकता है
• “अटैचमेंट के साथ जवाब दें” और “अटैचमेंट” से फ़ाइलें
• डिफ़ॉल्ट स्वाइप: बाएँ — पढ़ा, दाएँ — हटाएँ
• सुधार और बेहतरियाँ
</hi-IN>
<cs-CZ>
• Přihlášení ke Googlu, Microsoftu a Yandexu přímo u poskytovatele
• Schránky Google a Microsoft jednou požádají o nové přihlášení
• Gmail lze přidat heslem aplikace
• „Odpovědět s přílohami“ a soubory z „Příloh“
• Výchozí přejetí: vlevo — přečteno, vpravo — smazat
• Opravy a vylepšení
</cs-CZ>
<sv-SE>
• Inloggning hos Google, Microsoft och Yandex direkt hos leverantören
• Google- och Microsoft-brevlådor ber en gång om ny inloggning
• Gmail kan läggas till med ett applösenord
• ”Svara med bilagor” och filer från ”Bilagor”
• Standardsvep: vänster — läst, höger — radera
• Rättelser och förbättringar
</sv-SE>
<ja-JP>
• Google、Microsoft、Yandex へのログインをサービスで直接実行
• Google と Microsoft のメールボックスは一度だけ再ログインを求めます
• Gmail をアプリ パスワードで追加可能
• 「添付ファイル付きで返信」と「添付ファイル」からの添付
• 既定のスワイプ：左 — 既読、右 — 削除
• 修正と改善
</ja-JP>
```
