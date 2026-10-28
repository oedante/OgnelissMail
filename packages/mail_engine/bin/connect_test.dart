// Проверка подключения движка из консоли (1.6.12): тот же код, что в
// приложении (EngineFactory → OPTIONS → Provision → FolderSync → Sync), с
// выбором, кем представиться серверу.
//
//   cd packages/mail_engine
//   dart pub get
//   dart run bin/connect_test.dart --email ivanov@corp.ru --server mail.corp.ru --domain CORP --as iphone
//
// Параметры:
//   --email     адрес (обязательно)
//   --server    сервер Exchange (пусто — Autodiscover по домену адреса)
//   --domain    домен Windows для входа DOMAIN\логин (пусто — вход по адресу)
//   --as        iphone | android | ogneliss — профиль (по умолчанию iphone):
//                 iphone   — как Почта iPhone (режим совместимости приложения на iPhone);
//                 android  — как режим совместимости на Android;
//                 ogneliss — без совместимости (честный User-Agent приложения).
//   --model     модель iPhone для профиля iphone (по умолчанию iPhone15,2)
//   --ios       версия и сборка iOS (по умолчанию «18.1 22B83»)
//   --transport eas | ews | auto (по умолчанию eas — как вход по ActiveSync)
//   --base64    командная строка EAS как у Почты iPhone (один Base64-токен),
//               а не ?Cmd=..&User=..&DeviceId=..&DeviceType=.. — проверить, не
//               по этому ли анти-бот шлюз различает клиентов (OPTIONS проходит,
//               а Provision plain-query → 403). --no-base64 — обычный plain-query.
//   --ca        файл .pem/.crt/.cer с сертификатом ЦС организации (можно несколько раз);
//               ЦС приложения (assets/certs, Минцифры) подключаются сами
//   --insecure  принять любой сертификат сервера (только для проверки!)
//   --quiet     без подробного журнала запросов
//   --mail      заодно получить 5 последних писем «Входящих» (только чтение)
//
// Пароль — из переменной окружения OGN_PASSWORD или вводится скрыто.
// Заголовок Authorization в журнале скрыт. Ничего не отправляется и не
// удаляется; на сервере появится «мобильное устройство» с DeviceId OGNCLI…
// (одно на адрес и профиль — повторные запуски его переиспользуют).
//
// ВАЖНО: TLS здесь — Dart (как у приложения без режима совместимости), а не
// сетевой стек iOS. Шлюз, различающий клиентов по отпечатку TLS, может
// ответить 403 «If you are not a bot» даже профилю iphone — это не значит,
// что iPhone не войдёт. Настоящий сетевой стек iOS — в симуляторе iPhone на
// Mac (docs/guides/IOS_XCODE_SETUP.md, «Проверка в симуляторе»).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mail_engine/mail_engine.dart';

Future<void> main(List<String> argv) async {
  final (a, cas, stray) = _args(argv);
  if (stray.isNotEmpty) {
    // «--domain CORP android» — слово без «--» молча терялось (17.10).
    stderr.writeln('Непонятные параметры: ${stray.join(' ')}'
        '${stray.any((s) => const ['iphone', 'android', 'ogneliss'].contains(s.toLowerCase())) ? ' — может быть, «--as ${stray.first}»?' : ''}');
    exit(2);
  }
  final email = a['email'];
  if (email == null || email.isEmpty || a.containsKey('help')) {
    stdout.writeln(_usage);
    exit(email == null ? 2 : 0);
  }
  final profile = (a['as'] ?? 'iphone').toLowerCase();
  final model = a['model'] ?? 'iPhone15,2';
  final ios = a['ios'] ?? '18.1 22B83';

  final String ua;
  final String deviceType;
  var devModel = 'Android', devOs = 'Android', friendly = 'Mail';
  switch (profile) {
    case 'iphone':
      ua = _appleMailUa(model, ios);
      deviceType = model.startsWith('iPad') ? 'iPad' : 'iPhone';
      devModel = model.replaceAll(',', 'C');
      devOs = 'iOS $ios';
      friendly = deviceType;
    case 'android':
      ua = 'Android-Android/13 (Pixel 6/TP1A.221005.002)';
      deviceType = 'Android';
    case 'ogneliss':
      ua = 'Ogneliss/1.6.12 (console)';
      deviceType = 'Computer';
    default:
      stderr.writeln('--as: iphone, android или ogneliss');
      exit(2);
  }

  var password = Platform.environment['OGN_PASSWORD'];
  if (password == null || password.isEmpty) {
    stdout.write('Пароль для $email: ');
    try {
      stdin.echoMode = false;
    } catch (_) {}
    password = stdin.readLineSync(encoding: utf8) ?? '';
    try {
      stdin.echoMode = true;
    } catch (_) {}
    stdout.writeln();
  }

  final transport = switch ((a['transport'] ?? 'eas').toLowerCase()) {
    'ews' => MailTransportKind.ews,
    'auto' => null,
    _ => MailTransportKind.eas,
  };
  final deviceId = 'OGNCLI${_hash('$email|$profile').toUpperCase()}';

  // Форма командной строки EAS: --base64 (Base64 из MS-ASHTTP), --no-base64
  // (plain-query), по умолчанию — авто движка (plain-query). Почта iPhone по
  // журналам Exchange шлёт plain-query с Cmd в конце — профиль iphone так и
  // делает (appleMailProfile).
  final bool? base64Override = a.containsKey('base64')
      ? true
      : a.containsKey('no-base64')
          ? false
          : null;

  final cfg = AccountConfig(
    email: email,
    password: password,
    domain: (a['domain'] ?? '').isEmpty ? null : a['domain'],
    exchangeServer: (a['server'] ?? '').isEmpty ? null : a['server'],
    forceTransport: transport,
    userAgent: ua,
    deviceType: deviceType,
    deviceModel: devModel,
    deviceOs: devOs,
    deviceFriendlyName: friendly,
    deviceId: deviceId,
    bodyType: 2,
    bodyTruncationBytes: 4096,
    easBase64Override: base64Override,
    appleMailProfile: profile == 'iphone',
  );

  stdout.writeln('== Профиль: $profile');
  stdout.writeln('   User-Agent: $ua');
  stdout.writeln('   Командная строка EAS: '
      '${base64Override == null ? "авто (plain-query${profile == 'iphone' ? ', порядок Почты iPhone' : ''})" : base64Override ? "Base64" : "plain-query"}');
  stdout.writeln('   DeviceType: $deviceType, Model: $devModel, OS: $devOs, DeviceId: $deviceId');
  stdout.writeln('   Сервер: ${cfg.exchangeServer ?? '(Autodiscover)'}, '
      'вход: ${cfg.domain == null ? email : '${cfg.domain}\\${email.split('@').first}'}, '
      'транспорт: ${transport?.name ?? 'auto'}');

  // Доверенные ЦС: системные + ЦС приложения (assets/certs) + --ca.
  final ctx = SecurityContext(withTrustedRoots: true);
  final caFiles = <File>[
    for (final dir in const ['assets/certs', '../../assets/certs'])
      if (Directory(dir).existsSync())
        ...Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.pem')),
    for (final c in cas) File(c),
  ];
  final caNames = <String>[];
  for (final f in caFiles) {
    try {
      ctx.setTrustedCertificatesBytes(_pemOrDer(f.readAsBytesSync()));
      caNames.add(f.uri.pathSegments.last);
    } on TlsException catch (e) {
      // Уже добавлен (тот же ЦС из двух папок) — не ошибка.
      if (!e.toString().contains('already')) stderr.writeln('ЦС ${f.path}: $e');
    } catch (e) {
      stderr.writeln('ЦС ${f.path}: $e');
      if (cas.contains(f.path)) exit(2);
    }
  }
  if (caNames.isNotEmpty) stdout.writeln('   ЦС: ${caNames.join(', ')}');
  final hc = HttpClient(context: ctx);
  if (a.containsKey('insecure')) {
    hc.badCertificateCallback = (cert, host, port) => true;
    stdout.writeln('   ⚠ --insecure: сертификат сервера не проверяется');
  } else {
    hc.badCertificateCallback = (cert, host, port) {
      stdout.writeln('   ✗ Сертификат $host не подтверждён: ${cert.subject} (выдан ${cert.issuer}).');
      stdout.writeln('     Укажите ЦС организации: --ca <файл.cer> (экспорт из Windows: certmgr.msc → '
          'Доверенные корневые центры → сертификат → Экспорт, Base64 X.509) или для проверки --insecure.');
      return false;
    };
  }
  final http.Client client = IOClient(hc);

  final log = DebugLog(verbose: !a.containsKey('quiet'), echo: true);
  final sw = Stopwatch()..start();
  final (engine, res) = await EngineFactory.connect(cfg, logger: log, httpClient: client);
  stdout.writeln();
  if (engine == null || !res.success) {
    stdout.writeln('✗ НЕ ПОДКЛЮЧИЛОСЬ за ${sw.elapsed.inSeconds} с: ${res.error}');
    final e = res.error ?? '';
    if (e.contains('403')) {
      stdout.writeln('  403: шлюз или политика Exchange. С профилем iphone из консоли это может быть '
          'отпечаток TLS Dart, а не запрет iPhone — проверьте в симуляторе.');
    } else if (e.contains('ни один URL') && !a.containsKey('insecure')) {
      stdout.writeln('  Сервер не ответил: если выше «Сертификат … не подтверждён» — нужен --ca или --insecure.');
    } else if (e.contains('401')) {
      stdout.writeln('  401: логин/пароль/домен (или сервер принимает только NTLM — его консоль не умеет).');
    }
    exit(1);
  }
  stdout.writeln('✓ ПОДКЛЮЧЕНО за ${sw.elapsed.inMilliseconds} мс: ${res.transport?.name} @ ${res.resolvedHost}');
  try {
    final folders = await engine.listFolders();
    stdout.writeln('  Папок: ${folders.length}');
    for (final f in folders.where((f) => f.type != MailFolderType.user).take(12)) {
      stdout.writeln('   · ${f.displayName} (${f.type.name}, id ${f.id})');
    }
    if (a.containsKey('mail')) {
      final inbox = folders.where((f) => f.type == MailFolderType.inbox).firstOrNull;
      if (inbox != null) {
        final r = await engine.syncFolder(inbox.id);
        final list = [...r.added]..sort((x, y) => (y.date ?? DateTime(0)).compareTo(x.date ?? DateTime(0)));
        stdout.writeln('  Входящие: ${r.added.length} писем в первом пакете${r.moreAvailable ? ' (есть ещё)' : ''}');
        for (final m in list.take(5)) {
          stdout.writeln('   · ${m.date?.toLocal().toString().substring(0, 16) ?? ''}  ${m.from.email}  ${m.subject}');
        }
      }
    }
  } catch (e) {
    stdout.writeln('✗ После подключения: $e');
    exitCode = 1;
  } finally {
    await engine.dispose();
    client.close();
  }
}

const _usage = '''
dart run bin/connect_test.dart --email <адрес> [--server <хост>] [--domain <ДОМЕН>]
    [--as iphone|android|ogneliss] [--model iPhone15,2] [--ios "18.1 22B83"]
    [--transport eas|ews|auto] [--base64|--no-base64] [--ca <файл ЦС>] [--insecure] [--quiet] [--mail]
Пароль: переменная OGN_PASSWORD или скрытый ввод. Подробно — в начале файла.''';

/// --key value / --flag; --ca можно несколько раз; слова без «--» — в stray.
(Map<String, String>, List<String>, List<String>) _args(List<String> argv) {
  final m = <String, String>{};
  final cas = <String>[];
  final stray = <String>[];
  for (var i = 0; i < argv.length; i++) {
    final k = argv[i];
    if (!k.startsWith('--')) {
      stray.add(k);
      continue;
    }
    var name = k.substring(2);
    String value;
    final eq = name.indexOf('=');
    if (eq > 0) {
      value = name.substring(eq + 1);
      name = name.substring(0, eq);
    } else if (_flags.contains(name)) {
      value = '';
    } else if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      value = argv[++i];
    } else {
      value = '';
    }
    if (name == 'ca') {
      if (value.isNotEmpty) cas.add(value); // «--ca» без файла — пропускаем, не падаем
    } else {
      m[name] = value;
    }
  }
  return (m, cas, stray);
}

/// Параметры без значения: слово после них — не их значение.
const _flags = {'insecure', 'quiet', 'mail', 'help', 'base64', 'no-base64'};

/// PEM как есть; DER (.cer из Windows бывает двоичным) — в PEM.
List<int> _pemOrDer(List<int> bytes) {
  final head = String.fromCharCodes(bytes.take(64));
  if (head.contains('-----BEGIN')) return bytes;
  final b64 = base64.encode(bytes);
  final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, i + 64 > b64.length ? b64.length : i + 64)];
  return utf8.encode('-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n');
}

/// Как DeviceUserAgent.appleMailUserAgent в приложении: «Apple-iPhone15C2/2201.83».
String _appleMailUa(String model, String ios) {
  final b = RegExp(r'(\d+)([A-Z])(\d+)').firstMatch(ios.split(' ').last);
  final build = b == null
      ? '2101.0'
      : '${b.group(1)}${(b.group(2)!.codeUnitAt(0) - 64).toString().padLeft(2, '0')}.${b.group(3)}';
  return 'Apple-${model.replaceAll(',', 'C')}/$build';
}

String _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(s)) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
