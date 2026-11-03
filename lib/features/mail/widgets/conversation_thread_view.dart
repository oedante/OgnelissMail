// lib/features/mail/widgets/conversation_thread_view.dart
// Беседа под текстом письма (блок «Беседа (N писем)»): письма по времени на
// линии, текущее отмечено.
//
// 1.10.5 (просьба владельца 03.11.2026 «проверь беседу, которая при открытии
// письма показывается»):
// - нажатие на письмо открывает его (раньше только разворачивало превью —
//   открыть соседнее письмо или черновик отсюда было нельзя); стрелка
//   справа — больше текста превью;
// - портрет — тот же, что в шапке письма и в ленте (фото из контактов,
//   логотип BIMI или буква), а не только буква;
// - превью одной строкой без переносов («Hi Oedante, Congrats! …», а не
//   одно «Hi Oedante,»);
// - черновик ответа — «Черновик» красным и кому (как в ленте), нажатие —
//   редактор;
// - текущее письмо не разворачивается: его текст и так выше.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/text_safe.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/hero_email_transition.dart';

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
  State<ConversationThreadView> createState() => _ConversationThreadViewState();
}

class _ConversationThreadViewState extends State<ConversationThreadView> {
  /// Письма с развёрнутым превью (стрелка справа).
  final Set<String> _expandedIds = {};

  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sorted = List<EmailModel>.from(widget.emails)..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

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
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        for (var i = 0; i < sorted.length; i++) _item(context, sorted[i], isLast: i == sorted.length - 1),
      ],
    );
  }

  Widget _item(BuildContext context, EmailModel email, {required bool isLast}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final isCurrent = email.id == widget.currentEmailId;
    final isExpanded = !isCurrent && _expandedIds.contains(email.id);
    final draft = email.isDraft || email.folderId == 'drafts';
    final preview = _oneLine(email.preview);
    final name = email.from.label;

    final title = draft
        ? Text.rich(
            TextSpan(children: [
              TextSpan(text: l10n.tr('draft'), style: TextStyle(color: scheme.error)),
              if (email.to.isNotEmpty) TextSpan(text: '  ${email.to.map((a) => a.label).join(', ')}'),
            ]),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: email.isRead ? FontWeight.w600 : FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    final card = Material(
      color: isCurrent
          ? scheme.primaryContainer.withValues(alpha: 0.1)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent ? BorderSide(color: scheme.primary.withValues(alpha: 0.2)) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Текущее письмо уже открыто — нажатие ничего не делает.
        onTap: isCurrent ? null : () => widget.onEmailTap(email),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HeroEmailAvatar(
                    emailId: 'thread/${email.accountId}/${email.id}',
                    initial: initialOf(name.isNotEmpty ? name : email.from.email),
                    color: HeroEmailAvatar.colorForEmail(email.from.email),
                    email: email.from.email,
                    authResults: email.authResults,
                    radius: 14,
                    hero: false,
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: title),
                  if (email.hasAttachments)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xs),
                      child: Icon(AppIcons.attach_file, size: Sizes.iconInline, color: scheme.onSurfaceVariant),
                    ),
                  const SizedBox(width: Space.xs),
                  Text(
                    DateFormat('d MMM, HH:mm', l10n.localeCode).format(email.receivedAt.toLocal()),
                    style: theme.textTheme.bodySmall,
                  ),
                  // Больше текста превью — без открытия письма.
                  if (!isCurrent && preview.isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      tooltip: l10n.tr(isExpanded ? 'collapse' : 'expand'),
                      icon: Icon(isExpanded ? AppIcons.expand_less : AppIcons.expand_more,
                          size: 20, color: scheme.onSurface.withValues(alpha: 0.5)),
                      onPressed: () => setState(() {
                        if (!_expandedIds.remove(email.id)) _expandedIds.add(email.id);
                      }),
                    )
                  else
                    const SizedBox(width: Space.s),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Padding(
                  padding: const EdgeInsets.only(right: Space.s),
                  child: Text(
                    isExpanded ? email.preview.trim() : preview,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.4,
                      color: isExpanded ? null : scheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: isExpanded ? 12 : (isCurrent ? 1 : 2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Линия времени: точка и линия к следующему письму.
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: Space.m),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent ? scheme.primary : scheme.outline.withValues(alpha: 0.3),
                    border: isCurrent ? Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 3) : null,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: scheme.outline.withValues(alpha: 0.15))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.s, right: Space.l),
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}
