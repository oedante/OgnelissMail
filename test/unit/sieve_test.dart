// Фильтры Sieve: сборка и разбор блока правил Ogneliss, сохранение чужих
// правил скрипта, имена папок IMAP, разбор ответов ManageSieve.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/sieve/managesieve_client.dart';
import 'package:ogneliss/services/mail/sieve/sieve_rules.dart';

const _ext = {'fileinto', 'imap4flags', 'copy', 'comparator-i;unicode-casemap'};

const _rules = [
  SieveRule(name: 'Отчёты', field: SieveField.subject, value: 'Отчёт "ТОиР"', action: SieveAction.move, arg: 'INBOX/Отчёты', stop: true),
  SieveRule(name: '', field: SieveField.from, value: 'noreply@corp.ru', action: SieveAction.markRead),
  SieveRule(name: 'Выкл', enabled: false, field: SieveField.to, value: 'all@corp.ru', action: SieveAction.delete),
];

void main() {
  group('SieveRules', () {
    test('сборка: require, команды, выключенное правило — только описанием', () {
      final s = SieveRules.build(_rules, '', _ext);
      expect(s, startsWith('require ["comparator-i;unicode-casemap", "fileinto", "imap4flags"]; # ogneliss:require'));
      expect(s, contains('if header :contains :comparator "i;unicode-casemap" "subject" "Отчёт \\"ТОиР\\"" {'));
      expect(s, contains('fileinto "INBOX/Отчёты";'));
      expect(s, contains('addflag "\\\\Seen";'));
      expect(s, isNot(contains('discard;')));
      expect('# ogneliss:rule '.allMatches(s).length, 3);
    });

    test('разбор возвращает те же правила', () {
      final parts = SieveRules.parse(SieveRules.build(_rules, '', _ext));
      expect(parts.rules.length, 3);
      expect(parts.rules[0].value, 'Отчёт "ТОиР"');
      expect(parts.rules[0].arg, 'INBOX/Отчёты');
      expect(parts.rules[0].stop, isTrue);
      expect(parts.rules[2].enabled, isFalse);
      expect(parts.rules[2].action, SieveAction.delete);
      expect(parts.hasForeignRules, isFalse);
    });

    test('чужие правила сохраняются, наш блок — после их require', () {
      const foreign = 'require ["fileinto",\n  "envelope"];\n# from Roundcube\n'
          'if header :contains "subject" "spam" {\n  fileinto "Junk";\n}\n';
      final s = SieveRules.build(_rules, foreign, _ext);
      final reqEnd = s.indexOf('"envelope"];');
      final block = s.indexOf('# ogneliss:begin');
      final theirs = s.indexOf('if header :contains "subject" "spam"');
      expect(reqEnd, greaterThan(0));
      expect(block, greaterThan(reqEnd));
      expect(theirs, greaterThan(s.indexOf('# ogneliss:end')));

      final parts = SieveRules.parse(s);
      expect(parts.rules.length, 3);
      expect(parts.hasForeignRules, isTrue);
      expect(parts.foreign, contains('fileinto "Junk";'));
      expect(parts.foreign, isNot(contains('ogneliss')));

      // Повторная сборка не размножает блок и require.
      final again = SieveRules.build(parts.rules, parts.foreign, _ext);
      expect('# ogneliss:begin'.allMatches(again).length, 1);
      expect('# ogneliss:require'.allMatches(again).length, 1);
    });

    test('без copy на сервере — redirect без :copy', () {
      const r = SieveRule(name: '', field: SieveField.from, value: 'a@b.ru', action: SieveAction.forward, arg: 'me@x.ru');
      expect(SieveRules.command(r, {'fileinto'}), contains('redirect "me@x.ru";'));
      expect(SieveRules.command(r, {'copy'}), contains('redirect :copy "me@x.ru";'));
    });

    test('проверка заполненности', () {
      expect(const SieveRule(name: '', field: SieveField.from, value: 'x', action: SieveAction.move).isValid, isFalse);
      expect(const SieveRule(name: '', field: SieveField.from, value: 'x', action: SieveAction.forward, arg: 'nope').isValid,
          isFalse);
      expect(const SieveRule(name: '', field: SieveField.from, value: 'x', action: SieveAction.flag).isValid, isTrue);
    });

    test('имя папки IMAP (modified UTF-7)', () {
      expect(decodeImapUtf7('INBOX/&BB4EQgRHBDUEQgRL-'), 'INBOX/Отчеты');
      expect(decodeImapUtf7('A&-B'), 'A&B');
      expect(decodeImapUtf7('Archive'), 'Archive');
    });
  });

  group('ManageSieve: разбор ответов', () {
    test('возможности и OK', () async {
      final r = SieveResponseReader()
        ..add(utf8.encode('"IMPLEMENTATION" "Dovecot Pigeonhole"\r\n'
            '"SIEVE" "fileinto reject envelope imap4flags copy"\r\n'
            '"SASL" "PLAIN"\r\n"STARTTLS"\r\nOK "Ready."\r\n'));
      final lines = await r.readResponse();
      expect(lines.length, 4);
      expect(lines[1][1].value, contains('imap4flags'));
      expect(lines[3].single.value, 'STARTTLS');
    });

    test('список скриптов', () async {
      final r = SieveResponseReader()..add(utf8.encode('"roundcube" ACTIVE\r\n"old"\r\nOK\r\n'));
      final lines = await r.readResponse();
      expect(lines[0][0].value, 'roundcube');
      expect(lines[0][1].atom, isTrue);
      expect(lines[1].length, 1);
    });

    test('литерал со скриптом', () async {
      const script = 'require "fileinto";\r\nif true { keep; }\r\n';
      final r = SieveResponseReader()
        ..add(utf8.encode('{${utf8.encode(script).length}}\r\n$script\r\nOK "Getscript completed."\r\n'));
      final lines = await r.readResponse();
      expect(lines.single.single.value, script);
    });

    test('NO с кодом — исключение', () async {
      final r = SieveResponseReader()..add(utf8.encode('NO (QUOTA/MAXSIZE) "Script is too large"\r\n'));
      await expectLater(
        r.readResponse(),
        throwsA(isA<SieveException>()
            .having((e) => e.code, 'code', 'QUOTA/MAXSIZE')
            .having((e) => e.message, 'message', 'Script is too large')),
      );
    });

    test('ответ, пришедший частями', () async {
      final r = SieveResponseReader();
      final f = r.readResponse();
      r.add(utf8.encode('"a" AC'));
      r.add(utf8.encode('TIVE\r\nO'));
      r.add(utf8.encode('K\r\n'));
      final lines = await f;
      expect(lines.single[1].value, 'ACTIVE');
    });

    test('строка в кавычках для команды', () {
      expect(sieveQuote('a"b\\c'), '"a\\"b\\\\c"');
    });
  });
}
