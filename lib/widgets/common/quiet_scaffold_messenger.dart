// lib/widgets/common/quiet_scaffold_messenger.dart
// Чёрные всплывающие плашки внизу экрана («Удалено», «Отправлено»,
// «Сохранено» и т. п.) выключены во всём приложении (замечание 07.10.2026:
// мешают и закрывают кнопки). Все экраны берут ScaffoldMessenger отсюда,
// поэтому достаточно одного места; текст плашки уходит в журнал.
// Плашки с кнопкой «Отменить» тоже скрыты (решение 08.10.2026): удалённое
// восстанавливается из Корзины. Включить обратно — [showAppSnackBars] = true.
//
// 1.6.48 (решение владельца 19.10.2026: «всё только в журнал»): и ошибки
// из плашек больше не показываются строкой вверху экрана — только запись в
// журнал. Ошибки (по ключам ниже и красному фону) пишутся предупреждением,
// чтобы в журнале их было видно сразу; остальное — обычной строкой. Строка
// вверху экрана осталась для мест, которые зовут [showInlineError] сами.

import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/app_theme.dart' show AppColors;
import '../../l10n/app_localizations.dart';

/// Ошибки и объяснения, почему действие не выполнено: в журнал —
/// предупреждением (1.6.48; до этого — строкой вверху экрана). Подтверждения
/// («Сохранено», «Удалено», «Отправлено») — обычной строкой журнала.
const _noticeKeys = <String>[
  // ошибки
  'error', 'errorLbl', 'sendError', 'accountPhotoBad', 'archiveFolderNotFound', 'attachDownloadFailed',
  'attachLimitExceeded', 'cannotOpenFile', 'certPinMismatchLogin', 'couldNotParseJson',
  'couldNotParseSettings', 'couldNotSendResponse', 'deleteRejected', 'downloadedNFailed',
  'exportFailed', 'failedToSave', 'folderCreateFailed', 'groupExpandUnavailable', 'invalidJson',
  'junkFolderNotFound', 'logPackageFailed', 'moveFolderFailed', 'offlineQueueFull', 'pdfExportFailed',
  'reauthMismatch', 'recallUnavailable', 'renameRejected', 'signatureNotFound', 'trashFolderNotFound',
  // 1.6.45: ошибки, которые раньше уходили в скрытую плашку.
  'folderCleanupFailed', 'saveToDownloadsFailed', 'syncFailedFor', 'syncServerBusy',
  // «почему ничего не произошло»
  'groupExpandEmpty', 'noContactsToExport', 'nothingToMark', 'myDepartmentNone', 'noSignaturesCompose',
  'clipboardEmpty', 'bulkMoveSkipped', 'alreadySent', 'noMatchingMail',
];

/// Самый длинный неизменный кусок шаблона («Не удалось {x}» → «Не удалось»).
String _literal(String template) {
  final parts = template.split(RegExp(r'\{[^}]*\}')).map((p) => p.trim()).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return parts.isEmpty ? '' : parts.first;
}

/// Показывать ли плашки SnackBar.
bool showAppSnackBars = false;

class QuietScaffoldMessenger extends ScaffoldMessenger {
  const QuietScaffoldMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _QuietScaffoldMessengerState();
}

class _QuietScaffoldMessengerState extends ScaffoldMessengerState {
  Locale? _cachedFor;
  List<String> _fragments = const [];

  bool _isNotice(String text, SnackBar bar) {
    if (bar.backgroundColor == AppColors.errorRed) return true;
    final l10n = AppLocalizations.of(context);
    if (_cachedFor != l10n.locale) {
      _cachedFor = l10n.locale;
      _fragments = [
        for (final k in _noticeKeys)
          if (_literal(l10n.tr(k)).length >= 4) _literal(l10n.tr(k)),
      ];
    }
    final t = text.trim();
    return _fragments.any((f) => t.startsWith(f) || (f.length >= 8 && t.contains(f)));
  }

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(SnackBar snackBar,
      {AnimationStyle? snackBarAnimationStyle}) {
    if (showAppSnackBars) {
      return super.showSnackBar(snackBar, snackBarAnimationStyle: snackBarAnimationStyle);
    }
    final content = snackBar.content;
    final text = content is Text ? (content.data ?? '') : '';
    if (text.isNotEmpty && _isNotice(text, snackBar)) {
      AppLogger.warning('Плашка (только в журнал): $text');
    } else if (text.isNotEmpty) {
      AppLogger.info('Плашка (только в журнал): $text');
    }
    // Контроллер нужен вызывающему коду, а создать его можно только показом —
    // показываем пустую невидимую плашку и сразу убираем.
    final c = super.showSnackBar(
      const SnackBar(
        content: SizedBox.shrink(),
        duration: Duration(milliseconds: 1),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        width: 1,
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
    removeCurrentSnackBar();
    return c;
  }
}
