// lib/core/utils/subject_prefix.dart
// Префикс темы при ответе и пересылке (1.5.12, замечание 12.10.2026).
//
// Раньше к теме дописывалось «Re: » или «Fwd: », если тема не начиналась
// ровно с него же: ответ на «RE: …» становился «Re: RE: …», пересылка —
// «Fwd: RE: …», и с каждым кругом переписки префиксы росли. Теперь, как
// договорились, префикс один и в написании Outlook: «RE: » при ответе,
// «FW: » при пересылке. Все прежние префиксы в начале темы — английские,
// русские, немецкие и другие, со счётчиками («Re[2]:», «RE(3):»), любым
// регистром и в любом количестве — убираются.

class SubjectPrefix {
  SubjectPrefix._();

  /// Префиксы ответа и пересылки разных почтовых программ и языков.
  static final _prefixes = RegExp(
    r'^\s*(?:(?:re|fw|fwd|aw|wg|sv|vs|tr|rv|res|enc|antw|doorst|vb|odp|ynt|ilt|отв|ответ|пер|пересл|переслать|пересылка|переслано)'
    r'\s*(?:\[\d+\]|\(\d+\))?\s*[:：]\s*)+',
    caseSensitive: false,
    unicode: true,
  );

  /// Тема без префиксов ответа и пересылки в начале.
  static String strip(String subject) => subject.replaceFirst(_prefixes, '').trim();

  /// Тема ответа: «RE: тема».
  static String reply(String subject) => 'RE: ${strip(subject)}';

  /// Тема пересылки: «FW: тема».
  static String forward(String subject) => 'FW: ${strip(subject)}';
}
