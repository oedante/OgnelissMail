// Изменение поручений и проектов, общий план с ходом работ, права
// постановщика (просьба владельца 13.11.2026). Сквозная проверка: у каждого
// участника — свой телефон (своя база), письма сервиса доставляются
// остальным, разбор — как после синхронизации.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show accountsProvider;
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
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
  _Mail(this.from, this.to, this.cc, this.subject, this.html);
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
    sink(_Mail(me, to, cc, subject, bodyHtml));
    return true;
  }
}

class _NoReminders extends ReminderSchedulerService {
  _NoReminders(AppDatabase db) : super(db, NotificationService());
  @override
  Future<void> rescheduleAll({bool force = false}) async {}
}

/// Телефон участника: своя база, свой контейнер, свои письма.
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
  Future<AssignmentView?> find(String id) async => (await all()).where((v) => v.id == id).firstOrNull;
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await AppLocalizations.load('ru');
  });

  const boss = 'boss@corp.ru';
  const vera = 'vera@corp.ru';
  const dmitry = 'dmitry@corp.ru';
  const zam = 'zam@corp.ru';
  final names = {boss: 'Иван Петрович', vera: 'Вера', dmitry: 'Дмитрий', zam: 'Зам Начальника'};

  late Map<String, _Phone> phones;
  final queue = <_Mail>[];
  var n = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'s_locale': 'ru'});
    final prefs = await SharedPreferences.getInstance();
    queue.clear();
    phones = {for (final e in names.entries) e.key: _Phone(e.key, e.value)};
    for (final p in phones.values) {
      await p.db.into(p.db.accounts).insert(AccountsCompanion.insert(
          id: 'a', type: 7, email: p.email, displayName: p.name, username: p.email, createdAt: DateTime(2026)));
      await p.db.into(p.db.folders).insert(
          FoldersCompanion.insert(id: 'in', accountId: 'a', displayName: 'Входящие', type: Value(FolderType.inbox.index)));
      p.c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(p.db),
        sharedPrefsProvider.overrideWithValue(prefs),
        offlineSendProvider.overrideWith((ref) => _Outbox(ref, p.email, queue.add)),
        reminderSchedulerProvider.overrideWith((ref) => _NoReminders(p.db)),
      ]);
      p.c.read(accountsProvider);
    }
    // Ящики загружаются из базы асинхронно.
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

  /// Доставить отправленные письма получателям и разобрать почту у всех.
  /// [strip] — почтовый сервер вырезает скрытые отметки (пустые элементы
  /// с атрибутами data-ogneliss-*), как у владельца 13.11.2026.
  Future<List<_Mail>> deliver({bool strip = false}) async {
    final sent = [...queue];
    queue.clear();
    final cut = RegExp(r'<span data-ogneliss-[^>]*></span>');
    for (final m in sent) {
      for (final p in phones.values) {
        if (!m.rcpt.contains(p.email)) continue;
        await p.db.into(p.db.emails).insert(EmailsCompanion.insert(
              id: 'm${n++}',
              accountId: 'a',
              folderId: 'in',
              fromEmail: m.from,
              fromName: Value(names[m.from]),
              toRecipients: json(m.to),
              ccJson: Value(json(m.cc)),
              subject: m.subject,
              bodyHtml: Value(strip ? m.html.replaceAll(cut, '') : m.html),
              receivedAt: DateTime.now().add(Duration(microseconds: n)),
            ));
      }
    }
    for (final p in phones.values) {
      await AssignmentStore.scan(p.db, p.mine, since: DateTime.now().subtract(const Duration(days: 1)));
    }
    return sent;
  }

  EmailAddress a(String e) => EmailAddress(email: e, displayName: names[e]);
  AccountModel acc(_Phone p) => p.c.read(accountsProvider).first;

  Future<String> project({int visibility = 0}) async {
    final d = ProjectDraft(
      title: 'Ремонт склада',
      start: DateTime(2026, 11, 16),
      visibility: visibility,
      stages: [
        StageDraft(title: 'Смета', executor: a(vera), start: DateTime(2026, 11, 16), due: DateTime(2026, 11, 18)),
        StageDraft(
            title: 'Закупка', executor: a(dmitry), start: DateTime(2026, 11, 19), due: DateTime(2026, 11, 21), after: 0),
      ],
    );
    final id = await phones[boss]!.svc.createProject(acc(phones[boss]!), d);
    await deliver();
    return id;
  }

  test('участники видят весь план: кто что и после кого делает, статусы этапов', () async {
    final pid = await project();
    final v = phones[vera]!, d = phones[dmitry]!;
    final pv = await d.one(pid);
    final plan = PlanStage.decode(pv.row.planJson);
    expect(plan.map((s) => s.title), ['Смета', 'Закупка']);
    expect(plan.first.assigneeName, 'Вера');
    expect(plan.last.after, plan.first.id);
    expect(plan.first.status, AssignmentStatus.open);
    // Дмитрий — только свой этап; этап Веры — в плане.
    expect((await d.all()).where((x) => !x.isProject).map((x) => x.row.title), ['Закупка']);
    // Сразу после создания план уже у всех — «Ход работ» не нужен.
    await phones[boss]!.svc.dispatchPending();
    expect(queue, isEmpty);

    // Вера взяла в работу → у постановщика статус → ход работ всем.
    final s1 = (await v.all()).firstWhere((x) => x.row.title == 'Смета');
    await v.svc.setStatus(s1, AssignmentStatus.inProgress);
    await deliver();
    await phones[boss]!.svc.dispatchPending();
    final sent = await deliver();
    expect(sent.single.rcpt, containsAll([vera, dmitry]));
    final after = PlanStage.decode((await d.one(pid)).row.planJson);
    expect(after.first.status, AssignmentStatus.inProgress);
    // Без новых изменений — писем нет.
    await phones[boss]!.svc.dispatchPending();
    expect(queue, isEmpty);
  });

  test('видимость «только свои этапы»: плана у участников нет', () async {
    final pid = await project(visibility: 1);
    final pv = await phones[dmitry]!.one(pid);
    expect(pv.row.planJson, isNull);
    expect(pv.row.visibility, 1);
    final s1 = (await phones[vera]!.all()).firstWhere((x) => x.row.title == 'Смета');
    await phones[vera]!.svc.setStatus(s1, AssignmentStatus.inProgress);
    await deliver();
    await phones[boss]!.svc.dispatchPending();
    expect(queue, isEmpty, reason: 'ход работ не рассылается');
  });

  test('изменение этапа: срок, чек-лист, наблюдатель — у исполнителя; отметки сохраняются', () async {
    final pid = await project();
    final b = phones[boss]!, d = phones[dmitry]!;
    final s2 = (await b.all()).firstWhere((x) => x.row.title == 'Закупка');
    await AssignmentStore.update(d.db, s2.id, checklist: const [ChecklistItem('Цемент', done: true)]);
    final changed = await b.svc.editTask(
        s2,
        StageDraft(
            title: 'Закупка материалов',
            executor: a(dmitry),
            start: DateTime(2026, 11, 19),
            due: DateTime(2026, 11, 25),
            observers: [a(zam)],
            checklist: ['Цемент', 'Песок']),
        afterId: s2.row.afterId);
    expect(changed, isTrue);
    final mails = await deliver();
    expect(mails.single.html, contains('Закупка материалов'));
    final mine = await d.one(s2.id);
    expect(mine.row.title, 'Закупка материалов');
    expect(mine.due, DateTime(2026, 11, 25));
    expect(mine.checklist.map((c) => '${c.text}:${c.done}'), ['Цемент:true', 'Песок:false']);
    expect(mine.observers.single.email, zam);
    expect(mine.row.afterId, s2.row.afterId);
    expect((await AssignmentStore.events(d.db, s2.id)).last.type, 'edited');
    // Наблюдатель тоже видит этап.
    expect((await phones[zam]!.one(s2.id)).iObserve, isTrue);
    // Без изменений — письма нет.
    expect(
        await b.svc.editTask(await b.one(s2.id),
            StageDraft(
                title: 'Закупка материалов',
                executor: a(dmitry),
                start: DateTime(2026, 11, 19),
                due: DateTime(2026, 11, 25),
                observers: [a(zam)],
                checklist: ['Цемент', 'Песок']),
            afterId: s2.row.afterId),
        isFalse);
    expect(queue, isEmpty);
    expect(pid, isNotEmpty);
  });

  test('смена исполнителя: прежнему — снято, новому — поручение; старые сведения не применяются', () async {
    final b = phones[boss]!, v = phones[vera]!, d = phones[dmitry]!;
    final ids = await b.svc.create(account: acc(b), title: 'Отчёт', assignees: [a(vera)], due: DateTime(2026, 11, 20));
    await deliver();
    final id = ids.single;
    final oldHtml = (await v.db.select(v.db.emails).get()).single.bodyHtml!;
    await b.svc.editTask(await b.one(id), StageDraft(title: 'Отчёт за квартал', executor: a(dmitry), due: DateTime(2026, 11, 22)),
        afterId: null);
    final m = await deliver();
    expect(m.single.rcpt, containsAll([vera, dmitry]));
    expect((await v.one(id)).status, AssignmentStatus.cancelled);
    final dv = await d.one(id);
    expect(dv.iExecute, isTrue);
    expect(dv.row.title, 'Отчёт за квартал');
    expect(dv.due, DateTime(2026, 11, 22));
    // Повтор старого письма постановщика (первое поручение) ничего не меняет.
    queue.add(_Mail(boss, [a(dmitry)], const [], 'Поручение: Отчёт', oldHtml));
    await deliver();
    expect((await d.one(id)).row.title, 'Отчёт за квартал');
  });

  test('изменение проекта: новый этап, удалённый этап, название — у всех', () async {
    final pid = await project();
    final b = phones[boss]!, d = phones[dmitry]!, v = phones[vera]!;
    final p = await b.one(pid);
    final list = await b.svc.stages(pid);
    final draft = ProjectDraft(
      title: 'Ремонт склада №2',
      start: p.start,
      stages: [
        StageDraft(id: list[0].id, title: 'Смета', executor: a(vera), start: list[0].start, due: list[0].due),
        StageDraft(title: 'Монтаж', executor: a(vera), start: DateTime(2026, 11, 22), due: DateTime(2026, 11, 24), after: 0),
      ],
    );
    await b.svc.updateProject(p, draft);
    await deliver();
    // Этап Дмитрия удалён: у него снят и убран из списка.
    expect(await d.find(list[1].id), isNull);
    final removed = await AssignmentStore.byId(d.db, list[1].id);
    expect(removed!.status, AssignmentStatus.cancelled);
    expect(removed.isArchived, isTrue);
    // У Веры — новый этап и новое название проекта, план — без удалённого.
    expect((await v.all()).where((x) => !x.isProject).map((x) => x.row.title), containsAll(['Смета', 'Монтаж']));
    final pv = await v.one(pid);
    expect(pv.row.title, 'Ремонт склада №2');
    expect(PlanStage.decode(pv.row.planJson).map((s) => s.title), ['Смета', 'Монтаж']);
    expect((await AssignmentStore.events(v.db, pid)).map((e) => e.type), contains('edited'));
  });

  test('заместитель: этапы целиком, те же права; ответы исполнителя — и ему', () async {
    final pid = await project();
    final b = phones[boss]!, v = phones[vera]!, z = phones[zam]!;
    await b.svc.grantRights(await b.one(pid), a(zam));
    final mails = await deliver();
    expect(mails.length, 2, reason: 'заместителю — полные сведения, остальным — кто с правами');
    final zp = await z.one(pid);
    expect(zp.outgoing, isTrue);
    expect(zp.iDeputy, isTrue);
    expect(zp.iOwn, isFalse);
    final zs = (await z.all()).where((x) => x.parentId == pid).toList();
    expect(zs.map((x) => x.row.title), containsAll(['Смета', 'Закупка']));
    expect(zs.every((x) => x.outgoing), isTrue);
    expect(zs.firstWhere((x) => x.row.title == 'Смета').assignee!.email, vera);
    // У Веры этап знает заместителя: её «Готово» — и ему.
    final s1 = (await v.all()).firstWhere((x) => x.row.title == 'Смета');
    expect(s1.deputies.single.email, zam);
    await v.svc.setStatus(s1, AssignmentStatus.review);
    final ready = await deliver();
    expect(ready.first.rcpt, containsAll([boss, zam]));
    // Заместитель принимает работу — у Веры и у постановщика «Выполнено».
    await z.svc.setStatus(await z.one(s1.id), AssignmentStatus.done);
    // «Можно начинать» уходит следом, не задерживая «Принять».
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await deliver();
    expect((await v.one(s1.id)).status, AssignmentStatus.done);
    expect((await b.one(s1.id)).status, AssignmentStatus.done);
    // «Можно начинать» следующему этапу — от заместителя (он принял).
    expect((await phones[dmitry]!.all()).firstWhere((x) => x.row.title == 'Закупка').waiting, isFalse);
  });

  test('передача прав полностью (смена вахты): постановщик — новый, прежний — наблюдатель', () async {
    final pid = await project();
    final b = phones[boss]!, v = phones[vera]!, z = phones[zam]!;
    await b.svc.grantRights(await b.one(pid), a(zam), handover: true);
    await deliver();
    expect((await z.one(pid)).iOwn, isTrue);
    final s1 = (await v.all()).firstWhere((x) => x.row.title == 'Смета');
    expect(s1.row.ownerEmail, zam);
    expect((await v.one(pid)).row.ownerEmail, zam);
    final bp = await b.one(pid);
    expect(bp.outgoing, isFalse);
    expect(bp.iOwn, isFalse);
    // Ответ Веры — новому постановщику.
    await v.svc.setStatus(s1, AssignmentStatus.inProgress);
    final m = await deliver();
    expect(m.single.to.map((x) => x.email), contains(zam));
    expect((await z.one(s1.id)).status, AssignmentStatus.inProgress);
  });

  test('снять права заместителя: он — наблюдатель, кнопок постановщика нет', () async {
    final pid = await project();
    final b = phones[boss]!, z = phones[zam]!;
    await b.svc.grantRights(await b.one(pid), a(zam));
    await deliver();
    await b.svc.revokeRights(await b.one(pid), zam);
    await deliver();
    final zp = await z.one(pid);
    expect(zp.outgoing, isFalse);
    final zs = (await z.all()).where((x) => x.parentId == pid);
    expect(zs.every((x) => !x.outgoing && !x.iExecute), isTrue);
    expect(zs.every((x) => x.myRoles.contains(AssignmentRole.observer)), isTrue);
  });

  test('сервер вырезал скрытые отметки: статус и срок — по коду у номера OGN-…-X', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final id = (await b.svc.create(account: acc(b), title: 'Отчёт', assignees: [a(vera)], due: DateTime(2026, 11, 20)))
        .single;
    await deliver();
    await v.svc.setStatus(await v.one(id), AssignmentStatus.review);
    final r = await deliver(strip: true);
    expect(r.single.html, contains('OGN-$id-R'));
    expect((await b.one(id)).status, AssignmentStatus.review);
    // Постановщик принял работу — у исполнителя поручение закрылось.
    await b.svc.setStatus(await b.one(id), AssignmentStatus.done);
    final d = await deliver(strip: true);
    expect(d.single.html, contains('OGN-$id-D'));
    expect((await v.one(id)).status, AssignmentStatus.done);
  });

  test('новый срок со временем — по коду T, без отметки', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final id = (await b.svc.create(account: acc(b), title: 'Отчёт', assignees: [a(vera)], due: DateTime(2026, 11, 20)))
        .single;
    await deliver();
    await b.svc.reschedule(await b.one(id), DateTime(2026, 11, 21, 15, 30));
    final m = await deliver(strip: true);
    expect(m.single.html, contains('OGN-$id-T20261121T1530'));
    expect((await v.one(id)).due, DateTime(2026, 11, 21, 15, 30));
  });

  test('код из цитаты чужого письма не меняет статус; «Принято» постановщика словами — выполнено', () async {
    final b = phones[boss]!, v = phones[vera]!;
    final id = (await b.svc.create(account: acc(b), title: 'Отчёт', assignees: [a(vera)])).single;
    await deliver();
    await v.svc.setStatus(await v.one(id), AssignmentStatus.review);
    await deliver();
    // Постановщик отвечает из другой почты: слова, ниже — цитата с «OGN-…-W».
    queue.add(_Mail(boss, [a(vera)], const [], 'Re: Поручение: Отчёт',
        '<p>Принято, спасибо!</p><blockquote>Принято<br>OGN-$id-W</blockquote>'));
    await deliver();
    expect((await v.one(id)).status, AssignmentStatus.done);
  });

  test('код действия: туда и обратно', () {
    expect(AssignmentCodec.tag('ABCDEFGHJKMN', AssignmentAct.accepted), 'OGN-ABCDEFGHJKMN-D');
    final x = AssignmentCodec.actionFromText('Готово OGN-ABCDEFGHJKMN-R и ещё OGN-BCDEFGHJKMNP-D')!;
    expect((x.id, x.act, x.arg), ('ABCDEFGHJKMN', 'R', null));
    final t = AssignmentCodec.actionFromText('OGN-ABCDEFGHJKMN-T20261121T0905')!;
    expect(AssignmentAct.dueFrom(t.arg), DateTime(2026, 11, 21, 9, 5));
    expect(AssignmentAct.dueCode(DateTime(2026, 11, 21)), 'T20261121');
    // Старый номер без кода и старые версии: код находится по первому номеру.
    expect(AssignmentCodec.actionFromText('OGN-ABCDEFGHJKMN'), isNull);
    expect(AssignmentCodec.idFromBody('OGN-ABCDEFGHJKMN-D'), 'ABCDEFGHJKMN');
  });

  test('удаление этапа отметкой и разбор без приложения: rm=1', () {
    final html = AssignmentCodec.taskMarker(id: 'ABCDEFGHJKMN', rev: 100, removed: true, owner: boss, deputies: [zam]);
    final t = AssignmentCodec.parseTask(html)!;
    expect(t.rev, 100);
    expect(t.removed, isTrue);
    expect(t.owner, boss);
    expect(t.deputies, [zam]);
  });
}

