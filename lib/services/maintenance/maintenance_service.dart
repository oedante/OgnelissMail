import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show TableUpdate, UpdateKind;

import '../../core/logging/app_logger.dart';
import '../../core/security/mail_body_processor.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../mail/thread_linker.dart';
import '../sync/offline_store_service.dart';

final maintenanceServiceProvider = Provider<MaintenanceService>((ref) {
  return MaintenanceService(ref);
});

/// Обслуживание локальной БД: чистка осиротевших записей поискового индекса
/// (`emails_fts`) и сжатие файла SQLite (VACUUM). Запускается автоматически не
/// чаще раза в сутки — чтобы пользователю не нужно было заходить в настройки.
///
/// Вызывается при уходе приложения в фон (main_shell.didChangeAppLifecycleState
/// → paused): в этот момент нет активного UI и, как правило, синхронизации, а
/// VACUUM переписывает файл БД целиком и на большой базе может занять секунду-две.
class MaintenanceService {
  MaintenanceService(this._ref);
  final Ref _ref;

  static const _lastRunKey = 'last_db_maintenance_epoch_ms';
  static const _kBodiesMoved = 'db_bodies_at_end_v1';
  static const _kPreviewsFilled = 'db_previews_filled_v1';
  static const _kEasDupes = 'db_eas_dupes_removed_v1';
  static const _kCalFull = 'cal_full_after_162';
  static const _kPreviewLines = 'db_previews_lines_v1';
  static const _kThreads = 'db_threads_relinked_v1';
  static const _interval = Duration(hours: 24);

  bool _running = false;

  /// Разовые работы после обновления (1.6.1) — вскоре после запуска, а не
  /// при сворачивании: их результат нужен сразу. Сбой — повтор при следующем
  /// запуске.
  ///  1. Превью писем из сохранённых текстов (AppDatabase.fillMissingPreviews):
  ///     лента с 1.5.8 читает строки без тел, а у писем IMAP превью в строке
  ///     не было — лента IMAP осталась без превью.
  ///  2. Разметка текстов, которые уже в поисковом индексе
  ///     (AppDatabase.markIndexedBodies): остальные — тексты, сохранённые при
  ///     открытии письма, — доиндексирует OfflineStoreService.
  ///  3. Дубли писем ActiveSync от сброса синхронизации на сервере
  ///     (AppDatabase.removeEasDuplicates, замечание 13.10.2026).
  ///  4. Беседы IMAP по ссылкам на письма (1.8.13, ThreadLinker): беседы,
  ///     разорванные до этой версии, сливаются.
  Future<void> afterUpdateOnce() async {
    final prefs = _ref.read(sharedPrefsProvider);
    // Подсказки «Вставить:» убраны (1.8.12, замечание 30.10.2026: «странно
    // работают») — и фразы, выученные из отправленных писем, тоже.
    if (prefs.containsKey('smart_compose_phrases')) unawaited(prefs.remove('smart_compose_phrases'));
    final previews = prefs.getBool(_kPreviewsFilled) ?? false;
    final marked = prefs.getBool(OfflineStoreService.indexMarkedPrefKey) ?? false;
    final dupes = prefs.getBool(_kEasDupes) ?? false;
    final calFull = prefs.getBool(_kCalFull) ?? false;
    final lines = prefs.getBool(_kPreviewLines) ?? false;
    final threads = prefs.getBool(_kThreads) ?? false;
    if (_running || (previews && marked && dupes && calFull && lines && threads)) return;
    _running = true;
    final db = _ref.read(databaseProvider);
    try {
      if (!dupes) {
        final eas = [for (final a in _ref.read(accountsProvider)) if (a.usesEas) a.id];
        final n = await db.removeEasDuplicates(eas);
        await prefs.setBool(_kEasDupes, true);
        if (n > 0) AppLogger.info('База: убраны дубли писем ActiveSync — $n');
      }
      if (!calFull) {
        // Встречи ActiveSync по два раза (13.10.2026): после сброса ключа
        // сервером у них новые ServerId. Разово — полная перечитка
        // календаря: строки, которых нет на сервере, убираются.
        for (final a in _ref.read(accountsProvider)) {
          if (a.usesEas) await prefs.setBool('calfull_req_${a.id}', true);
        }
        await prefs.setBool(_kCalFull, true);
      }
      if (!previews) {
        final sw = Stopwatch()..start();
        final n = await db.fillMissingPreviews();
        await prefs.setBool(_kPreviewsFilled, true);
        AppLogger.info('База: превью из сохранённых текстов — $n писем за ${sw.elapsedMilliseconds} мс');
      }
      if (!marked) {
        final sw = Stopwatch()..start();
        final r = await db.markIndexedBodies();
        await prefs.setBool(OfflineStoreService.indexMarkedPrefKey, true);
        AppLogger.info('База: тексты в поиске — ${r.marked}, ждут добавления в поиск — ${r.left} '
            '(${sw.elapsedMilliseconds} мс)');
      }
      if (!lines) {
        // 1.6.31: превью с переносами строк для уже загруженных писем — из
        // сохранённого текста (настройка «строк текста в ленте»). Порциями,
        // с паузой: база и лента не заняты надолго.
        final sw = Stopwatch()..start();
        var last = 0;
        var changed = 0;
        while (true) {
          final src = await db.previewSources(last, 150);
          if (src.isEmpty) break;
          last = src.last.rowid;
          final multi = await MailBodyProcessor.previewAll({
            for (final r in src) '${r.rowid}': (plain: r.plain, html: r.html),
          });
          final upd = <int, String>{
            for (final r in src)
              if (multi['${r.rowid}'] case final p? when p.contains('\n') && p != r.preview) r.rowid: p,
          };
          await db.setPreviewsByRowid(upd);
          changed += upd.length;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        await prefs.setBool(_kPreviewLines, true);
        if (changed > 0) db.notifyUpdates({TableUpdate.onTable(db.emails, kind: UpdateKind.update)});
        AppLogger.info('База: превью с переносами строк — $changed писем за ${sw.elapsedMilliseconds} мс');
      }
      if (!threads) {
        final sw = Stopwatch()..start();
        var n = 0;
        for (final a in _ref.read(accountsProvider)) {
          if (ThreadLinker.appliesTo(a)) n += await ThreadLinker.relinkAccount(db, a);
        }
        await prefs.setBool(_kThreads, true);
        AppLogger.info('База: беседы по ссылкам на письма — $n писем за ${sw.elapsedMilliseconds} мс');
      }
    } catch (e) {
      AppLogger.warning('База: разовая подготовка после обновления не завершена — $e');
    } finally {
      _running = false;
    }
  }

  /// Запустить обслуживание, если с прошлого раза прошло ≥ 24 ч. Безопасно
  /// вызывать часто (при каждом сворачивании) — сам решает, пора ли, и не
  /// запускается повторно, пока идёт.
  Future<void> maybeRunDaily() async {
    if (_running) return;
    // Разово (1.5.8): тексты писем — в конец строки таблицы, чтобы лента и
    // счётчики не читали их (AppDatabase.moveBodiesToEnd). Когда приложение
    // свёрнуто: копирование таблицы занимает секунды, база в это время занята.
    if (!(_ref.read(sharedPrefsProvider).getBool(_kBodiesMoved) ?? false)) {
      _running = true;
      try {
        final sw = Stopwatch()..start();
        final moved = await _ref.read(databaseProvider).moveBodiesToEnd();
        await _ref.read(sharedPrefsProvider).setBool(_kBodiesMoved, true);
        if (moved) AppLogger.info('База: тексты писем перенесены в конец строки за ${sw.elapsedMilliseconds} мс');
      } catch (e) {
        // Таблица осталась прежней (транзакция откатилась); не повторяем —
        // приложение работает и так, только медленнее.
        AppLogger.warning('База: перестановка столбцов не выполнена — $e');
        await _ref.read(sharedPrefsProvider).setBool(_kBodiesMoved, true);
      } finally {
        _running = false;
      }
      return;
    }
    if (!(_ref.read(sharedPrefsProvider).getBool(_kPreviewsFilled) ?? false) ||
        !(_ref.read(sharedPrefsProvider).getBool(_kEasDupes) ?? false) ||
        !(_ref.read(sharedPrefsProvider).getBool(OfflineStoreService.indexMarkedPrefKey) ?? false)) {
      await afterUpdateOnce();
      return;
    }
    final prefs = _ref.read(sharedPrefsProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_lastRunKey) ?? 0;
    if (now - last < _interval.inMilliseconds) return;

    _running = true;
    // Ставим отметку СРАЗУ: даже при сбое не будем долбить VACUUM при каждом
    // сворачивании до конца суток.
    await prefs.setInt(_lastRunKey, now);
    try {
      final db = _ref.read(databaseProvider);
      final pruned = await db.pruneOrphanFts();
      try {
        await db.optimize();
      } catch (_) {}
      // VACUUM переписывает весь файл базы — только если свободного места в
      // нём много (раньше — каждый день, даже когда сжимать было нечего).
      final free = await db.freeSpace();
      final doVacuum = free.ratio >= 0.2 && free.freeBytes >= 8 * 1024 * 1024;
      if (doVacuum) await db.vacuum();
      AppLogger.info('DB maintenance: pruned $pruned FTS-сирот, '
          '${doVacuum ? 'VACUUM выполнен' : 'VACUUM не нужен'} '
          '(свободно ${(free.ratio * 100).round()}%, ${free.freeBytes ~/ (1024 * 1024)} МБ)');
    } catch (e) {
      AppLogger.warning('DB maintenance failed: $e');
    } finally {
      _running = false;
    }
  }

  /// Принудительный прогон (для кнопки «Оптимизировать хранилище»): без проверки
  /// интервала, но с обновлением отметки времени.
  Future<int> runNow() async {
    _running = true;
    try {
      final db = _ref.read(databaseProvider);
      final pruned = await db.pruneOrphanFts();
      await db.vacuum();
      await _ref.read(sharedPrefsProvider)
          .setInt(_lastRunKey, DateTime.now().millisecondsSinceEpoch);
      return pruned;
    } finally {
      _running = false;
    }
  }
}
