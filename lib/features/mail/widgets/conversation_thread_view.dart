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
//
// 2.6.8 (владелец 21.11.2026: «при открытии длинных бесед подвисает»): блок
// строил все письма беседы сразу, и каждое — с IntrinsicHeight (раскладка
// дважды). На беседе из 400 писем — 3,3 с на первый кадр и 1,6 с на каждую
// перерисовку письма над ним (замер test/widget/conversation_thread_view_test).
// Теперь — окно из [window] писем вокруг текущего, «Более новые» и «Более
// ранние» добавляют по [step], «Вся беседа» открывает экран беседы (там
// список ленивый). Линия времени — без IntrinsicHeight.

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

  /// Вся беседа отдельным экраном; null — без кнопки.
  final VoidCallback? onOpenAll;

  /// Сколько писем показано сразу (вокруг текущего).
  static const window = 7;

  /// Сколько добавляют «Более новые» / «Более ранние».
  static const step = 20;

  const ConversationThreadView({
    super.key,
    required this.emails,
    required this.currentEmailId,
    required this.onEmailTap,
    this.onOpenAll,
  });

  @override
  State<ConversationThreadView> createState() => _ConversationThreadViewState();
}

class _ConversationThreadViewState extends State<ConversationThreadView> {
  /// Письма с развёрнутым превью (стрелка справа).
  final Set<String> _expandedIds = {};

  /// Сколько писем добавлено к окну сверху (новее) и снизу (раньше).
  int _moreNewer = 0;
  int _moreOlder = 0;

  /// Письма новые сверху — сортируются, только когда список сменился.
  List<EmailModel>? _sortedOf;
  List<EmailModel> _sorted = const [];

  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  void didUpdateWidget(ConversationThreadView old) {
    super.didUpdateWidget(old);
    if (old.currentEmailId != widget.currentEmailId) {
      _moreNewer = 0;
      _moreOlder = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Новые сверху (1.14.0, просьба владельца 06.11.2026) — как в ленте:
    // последний ответ виден первым, без прокрутки через всю беседу.
    if (!identical(_sortedOf, widget.emails)) {
      _sortedOf = widget.emails;
      _sorted = List<EmailModel>.from(widget.emails)..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    }
    final sorted = _sorted;
    final range = threadWindow(
      count: sorted.length,
      current: sorted.indexWhere((e) => e.id == widget.currentEmailId),
      moreNewer: _moreNewer,
      moreOlder: _moreOlder,
    );
    final hidden = sorted.length - (range.end - range.start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
          child: Row(
            children: [
              Icon(AppIcons.forum, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  l10n.plural('threadTitleN', sorted.length),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              // Длинная беседа — целиком на экране беседы.
              if (hidden > 0 && widget.onOpenAll != null)
                TextButton(
                  key: const ValueKey('thread_open_all'),
                  onPressed: widget.onOpenAll,
                  child: Text(l10n.tr('threadOpenAll')),
                ),
            ],
          ),
        ),
        if (range.start > 0)
          _more(context, l10n.tr('threadNewer').replaceAll('{n}', '${range.start}'), up: true,
              onTap: () => setState(() => _moreNewer += ConversationThreadView.step)),
        for (var i = range.start; i < range.end; i++)
          _item(context, sorted[i], isLast: i == sorted.length - 1),
        if (range.end < sorted.length)
          _more(context, l10n.tr('threadOlder').replaceAll('{n}', '${sorted.length - range.end}'), up: false,
              onTap: () => setState(() => _moreOlder += ConversationThreadView.step)),
      ],
    );
  }

  /// «Более новые письма: N» / «Более ранние письма: N».
  Widget _more(BuildContext context, String label, {required bool up, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(left: _rail, right: Space.l, bottom: Space.s),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: ValueKey(up ? 'thread_newer' : 'thread_older'),
            onPressed: onTap,
            icon: Icon(up ? AppIcons.expand_less : AppIcons.expand_more, size: 20),
            label: Text(label),
          ),
        ),
      );

  /// Ширина колонки линии времени.
  static const double _rail = 48;

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
                    folder: (account: email.accountId, folder: email.folderId),
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

    // Линия времени: точка и линия к следующему письму. Без
    // IntrinsicHeight: линия — позиционированный слой по высоте карточки.
    const dotTop = Space.m;
    return Stack(
      children: [
        if (!isLast)
          PositionedDirectional(
            start: _rail / 2 - 1,
            top: dotTop + 12,
            bottom: 0,
            child: Container(width: 2, color: scheme.outline.withValues(alpha: 0.15)),
          ),
        PositionedDirectional(
          start: _rail / 2 - 6,
          top: dotTop,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent ? scheme.primary : scheme.outline.withValues(alpha: 0.3),
              border: isCurrent ? Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 3) : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: _rail, bottom: Space.s, end: Space.l),
          child: card,
        ),
      ],
    );
  }
}

/// Окно писем блока «Беседа» (новые сверху): [window] писем вокруг текущего
/// (два более новых над ним), плюс добавленные «Более новые» / «Более
/// ранние». [current] -1 — текущего письма в списке нет: с самого нового.
@visibleForTesting
({int start, int end}) threadWindow({
  required int count,
  required int current,
  int moreNewer = 0,
  int moreOlder = 0,
  int window = ConversationThreadView.window,
}) {
  if (count <= 0) return (start: 0, end: 0);
  final c = current < 0 ? 0 : current;
  var start = c - 2 < 0 ? 0 : c - 2;
  var end = start + window > count ? count : start + window;
  if (end - start < window) start = end - window < 0 ? 0 : end - window;
  start = start - moreNewer < 0 ? 0 : start - moreNewer;
  end = end + moreOlder > count ? count : end + moreOlder;
  return (start: start, end: end);
}
