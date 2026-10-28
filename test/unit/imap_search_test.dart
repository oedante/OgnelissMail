// test/unit/imap_search_test.dart
// Поиск на сервере IMAP: кириллица — литералом {N} с CHARSET UTF-8 (Gmail
// отвечал «BAD Could not parse command» на текст в кавычках).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  test('латиница — в кавычках, без CHARSET', () {
    expect(imapSearchVariants('report', gmail: true), ['X-GM-RAW "report"']);
    expect(imapSearchVariants('report', gmail: false), ['OR OR SUBJECT "report" FROM "report" TO "report"']);
  });

  test('кириллица — литерал с длиной в байтах UTF-8, затем запасной вариант', () {
    const q = 'смирнов';
    final n = utf8.encode(q).length; // 14 байт
    final g = imapSearchVariants(q, gmail: true);
    expect(g.first, 'CHARSET UTF-8 X-GM-RAW {$n}\n$q');
    expect(g.last, 'CHARSET UTF-8 X-GM-RAW "$q"');
    final o = imapSearchVariants(q, gmail: false);
    expect(o.first, 'CHARSET UTF-8 OR OR SUBJECT {$n}\n$q FROM {$n}\n$q TO {$n}\n$q');
    // Части команды (enough_mail делит по переводу строки и шлёт после «+»).
    expect(o.first.split('\n').length, 4);
  });
}
