// Картинки цитаты — в письмо (2.7.1, замечание владельца 24.11.2026: ответ
// ушёл с пустым местом вместо скриншота исходного письма). Ссылка cid:
// исходного письма заменяется самой картинкой (data:), которую отправка
// превращает во встроенную часть письма.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/providers/mail_open_cache.dart';
import 'package:ogneliss/services/mail/attachment_cache_service.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==';

class _Cache extends AttachmentCacheService {
  _Cache(this.files);
  final Map<String, String> files;
  @override
  Future<void> ensureLoaded() async {}
  @override
  bool has(String attachmentId) => files.containsKey(attachmentId);
  @override
  Future<String?> get(String attachmentId) async => files[attachmentId];
}

void main() {
  late Directory dir;
  late ProviderContainer c;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quote_img');
    final f = File('${dir.path}/image001.png')..writeAsBytesSync(base64.decode(_png));
    c = ProviderContainer(overrides: [
      attachmentCacheProvider.overrideWithValue(
          _Cache({MailEngineService.attachmentCacheKey('a1', 'm1', 'att1'): f.path})),
    ]);
  });

  tearDown(() async {
    c.dispose();
    await dir.delete(recursive: true);
  });

  EmailModel original() => EmailModel(
        id: 'm1',
        accountId: 'a1',
        folderId: 'INBOX',
        from: const EmailAddress(email: 'andrey@corp.example'),
        to: const [EmailAddress(email: 'oleg@corp.example')],
        subject: 'ФУЙ',
        receivedAt: DateTime(2026, 11, 23, 15, 36),
        attachments: const [
          EmailAttachment(id: 'att1', name: 'image001.png', mimeType: 'image/png', size: 70, isInline: true, contentId: '<image001.png@01DB3D2E.5A7F0C40>'),
        ],
      );

  test('cid: исходного письма — картинкой data: в тексте ответа', () async {
    const reply = '<p>А почему на инструктаж не позвали?</p><hr>'
        '<img width="769" height="281" src="cid:image001.png@01DB3D2E.5A7F0C40">'
        "<img src='cid:unknown@x'>";
    final out = await c.read(mailOpenCacheProvider).embedInlineImages('a1', original(), reply);
    expect(out, contains('width="769" height="281" src="data:image/png;base64,$_png"'));
    // Неизвестная картинка — ссылка остаётся (лучше пустое место, чем сбой отправки).
    expect(out, contains("src='cid:unknown@x'"));
    expect(out, startsWith('<p>А почему на инструктаж не позвали?</p>'));
  });

  test('без cid: — текст как есть', () async {
    const plain = '<p>Слово cid: в тексте — не картинка</p>';
    expect(await c.read(mailOpenCacheProvider).embedInlineImages('a1', original(), plain), plain);
  });
}
