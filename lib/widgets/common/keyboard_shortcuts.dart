// lib/widgets/common/keyboard_shortcuts.dart
// Горячие клавиши для desktop (Windows, macOS, Linux):
// - Ctrl+N — новое письмо
// - Ctrl+R — ответить
// - Ctrl+Shift+R — ответить всем
// - Ctrl+F — переслать
// - Ctrl+Enter — отправить
// - Delete — удалить
// - Ctrl+Shift+F — поиск
// - Ctrl+1..5 — переключение вкладок
// - Esc — закрыть/отмена

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'command_palette.dart';

/// Обёртка с горячими клавишами для desktop
class KeyboardShortcutsWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onCompose;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;
  final VoidCallback? onSearch;
  final VoidCallback? onRefresh;
  final void Function(int index)? onSwitchTab;

  const KeyboardShortcutsWrapper({
    super.key,
    required this.child,
    this.onCompose,
    this.onReply,
    this.onReplyAll,
    this.onForward,
    this.onDelete,
    this.onSearch,
    this.onRefresh,
    this.onSwitchTab,
  });

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;

    return Shortcuts(
      shortcuts: {
        // Новое письмо
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _ComposeIntent(),
        // macOS: Cmd+N
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const _ComposeIntent(),

        // Ответить
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR):
            const _ReplyIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyR):
            const _ReplyIntent(),

        // Ответить всем
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyR):
            const _ReplyAllIntent(),

        // Переслать
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _ForwardIntent(),

        // Удалить
        const SingleActivator(LogicalKeyboardKey.delete):
            const _DeleteIntent(),

        // Поиск
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyF):
            const _SearchIntent(),
        // Ctrl+E — поиск, как в Outlook (Ctrl+K занят командной палитрой;
        // раньше он был назначен дважды и поиск по нему не открывался).
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyE):
            const _SearchIntent(),

        // Обновить
        const SingleActivator(LogicalKeyboardKey.f5):
            const _RefreshIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyS):
            const _RefreshIntent(),

        // Вкладки 1-5
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit1): const _SwitchTabIntent(0),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit2): const _SwitchTabIntent(1),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit3): const _SwitchTabIntent(2),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit4): const _SwitchTabIntent(3),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit5): const _SwitchTabIntent(4),
        // Командная палитра Ctrl+K / Cmd+K
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK): const _PaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK): const _PaletteIntent(),
      },
      child: Actions(
        actions: {
          _ComposeIntent: CallbackAction<_ComposeIntent>(onInvoke: (_) {
            onCompose?.call();
            if (onCompose == null) context.push('/compose');
            return null;
          }),
          _ReplyIntent: CallbackAction<_ReplyIntent>(onInvoke: (_) { onReply?.call(); return null; }),
          _ReplyAllIntent: CallbackAction<_ReplyAllIntent>(onInvoke: (_) { onReplyAll?.call(); return null; }),
          _ForwardIntent: CallbackAction<_ForwardIntent>(onInvoke: (_) { onForward?.call(); return null; }),
          _DeleteIntent: CallbackAction<_DeleteIntent>(onInvoke: (_) { onDelete?.call(); return null; }),
          _SearchIntent: CallbackAction<_SearchIntent>(onInvoke: (_) { onSearch?.call(); return null; }),
          _RefreshIntent: CallbackAction<_RefreshIntent>(onInvoke: (_) { onRefresh?.call(); return null; }),
          _SwitchTabIntent: CallbackAction<_SwitchTabIntent>(onInvoke: (intent) { onSwitchTab?.call(intent.index); return null; }),
          _PaletteIntent: CallbackAction<_PaletteIntent>(onInvoke: (_) { CommandPalette.show(context); return null; }),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}

class _ComposeIntent extends Intent { const _ComposeIntent(); }
class _PaletteIntent extends Intent { const _PaletteIntent(); }
class _ReplyIntent extends Intent { const _ReplyIntent(); }
class _ReplyAllIntent extends Intent { const _ReplyAllIntent(); }
class _ForwardIntent extends Intent { const _ForwardIntent(); }
class _DeleteIntent extends Intent { const _DeleteIntent(); }
class _SearchIntent extends Intent { const _SearchIntent(); }
class _RefreshIntent extends Intent { const _RefreshIntent(); }
class _SwitchTabIntent extends Intent {
  final int index;
  const _SwitchTabIntent(this.index);
}
