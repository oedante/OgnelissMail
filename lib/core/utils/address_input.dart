// lib/core/utils/address_input.dart
// Адреса, набранные или вставленные в поле «Кому» (1.8.13).
//
// Раньше строка делилась по запятым и пробелам, и любой кусок с «@»
// становился адресатом: «Иванов <ivan@corp.ru>» из адресной строки Outlook
// давал адресата «<ivan@corp.ru>» с угловыми скобками, «ivan@» — адресата
// без домена, «IVAN@corp.ru» и «ivan@corp.ru» — двух адресатов. Письмо
// уходило с ошибкой сервера или возвращалось недоставленным.
// Теперь: «Имя <адрес>», «"Фамилия, Имя" <адрес>», «mailto:адрес» и просто
// адреса через запятую, точку с запятой, пробел или перевод строки; что не
// адрес — остаётся в поле, чтобы его исправили.

import '../../data/models/email_model.dart' show EmailAddress;

class AddressInput {
  AddressInput._();

  /// «Имя <адрес>» (имя — в кавычках или без) или адрес без имени.
  static final _token = RegExp(
    r'(?:"([^"]*)"|([^",;<>\n]*?))\s*<\s*(?:mailto:)?([^<>\s]+)\s*>'
    r'|(?:mailto:)?([^\s,;<>"]+@[^\s,;<>"]+)',
    caseSensitive: false,
  );

  /// Адрес: имя@домен, без пробелов и служебных знаков, домен не
  /// начинается и не кончается точкой.
  static final _valid = RegExp(
    r'''^[^\s@<>()\[\],;:"\\]+@[^\s@<>()\[\],;:"\\.]+(\.[^\s@<>()\[\],;:"\\.]+)*$''',
  );

  static bool isValid(String email) => _valid.hasMatch(email.trim());

  /// Разобрать строку. [addresses] — правильные адреса (по одному разу, без
  /// учёта регистра); [rest] — то, что адресом не стало (вернуть в поле).
  static ({List<EmailAddress> addresses, String rest}) parse(String text) {
    final out = <EmailAddress>[];
    final seen = <String>{};
    final rest = StringBuffer();
    var last = 0;
    for (final m in _token.allMatches(text)) {
      final gap = text.substring(last, m.start);
      last = m.end;
      var email = (m.group(3) ?? m.group(4) ?? '').trim();
      // «mailto:адрес?subject=…» — без параметров ссылки; точка или скобка в
      // конце — от предложения, а не от адреса.
      final q = email.indexOf('?');
      if (q > 0) email = email.substring(0, q);
      email = email.replaceAll(RegExp(r'^[(\[]+|[.)\]]+$'), '');
      final name = (m.group(1) ?? m.group(2) ?? '').trim();
      if (!isValid(email)) {
        rest.write('${gap.trim().isEmpty ? '' : '${gap.trim()} '}${m.group(0)!.trim()} ');
        continue;
      }
      // Слова перед адресом без угловых скобок («Иван ivan@x.ru») — не имя:
      // остаются в поле.
      if (m.group(4) != null && gap.replaceAll(RegExp(r'[\s,;]'), '').isNotEmpty) {
        rest.write('${gap.trim()} ');
      }
      if (!seen.add(email.toLowerCase())) continue;
      out.add(EmailAddress(email: email, displayName: name.isEmpty || name == email ? null : name));
    }
    final tail = text.substring(last).replaceAll(RegExp(r'^[\s,;]+'), '').trim();
    if (tail.isNotEmpty) rest.write(tail);
    return (addresses: out, rest: rest.toString().trim());
  }
}
