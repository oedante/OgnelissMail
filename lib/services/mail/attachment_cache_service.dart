// lib/services/mail/attachment_cache_service.dart
// LRU-кеш скачанных вложений с лимитом по суммарному размеру.
// Файлы хранятся на диске; при превышении лимита вытесняются самые
// давно использованные (least-recently-used).

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/security/attachment_safety.dart';

import '../../core/logging/app_logger.dart';

final attachmentCacheProvider = Provider<AttachmentCacheService>((ref) {
  return AttachmentCacheService();
});

class AttachmentCacheService {
  static const _kIndex = 'attachment_cache_index';
  static const _kMaxBytes = 'attachment_cache_max_bytes';

  /// Ступень изменения порога и границы. Ноль запрещён: без кэша каждое
  /// открытие вложения снова качало бы файл из сети.
  static const stepBytes = 50 * 1024 * 1024;   // 50 МБ
  static const minBytes = 50 * 1024 * 1024;    // минимум — одна ступень
  static const maxAllowedBytes = 5 * 1024 * 1024 * 1024; // 5 ГБ — разумный потолок
  static const defaultMaxBytes = 500 * 1024 * 1024;

  /// Порог, после которого включается автоочистка (настраивается).
  int maxBytes = defaultMaxBytes;

  /// Чистим не «впритык» к порогу, а с запасом: иначе после достижения лимита
  /// КАЖДОЕ новое вложение запускало бы вытеснение (постоянная пробуксовка).
  /// Освобождаем до 90% порога — запас на ~10%.
  static const _evictToFraction = 0.9;

  /// Сколько держать вложение, к которому не обращались. Кэш существует ради
  /// «не качать повторно то, чем пользуются»; забытое место занимать не должно.
  static const staleAfter = Duration(days: 3);

  Directory? _cacheDir;
  // attachmentId -> {file, size, lastAccess}
  Map<String, _CacheEntry> _index = {};

  /// Индекс прочитан ([init]). В фоновом изоляте кэш не открывается —
  /// запись туда переписала бы чужой индекс неполным.
  bool get isReady => _ready;
  bool _ready = false;

  Future<void> init() async {
    await _dir();
    final prefs = await SharedPreferences.getInstance();
    maxBytes = prefs.getInt(_kMaxBytes) ?? defaultMaxBytes;
    final raw = prefs.getString(_kIndex);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _index = map.map((k, v) => MapEntry(k, _CacheEntry.fromJson(v as Map<String, dynamic>)));
      } catch (_) {}
    }
    _ready = true;
    // Файлы могли пропасть, пока приложение не работало (очистка системой).
    unawaited(reconcile());
  }

  /// Убрать из индекса записи, файлов которых нет на диске. Каталог кэша
  /// может очистить система (мало места) или «очистка» оболочки (Huawei,
  /// журнал 23.10.2026): файлов уже нет, а «Хранилище» по индексу показывало
  /// «35.5 МБ, файлов 288». Возвращает, сколько записей убрано.
  Future<int> reconcile() async {
    final gone = <String>[];
    for (final e in _index.entries.toList()) {
      try {
        if (!await File(e.value.path).exists()) gone.add(e.key);
      } catch (_) {}
    }
    if (gone.isEmpty) return 0;
    for (final k in gone) {
      _index.remove(k);
      _removed.add(k);
    }
    await _persist();
    AppLogger.info('Кэш вложений: файлов нет на диске — убрано записей: ${gone.length}');
    return gone.length;
  }

  /// Каталог кэша — есть на диске. 1.7.2 (журнал Huawei EMUI 23.10.2026):
  /// каталог вложений лежит в кэше приложения, и его может удалить система
  /// (мало места) или «очистка» оболочки производителя. Путь запоминался при
  /// запуске, и до перезапуска приложения КАЖДАЯ запись падала с
  /// «PathNotFoundException: Cannot open file» — вложения не открывались
  /// («Ошибка»), картинки и предзагрузка не сохранялись. Теперь каталог
  /// проверяется и при необходимости создаётся перед каждой записью.
  Future<Directory> _dir() async {
    var d = _cacheDir;
    if (d == null) {
      final base = await getApplicationCacheDirectory();
      d = Directory('${base.path}/attachments');
      _cacheDir = d;
    }
    if (!await d.exists()) {
      await d.create(recursive: true);
      // Каталог пропал вместе с файлами — записи индекса без файлов убрать.
      AppLogger.warning('Кэш вложений: каталог удалён системой — создан заново');
      if (_index.isNotEmpty) unawaited(reconcile());
    }
    return d;
  }

  // ignore: unused_element
  String _keyFor(String attachmentId) =>
      sha256.convert(utf8.encode(attachmentId)).toString().substring(0, 32);

  /// Получить путь к кешированному файлу или null, если нет.
  /// Есть ли запись в кэше — без проверки файла и без отметки «открывали»
  /// (для фоновых проверок «докачивать ли»: они не должны продлевать жизнь
  /// записи и писать индекс).
  bool has(String attachmentId) => _index.containsKey(attachmentId);

  Future<String?> get(String attachmentId) async {
    final entry = _index[attachmentId];
    if (entry == null) return null;
    final file = File(entry.path);
    if (!await file.exists()) {
      _index.remove(attachmentId);
      await _persist();
      return null;
    }
    // Обновляем время доступа (LRU). Индекс записывается не сразу, а через
    // несколько секунд одним разом (1.5.6): раньше каждое чтение перечитывало
    // и перезаписывало весь индекс в настройках (сотни записей, JSON на
    // главном потоке) — письмо с картинками в подписи открывалось с рывком, а
    // «Письма на телефоне» гоняли индекс сотни раз за проход.
    entry.lastAccess = DateTime.now().millisecondsSinceEpoch;
    _persistSoon();
    return entry.path;
  }

  Timer? _persistTimer;

  /// Записать индекс чуть позже — для отметок «открывали», которые не
  /// обязательно сохранять немедленно.
  void _persistSoon() {
    _persistTimer ??= Timer(const Duration(seconds: 3), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  /// Сохранить вложение в кеш. Возвращает путь к файлу.
  ///
  /// Файл адресуется ХЭШЕМ СОДЕРЖИМОГО (MD5): один и тот же документ,
  /// приложенный к десяткам писем (пересылки, длинный тред), лежит на диске
  /// ОДИН раз. Индекс же ведётся по attachmentId — именно он известен ДО
  /// загрузки и позволяет не качать повторно. MD5 здесь не для стойкости, а для
  /// адресации: он быстрый, а подмена содержимого нам не угрожает.
  ///
  /// [deferPersist] — индекс записать чуть позже, одним разом (проход
  /// «Писем на телефоне» кладёт сотни картинок подряд); в конце прохода —
  /// [flush].
  Future<String> put(String attachmentId, String fileName, List<int> bytes,
      {DateTime? keepUntil, bool deferPersist = false}) async {
    final dir = await _dir();

    var safeName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    // Имя файла в Android и iOS — до 255 байт; длинные имена вложений
    // (темы писем, перечни) укорачиваем, сохраняя расширение.
    if (safeName.length > 120) {
      final dot = safeName.lastIndexOf('.');
      final ext = dot > 0 && safeName.length - dot <= 10 ? safeName.substring(dot) : '';
      safeName = safeName.substring(0, 120 - ext.length) + ext;
    }
    final digest = md5.convert(bytes).toString();
    final path = '${dir.path}/${digest}_$safeName';
    final file = File(path);
    // Уже лежит (то же содержимое из другого письма) — не переписываем.
    if (!await file.exists() || await file.length() != bytes.length) {
      try {
        await file.writeAsBytes(bytes);
      } on PathNotFoundException {
        // Каталог удалили между проверкой и записью — создать и повторить.
        await dir.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      // Windows: метка «из интернета» — SmartScreen и защищённый режим Office.
      await AttachmentSafety.markFromInternet(path);
    }

    _index[attachmentId] = _CacheEntry(
      path: path,
      size: bytes.length,
      lastAccess: DateTime.now().millisecondsSinceEpoch,
      keepUntil: keepUntil?.millisecondsSinceEpoch ?? 0,
    );
    await _evictIfNeeded();
    if (deferPersist) {
      _persistSoon();
    } else {
      await _persist();
    }
    return path;
  }

  /// Записать отложенный индекс сейчас (конец прохода «Писем на телефоне»:
  /// фоновый изолят может завершиться раньше, чем сработает таймер).
  Future<void> flush() async {
    final t = _persistTimer;
    if (t == null) return;
    t.cancel();
    _persistTimer = null;
    await _persist();
  }

  /// Сколько записей индекса ссылается на файл. Нужен из-за дедупликации:
  /// удалять файл можно, только когда на него не осталось ссылок.
  int _refs(String path) =>
      _index.values.where((e) => e.path == path).length;

  /// Текущий суммарный размер кеша. Считаем УНИКАЛЬНЫЕ файлы: при дедупликации
  /// несколько записей указывают на один файл, и суммирование по записям
  /// завысило бы размер в разы.
  int get currentBytes {
    final seen = <String, int>{};
    for (final e in _index.values) {
      seen[e.path] = e.size;
    }
    return seen.values.fold(0, (s, v) => s + v);
  }

  /// Убрать запись и, если на файл больше никто не ссылается, удалить файл.
  /// Без проверки ссылок дедупликация ломалась бы: удаление одной записи
  /// стирало бы файл, нужный другим письмам.
  Future<void> _removeEntry(String attachmentId) async {
    final entry = _index.remove(attachmentId);
    if (entry == null) return;
    _removed.add(attachmentId);
    if (_refs(entry.path) > 0) return; // файл ещё нужен другому вложению
    try {
      final f = File(entry.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Убрать всё, что не открывали дольше [ttl]. Кэш нужен, чтобы не качать
  /// повторно то, чем пользуются; давно забытое просто занимает место.
  Future<int> evictStale({Duration ttl = staleAfter}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final deadline = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    final stale = _index.entries
        .where((e) => e.value.lastAccess < deadline && e.value.keepUntil < now)
        .map((e) => e.key)
        .toList();
    for (final id in stale) {
      await _removeEntry(id);
    }
    if (stale.isNotEmpty) {
      await _persist();
      AppLogger.info('Attachment cache: убрано по давности — ${stale.length}');
    }
    return stale.length;
  }

  /// Вытеснение LRU при превышении лимита. Сначала убираем просроченные по
  /// давности — обычно этого уже достаточно.
  Future<void> _evictIfNeeded() async {
    await evictStale();
    var total = currentBytes;
    if (total <= maxBytes) return;
    // Цель — 90% порога, а не сам порог: даём запас, чтобы следующая пара
    // вложений не вызывала чистку заново.
    final target = (maxBytes * _evictToFraction).round();
    // Сортируем по времени доступа (старые — первыми)
    final entries = _index.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));
    for (final e in entries) {
      if (total <= target) break;
      final path = e.value.path;
      final size = e.value.size;
      await _removeEntry(e.key);
      // Место освободилось, только если файл действительно удалён.
      if (_refs(path) == 0) total -= size;
      AppLogger.debug('Attachment cache: вытеснен ${e.key}');
    }
  }

  /// Изменить порог: округляем к ступени 50 МБ и держим в границах.
  /// Ноль недопустим — хоть какой-то кэш нужен всегда.
  Future<void> setMaxBytes(int bytes) async {
    final stepped = (bytes / stepBytes).round() * stepBytes;
    maxBytes = stepped.clamp(minBytes, maxAllowedBytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxBytes, maxBytes);
    await _evictIfNeeded(); // порог мог стать меньше текущего размера
    await _persist();
  }

  /// Сколько файлов сейчас в кэше (уникальных).
  int get fileCount => _index.values.map((e) => e.path).toSet().length;

  /// Убрать вложения аккаунта (ключи кэша — «аккаунт|письмо|вложение»).
  /// Вызывается при удалении аккаунта: файлы чужого уже ящика не должны
  /// оставаться на устройстве.
  Future<void> removeForAccount(String accountId) async {
    final keys = _index.keys.where((k) => k.startsWith('$accountId|')).toList();
    for (final k in keys) {
      await _removeEntry(k);
    }
    if (keys.isNotEmpty) await _persist();
  }

  /// Убрать вложения одного письма (защищённое письмо закрыли — файлы не
  /// остаются на устройстве).
  Future<int> removeForEmail(String accountId, String emailId) async {
    final keys = _index.keys.where((k) => k.startsWith('$accountId|$emailId|')).toList();
    for (final k in keys) {
      await _removeEntry(k);
    }
    if (keys.isNotEmpty) await _persist();
    return keys.length;
  }

  /// Ключи кэша («аккаунт|письмо|вложение»).
  List<String> get keys => _index.keys.toList();

  /// Индекс загружен (фоновая синхронизация идёт в своём изоляте).
  Future<void> ensureLoaded() async {
    if (_cacheDir == null) await init();
  }

  /// Убрать записи [keys]; файл удаляется, когда на него не осталось ссылок.
  Future<int> removeKeys(Iterable<String> keys) async {
    var n = 0;
    for (final k in keys) {
      if (_index.containsKey(k)) {
        await _removeEntry(k);
        n++;
      }
    }
    if (n > 0) await _persist();
    return n;
  }

  Future<void> clear() async {
    for (final e in _index.values) {
      try {
        final f = File(e.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    // Файлы, учтённые только другим изолятом, тоже убираем.
    try {
      final dir = _cacheDir;
      if (dir != null && await dir.exists()) {
        await for (final f in dir.list()) {
          if (f is File) await f.delete();
        }
      }
    } catch (_) {}
    _index.clear();
    _removed.clear();
    await _persist(merge: false); // «Очистить кэш» — полностью, без слияния
  }

  /// Ключи, удалённые этим экземпляром: при слиянии с индексом на диске их
  /// нельзя «воскрешать».
  final Set<String> _removed = {};

  Future<void> _persist({bool merge = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (merge) {
      // Фоновый изолят (WorkManager, предзагрузка вложений) держит свою копию
      // индекса. Раньше каждый экземпляр записывал только свою копию и затирал
      // чужие записи — файлы оставались на диске без учёта. Перед записью
      // перечитываем индекс и сливаем: чужие новые записи добавляем,
      // время доступа берём наибольшее.
      try {
        await prefs.reload();
        final raw = prefs.getString(_kIndex);
        if (raw != null) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          for (final e in map.entries) {
            if (_removed.contains(e.key)) continue;
            final other = _CacheEntry.fromJson(e.value as Map<String, dynamic>);
            final mine = _index[e.key];
            if (mine == null) {
              if (File(other.path).existsSync()) _index[e.key] = other;
            } else if (other.lastAccess > mine.lastAccess && other.path == mine.path) {
              mine.lastAccess = other.lastAccess;
            }
          }
        }
      } catch (_) {}
    }
    await prefs.setString(_kIndex,
        jsonEncode(_index.map((k, v) => MapEntry(k, v.toJson()))));
  }
}

class _CacheEntry {
  final String path;
  final int size;
  int lastAccess;

  /// Не убирать по давности до этого момента (мс): картинки свежих писем,
  /// загруженные заранее, живут весь срок «Картинки в письмах», даже если
  /// письмо не открывали.
  final int keepUntil;
  _CacheEntry({required this.path, required this.size, required this.lastAccess, this.keepUntil = 0});

  Map<String, dynamic> toJson() =>
      {'path': path, 'size': size, 'lastAccess': lastAccess, if (keepUntil > 0) 'keepUntil': keepUntil};
  factory _CacheEntry.fromJson(Map<String, dynamic> j) => _CacheEntry(
        path: j['path'] as String,
        size: j['size'] as int,
        lastAccess: j['lastAccess'] as int,
        keepUntil: (j['keepUntil'] as int?) ?? 0,
      );
}
