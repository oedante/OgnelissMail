# «Что нового» — 2.6.1 (159), относительно 2.6.0

2.6.0 ушла тестировщикам; 2.6.1 — исправления по журналам с форума
(Samsung S24 и realme, 16.11.2026). Тексты ниже — для тестировщиков и
страницы выпуска на GitHub. Если 2.6.1 — первая сборка после 2.6.0,
которая уходит в магазин, возьмите тексты магазинов из
`STORE_NOTES_2.6.0.md` (их последняя строка «Исправления и улучшения»
покрывает и эти). Шаги владельца — `OWNER_STEPS_2.6.1.md`.

## Сделано в 2.6.1

- **Android: вылет при первом открытии после простоя.** Система выгружает
  свёрнутое приложение из памяти, а окно оставляет в недавних с
  сохранённым состоянием. При открытии восстановленное окно искало движок
  Flutter раньше, чем приложение его создавало, — сбой; следующий запуск
  уже работал. Теперь движок создаётся первым. Ошибка была с 07.10.2026
  (движок, который живёт дольше окна).
- **Синхронизация не останавливается на одном письме.** Почтовая
  библиотека (enough_mail 2.1.7) не разбирала структуру некоторых писем
  Mail.ru и Яндекса (RangeError в BODYSTRUCTURE): ответ сервера оставался
  недочитанным, и проверка папки ждала 5 минут на каждом проходе. Теперь
  сбой одной строки ответа не останавливает остальные: такое письмо
  загружается без структуры, открытое — целиком, вложения — из самого
  письма. Библиотека не изменена (подкласс клиента).
- **Без ложного «Требуется вход».** Обрыв связи или тайм-аут при входе в
  ящик OAuth больше не считается отказом сервера и не обновляет токен
  принудительно. Яндекс при входе напрямую (с 2.2.1, без сервера входа)
  обновление токена без секрета клиента не принимает, и ящик с
  действующим токеном мог получить «Требуется вход».
- **Логотипы отправителей (BIMI) у ящиков Яндекса, Mail.ru и iCloud.**
  Логотип показывается, только если сервер ящика подтвердил, что письмо
  действительно от домена отправителя (DMARC). Приложение ждало строку
  «dmarc=pass», а Яндекс и Mail.ru её не пишут (только SPF и DKIM), Яндекс
  подписывает заголовок именем сервера без домена, а iCloud пишет
  результаты отдельными заголовками — у всех трёх в диагностике было
  «доменов с подписью DMARC: 0», и сервер логотипов ни разу не
  спрашивался. Теперь DMARC засчитывается по пройденной проверке DKIM или
  SPF для домена из From (так он и определён, RFC 7489), заголовки iCloud
  читаются все. Рабочая почта Exchange логотипы на сервере Ogneliss больше
  не ищет (правило: с рабочей почтой серверы Ogneliss не используются).
  Логотип по-прежнему есть только у тех компаний, что опубликовали запись
  BIMI.
- **Причина сбоя Android — в журнале.** Для сбоя в Java система сообщает
  только «crash». Теперь приложение записывает исключение и верхние строки
  стека (только код) и при следующем запуске выводит «Сбой (Java): …».

## Кратко (RU / EN)

**RU.** Android: приложение больше не закрывается при первом открытии после
простоя. Синхронизация не останавливается на письме, которое не удалось
разобрать. Обрыв связи больше не приводит к ложному «Требуется вход».

**EN.** Android: the app no longer closes on first launch after being idle.
Sync no longer stalls on an email it cannot parse. A dropped connection no
longer causes a false "Sign-in required".

## App Store — iPhone, iPad и Mac (ru, en, de, fr)

```
<ru-RU>
• Синхронизация не останавливается на письме, которое не удалось разобрать (Mail.ru, Яндекс)
• Обрыв связи больше не приводит к ложному «Требуется вход»
</ru-RU>
<en-US>
• Sync no longer stalls on an email it cannot parse (Mail.ru, Yandex)
• A dropped connection no longer causes a false "Sign-in required"
</en-US>
<de-DE>
• Die Synchronisierung bleibt nicht mehr bei einer nicht lesbaren E-Mail hängen (Mail.ru, Yandex)
• Ein Verbindungsabbruch führt nicht mehr fälschlich zu „Anmeldung erforderlich“
</de-DE>
<fr-FR>
• La synchronisation ne bloque plus sur un e-mail illisible (Mail.ru, Yandex)
• Une coupure de connexion n’affiche plus à tort « Connexion requise »
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Приложение больше не закрывается при первом открытии после простоя
• Синхронизация не останавливается на письме, которое не удалось разобрать (Mail.ru, Яндекс)
• Обрыв связи больше не приводит к ложному «Требуется вход»
</ru-RU>
<en-US>
• The app no longer closes on first launch after being idle
• Sync no longer stalls on an email it cannot parse (Mail.ru, Yandex)
• A dropped connection no longer causes a false "Sign-in required"
</en-US>
<de-DE>
• Die App schließt sich nach längerer Pause beim ersten Öffnen nicht mehr
• Die Synchronisierung bleibt nicht mehr bei einer nicht lesbaren E-Mail hängen (Mail.ru, Yandex)
• Ein Verbindungsabbruch führt nicht mehr fälschlich zu „Anmeldung erforderlich“
</de-DE>
<fr-FR>
• L’application ne se ferme plus à la première ouverture après une longue inactivité
• La synchronisation ne bloque plus sur un e-mail illisible (Mail.ru, Yandex)
• Une coupure de connexion n’affiche plus à tort « Connexion requise »
</fr-FR>
<ar>
• لم يعد التطبيق يُغلق عند فتحه لأول مرة بعد فترة خمول
• لم تعد المزامنة تتوقف عند رسالة تعذّرت قراءتها (Mail.ru وYandex)
• لم يعد انقطاع الاتصال يُظهر خطأً «يلزم تسجيل الدخول»
</ar>
<hu-HU>
• Az alkalmazás már nem záródik be az első megnyitáskor hosszabb tétlenség után
• A szinkronizálás már nem akad el egy nem értelmezhető levélen (Mail.ru, Yandex)
• A kapcsolat megszakadása már nem okoz téves „Bejelentkezés szükséges” üzenetet
</hu-HU>
<vi>
• Ứng dụng không còn tự đóng khi mở lần đầu sau thời gian không dùng
• Đồng bộ không còn bị kẹt ở email không đọc được (Mail.ru, Yandex)
• Mất kết nối không còn gây báo nhầm “Cần đăng nhập”
</vi>
<da-DK>
• Appen lukker ikke længere ved første åbning efter længere tids inaktivitet
• Synkroniseringen går ikke længere i stå ved en e-mail, der ikke kan læses (Mail.ru, Yandex)
• En afbrudt forbindelse giver ikke længere et fejlagtigt "Login påkrævet"
</da-DK>
<iw-IL>
• האפליקציה כבר לא נסגרת בפתיחה הראשונה אחרי זמן ללא שימוש
• הסנכרון כבר לא נתקע בהודעה שלא ניתן לקרוא (Mail.ru, Yandex)
• ניתוק בחיבור כבר לא גורם להודעה שגויה "נדרשת התחברות"
</iw-IL>
<id>
• Aplikasi tidak lagi tertutup saat dibuka pertama kali setelah lama tidak dipakai
• Sinkronisasi tidak lagi macet pada email yang tidak dapat dibaca (Mail.ru, Yandex)
• Koneksi terputus tidak lagi memunculkan "Perlu masuk" yang keliru
</id>
<es-ES>
• La aplicación ya no se cierra al abrirla por primera vez tras un tiempo inactiva
• La sincronización ya no se detiene en un correo que no se puede leer (Mail.ru, Yandex)
• Un corte de conexión ya no provoca un falso «Inicio de sesión necesario»
</es-ES>
<it-IT>
• L’app non si chiude più alla prima apertura dopo un periodo di inattività
• La sincronizzazione non si blocca più su un’email illeggibile (Mail.ru, Yandex)
• Un’interruzione di rete non causa più un falso «Accesso richiesto»
</it-IT>
<zh-CN>
• 长时间未使用后首次打开不再闪退
• 同步不再卡在无法解析的邮件上（Mail.ru、Yandex）
• 网络中断不再误报“需要登录”
</zh-CN>
<ko-KR>
• 오래 사용하지 않은 뒤 처음 열 때 앱이 더 이상 종료되지 않습니다
• 읽을 수 없는 이메일 때문에 동기화가 멈추지 않습니다 (Mail.ru, Yandex)
• 연결이 끊겨도 더 이상 '로그인 필요'가 잘못 표시되지 않습니다
</ko-KR>
<nl-NL>
• De app sluit niet meer bij de eerste keer openen na een periode van inactiviteit
• Synchronisatie loopt niet meer vast op een e-mail die niet gelezen kan worden (Mail.ru, Yandex)
• Een verbroken verbinding geeft niet meer ten onrechte "Aanmelden vereist"
</nl-NL>
<no-NO>
• Appen lukkes ikke lenger ved første åpning etter lengre tids inaktivitet
• Synkroniseringen stopper ikke lenger på en e-post som ikke kan leses (Mail.ru, Yandex)
• Et brudd i tilkoblingen gir ikke lenger feilaktig «Pålogging kreves»
</no-NO>
<pl-PL>
• Aplikacja nie zamyka się już przy pierwszym otwarciu po dłuższej bezczynności
• Synchronizacja nie zatrzymuje się już na wiadomości, której nie da się odczytać (Mail.ru, Yandex)
• Zerwane połączenie nie powoduje już błędnego „Wymagane logowanie”
</pl-PL>
<pt-BR>
• O app não fecha mais ao abrir pela primeira vez após um período inativo
• A sincronização não trava mais em um e-mail que não pode ser lido (Mail.ru, Yandex)
• Uma queda de conexão não mostra mais um falso "Login necessário"
</pt-BR>
<ro>
• Aplicația nu se mai închide la prima deschidere după o perioadă de inactivitate
• Sincronizarea nu se mai blochează la un e-mail care nu poate fi citit (Mail.ru, Yandex)
• O întrerupere a conexiunii nu mai afișează greșit „Este necesară autentificarea”
</ro>
<sk>
• Aplikácia sa už nezatvára pri prvom otvorení po dlhšej nečinnosti
• Synchronizácia sa už nezasekne na e-maile, ktorý sa nedá prečítať (Mail.ru, Yandex)
• Výpadok pripojenia už nespôsobí chybné „Vyžaduje sa prihlásenie“
</sk>
<th>
• แอปไม่ปิดเองอีกต่อไปเมื่อเปิดครั้งแรกหลังจากไม่ได้ใช้งานนาน
• การซิงค์ไม่ค้างที่อีเมลที่อ่านไม่ได้อีกต่อไป (Mail.ru, Yandex)
• การเชื่อมต่อหลุดจะไม่แสดง "ต้องลงชื่อเข้าใช้" ผิดพลาดอีกต่อไป
</th>
<tr-TR>
• Uygulama uzun süre kullanılmadıktan sonra ilk açılışta artık kapanmıyor
• Eşitleme artık okunamayan bir e-postada takılmıyor (Mail.ru, Yandex)
• Bağlantı kopması artık yanlışlıkla "Oturum açılması gerekiyor" göstermiyor
</tr-TR>
<fi-FI>
• Sovellus ei enää sulkeudu ensimmäisellä avauskerralla pitkän käyttämättömyyden jälkeen
• Synkronointi ei enää jumitu viestiin, jota ei voi lukea (Mail.ru, Yandex)
• Katkennut yhteys ei enää aiheuta virheellistä ”Kirjautuminen vaaditaan” -ilmoitusta
</fi-FI>
<hi-IN>
• लंबे समय तक इस्तेमाल न होने के बाद पहली बार खोलने पर ऐप अब बंद नहीं होता
• पढ़े न जा सकने वाले ईमेल पर सिंक अब नहीं अटकता (Mail.ru, Yandex)
• कनेक्शन टूटने पर अब गलती से "साइन-इन ज़रूरी" नहीं दिखता
</hi-IN>
<cs-CZ>
• Aplikace se už nezavírá při prvním otevření po delší nečinnosti
• Synchronizace se už nezasekne na e-mailu, který nejde přečíst (Mail.ru, Yandex)
• Výpadek připojení už nezpůsobí chybné „Vyžaduje se přihlášení“
</cs-CZ>
<sv-SE>
• Appen stängs inte längre vid första öppningen efter en tids inaktivitet
• Synkroniseringen fastnar inte längre på ett mejl som inte kan läsas (Mail.ru, Yandex)
• Ett avbrott i anslutningen ger inte längre felaktigt ”Inloggning krävs”
</sv-SE>
<ja-JP>
• しばらく使わなかった後の初回起動でアプリが終了しなくなりました
• 解析できないメールで同期が止まらなくなりました（Mail.ru、Yandex）
• 接続が切れても「サインインが必要」と誤って表示されなくなりました
</ja-JP>
```
