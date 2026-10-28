// lib/features/mail/widgets/account_auth_banner.dart
// Плашка «не удаётся войти в ящик» над списком писем.
//
// Раньше при смене пароля или отзыве доступа синхронизация просто
// останавливалась: список выглядел актуальным, новые письма не приходили,
// а сообщить об этом было некому (errorBannerProvider нигде не заполнялся).
// Теперь видно, какой ящик не синхронизируется, и войти снова можно прямо
// отсюда — без удаления аккаунта.

import 'dart:async';
import '../../../core/theme/app_icons.dart';

import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/certificate_pinning_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../auth/widgets/certificate_trust_dialog.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/mail_providers.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

class AccountAuthBanner extends ConsumerWidget {
  const AccountAuthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(accountsProvider
        .select((l) => l.where((a) => a.isActive && a.authFailedAt != null).toList()));
    if (failed.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final a in failed)
          Material(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 6, Space.s, 6),
              child: Row(
                children: [
                  Icon(AppIcons.lock_reset, size: 20, color: scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.tr('authFailedBanner').replaceAll('{email}', a.email),
                      style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => reauthenticateFlow(context, ref, a),
                    child: Text(l10n.tr('signInAgain')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Повторное подключение ящика.
///
/// OAuth — сразу в браузер. Вход по паролю — экран входа в режиме «Войти
/// снова» (`/login?reauth=<id>`): адрес ящика, пароль и в «Расширенных
/// настройках» — логин, домен, сервер и совместимость со шлюзом (Exchange)
/// или серверы, порты и шифрование IMAP/SMTP, всё заполнено текущими
/// значениями.
///
/// После входа — проверка: если сервер ответил сертификатом, которому
/// устройство не доверяет, предлагается сверить отпечаток и доверять ему
/// (как при добавлении ящика). Раньше переподключение к серверу с
/// собственным сертификатом просто не удавалось.
Future<void> reauthenticateFlow(BuildContext context, WidgetRef ref, AccountModel a) async {
  final l10n = AppLocalizations.of(context);
  final started = DateTime.now();
  var account = a;
  if (!a.usesOAuthTokens) {
    // Вход по паролю — экран входа в режиме «Войти снова» (1.5.12): те же
    // поля, что при добавлении ящика, заполненные данными ящика. Раньше был
    // отдельный диалог, где подписи полей наезжали друг на друга. Ошибки
    // входа экран показывает сам; закрылся без ящика — пользователь отменил.
    final result = await context.push<AccountModel>('/login?reauth=${Uri.encodeQueryComponent(a.id)}');
    if (result == null) return;
    account = result;
  } else {
    final err = await ref.read(authProvider.notifier).reauthenticate(account);
    if (err != null) {
      if (err.startsWith('mismatch:')) {
        showInlineError(l10n.tr('reauthMismatch').replaceAll('{email}', err.substring(9)));
      } else {
        showInlineError(err);
      }
      return;
    }
  }
  showInlineNotice(l10n.tr('reauthDone'));

  // Ждём первую синхронизацию с новыми данными и проверяем сертификат.
  final fresh = ref.read(accountsProvider).where((x) => x.id == a.id).firstOrNull ?? account;
  await ref.read(syncServiceProvider).syncAccount(fresh);
  final pins = ref.read(certPinningProvider);
  final rejected = pins.lastRejected(since: started, hosts: _hostsOf(fresh));
  if (rejected == null || !context.mounted) return;
  if (rejected.pinMismatch) {
    // Сертификат сервера сменился, а закреплён прежний: раньше об этом
    // молчали, и ящик просто не синхронизировался. Доверять новому сами не
    // предлагаем (это может быть подмена) — объясняем, что делать.
    showInlineError(l10n.tr('certPinMismatchLogin').replaceAll('{host}', rejected.host));
    return;
  }
  if (await showCertificateTrustDialog(context, rejected)) {
    await pins.trustCertificate(rejected);
    ref.read(mailEngineServiceProvider).disconnect(a.id);
    unawaited(ref.read(syncServiceProvider).syncAccount(fresh));
  }
}

/// Хосты серверов ящика без схемы и порта.
Set<String> _hostsOf(AccountModel a) {
  String? h(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    var s = v.trim();
    final u = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    s = u?.host ?? s;
    return s.isEmpty ? null : s.toLowerCase();
  }
  return {
    for (final v in [a.exchangeServer, a.ewsUrl, a.imapServer, a.smtpServer])
      if (h(v) case final x?) x,
  };
}
