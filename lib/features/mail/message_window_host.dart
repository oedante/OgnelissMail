// lib/features/mail/message_window_host.dart
//
// Главное окно выполняет просьбы окон писем (message_window.dart): ответить,
// переслать, удалить, открыть ссылку или само письмо — и выходит на передний
// план (1.9.x, просьба владельца 31.10.2026).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/app_router.dart';
import '../../core/security/link_opener.dart';
import '../../services/mail/email_actions_service.dart';
import 'message_window.dart';
import 'providers/mail_providers.dart' show accountsProvider;

abstract final class MessageWindowHost {
  static Future<void> start(ProviderContainer container) =>
      MessageWindow.serve((method, args) => handle(container, method, args));

  static Future<void> handle(ProviderContainer c, String method, Map<String, Object?> args) async {
    final accountId = '${args['accountId'] ?? ''}';
    final emailId = '${args['emailId'] ?? ''}';
    final router = c.read(appRouterProvider);
    final q = 'accountId=${Uri.encodeQueryComponent(accountId)}';
    final id = Uri.encodeQueryComponent(emailId);
    try {
      switch (method) {
        case 'reply':
          await _front();
          unawaited(router.push('/compose?replyToId=$id&$q'));
        case 'replyAll':
          await _front();
          unawaited(router.push('/compose?replyToId=$id&$q&replyAll=true'));
        case 'forward':
          await _front();
          unawaited(router.push('/compose?forwardFromId=$id&$q'));
        case 'open' || 'openAttachment':
          await _front();
          unawaited(router.push(messagePath(emailId, accountId: accountId)));
        case 'openLink':
          final ctx = router.routerDelegate.navigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          await _front();
          if (!ctx.mounted) return;
          await LinkOpener.open(ctx, '${args['url'] ?? ''}', linkText: args['text'] as String?, accountId: accountId);
        case 'delete':
          final account = c.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
          if (account == null) return;
          await c.read(emailActionsProvider).delete(account, emailId, '${args['folderId'] ?? ''}');
      }
    } catch (e) {
      AppLogger.warning('Окно письма: «$method» не выполнено — $e');
    }
  }

  static Future<void> _front() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }
}
