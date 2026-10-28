// lib/services/backup/backup_service.dart
// Резервная копия и перенос на новый телефон.
//
// Что попадает в копию: ящики (настройки серверов, цвет, порядок, тип),
// настройки приложения (SharedPreferences — кроме служебных: токенов
// синхронизации, идентификатора устройства Exchange, кэшей, журнала),
// подписи, заметки, которые есть только на телефоне, и — по выбору —
// пароли и токены входа, чтобы на новом телефоне не входить заново.
// Письма, календарь и контакты не копируются: они на сервере и загрузятся
// сами.
//
// Файл зашифрован паролем, который задаёт пользователь: ключ — PBKDF2-
// HMAC-SHA256 (150 000 итераций, случайная соль), шифр — AES-256-GCM
// (подделка или неверный пароль обнаруживаются). Без пароля файл
// бесполезен; пароль нигде не сохраняется.

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:pointycastle/export.dart' hide Signature;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/database/app_database.dart';

class BackupException implements Exception {
  /// Ключ строки перевода: backupErrPassword, backupErrFormat, backupErrNewer.
  final String key;
  const BackupException(this.key);
  @override
  String toString() => 'BackupException($key)';
}

class RestoreReport {
  final int accountsAdded;
  final int accountsSkipped;
  final int settings;
  final int signatures;
  final int notes;
  final bool withSecrets;
  const RestoreReport({
    required this.accountsAdded,
    required this.accountsSkipped,
    required this.settings,
    required this.signatures,
    required this.notes,
    required this.withSecrets,
  });
}

class BackupService {
  BackupService._();

  static const format = 'ogneliss-backup';
  static const version = 1;
  static const _iterations = 150000;

  /// Секреты ящика в защищённом хранилище (пароль, пароль календаря,
  /// токены OAuth, данные сервера входа).
  static const _secretPrefixes = ['pwd_', 'davpw_', 'at_', 'rt_', 'exp_', 'proxy_', 'proxy_session_'];

  /// Служебные ключи настроек: относятся к этому телефону или пересоздаются
  /// сами. Идентификатор устройства Exchange копировать нельзя — два
  /// телефона с одним DeviceId сервер считает одним устройством.
  static const _skipPrefixes = [
    'synctok_', 'ews_delta_', 'calfull_', 'easfolders_', 'eas_device_id_', 'eas_policy_',
    'dav_', 'widget_', 'startup_last_', 'attachment_cache_', 'bg_journal', 'diag_', 'log_',
    'perm_', 'device_admin_', 'reminder_scheduled_ids', 'booking_added', 'db_encryption_key',
    'search_history', 'oauth_', 'pending_', 'last_sync', 'heartbeat', 'undosend_',
    // Архив Ogneliss (1.7.3): какой архив подключён и его расписание —
    // свои у каждого устройства.
    'ogna_',
  ];

  static bool _skipKey(String k) => _skipPrefixes.any(k.startsWith);

  // ─────────────────────────── создание ───────────────────────────

  static Future<Uint8List> create({
    required AppDatabase db,
    required SharedPreferences prefs,
    required SecureStorageService secure,
    required String passphrase,
    required bool includeSecrets,
    required String appVersion,
  }) async {
    final payload = await collect(db: db, prefs: prefs, secure: secure, includeSecrets: includeSecrets);
    final plain = utf8.encode(jsonEncode(payload));
    final accounts = (payload['accounts'] as List).length;

    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    final iv = Uint8List.fromList(List.generate(12, (_) => rnd.nextInt(256)));
    final key = await _key(passphrase, salt, _iterations);
    final cipher = _gcm(true, key, iv, Uint8List.fromList(plain));
    final file = {
      'format': format,
      'version': version,
      'app': appVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
      'accounts': accounts,
      'secrets': includeSecrets,
      'kdf': {'alg': 'pbkdf2-hmac-sha256', 'iter': _iterations, 'salt': base64.encode(salt)},
      'cipher': 'aes-256-gcm',
      'iv': base64.encode(iv),
      'data': base64.encode(cipher),
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(file)));
  }

  /// Содержимое копии без шифрования: ящики, настройки, подписи, заметки
  /// и — по выбору — пароли. Шифрует [create]; архив Ogneliss (1.7.3) кладёт
  /// содержимое в свою зашифрованную базу.
  static Future<Map<String, dynamic>> collect({
    required AppDatabase db,
    required SharedPreferences prefs,
    required SecureStorageService secure,
    required bool includeSecrets,
  }) async {
    final accounts = await db.select(db.accounts).get();
    final settings = <String, Map<String, Object?>>{};
    for (final k in prefs.getKeys()) {
      if (_skipKey(k)) continue;
      final v = prefs.get(k);
      if (v is String) {
        settings[k] = {'t': 's', 'v': v};
      } else if (v is bool) {
        settings[k] = {'t': 'b', 'v': v};
      } else if (v is int) {
        settings[k] = {'t': 'i', 'v': v};
      } else if (v is double) {
        settings[k] = {'t': 'd', 'v': v};
      } else if (v is List) {
        settings[k] = {'t': 'l', 'v': v.map((e) => '$e').toList()};
      }
    }
    final signatures = await db.select(db.signatures).get();
    // Заметки только с телефона (у серверных — serverId, они вернутся сами).
    final notes = await (db.select(db.notes)
          ..where((n) => n.serverId.isNull() & n.isDeleted.equals(false)))
        .get();
    final secrets = <String, Map<String, String>>{};
    if (includeSecrets) {
      for (final a in accounts) {
        final m = <String, String>{};
        for (final p in _secretPrefixes) {
          final v = await secure.read('$p${a.id}');
          if (v != null && v.isNotEmpty) m[p] = v;
        }
        if (m.isNotEmpty) secrets[a.id] = m;
      }
    }
    AppLogger.info('Резервная копия: ящиков ${accounts.length}, настроек ${settings.length}, '
        'подписей ${signatures.length}, заметок ${notes.length}, пароли: ${includeSecrets ? 'да' : 'нет'}');
    return {
      'accounts': [for (final a in accounts) a.toJson()],
      'settings': settings,
      'signatures': [for (final s in signatures) s.toJson()],
      'notes': [for (final n in notes) n.toJson()],
      'secrets': secrets,
    };
  }

  // ─────────────────────────── чтение ───────────────────────────

  /// Расшифровать файл. Неверный пароль или повреждённый файл —
  /// [BackupException].
  static Future<Map<String, dynamic>> open(Uint8List bytes, String passphrase) async {
    Map<String, dynamic> file;
    try {
      file = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('backupErrFormat');
    }
    if (file['format'] != format) throw const BackupException('backupErrFormat');
    if ((file['version'] as num? ?? 0) > version) throw const BackupException('backupErrNewer');
    try {
      final kdf = file['kdf'] as Map<String, dynamic>;
      final salt = base64.decode(kdf['salt'] as String);
      final iter = (kdf['iter'] as num).toInt();
      final key = await _key(passphrase, Uint8List.fromList(salt), iter);
      final plain = _gcm(false, key, Uint8List.fromList(base64.decode(file['iv'] as String)),
          Uint8List.fromList(base64.decode(file['data'] as String)));
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on InvalidCipherTextException {
      throw const BackupException('backupErrPassword');
    } on ArgumentError {
      throw const BackupException('backupErrPassword');
    } catch (e) {
      if (e is BackupException) rethrow;
      AppLogger.warning('Резервная копия не читается: $e');
      throw const BackupException('backupErrFormat');
    }
  }

  // ─────────────────────────── восстановление ───────────────────────────

  /// Ящики, которые уже есть на телефоне (тот же id или адрес), не
  /// трогаются; настройки из копии заменяют текущие.
  static Future<RestoreReport> restore({
    required Map<String, dynamic> payload,
    required AppDatabase db,
    required SharedPreferences prefs,
    required SecureStorageService secure,
  }) async {
    final existing = await db.select(db.accounts).get();
    final ids = {for (final a in existing) a.id};
    final emails = {for (final a in existing) a.email.trim().toLowerCase()};
    final secrets = (payload['secrets'] as Map?)?.cast<String, dynamic>() ?? const {};
    var added = 0, skipped = 0;
    final addedIds = <String>{};

    for (final raw in (payload['accounts'] as List? ?? const [])) {
      final a = Account.fromJson((raw as Map).cast<String, dynamic>());
      if (ids.contains(a.id) || emails.contains(a.email.trim().toLowerCase())) {
        skipped++;
        continue;
      }
      final hasSecret = (secrets[a.id] as Map?)?.isNotEmpty == true;
      await db.into(db.accounts).insert(a.copyWith(
            lastSyncAt: const Value(null),
            unreadCount: 0,
            certificatePath: const Value(null),
            // Без пароля в копии ящик сразу просит войти (плашка в почте).
            authFailedAt: Value(hasSecret ? null : DateTime.now()),
          ));
      addedIds.add(a.id);
      added++;
    }

    for (final id in addedIds) {
      final m = (secrets[id] as Map?)?.cast<String, dynamic>();
      if (m == null) continue;
      for (final e in m.entries) {
        if (_secretPrefixes.contains(e.key) && e.value is String) {
          await secure.write('${e.key}$id', e.value as String);
        }
      }
    }

    var settings = 0;
    final s = (payload['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final e in s.entries) {
      if (_skipKey(e.key)) continue;
      final m = (e.value as Map).cast<String, dynamic>();
      final v = m['v'];
      switch (m['t']) {
        case 's':
          await prefs.setString(e.key, v as String);
        case 'b':
          await prefs.setBool(e.key, v as bool);
        case 'i':
          await prefs.setInt(e.key, (v as num).toInt());
        case 'd':
          await prefs.setDouble(e.key, (v as num).toDouble());
        case 'l':
          await prefs.setStringList(e.key, [for (final x in v as List) '$x']);
        default:
          continue;
      }
      settings++;
    }

    var sigs = 0;
    for (final raw in (payload['signatures'] as List? ?? const [])) {
      final sig = Signature.fromJson((raw as Map).cast<String, dynamic>());
      await db.into(db.signatures).insertOnConflictUpdate(sig);
      sigs++;
    }

    var notes = 0;
    final noteIds = {for (final n in await db.select(db.notes).get()) n.id};
    for (final raw in (payload['notes'] as List? ?? const [])) {
      final n = Note.fromJson((raw as Map).cast<String, dynamic>());
      if (noteIds.contains(n.id)) continue;
      await db.into(db.notes).insert(n);
      notes++;
    }

    AppLogger.info('Восстановление из копии: ящиков добавлено $added, пропущено $skipped, '
        'настроек $settings, подписей $sigs, заметок $notes');
    return RestoreReport(
      accountsAdded: added,
      accountsSkipped: skipped,
      settings: settings,
      signatures: sigs,
      notes: notes,
      withSecrets: secrets.isNotEmpty,
    );
  }

  // ─────────────────────────── шифрование ───────────────────────────

  /// PBKDF2 в отдельном изоляте: 150 000 итераций — секунда-две на
  /// телефоне, интерфейс не должен замирать.
  static Future<Uint8List> _key(String passphrase, Uint8List salt, int iterations) {
    return Isolate.run(() {
      final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, iterations, 32));
      return d.process(Uint8List.fromList(utf8.encode(passphrase)));
    });
  }

  static Uint8List _gcm(bool encrypt, Uint8List key, Uint8List iv, Uint8List data) {
    final c = GCMBlockCipher(AESEngine())
      ..init(encrypt, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return c.process(data);
  }
}
