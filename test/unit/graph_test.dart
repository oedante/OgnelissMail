// Microsoft Graph для Exchange Online (1.8.10): разбор ответов Graph,
// правила сервера, согласие при входе и клиент запросов (сеть подменена).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/graph/graph_client.dart';
import 'package:ogneliss/services/mail/graph/graph_directory.dart';
import 'package:ogneliss/services/mail/graph/graph_server_tools.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';
import 'package:ogneliss/services/mail/sieve/sieve_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccountModel _exo({String id = 'a1'}) => AccountModel(
      id: id,
      type: AccountType.activesync,
      email: 'ivan@contoso.example',
      displayName: 'Иван',
      username: 'ivan@contoso.example',
      exchangeServer: 'outlook.office365.com',
      exchangeAuthMethod: ExchangeAuthMethod.bearer,
      createdAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('вход: согласие на Graph', () {
    test('отказ из-за прав — повтор без Graph; отмена и прочее — нет', () {
      expect(DirectOAuth.isConsentError('access_denied', 'AADSTS65004: User declined to consent'), isTrue);
      expect(DirectOAuth.isConsentError('access_denied', 'AADSTS90094: admin approval required'), isTrue);
      expect(DirectOAuth.isConsentError('consent_required', null), isTrue);
      expect(DirectOAuth.isConsentError('invalid_scope', null), isTrue);
      expect(DirectOAuth.isConsentError('access_denied', null), isFalse);
      expect(DirectOAuth.isConsentError('server_error', 'AADSTS50020'), isFalse);
    });

    test('клиент токена Graph — только у входа Exchange Online', () {
      final c = DirectOAuth.graphClient('exchange|11111111-2222');
      expect(c, isNotNull);
      expect(c!.clientId, '11111111-2222');
      expect(c.scopes, contains('https://graph.microsoft.com/.default'));
      expect(c.tokenEndpoint.toString(), contains('/organizations/'));
      expect(DirectOAuth.graphClient('microsoft|x'), isNull);
      expect(DirectOAuth.graphClient('google|x'), isNull);
    });

    test('права при входе — без согласия администратора', () {
      final s = DirectOAuth.graphConsentScopes.join(' ');
      expect(s, isNot(contains('Place.Read.All')));
      expect(s, isNot(contains('GroupMember.Read.All')));
      expect(s, isNot(contains('User.Read.All')));
      expect(s, contains('MailboxSettings.ReadWrite'));
    });
  });

  group('адресная книга Graph', () {
    test('пользователь каталога → контакт', () {
      final c = GraphDirectory.contactFromUser({
        'displayName': 'Смирнова Анна Петровна',
        'givenName': 'Анна',
        'surname': 'Смирнова',
        'mail': 'Anna.Smirnova@contoso.example',
        'jobTitle': 'Инженер',
        'department': 'Отдел эксплуатации',
        'companyName': 'Контосо',
        'officeLocation': 'к. 12',
        'businessPhones': ['+7 495 000-00-01'],
        'mobilePhone': '+7 900 000-00-02',
      }, accountId: 'a1')!;
      expect(c.email, 'anna.smirnova@contoso.example');
      expect(c.jobTitle, 'Инженер');
      expect(c.department, 'Отдел эксплуатации');
      expect(c.company, 'Контосо');
      expect(c.office, 'к. 12');
      expect(c.phoneWork, '+7 495 000-00-01');
      expect(c.phoneMobile, '+7 900 000-00-02');
      expect(GraphDirectory.contactFromUser({'displayName': 'Без адреса'}), isNull);
    });

    test('люди: нужный адрес, сотрудник организации — раньше личного контакта', () {
      final p = GraphDirectory.pickPerson([
        {
          'displayName': 'Анна (личный контакт)',
          'scoredEmailAddresses': [
            {'address': 'anna@contoso.example'}
          ],
          'personType': {'class': 'Person', 'subclass': 'PersonalContact'},
        },
        {
          'displayName': 'Смирнова Анна',
          'jobTitle': 'Инженер',
          'department': 'Эксплуатация',
          'scoredEmailAddresses': [
            {'address': 'Anna@contoso.example'}
          ],
          'phones': [
            {'type': 'business', 'number': '101'},
            {'type': 'mobile', 'number': '+7 900'}
          ],
          'personType': {'class': 'Person', 'subclass': 'OrganizationUser'},
        },
        {
          'displayName': 'Другой',
          'scoredEmailAddresses': [
            {'address': 'other@contoso.example'}
          ],
        },
      ], 'anna@contoso.example')!;
      expect(p.displayName, 'Смирнова Анна');
      expect(p.department, 'Эксплуатация');
      expect(p.phoneWork, '101');
      expect(p.phoneMobile, '+7 900');
      expect(GraphDirectory.pickPerson(const [], 'x@y.z'), isNull);
    });

    test('MailTips: автоответ без разметки, переполненный ящик, рассылка', () {
      final tips = GraphDirectory.parseMailTips({
        'value': [
          {
            'emailAddress': {'address': 'Anna@contoso.example', 'name': 'Анна'},
            'automaticReplies': {'message': '<html><body><p>В отпуске до 10&nbsp;ноября</p></body></html>'},
            'mailboxFull': false,
          },
          {
            'emailAddress': {'address': 'all@contoso.example'},
            'automaticReplies': {'message': ''},
            'totalMemberCount': 120,
            'externalMemberCount': 3,
          },
          {
            'emailAddress': {'address': 'full@contoso.example'},
            'mailboxFull': true,
          },
        ]
      });
      expect(tips.length, 3);
      expect(tips[0].email, 'anna@contoso.example');
      expect(tips[0].autoReply, 'В отпуске до 10 ноября');
      expect(tips[1].autoReply, isNull);
      expect(tips[1].isBigList, isTrue);
      expect(tips[1].hasExternal, isTrue);
      expect(tips[2].mailboxFull, isTrue);
      expect(GraphDirectory.parseMailTips(null), isEmpty);
    });

    test('переговорные и категории', () {
      final rooms = GraphDirectory.parsePlaces([
        {'displayName': 'Переговорная 3.1', 'emailAddress': 'room31@contoso.example'},
        {'displayName': 'Без адреса'},
      ]);
      expect(rooms.single.email, 'room31@contoso.example');
      expect(rooms.single.name, 'Переговорная 3.1');
      final cats = GraphDirectory.parseCategories([
        {'displayName': 'Красная', 'color': 'preset0'},
        {'displayName': 'Синяя', 'color': 'preset7'},
        {'displayName': 'Без цвета', 'color': 'none'},
      ]);
      expect(cats.map((c) => c.color).toList(), [0, 7, -1]);
    });
  });

  group('правила сервера Graph', () {
    test('список: действия, только чтение, порядок', () {
      final rules = GraphServerTools.parseRules([
        {
          'id': 'r2',
          'displayName': 'Рассылки',
          'sequence': 2,
          'isEnabled': false,
          'actions': {'moveToFolder': 'AAMk…', 'stopProcessingRules': true, 'markAsRead': false},
        },
        {
          'id': 'r1',
          'displayName': 'Начальник',
          'sequence': 1,
          'isEnabled': true,
          'isReadOnly': true,
          'hasError': true,
          'actions': {
            'forwardTo': [
              {
                'emailAddress': {'address': 'x@y.z'}
              }
            ],
            'assignCategories': <String>[],
          },
        },
      ]);
      expect(rules.map((r) => r.id).toList(), ['r1', 'r2']);
      expect(rules[0].readOnly, isTrue);
      expect(rules[0].inError, isTrue);
      expect(rules[0].actions, ['forward']);
      expect(rules[1].enabled, isFalse);
      expect(rules[1].actions.toSet(), {'move', 'stop'});
    });

    test('новое правило: условие и действие', () {
      final b = GraphServerTools.ruleBody(
          const SieveRule(name: '', field: SieveField.from, op: SieveOp.isExactly, value: 'boss@x.y', action: SieveAction.forward, arg: 'me@home.example'),
          3);
      expect(b['displayName'], 'boss@x.y');
      expect(b['sequence'], 3);
      expect(jsonEncode(b['conditions']), '{"fromAddresses":[{"emailAddress":{"address":"boss@x.y"}}]}');
      expect(jsonEncode(b['actions']), '{"forwardTo":[{"emailAddress":{"address":"me@home.example"}}]}');

      final d = GraphServerTools.ruleBody(
          const SieveRule(name: 'Спам', field: SieveField.subject, value: 'акция', action: SieveAction.delete), 0);
      expect(d['sequence'], 1);
      expect(jsonEncode(d['conditions']), '{"subjectContains":["акция"]}');
      expect(jsonEncode(d['actions']), '{"delete":true,"stopProcessingRules":true}');

      final m = GraphServerTools.ruleBody(
          const SieveRule(name: 'В папку', field: SieveField.to, value: 'team', action: SieveAction.move, arg: 'F1', stop: true), 2);
      expect(jsonEncode(m['conditions']), '{"recipientContains":["team"]}');
      expect(jsonEncode(m['actions']), '{"moveToFolder":"F1","stopProcessingRules":true}');

      final r = GraphServerTools.ruleBody(
          const SieveRule(name: 'x', field: SieveField.any, value: 'счёт', action: SieveAction.markRead), 1);
      expect(jsonEncode(r['conditions']), '{"bodyOrSubjectContains":["счёт"]}');
      expect(jsonEncode(r['actions']), '{"markAsRead":true}');
    });

    test('восстановить удалённые: список писем', () {
      final items = GraphServerTools.parseRecoverable([
        {
          'id': 'm1',
          'subject': 'Смета',
          'from': {
            'emailAddress': {'name': 'Анна', 'address': 'anna@x.y'}
          },
          'receivedDateTime': '2026-10-20T07:30:00Z',
        },
        {'subject': 'без id'},
      ]);
      expect(items.single.id, 'm1');
      expect(items.single.from, 'Анна');
      expect(items.single.isMail, isTrue);
      expect(items.single.received!.toUtc(), DateTime.utc(2026, 10, 20, 7, 30));
    });
  });

  group('клиент Graph', () {
    late SharedPreferences prefs;
    late SecureStorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      FlutterSecureStorage.setMockInitialValues({
        'oc_a1': 'exchange|client-id',
        'rt_a1': 'refresh',
        'gat_a1': 'graph-token',
        'gexp_a1': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      });
      storage = SecureStorageService();
    });

    test('запрос с токеном, все страницы списка', () async {
      final seen = <String>[];
      final client = GraphClient(storage, prefs, httpClient: MockClient((req) async {
        seen.add('${req.method} ${req.url.path}?${req.url.query}');
        expect(req.headers['Authorization'], 'Bearer graph-token');
        if (req.url.queryParameters.containsKey(r'$skiptoken')) {
          return http.Response(jsonEncode({'value': [{'id': 'r2'}]}), 200);
        }
        return http.Response(
            jsonEncode({
              'value': [{'id': 'r1'}],
              '@odata.nextLink': '${GraphClient.base}/me/mailFolders/inbox/messageRules?\$skiptoken=2',
            }),
            200);
      }));
      final list = await client.list(_exo(), '/me/mailFolders/inbox/messageRules');
      expect(list.map((r) => r['id']).toList(), ['r1', 'r2']);
      expect(seen.length, 2);
    });

    test('ошибка Graph — код и текст; 404 у фото — «нет фото»', () async {
      final client = GraphClient(storage, prefs, httpClient: MockClient((req) async {
        if (req.url.path.endsWith(r'$value')) return http.Response('', 404);
        return http.Response(jsonEncode({'error': {'code': 'ErrorAccessDenied', 'message': 'Access is denied.'}}), 403);
      }));
      expect(await client.getBytes(_exo(), '/me/photo/\$value'), isNull);
      await expectLater(
        client.get(_exo(), '/places/microsoft.graph.roomlist'),
        throwsA(isA<GraphException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.code, 'code', 'ErrorAccessDenied')
            .having((e) => e.forbidden, 'forbidden', isTrue)),
      );
    });

    test('не Exchange Online — Graph нет, запрос не уходит', () async {
      var calls = 0;
      final client = GraphClient(storage, prefs, httpClient: MockClient((req) async {
        calls++;
        return http.Response('{}', 200);
      }));
      final imap = AccountModel(
          id: 'a2', type: AccountType.imap, email: 'x@y.z', displayName: 'x', username: 'x', createdAt: DateTime(2026));
      expect(client.supports(imap), isFalse);
      await expectLater(client.get(imap, '/me'), throwsA(isA<GraphException>().having((e) => e.status, 'status', 0)));
      expect(calls, 0);
      expect(client.access(imap), GraphAccess.unknown);
    });

    test('отказ в согласии — пауза, «нет согласия»; сброс — заново', () async {
      await prefs.setString('graph_state_a1', 'noconsent:${DateTime.now().millisecondsSinceEpoch}');
      final client = GraphClient(storage, prefs, httpClient: MockClient((req) async => http.Response('{}', 200)));
      expect(client.access(_exo()), GraphAccess.noConsent);
      expect(await client.token(_exo()), isNull);
      await client.reset('a1');
      expect(client.access(_exo()), GraphAccess.unknown);
    });
  });
}
