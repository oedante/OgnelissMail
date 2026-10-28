// lib/widgets/common/shared_mailbox_badge.dart
//
// Визуальное выделение элементов ОБЩЕГО (делегированного) ящика.
//
// Зачем это нужно. Секретарь ведёт ящик руководителя, отдел — общий ящик
// подразделения. Письма, события и задачи из такого ящика внешне ничем не
// отличаются от собственных, и легко ошибиться: ответить от чужого имени,
// удалить чужое письмо, принять приглашение за руководителя. Цена ошибки в
// деловой переписке высокая, поэтому такие элементы помечаются явно.
//
// Оформление намеренно спокойное: не красный «алярм», а заметная, но
// нейтральная метка — работа с общим ящиком штатная, а не аварийная.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

import '../../core/theme/app_theme.dart';

/// Цвет-акцент для элементов общего ящика.
const kSharedMailboxColor = AppColors.accentOrange;

/// Компактная метка «общий ящик» с адресом.
class SharedMailboxBadge extends StatelessWidget {
  const SharedMailboxBadge({
    super.key,
    required this.mailboxEmail,
    this.compact = false,
  });

  final String mailboxEmail;

  /// Компактный вид — только иконка с подсказкой. Для плотных списков.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: mailboxEmail,
        child: const Icon(AppIcons.supervisor_account,
            size: 14, color: kSharedMailboxColor),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kSharedMailboxColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: kSharedMailboxColor.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.supervisor_account,
              size: 12, color: kSharedMailboxColor),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              mailboxEmail,
              style: const TextStyle(
                fontSize: 10,
                color: kSharedMailboxColor,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Полоса-акцент слева от элемента общего ящика.
///
/// Используется в списках: тонкая вертикальная линия заметна периферийным
/// зрением при быстрой прокрутке, но не отвлекает при чтении.
class SharedMailboxStripe extends StatelessWidget {
  const SharedMailboxStripe({super.key, required this.child, required this.isShared});

  final Widget child;
  final bool isShared;

  @override
  Widget build(BuildContext context) {
    if (!isShared) return child;
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: kSharedMailboxColor, width: 3),
        ),
      ),
      child: child,
    );
  }
}
