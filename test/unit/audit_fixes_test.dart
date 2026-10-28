// Тесты исправлений по аудиту (октябрь 2026): безопасность, умная почта,
// локализация. Чистая логика — без БД, сети и виджетов.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/errors/app_exceptions.dart';
import 'package:ogneliss/core/logging/app_logger.dart';
import 'package:ogneliss/core/security/attachment_safety.dart';
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/core/security/link_opener.dart';
import 'package:ogneliss/core/utils/quote_splitter.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/compose/widgets/mail_editor.dart';
import 'package:ogneliss/l10n/strings_store.dart';
import 'package:ogneliss/services/calendar/meeting_link_service.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart' show imapConversationId;
import 'package:ogneliss/services/mail/oauth/proxy_pkce.dart';

void main() {
  group('HtmlSanitizer (G-1)', () {
    test('удаляет script, обработчики и javascript:', () {
      final out = HtmlSanitizer.sanitize(
          '<p>Привет</p><script>alert(1)</script><img src=x onerror=alert(1)>'
          '<a href="java&#x73;cript:alert(1)">ссылка</a>');
      expect(out, contains('Привет'));
      expect(out.toLowerCase(), isNot(contains('<script')));
      expect(out.toLowerCase(), isNot(contains('onerror')));
      expect(out.toLowerCase(), isNot(contains('javascript')));
      expect(out, contains('ссылка'));
    });

    test('убирает CSS с url() и оставляет безопасные картинки', () {
      final out = HtmlSanitizer.sanitize(
          '<div style="background:url(https://t.example/p.gif)">x</div>'
          '<img src="cid:logo"><img src="data:image/png;base64,AAAA">');
      expect(out, isNot(contains('url(')));
      expect(out, contains('cid:logo'));
      expect(out, contains('data:image/png;base64'));
    });

    test('для редактора экранирует обратную косую черту', () {
      expect(HtmlSanitizer.forEditor(r"<p>a\'b</p>"), isNot(contains(r'\')));
    });
  });

  group('Цитата (M-6)', () {
    test('жирное «От:» русского Outlook сворачивается', () {
      const html = '<p>Добрый день, согласую.</p>'
          '<p class="MsoNormal"><b>От:</b> Иванов И.И. &lt;i@corp.ru&gt;<br>'
          '<b>Отправлено:</b> 1 октября</p><p>Старый текст</p>';
      final s = splitQuotedHtml(html);
      expect(s.hasQuote, isTrue);
      expect(s.reply, contains('согласую'));
      expect(s.reply, isNot(contains('Иванов')));
    });

    test('шапка внутри таблицы — разрез по таблице, таблица цела', () {
      const html = '<div class="WordSection1"><p>Принято, спасибо.</p>'
          '<table><tr><td><p><b>От:</b> Петров П.П.<br><b>Отправлено:</b> 2 октября</p>'
          '<table><tr><td>Ячейка 1</td><td>Ячейка 2</td></tr></table></td></tr></table></div>';
      final s = splitQuotedHtml(html);
      expect(s.hasQuote, isTrue);
      expect(s.reply, contains('Принято'));
      expect(s.reply, isNot(contains('<table')));
      // Обёртка сохраняется в обеих половинах, таблица в цитате — целиком.
      expect(s.quoted, contains('WordSection1'));
      expect('<table'.allMatches(s.quoted).length, 2);
      expect('</table>'.allMatches(s.quoted).length, 2);
      expect(s.quoted, contains('Ячейка 2'));
    });

    test('пересылка без комментария не сворачивается', () {
      const html = '<p>---------- Forwarded message ---------</p><p>Текст письма</p>';
      final s = splitQuotedHtml(html);
      expect(s.hasQuote, isFalse);
      expect(s.reply, contains('Текст письма'));
    });

    test('фраза «пишет:» в длинном абзаце ответа — не цитата', () {
      final html = '<p>${'Коллега пишет: нужно согласовать график работ. ' * 6}</p><p>Итого</p>';
      final s = splitQuotedHtml(html);
      expect(s.hasQuote, isFalse);
    });
  });

  group('Редактор HugeRTE', () {
    test('CSP пускает только встроенный скрипт по хэшу', () {
      const script = 'console.log(1);';
      final page = buildMailEditorPage(script: script, skinCss: '', config: const {});
      final hash = base64.encode(sha256.convert(utf8.encode(script)).bytes);
      expect(page, contains("script-src 'sha256-$hash'"));
      expect(page, contains("connect-src 'none'"));
      expect(page, contains('<script>$script</script>'));
    });

    test('</script> в настройках не закрывает тег', () {
      final page = buildMailEditorPage(
          script: '', skinCss: '', config: const {'placeholder': '</script><script>alert(1)</script>'});
      expect('<script'.allMatches(page).length, 2); // config + редактор
    });

    test('картинка — по сигнатуре, SVG не принимается', () {
      expect(imageMimeBySignature([0x89, 0x50, 0x4E, 0x47, 0, 0]), 'image/png');
      expect(imageMimeBySignature(utf8.encode('<svg onload=alert(1)>')), isNull);
    });
  });

  group('Отказ во входе (push)', () {
    test('401 и AUTHENTICATIONFAILED — отказ, 403 и таймаут — нет', () {
      expect(looksLikeAuthError(Exception('HTTP 401')), isTrue);
      expect(looksLikeAuthError(Exception('NO [AUTHENTICATIONFAILED] Invalid credentials')), isTrue);
      expect(looksLikeAuthError(const PushAuthFailure()), isTrue);
      expect(looksLikeAuthError(Exception('HTTP 403')), isFalse);
      expect(looksLikeAuthError(Exception('TimeoutException after 0:00:15')), isFalse);
      expect(looksLikeAuthError(Exception('HTTP 4010 bytes')), isFalse);
    });
  });

  group('Ссылки (U-5)', () {
    test('текст показывает другой домен', () {
      final c = LinkOpener.check('https://evil.example/login', linkText: 'www.sberbank.ru')!;
      expect(c.textMismatch, isTrue);
    });
    test('тот же домен — без предупреждения', () {
      final c = LinkOpener.check('https://portal.corp.ru/a', linkText: 'corp.ru')!;
      expect(c.hasWarning, isFalse);
    });
    test('http, IP и punycode помечаются', () {
      expect(LinkOpener.check('http://a.ru')!.insecure, isTrue);
      expect(LinkOpener.check('https://10.0.0.1/x')!.suspiciousHost, isTrue);
      expect(LinkOpener.check('https://xn--80ak6aa92e.com')!.suspiciousHost, isTrue);
    });
    test('javascript: не открывается', () {
      expect(LinkOpener.check('javascript:alert(1)'), isNull);
    });
  });

  group('Вложения (G-8)', () {
    test('исполняемые блокируются', () {
      expect(AttachmentSafety.riskOf('setup.exe'), AttachmentRisk.blocked);
      expect(AttachmentSafety.riskOf('счёт.pdf.js'), AttachmentRisk.blocked);
      expect(AttachmentSafety.riskOf('doc\u202Efdp.exe'), AttachmentRisk.blocked);
    });
    test('макросы — предупреждение, документы — без', () {
      expect(AttachmentSafety.riskOf('план.docm'), AttachmentRisk.warn);
      expect(AttachmentSafety.riskOf('акт.pdf'), AttachmentRisk.safe);
    });
  });

  group('Беседы (M-4)', () {
    test('корень — первый Message-ID из References', () {
      expect(imapConversationId('<root@x> <mid@x>', '<mid@x>', '<me@x>'), '<root@x>');
      expect(imapConversationId(null, '<p@x>', '<me@x>'), '<p@x>');
      expect(imapConversationId(null, null, '<me@x>'), '<me@x>');
    });
  });

  group('Поисковый индекс', () {
    test('rowid устойчив, в пределах 53 бит и различает аккаунты', () {
      final a = AppDatabase.ftsRowId('acc1', 'INBOX:1');
      expect(a, AppDatabase.ftsRowId('acc1', 'INBOX:1'));
      expect(a, isNot(AppDatabase.ftsRowId('acc2', 'INBOX:1')));
      expect(a >= 0 && a < (1 << 53), isTrue);
    });
  });

  group('Ссылка на встречу (G-10)', () {
    test('по хосту, а не по подстроке', () {
      expect(MeetingLinkService.platformOf('https://teams.microsoft.com/l/meetup-join/1'), 'Teams');
      expect(MeetingLinkService.platformOf('https://evil.example/?teams.microsoft.com'), isNull);
      expect(MeetingLinkService.platformOf('https://teams.microsoft.com@evil.example/'), isNull);
    });
  });

  group('Журнал (G-9)', () {
    test('адреса и токены маскируются', () {
      final m = AppLogger.mask('ivanov@corp.ru at=abc&rt=def Bearer xyz.123');
      expect(m, contains('i***@corp.ru'));
      expect(m, isNot(contains('abc')));
      expect(m, isNot(contains('def')));
      expect(m, isNot(contains('xyz.123')));
    });
  });

  group('PKCE прокси (G-6)', () {
    test('challenge = base64url(sha256(verifier)) без =', () {
      final p = ProxyPkce.generate();
      final expected = base64Url
          .encode(sha256.convert(ascii.encode(p.verifier)).bytes)
          .replaceAll('=', '');
      expect(p.challenge, expected);
      expect(p.challenge.length, 43);
    });
  });

  group('Локализация', () {
    // 1.7.3: строки — файлами assets/l10n/<код>.xml.
    LangStrings load(String l) => StringsStore.parse(File('assets/l10n/$l.xml').readAsStringSync());

    test('каждая строка есть на ru, en, de, fr', () {
      final en = load('en');
      expect(en.strings.length, greaterThan(3000));
      for (final l in const ['ru', 'de', 'fr']) {
        final o = load(l);
        for (final k in en.strings.keys) {
          expect(o.strings[k], isNotNull, reason: '$k: $l');
        }
        for (final k in en.plurals.keys) {
          expect(o.plurals[k], isNotNull, reason: '$k: $l');
        }
      }
    });

    // Русский — язык оригинала: в подсказках шаблонов в нём русские имена
    // полей ({имя}, {телефон}) — шаблоны понимают оба вида.
    test('заполнители {…} совпадают во всех языках', () {
      final re = RegExp(r'\{[a-zA-Z_]+\}');
      Set<String> ph(String? s) => re.allMatches(s ?? '').map((m) => m.group(0)!).toSet();
      final en = load('en');
      for (final l in const ['de', 'fr']) {
        final o = load(l);
        for (final e in en.strings.entries) {
          expect(ph(o.strings[e.key]), ph(e.value), reason: '${e.key}: $l');
        }
      }
    });
  });
}
