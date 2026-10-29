// Microsoft Graph для Exchange Online в приложении (1.8.10; с 1.8.11 сам
// Graph — в движке, см. graph_engine_test.dart): согласие при входе, токены
// Graph (напрямую и через сервер входа), перевод в модели приложения.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/contact_model.dart';
import 'package:ogneliss/services/mail/engine/graph_server_tools.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';
import 'package:ogneliss/services/mail/oauth/graph_tokens.dart';
import 'package:ogneliss/services/mail/oauth/oauth_proxy_client.dart';
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

/// Сервер входа: обновление токена без сети.
class _FakeProxy extends OAuthProxyClient {
  _FakeProxy(super.storage);
  final calls = <String>[];

  @override
  bool get isEnabled => true;

  @override
  Future<({String accessToken, DateTime expiresAt, String rt})> refreshWithBlob(String rt, String provider,
      {String? resource}) async {
    calls.add('$provider $resource $rt');
    return (accessToken: 'graph-via-proxy', expiresAt: DateTime.now().add(const Duration(hours: 1)), rt: 'blob2');
  }
}

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
      expect(c.scopes, me.GraphEngine.tokenScopes);
      expect(c.tokenEndpoint.toString(), contains('/organizations/'));
      expect(DirectOAuth.graphClient('microsoft|x'), isNull);
      expect(DirectOAuth.graphClient('google|x'), isNull);
    });

    test('права при входе — из движка, без согласия администратора', () {
      expect(DirectOAuth.graphConsentScopes, me.GraphEngine.consentScopes);
      final s = DirectOAuth.graphConsentScopes.join(' ');
      expect(s, isNot(contains('Place.Read.All')));
      expect(s, isNot(contains('GroupMember.Read.All')));
      expect(s, isNot(contains('User.Read.All')));
      expect(s, contains('MailboxSettings.ReadWrite'));
    });
  });

  group('модели приложения', () {
    test('пользователь Graph → контакт адресной книги', () {
      final c = MailEngineService.contactFromGraph(
          const me.GraphUser(
            email: 'anna@contoso.example',
            displayName: 'Смирнова Анна',
            givenName: 'Анна',
            surname: 'Смирнова',
            jobTitle: 'Инженер',
            department: 'Эксплуатация',
            office: 'к. 12',
            businessPhone: '101',
            mobilePhone: '+7 900',
            manager: 'Петров',
          ),
          accountId: 'a1');
      expect(c.id, 'gal_${'anna@contoso.example'.hashCode}');
      expect(c.accountId, 'a1');
      expect(c.firstName, 'Анна');
      expect(c.lastName, 'Смирнова');
      expect(c.phoneWork, '101');
      expect(c.phoneMobile, '+7 900');
      expect(c.manager, 'Петров');
      expect(c.source, ContactSource.exchangeGal);
    });

    test('подсказка Graph → MailTips; места → переговорные', () {
      final t = MailEngineService.mailTipFromGraph(
          const me.GraphMailTip(email: 'all@contoso.example', totalMembers: 120, externalMembers: 3));
      expect(t.isBigList, isTrue);
      expect(t.hasExternal, isTrue);
      expect(MailEngineService.roomsFromGraph(const [me.GraphPlace(name: 'Комната', email: 'r@x.y')]).single.email,
          'r@x.y');
    });

    test('правило редактора → правило Graph; флажка у Graph нет', () {
      final s = GraphServerTools.specFromSieve(
          const SieveRule(
              name: 'Начальник',
              field: SieveField.from,
              op: SieveOp.isExactly,
              value: 'boss@x.y',
              action: SieveAction.forward,
              arg: 'me@home.example'),
          3)!;
      expect(jsonEncode(s.toJson()['conditions']), '{"fromAddresses":[{"emailAddress":{"address":"boss@x.y"}}]}');
      expect(s.toJson()['sequence'], 3);
      expect(
          GraphServerTools.specFromSieve(
              const SieveRule(name: 'x', field: SieveField.subject, value: 'y', action: SieveAction.flag), 1),
          isNull);
      final r = GraphServerTools.ruleFromGraph(const me.GraphRule(
          id: 'r1', name: 'x', enabled: false, sequence: 4, readOnly: true, hasError: false, actions: {'move'}));
      expect(r.priority, 4);
      expect(r.readOnly, isTrue);
      expect(r.actions, ['move']);
    });
  });

  group('токены Graph', () {
    late SharedPreferences prefs;
    late SecureStorageService storage;

    Future<void> init(Map<String, String> secure) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      FlutterSecureStorage.setMockInitialValues(secure);
      storage = SecureStorageService();
    }

    test('движок берёт сохранённый токен', () async {
      await init({
        'oc_a1': 'exchange|client-id',
        'rt_a1': 'refresh',
        'gat_a1': 'graph-token',
        'gexp_a1': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      });
      final tokens = GraphTokens(storage, prefs, httpClient: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer graph-token');
        return http.Response(jsonEncode({'mail': 'ivan@contoso.example', 'displayName': 'Ivan'}), 200);
      }));
      final engine = tokens.engine(_exo())!;
      expect(identical(engine, tokens.engine(_exo())), isTrue);
      expect((await engine.me())!.email, 'ivan@contoso.example');
    });

    test('не Exchange Online — Graph нет', () async {
      await init({});
      final tokens = GraphTokens(storage, prefs);
      final imap = AccountModel(
          id: 'a2', type: AccountType.imap, email: 'x@y.z', displayName: 'x', username: 'x', createdAt: DateTime(2026));
      expect(tokens.supports(imap), isFalse);
      expect(tokens.engine(imap), isNull);
      expect(await tokens.token(imap), isNull);
      expect(tokens.access(imap), GraphAccess.unknown);
    });

    test('вход через сервер входа — токен Graph у него (resource=graph)', () async {
      await init({'rt_a1': 'blob1'});
      final proxy = _FakeProxy(storage);
      final tokens = GraphTokens(storage, prefs, proxy: proxy);
      expect(await tokens.token(_exo()), 'graph-via-proxy');
      expect(proxy.calls, ['exchange graph blob1']);
      expect(await storage.getRefreshToken('a1'), 'blob2');
      expect(tokens.access(_exo()), GraphAccess.ok);
    });

    test('отказ в согласии — пауза, «нет согласия»; сброс — заново', () async {
      await init({'oc_a1': 'exchange|client-id', 'rt_a1': 'refresh'});
      await prefs.setString('graph_state_a1', 'noconsent:${DateTime.now().millisecondsSinceEpoch}');
      final tokens = GraphTokens(storage, prefs);
      expect(tokens.access(_exo()), GraphAccess.noConsent);
      expect(await tokens.token(_exo()), isNull);
      await tokens.reset('a1');
      expect(tokens.access(_exo()), GraphAccess.unknown);
    });
  });
}
