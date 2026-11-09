// lib/services/assignments/assignment_phrases.dart
// Статус поручения по ответу исполнителя (решение владельца 09.11.2026:
// «да, менять сразу, но такие фразы — на всех языках»). Исполнитель может
// ответить из любой почты: «Принято» — поручение в работе, «Готово» — на
// проверке у поручившего. Ответ из Ogneliss Mail несёт и скрытую отметку
// статуса (assignment_codec.dart) — она точнее и главнее слов.
//
// Разбирается только свежая часть ответа (без цитаты), первые 300 знаков.
// Отрицание перед фразой («не готово», «not done», «noch nicht fertig») —
// не считается. «Готово» главнее «Принято»: «Принято, всё сделано» — готово.

/// Что сказал исполнитель.
enum AssignmentSignal { accepted, done }

abstract final class AssignmentPhrases {
  /// «Принято» / взял в работу — по языкам.
  static const accepted = <String, List<String>>{
    'ru': ['принято', 'принял', 'приняла', 'беру в работу', 'взял в работу', 'взяла в работу', 'в работе', 'сделаю', 'займусь'],
    'en': ['accepted', 'on it', 'will do', "i'll do it", 'i will do it', 'got it', 'in progress', 'working on it'],
    'ar': ['تم القبول', 'سأتولى ذلك', 'قيد التنفيذ', 'موافق', 'سأقوم بذلك'],
    'cs': ['přijato', 'beru', 'pracuji na tom', 'postarám se', 'udělám'],
    'da': ['accepteret', 'jeg tager den', 'i gang', 'det klarer jeg', 'det gør jeg'],
    'de': ['angenommen', 'übernehme', 'ich kümmere mich', 'in arbeit', 'mache ich', 'erledige ich'],
    'es': ['aceptado', 'me encargo', 'en curso', 'en ello', 'lo hago', 'de acuerdo, lo hago'],
    'fi': ['hyväksytty', 'hoidan', 'työn alla', 'otan tämän', 'teen sen'],
    'fr': ['accepté', "je m'en occupe", 'en cours', 'je prends', 'je le fais'],
    'he': ['התקבל', 'אני על זה', 'בטיפול', 'מקבל', 'מקבלת'],
    'hi': ['स्वीकार', 'मैं कर दूँगा', 'मैं कर दूंगी', 'काम चल रहा है', 'ठीक है, करता हूँ'],
    'hu': ['elfogadva', 'intézem', 'folyamatban', 'vállalom', 'megcsinálom'],
    'id': ['diterima', 'saya kerjakan', 'sedang dikerjakan', 'siap', 'akan saya kerjakan'],
    'it': ['accettato', 'me ne occupo', 'in corso', 'ci penso io', 'lo faccio'],
    'ja': ['承知しました', '了解しました', '対応します', '対応中', '引き受けます', '承りました'],
    'ko': ['확인했습니다', '접수했습니다', '진행하겠습니다', '진행 중', '맡겠습니다'],
    'nb': ['akseptert', 'jeg tar den', 'i gang', 'fikser det', 'det gjør jeg'],
    'nl': ['geaccepteerd', 'ik pak het op', 'mee bezig', 'komt goed', 'ik doe het'],
    'pl': ['przyjęte', 'przyjąłem', 'przyjęłam', 'zajmę się', 'w trakcie', 'biorę'],
    'pt': ['aceito', 'aceite', 'vou fazer', 'em andamento', 'deixa comigo', 'em curso'],
    'ro': ['acceptat', 'mă ocup', 'în lucru', 'preiau', 'o fac'],
    'sk': ['prijaté', 'beriem', 'pracujem na tom', 'postarám sa', 'urobím'],
    'sv': ['accepterat', 'jag tar det', 'på gång', 'fixar det', 'jag gör det'],
    'th': ['รับทราบ', 'รับงาน', 'กำลังทำ', 'จะทำให้', 'รับเรื่อง'],
    'tr': ['kabul edildi', 'ilgileniyorum', 'üzerinde çalışıyorum', 'hallederim', 'tamam'],
    'vi': ['đã nhận', 'tôi sẽ làm', 'đang làm', 'nhận việc', 'đã tiếp nhận'],
    'zh': ['收到', '已接受', '我来处理', '处理中', '好的'],
  };

  /// «Готово» / сделано — по языкам.
  static const done = <String, List<String>>{
    'ru': ['готово', 'сделано', 'выполнено', 'исполнено', 'сделал', 'сделала', 'выполнил', 'выполнила'],
    'en': ['done', 'completed', 'finished', "it's done", 'all done'],
    'ar': ['تم التنفيذ', 'أنجزت', 'اكتمل', 'تم الانتهاء', 'جاهز'],
    'cs': ['hotovo', 'splněno', 'dokončeno', 'uděláno'],
    'da': ['færdig', 'klaret', 'udført', 'gjort'],
    'de': ['erledigt', 'fertig', 'abgeschlossen', 'gemacht'],
    'es': ['hecho', 'listo', 'terminado', 'completado'],
    'fi': ['valmis', 'tehty', 'hoidettu', 'suoritettu'],
    'fr': ["c'est fait", 'terminé', 'réalisé', 'fini'],
    'he': ['בוצע', 'מוכן', 'הושלם', 'סיימתי'],
    'hi': ['हो गया', 'पूरा हुआ', 'कर दिया', 'समाप्त'],
    'hu': ['kész', 'elkészült', 'megcsinálva', 'teljesítve'],
    'id': ['selesai', 'sudah beres', 'beres', 'tuntas'],
    'it': ['fatto', 'completato', 'finito', 'terminato'],
    'ja': ['完了しました', '完了', '終わりました', '対応済み'],
    'ko': ['완료했습니다', '완료', '끝났습니다', '처리했습니다'],
    'nb': ['ferdig', 'gjort', 'utført', 'fullført'],
    'nl': ['klaar', 'gedaan', 'afgerond', 'voltooid'],
    'pl': ['gotowe', 'zrobione', 'wykonane', 'zakończone'],
    'pt': ['feito', 'pronto', 'concluído', 'finalizado'],
    'ro': ['gata', 'făcut', 'finalizat', 'terminat'],
    'sk': ['hotovo', 'splnené', 'dokončené', 'urobené'],
    'sv': ['klart', 'gjort', 'färdigt', 'slutfört'],
    'th': ['เสร็จแล้ว', 'เรียบร้อย', 'ทำแล้ว', 'เสร็จสิ้น'],
    'tr': ['yapıldı', 'tamamlandı', 'bitti', 'hazır'],
    'vi': ['đã xong', 'xong', 'hoàn thành', 'đã làm xong'],
    'zh': ['已完成', '完成', '搞定', '做好了'],
  };

  /// Отрицания перед фразой («не готово», «not done», «noch nicht»).
  static const _negations = <String>{
    'не', 'ещё не', 'еще не', 'нет', 'not', "isn't", "aren't", "haven't", 'not yet', 'no', 'nicht', 'kein',
    'noch nicht', 'pas', 'non', 'não', 'nie', 'ne', 'niet', 'inte', 'ej', 'ikke', 'ei', 'nem', 'nu', 'değil',
    'لم', 'لا', 'ليس', 'לא', 'नहीं', 'belum', 'tidak', 'chưa', 'không', 'ยังไม่', 'ไม่', 'まだ', '未', '没', '没有',
    '不', '안', '못', 'henüz',
  };

  /// Будущее и долженствование перед фразой («will be done», «будет
  /// готово», «needs to be done») — ещё не сделано.
  static const _future = <String>{
    'be', 'will', 'to', 'get', 'should', 'must', 'would', 'can', 'could', 'need', 'needs', 'будет', 'будут',
    'должно', 'должна', 'должен', 'нужно', 'надо', 'wird', 'werden', 'muss', 'sera', 'doit', 'será', 'debe',
    'sarà', 'deve', 'będzie', 'bude', 'zal', 'moet', 'blir', 'ska', 'skal', 'bliver', 'tulee', 'lesz', 'va', 'olacak',
  };

  /// Языки без пробелов между словами: фраза ищется подстрокой.
  static const _noSpaces = {'ja', 'zh', 'th'};

  static final _wordChar = RegExp(r"[\p{L}\p{N}'’]", unicode: true);

  /// Что сказано в свежей части ответа [text]; null — ни «Принято», ни
  /// «Готово» (вопрос, уточнение — только в историю).
  static AssignmentSignal? classify(String text) {
    var t = text.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    if (t.length > 300) t = t.substring(0, 300);
    if (_found(t, done)) return AssignmentSignal.done;
    if (_found(t, accepted)) return AssignmentSignal.accepted;
    return null;
  }

  static bool _found(String t, Map<String, List<String>> dict) {
    for (final e in dict.entries) {
      final cjk = _noSpaces.contains(e.key);
      for (final p in e.value) {
        var from = 0;
        while (true) {
          final i = t.indexOf(p, from);
          if (i < 0) break;
          from = i + 1;
          final end = i + p.length;
          if (!cjk) {
            // Целым словом: «сделано», но не «переделано»; «done», но не «abandoned».
            if (i > 0 && _wordChar.hasMatch(t[i - 1])) continue;
            if (end < t.length && _wordChar.hasMatch(t[end])) continue;
          }
          if (_negated(t, i, cjk)) continue;
          // Вопрос («is it done?») — не ответ о статусе.
          final stop = t.indexOf(RegExp(r'[.!?。！？]'), end);
          if (stop >= 0 && (t[stop] == '?' || t[stop] == '？')) continue;
          return true;
        }
      }
    }
    return false;
  }

  /// Перед фразой (до двух слов назад, а в языках без пробелов — до трёх
  /// знаков) стоит отрицание.
  static bool _negated(String t, int at, bool cjk) {
    if (cjk) {
      final before = t.substring(at < 3 ? 0 : at - 3, at);
      return _negations.any((n) => n.length <= 2 && before.contains(n));
    }
    final words = t.substring(0, at).trim().split(RegExp(r'[\s,.;:!?()«»\x22]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return false;
    final last = words.last;
    final two = words.length >= 2 ? '${words[words.length - 2]} $last' : last;
    return _negations.contains(last) || _negations.contains(two) || _future.contains(last);
  }
}
