// lib/widgets/ui/confirm_dialog.dart
// Подтверждение необратимого действия — один вид во всём приложении
// (принцип Dialer «подтверждение необратимого», docs/plan/UI_REDESIGN.md):
// заголовок-вопрос, пояснение, «Отмена» и действие цветом ошибки темы.
// Раньше кнопка удаления была то синей, то красной — в зависимости от экрана.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// true — пользователь подтвердил. [action] — подпись кнопки (по умолчанию
/// «Удалить»).
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? message,
  String? action,
}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: message == null || message.isEmpty ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action ?? l10n.delete),
          ),
        ],
      );
    },
  );
  return ok == true;
}
