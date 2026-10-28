// lib/features/mail/widgets/conversation_thread_view.dart
// Визуализация цепочки писем (threading/conversation view).
// Показывает хронологию переписки с индикацией направления,
// свёрнутые/развёрнутые сообщения, аватарки участников.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/avatar_colors.dart';
import '../../../core/utils/text_safe.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/person_photo.dart' show avatarTones;

class ConversationThreadView extends StatefulWidget {
  final List<EmailModel> emails;
  final String currentEmailId;
  final void Function(EmailModel email) onEmailTap;

  const ConversationThreadView({
    super.key,
    required this.emails,
    required this.currentEmailId,
    required this.onEmailTap,
  });

  @override
  State<ConversationThreadView> createState() =>
      _ConversationThreadViewState();
}

class _ConversationThreadViewState extends State<ConversationThreadView> {
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    // Разворачиваем текущее письмо по умолчанию
    _expandedIds.add(widget.currentEmailId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sorted = List<EmailModel>.from(widget.emails)
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
          child: Row(
            children: [
              Icon(AppIcons.forum, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Space.s),
              Text(
                l10n.plural('threadTitleN', sorted.length),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Цепочка
        ...sorted.asMap().entries.map((entry) {
          final index = entry.key;
          final email = entry.value;
          final isExpanded = _expandedIds.contains(email.id);
          final isCurrent = email.id == widget.currentEmailId;
          final isLast = index == sorted.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Линия таймлайна
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      // Точка
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withValues(alpha: 0.3),
                          border: isCurrent
                              ? Border.all(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  width: 3)
                              : null,
                        ),
                      ),
                      // Линия вниз
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: theme.colorScheme.outline.withValues(alpha: 0.15),
                          ),
                        ),
                    ],
                  ),
                ),

                // Содержимое
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedIds.remove(email.id);
                        } else {
                          _expandedIds.add(email.id);
                        }
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: Space.s, right: Space.l),
                      padding: const EdgeInsets.all(Space.m),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.1)
                            : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent
                            ? Border.all(
                                color:
                                    theme.colorScheme.primary.withValues(alpha: 0.2))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Заголовок
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    avatarTones(context, _avatarColor(email.from.email)).fill,
                                // Пустой отправитель (черновик, системное
                                // письмо) ронял экран: RangeError на [0]
                                // (журнал 13.10.2026).
                                child: Text(
                                  initialOf(email.from.displayName ?? email.from.email),
                                  style: TextStyle(
                                    color: avatarTones(context, _avatarColor(email.from.email)).letter,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: Space.s),
                              // Черновик в цепочке: видно, что ответ начат, но
                              // не отправлен. Без пометки он выглядел бы как
                              // обычное письмо, и человек мог решить, что уже
                              // ответил.
                              if (email.isDraft)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    '[${l10n.tr('draft')}]',
                                    style: const TextStyle(
                                      color: AppColors.errorRed,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  email.isDraft ? '' : email.from.label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                DateFormat('d MMM, HH:mm', l10n.localeCode)
                                    .format(email.receivedAt.toLocal()),
                                style: theme.textTheme.bodySmall,
                              ),
                              Icon(
                                isExpanded
                                    ? AppIcons.expand_less
                                    : AppIcons.expand_more,
                                size: 20,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ],
                          ),

                          // Развёрнутое содержимое
                          if (isExpanded) ...[
                            const SizedBox(height: Space.s),
                            Text(
                              email.bodyPreview ?? email.bodyPlain ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.4,
                              ),
                              maxLines: 10,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (email.hasAttachments) ...[
                              const SizedBox(height: Space.xs),
                              Row(
                                children: [
                                  Icon(AppIcons.attach_file,
                                      size: 14,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4)),
                                  const SizedBox(width: Space.xs),
                                  Text(
                                    l10n.plural('attachmentsCountN', email.attachments.length),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ] else ...[
                            const SizedBox(height: Space.xs),
                            Text(
                              email.preview,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Цвет кружка — общая приглушённая палитра (прежние пастельные тона с
  /// белой буквой не читались).
  Color _avatarColor(String email) => Color(avatarColorValue(email));
}
