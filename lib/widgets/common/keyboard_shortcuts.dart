// lib/widgets/common/keyboard_shortcuts.dart
// Горячие клавиши для desktop (Windows, macOS, Linux) — как в Outlook
// (решение владельца 02.11.2026):
// - Ctrl+N, Ctrl+Shift+M — новое письмо
// - Ctrl+R — ответить, Ctrl+Shift+R — ответить всем, Ctrl+F — переслать
// - Ctrl+Enter — отправить (экран письма)
// - Delete — удалить, Backspace — в архив, Insert — флажок (экран письма)
// - Ctrl+Q / Ctrl+U — прочитано / не прочитано, Ctrl+P — печать (экран письма)
// - Ctrl+E, F3, Ctrl+Shift+F — поиск
// - F5, F9 — проверить почту
// - Ctrl+Shift+I — «Входящие»
// - Ctrl+1..5 — почта, календарь, контакты, задачи…
// - Ctrl+K — командная палитра
// - Esc — закрыть/отмена

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../ui/help_hint.dart' show showHelpSheet;
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

    // Сочетания — SingleActivator (Ctrl; на Mac — и ⌘, [withMacCommand]).
    // Ответить, переслать и удалить — только если оболочке их передали:
    // иначе пустое действие забирало клавишу, и ⌘R на Mac не доходил ни до
    // чего (17.11.2026: «сочетания клавиш не реагировали»). Письмо в панели
    // обрабатывает их само.
    SingleActivator ctrl(LogicalKeyboardKey k, {bool shift = false}) => SingleActivator(k, control: true, shift: shift);
    final shortcuts = withMacCommand<Intent>({
      // Новое письмо; Ctrl+Shift+M — откуда угодно (Outlook).
      ctrl(LogicalKeyboardKey.keyN): const _ComposeIntent(),
      ctrl(LogicalKeyboardKey.keyM, shift: true): const _ComposeIntent(),
      if (onReply != null) ctrl(LogicalKeyboardKey.keyR): const _ReplyIntent(),
      if (onReplyAll != null) ctrl(LogicalKeyboardKey.keyR, shift: true): const _ReplyAllIntent(),
      if (onForward != null) ctrl(LogicalKeyboardKey.keyF): const _ForwardIntent(),
      if (onDelete != null) const SingleActivator(LogicalKeyboardKey.delete): const _DeleteIntent(),
      // Поиск: Ctrl+E (Outlook), Ctrl+Shift+F, F3. Ctrl+K — палитра команд.
      ctrl(LogicalKeyboardKey.keyE): const _SearchIntent(),
      ctrl(LogicalKeyboardKey.keyF, shift: true): const _SearchIntent(),
      const SingleActivator(LogicalKeyboardKey.f3): const _SearchIntent(),
      // Ctrl+Shift+I — «Входящие» (Outlook): вкладка почты.
      ctrl(LogicalKeyboardKey.keyI, shift: true): const _SwitchTabIntent(0),
      // Проверить почту: F5, F9 («Отправить и получить» в Outlook), Ctrl+Shift+S.
      const SingleActivator(LogicalKeyboardKey.f5): const _RefreshIntent(),
      const SingleActivator(LogicalKeyboardKey.f9): const _RefreshIntent(),
      ctrl(LogicalKeyboardKey.keyS, shift: true): const _RefreshIntent(),
      // Разделы 1–5.
      ctrl(LogicalKeyboardKey.digit1): const _SwitchTabIntent(0),
      ctrl(LogicalKeyboardKey.digit2): const _SwitchTabIntent(1),
      ctrl(LogicalKeyboardKey.digit3): const _SwitchTabIntent(2),
      ctrl(LogicalKeyboardKey.digit4): const _SwitchTabIntent(3),
      ctrl(LogicalKeyboardKey.digit5): const _SwitchTabIntent(4),
      ctrl(LogicalKeyboardKey.keyK): const _PaletteIntent(),
    });

    return Shortcuts(
      shortcuts: shortcuts,
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
          // Delete — только если экран его ждёт и не набирают текст: иначе
          // клавиша не доходила до полей ввода (1.10.1).
          _DeleteIntent: _UnlessTyping<_DeleteIntent>(onDelete),
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

/// Клавиши Mac (17.11.2026): на Mac главная клавиша сочетаний — ⌘, а не
/// Ctrl. Для каждого сочетания с Ctrl добавляется такое же с ⌘ (Ctrl тоже
/// работает); [except] — клавиши, у которых ⌘ занят системой или другим
/// действием (⌘Q — выход из программы). На Windows и Linux — как есть.
Map<ShortcutActivator, T> withMacCommand<T>(Map<ShortcutActivator, T> bindings,
    {Set<LogicalKeyboardKey> except = const {}}) {
  if (defaultTargetPlatform != TargetPlatform.macOS) return bindings;
  final out = Map<ShortcutActivator, T>.of(bindings);
  // SingleActivator не сравнивается по значению — свои ⌘ ищутся по полям.
  bool taken(SingleActivator c) => out.keys.whereType<SingleActivator>().any(
      (b) => b.meta && !b.control && b.trigger == c.trigger && b.shift == c.shift && b.alt == c.alt);
  for (final e in bindings.entries) {
    final a = e.key;
    if (a is! SingleActivator || !a.control || a.meta || except.contains(a.trigger)) continue;
    final cmd = SingleActivator(a.trigger, meta: true, shift: a.shift, alt: a.alt, includeRepeats: a.includeRepeats);
    if (!taken(cmd)) out[cmd] = e.value;
  }
  return out;
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

/// Действие клавиши без Ctrl: выключено, пока в фокусе поле ввода или
/// обработчика нет, — тогда клавиша идёт дальше, к полю.
class _UnlessTyping<T extends Intent> extends Action<T> {
  _UnlessTyping(this.run);

  final VoidCallback? run;

  @override
  bool isEnabled(T intent) => run != null && !textInputFocused();

  @override
  Object? invoke(T intent) {
    run?.call();
    return null;
  }
}

/// Поле ввода в фокусе (быстрый ответ, поиск, тема…): клавиши без Ctrl
/// принадлежат ему.
bool textInputFocused() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  // Фокус у уже снятого с экрана элемента (iPad, второе нажатие «Меню»,
  // журнал владельца 10.11.2026): его widget — null, проверка падала
  // «Null check operator» при построении ленты — белый экран.
  if (ctx == null || !ctx.mounted) return false;
  return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Горячие клавиши экрана, у которого внутри есть поле ввода (1.10.1).
///
/// [CallbackShortcuts] забирает клавишу раньше текстового поля под ним: в
/// письме Backspace («в архив») и Delete («удалить») срабатывали, пока
/// человек стирал текст в строке «Ответить…» — и с клавиатуры компьютера, и
/// с экранной клавиатуры Android, которая шлёт Backspace клавишей, когда
/// поле уже пусто. [plain] — клавиши без Ctrl (Delete, Backspace, Insert):
/// пока в фокусе поле ввода, их нет вовсе, и клавиша доходит до поля.
class TypingAwareShortcuts extends StatelessWidget {
  const TypingAwareShortcuts({super.key, required this.bindings, required this.plain, required this.child});

  /// Сочетания, которые работают всегда (Ctrl+R, Esc…).
  final Map<ShortcutActivator, VoidCallback> bindings;

  /// Клавиши, которые не трогают набор текста.
  final Map<ShortcutActivator, VoidCallback> plain;

  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Меняется при каждой смене фокуса — перестраивается только список
        // клавиш, экран под ним — нет.
        listenable: FocusManager.instance,
        builder: (context, child) => CallbackShortcuts(
          bindings: {...bindings, if (!textInputFocused()) ...plain},
          child: child!,
        ),
        child: child,
      );
}

/// Клавиши компьютера для справки (2.6.4, проход по интерфейсу компьютера:
/// в «Спец. возможностях» был только список жестов пальцем). Клавиши — как
/// в [KeyboardShortcutsWrapper], ленте и письме; на Mac — значками ⌘ ⌃ ⇧.
List<(String, String)> desktopKeyList(AppLocalizations l10n, {required bool mac}) {
  String k(String win, String macKeys) => mac ? macKeys : win;
  return [
    ('↑ ↓   J  K', l10n.tr('keysHintNav')),
    (k('Ctrl+N', '⌘N'), l10n.compose),
    (k('Ctrl+R', '⌘R'), l10n.tr('replyLbl')),
    (k('Ctrl+Shift+R', '⇧⌘R'), l10n.tr('replyAllLbl')),
    // На Mac ⌘F — поиск в письме, пересылка — ⌘J (как Outlook для Mac).
    (k('Ctrl+F', '⌘J'), l10n.tr('forwardLbl')),
    (k('Ctrl+Enter', '⌘↩'), l10n.tr('sendLbl')),
    (k('Delete', '⌘⌫'), l10n.tr('deleteLbl')),
    (k('Backspace', '⌫'), l10n.tr('archiveLbl')),
    if (!mac) ('Insert', l10n.tr('actFlagFull')),
    // ⌘Q на Mac — выход из программы.
    (k('Ctrl+Q', '⌃Q'), l10n.tr('markRead')),
    (k('Ctrl+U', '⌘U'), l10n.tr('markUnread')),
    (k('Ctrl+P', '⌘P'), l10n.tr('printEmail')),
    (k('F4', '⌘F   F4'), l10n.tr('findInMail')),
    (k('Ctrl+E   F3', '⌘E   F3'), l10n.tr('searchLbl')),
    ('F5   F9', l10n.tr('checkMail')),
    (k('Ctrl+1 … 5', '⌘1 … 5'), l10n.tr('sections')),
    (k('Ctrl+K', '⌘K'), l10n.tr('keysHintPalette')),
    ('Esc', l10n.tr('closeLbl')),
  ];
}

/// Справка «Сочетания клавиш» (компьютер).
Future<void> showKeyboardHelp(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final mac = Theme.of(context).platform == TargetPlatform.macOS;
  final text = [for (final (keys, label) in desktopKeyList(l10n, mac: mac)) '$keys — $label'].join('\n');
  return showHelpSheet(context, title: l10n.tr('kbdShortcuts'), text: text);
}
