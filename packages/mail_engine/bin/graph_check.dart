// Проверка Microsoft Graph из консоли (1.8.11): тот же GraphEngine, что в
// приложении у ящиков Exchange Online, — что выдаёт Graph этому токену.
// Только чтение: ничего не создаётся, не меняется и не удаляется.
//
//   cd packages/mail_engine
//   dart pub get
//   OGN_GRAPH_TOKEN=eyJ0... dart run bin/graph_check.dart --person anna@contoso.ru
//
// Параметры:
//   --person   адрес коллеги: карточка (People.Read, каталог) и фото
//   --tips     адреса через запятую: подсказки MailTips
//   --quiet    без журнала запросов
//
// Токен — из переменной окружения OGN_GRAPH_TOKEN (в командной строке он
// попал бы в историю оболочки). Токен Graph для своей учётной записи можно
// взять, например, в Graph Explorer (https://developer.microsoft.com/graph/graph-explorer,
// «Access token») или у своего приложения Entra:
//   POST https://login.microsoftonline.com/organizations/oauth2/v2.0/token
//   grant_type=refresh_token, scope=https://graph.microsoft.com/.default offline_access
// Права в токене — те, на которые есть согласие; по каждой проверке видно,
// какого права не хватает (403 — нет права, функция в приложении пойдёт по
// EWS или будет недоступна).

import 'dart:io';

import 'package:mail_engine/mail_engine.dart';

Future<void> main(List<String> argv) async {
  final args = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final next = i + 1 < argv.length && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
    args[a.substring(2)] = next;
  }
  if (args.containsKey('help')) {
    stdout.writeln('OGN_GRAPH_TOKEN=… dart run bin/graph_check.dart [--person адрес] [--tips адрес,адрес] [--quiet]');
    exit(0);
  }
  final token = Platform.environment['OGN_GRAPH_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('Нет токена: задайте переменную окружения OGN_GRAPH_TOKEN (см. начало файла).');
    exit(2);
  }
  final g = GraphEngine(
    tokenSource: ({bool force = false}) async => force ? null : token,
    logger: args.containsKey('quiet') ? null : DebugLog(verbose: false),
  );

  Future<void> check(String what, String right, Future<String> Function() f) async {
    try {
      stdout.writeln('✓ $what: ${await f()}');
    } on GraphException catch (e) {
      final hint = e.status == 403 || e.status == 0 ? ' — нет права $right' : '';
      stdout.writeln('✗ $what: $e$hint');
    } catch (e) {
      stdout.writeln('✗ $what: $e');
    }
  }

  await check('своя карточка', 'User.Read', () async {
    final u = await g.me();
    return u == null ? 'пусто' : '${u.displayName} <${u.email}>${u.jobTitle == null ? '' : ', ${u.jobTitle}'}';
  });
  await check('категории Outlook', 'MailboxSettings.Read', () async {
    final list = await g.masterCategories();
    return '${list.length}${list.isEmpty ? '' : ' (${list.take(5).map((c) => c.name).join(', ')}…)'}';
  });
  await check('правила «Входящих»', 'MailboxSettings.ReadWrite', () async {
    final list = await g.rules();
    return '${list.length}${list.isEmpty ? '' : ' (${list.take(5).map((r) => r.name).join(', ')})'}';
  });
  await check('папки почты', 'Mail.ReadWrite', () async => '${(await g.mailFolders()).length}');
  await check('восстановить удалённые', 'Mail.ReadWrite', () async => '${(await g.recoverableItems(max: 10)).length} писем');
  await check('списки переговорных', 'Place.Read.All (администратор)', () async => '${(await g.roomLists()).length}');
  final person = args['person'];
  if (person != null && person.contains('@')) {
    await check('карточка $person', 'People.Read / User.Read.All', () async {
      final u = await g.person(person);
      if (u == null) return 'не найден';
      return [u.displayName, u.jobTitle, u.department, u.office, u.businessPhone, if (u.manager != null) 'руководитель ${u.manager}']
          .whereType<String>()
          .join(', ');
    });
    await check('фото $person', 'User.ReadBasic.All', () async {
      final b = await g.photo(person);
      return b == null ? 'нет фото' : '${b.length} байт';
    });
  }
  final tips = args['tips'];
  if (tips != null && tips.contains('@')) {
    await check('MailTips', 'Mail.Read', () async {
      final list = await g.mailTips(tips.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
      return list
          .map((t) => '${t.email}${t.autoReply == null ? '' : ' — автоответ'}${t.mailboxFull ? ' — ящик полон' : ''}'
              '${t.totalMembers == null ? '' : ' — ${t.totalMembers} получателей'}')
          .join('; ');
    });
  }
}
