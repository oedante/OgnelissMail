// lib/features/compose/compose_window_app.dart
//
// Само окно редактора на компьютере (2.5.4, compose_window.dart): маршруты,
// размер и заголовок окна, закрытие после отправки и по крестику окна,
// экран «не запустилось» с переходом в главное окно.

import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../mail/message_window.dart';
import '../mail/screens/attachment_hub_screen.dart';
import 'compose_window.dart';
import 'screens/compose_screen.dart';

/// Заголовок окна по тому, что открыто: ответ, пересылка, черновик, новое.
String composeWindowTitle(AppLocalizations l10n, Map<String, String> q) {
  final what = q['draftId'] != null
      ? l10n.tr('draft')
      : q['replyToId'] != null
          ? l10n.tr(q['replyAll'] == 'true' ? 'replyAllTitle' : 'replyTitle')
          : q['forwardFromId'] != null
              ? l10n.tr('forwardTitle')
              : l10n.tr('newMessage');
  return '$what — Ogneliss Mail';
}

/// Маршруты окна: главная страница (открывает редактор и закрывает окно,
/// когда он закрыт), редактор, выбор файлов из «Вложений».
GoRouter composeWindowRouter(Map<String, String> query) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => ComposeWindowHome(query: query)),
        GoRoute(
          path: '/compose',
          pageBuilder: (_, st) => NoTransitionPage<void>(
            key: st.pageKey,
            child: ComposeScreen.fromQuery({
              for (final e in st.uri.queryParameters.entries)
                if (e.key != ComposeWindow.hereParam) e.key: e.value,
            }),
          ),
        ),
        GoRoute(
          path: '/attachment-hub',
          builder: (_, st) => AttachmentHubScreen(
            sender: st.uri.queryParameters['from'],
            pick: st.uri.queryParameters['pick'] == '1',
          ),
        ),
      ],
    );

/// Окно на экране: размер, заголовок, показ, закрытие. Управление окном —
/// плагин window_manager в движке окна; его нет (сборка без регистрации
/// плагинов в окнах) — окно показывается и прячется средствами
/// desktop_multi_window.
abstract final class ComposeWindowFrame {
  static bool _wm = false;
  static String? _windowId;

  static Future<void> setup({required String title, String? windowId}) async {
    _windowId = windowId;
    try {
      await windowManager.ensureInitialized();
      _wm = true;
      await windowManager.setTitle(title);
      // Размер — как у окна письма Outlook, но не больше экрана.
      final display = WidgetsBinding.instance.platformDispatcher.displays.firstOrNull;
      final screen = display == null ? const Size(1280, 900) : display.size / display.devicePixelRatio;
      final size = Size(math.min(980, screen.width * 0.9), math.min(840, screen.height * 0.88));
      await windowManager.setMinimumSize(const Size(560, 460));
      await windowManager.setSize(size);
      await windowManager.center();
      // Крестик окна — как «Закрыть» редактора: сохранить черновик или
      // спросить (ComposeWindowHome.onWindowClose).
      await windowManager.setPreventClose(true);
    } catch (e) {
      _wm = false;
      AppLogger.warning('Окно редактора: управление окном недоступно — $e');
    }
  }

  /// Главное окно просит выйти вперёд (тот же черновик открыли ещё раз).
  static Future<void> listenFocus() async {
    try {
      final me = await WindowController.fromCurrentEngine();
      await me.setWindowMethodHandler((call) async {
        if (call.method == ComposeWindow.focusMethod) await focus();
        return null;
      });
    } catch (e) {
      AppLogger.warning('Окно редактора: просьбы главного окна не принимаются — $e');
    }
  }

  static Future<void> focus() async {
    try {
      if (_wm) {
        if (await windowManager.isMinimized()) await windowManager.restore();
        await windowManager.show();
        await windowManager.focus();
      } else if (_windowId != null) {
        await WindowController.fromWindowId(_windowId!).show();
      }
    } catch (_) {}
  }

  /// Показать окно и сообщить главному окну, что оно показано.
  static Future<void> show() async {
    try {
      if (_wm) {
        await windowManager.show();
        await windowManager.focus();
      } else if (_windowId != null) {
        await WindowController.fromWindowId(_windowId!).show();
      }
    } catch (e) {
      AppLogger.warning('Окно редактора не показано: $e');
    }
    if (_windowId != null) unawaited(MessageWindow.ask('composeReady', {'windowId': _windowId}));
  }

  /// Закрыть окно (его движок завершится вместе с ним). destroy() у
  /// window_manager завершает всё приложение — только close().
  static Future<void> close() async {
    if (_wm) {
      try {
        await windowManager.setPreventClose(false);
        await windowManager.close();
        return;
      } catch (_) {}
    }
    try {
      final c = await WindowController.fromCurrentEngine();
      await c.hide();
    } catch (_) {}
  }
}

/// Главная страница окна: сразу открывает редактор; редактор закрыт
/// (отправлено, сохранено, удалено) — дождаться записи черновика и закрыть
/// окно.
class ComposeWindowHome extends StatefulWidget {
  final Map<String, String> query;
  const ComposeWindowHome({super.key, required this.query});

  @override
  State<ComposeWindowHome> createState() => _ComposeWindowHomeState();
}

class _ComposeWindowHomeState extends State<ComposeWindowHome> with WindowListener {
  bool _composing = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    try {
      windowManager.addListener(this);
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _start() async {
    _composing = true;
    await context.push(Uri(path: '/compose', queryParameters: widget.query).toString());
    _composing = false;
    await _close();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    // Черновик пишется при закрытии редактора — окно ждёт записи.
    await ComposeWindow.idle();
    await ComposeWindowFrame.close();
  }

  @override
  void onWindowClose() {
    if (!_composing) {
      unawaited(_close());
      return;
    }
    // Как кнопка «Закрыть» редактора: пустое письмо закроется, в остальном
    // редактор сам сохранит черновик или спросит.
    unawaited(GoRouter.of(context).routerDelegate.navigatorKey.currentState?.maybePop());
  }

  @override
  Widget build(BuildContext context) => ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
}

/// Окно не запустилось (нет связи с главным окном, база не открылась):
/// причина и «Открыть в главном окне».
class ComposeWindowErrorApp extends StatelessWidget {
  final Map<String, String> query;
  final String error;
  const ComposeWindowErrorApp({super.key, required this.query, required this.error});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(1.0),
        darkTheme: AppTheme.darkTheme(1.0),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(AppIcons.error, size: 48, color: AppColors.errorRed),
                  const SizedBox(height: Space.m),
                  Text(l10n.tr('composeWindowFailed'),
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: Space.s),
                  Text(error, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: Space.l),
                  FilledButton.icon(
                    icon: const Icon(AppIcons.open_in_new),
                    label: Text(l10n.tr('openInMainWindow')),
                    onPressed: () async {
                      await MessageWindow.ask('composeOpenHere', {'query': query});
                      await ComposeWindowFrame.close();
                    },
                  ),
                ]),
              ),
            ),
          );
        }),
      );
}
