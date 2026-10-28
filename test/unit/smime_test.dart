// S/MIME: чтение .pfx (PBES2/AES и старый 3DES), проверка подписи и
// расшифровка писем, созданных OpenSSL (как Outlook), и обратный путь —
// наша подпись и шифрование читаются нашим же кодом.
// Образцы — test/fixtures/smime (тестовый ключ, пароль «secret»).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/cms/cms.dart';
import 'package:ogneliss/services/security/cms/pkcs12.dart';
import 'package:ogneliss/services/security/smime_mime.dart';

Uint8List _f(String name) => File('test/fixtures/smime/$name').readAsBytesSync();

void main() {
  late SmimeIdentity id;

  setUpAll(() {
    id = Pkcs12.parse(_f('aes.p12'), 'secret');
  });

  group('PKCS#12', () {
    test('PBES2 + AES-256 (OpenSSL 3, Windows AES256-SHA256)', () {
      expect(id.certificate.commonName, 'Ivan Ivanov');
      expect(id.certificate.hasEmail('ivanov@corp.test'), isTrue);
      expect(id.key.n, id.certificate.rsa!.n);
    });

    test('старый формат: PBE-SHA1-3DES', () {
      final legacy = Pkcs12.parse(_f('legacy.p12'), 'secret');
      expect(legacy.certificate.commonName, 'Ivan Ivanov');
    });

    test('неверный пароль', () {
      expect(
        () => Pkcs12.parse(_f('aes.p12'), 'wrong'),
        throwsA(isA<Pkcs12Exception>().having((e) => e.code, 'code', 'password')),
      );
    });
  });

  group('Чтение писем OpenSSL', () {
    test('подпись multipart/signed верна', () {
      final r = SmimeMime.open(_f('signed.eml'));
      expect(r.signature, isNotNull);
      expect(r.signature!.valid, isTrue, reason: r.signature!.error);
      expect(r.signature!.signer!.hasEmail('ivanov@corp.test'), isTrue);
      expect(utf8.decode(r.entity, allowMalformed: true), contains('Совещание завтра'));
    });

    test('изменённое письмо — подпись не сходится', () {
      final raw = utf8.decode(_f('signed.eml')).replaceFirst('Совещание завтра', 'Совещание сегодня');
      final r = SmimeMime.open(Uint8List.fromList(utf8.encode(raw)));
      expect(r.signature!.valid, isFalse);
    });

    for (final name in ['encrypted.eml', 'encrypted_3des.eml', 'encrypted_oaep.eml']) {
      test('расшифровка $name', () {
        final r = SmimeMime.open(_f(name), identity: id);
        expect(r.error, isNull);
        expect(r.decrypted, isTrue);
        expect(utf8.decode(r.entity, allowMalformed: true), contains('Совещание завтра'));
      });
    }

    test('без своего ключа — needKey', () {
      expect(SmimeMime.open(_f('encrypted.eml')).error, 'needKey');
    });
  });

  group('Наша подпись и шифрование', () {
    final message = Uint8List.fromList(utf8.encode('From: me@corp.test\r\nTo: ivanov@corp.test\r\n'
        'Subject: Test\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n'
        'Content-Transfer-Encoding: base64\r\n\r\n${base64.encode(utf8.encode('Привет'))}\r\n'));

    test('подпись проверяется', () {
      final signed = SmimeMime.transformMessage(message, (e) => SmimeMime.signEntity(e, id));
      final s = latin1.decode(signed);
      expect(s, contains('multipart/signed'));
      expect(s, contains('Subject: Test'));
      final r = SmimeMime.open(signed);
      expect(r.signature!.valid, isTrue, reason: r.signature!.error);
    });

    test('шифрование и подпись внутри', () {
      final protected = SmimeMime.transformMessage(
          message, (e) => SmimeMime.encryptEntity(SmimeMime.signEntity(e, id), [id.certificate]));
      expect(latin1.decode(protected), contains('smime.p7m'));
      final r = SmimeMime.open(protected, identity: id);
      expect(r.decrypted, isTrue);
      expect(r.signature?.valid, isTrue);
      expect(latin1.decode(r.entity), contains('Content-Type: text/plain'));
    });

    test('Bcc убирается из готового письма, остальное не трогается', () {
      final m = Uint8List.fromList(latin1.encode('From: a@b\r\nBcc: x@y,\r\n z@w\r\nTo: c@d\r\n\r\nBcc: body\r\n'));
      final out = latin1.decode(SmimeMime.withoutHeaders(m, const {'bcc'}));
      expect(out, 'From: a@b\r\nTo: c@d\r\n\r\nBcc: body\r\n');
    });

    test('CMS: тип содержимого', () {
      final cms = Cms.envelope(Uint8List.fromList([1, 2, 3]), [id.certificate]);
      expect(Cms.contentType(cms), '1.2.840.113549.1.7.3');
      expect(Cms.decrypt(cms, id), [1, 2, 3]);
    });
  });
}
