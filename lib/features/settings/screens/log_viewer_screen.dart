// lib/features/settings/screens/log_viewer_screen.dart
// Просмотр последних логов приложения для диагностики (вход Exchange/IMAP и пр.).
//
// Для ИТ-поддержки — пакет диагностики (ZIP: журнал + сводка об устройстве,
// ящиках и политике): «Отправить в поддержку» открывает письмо с вложением
// в самом приложении, «Сохранить» — системный диалог сохранения файла,
// «Поделиться» (Android) — любая почта или мессенджер.
// «Подробный журнал» на 24 часа добавляет протокольные записи движка.

import 'dart:async';
import 'dart:io';
import '../../../core/theme/app_icons.dart';
import '../../../core/platform/file_pick.dart' show FilePick;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/help_hint.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/diagnostics_report.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen> {
  String _logs = '';
  bool _loading = true;
  bool _busy = false; // собирается пакет диагностики

  bool get _desktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await AppLogger.readRecentLogs(maxLines: 800);
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  Future<T?> _withBusy<T>(Future<T> Function() job) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await job();
    } catch (e, st) {
      AppLogger.error('Пакет диагностики', e, st);
      if (mounted) {
            showInlineError(AppLocalizations.of(context).tr('logPackageFailed'));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Письмо в поддержку из самого приложения: адресат — SUPPORT_EMAIL,
  /// вложение — пакет диагностики. Без ящиков (вход не удался) писать не
  /// из чего — тогда «Поделиться» на Android и «Сохранить» на Windows.
  Future<void> _sendToSupport() async {
    final l10n = AppLocalizations.of(context);
    if (ref.read(accountsProvider).isEmpty) {
      _desktop ? await _saveFile() : await _sharePackage();
      return;
    }
    final file = await _withBusy(() => DiagnosticsReport.build(ref));
    if (file == null || !mounted) return;
    final q = <String, String>{
      if (AppConstants.supportEmail.isNotEmpty) 'to': AppConstants.supportEmail,
      'subject': l10n.tr('logSupportSubject').replaceAll('{app}', AppConstants.appName),
      'body': l10n.tr('logSupportBody'),
      'attachments': file.path,
    };
    unawaited(context.push(Uri(path: '/compose', queryParameters: q).toString()));
  }

  /// Сохранить пакет через системный диалог (Windows — «Сохранить как»,
  /// Android — выбор папки, например «Загрузки»).
  Future<void> _saveFile() async {
    final l10n = AppLocalizations.of(context);
    final bytes = await _withBusy(() => DiagnosticsReport.buildBytes(ref));
    if (bytes == null) return;
    final data = Uint8List.fromList(bytes);
    final saved = await FilePick.save(
      dialogTitle: l10n.tr('logSave'),
      fileName: DiagnosticsReport.fileName(),
      bytes: data,
    );
    if (saved == null) return;
    showInlineNotice(l10n.tr('logSaved').replaceAll('{path}', saved.shown));
  }

  /// Android: системное «Поделиться» — почта, мессенджер, диск.
  Future<void> _sharePackage() async {
    final l10n = AppLocalizations.of(context);
    final file = await _withBusy(() => DiagnosticsReport.build(ref));
    if (file == null) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: l10n.tr('logSupportSubject').replaceAll('{app}', AppConstants.appName),
    ));
  }

  /// Windows: открыть папку журнала в Проводнике с выделенным файлом.
  Future<void> _openFolder() async {
    final path = AppLogger.logFilePath;
    if (path == null) return;
    try {
      if (Platform.isWindows) {
        // Проводник понимает /select только с обратными слэшами.
        await Process.start('explorer.exe', ['/select,', path.replaceAll('/', r'\')]);
      } else {
        await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [File(path).parent.path]);
      }
    } catch (e) {
      AppLogger.warning('Не удалось открыть папку журнала: $e');
      await Clipboard.setData(ClipboardData(text: path));
    }
  }

  Future<void> _toggleDetailed(bool on) async {
    final until = AppLogger.setDetailed(on ? const Duration(hours: 24) : null);
    final prefs = ref.read(sharedPrefsProvider);
    if (until == null) {
      await prefs.remove(AppLogger.detailedPrefsKey);
    } else {
      await prefs.setInt(AppLogger.detailedPrefsKey, until);
    }
    if (mounted) setState(() {});
  }

  Future<void> _clearLogs() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('clearLogsQ')),
        content: Text(l10n.tr('clearLogsWarn')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('clear'))),
        ],
      ),
    );
    if (ok != true) return;
    await AppLogger.clearLogs();
    await _load();
    AppLogger.info(l10n.tr('logsCleared'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('logsTitle')),
        actions: [
          HelpButton(text: l10n.tr('logsHelp'), title: l10n.tr('logsTitle')),
          IconButton(
            icon: const Icon(AppIcons.refresh),
            tooltip: l10n.tr('refresh'),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(AppIcons.content_copy),
            tooltip: l10n.tr('copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logs));
              showInlineNotice(l10n.tr('logsCopied'), duration: const Duration(seconds: 2));
            },
          ),
          IconButton(
            icon: const Icon(AppIcons.support_agent),
            tooltip: l10n.tr('logSendSupport'),
            onPressed: _busy ? null : _sendToSupport,
          ),
          IconButton(
            icon: const Icon(AppIcons.save_alt),
            tooltip: l10n.tr('logSave'),
            onPressed: _busy ? null : _saveFile,
          ),
          if (!_desktop)
            IconButton(
              icon: const Icon(AppIcons.share),
              tooltip: l10n.tr('shareFile'),
              onPressed: _busy ? null : _sharePackage,
            ),
          if (_desktop)
            IconButton(
              icon: const Icon(AppIcons.folder_open),
              tooltip: l10n.tr('logOpenFolder'),
              onPressed: _openFolder,
            ),
          IconButton(
            icon: const Icon(AppIcons.delete),
            tooltip: l10n.tr('clear'),
            onPressed: _clearLogs,
          ),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(height: Space.xs, child: _busy ? const LinearProgressIndicator() : null),
                SwitchListTile(
                  dense: true,
                  value: AppLogger.detailed,
                  onChanged: _toggleDetailed,
                  title: Text(l10n.tr('logDetailed')),
                  subtitle: Text(AppLogger.detailed
                      ? l10n.tr('logDetailedOn').replaceAll(
                          '{until}',
                          MaterialLocalizations.of(context).formatTimeOfDay(
                              TimeOfDay.fromDateTime(AppLogger.detailedUntil!),
                              alwaysUse24HourFormat: true))
                      : l10n.tr('logDetailedHint')),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.m),
                    child: SelectableText(
                      _logs.isEmpty ? (l10n.tr('logsEmpty')) : _logs,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
