// Сигналы сервера (1.9.x, просьба владельца 31.10.2026): регистрация токена
// на «будильнике» — Android (FCM) и iPhone (APNs), включение, выключение,
// обновление раз в сутки, поле platform; связка фоновой задачи push_wake.
// Канал ogneliss/push и сервер — заглушки.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/background/background_service.dart' show backgroundTaskInfo;
import 'package:ogneliss/services/push/push_wake_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('ogneliss/push');
const _upChannel = MethodChannel('ogneliss/unifiedpush');
final _vapid = 'B${'A' * 86}';
const _upUrl = 'https://ntfy.example.org/upAbCdEf0123?up=1';
final _p256dh = 'B${'k' * 86}';
const _auth = 'aaaaaaaaaaaaaaaaaaaaaa';
final _fcmToken = 'dXyZ01:APA91b${'Qw_-' * 36}';
final _fcmToken2 = 'eAbC02:APA91b${'Zx-_' * 36}';
final _apnsToken = 'ab' * 32;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<http.Request> posts;
  late List<http.Request> gets;
  late List<MethodCall> upCalls;
  late Map<String, Object?> upCurrent;
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) native;
  var status = 204;

  Map<String, Object?> body(http.Request r) => jsonDecode(r.body) as Map<String, Object?>;

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<ProviderContainer> make({PushWakeOs os = PushWakeOs.android, Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final client = MockClient((r) async {
      if (r.method == 'GET') {
        gets.add(r);
        return http.Response(jsonEncode({'key': _vapid}), 200);
      }
      posts.add(r);
      return http.Response('', status);
    });
    final c = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      pushWakeServiceProvider.overrideWith((ref) => PushWakeService(ref, os: os, client: client)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Сообщение от платформы в Dart (как PushWakeFcm.onNewToken / AppDelegate).
  Future<void> fromNative(String method, Object? args) async {
    await messenger.handlePlatformMessage(
        _channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
    await settle();
  }

  setUp(() {
    posts = [];
    gets = [];
    upCalls = [];
    upCurrent = {'distributor': null, 'url': null};
    messenger.setMockMethodCallHandler(_upChannel, (call) async {
      upCalls.add(call);
      switch (call.method) {
        case 'distributors':
          return [
            {'id': 'io.heckel.ntfy', 'name': 'ntfy'},
          ];
        case 'current':
          return upCurrent;
      }
      return null;
    });
    calls = [];
    status = 204;
    native = (call) => call.method == 'register' ? _fcmToken : null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return native(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(_upChannel, null);
  });

  /// Сообщение от PushWakeUnifiedPush.kt в Dart.
  Future<void> fromUp(String method, Object? args) async {
    await messenger.handlePlatformMessage(
        _upChannel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
    await settle();
  }

  group('Android без сервисов Google (UnifiedPush, 1.10.x)', () {
    test('список распространителей и выбор: регистрация с ключом VAPID, адрес с ключами — на сервер', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      expect(await s.upDistributors(), [(id: 'io.heckel.ntfy', name: 'ntfy')]);
      upCurrent = {'distributor': 'io.heckel.ntfy', 'url': _upUrl, 'p256dh': _p256dh, 'auth': _auth};
      await s.useTransport(PushWakeTransport.unifiedpush, distributor: 'io.heckel.ntfy');

      expect(s.transport, PushWakeTransport.unifiedpush);
      expect(gets.single.url.path, endsWith('/vapid'));
      final reg = upCalls.firstWhere((c) => c.method == 'register');
      expect(reg.arguments, {'distributor': 'io.heckel.ntfy', 'vapid': _vapid});
      expect(calls.where((c) => c.method == 'register'), isEmpty, reason: 'FCM не запрашивается');
      expect(body(posts.single), {
        'token': _upUrl,
        'env': 'up',
        'interval': 15,
        'mode': 'normal',
        'platform': 'unifiedpush',
        'p256dh': _p256dh,
        'auth': _auth,
      });
      expect(s.state().registered, isTrue);
    });

    test('адрес приходит позже (onEndpoint) — тогда и регистрация', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.init();
      posts.clear();
      await s.useTransport(PushWakeTransport.unifiedpush, distributor: 'io.heckel.ntfy');
      expect(posts.where((r) => r.url.path.endsWith('/register')), isEmpty);
      await fromUp('onEndpoint', {'url': _upUrl, 'p256dh': _p256dh, 'auth': _auth});
      expect(body(posts.last)['platform'], 'unifiedpush');
      expect(body(posts.last)['token'], _upUrl);
    });

    test('с Google на UnifiedPush: токен FCM снимается с сервера и у Android', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.apply(); // FCM
      expect(body(posts.single)['platform'], 'android');
      posts.clear();
      calls.clear();
      upCurrent = {'distributor': 'io.heckel.ntfy', 'url': _upUrl, 'p256dh': _p256dh, 'auth': _auth};
      await s.useTransport(PushWakeTransport.unifiedpush, distributor: 'io.heckel.ntfy');
      expect(posts.first.url.path, endsWith('/unregister'));
      expect(body(posts.first), {'token': _fcmToken, 'platform': 'android'});
      expect(calls.map((c) => c.method), contains('unregister'));
      expect(body(posts.last)['platform'], 'unifiedpush');

      // И обратно: снимается адрес UnifiedPush, у распространителя — тоже.
      posts.clear();
      upCalls.clear();
      await s.useTransport(PushWakeTransport.fcm);
      expect(body(posts.first), {'token': _upUrl, 'platform': 'unifiedpush'});
      expect(upCalls.map((c) => c.method), contains('unregister'));
      expect(body(posts.last)['platform'], 'android');
    });

    test('без Firebase в сборке — по умолчанию UnifiedPush; без распространителя — ничего не делается', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final client = MockClient((r) async {
        posts.add(r);
        return http.Response('', 204);
      });
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        pushWakeServiceProvider.overrideWith(
            (ref) => PushWakeService(ref, os: PushWakeOs.android, client: client, fcmAvailable: false)),
      ]);
      addTearDown(c.dispose);
      final s = c.read(pushWakeServiceProvider);
      expect(s.transport, PushWakeTransport.unifiedpush);
      await s.apply();
      expect(posts, isEmpty);
      expect(calls, isEmpty);
      expect(upCalls.where((c) => c.method == 'register'), isEmpty);
    });

    test('ошибка распространителя видна в состоянии; адрес без шифрования не отправляется', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.init();
      await s.useTransport(PushWakeTransport.unifiedpush, distributor: 'io.heckel.ntfy');
      posts.clear();
      await fromUp('onError', {'reason': 'VAPID_REQUIRED'});
      expect(s.state().lastError, contains('VAPID_REQUIRED'));
      await fromUp('onEndpoint', {'url': 'http://ntfy.example.org/up1', 'p256dh': _p256dh, 'auth': _auth});
      await fromUp('onEndpoint', {'url': _upUrl, 'p256dh': null, 'auth': null});
      expect(posts, isEmpty);
    });
  });

  group('Android (FCM)', () {
    test('включено: токен от Android регистрируется с platform android, окружение fcm', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.apply();

      expect(calls.single.method, 'register');
      expect((calls.single.arguments as Map).keys, containsAll(['apiKey', 'appId', 'senderId', 'projectId']));
      expect(posts, hasLength(1));
      expect(posts.single.url.path, endsWith('/register'));
      expect(body(posts.single), {
        'token': _fcmToken,
        'env': 'fcm',
        'interval': 15,
        'mode': 'normal',
        'platform': 'android',
      });
      final st = s.state();
      expect(st.registered, isTrue);
      expect(st.env, 'fcm');
      expect(st.lastError, isNull);
    });

    test('повтор в течение суток — без запроса, через сутки — обновление', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.apply();
      await s.apply();
      expect(posts, hasLength(1));

      final old = DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch;
      await c.read(sharedPrefsProvider).setInt('push_wake_sent_at', old);
      await s.apply();
      expect(posts, hasLength(2));
      expect(posts.last.url.path, endsWith('/register'));
    });

    test('смена интервала — перерегистрация с новым интервалом', () async {
      final c = await make();
      await c.read(pushWakeServiceProvider).apply();
      await c.read(pushWakePrefsProvider.notifier).setInterval(30);
      await settle();
      expect(posts, hasLength(2));
      expect(body(posts.last)['interval'], 30);
    });

    test('выключено: снять с сервера и отозвать токен у Android', () async {
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.apply();
      await c.read(pushWakePrefsProvider.notifier).setEnabled(false);
      await settle();

      expect(posts.last.url.path, endsWith('/unregister'));
      expect(body(posts.last), {'token': _fcmToken, 'platform': 'android'});
      expect(calls.map((c) => c.method), contains('unregister'));
      expect(s.state().registered, isFalse);
    });

    test('Android сменил токен: прежний снимается, новый регистрируется', () async {
      final c = await make();
      await c.read(pushWakeServiceProvider).init();
      expect(posts, hasLength(1));

      await fromNative('onToken', {'token': _fcmToken2, 'env': 'fcm'});
      expect(posts, hasLength(3));
      expect(posts[1].url.path, endsWith('/unregister'));
      expect(body(posts[1])['token'], _fcmToken);
      expect(body(posts[2])['token'], _fcmToken2);
      expect(body(posts[2])['platform'], 'android');
    });

    test('нет сервисов Google Play — ошибка видна в состоянии, на сервер ничего', () async {
      native = (call) => throw PlatformException(code: 'token', message: 'SERVICE_NOT_AVAILABLE');
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.apply();

      expect(posts, isEmpty);
      expect(s.state().registered, isFalse);
      expect(s.state().lastError, 'Android: SERVICE_NOT_AVAILABLE');
    });

    test('сервер отказал — не зарегистрировано, ошибка в состоянии', () async {
      status = 400;
      final c = await make();
      final s = c.read(pushWakeServiceProvider);
      await s.apply();
      expect(s.state().registered, isFalse);
      expect(s.state().lastError, contains('HTTP 400'));
    });

    test('неверный токен не отправляется', () async {
      native = (call) => call.method == 'register' ? 'bad token!' : null;
      final c = await make();
      await c.read(pushWakeServiceProvider).apply();
      expect(posts, isEmpty);
    });
  });

  group('iPhone (APNs)', () {
    test('register без параметров, токен приходит в onToken; platform ios', () async {
      native = (call) => null;
      final c = await make(os: PushWakeOs.ios);
      await c.read(pushWakeServiceProvider).init();
      expect(calls.single.method, 'register');
      expect(calls.single.arguments, isNull);
      expect(posts, isEmpty);

      await fromNative('onToken', {'token': _apnsToken, 'env': 'production'});
      expect(body(posts.single), {
        'token': _apnsToken,
        'env': 'production',
        'interval': 15,
        'mode': 'silent',
        'platform': 'ios',
      });
    });
  });

  group('фоновая задача сигнала', () {
    test('push_wake — своё имя в журнале и лимит 3 минуты; плановая — как раньше', () {
      final wake = backgroundTaskInfo('push_wake');
      expect(wake.kind, PushWakeService.androidWakeKind);
      expect(wake.limit, const Duration(minutes: 3));
      final periodic = backgroundTaskInfo('periodic_sync');
      expect(periodic.kind, 'WorkManager');
      expect(periodic.limit, const Duration(minutes: 9));
    });

    test('отметка сигнала видна в состоянии («Последний сигнал»)', () async {
      final c = await make();
      expect(c.read(pushWakeServiceProvider).state().lastWake, isNull);
      await PushWakeService.noteWake(c.read(sharedPrefsProvider));
      final last = c.read(pushWakeServiceProvider).state().lastWake;
      expect(last, isNotNull);
      expect(DateTime.now().difference(last!).inSeconds, lessThan(5));
    });
  });
}
