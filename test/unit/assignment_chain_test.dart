// Вся цепочка поручения (проверка 15.11.2026): поручить → принять в работу
// → вопрос и ответ → «Готово» → вернуть на доработку с пояснением → снова
// «Готово» → принять; напоминание, перенос срока, снятие. У каждого
// участника — свой телефон (своя база). Письма доставляются получателям и
// в «Отправленные» отправителя, с Message-ID и In-Reply-To — как у
// настоящего сервера; разбор — как после синхронизации.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/subject_prefix.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show accountsProvider;
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/assignments/assignment_service.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';
import 'package:ogneliss/services/mail/offline_send_service.dart';
import 'package:ogneliss/services/notifications/notification_service.dart';
import 'package:ogneliss/services/notifications/reminder_scheduler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Mail {
  final String from;
  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final String subject;
  final String html;
  final String? inReplyTo;
  _Mail(this.from, this.to, this.cc, this.subject, this.html, this.inReplyTo);
  Set<String> get rcpt => {for (final a in [...to, ...cc]) a.email.toLowerCase()};
}

class _Outbox extends OfflineSendService {
  _Outbox(super.ref, this.me, this.sink);
  final String me;
  final void Function(_Mail) sink;

  @override
  Future<bool> sendOrQueue({
    required String accountId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool keepTooLarge = false,
    bool requestDeliveryReport = false,
    bool requestReadReceipt = false,
  }) async {
    sink(_Mail(me, to, cc, subject, bodyHtml, inReplyTo));
    return true;
  }
}

class _NoReminders extends ReminderSchedulerService {
  _NoReminders(AppDatabase db) : super(db, NotificationService());
  @override
  Future<void> rescheduleAll({bool force = false}) async {}
}

class _Phone {
  final String email;
  final String name;
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  late final ProviderContainer c;
  _Phone(this.email, this.name);

  AssignmentService get svc => c.read(assignmentServiceProvider);
  Map<String, Set<String>> get mine => {
        'a': {email}
      };
  Future<List<AssignmentView>> all() => AssignmentStore.all(db, mine);
  Future<AssignmentView> one(String id) async => (await all()).firstWhere((v) => v.id == id);
  Future<List<AssignmentEvent>> history(String id) => AssignmentStore.events(db, id);
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await AppLocalizations.load('ru');
  });

  const boss = 'boss@corp.ru';
  const vera = 'vera@corp.ru';
  final names = {boss: 'Иван Петрович', vera: 'Вера Сергеевна'};

  late Map<String, _Phone> phones;
  final queue = <_Mail>[];
  final log = <_Mail>[];
  var n = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'s_locale': 'ru'});
    final prefs = await SharedPreferences.getInstance();
    queue.clear();
    log.clear();
    phones = {for (final e in names.entries) e.key: _Phone(e.key, e.value)};
    for (final p in phones.values) {
      await p.db.into(p.db.accounts).insert(AccountsCompanion.insert(
          id: 'a', type: 7, email: p.email, displayName: p.name, username: p.email, createdAt: DateTime(2026)));
      for (final (id, t) in [('in', FolderType.inbox), ('sent', FolderType.sent)]) {
        await p.db.into(p.db.folders).insert(
            FoldersCompanion.insert(id: id, accountId: 'a', displayName: id, type: Value(t.index)));
      }
      p.c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(p.db),
        sharedPrefsProvider.overrideWithValue(prefs),
        offlineSendProvider.overrideWith((ref) => _Outbox(ref, p.email, queue.add)),
        reminderSchedulerProvider.overrideWith((ref) => _NoReminders(p.db)),
      ]);
      p.c.read(accountsProvider);
    }
    for (var i = 0; i < 50 && phones.values.any((p) => p.c.read(accountsProvider).isEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });

  tearDown(() async {
    for (final p in phones.values) {
      p.c.dispose();
      await p.db.close();
    }
  });

  String json(List<EmailAddress> l) => jsonEncode([for (final a in l) {'email': a.email, 'displayName': a.displayName}]);

  /// Message-ID письма у всех (одно письмо — один Message-ID).
  final mids = <_Mail, String>{};

  Future<void> put(_Phone p, _Mail m, String folder) async {
    final mid = mids[m] ??= '<m${n++}@corp.ru>';
    await p.db.into(p.db.emails).insert(EmailsCompanion.insert(
          id: '${p.email}-${n++}',
          accountId: 'a',
          folderId: folder,
          fromEmail: m.from,
          fromName: Value(names[m.from]),
          toRecipients: json(m.to),
          ccJson: Value(json(m.cc)),
          subject: m.subject,
          bodyHtml: Value(m.html),
          internetMessageId: Value(mid),
          referencesStr: Value(m.inReplyTo),
          receivedAt: DateTime.now().add(Duration(microseconds: n)),
        ));
  }

  /// Доставить отправленное: получателям — во «Входящие», отправителю — в
  /// «Отправленные»; разбор почты у всех.
  Future<List<_Mail>> deliver() async {
    final sent = [...queue];
    queue.clear();
    log.addAll(sent);
    for (final m in sent) {
      for (final p in phones.values) {
        if (p.email == m.from) {
          await put(p, m, 'sent');
        } else if (m.rcpt.contains(p.email)) {
          await put(p, m, 'in');
        }
      }
    }
    for (final p in phones.values) {
      await AssignmentStore.scan(p.db, p.mine, since: DateTime.now().subtract(const Duration(days: 1)));
    }
    return sent;
  }

  /// Письмо, написанное человеком в обычном редакторе (ответ с цитатой).
  Future<void> handReply(_Phone from, _Mail to, String text) async {
    final mid = mids[to]!;
    queue.add(_Mail(from.email, [EmailAddress(email: to.from)], const [], SubjectPrefix.reply(to.subject),
        '<div>$text</div><div class="gmail_quote"><blockquote>${to.html}</blockquote></div>', mid));
    await deliver();
  }

  EmailAddress a(String e) => EmailAddress(email: e, displayName: names[e]);

  test('цепочка: поручить → взять → вопрос → готово → доработка → готово → принять', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Отчёт за квартал', assignees: [a(vera)], due: DateTime(2026, 11, 21)))
        .single;
    final first = (await deliver()).single;
    expect((await v.one(id)).status, AssignmentStatus.open);

    // Исполнитель берёт в работу.
    await v.svc.setStatus(await v.one(id), AssignmentStatus.inProgress);
    final taken = (await deliver()).single;
    expect((await b.one(id)).status, AssignmentStatus.inProgress);
    expect(taken.subject, 'Re: ${first.subject}');
    expect(taken.inReplyTo, isNotNull, reason: 'ответ — в беседу письма поручения');

    // Вопрос — обычным ответом на письмо поручения; статус не меняется,
    // вопрос — в истории у постановщика.
    await handReply(v, first, 'Какой формат отчёта нужен?');
    expect((await b.one(id)).status, AssignmentStatus.inProgress);
    expect((await b.history(id)).map((e) => e.payloadJson).join(), contains('Какой формат'));

    // «Готово» с результатом.
    await v.svc.setStatus(await v.one(id), AssignmentStatus.review, note: 'Отчёт приложен');
    await deliver();
    expect((await b.one(id)).status, AssignmentStatus.review);

    // Вернуть на доработку с пояснением — у исполнителя «В работе» и
    // пояснение в истории.
    await b.svc.setStatus(await b.one(id), AssignmentStatus.inProgress, note: 'Добавьте раздел по рискам');
    await deliver();
    expect((await v.one(id)).status, AssignmentStatus.inProgress);
    expect((await v.history(id)).map((e) => e.payloadJson).join(), contains('Добавьте раздел по рискам'));

    // Снова «Готово» — и принять.
    await v.svc.setStatus(await v.one(id), AssignmentStatus.review);
    await deliver();
    expect((await b.one(id)).status, AssignmentStatus.review);
    await b.svc.setStatus(await b.one(id), AssignmentStatus.done);
    await deliver();
    expect((await v.one(id)).status, AssignmentStatus.done);
    expect((await b.one(id)).status, AssignmentStatus.done);

    // Все письма — одной темой (одна беседа).
    expect(log.map((m) => SubjectPrefix.strip(m.subject)).toSet(), {first.subject});
  });

  test('напоминание и перенос срока — у исполнителя; статус не меняется', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Сверка', assignees: [a(vera)], due: DateTime(2026, 11, 21)))
        .single;
    await deliver();
    expect(await b.svc.remind(await b.one(id)), isTrue);
    expect(await b.svc.remind(await b.one(id)), isFalse, reason: 'повтор сразу — нет');
    await deliver();
    expect((await v.history(id)).any((e) => e.payloadJson.contains('Напоминаю')), isTrue);
    expect((await v.one(id)).status, AssignmentStatus.open);
    await b.svc.reschedule(await b.one(id), DateTime(2026, 11, 25, 15, 30));
    await deliver();
    expect((await v.one(id)).due, DateTime(2026, 11, 25, 15, 30));
  });

  test('снять поручение — у исполнителя «Снято»', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Закупка', assignees: [a(vera)])).single;
    await deliver();
    await b.svc.setStatus(await b.one(id), AssignmentStatus.cancelled);
    await deliver();
    expect((await v.one(id)).status, AssignmentStatus.cancelled);
  });

  test('ответ из другой почты словами: «Принято», «Готово» — статусы у постановщика', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Акт', assignees: [a(vera)])).single;
    final first = (await deliver()).single;
    await handReply(v, first, 'Принято');
    expect((await b.one(id)).status, AssignmentStatus.inProgress);
    await handReply(v, first, 'Готово, акт подписан');
    expect((await b.one(id)).status, AssignmentStatus.review);
  });

  test('«Задать вопрос»: письмо поручения после пересинхронизации и без писем в ящике', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Смета', assignees: [a(vera)], due: DateTime(2026, 11, 21)))
        .single;
    final first = (await deliver()).single;
    await b.svc.remind(await b.one(id));
    await deliver();

    // Ответ — на последнее письмо постановщика, которое есть в ящике.
    var q = await v.svc.questionCompose(await v.one(id));
    final inbox = await (v.db.select(v.db.emails)..where((e) => e.folderId.equals('in'))).get();
    expect(q['replyToId'], inbox.last.id);

    // Exchange пересинхронизировал папку: те же письма под новыми номерами.
    final before = (await v.history(id)).length;
    await v.db.delete(v.db.emails).go();
    for (final m in inbox) {
      await v.db.into(v.db.emails).insert(m.copyWith(id: 'new-${m.id}').toCompanion(true));
    }
    await AssignmentStore.scan(v.db, v.mine, since: DateTime.now().subtract(const Duration(days: 1)));
    expect((await v.history(id)).length, before, reason: 'история не задваивается');
    expect((await v.one(id)).row.sourceEmailId, 'new-${inbox.first.id}', reason: 'письмо-основание — новое');
    q = await v.svc.questionCompose(await v.one(id));
    expect(q['replyToId'], startsWith('new-'));

    // Писем поручения в ящике нет — новое письмо постановщику: тема беседы и
    // номер поручения; ответ привязывается к поручению.
    await v.db.delete(v.db.emails).go();
    q = await v.svc.questionCompose(await v.one(id));
    expect(q['replyToId'], isNull);
    expect(q['to'], boss);
    expect(q['subject'], 'Re: ${first.subject}');
    expect(q['quick'], contains('OGN-$id'));
    queue.add(_Mail(vera, [a(boss)], const [], q['subject']!, '<div>${q['quick']} Нужна ли разбивка по месяцам?</div>', null));
    await deliver();
    expect((await b.history(id)).map((e) => e.payloadJson).join(), contains('разбивка по месяцам'));
    expect((await b.one(id)).status, AssignmentStatus.open);
  });

  test('ответ словами из обычного редактора меняет статус и у самого отправившего', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Договор', assignees: [a(vera)])).single;
    final first = (await deliver()).single;
    // Исполнитель ответил «Принято» обычным письмом — «В работе» у обоих.
    await handReply(v, first, 'Принято, займусь сегодня');
    expect((await b.one(id)).status, AssignmentStatus.inProgress);
    expect((await v.one(id)).status, AssignmentStatus.inProgress);
    await handReply(v, first, 'Готово, договор согласован');
    expect((await b.one(id)).status, AssignmentStatus.review);
    expect((await v.one(id)).status, AssignmentStatus.review);
    // Постановщик ответил «Принято, спасибо» обычным письмом — «Выполнено» у обоих.
    final last = log.lastWhere((m) => m.from == vera);
    await handReply(b, last, 'Принято, спасибо');
    expect((await v.one(id)).status, AssignmentStatus.done);
    expect((await b.one(id)).status, AssignmentStatus.done);
  });

  test('разбор порциями: больше 500 писем поручений — свежие тоже разбираются', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final acc = b.c.read(accountsProvider).first;
    final id = (await b.svc.create(account: acc, title: 'Склад', assignees: [a(vera)])).single;
    await deliver();
    // 520 старых писем с номером другого поручения.
    for (var i = 0; i < 520; i++) {
      await b.db.into(b.db.emails).insert(EmailsCompanion.insert(
            id: 'old$i',
            accountId: 'a',
            folderId: 'in',
            fromEmail: 'x@corp.ru',
            toRecipients: '[]',
            subject: 'Письмо $i',
            bodyHtml: const Value('<div>OGN-ZZZZZZZZZZZZ</div>'),
            receivedAt: DateTime.now().subtract(const Duration(hours: 3)),
          ));
    }
    await v.svc.setStatus(await v.one(id), AssignmentStatus.inProgress);
    await deliver();
    expect((await b.one(id)).status, AssignmentStatus.inProgress);
  });
}
