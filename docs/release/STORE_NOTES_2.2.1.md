# «Что нового» — 2.2.1 (147)

Номер — просьба владельца 10.11.2026 («подними версию»; 2.2.0 собрана и
стоит на телефоне владельца). Ниже — только изменения после сборки 2.2.0;
всё прежнее — `STORE_NOTES_2.2.0.md`. Тексты для магазинов — в конце (App
Store — ru, en, de, fr; Google Play — 27 языков).

## Сделано (10.11.2026, по журналу владельца 15:22 и снимкам)

- **Свайпы — результат внизу, как при удалении** (замечание владельца:
  «не нравится, как при свайпе зависает информация о выполненном действии.
  При удалении нормально работает»): после «Прочитано», «Флаг», «На
  контроль» (свайпом или кнопкой, в ленте и в беседе) — строка внизу
  «Прочитано · Вернуть» с отсчётом, та же, что «Письмо удалено · Вернуть».
  Плашки поверх самой строки больше нет.
- **Превью без «[image: Google]»** (снимок владельца): Gmail и Outlook
  пишут картинки в текстовой части письма пометками «[image: …]»,
  «[cid:…]», «[image001.png]» — в ленте и в уведомлении их больше нет (и у
  уже загруженных писем). В самом письме текст — как есть.
- **Фоновая проверка после сна телефона быстрее**: соединение IMAP,
  простоявшее больше 10 минут, сразу открывается заново, а не проверяется с
  ожиданием до 10 секунд на ящик (в журнале — 30–55 с лишних на проверку
  при трёх-четырёх ящиках IMAP).
- **Отмена входа — не ошибка**: закрыли окно входа Google, Microsoft,
  Яндекса («назад», крестик) — ничего не показывается (раньше —
  «PlatformException(CANCELED…)» строкой ошибки), и при «Войти снова» тоже.
- **Сборка**: без ложного «[SEVERE] RustBuilder: Failed to find lib.name» в
  `flutter test` и сборке (копия native_toolchain_rust 1.0.6 с исправлением
  из 1.0.7, `packages/native_toolchain_rust`).

Проверено по журналу 10.11 15:22: вход без сервера — Google, Яндекс
(почта, календарь, контакты) и Microsoft — работает; сигналы сервера
приходят раз в 15 минут.

Зависимости: новых нет. Платформы: `project.pbxproj`, `Runner.entitlements`,
`Info.plist` и манифест Android не менялись.

## App Store — iPhone и iPad (ru, en, de, fr)

```
<ru-RU>
• После свайпа «Прочитано», «Флаг», «На контроль» — подсказка с «Вернуть» внизу, как при удалении
• Превью и уведомления — без пометок «[image: …]»
• Фоновая проверка почты быстрее после сна телефона
• Отмена входа больше не показывается как ошибка
</ru-RU>
<en-US>
• After swiping Read, Flag or Follow-up, a bottom bar with Undo appears, just like after deleting
• Previews and notifications no longer show “[image: …]” tags
• Faster background mail checks after the phone wakes up
• Cancelling sign-in is no longer shown as an error
</en-US>
<de-DE>
• Nach dem Wischen für „Gelesen“, „Markierung“ oder „Nachverfolgen“ erscheint unten eine Leiste mit „Rückgängig“ – wie beim Löschen
• Vorschau und Benachrichtigungen ohne „[image: …]“-Marken
• Schnellere Mailprüfung im Hintergrund, wenn das Telefon aufwacht
• Abgebrochene Anmeldung wird nicht mehr als Fehler angezeigt
</de-DE>
<fr-FR>
• Après un balayage « Lu », « Drapeau » ou « Suivi », une barre « Annuler » s’affiche en bas, comme après une suppression
• Aperçus et notifications sans balises « [image: …] »
• Vérification en arrière-plan plus rapide au réveil du téléphone
• L’annulation de la connexion n’est plus affichée comme une erreur
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

Предел Google Play — 500 знаков на язык; здесь каждый язык не длиннее 450.

```
<ru-RU>
• После свайпа «Прочитано», «Флаг», «На контроль» — подсказка с «Вернуть» внизу, как при удалении
• Превью и уведомления — без пометок «[image: …]»
• Фоновая проверка почты быстрее после сна телефона
• Отмена входа больше не показывается как ошибка
</ru-RU>
<en-US>
• After swiping Read, Flag or Follow-up, a bottom bar with Undo appears, just like after deleting
• Previews and notifications no longer show “[image: …]” tags
• Faster background mail checks after the phone wakes up
• Cancelling sign-in is no longer shown as an error
</en-US>
<de-DE>
• Nach dem Wischen für „Gelesen“, „Markierung“ oder „Nachverfolgen“ erscheint unten eine Leiste mit „Rückgängig“ – wie beim Löschen
• Vorschau und Benachrichtigungen ohne „[image: …]“-Marken
• Schnellere Mailprüfung im Hintergrund, wenn das Telefon aufwacht
• Abgebrochene Anmeldung wird nicht mehr als Fehler angezeigt
</de-DE>
<fr-FR>
• Après un balayage « Lu », « Drapeau » ou « Suivi », une barre « Annuler » s’affiche en bas, comme après une suppression
• Aperçus et notifications sans balises « [image: …] »
• Vérification en arrière-plan plus rapide au réveil du téléphone
• L’annulation de la connexion n’est plus affichée comme une erreur
</fr-FR>
<ar>
• بعد السحب لـ«مقروء» أو «علامة» أو «متابعة» يظهر شريط سفلي مع «تراجع» كما بعد الحذف
• المعاينة والإشعارات من دون وسوم «[image: …]»
• فحص البريد في الخلفية أسرع بعد استيقاظ الهاتف
• إلغاء تسجيل الدخول لم يعد يُعرض كخطأ
</ar>
<hu-HU>
• Olvasott, Jelölő vagy Követés húzás után alul „Visszavonás” sáv jelenik meg, mint törléskor
• Előnézet és értesítések „[image: …]” jelölések nélkül
• Gyorsabb háttér-ellenőrzés, amikor a telefon felébred
• A bejelentkezés megszakítása már nem jelenik meg hibaként
</hu-HU>
<vi>
• Sau khi vuốt Đã đọc, Gắn cờ hoặc Theo dõi, thanh Hoàn tác hiện ở dưới như khi xóa
• Bản xem trước và thông báo không còn nhãn “[image: …]”
• Kiểm tra thư nền nhanh hơn khi điện thoại thức dậy
• Hủy đăng nhập không còn hiển thị như lỗi
</vi>
<da-DK>
• Efter swipe for Læst, Flag eller Opfølgning vises en bjælke med Fortryd nederst – som ved sletning
• Forhåndsvisning og notifikationer uden “[image: …]”-mærker
• Hurtigere tjek af mail i baggrunden, når telefonen vågner
• Annulleret login vises ikke længere som en fejl
</da-DK>
<iw-IL>
• אחרי החלקה ל„נקרא”, „סימון” או „מעקב” מופיע למטה סרגל עם „ביטול”, כמו אחרי מחיקה
• תצוגה מקדימה והתראות בלי תגיות „[image: …]”
• בדיקת דואר ברקע מהירה יותר כשהטלפון מתעורר
• ביטול התחברות כבר לא מוצג כשגיאה
</iw-IL>
<id>
• Setelah geser Dibaca, Bendera, atau Pantau, bilah Urungkan muncul di bawah seperti saat menghapus
• Pratinjau dan notifikasi tanpa tanda “[image: …]”
• Pemeriksaan email di latar lebih cepat saat ponsel aktif kembali
• Membatalkan login tidak lagi ditampilkan sebagai kesalahan
</id>
<es-ES>
• Tras deslizar Leído, Marca o Seguimiento aparece abajo una barra con Deshacer, como al eliminar
• Vistas previas y notificaciones sin etiquetas «[image: …]»
• Comprobación del correo en segundo plano más rápida al activarse el teléfono
• Cancelar el inicio de sesión ya no se muestra como error
</es-ES>
<it-IT>
• Dopo lo scorrimento Letto, Contrassegno o Controllo compare in basso una barra Annulla, come dopo l’eliminazione
• Anteprime e notifiche senza tag «[image: …]»
• Controllo della posta in background più rapido al risveglio del telefono
• L’annullamento dell’accesso non viene più mostrato come errore
</it-IT>
<zh-CN>
• 滑动“已读”“旗标”“跟进”后，底部会出现“撤销”栏，与删除时相同
• 预览和通知不再显示“[image: …]”标记
• 手机唤醒后后台检查邮件更快
• 取消登录不再显示为错误
</zh-CN>
<ko-KR>
• 읽음, 플래그, 후속 조치로 스와이프하면 삭제할 때처럼 아래에 실행 취소 바가 나타납니다
• 미리보기와 알림에 “[image: …]” 표시가 더 이상 없습니다
• 휴대폰이 깨어날 때 백그라운드 메일 확인이 더 빨라졌습니다
• 로그인 취소가 더 이상 오류로 표시되지 않습니다
</ko-KR>
<nl-NL>
• Na vegen voor Gelezen, Vlag of Opvolgen verschijnt onderaan een balk met Ongedaan maken, net als bij verwijderen
• Voorbeelden en meldingen zonder ‘[image: …]’-labels
• Snellere mailcontrole op de achtergrond als de telefoon ontwaakt
• Geannuleerd inloggen wordt niet meer als fout getoond
</nl-NL>
<no-NO>
• Etter sveip for Lest, Flagg eller Oppfølging vises en linje med Angre nederst – som ved sletting
• Forhåndsvisning og varsler uten «[image: …]»-merker
• Raskere sjekk av e-post i bakgrunnen når telefonen våkner
• Avbrutt pålogging vises ikke lenger som en feil
</no-NO>
<pl-PL>
• Po przesunięciu „Przeczytane”, „Flaga” lub „Kontrola” na dole pojawia się pasek „Cofnij”, jak przy usuwaniu
• Podglądy i powiadomienia bez znaczników „[image: …]”
• Szybsze sprawdzanie poczty w tle po wybudzeniu telefonu
• Anulowanie logowania nie jest już pokazywane jako błąd
</pl-PL>
<pt-BR>
• Depois de deslizar Lido, Sinalizar ou Acompanhar, aparece embaixo uma barra Desfazer, como ao excluir
• Prévias e notificações sem as marcas “[image: …]”
• Verificação de e-mails em segundo plano mais rápida quando o celular acorda
• Cancelar o login não aparece mais como erro
</pt-BR>
<ro>
• După glisarea Citit, Semnalizare sau Urmărire apare jos o bară Anulează, ca la ștergere
• Previzualizări și notificări fără etichete „[image: …]”
• Verificare mai rapidă a e-mailului în fundal la trezirea telefonului
• Anularea autentificării nu mai apare ca eroare
</ro>
<sk>
• Po potiahnutí Prečítané, Príznak alebo Sledovať sa dole zobrazí lišta Späť, ako pri odstránení
• Náhľady a upozornenia bez značiek „[image: …]“
• Rýchlejšia kontrola pošty na pozadí po prebudení telefónu
• Zrušené prihlásenie sa už nezobrazuje ako chyba
</sk>
<th>
• หลังปัดเพื่อ อ่านแล้ว ติดธง หรือ ติดตาม จะมีแถบ เลิกทำ ด้านล่างเหมือนตอนลบ
• ตัวอย่างและการแจ้งเตือนไม่มีแท็ก “[image: …]” อีก
• ตรวจอีเมลเบื้องหลังเร็วขึ้นเมื่อโทรศัพท์ตื่น
• การยกเลิกเข้าสู่ระบบไม่แสดงเป็นข้อผิดพลาดอีก
</th>
<tr-TR>
• Okundu, Bayrak veya Takip kaydırmasından sonra, silmede olduğu gibi altta Geri al çubuğu çıkar
• Önizleme ve bildirimlerde artık “[image: …]” etiketi yok
• Telefon uyandığında arka planda posta denetimi daha hızlı
• Oturum açmayı iptal etmek artık hata olarak gösterilmiyor
</tr-TR>
<fi-FI>
• Kun pyyhkäiset Luettu, Lippu tai Seuranta, alas tulee Kumoa-palkki kuten poistossa
• Esikatselut ja ilmoitukset ilman ”[image: …]”-merkintöjä
• Nopeampi taustatarkistus, kun puhelin herää
• Kirjautumisen peruminen ei enää näy virheenä
</fi-FI>
<hi-IN>
• पढ़ा गया, फ़्लैग या फ़ॉलो-अप स्वाइप के बाद नीचे “पूर्ववत करें” पट्टी आती है, जैसे हटाने पर
• प्रीव्यू और सूचनाओं में अब “[image: …]” टैग नहीं
• फ़ोन जागने पर बैकग्राउंड में मेल जाँच तेज़
• लॉगिन रद्द करना अब त्रुटि के रूप में नहीं दिखता
</hi-IN>
<cs-CZ>
• Po potažení Přečteno, Příznak nebo Sledovat se dole zobrazí lišta Zpět, jako při smazání
• Náhledy a oznámení bez značek „[image: …]“
• Rychlejší kontrola pošty na pozadí po probuzení telefonu
• Zrušené přihlášení se už nezobrazuje jako chyba
</cs-CZ>
<sv-SE>
• Efter svep för Läst, Flagga eller Uppföljning visas ett fält med Ångra längst ned – som vid borttagning
• Förhandsvisningar och aviseringar utan ”[image: …]”-märken
• Snabbare kontroll av e-post i bakgrunden när telefonen vaknar
• Avbruten inloggning visas inte längre som ett fel
</sv-SE>
<ja-JP>
• 「既読」「フラグ」「フォロー」のスワイプ後、削除時と同じく下に「元に戻す」バーを表示
• プレビューと通知に「[image: …]」が表示されなくなりました
• スマホの復帰後、バックグラウンドのメール確認が高速に
• ログインのキャンセルがエラーとして表示されなくなりました
</ja-JP>
```
