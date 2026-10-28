// 1.7.0: черновики — связь с исходным письмом (parent_id), начатые ответы
// («Черновик: …» в ленте), сравнение тем без «RE:».
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/draft_autosave_service.dart';
import 'package:ogneliss/services/mail/reply_drafts.dart';

void main() {
  group('DraftData.parentRef', () {
    test('ответ и пересылка', () {
      final reply = DraftData(
        id: 'draft-1',
        accountId: 'a1',
        replyToId: 'INBOX:42',
        parentAccountId: 'a2',
        savedAt: DateTime(2026, 10, 20),
      );
      expect(reply.parentRef, 'r|a2|INBOX:42');
      final fwd = DraftData(
        id: 'draft-2',
        accountId: 'a1',
        forwardFromId: 'AAMk|x',
        savedAt: DateTime(2026, 10, 20),
      );
      // Ящик исходного письма не задан — ящик черновика.
      expect(fwd.parentRef, 'f|a1|AAMk|x');
      expect(DraftData(id: 'd', accountId: 'a', savedAt: DateTime(2026)).parentRef, isNull);
    });

    test('разбор', () {
      final p = DraftData.parseParentRef('f|a1|AAMk|x')!;
      expect(p.accountId, 'a1');
      expect(p.emailId, 'AAMk|x');
      expect(p.forward, isTrue);
      expect(DraftData.parseParentRef('r|a2|5:12')!.forward, isFalse);
      expect(DraftData.parseParentRef(null), isNull);
      expect(DraftData.parseParentRef('r||5:12'), isNull);
      expect(DraftData.parseParentRef('x|a|b'), isNull);
    });
  });

  group('ReplyDraft', () {
    test('тема без приставок ответа и пересылки', () {
      expect(ReplyDraft.bareSubject('RE: Fw: Отчёт за май'), 'отчёт за май');
      expect(ReplyDraft.bareSubject('Отв: Пер: AW: WG: План'), 'план');
      expect(ReplyDraft.bareSubject('RE[2]: Встреча'), 'встреча');
      expect(ReplyDraft.bareSubject('Ответ: Счёт'), 'счёт');
      expect(ReplyDraft.bareSubject('Report RE: May'), 'report re: may');
      expect(ReplyDraft.bareSubject('  '), '');
    });

    test('начало текста без приветствия и тегов', () {
      expect(
        ReplyDraft.snippet('<div>Добрый день, Иван Петрович,</div><div>Пришлю отчёт завтра.</div>'),
        'Пришлю отчёт завтра.',
      );
      expect(ReplyDraft.snippet('Готово &amp; отправлено'), 'Готово & отправлено');
      // Одна строка — приветствие не отбрасывается (иначе нечего показать).
      expect(ReplyDraft.snippet('Коллеги,'), 'Коллеги,');
      final long = ReplyDraft.snippet('а' * 300);
      expect(long.length, 141);
      expect(long.endsWith('…'), isTrue);
    });

    test('JSON туда и обратно', () {
      final d = ReplyDraft(
        accountId: 'a1',
        emailId: 'INBOX:7',
        conversationId: 'c1',
        subject: 'RE: План',
        text: 'Согласен',
        forward: false,
        at: DateTime.fromMillisecondsSinceEpoch(1760000000000),
      );
      expect(ReplyDraft.fromJson(d.toJson()), d);
      expect(ReplyDraft.fromJson({'a': 'x'}), isNull);
      expect(ReplyDraft.fromJson('строка'), isNull);
    });

    test('поиск начатого ответа: письмо и беседа', () {
      final d = ReplyDraft(
        accountId: 'a1',
        emailId: 'INBOX:7',
        conversationId: 'c1',
        subject: 'RE: План',
        text: 'Согласен',
        at: DateTime(2026, 10, 20),
      );
      final m = {d.key: d};
      expect(replyDraftFor(m, 'a1', 'INBOX:7', null), d);
      expect(replyDraftFor(m, 'a1', 'INBOX:8', 'c1'), d);
      expect(replyDraftFor(m, 'a1', 'INBOX:8', null), isNull);
      expect(replyDraftFor(m, 'a2', 'INBOX:7', 'c1'), isNull);
    });
  });
}
