// lib/core/platform/app_shortcuts.dart
// Быстрые действия по долгому нажатию на значок приложения: «Мой день»,
// «Написать письмо», «Создать встречу», «Создать напоминание». Письмо и напоминание
// создаются в открытом ящике, а если ящик не выбран (общий вид) — в первом
// личном; в самом окне ящик можно поменять.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import '../../features/mail/providers/mail_providers.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../features/settings/providers/feature_flags_provider.dart';
import '../../l10n/app_localizations.dart';
import '../logging/app_logger.dart';
import '../navigation/app_router.dart';

class AppShortcuts {
  AppShortcuts._();

  static const _compose = 'compose';
  static const _event = 'event';
  static const _reminder = 'reminder';
  static const _myDay = 'myday';

  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> init(ProviderContainer container) async {
    if (!_supported) return;
    const qa = QuickActions();
    try {
      await qa.initialize((type) => unawaited(_open(container, type)));
      await _setItems(container);
      // Язык сменили — подписи действий тоже.
      container.listen(settingsProvider.select((s) => s.locale.languageCode), (_, __) {
        unawaited(_setItems(container));
      });
      // «Мой день» включили/выключили — пункт появляется/исчезает.
      container.listen(settingsProvider.select((s) => s.myDay), (_, __) {
        unawaited(_setItems(container));
      });
    } catch (e) {
      AppLogger.warning('Быстрые действия значка: $e');
    }
  }

  static Future<void> _setItems(ProviderContainer container) async {
    final settings = container.read(settingsProvider);
    final l10n = AppLocalizations(settings.locale);
    await const QuickActions().setShortcutItems([
      // Значки — контурные Material Symbols на круге цвета знака приложения
      // (res/drawable-anydpi-v26 — адаптивные; iOS — шаблонные картинки).
      if (settings.myDay)
        ShortcutItem(type: _myDay, localizedTitle: l10n.tr('myDay'), icon: 'ic_shortcut_myday'),
      ShortcutItem(type: _compose, localizedTitle: l10n.tr('shortcutCompose'), icon: 'ic_shortcut_compose'),
      ShortcutItem(type: _event, localizedTitle: l10n.tr('shortcutEvent'), icon: 'ic_shortcut_event'),
      ShortcutItem(type: _reminder, localizedTitle: l10n.tr('shortcutReminder'), icon: 'ic_shortcut_reminder'),
    ]);
  }

  /// Ящик для нового письма: открытый, иначе первый личный, иначе основной.
  static String? _accountId(ProviderContainer container) {
    final explicit = container.read(settingsProvider).activeAccountId;
    final accounts = container.read(accountsProvider);
    if (explicit != null && accounts.any((a) => a.id == explicit)) return explicit;
    final personal = accounts.where((a) => !a.isWork).firstOrNull;
    return personal?.id ?? container.read(activeAccountProvider)?.id;
  }

  /// Открыть экран быстрого действия — и для нажатий на виджет «Мой день».
  static Future<void> openType(ProviderContainer container, String type) => _open(container, type);

  static Future<void> _open(ProviderContainer container, String type) async {
    final router = container.read(appRouterProvider);
    // Холодный запуск: ждём, пока заставка, вход и блокировка пропустят на
    // главный экран, — иначе они перекроют открытое окно.
    for (var i = 0; i < 60; i++) {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      const gate = {'/splash', '/onboarding', '/license', '/login', '/lock'};
      if (path.isNotEmpty && !gate.contains(path)) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    // Письмо из виджета «Почта»: «email?id=…&acc=…».
    if (type.startsWith('email')) {
      final q = Uri.parse(type).queryParameters;
      final id = q['id'];
      if (id != null && id.isNotEmpty) {
        unawaited(router.push(messagePath(id, accountId: q['acc'])));
      }
      return;
    }
    // Встреча из виджета «Календарь»: «calevent?id=…&acc=…».
    if (type.startsWith('calevent')) {
      final q = Uri.parse(type).queryParameters;
      final id = q['id'];
      if (id != null && id.isNotEmpty) {
        unawaited(router.push(eventDetailsPath(id, accountId: q['acc'] ?? '')));
      }
      return;
    }
    // Раздел «Заметки» выключен (1.5.9) — виджет и ярлык ведут в почту.
    if ((type.startsWith('note?') || type == 'newnote' || type == 'notes') &&
        !container.read(featureFlagsProvider).showNotes) {
      router.go('/mail');
      return;
    }
    // Заметка из виджета «Заметки»: «note?id=…»; «newnote» — новая.
    if (type.startsWith('note?')) {
      final id = Uri.parse(type).queryParameters['id'];
      if (id != null && id.isNotEmpty) unawaited(router.push('/notes/edit', extra: id));
      return;
    }
    if (type == 'newnote') {
      unawaited(router.push('/notes/edit'));
      return;
    }
    final acc = _accountId(container);
    switch (type) {
      case _compose:
        unawaited(router.push(Uri(path: '/compose', queryParameters: {
          if (acc != null) 'accountId': acc,
        }).toString()));
      case _event:
        unawaited(router.push('/create-event'));
      case _myDay:
        router.go('/my-day');
      case 'mail':
        router.go('/mail');
      case 'calendar':
        router.go('/calendar');
      case 'notes':
        router.go('/notes');
      case _reminder:
        router.go(Uri(path: '/tasks', queryParameters: {
          'new': '1',
          if (acc != null) 'accountId': acc,
        }).toString());
    }
  }
}
