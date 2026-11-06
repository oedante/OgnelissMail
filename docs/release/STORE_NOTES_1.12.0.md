# «Что нового» — 1.12.0 (138)

Номер — решение владельца 04.11.2026 (архив для Android и iOS, выпуск в
магазины). Архив 1.11.0 (137) — `STORE_NOTES_1.11.0.md`; что вошло в 1.11.0
и раньше — там.

Тексты для магазинов — только то, что действительно ново в 1.12.0:
новое, исправленное и обновлённое (решение владельца 04.11.2026: «не копируй
старый текст»). На iPhone и iPad документы Office, RTF и CSV по-прежнему
показывает Просмотр iOS, поэтому в App Store из документов — только
OpenDocument.

Добавлено и исправлено в 1.12.0 (после архива 1.11.0):

- **Предпросмотр документов во вложениях** (план владельца 04.11.2026):
  - DOCX, DOCM, DOTX, ODT, RTF — текстом в том же защищённом окне, что
    письмо (без сети и JavaScript, тёмная тема, масштаб; на компьютере —
    виджетами): заголовки, списки с нумерацией, таблицы с объединёнными
    ячейками, картинки, ссылки (через проверку домена), сноски; RTF из
    русского Word в Windows-1251;
  - XLSX, XLSM, ODS, CSV, TSV — сеткой листов: закреплённые заголовки
    столбцов и номера строк, листы внизу, объединения, заливка и шрифты,
    форматы чисел и дат по языку приложения, строка с полным текстом
    ячейки, масштаб; CSV из русского Excel (Windows-1251, «;»);
  - PPTX, PPSX, ODP — слайдами, по нажатию — во весь экран с масштабом;
  - формат — по содержимому: «.doc», который на деле RTF или DOCX, и
    таблица ODS с расширением .xlsx открываются правильно;
  - документ с паролем, старые .doc/.xls/.ppt, слишком большой файл —
    понятной строкой и кнопкой «Открыть во внешнем приложении»; большой
    документ — началом с плашкой;
  - iPhone и iPad: Office, RTF, CSV — по-прежнему Просмотр iOS;
    OpenDocument (его Просмотр не открывает) — приложение;
  - «Настройки → Почта → Просмотр документов»: общий выключатель и виды
    (текстовые документы, таблицы, CSV таблицей, презентации); выключенный
    вид открывается, как раньше;
  - защита от испорченных файлов: пределы на распакованное («ZIP-бомба»),
    разбор в отдельном потоке с остановкой через 30 с, макросы не
    выполняются;
  - FAQ: ответ «Какие вложения открываются прямо в приложении?» переписан,
    новый вопрос «Как выключить просмотр документов в приложении?» (27
    языков);
  - патентные условия форматов — `LICENSING.md`, раздел 6.
- **Перевод: язык письма по основному алфавиту** (журнал владельца
  04.11.2026: «язык письма не определён», «Не удалось перевести»): подпись
  на двух языках и письмо с переводом рядом сбивали ML Kit; короткое
  русское письмо больше не определяется как украинское.
- **Шапки цитат на языке приложения** (замечание владельца 04.11.2026):
  From / Sent / To / Cc / Subject — подписями приложения, английская дата —
  «четверг, 22 октября 2026 г. 14:48» (нажимается, как и раньше).
- **Календарь:** «Весь день» у встречи через полночь давал событие на два
  дня (замечание владельца 04.11.2026, события iCloud).

Платформы: новых разрешений, прав и возможностей нет; project.pbxproj,
Runner.entitlements и Info.plist не менялись; в Xcode включать ничего не
нужно.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• Документы OpenDocument (ODT, ODS, ODP) — прямо в почте: тексты, таблицы с листами, презентации слайдами
• Просмотр документов отключается целиком или по видам (Настройки → Почта)
• Шапки цитат (От, Кому, Отправлено) и даты — на языке приложения
• Точнее определяется язык письма для перевода
• Исправлено: событие на весь день могло растянуться на два дня
</ru-RU>
<en-US>
• OpenDocument files (ODT, ODS, ODP) right in the app: text, spreadsheets with sheets, slides
• Document preview can be turned off entirely or by type (Settings → Mail)
• Quoted message headers (From, To, Sent) and dates in the app’s language
• More accurate language detection for translation
• Fixed: an all-day event could stretch over two days
</en-US>
<de-DE>
• OpenDocument-Dateien (ODT, ODS, ODP) direkt in der App: Texte, Tabellen mit Blättern, Folien
• Dokumentvorschau ganz oder je Dateityp abschaltbar (Einstellungen → E-Mail)
• Kopfzeilen zitierter Nachrichten (Von, An, Gesendet) und Datum in der App-Sprache
• Genauere Spracherkennung für die Übersetzung
• Behoben: Ganztägige Termine konnten sich über zwei Tage erstrecken
</de-DE>
<fr-FR>
• Fichiers OpenDocument (ODT, ODS, ODP) directement dans l’app : textes, tableurs avec leurs feuilles, diapositives
• Aperçu des documents désactivable en entier ou par type (Réglages → Messagerie)
• En-têtes des messages cités (De, À, Envoyé) et dates dans la langue de l’app
• Détection plus précise de la langue pour la traduction
• Corrigé : un événement sur toute la journée pouvait s’étendre sur deux jours
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 480.

```
<ru-RU>
• Документы прямо в почте: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF и CSV
• Таблицы — с листами, презентации — слайдами
• Просмотр документов отключается целиком или по видам
• Шапки цитат (От, Кому, Отправлено) и даты — на языке приложения
• Точнее определяется язык письма для перевода
• Исправлено: событие на весь день могло растянуться на два дня
</ru-RU>
<en-US>
• Documents right in the app: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF and CSV
• Spreadsheets with their sheets, presentations as slides
• Document preview can be turned off entirely or by type
• Quoted message headers (From, To, Sent) and dates in the app’s language
• More accurate language detection for translation
• Fixed: an all-day event could stretch over two days
</en-US>
<de-DE>
• Dokumente direkt in der App: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF und CSV
• Tabellen mit ihren Blättern, Präsentationen als Folien
• Dokumentvorschau ganz oder je Dateityp abschaltbar
• Kopfzeilen zitierter Nachrichten (Von, An, Gesendet) und Datum in der App-Sprache
• Genauere Spracherkennung für die Übersetzung
• Behoben: Ganztägige Termine konnten sich über zwei Tage erstrecken
</de-DE>
<fr-FR>
• Documents directement dans l’app : DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF et CSV
• Tableurs avec leurs feuilles, présentations en diapositives
• Aperçu des documents désactivable en entier ou par type
• En-têtes des messages cités (De, À, Envoyé) et dates dans la langue de l’app
• Détection plus précise de la langue pour la traduction
• Corrigé : un événement sur toute la journée pouvait s’étendre sur deux jours
</fr-FR>
<ar>
• المستندات داخل التطبيق مباشرةً: DOCX وXLSX وPPTX وODT وODS وODP وRTF وCSV
• جداول البيانات مع أوراقها والعروض التقديمية كشرائح
• يمكن إيقاف معاينة المستندات كليًا أو حسب النوع
• رؤوس الرسائل المقتبسة (من، إلى، أُرسلت) والتواريخ بلغة التطبيق
• تحديد أدق للغة الرسالة عند الترجمة
• تم الإصلاح: قد يمتد حدث طوال اليوم على يومين
</ar>
<hu-HU>
• Dokumentumok közvetlenül az alkalmazásban: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF és CSV
• Táblázatok munkalapokkal, bemutatók diákként
• A dokumentumok előnézete teljesen vagy típusonként kikapcsolható
• Az idézett üzenetek fejléce (Feladó, Címzett, Elküldve) és a dátumok az alkalmazás nyelvén
• Pontosabb nyelvfelismerés a fordításhoz
• Javítva: az egész napos esemény két napra nyúlhatott
</hu-HU>
<vi>
• Xem tài liệu ngay trong ứng dụng: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF và CSV
• Bảng tính kèm các trang tính, bản trình bày theo từng trang chiếu
• Có thể tắt xem trước tài liệu hoàn toàn hoặc theo loại
• Phần đầu thư được trích dẫn (Từ, Đến, Đã gửi) và ngày tháng theo ngôn ngữ ứng dụng
• Nhận diện ngôn ngữ chính xác hơn khi dịch
• Đã sửa: sự kiện cả ngày có thể kéo dài sang hai ngày
</vi>
<da-DK>
• Dokumenter direkte i appen: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF og CSV
• Regneark med faner, præsentationer som dias
• Forhåndsvisning af dokumenter kan slås helt fra eller pr. type
• Overskrifter i citerede beskeder (Fra, Til, Sendt) og datoer på appens sprog
• Mere præcis sproggenkendelse til oversættelse
• Rettet: en heldagsbegivenhed kunne strække sig over to dage
</da-DK>
<iw-IL>
• מסמכים ישירות באפליקציה: DOCX,‏ XLSX,‏ PPTX,‏ ODT,‏ ODS,‏ ODP,‏ RTF ו-CSV
• גיליונות אלקטרוניים עם הגיליונות שלהם, מצגות כשקופיות
• אפשר לכבות את התצוגה המקדימה של מסמכים לגמרי או לפי סוג
• כותרות של הודעות מצוטטות (מאת, אל, נשלח) ותאריכים בשפת האפליקציה
• זיהוי שפה מדויק יותר לתרגום
• תוקן: אירוע של יום שלם עלול היה להימשך יומיים
</iw-IL>
<id>
• Dokumen langsung di aplikasi: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, dan CSV
• Spreadsheet lengkap dengan lembarnya, presentasi sebagai slide
• Pratinjau dokumen dapat dimatikan seluruhnya atau per jenis
• Header pesan yang dikutip (Dari, Kepada, Dikirim) dan tanggal dalam bahasa aplikasi
• Deteksi bahasa yang lebih akurat untuk terjemahan
• Diperbaiki: acara sepanjang hari bisa terbentang dua hari
</id>
<es-ES>
• Documentos en la propia app: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF y CSV
• Hojas de cálculo con sus hojas, presentaciones en diapositivas
• Vista previa de documentos desactivable por completo o por tipo
• Encabezados de mensajes citados (De, Para, Enviado) y fechas en el idioma de la app
• Detección del idioma más precisa para traducir
• Corregido: un evento de todo el día podía ocupar dos días
</es-ES>
<it-IT>
• Documenti direttamente nell’app: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF e CSV
• Fogli di calcolo con i loro fogli, presentazioni in diapositive
• Anteprima dei documenti disattivabile del tutto o per tipo
• Intestazioni dei messaggi citati (Da, A, Inviato) e date nella lingua dell’app
• Rilevamento della lingua più preciso per la traduzione
• Corretto: un evento di tutto il giorno poteva occupare due giorni
</it-IT>
<zh-CN>
• 直接在应用内查看文档：DOCX、XLSX、PPTX、ODT、ODS、ODP、RTF 和 CSV
• 表格按工作表显示，演示文稿按幻灯片显示
• 可完全关闭或按类型关闭文档预览
• 引用邮件的标头（发件人、收件人、发送时间）和日期以应用语言显示
• 翻译时更准确地识别语言
• 修复：全天事件可能跨越两天的问题
</zh-CN>
<ko-KR>
• 앱에서 바로 문서 보기: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF, CSV
• 시트가 있는 스프레드시트, 슬라이드로 보는 프레젠테이션
• 문서 미리 보기를 전체 또는 종류별로 끌 수 있음
• 인용된 메일의 머리글(보낸 사람, 받는 사람, 보낸 날짜)과 날짜를 앱 언어로 표시
• 번역을 위한 언어 감지 정확도 향상
• 수정: 종일 일정이 이틀에 걸쳐 표시될 수 있던 문제
</ko-KR>
<nl-NL>
• Documenten direct in de app: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF en CSV
• Spreadsheets met tabbladen, presentaties als dia’s
• Documentvoorbeeld helemaal of per type uit te schakelen
• Kopteksten van geciteerde berichten (Van, Aan, Verzonden) en datums in de taal van de app
• Nauwkeurigere taalherkenning voor vertaling
• Opgelost: een evenement van de hele dag kon twee dagen beslaan
</nl-NL>
<no-NO>
• Dokumenter rett i appen: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF og CSV
• Regneark med faner, presentasjoner som lysbilder
• Forhåndsvisning av dokumenter kan slås av helt eller per type
• Overskrifter i siterte meldinger (Fra, Til, Sendt) og datoer på appens språk
• Mer presis språkgjenkjenning for oversettelse
• Rettet: en heldagshendelse kunne strekke seg over to dager
</no-NO>
<pl-PL>
• Dokumenty bezpośrednio w aplikacji: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF i CSV
• Arkusze z zakładkami, prezentacje jako slajdy
• Podgląd dokumentów można wyłączyć całkowicie lub dla wybranych typów
• Nagłówki cytowanych wiadomości (Od, Do, Wysłano) i daty w języku aplikacji
• Dokładniejsze rozpoznawanie języka do tłumaczenia
• Naprawiono: wydarzenie całodniowe mogło zajmować dwa dni
</pl-PL>
<pt-BR>
• Documentos no próprio app: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF e CSV
• Planilhas com suas abas, apresentações em slides
• Pré-visualização de documentos desativável por completo ou por tipo
• Cabeçalhos de mensagens citadas (De, Para, Enviado) e datas no idioma do app
• Detecção de idioma mais precisa para a tradução
• Corrigido: um evento de dia inteiro podia ocupar dois dias
</pt-BR>
<ro>
• Documente direct în aplicație: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF și CSV
• Foi de calcul cu file, prezentări ca diapozitive
• Previzualizarea documentelor se poate dezactiva complet sau pe tipuri
• Antetele mesajelor citate (De la, Către, Trimis) și datele în limba aplicației
• Detectare mai precisă a limbii pentru traducere
• Corectat: un eveniment de o zi întreagă se putea întinde pe două zile
</ro>
<sk>
• Dokumenty priamo v aplikácii: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF a CSV
• Tabuľky s hárkami, prezentácie ako snímky
• Náhľad dokumentov sa dá vypnúť celý alebo podľa typu
• Hlavičky citovaných správ (Od, Komu, Odoslané) a dátumy v jazyku aplikácie
• Presnejšie rozpoznanie jazyka na preklad
• Opravené: celodenná udalosť sa mohla roztiahnuť na dva dni
</sk>
<th>
• เปิดเอกสารในแอปได้ทันที: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF และ CSV
• สเปรดชีตแสดงพร้อมแผ่นงาน งานนำเสนอแสดงเป็นสไลด์
• ปิดการแสดงตัวอย่างเอกสารได้ทั้งหมดหรือตามประเภท
• ส่วนหัวของข้อความที่อ้างถึง (จาก ถึง ส่งเมื่อ) และวันที่เป็นภาษาของแอป
• ตรวจจับภาษาเพื่อการแปลได้แม่นยำขึ้น
• แก้ไข: กิจกรรมตลอดวันอาจแสดงยาวสองวัน
</th>
<tr-TR>
• Belgeler doğrudan uygulamada: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF ve CSV
• Sayfalarıyla tablolar, slayt olarak sunular
• Belge önizlemesi tamamen veya türe göre kapatılabilir
• Alıntılanan iletilerin üst bilgileri (Kimden, Kime, Gönderildi) ve tarihler uygulamanın dilinde
• Çeviri için daha doğru dil algılama
• Düzeltildi: tüm gün süren bir etkinlik iki güne yayılabiliyordu
</tr-TR>
<fi-FI>
• Asiakirjat suoraan sovelluksessa: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF ja CSV
• Laskentataulukot välilehtineen, esitykset dioina
• Asiakirjojen esikatselun voi poistaa käytöstä kokonaan tai tyypeittäin
• Lainattujen viestien otsikot (Lähettäjä, Vastaanottaja, Lähetetty) ja päivämäärät sovelluksen kielellä
• Tarkempi kielen tunnistus käännöstä varten
• Korjattu: koko päivän tapahtuma saattoi venyä kahdelle päivälle
</fi-FI>
<hi-IN>
• दस्तावेज़ सीधे ऐप में: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF और CSV
• शीट के साथ स्प्रेडशीट, स्लाइड के रूप में प्रस्तुतियाँ
• दस्तावेज़ पूर्वावलोकन पूरी तरह या प्रकार के अनुसार बंद किया जा सकता है
• उद्धृत संदेशों के हेडर (प्रेषक, प्राप्तकर्ता, भेजा गया) और तिथियाँ ऐप की भाषा में
• अनुवाद के लिए भाषा की अधिक सटीक पहचान
• ठीक किया गया: पूरे दिन का इवेंट दो दिनों तक फैल सकता था
</hi-IN>
<cs-CZ>
• Dokumenty přímo v aplikaci: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF a CSV
• Tabulky s listy, prezentace jako snímky
• Náhled dokumentů lze vypnout celý nebo podle typu
• Záhlaví citovaných zpráv (Od, Komu, Odesláno) a data v jazyce aplikace
• Přesnější rozpoznání jazyka pro překlad
• Opraveno: celodenní událost se mohla roztáhnout na dva dny
</cs-CZ>
<sv-SE>
• Dokument direkt i appen: DOCX, XLSX, PPTX, ODT, ODS, ODP, RTF och CSV
• Kalkylblad med flikar, presentationer som bilder
• Förhandsvisning av dokument kan stängas av helt eller per typ
• Rubriker i citerade meddelanden (Från, Till, Skickat) och datum på appens språk
• Säkrare språkigenkänning för översättning
• Åtgärdat: en heldagshändelse kunde sträcka sig över två dagar
</sv-SE>
<ja-JP>
• アプリ内で文書を表示：DOCX・XLSX・PPTX・ODT・ODS・ODP・RTF・CSV
• スプレッドシートはシート付き、プレゼンテーションはスライドで表示
• 文書のプレビューは全体または種類ごとにオフにできます
• 引用メッセージのヘッダー（差出人・宛先・送信日時）と日付をアプリの言語で表示
• 翻訳のための言語判定がより正確に
• 修正：終日の予定が2日間にまたがることがある問題
</ja-JP>
```
