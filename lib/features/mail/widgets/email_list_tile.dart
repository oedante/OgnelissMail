// lib/features/mail/widgets/email_list_tile.dart
// Финальный тайл письма:
// - Hero-анимация аватарки
// - Цветовая метка аккаунта (полоска слева)
// - Реальный счётчик бесед
// - Optimized sub-widgets
// - Semantics для screen reader
// - Иконки: приоритет, вложения, флаг, replied, forwarded

import '../../../core/utils/text_safe.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/shared_mailbox_badge.dart';
import '../../../data/models/email_model.dart';
import '../../../services/rules/device_rules_service.dart' show highlightTagsProvider;
import '../../../services/mail/own_addresses.dart';
import '../../../services/mail/control_service.dart';
import '../../../services/mail/conversation_counter.dart';
import '../../../services/mail/reply_drafts.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/animated_appearance.dart';
import '../../../widgets/common/quick_long_press.dart';
import '../../../core/utils/app_date_format.dart';
import '../providers/mail_providers.dart' show accountsProvider;
import '../../../data/models/account_model.dart';
import '../../settings/providers/settings_provider.dart';
import 'preview_text.dart';
import '../providers/pinned_mail.dart' show pinnedMailProvider;
import '../../../core/theme/ogneliss_look.dart';

class EmailListTile extends ConsumerWidget {
  final EmailModel email;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  /// Палец после удержания строки (карточка письма: провести на кнопку).
  final HoldTracker? holdTracker;
  /// Палец после удержания портрета (выбор писем проведением, 1.6.47).
  final HoldTracker? avatarHoldTracker;
  /// Долгое нажатие на портрет — выбор писем (на остальной строке — меню).
  final VoidCallback? onAvatarLongPress;
  /// Правая кнопка мыши / двухпальцевое нажатие на тачпаде — меню действий.
  final VoidCallback? onSecondaryTap;
  final bool showConversationIndicator;

  /// Показывать метку папки. Включается в сводных режимах («Вся почта»,
  /// результаты поиска), где письма приходят из разных папок.
  final bool showFolderBadge;

  /// Отметить ящик письма: цветная полоса слева и имя ящика в метке.
  /// Включается в «Хабе аккаунтов» и группах, где в одной ленте письма
  /// нескольких ящиков (раньше было видно только папку — «Входящие», а чьи
  /// это входящие, нет; замечание 06.10.2026).
  final bool showAccountMark;

  /// Адрес общего ящика, если письмо принадлежит делегированному ящику.
  /// Такие письма выделяются: легко ошибиться и ответить от чужого имени.
  final String? sharedMailboxEmail;
  final bool isSelected;
  final bool isInSelectionMode;
  final bool isChecked;
  final VoidCallback? onCheckChanged;
  /// Список «Позже»: справа — срок возврата вместо даты получения.
  final bool showLaterTime;

  const EmailListTile({
    this.showLaterTime = false,
    this.showFolderBadge = false,
    this.showAccountMark = false,
    this.sharedMailboxEmail,
    super.key,
    required this.email,
    this.onTap,
    this.onLongPress,
    this.holdTracker,
    this.avatarHoldTracker,
    this.onSecondaryTap,
    this.showConversationIndicator = true,
    this.onAvatarLongPress,
    this.isSelected = false,
    this.isInSelectionMode = false,
    this.isChecked = false,
    this.onCheckChanged,
  });

  /// Появляются плавно только письма, пришедшие за время работы приложения,
  /// и только один раз: строки, прокрученные в экран или подгруженные
  /// следующей страницей, показываются сразу (иначе список «мигает»).
  static final _sessionStart = DateTime.now();
  static final _appeared = <String>{};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fresh = uiAnimations && email.receivedAt.isAfter(_sessionStart) && _appeared.add(email.id);
    final tile = AnimatedAppearance(play: fresh, child: _buildTile(context, ref));
    if (!showAccountMark) return tile;
    final mark = ref.watch(accountsProvider.select((l) => accountMarkOf(l, email.accountId)));
    if (mark == null) return tile;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Color(mark.color), width: 4)),
      ),
      child: tile,
    );
  }

  static Widget _controlMark(BuildContext context, int state, {({int replied, int total})? progress}) {
    // Моё письмо нескольким адресатам: круг заполняется по доле ответивших
    // из «Кому» (копия не считается).
    if (progress != null && state == 1) {
      return Tooltip(
        message: '${progress.replied}/${progress.total}',
        child: SizedBox(
          width: 14,
          height: 14,
          child: CustomPaint(
            painter: ControlRingPainter(
              fraction: progress.total == 0 ? 0 : progress.replied / progress.total,
              color: Theme.of(context).colorScheme.primary,
              track: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      );
    }
    final (icon, color) = switch (state) {
      3 => (AppIcons.bookmark_added, AppColors.successText(context)),
      2 => (AppIcons.bookmark, AppColors.accentOrange),
      _ => (AppIcons.bookmark, Theme.of(context).colorScheme.primary),
    };
    return Icon(icon, size: 14, fill: 1, color: color);
  }

  static Widget _laterMark(BuildContext context, int state) => Icon(
        AppIcons.watch_later,
        size: 14,
        fill: 1,
        color: state == 2 ? AppColors.accentOrange : const Color(0xFF7B61B8),
      );

  /// Цвет и короткое имя ящика для отметки в общей ленте. Имя — то, что
  /// различает ящики: домен без зоны («acmegroup», «gmail»), а если с этим
  /// доменом несколько ящиков — имя до «@».
  static ({int color, String label})? accountMarkOf(List<AccountModel> list, String accountId) {
    AccountModel? a;
    for (final x in list) {
      if (x.id == accountId) a = x;
    }
    if (a == null) return null;
    final at = a.email.indexOf('@');
    if (at < 0) return (color: a.colorValue, label: a.email);
    final local = a.email.substring(0, at);
    final domain = a.email.substring(at + 1).toLowerCase();
    final sameDomain = list.where((x) => x.email.toLowerCase().endsWith('@$domain')).length;
    final label = sameDomain > 1 ? local : domain.split('.').first;
    return (color: a.colorValue, label: label);
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Свёрнутая беседа: непрочитанная, если внутри есть непрочитанные письма
    // (а не только верхнее), и отметка «На контроле» любого письма беседы.
    final conv = showConversationIndicator && email.conversationId != null
        ? ref.watch(conversationStatsProvider.select((m) => m[conversationKey(email.accountId, email.conversationId!)]))
        : null;
    final isUnread = !email.isRead || (conv?.unread ?? 0) > 0;
    final controlState = (conv?.control ?? 0) != 0 ? conv!.control : email.controlState;
    final controlReplied = (conv?.control ?? 0) != 0 ? conv!.replied : email.controlReplied;
    final controlTo = (conv?.control ?? 0) != 0 ? conv?.to : null;
    // Закреплено вверху (1.7.2+110, пункт плана «закреплённое — значком
    // булавки в строке»): булавка среди значков строки — закреплённое видно и
    // в поиске, и после прокрутки, где полосы раздела уже нет.
    final pinned = ref.watch(pinnedMailProvider.select((l) => l.any((p) => p.accountId == email.accountId && p.emailId == email.id)));

    // Своё отправленное письмо (во «Всей почте» теперь есть и отправленные):
    // вместо собственного имени — адресаты.
    // «Своё» — любой адрес ящика (адрес входа, основной с сервера, алиасы).
    final isOwnFrom = ref.watch(accountsProvider.select((list) {
      for (final a in list) {
        if (a.id == email.accountId) {
          if (a.sharedMailboxEmail?.isNotEmpty ?? false) {
            return email.from.email.toLowerCase() == a.sharedMailboxEmail!.toLowerCase();
          }
          return OwnAddresses.isMine(a, email.from.email);
        }
      }
      return false;
    }));
    final isOwnSent = !email.isDraft && isOwnFrom && email.to.isNotEmpty;
    final ownAddress = email.from.email.toLowerCase();

    final accountMark = showAccountMark
        ? ref.watch(accountsProvider.select((l) => accountMarkOf(l, email.accountId)))
        : null;

    final showControl = ref.watch(settingsProvider.select((s) => s.mailControl));
    final previewLines = ref.watch(settingsProvider.select((s) => s.previewLines));

    // Правило «подсветить строку»: лёгкий фон цвета тега (правила на телефоне).
    final hlTags = ref.watch(highlightTagsProvider);
    final hlTag = hlTags.isEmpty ? null : email.tags.where(hlTags.contains).firstOrNull;
    final hlColor = hlTag == null ? null : AppTheme.getTagColor(hlTag).withValues(alpha: 0.08);

    // Счётчик бесед
    final convCounts = ref.watch(conversationCountProvider);
    final convCount = email.conversationId != null
        ? (convCounts[conversationKey(email.accountId, email.conversationId!)] ?? 1)
        : 1;

    // Начат и не отправлен ответ на это письмо (на свёрнутой беседе — на
    // любое её письмо): в строке превью «Черновик: …», как в Telegram
    // (1.7.0). Пока сам черновик есть в «Черновиках».
    final convForDraft = showConversationIndicator && convCount > 1 ? email.conversationId : null;
    final replyDraft = email.isDraft
        ? null
        : ref.watch(replyDraftsProvider.select(
            (m) => m.isEmpty ? null : replyDraftFor(m, email.accountId, email.id, convForDraft)));
    final showReplyDraft = replyDraft != null &&
        ref.watch(draftSubjectsProvider.select(
            (v) => v.value?.contains(ReplyDraft.bareSubject(replyDraft.subject)) ?? true));

    // Фон строки: лента — цвета поверхности (белая в светлой теме), выбранное
    // письмо — заливкой secondaryContainer, правило «подсветить» и
    // непрочитанное — лёгким оттенком поверх фона ленты.
    final listBg = AppColors.listFill(context);
    final rowColor = isSelected
        ? theme.colorScheme.secondaryContainer
        : hlColor != null
            ? Color.alphaBlend(hlColor, listBg)
            : (isUnread
                ? Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.035), listBg)
                : listBg);

    return Semantics(
      // Для озвучивания «Кому:» у своих писем остаётся.
      label: '${isOwnSent ? '${AppLocalizations.of(context).tr('toLbl')}: ${email.to.map((a) => a.label).join(', ')}' : email.from.label}. '
          '${email.subject}. ${email.preview}',
      button: true,
      // Строка непрозрачная, цвета ленты (1.6.25): под ней панель свайпа, и
      // прозрачная строка пропускала её цвет. Между строками — тонкая линия
      // от начала текста, как в настройках (лента без линий сливалась).
      child: Material(
        color: rowColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Удержание — 250 мс, а не 500 (1.6.46): QuickLongPress. После
            // удержания палец можно довести до кнопки карточки ([holdTracker]).
            QuickLongPress(
              onLongPress: onLongPress,
              tracker: holdTracker,
              // «Вдавливание» строки, пока палец держит (1.6.47).
              pressEffect: true,
              child: InkWell(
              onTap: onTap,
              onSecondaryTap: onSecondaryTap,
              child: Container(
                // Без линий строки чуть свободнее (1.8.0): 10 вместо 8.
                padding: EdgeInsets.symmetric(
                    vertical: OgnelissLook.of(context).outlined ? Space.s : Space.s + Space.xxs),
                child: Row(
                  children: [
                    // Цветная полоса аккаунта слева убрана (замечание 05.10:
                    // «рядом с письмами какие-то полосы»).
                    // Checkbox (в режиме выбора) или аватарка
                    Stack(clipBehavior: Clip.none, children: [
                    // Удержание портрета — выбор писем, так же быстро, как
                    // карточка: оба по 250 мс, портрет срабатывает первым (его
                    // распознаватель ближе к пальцу и заведён раньше).
                    QuickLongPress(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: onAvatarLongPress ?? onLongPress,
                      tracker: onAvatarLongPress == null ? holdTracker : avatarHoldTracker,
                      child: Padding(
                      padding: const EdgeInsets.only(left: Space.l, right: Space.m),
                      child: isInSelectionMode
                          ? Checkbox(
                              value: isChecked,
                              onChanged: (_) => onCheckChanged?.call(),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            )
                          : HeroEmailAvatar(
                              // id письма уникален только внутри ящика: в «Вся
                              // почта» у двух аккаунтов может быть INBOX:123.
                              emailId: '${email.accountId}/${email.id}',
                              initial: _initial(email.from),
                              color: HeroEmailAvatar.colorForEmail(email.from.email),
                              email: email.from.email,
                            ),
                    ),
                    ),
                    // Отметки в поле слева от портрета: вверху — «На контроле»
                    // (закладка: синяя — жду ответа, оранжевая — должен ответить,
                    // зелёная с галочкой — исполнено), внизу — «Позже» (часы;
                    // оранжевые — письмо вернулось).
                    if (!isInSelectionMode && controlState != 0 && showControl)
                      Positioned(
                          left: 1,
                          top: 0,
                          child: _controlMark(context, controlState,
                              progress: ControlService.progress(
                                state: controlState,
                                to: controlTo != null
                                    ? ControlService.toRecipients(controlTo, ownAddress)
                                    : [for (final a in email.to) if (a.email.toLowerCase() != ownAddress) a.email.toLowerCase()],
                                replied: controlReplied,
                              ))),
                    if (!isInSelectionMode && email.laterState != 0)
                      Positioned(left: 1, bottom: 0, child: _laterMark(context, email.laterState)),
                    ]),

                    // Содержимое
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Строка 1: Имя + время
                          Row(
                            children: [
                              if (isUnread)
                                Container(
                                  width: 8, height: 8,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                                ),
                              Expanded(
                                // Черновик — как в Outlook: «Черновик» и адресаты
                                // (отправителя у него нет — строка была пустой).
                                child: email.isDraft
                                    ? Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                            text: AppLocalizations.of(context).tr('draft'),
                                            style: TextStyle(color: theme.colorScheme.error),
                                          ),
                                          if (email.to.isNotEmpty)
                                            TextSpan(text: '  ${email.to.map((a) => a.label).join(', ')}'),
                                        ]),
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : isOwnSent
                                        // Только адресаты, с того же края, что имя
                                        // отправителя у входящих (1.5.11): стрелка и
                                        // «Кому:» сдвигали имя вправо, лента
                                        // получалась рваной. Что письмо своё, видно
                                        // по портрету и метке папки.
                                        ? Text(
                                            email.to.map((a) => a.label).join(', '),
                                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        : Text(
                                            email.from.label,
                                            style: theme.textTheme.titleSmall?.copyWith(
                                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                              ),
                              const SizedBox(width: Space.s),
                              Text(
                                showLaterTime && email.remindAt != null && email.laterState == 1
                                    ? DateFormat('HH:mm').format(email.remindAt!.toLocal())
                                    : _formatTime(context, email.receivedAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Строка 2: Тема + conversation count
                          Row(
                            children: [
                              if (email.isHighPriority)
                                const Padding(
                                  padding: EdgeInsets.only(right: Space.xs),
                                  child: Icon(AppIcons.priority_high, size: 16, color: AppColors.errorRed),
                                ),
                              Expanded(
                                child: Text(
                                  email.subject.isEmpty ? AppLocalizations.of(context).tr('noSubject') : email.subject,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showConversationIndicator && convCount > 1)
                                Container(
                                  margin: const EdgeInsets.only(left: Space.xs),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(AppIcons.forum, size: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                      const SizedBox(width: 2),
                                      Text(
                                        '$convCount',
                                        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Строка 3: Превью + иконки. Строк превью — по
                          // настройке (1–4, 1.6.31); метка папки — у первой.
                          Row(
                            crossAxisAlignment: previewLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: showReplyDraft
                                    ? Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                            text: '${AppLocalizations.of(context).tr('draftPrefix')} ',
                                            style: TextStyle(color: theme.colorScheme.error),
                                          ),
                                          TextSpan(text: replyDraft.text),
                                        ]),
                                        maxLines: previewLines,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                                        ),
                                      )
                                    : PreviewText(
                                        // Превью может быть пустым (IMAP-список грузит
                                        // только заголовки) — тогда без одинокого «-».
                                        email.preview,
                                        lines: previewLines,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                                        ),
                                      ),
                              ),
                              // Метка папки — в строке превью, а не отдельной
                              // строкой: строка письма стала на треть ниже.
                              if (accountMark != null ||
                                  (showFolderBadge && (email.folderName?.isNotEmpty ?? false)))
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  constraints: BoxConstraints(maxWidth: accountMark != null ? 170 : 120),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: accountMark != null
                                        ? Color(accountMark.color).withValues(alpha: 0.14)
                                        : theme.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      if (accountMark != null)
                                        TextSpan(
                                          text: accountMark.label,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: theme.brightness == Brightness.dark
                                                ? Color.lerp(Color(accountMark.color), Colors.white, 0.45)
                                                : Color(accountMark.color),
                                          ),
                                        ),
                                      if (accountMark != null && showFolderBadge && (email.folderName?.isNotEmpty ?? false))
                                        const TextSpan(text: ' · '),
                                      if (showFolderBadge && (email.folderName?.isNotEmpty ?? false))
                                        TextSpan(
                                          text: email.folderName!.toUpperCase() == 'INBOX'
                                              ? AppLocalizations.of(context).tr('inbox')
                                              : email.folderName!,
                                        ),
                                    ]),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (pinned)
                                Padding(padding: const EdgeInsets.only(left: Space.xs),
                                    child: Icon(AppIcons.push_pin, size: 15, fill: 1, color: theme.colorScheme.primary.withValues(alpha: 0.75))),
                              if (email.hasAttachments)
                                Padding(padding: const EdgeInsets.only(left: Space.xs),
                                    child: Icon(AppIcons.attach_file, size: 15, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                              if (email.isFlagged)
                                const Padding(padding: EdgeInsets.only(left: Space.xs),
                                    child: Icon(AppIcons.flag, size: 15, fill: 1, color: AppColors.errorRed)),
                              if (email.isReplied)
                                Padding(padding: const EdgeInsets.only(left: Space.xs),
                                    child: Icon(AppIcons.reply, size: 15, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                              if (email.isForwarded)
                                Padding(padding: const EdgeInsets.only(left: Space.xs),
                                    child: Icon(AppIcons.forward, size: 15, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
                            ],
                          ),

                          // Строка 4: метка папки и теги.
                          //
                          // Метку папки показываем только в сводных режимах («Вся
                          // почта», поиск): внутри конкретной папки она очевидна и
                          // лишь занимает место. При разветвлённой структуре папок
                          // (отделы, проекты, площадки…) это заметно помогает
                          // понять контекст письма, не открывая его.
                          // Метка общего ящика — первой: она важнее папки.
                          if (sharedMailboxEmail != null) ...[
                            const SizedBox(height: 6),
                            SharedMailboxBadge(mailboxEmail: sharedMailboxEmail!),
                          ],

                          if (email.tags.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 20,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: email.tags.length.clamp(0, 3),
                                separatorBuilder: (_, __) => const SizedBox(width: Space.xs),
                                itemBuilder: (_, i) {
                                  final tag = email.tags[i];
                                  final color = AppTheme.getTagColor(tag);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
                                    ),
                                    child: Text(tag, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: color)),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: Space.s),
                  ],
                ),
              ),
            )),
            // Линия между строками — только в высококонтрастной теме (1.8.0,
            // «воздушный» вид: строки разделяют поля, как в Ogneliss Dialer).
            if (OgnelissLook.of(context).outlined)
              Padding(
                padding: const EdgeInsets.only(left: Space.l + 48 + Space.m),
                child: Divider(height: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
              ),
          ],
        ),
      ),
    );
  }

  String _initial(EmailAddress addr) {
    final name = addr.displayName ?? addr.email;
    return name.isNotEmpty ? initialOf(name) : '?';
  }

  // Локале-зависимый штамп: сегодня — время, в этом году — день и месяц, иначе
  // дата. Форматы кэшируются внутри AppDateFormat (раньше локаль 'ru' и 24-часовое
  // время были зашиты — для en это неверно).
  String _formatTime(BuildContext context, DateTime dateUtc) =>
      AppDateFormat.listStamp(context, dateUtc);
}


/// Круг «На контроле» для письма нескольким адресатам: кольцо и сектор по
/// доле ответивших.
class ControlRingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;
  const ControlRingPainter({required this.fraction, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color);
    if (fraction > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 1.8), -1.5708, 6.28318 * fraction.clamp(0, 1), true,
          Paint()..color = color);
    } else {
      canvas.drawCircle(c, r - 1.8, Paint()..color = track.withValues(alpha: 0.5));
    }
  }

  @override
  bool shouldRepaint(ControlRingPainter old) => old.fraction != fraction || old.color != color;
}
