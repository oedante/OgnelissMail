import '../../services/push/push_wake_service.dart';
import 'package:crypto/crypto.dart' show sha256;
// lib/core/logging/diagnostics_report.dart
// Пакет диагностики для ИТ-поддержки: ZIP с журналом и сводкой
// (версия, устройство, ящики, политика Exchange, сертификаты).
//
// Адреса в сводке маскируются так же, как в журнале (i***@corp.ru);
// паролей, токенов и ключа прокси в пакете нет — только «задан / не задан».

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../data/providers/database_provider.dart';
import '../../services/mail/engine/mail_engine_service.dart';
import '../../services/security/device_security_service.dart';
import '../../services/security/eas_policy_store.dart';
import '../constants/app_constants.dart';
import '../security/certificate_pinning_service.dart';
import 'app_logger.dart';
import '../platform/platform_diagnostics.dart';
import '../../services/background/background_journal.dart';
import '../../services/notifications/account_notify_mode.dart';
import '../../services/background/foreground_sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticsReport {
  DiagnosticsReport._();

  /// Имя файла пакета: ogneliss-diagnostics-20261003-0640.zip
  static String fileName([DateTime? at]) =>
      'ogneliss-diagnostics-${DateFormat('yyyyMMdd-HHmm').format(at ?? DateTime.now())}.zip';

  /// Собрать пакет во временной папке. Возвращает файл ZIP.
  static Future<File> build(WidgetRef ref) async {
    final bytes = await buildBytes(ref);
    final dir = await getTemporaryDirectory();
    // Пакеты прошлых дней из временной папки убираем: в них журнал.
    try {
      final limit = DateTime.now().subtract(const Duration(days: 1));
      for (final e in dir.listSync()) {
        final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        if (e is File && name.startsWith('ogneliss-diagnostics-') && e.lastModifiedSync().isBefore(limit)) {
          e.deleteSync();
        }
      }
    } catch (_) {}
    final f = File('${dir.path}${Platform.pathSeparator}${fileName()}');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<List<int>> buildBytes(WidgetRef ref) async {
    final summary = await _summary(ref);
    await AppLogger.settle();
    final logPath = AppLogger.logFilePath;
    // Чтение и сжатие журнала (до 15 МБ) — в отдельном изоляте, иначе
    // интерфейс замирает на секунды. В изолят передаём только строки.
    return Isolate.run(() => _zip(summary, logPath));
  }

  static List<int> _zip(String summary, String? logPath) {
    final archive = Archive();
    final s = utf8.encode(summary);
    archive.addFile(ArchiveFile('diagnostics.txt', s.length, s));
    if (logPath != null) {
      final f = File(logPath);
      if (f.existsSync()) {
        final l = f.readAsBytesSync();
        archive.addFile(ArchiveFile('ogneliss.log', l.length, l));
      }
    }
    // Журнал до 15 МБ сжимается примерно в 10 раз — пакет проходит
    // ограничение размера вложения почтового сервера.
    // archive 4.5+ (pubspec): encode возвращает не-null байты.
    return ZipEncoder().encode(archive);
  }

  static Future<String> _summary(WidgetRef ref) async {
    final b = StringBuffer();
    void line(String s) => b.writeln(s);
    String yes(bool v) => v ? 'да' : 'нет';

    line('${AppConstants.appName} — диагностика');
    line('Создан: ${DateTime.now().toIso8601String()} (${DateTime.now().timeZoneName})');
    try {
      final p = await PackageInfo.fromPlatform();
      line('Версия: ${p.version} (сборка ${p.buildNumber}), '
          '${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')}');
    } catch (_) {
      line('Версия: ${AppConstants.appVersion}');
    }
    line('Устройство: ${await _device()}');
    line('Подробный журнал: ${AppLogger.detailed ? 'до ${AppLogger.detailedUntil}' : 'выключен'}');
    // Фоновая работа: ограничения устройства и история запусков.
    try {
      final d = await PlatformDiagnostics.collect();
      if (d.isNotEmpty) {
        line('Платформа: ${PlatformDiagnostics.summary(d)}');
        final iss = PlatformDiagnostics.issues(d);
        line('Ограничения фоновой работы: ${iss.isEmpty ? 'не обнаружены' : iss.map((e) => e.name).join(', ')}');
      }
      final sp = await SharedPreferences.getInstance();
      final frozenN = sp.getInt(ForegroundSyncController.frozenCountKey) ?? 0;
      if (frozenN > 0) {
        final last = DateTime.fromMillisecondsSinceEpoch(sp.getInt(ForegroundSyncController.frozenLastKey) ?? 0);
        line('Замораживание системой: ×$frozenN, последнее $last '
            '(~${sp.getInt(ForegroundSyncController.frozenMinutesKey) ?? 0} мин)');
      }
      line('Фоновая работа (история):');
      line(await BackgroundJournal.report());
    } catch (_) {}
    line('');

    final engine = ref.read(mailEngineServiceProvider);
    final accounts = ref.read(accountsProvider);
    // Режим уведомлений ящика и проверка (1.6.45): «уведомления не приходят»
    // бывает и из-за «Только VIP», выбранного когда-то у ящика.
    final notifyPrefs = await SharedPreferences.getInstance();
    line('Ящики (${accounts.length}):');
    for (final (i, a) in accounts.indexed) {
      final server = a.exchangeServer ?? a.imapServer ?? '—';
      final err = engine.lastConnectError(a.id);
      line('  ${i + 1}. ${AppLogger.mask(a.email)} — ${a.type.name}, сервер $server'
          '${a.ewsUrl != null ? ', EWS ${Uri.tryParse(a.ewsUrl!)?.host ?? '?'}' : ''}'
          '${a.domain != null && a.domain!.isNotEmpty ? ', домен ${a.domain}' : ''}'
          ', активен: ${yes(a.isActive)}'
          ', проверка: ${a.syncInterval.name}'
          ', уведомления: ${AccountNotify.of(notifyPrefs, a.id).name}'
          '${a.authFailedAt != null ? ', требуется вход с ${a.authFailedAt}' : ''}'
          '${err != null ? ', последняя ошибка подключения: ${AppLogger.mask(err)}' : ''}');
    }
    // Контакты и фото по источникам (1.5.12): по журналу было не понять,
    // есть ли фото в базе или они не показываются.
    try {
      final db = ref.read(databaseProvider);
      final rows = await db.customSelect(
        "SELECT source, COUNT(*) AS n, SUM(CASE WHEN avatar_url IS NOT NULL AND avatar_url <> '' THEN 1 ELSE 0 END) AS ph "
        'FROM contacts GROUP BY source',
      ).get();
      const names = ['адресная книга', 'личные', 'телефон', 'из переписки'];
      final parts = [
        for (final r in rows)
          '${(r.read<int>('source') < names.length) ? names[r.read<int>('source')] : r.read<int>('source')} '
              '${r.read<int>('n')} (с фото ${r.readNullable<int>('ph') ?? 0})',
      ];
      final sp = await SharedPreferences.getInstance();
      final tried = sp.getString('gal_photo_tried');
      final noPhoto = tried == null ? 0 : (jsonDecode(tried) as Map).length;
      line('Контакты: ${parts.isEmpty ? 'нет' : parts.join(', ')}; без фото в адресной книге (неделя): $noPhoto');
    } catch (_) {}
    line('');

    final p = ref.read(easPolicyProvider);
    line('Политика Exchange: пароль=${yes(p.pinRequired)}, длина≥${p.minPasswordLength}, '
        'простые PIN=${yes(p.allowSimplePassword)}, буквы=${yes(p.alphanumericRequired)}, '
        'тайм-аут=${p.maxInactivitySeconds} с, шифрование=${yes(p.requireEncryption)}, '
        'попыток до стирания=${p.maxFailedAttempts}');
    final d = await ref.read(deviceSecurityServiceProvider).status();
    if (d.supported) {
      line('Устройство и политика: блокировка=${d.complexity.name}, защищено=${yes(d.deviceSecure)}, '
          'шифрование=${d.encryption.name}, администратор=${yes(d.adminActive)}, '
          'тайм-аут экрана=${d.maxTimeToLockMs ~/ 1000} с, SDK ${d.sdk}');
    }

    try {
      final pin = ref.read(certPinningProvider);
      final hosts = pin.rules.map((r) => r.domain.startsWith('=') ? r.domain.substring(1) : r.domain);
      line('Сертификаты: режим=${pin.mode.name}, правил=${pin.rules.length}'
          '${hosts.isEmpty ? '' : ' (${hosts.join(', ')})'}, доверенных доменов=${pin.trustedCaDomains.length}');
    } catch (_) {}
    line('OAuth-прокси: адрес ${AppConstants.oauthProxyBaseUrl.isEmpty ? 'не задан' : AppConstants.oauthProxyBaseUrl}, '
        'ключ ${AppConstants.oauthProxyApiKey.isEmpty ? 'НЕ задан' : 'задан, отпечаток ${sha256.convert(utf8.encode(AppConstants.oauthProxyApiKey)).toString().substring(0, 8)}'}'
        // Сверка с прокси: GET <адрес>/healthz → keys.api должен совпасть.
        );
    // Сигналы сервера на iPhone (1.7.2): включены ли, регистрация, последний сигнал.
    if (PushWakeService.supported) {
      try {
        final st = ref.read(pushWakeServiceProvider).state();
        final pw = ref.read(pushWakePrefsProvider);
        line('Сигналы сервера (iPhone): ${pw.enabled ? 'вкл' : 'выкл'}, раз в ${pw.interval} мин, '
            'режим ${AppConstants.pushWakeMode}, адрес ${AppConstants.pushRelayUrl}; регистрация: '
            '${st.registered ? '${st.env}, ${st.registeredAt?.toIso8601String() ?? '?'}' : 'нет'}'
            '${st.lastWake == null ? '' : '; последний сигнал ${st.lastWake!.toIso8601String()}'}'
            '${st.lastError == null ? '' : '; ошибка: ${st.lastError}'}');
      } catch (_) {}
    }
    return b.toString();
  }

  static Future<String> _device() async {
    if (kIsWeb) return 'web';
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return 'Android ${a.version.release} (SDK ${a.version.sdkInt}), ${a.manufacturer} ${a.model}';
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return '${i.systemName} ${i.systemVersion}, ${i.utsname.machine} (${i.model})';
      }
      if (Platform.isWindows) {
        final w = await info.windowsInfo;
        return '${w.productName} ${w.displayVersion} (сборка ${w.buildNumber})';
      }
    } catch (_) {}
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  }
}
