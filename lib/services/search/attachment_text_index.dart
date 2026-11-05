// lib/services/search/attachment_text_index.dart
// Текст вложений в поисковом индексе (1.12.x, поиск по тексту вложений,
// просьба владельца 04.11.2026; Настройки → Почта → «Искать в тексте
// вложений», по умолчанию включено).
//
// Когда: сразу после того, как вложение легло в кэш (открыли, предзагрузка
// режима «с вложениями», картинки «Писем на телефоне» — откуда угодно:
// AttachmentCacheService.added), и понемногу — для файлов, которые уже в
// кэше (после обновления приложения, скачанные фоновой синхронизацией):
// [backfill] вызывает проход «Писем на телефоне» после синхронизации ящика,
// небольшими порциями и не на экономии заряда. Работа — с приоритетом
// обслуживания планировщика (уступает открытому письму), разбор — в
// отдельном изоляте (AttachmentText.extractFile).
//
// Где: столбец attachments_text строки письма в emails_fts. У письма бывает
// несколько вложений, а файлы из кэша уходят (через 3 дня без открытия) —
// поэтому текст каждого вложения хранится своей частью: метка вложения
// (управляющие символы U+001E, 12 знаков из U+0001–U+0008 и U+000E–U+0015,
// U+001F — для поиска это разделители, словами они не становятся), затем
// его текст. Повторное извлечение заменяет свою часть, текст ушедших из кэша
// файлов остаётся, а «уже прочитано» проверяется по метке прямо в индексе —
// без отдельной таблицы и без записей в настройках (схема базы не меняется;
// фоновый изолят видит то же, что и приложение). Вложение без текста
// (картинка внутри документа, повреждённый файл) — метка без текста: его не
// разбирают снова.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/text_safe.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../features/settings/providers/settings_provider.dart';
import '../background/work_scheduler.dart';
import '../mail/attachment_cache_service.dart';
import 'attachment_text.dart';

final attachmentTextIndexProvider = Provider<AttachmentTextIndex>((ref) => AttachmentTextIndex(ref));

class AttachmentTextIndex {
  AttachmentTextIndex(this._ref);
  final Ref _ref;

  /// Файлов за проход [backfill]: приложение открыто или телефон на
  /// зарядке — и в фоне на батарее.
  static const batch = 12;
  static const batchQuick = 3;

  bool get enabled => _ref.read(settingsProvider).searchAttachments;

  StreamSubscription<CachedAttachment>? _sub;

  /// Ключи кэша, которые в этом процессе уже разобраны или пропущены.
  final Set<String> _done = {};

  /// Очередь разбора (по порядку добавления): ключ кэша → имя вложения.
  final Map<String, String?> _queue = {};
  bool _draining = false;
  final Set<String> _backfilling = {};

  /// Слушать кэш вложений и настройку (main.dart, после AttachmentCacheService.init).
  void start() {
    if (kIsWeb || _sub != null) return;
    _sub = _ref.read(attachmentCacheProvider).added.listen(_onCached);
    _ref.listen<bool>(settingsProvider.select((s) => s.searchAttachments), (prev, on) {
      if (prev == on) return;
      if (on) {
        // Включили снова — файлы, которые ещё в кэше, разбираются заново.
        for (final a in _ref.read(accountsProvider)) {
          unawaited(backfill(a.id));
        }
      } else {
        unawaited(clear());
      }
    });
  }

  void _onCached(CachedAttachment c) {
    if (!enabled) return;
    if (AttachmentText.kindOf(c.fileName) == null && AttachmentText.kindOf(nameFromPath(c.path)) == null) return;
    _done.remove(c.key);
    _queue[c.key] = c.fileName;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      // Файл только что открыли: предпросмотр разбирает его сам — не мешаем.
      await Future<void>.delayed(const Duration(seconds: 3));
      while (_queue.isNotEmpty && enabled) {
        final key = _queue.keys.first;
        final name = _queue.remove(key);
        await WorkScheduler.instance.run(WorkPriority.idle, () => _process(key, name));
      }
    } finally {
      _draining = false;
      _queue.clear();
    }
  }

  /// Понемногу разобрать файлы ящика, которые уже лежат в кэше, но ещё не в
  /// индексе. [quick] — свёрнутое приложение на батарее: меньше файлов.
  /// Возвращает, сколько файлов разобрано.
  Future<int> backfill(String accountId, {bool quick = false}) async {
    if (kIsWeb || !enabled || !_backfilling.add(accountId)) return 0;
    var n = 0;
    try {
      final cache = _ref.read(attachmentCacheProvider);
      await cache.ensureLoaded();
      final prefix = '$accountId|';
      final cand = <String, ({String accountId, String emailId, String needle})>{};
      for (final k in cache.keys) {
        if (!k.startsWith(prefix) || _done.contains(k) || _queue.containsKey(k)) continue;
        final p = parseKey(k);
        final path = cache.pathOf(k);
        if (p == null || path == null) continue;
        // Картинки и архивы — по имени файла, без базы.
        if (AttachmentText.kindOf(nameFromPath(path)) == null) {
          _done.add(k);
          continue;
        }
        cand[k] = (accountId: p.accountId, emailId: p.emailId, needle: '$_start${markerOf(p.attachmentId)}');
      }
      if (cand.isEmpty) return 0;
      final db = _ref.read(databaseProvider);
      final indexed = await db.ftsAttachmentsContaining(cand);
      _done.addAll(indexed);
      final todo = [
        for (final k in cand.keys)
          if (!indexed.contains(k)) k,
      ];
      final started = DateTime.now();
      var tried = 0;
      final maxRun = quick ? const Duration(seconds: 40) : const Duration(minutes: 3);
      for (final k in todo.take(quick ? batchQuick : batch)) {
        if (!enabled || DateTime.now().difference(started) > maxRun) break;
        tried++;
        if (await WorkScheduler.instance.run(WorkPriority.idle, () => _process(k, null))) n++;
      }
      if (n > 0) AppLogger.debug('Поиск по вложениям: разобрано файлов $n, ждут ${todo.length - tried}');
    } catch (e) {
      AppLogger.debug('Поиск по вложениям: $e');
    } finally {
      _backfilling.remove(accountId);
    }
    return n;
  }

  /// Выключили настройку: текст вложений — из всего индекса.
  Future<void> clear() async {
    _queue.clear();
    _done.clear();
    try {
      final n = await _ref.read(databaseProvider).clearFtsAttachmentsText();
      if (n > 0) AppLogger.info('Поиск по вложениям выключен: текст убран у писем — $n');
    } catch (e) {
      AppLogger.debug('Поиск по вложениям: очистка — $e');
    }
  }

  /// Разобрать файл кэша [key]; true — файл прочитан.
  Future<bool> _process(String key, String? fileName) async {
    if (!enabled || !_done.add(key)) return false;
    final p = parseKey(key);
    final path = _ref.read(attachmentCacheProvider).pathOf(key);
    if (p == null || path == null) return false;
    try {
      final db = _ref.read(databaseProvider);
      // Имя и тип — из письма (у файла в кэше имя упрощено); письма нет
      // (черновик редактора, удалено) — нечего индексировать.
      final e = db.emails;
      final row =
          await (db.selectOnly(e)
                ..addColumns([e.attachmentsJson])
                ..where(e.accountId.equals(p.accountId) & e.id.equals(p.emailId))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) return false;
      final att = _attachment(row.read(e.attachmentsJson), p.attachmentId);
      final name = att?.name ?? fileName ?? nameFromPath(path);
      final mime = att?.mimeType;
      if (AttachmentText.kindOf(name, mimeType: mime) == null) return false;
      final lang = _ref.read(settingsProvider).locale.languageCode;
      final got = await AttachmentText.extractFile(path, name, mimeType: mime, lang: lang);
      if (got.retryLater) {
        // В следующий запуск приложения — снова (файл появится, старый
        // формат Office научится читаться).
        return true;
      }
      if (!enabled) return true;
      final before = await db.ftsAttachmentsText(p.accountId, p.emailId) ?? '';
      final after = merge(before, p.attachmentId, got.text);
      if (after != before) await db.setFtsAttachmentsText(p.accountId, p.emailId, after);
      return true;
    } catch (e) {
      AppLogger.debug('Поиск по вложениям: $key — $e');
      return false;
    }
  }

  static EmailAttachment? _attachment(String? json, String id) {
    if (json == null || json.isEmpty) return null;
    try {
      for (final m in (jsonDecode(json) as List).whereType<Map>()) {
        final a = EmailAttachment.fromMap(Map<String, dynamic>.from(m));
        if (a.id == id) return a;
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────── ключи и части ───────────────────────────

  /// Ключ кэша «аккаунт|письмо|вложение» (MailEngineService.attachmentCacheKey):
  /// id вложения — после последней «|», как в OfflineStoreService.cleanupCache.
  static ({String accountId, String emailId, String attachmentId})? parseKey(String key) {
    final a = key.indexOf('|');
    final b = key.lastIndexOf('|');
    if (a <= 0 || b <= a + 1 || b == key.length - 1) return null;
    return (accountId: key.substring(0, a), emailId: key.substring(a + 1, b), attachmentId: key.substring(b + 1));
  }

  /// Имя вложения из пути файла в кэше («<md5>_<имя>»): для расширения.
  static String nameFromPath(String path) {
    final base = path.split(RegExp(r'[/\\]')).last;
    final u = base.indexOf('_');
    return u >= 0 ? base.substring(u + 1) : base;
  }

  static const _start = '\u001E';
  static const _end = '\u001F';

  /// Знаки метки: управляющие, которые поиск считает разделителями.
  static const _alphabet = [
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, //
  ];

  /// Метка вложения: 48 бит хеша FNV-1a его id — 12 знаков по 4 бита.
  static String markerOf(String attachmentId) {
    final bytes = utf8.encode(attachmentId);
    int fnv(int seed) {
      var h = seed;
      for (final c in bytes) {
        h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
      }
      return h;
    }

    final hi = fnv(0x811c9dc5);
    final lo = fnv(0x050c5d1f);
    final out = StringBuffer();
    for (var i = 0; i < 8; i++) {
      out.writeCharCode(_alphabet[(hi >> (4 * i)) & 0xF]);
    }
    for (var i = 0; i < 4; i++) {
      out.writeCharCode(_alphabet[(lo >> (4 * i)) & 0xF]);
    }
    return out.toString();
  }

  /// Части текста вложений: метка → текст, в порядке хранения. Текст без
  /// разметки (записанный не этим кодом) — часть с пустой меткой.
  static Map<String, String> sectionsOf(String stored) {
    final out = <String, String>{};
    if (stored.isEmpty) return out;
    final parts = stored.split(_start);
    if (parts.first.trim().isNotEmpty) out[''] = parts.first;
    for (final part in parts.skip(1)) {
      final e = part.indexOf(_end);
      if (e != 12) continue; // повреждённая часть — не сохраняем
      out[part.substring(0, e)] = part.substring(e + 1);
    }
    return out;
  }

  /// Текст вложений письма после разбора вложения [attachmentId]: его часть
  /// заменена (или добавлена в конец); всё вместе — не длиннее
  /// AttachmentText.maxMessageChars (новой части достаётся остаток).
  static String merge(String stored, String attachmentId, String text) {
    final sections = sectionsOf(stored);
    final marker = markerOf(attachmentId);
    sections.remove(marker);
    var used = 0;
    for (final t in sections.values) {
      used += t.length + 14;
    }
    final left = AttachmentText.maxMessageChars - used - 14;
    sections[marker] = left > 0 ? cutSafe(text, left) : '';
    final out = StringBuffer();
    sections.forEach((m, t) {
      if (m.isEmpty) {
        out.write(t);
      } else {
        out
          ..write(_start)
          ..write(m)
          ..write(_end)
          ..write(t);
      }
    });
    return out.toString();
  }
}
