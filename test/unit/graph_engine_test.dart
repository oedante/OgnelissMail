// Microsoft Graph в движке (packages/mail_engine, GraphEngine, 1.8.11):
// разбор ответов, тело нового правила и запросы (сеть подменена).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

void main() {
  group('разбор ответов', () {
    test('пользователь каталога', () {
      final u = GraphEngine.parseUser({
        'displayName': 'Смирнова Анна Петровна',
        'givenName': 'Анна',
        'surname': 'Смирнова',
        'mail': 'Anna.Smirnova@contoso.example',
        'jobTitle': 'Инженер',
        'department': 'Отдел эксплуатации',
        'companyName': 'Контосо',
        'officeLocation': 'к. 12',
        'businessPhones': ['', '+7 495 000-00-01'],
        'mobilePhone': '+7 900 000-00-02',
      })!;
      expect(u.email, 'anna.smirnova@contoso.example');
      expect(u.jobTitle, 'Инженер');
      expect(u.department, 'Отдел эксплуатации');
      expect(u.company, 'Контосо');
      expect(u.office, 'к. 12');
      expect(u.businessPhone, '+7 495 000-00-01');
      expect(u.mobilePhone, '+7 900 000-00-02');
      expect(u.hasPosition, isTrue);
      expect(GraphEngine.parseUser({'displayName': 'Без адреса'}), isNull);
      // Без mail — адрес входа.
      expect(GraphEngine.parseUser({'userPrincipalName': 'Ivan@contoso.example'})!.email, 'ivan@contoso.example');
    });

    test('люди: нужный адрес, сотрудник организации — раньше личного контакта', () {
      final p = GraphEngine.pickPerson([
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
      expect(p.businessPhone, '101');
      expect(p.mobilePhone, '+7 900');
      expect(GraphEngine.pickPerson(const [], 'x@y.z'), isNull);
    });

    test('слияние карточек: пустые поля — из второй, имя — полнее', () {
      const a = GraphUser(email: 'a@x.y', displayName: 'Анна', jobTitle: 'Инженер');
      const b = GraphUser(email: 'a@x.y', displayName: 'Смирнова Анна', department: 'Эксплуатация', jobTitle: 'Другая');
      final m = a.mergedWith(b);
      expect(m.displayName, 'Смирнова Анна');
      expect(m.jobTitle, 'Инженер');
      expect(m.department, 'Эксплуатация');
      expect(m.withManager('Петров').manager, 'Петров');
    });

    test('MailTips: автоответ без разметки, переполненный ящик, рассылка', () {
      final tips = GraphEngine.parseMailTips({
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
      expect(tips[0].name, 'Анна');
      expect(tips[0].autoReply, 'В отпуске до 10 ноября');
      expect(tips[1].autoReply, isNull);
      expect(tips[1].totalMembers, 120);
      expect(tips[1].externalMembers, 3);
      expect(tips[2].mailboxFull, isTrue);
      expect(GraphEngine.parseMailTips(null), isEmpty);
    });

    test('переговорные и категории', () {
      final rooms = GraphEngine.parsePlaces([
        {'displayName': 'Переговорная 3.1', 'emailAddress': 'room31@contoso.example'},
        {'displayName': 'Без адреса'},
      ]);
      expect(rooms.single.email, 'room31@contoso.example');
      expect(rooms.single.name, 'Переговорная 3.1');
      final cats = GraphEngine.parseCategories([
        {'displayName': 'Красная', 'color': 'preset0'},
        {'displayName': 'Синяя', 'color': 'preset7'},
        {'displayName': 'Без цвета', 'color': 'none'},
      ]);
      expect(cats.map((c) => c.color).toList(), [0, 7, -1]);
    });

    test('правила: действия, только чтение, порядок', () {
      final rules = GraphEngine.parseRules([
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
        {'displayName': 'без id'},
      ]);
      expect(rules.map((r) => r.id).toList(), ['r1', 'r2']);
      expect(rules[0].readOnly, isTrue);
      expect(rules[0].hasError, isTrue);
      expect(rules[0].actions, {'forward'});
      expect(rules[1].enabled, isFalse);
      expect(rules[1].actions, {'move', 'stop'});
    });

    test('письма для восстановления', () {
      final items = GraphEngine.parseMessages([
        {
          'id': 'm1',
          'subject': 'Смета',
          'from': {
            'emailAddress': {'name': 'Анна', 'address': 'anna@x.y'}
          },
          'receivedDateTime': '2026-10-20T07:30:00Z',
        },
        {
          'id': 'm2',
          'from': {
            'emailAddress': {'address': 'robot@x.y'}
          },
        },
        {'subject': 'без id'},
      ]);
      expect(items.map((m) => m.id).toList(), ['m1', 'm2']);
      expect(items[0].from, 'Анна');
      expect(items[0].received!.toUtc(), DateTime.utc(2026, 10, 20, 7, 30));
      expect(items[1].from, 'robot@x.y');
      expect(items[1].received, isNull);
    });

    test('ошибка Graph: код и текст', () {
      final e = GraphEngine.parseError('{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}');
      expect(e.code, 'ErrorAccessDenied');
      expect(e.message, 'Access is denied.');
      expect(GraphEngine.parseError('<html>').code, '');
    });
  });

  group('новое правило', () {
    test('условие и действие → messageRule', () {
      final b = const GraphRuleSpec(
              name: '',
              field: GraphRuleField.from,
              exact: true,
              value: 'boss@x.y',
              action: GraphRuleAction.forward,
              arg: 'me@home.example',
              sequence: 3)
          .toJson();
      expect(b['displayName'], 'boss@x.y');
      expect(b['sequence'], 3);
      expect(jsonEncode(b['conditions']), '{"fromAddresses":[{"emailAddress":{"address":"boss@x.y"}}]}');
      expect(jsonEncode(b['actions']), '{"forwardTo":[{"emailAddress":{"address":"me@home.example"}}]}');

      final d = const GraphRuleSpec(
              name: 'Спам', field: GraphRuleField.subject, value: 'акция', action: GraphRuleAction.delete, sequence: 0)
          .toJson();
      expect(d['sequence'], 1);
      expect(jsonEncode(d['conditions']), '{"subjectContains":["акция"]}');
      expect(jsonEncode(d['actions']), '{"delete":true,"stopProcessingRules":true}');

      final m = const GraphRuleSpec(
              name: 'В папку',
              field: GraphRuleField.to,
              value: 'team',
              action: GraphRuleAction.move,
              arg: 'F1',
              stop: true,
              sequence: 2)
          .toJson();
      expect(jsonEncode(m['conditions']), '{"recipientContains":["team"]}');
      expect(jsonEncode(m['actions']), '{"moveToFolder":"F1","stopProcessingRules":true}');

      // «Точно» у темы не бывает — «содержит».
      final r = const GraphRuleSpec(
              name: 'x', field: GraphRuleField.any, exact: true, value: 'счёт', action: GraphRuleAction.markRead)
          .toJson();
      expect(jsonEncode(r['conditions']), '{"bodyOrSubjectContains":["счёт"]}');
      expect(jsonEncode(r['actions']), '{"markAsRead":true}');
    });
  });

  group('запросы', () {
    test('токен, все страницы списка', () async {
      final seen = <String>[];
      final g = GraphEngine(
        tokenSource: ({bool force = false}) async => 'graph-token',
        httpClient: MockClient((req) async {
          seen.add(req.url.toString());
          expect(req.headers['Authorization'], 'Bearer graph-token');
          if (req.url.queryParameters.containsKey(r'$skiptoken')) {
            return http.Response(
                jsonEncode({
                  'value': [
                    {'id': 'r2', 'sequence': 2}
                  ]
                }),
                200);
          }
          return http.Response(
              jsonEncode({
                'value': [
                  {'id': 'r1', 'sequence': 1}
                ],
                '@odata.nextLink': '${GraphEngine.base}/me/mailFolders/inbox/messageRules?\$skiptoken=2',
              }),
              200);
        }),
      );
      final rules = await g.rules();
      expect(rules.map((r) => r.id).toList(), ['r1', 'r2']);
      expect(seen.length, 2);
      expect(seen.last, contains(r'$skiptoken=2'));
    });

    test('401 — новый токен (force) и повтор', () async {
      final asked = <bool>[];
      final g = GraphEngine(
        tokenSource: ({bool force = false}) async {
          asked.add(force);
          return force ? 'new' : 'old';
        },
        httpClient: MockClient((req) async => req.headers['Authorization'] == 'Bearer new'
            ? http.Response.bytes(utf8.encode(jsonEncode({'mail': 'me@contoso.example', 'displayName': 'Я'})), 200)
            : http.Response('', 401)),
      );
      final me = await g.me();
      expect(me!.email, 'me@contoso.example');
      expect(asked, [false, true]);
    });

    test('ошибка — GraphException; 404 у фото — «нет фото»', () async {
      final g = GraphEngine(
        tokenSource: ({bool force = false}) async => 't',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith(r'$value')) return http.Response('', 404);
          return http.Response(jsonEncode({'error': {'code': 'ErrorAccessDenied', 'message': 'Access is denied.'}}), 403);
        }),
      );
      expect(await g.photo('anna@contoso.example'), isNull);
      await expectLater(
        g.roomLists(),
        throwsA(isA<GraphException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.code, 'code', 'ErrorAccessDenied')
            .having((e) => e.forbidden, 'forbidden', isTrue)),
      );
    });

    test('429 с Retry-After — одна повторная попытка (1.8.13)', () async {
      var calls = 0;
      final g = GraphEngine(
        tokenSource: ({bool force = false}) async => 't',
        httpClient: MockClient((req) async {
          calls++;
          if (calls == 1) return http.Response('', 429, headers: {'retry-after': '0'});
          return http.Response.bytes(utf8.encode(jsonEncode({'mail': 'me@contoso.example'})), 200);
        }),
      );
      expect((await g.me())!.email, 'me@contoso.example');
      expect(calls, 2);
      expect(GraphEngine.retryDelay(429, '120'), const Duration(seconds: 30));
      expect(GraphEngine.retryDelay(503, null), const Duration(seconds: 2));
      expect(GraphEngine.retryDelay(404, '5'), isNull);
    });

    test('нет токена — запрос не уходит', () async {
      var calls = 0;
      final g = GraphEngine(
        tokenSource: ({bool force = false}) async => null,
        httpClient: MockClient((req) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(g.me(), throwsA(isA<GraphException>().having((e) => e.status, 'status', 0)));
      expect(calls, 0);
    });

    test('правило: включить — только isEnabled; восстановить — во «Входящие»', () async {
      final sent = <String>[];
      final g = GraphEngine(
        tokenSource: ({bool force = false}) async => 't',
        httpClient: MockClient((req) async {
          sent.add('${req.method} ${req.url.path} ${req.body}');
          if (req.url.path.endsWith('/m2/move')) return http.Response('', 500);
          return http.Response('{}', 200);
        }),
      );
      await g.setRuleEnabled('r/1', false);
      expect(sent.single, 'PATCH /v1.0/me/mailFolders/inbox/messageRules/r%2F1 {"isEnabled":false}');
      sent.clear();
      expect(await g.restoreToInbox(['m1', 'm2']), 1);
      expect(sent.first, 'POST /v1.0/me/messages/m1/move {"destinationId":"inbox"}');
    });
  });
}
