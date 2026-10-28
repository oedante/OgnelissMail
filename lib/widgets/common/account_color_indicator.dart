// lib/widgets/common/account_color_indicator.dart
// Цветовая метка аккаунта — тонкая полоска слева на письме,
// показывающая из какого аккаунта пришло письмо.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/mail/providers/mail_providers.dart';

/// Тонкая полоска цвета аккаунта слева от письма
class AccountColorIndicator extends ConsumerWidget {
  final String accountId;
  final double width;
  final double height;

  const AccountColorIndicator({
    super.key,
    required this.accountId,
    this.width = 3,
    this.height = double.infinity,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final account = accounts.where((a) => a.id == accountId).firstOrNull;

    if (account == null || accounts.length <= 1) {
      return const SizedBox.shrink();
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color(account.colorValue),
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}

/// Точка с цветом аккаунта (для использования inline)
class AccountColorDot extends ConsumerWidget {
  final String accountId;
  final double size;

  const AccountColorDot({
    super.key,
    required this.accountId,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final account = accounts.where((a) => a.id == accountId).firstOrNull;

    if (account == null || accounts.length <= 1) return const SizedBox.shrink();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(account.colorValue),
        shape: BoxShape.circle,
      ),
    );
  }
}
