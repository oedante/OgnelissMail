// lib/services/mail/dav/vcard_parser.dart
// Минимальный парсер vCard (3.0/4.0): FN, N, EMAIL, TEL, ORG, TITLE, PHOTO.
// Без внешних зависимостей. Учитывает развёртку строк и параметры (TYPE).

import 'dart:convert' show utf8;

class VCardData {
  final String? fn;       // отображаемое имя
  final String? given;
  final String? family;
  final String? middle;
  final String email;
  final List<String> emails;
  final String? phoneWork;
  final String? phoneMobile;
  final String? org;
  final String? title;
  /// Фото: data URI (встроенное base64) или https-адрес (Google отдаёт ссылку).
  final String? photo;

  const VCardData({
    this.fn,
    this.given,
    this.family,
    this.middle,
    this.email = '',
    this.emails = const [],
    this.phoneWork,
    this.phoneMobile,
    this.org,
    this.title,
    this.photo,
  });

  String get displayName {
    if (fn != null && fn!.isNotEmpty) return fn!;
    final parts = [given, family].where((e) => e != null && e.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : email;
  }
}

class VCardParser {
  static List<VCardData> parse(String text) {
    final lines = _unfold(text);
    final cards = <VCardData>[];
    List<List<String>>? cur; // [name+params, value]
    for (final l in lines) {
      final up = l.toUpperCase();
      if (up == 'BEGIN:VCARD') {
        cur = [];
      } else if (up == 'END:VCARD') {
        if (cur != null) cards.add(_build(cur));
        cur = null;
      } else if (cur != null) {
        final colon = l.indexOf(':');
        if (colon > 0) cur.add([l.substring(0, colon), l.substring(colon + 1)]);
      }
    }
    return cards;
  }

  static VCardData _build(List<List<String>> props) {
    String? fn, given, family, middle, org, title, photo;
    final emails = <String>[];
    String? phoneWork, phoneMobile;

    for (final p in props) {
      final left = p[0];
      final value = p[1].trim();
      final segs = left.split(';');
      // Группа свойства («item1.EMAIL» у Google) — отбрасываем.
      final full = segs.first.toUpperCase();
      final name = full.contains('.') ? full.substring(full.lastIndexOf('.') + 1) : full;
      final params = segs.skip(1).map((e) => e.toUpperCase()).join(';');

      switch (name) {
        case 'FN':
          fn = _unescape(value);
          break;
        case 'N':
          // Family;Given;Middle;Prefix;Suffix
          final n = value.split(RegExp(r'(?<!\\);'));
          family = _nz(_unescape(n.isNotEmpty ? n[0] : null));
          given = _nz(_unescape(n.length > 1 ? n[1] : null));
          middle = _nz(_unescape(n.length > 2 ? n[2] : null));
          break;
        case 'EMAIL':
          if (value.isNotEmpty) emails.add(value);
          break;
        case 'TEL':
          final isCell = params.contains('CELL') || params.contains('MOBILE');
          if (isCell) {
            phoneMobile ??= value;
          } else {
            phoneWork ??= value;
          }
          break;
        case 'ORG':
          org = _unescape(value.split(RegExp(r'(?<!\\);')).first);
          break;
        case 'TITLE':
          title = _unescape(value);
          break;
        case 'PHOTO':
          photo ??= _photo(value, params);
          break;
      }
    }

    return VCardData(
      fn: fn,
      given: given,
      family: family,
      middle: middle,
      email: emails.isNotEmpty ? emails.first : '',
      emails: emails,
      phoneWork: phoneWork,
      phoneMobile: phoneMobile,
      org: org,
      title: title,
      photo: photo,
    );
  }

  /// PHOTO в любом из видов: «data:…» (vCard 4), https-ссылка, base64 с
  /// ENCODING=b и TYPE=JPEG (vCard 3).
  static String? _photo(String value, String params) {
    final v = value.replaceAll(RegExp(r'\s'), '');
    if (v.isEmpty) return null;
    final low = v.toLowerCase();
    if (low.startsWith('data:image/')) return v;
    if (low.startsWith('https://') || low.startsWith('http://')) return v;
    if (params.contains('ENCODING=B') || params.contains('BASE64')) {
      final type = params.contains('PNG') ? 'png' : params.contains('GIF') ? 'gif' : 'jpeg';
      return 'data:image/$type;base64,$v';
    }
    return null;
  }

  static List<String> _unfold(String text) {
    final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = <String>[];
    for (final l in raw) {
      if (l.isEmpty) continue;
      if ((l.startsWith(' ') || l.startsWith('\t')) && out.isNotEmpty) {
        out[out.length - 1] = out.last + l.substring(1);
      } else {
        out.add(l);
      }
    }
    return out;
  }

  static String? _nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
  static String? _unescape(String? v) =>
      v?.replaceAll(r'\n', '\n').replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\\', '\\');
}


/// Генерация и правка vCard 3.0 для CardDAV (Google, Яндекс, Yahoo).
/// Правка заменяет только поля, которые есть в приложении (имя, первый
/// e-mail, рабочий и мобильный телефон, организация, должность); фото,
/// адреса, заметки и прочее остаются как были.
class VCardWriter {
  /// Перенос строк длиннее 75 байт (фото base64 — тысячи символов).
  static String _join(List<String> lines) {
    final b = StringBuffer();
    for (final line in lines) {
      if (utf8.encode(line).length <= 75) {
        b.write('$line\r\n');
        continue;
      }
      var bytes = 0;
      for (final r in line.runes) {
        final ch = String.fromCharCode(r);
        final n = utf8.encode(ch).length;
        if (bytes + n > 74) {
          b.write('\r\n ');
          bytes = 1;
        }
        b.write(ch);
        bytes += n;
      }
      b.write('\r\n');
    }
    return b.toString();
  }

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  static List<String> _fields({
    required String displayName,
    String? firstName,
    String? lastName,
    String? middleName,
    String? email,
    String? phoneWork,
    String? phoneMobile,
    String? company,
    String? jobTitle,
    // Левая часть заменяемых строк как была («item1.EMAIL;TYPE=INTERNET»,
    // «TEL;TYPE=HOME») и хвост ORG (отдел) — чтобы правка не меняла их тип.
    String emailLeft = 'EMAIL;TYPE=INTERNET',
    String workLeft = 'TEL;TYPE=WORK',
    String cellLeft = 'TEL;TYPE=CELL',
    String orgTail = '',
  }) =>
      [
        'FN:${_esc(displayName)}',
        'N:${_esc(lastName ?? '')};${_esc(firstName ?? '')};${_esc(middleName ?? '')};;',
        if (email != null && email.trim().isNotEmpty) '$emailLeft:${email.trim()}',
        if (phoneWork != null && phoneWork.trim().isNotEmpty) '$workLeft:${phoneWork.trim()}',
        if (phoneMobile != null && phoneMobile.trim().isNotEmpty) '$cellLeft:${phoneMobile.trim()}',
        if (company != null && company.trim().isNotEmpty) 'ORG:${_esc(company.trim())}$orgTail',
        if (jobTitle != null && jobTitle.trim().isNotEmpty) 'TITLE:${_esc(jobTitle.trim())}',
      ];

  static String card({
    required String uid,
    required String displayName,
    String? firstName,
    String? lastName,
    String? middleName,
    String? email,
    String? phoneWork,
    String? phoneMobile,
    String? company,
    String? jobTitle,
  }) {
    final l = [
      'BEGIN:VCARD',
      'VERSION:3.0',
      'UID:$uid',
      ..._fields(
        displayName: displayName,
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        email: email,
        phoneWork: phoneWork,
        phoneMobile: phoneMobile,
        company: company,
        jobTitle: jobTitle,
      ),
      'END:VCARD',
    ];
    return _join(l);
  }

  static String _name(String line) {
    final i = line.indexOf(RegExp('[;:]'));
    final full = (i < 0 ? line : line.substring(0, i)).toUpperCase();
    return full.contains('.') ? full.substring(full.lastIndexOf('.') + 1) : full;
  }

  static String patch(
    String vcf, {
    required String displayName,
    String? firstName,
    String? lastName,
    String? middleName,
    String? email,
    String? phoneWork,
    String? phoneMobile,
    String? company,
    String? jobTitle,
  }) {
    final lines = VCardParser._unfold(vcf);
    final out = <String>[];
    var emailDone = false, workDone = false, cellDone = false, inCard = false;
    var insertAt = -1;
    String? emailLeft, workLeft, cellLeft;
    var orgTail = '';
    for (final l in lines) {
      final up = l.toUpperCase();
      if (up == 'BEGIN:VCARD') {
        inCard = true;
        out.add(l);
        continue;
      }
      if (up == 'END:VCARD') {
        inCard = false;
        out.add(l);
        continue;
      }
      if (!inCard) {
        out.add(l);
        continue;
      }
      final n = _name(l);
      if (n == 'VERSION') {
        out.add(l);
        insertAt = out.length;
        continue;
      }
      if (n == 'ORG') {
        // «Компания;Отдел» — отдел (после неэкранированной «;») сохраняем.
        final v = l.substring(l.indexOf(':') + 1);
        final m = RegExp(r'(?<!\\);').firstMatch(v);
        if (m != null) orgTail = v.substring(m.start);
        continue;
      }
      if (n == 'FN' || n == 'N' || n == 'TITLE' || n == 'REV') continue;
      if (n == 'EMAIL' && !emailDone) {
        emailDone = true;
        if (l.contains(':')) emailLeft = l.substring(0, l.indexOf(':'));
        continue;
      }
      if (n == 'TEL') {
        final params = l.substring(0, l.contains(':') ? l.indexOf(':') : l.length).toUpperCase();
        final cell = params.contains('CELL') || params.contains('MOBILE');
        if (cell && !cellDone) {
          cellDone = true;
          if (l.contains(':')) cellLeft = l.substring(0, l.indexOf(':'));
          continue;
        }
        if (!cell && !workDone) {
          workDone = true;
          if (l.contains(':')) workLeft = l.substring(0, l.indexOf(':'));
          continue;
        }
      }
      out.add(l);
    }
    final fields = _fields(
      displayName: displayName,
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      email: email,
      phoneWork: phoneWork,
      phoneMobile: phoneMobile,
      company: company,
      jobTitle: jobTitle,
      emailLeft: emailLeft ?? 'EMAIL;TYPE=INTERNET',
      workLeft: workLeft ?? 'TEL;TYPE=WORK',
      cellLeft: cellLeft ?? 'TEL;TYPE=CELL',
      orgTail: orgTail,
    );
    if (insertAt < 0) {
      final b = out.indexWhere((x) => x.toUpperCase() == 'BEGIN:VCARD');
      insertAt = b < 0 ? 0 : b + 1;
    }
    out.insertAll(insertAt, fields);
    return _join(out);
  }
}
