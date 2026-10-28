// lib/services/archive/archive_vault.dart
// Архив Ogneliss на этом устройстве: создать, открыть паролем или кодом
// восстановления, сменить пароль, сохранить копию (.ogna), подключить копию,
// закрыть, удалить (1.7.3, docs/plan/ARCHIVE_IDEA.md).
//
// Файлы — в папке данных приложения (ApplicationSupport/archive): база
// `<id>.db` (SQLite3 Multiple Ciphers, ключ архива) и заголовок `<id>.json`
// (ключ архива в конвертах паролем и кодом). Ключ архива на устройстве — в
// защищённом хранилище системы: пароль спрашивается только при подключении
// копии на новом устройстве, после переустановки или после «Закрыть архив».
//
// Сейчас архив один; файлы и ключи названы по id архива — несколько архивов
// (тома по годам, архив коллеги) добавятся без переделки хранения.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as s3;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'archive_container.dart';
import 'archive_crypto.dart';
import 'archive_db.dart';

enum ArchiveStatus {
  /// Архива на устройстве нет.
  none,

  /// Архив есть, ключа на устройстве нет — нужен пароль или код.
  locked,

  /// Открыт: виден в меню, участвует в поиске, в него пишет архивация.
  open,
}

/// Как открыли архив: паролем, кодом восстановления (тогда стоит задать
/// новый пароль) или не открыли.
enum ArchiveUnlock { wrong, password, code }

class ArchiveVaultState {
  final ArchiveStatus status;
  final ArchiveHeader? header;

  /// Растёт после каждой записи в архив — списки и счётчики перечитываются.
  final int revision;

  /// Когда последний раз сохранялась копия архива (.ogna).
  final DateTime? lastCopy;

  const ArchiveVaultState(this.status, {this.header, this.revision = 0, this.lastCopy});

  bool get isOpen => status == ArchiveStatus.open;
  bool get exists => status != ArchiveStatus.none;

  ArchiveVaultState copyWith({ArchiveStatus? status, ArchiveHeader? header, int? revision, DateTime? lastCopy}) =>
      ArchiveVaultState(
        status ?? this.status,
        header: header ?? this.header,
        revision: revision ?? this.revision,
        lastCopy: lastCopy ?? this.lastCopy,
      );
}

final archiveVaultProvider = AsyncNotifierProvider<ArchiveVault, ArchiveVaultState>(ArchiveVault.new);

/// Открытая база архива (null — архива нет или он закрыт). Перечитывается
/// при каждой записи в архив.
final archiveDbProvider = Provider<ArchiveDb?>((ref) {
  final s = ref.watch(archiveVaultProvider).value;
  if (s == null || !s.isOpen) return null;
  return ref.read(archiveVaultProvider.notifier).db;
});

class ArchiveVault extends AsyncNotifier<ArchiveVaultState> {
  static const _kActive = 'ogna_active_id';
  static const _kLastCopy = 'ogna_last_copy_ms';
  static String _keyName(String id) => 'ogna_key_$id';

  /// Короче пароль архива не бывает.
  static const minPassword = 8;

  ArchiveDb? _db;
  Uint8List? _key;

  ArchiveDb? get db => _db;

  @override
  Future<ArchiveVaultState> build() async {
    ref.onDispose(() {
      final d = _db;
      _db = null;
      _key = null;
      if (d != null) unawaited(d.close());
    });
    final prefs = ref.read(sharedPrefsProvider);
    final copyMs = prefs.getInt(_kLastCopy);
    final lastCopy = copyMs == null ? null : DateTime.fromMillisecondsSinceEpoch(copyMs);
    final id = prefs.getString(_kActive);
    if (id == null) return const ArchiveVaultState(ArchiveStatus.none);
    final header = await _readHeader(id);
    final dbFile = await _dbFile(id);
    if (header == null || !await dbFile.exists()) {
      // Файлы пропали (очистка данных приложения) — архива на устройстве нет.
      AppLogger.warning('Архив Ogneliss: файлы архива не найдены — архив не подключён');
      await prefs.remove(_kActive);
      return ArchiveVaultState(ArchiveStatus.none, lastCopy: lastCopy);
    }
    String? hex;
    try {
      hex = await ref.read(secureStorageProvider).read(_keyName(id));
    } catch (e) {
      AppLogger.warning('Архив Ogneliss: ключ из хранилища не прочитан: $e');
    }
    if (hex == null || hex.length != 64) {
      return ArchiveVaultState(ArchiveStatus.locked, header: header, lastCopy: lastCopy);
    }
    try {
      await _open(id, ArchiveCrypto.unhex(hex));
      return ArchiveVaultState(ArchiveStatus.open, header: header, lastCopy: lastCopy);
    } catch (e) {
      AppLogger.warning('Архив Ogneliss не открылся сохранённым ключом: $e');
      return ArchiveVaultState(ArchiveStatus.locked, header: header, lastCopy: lastCopy);
    }
  }

  ArchiveVaultState get _now => state.value ?? const ArchiveVaultState(ArchiveStatus.none);

  // ── файлы ──

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'archive'));
    await d.create(recursive: true);
    return d;
  }

  static Future<File> _dbFile(String id) async => File(p.join((await _dir()).path, '$id.db'));
  static Future<File> _headerFile(String id) async => File(p.join((await _dir()).path, '$id.json'));

  static Future<ArchiveHeader?> _readHeader(String id) async {
    try {
      final f = await _headerFile(id);
      if (!await f.exists()) return null;
      return ArchiveHeader.decode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeHeader(ArchiveHeader h) async {
    final f = await _headerFile(h.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(h.encode(), flush: true);
    await tmp.rename(f.path);
  }

  /// Есть ли шифрование в загруженной библиотеке SQLite (сборка с
  /// sqlite3mc). Без него архив не создаётся: он лежал бы открытым текстом.
  static bool cipherAvailable() {
    try {
      final probe = s3.sqlite3.openInMemory();
      try {
        return probe.select('PRAGMA cipher').isNotEmpty;
      } finally {
        probe.close();
      }
    } catch (_) {
      return false;
    }
  }

  static ArchiveDb _connect(File file, Uint8List key) {
    final hex = ArchiveCrypto.hex(key);
    return ArchiveDb(NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        raw.execute("PRAGMA key = '$hex';");
        raw.execute('PRAGMA busy_timeout = 5000;');
      },
    ));
  }

  Future<void> _open(String id, Uint8List key) async {
    await _close();
    final db = _connect(await _dbFile(id), key);
    try {
      await db.check();
    } catch (_) {
      await db.close();
      rethrow;
    }
    _db = db;
    _key = key;
  }

  Future<void> _close() async {
    final d = _db;
    _db = null;
    _key = null;
    if (d != null) {
      try {
        await d.close();
      } catch (_) {}
    }
  }

  // ── создание и открытие ──

  /// Создать архив. Возвращает код восстановления — показать один раз.
  Future<String> create({required String password, required String name}) async {
    if (password.length < minPassword) throw const ArchiveFormatException('archivePwShort');
    if (_now.exists) throw const ArchiveFormatException('archiveAlreadyExists');
    if (!cipherAvailable()) throw const ArchiveFormatException('archiveNoCipher');
    final id = ArchiveCrypto.hex(ArchiveCrypto.randomBytes(8));
    final key = ArchiveCrypto.newArchiveKey();
    final code = ArchiveCrypto.newRecoveryCode();
    final header = ArchiveHeader(
      id: id,
      name: name.trim(),
      created: DateTime.now(),
      app: AppConstants.appVersion,
      keys: {
        'password': await ArchiveCrypto.wrap(key, password, iterations: ArchiveCrypto.passwordIterations),
        'code': await ArchiveCrypto.wrap(key, ArchiveCrypto.normalizeCode(code),
            iterations: ArchiveCrypto.codeIterations),
      },
    );
    await _writeHeader(header);
    await _open(id, key);
    await _db!.setMeta('name', header.name);
    await ref.read(secureStorageProvider).write(_keyName(id), ArchiveCrypto.hex(key));
    await ref.read(sharedPrefsProvider).setString(_kActive, id);
    AppLogger.info('Архив Ogneliss создан');
    state = AsyncData(ArchiveVaultState(ArchiveStatus.open, header: header, lastCopy: _now.lastCopy));
    return code;
  }

  /// Ключ архива паролем или кодом восстановления из заголовка [h].
  static Future<({Uint8List? key, ArchiveUnlock how})> _unwrap(ArchiveHeader h, String secret) async {
    final pw = h.keys['password'];
    final cd = h.keys['code'];
    if (ArchiveCrypto.looksLikeCode(secret) && cd != null) {
      final k = await ArchiveCrypto.unwrap(cd, ArchiveCrypto.normalizeCode(secret));
      if (k != null) return (key: k, how: ArchiveUnlock.code);
    }
    if (pw != null && secret.isNotEmpty) {
      final k = await ArchiveCrypto.unwrap(pw, secret);
      if (k != null) return (key: k, how: ArchiveUnlock.password);
    }
    return (key: null, how: ArchiveUnlock.wrong);
  }

  /// Открыть закрытый архив паролем или кодом восстановления.
  Future<ArchiveUnlock> unlock(String secret) async {
    final h = _now.header;
    if (h == null || _now.status != ArchiveStatus.locked) return ArchiveUnlock.wrong;
    final r = await _unwrap(h, secret);
    final key = r.key;
    if (key == null) return ArchiveUnlock.wrong;
    try {
      await _open(h.id, key);
    } catch (e) {
      AppLogger.warning('Архив Ogneliss: ключ подошёл, база не открылась: $e');
      throw const ArchiveFormatException('archiveBroken');
    }
    await ref.read(secureStorageProvider).write(_keyName(h.id), ArchiveCrypto.hex(key));
    state = AsyncData(_now.copyWith(status: ArchiveStatus.open, revision: _now.revision + 1));
    return r.how;
  }

  /// Новый пароль архива (архив открыт; после входа кодом — обязательно).
  Future<void> setPassword(String password) async {
    final h = _now.header;
    final key = _key;
    if (h == null || key == null) throw const ArchiveFormatException('archiveLocked');
    if (password.length < minPassword) throw const ArchiveFormatException('archivePwShort');
    final env = await ArchiveCrypto.wrap(key, password, iterations: ArchiveCrypto.passwordIterations);
    final next = h.copyWith(keys: {...h.keys, 'password': env});
    await _writeHeader(next);
    state = AsyncData(_now.copyWith(header: next));
    AppLogger.info('Архив Ogneliss: пароль изменён');
  }

  /// Новый код восстановления (прежний перестаёт действовать).
  Future<String> renewRecoveryCode() async {
    final h = _now.header;
    final key = _key;
    if (h == null || key == null) throw const ArchiveFormatException('archiveLocked');
    final code = ArchiveCrypto.newRecoveryCode();
    final env =
        await ArchiveCrypto.wrap(key, ArchiveCrypto.normalizeCode(code), iterations: ArchiveCrypto.codeIterations);
    final next = h.copyWith(keys: {...h.keys, 'code': env});
    await _writeHeader(next);
    state = AsyncData(_now.copyWith(header: next));
    AppLogger.info('Архив Ogneliss: новый код восстановления');
    return code;
  }

  /// Проверить пароль архива (перед удалением архива или сменой пароля).
  Future<bool> checkSecret(String secret) async {
    final h = _now.header;
    if (h == null) return false;
    return (await _unwrap(h, secret)).key != null;
  }

  /// Закрыть архив на этом устройстве: ключ забывается, файл остаётся;
  /// открыть снова — паролем или кодом.
  Future<void> lock() async {
    final h = _now.header;
    await _close();
    if (h != null) {
      try {
        await ref.read(secureStorageProvider).delete(_keyName(h.id));
      } catch (_) {}
    }
    state = AsyncData(_now.copyWith(status: h == null ? ArchiveStatus.none : ArchiveStatus.locked));
  }

  /// Удалить архив с устройства (копии .ogna в других местах остаются).
  Future<void> deleteArchive() async {
    final h = _now.header;
    await _close();
    if (h != null) {
      final db = await _dbFile(h.id);
      for (final f in [
        db,
        File('${db.path}-journal'),
        File('${db.path}-wal'),
        File('${db.path}-shm'),
        await _headerFile(h.id),
      ]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (e) {
          AppLogger.warning('Архив Ogneliss: файл не удалён ${p.basename(f.path)}: $e');
        }
      }
      try {
        await ref.read(secureStorageProvider).delete(_keyName(h.id));
      } catch (_) {}
    }
    await ref.read(sharedPrefsProvider).remove(_kActive);
    AppLogger.info('Архив Ogneliss удалён с устройства');
    state = AsyncData(ArchiveVaultState(ArchiveStatus.none, lastCopy: _now.lastCopy));
  }

  /// Записи в архиве изменились — перечитать списки.
  void touch() {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(s.copyWith(revision: s.revision + 1));
  }

  // ── копия (.ogna) ──

  /// Имя файла копии: «ogneliss-archive-2026-10-25.ogna».
  static String copyName(DateTime d) =>
      'ogneliss-archive-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.ogna';

  /// Собрать файл .ogna во временной папке (для «Сохранить копию»). На время
  /// сборки база закрывается: копия — целая, без недописанной транзакции.
  Future<File> buildCopy() async {
    final h = _now.header;
    final key = _key;
    if (h == null || key == null) throw const ArchiveFormatException('archiveLocked');
    final tmpDir = await getTemporaryDirectory();
    final out = File(p.join(tmpDir.path, copyName(DateTime.now())));
    await _close();
    try {
      await ArchiveContainer.write(out, h, await _dbFile(h.id));
    } finally {
      await _open(h.id, key);
      touch();
    }
    return out;
  }

  /// Копия сохранена (человек выбрал, куда) — запомнить дату.
  Future<void> markCopied() async {
    final now = DateTime.now();
    await ref.read(sharedPrefsProvider).setInt(_kLastCopy, now.millisecondsSinceEpoch);
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(lastCopy: now));
  }

  /// Подключить копию архива [file] (.ogna) паролем или кодом. На устройстве
  /// архива быть не должно (несколько архивов — позже).
  Future<ArchiveUnlock> connect(File file, String secret) async {
    if (_now.exists) throw const ArchiveFormatException('archiveAlreadyExists');
    if (!cipherAvailable()) throw const ArchiveFormatException('archiveNoCipher');
    final parsed = await ArchiveContainer.readHeader(file);
    final h = parsed.header;
    final r = await _unwrap(h, secret);
    final key = r.key;
    if (key == null) return ArchiveUnlock.wrong;
    final dbFile = await _dbFile(h.id);
    try {
      if (await dbFile.exists()) await dbFile.delete();
      await ArchiveContainer.extractDb(file, parsed.dataOffset, dbFile);
      await _writeHeader(h);
      await _open(h.id, key);
    } catch (e) {
      AppLogger.warning('Архив Ogneliss: копия не подключена: $e');
      await _close();
      for (final f in [dbFile, await _headerFile(h.id)]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (e is ArchiveFormatException) rethrow;
      throw const ArchiveFormatException('archiveBroken');
    }
    await ref.read(secureStorageProvider).write(_keyName(h.id), ArchiveCrypto.hex(key));
    await ref.read(sharedPrefsProvider).setString(_kActive, h.id);
    AppLogger.info('Архив Ogneliss подключён из копии');
    state = AsyncData(ArchiveVaultState(ArchiveStatus.open, header: h, lastCopy: _now.lastCopy));
    return r.how;
  }

  /// Размер базы архива на устройстве (байты).
  Future<int> sizeOnDevice() async {
    final h = _now.header;
    if (h == null) return 0;
    try {
      return await (await _dbFile(h.id)).length();
    } catch (_) {
      return 0;
    }
  }
}
