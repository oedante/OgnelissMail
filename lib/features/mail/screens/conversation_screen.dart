// lib/features/mail/screens/conversation_screen.dart
// Беседы как в OfficeMail (п. 6 проверки 05.10, фаза Ф2 UI_REDESIGN.md):
// строка беседы в списке → экран беседы (письма карточками, самое новое
// сверху) → письмо с листанием «2 / 8» и стрелками к соседним письмам.
//
// Оба экрана подписаны на БД: прочтение, удаление и новое письмо в беседе
// видны сразу, без перезагрузки.

import '../../../core/utils/text_safe.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import '../../contacts/widgets/person_card.dart';
import '../../../core/theme/app_icons.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_router.dart' show conversationMessagePath;
import '../../../core/theme/tokens.dart';
import '../../../core/theme/mail_page_color.dart';
import '../../../services/background/work_scheduler.dart';
import '../widgets/mail_html_view.dart' show MailHtmlView, MailWebViewPool;
import '../../../core/utils/app_date_format.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/mail/special_folders.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/email_actions_service.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/readable_width.dart';
import '../providers/mail_providers.dart';
import '../providers/mail_open_cache.dart';
import 'dart:async';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/screens/swipe_settings_screen.dart' show conversationSwipeActions;
import '../widgets/control_sheet.dart' show applyControl, ControlChoice;
import '../widgets/later_sheet.dart' show postponeEmails;
import 'mail_detail_screen.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/swipe_action_indicator.dart';
import '../widgets/mail_peek_card.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../widgets/common/quick_long_press.dart';
import '../../../widgets/common/peek_card.dart' show peekAnchorOf;
import '../widgets/peek_helpers.dart';
import '../widgets/quick_reply_bar.dart';
import '../providers/drawer_prefs.dart' show convChatOrderProvider, quickReplyBarProvider;
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../../services/notifications/account_notify_mode.dart' show ConversationNotify;
import '../providers/conversation_mute.dart';
import '../../../widgets/ui/app_menu_button.dart';
import 'package:intl/intl.dart' show DateFormat;

/// Письма беседы из БД, самое новое первым — строки без тел (1.5.9): раньше
/// каждое изменение таблицы писем (во время синхронизации — несколько раз в
/// секунду) перечитывало тексты всех писем длинной беседы. Изменения других
/// писем экран не перерисовывают. Превью, которого нет в строке (IMAP),
/// берётся из начала текста — один раз на письмо.
Stream<List<EmailModel>> _watchConversation(
    AppDatabase db, String conversationId, String accountId) {
  final previews = <String, String>{};
  final asked = <String>{};
  bool noPreview(Email r) => (r.bodyPreview ?? '').trim().isEmpty;
  return db
      .watchConversationLight(conversationId: conversationId, accountId: accountId)
      .distinct((a, b) => listEquals(a, b))
      .asyncMap((rows) async {
    final need = [
      for (final r in rows)
        if (noPreview(r) && asked.add(r.id)) r.id,
    ];
    if (need.isNotEmpty) {
      try {
        previews.addAll(await db.previewsFromBody(accountId, need));
      } catch (e) {
        AppLogger.debug('Беседа: превью из текста — $e');
      }
    }
    return [
      for (final r in rows)
        emailModelFromRow(noPreview(r) && previews[r.id] != null
            ? r.copyWith(bodyPreview: Value(previews[r.id]))
            : r),
    ];
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Экран беседы
// ─────────────────────────────────────────────────────────────────────────────

class ConversationScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String accountId;

  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.accountId,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  late final Stream<List<EmailModel>> _stream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stream = _watchConversation(
        ref.read(databaseProvider), widget.conversationId, widget.accountId);
  }

  void _open(EmailModel e) {
    HapticFeedback.selectionClick();
    if (e.isDraft || e.folderId == 'drafts') {
      context.push('/compose?draftId=${Uri.encodeQueryComponent(e.id)}'
          '&accountId=${Uri.encodeQueryComponent(e.accountId)}');
      return;
    }
    // Письмо готовится, пока экран выезжает (и картинки подписи — тоже).
    ref.read(mailOpenCacheProvider).prefetch(e.accountId, e.id, images: true);
    context.push(conversationMessagePath(widget.conversationId, e.id, accountId: e.accountId));
  }

  Future<void> _markAllRead(List<EmailModel> emails) async {
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null) return;
    final byFolder = <String, List<String>>{};
    for (final e in emails.where((e) => !e.isRead)) {
      (byFolder[e.folderId] ??= []).add(e.id);
    }
    if (byFolder.isEmpty) return;
    setState(() => _busy = true);
    try {
      final actions = ref.read(emailActionsProvider);
      for (final entry in byFolder.entries) {
        await actions.batchSetRead(account, entry.value, entry.key, true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll(List<EmailModel> emails, AppLocalizations l10n) async {
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null) return;
    final trashId = await ref
        .read(databaseProvider)
        .folderIdOfType(widget.accountId, FolderType.trash.index);
    if (trashId == null) {
      // Плашки скрыты (19.10) — строкой на экране.
      showInlineError(l10n.tr('trashFolderNotFound'));
      return;
    }
    final toMove = emails.where((e) => e.folderId != trashId).toList();
    if (toMove.isEmpty || !mounted) return;
    final ok = await confirmDestructive(context,
        title: l10n.tr('convDeleteTitle'),
        message: l10n.tr('convDeleteBody').replaceAll('{n}', '${toMove.length}'));
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final byFolder = <String, List<String>>{};
    for (final e in toMove) {
      (byFolder[e.folderId] ??= []).add(e.id);
    }
    try {
      final actions = ref.read(emailActionsProvider);
      for (final entry in byFolder.entries) {
        await actions.batchMove(account, entry.value, entry.key, trashId);
      }
      AppLogger.info('Беседа удалена (${toMove.length})');
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Свайпы и меню письма в беседе ──

  ActionPane? _pane(SwipeAction a, EmailModel e, AppLocalizations l10n, {required bool fromStart}) {
    if (a == SwipeAction.none || !conversationSwipeActions.contains(a)) return null;
    final settings = ref.read(settingsProvider);
    if (a == SwipeAction.control && !settings.mailControl) return null;
    final removes = a == SwipeAction.archive || a == SwipeAction.delete || a == SwipeAction.moveToJunk;
    final (icon, label, base) = _look(a, e, l10n);
    final tone = SwipeTone.of(context, base);
    return ActionPane(
      // Панель на месте, значок у края — виден с первых миллиметров (1.6.21).
      motion: const BehindMotion(),
      extentRatio: 0.28,
      dismissible: DismissiblePane(
        dismissThreshold: 0.4,
        closeOnCancel: true,
        confirmDismiss: removes
            ? null
            : () async {
                unawaited(_run(a, e, l10n));
                return false;
              },
        onDismissed: () => unawaited(_run(a, e, l10n)),
      ),
      children: [
        CustomSlidableAction(
          onPressed: (_) => unawaited(_run(a, e, l10n)),
          backgroundColor: tone.$1,
          foregroundColor: tone.$2,
          padding: EdgeInsets.zero,
          child: Semantics(
            label: label,
            button: true,
            child: ExcludeSemantics(
              child: SwipeActionIndicator(
                icon: icon,
                label: label,
                color: tone.$2,
                fromStart: fromStart,
                atEdge: true,
                extentRatio: 0.28,
                armAt: 0.4,
                animated: settings.swipeAnimated && !settings.reduceMotion,
              ),
            ),
          ),
        ),
      ],
    );
  }

  (IconData, String, Color) _look(SwipeAction a, EmailModel e, AppLocalizations l10n) => switch (a) {
        SwipeAction.markRead => (
            e.isRead ? AppIcons.mark_email_unread : AppIcons.mark_email_read,
            l10n.tr(e.isRead ? 'markUnread' : 'markRead'),
            AppColors.infoBlue
          ),
        SwipeAction.flag => (AppIcons.flag, l10n.tr('flag'), AppColors.warningYellow),
        SwipeAction.archive => (AppIcons.archive, l10n.tr('archive'), AppColors.primaryBlue),
        SwipeAction.delete => (AppIcons.delete, l10n.delete, AppColors.errorRed),
        SwipeAction.moveToJunk => (AppIcons.block, l10n.tr('moveToJunk'), AppColors.accentOrange),
        SwipeAction.snooze => (AppIcons.watch_later, l10n.tr('later'), AppColors.accentOrange),
        SwipeAction.control => (AppIcons.task_alt, l10n.tr(e.controlState == 0 ? 'controlSet' : 'controlClear'), AppColors.successGreen),
        SwipeAction.reply => (AppIcons.reply, l10n.tr('reply'), AppColors.primaryBlue),
        SwipeAction.forward => (AppIcons.forward, l10n.tr('forward'), AppColors.primaryBlue),
        _ => (AppIcons.more_horiz, '', AppColors.infoBlue),
      };

  Future<void> _run(SwipeAction a, EmailModel e, AppLocalizations l10n) async {
    final account = ref.read(accountsProvider).where((x) => x.id == e.accountId).firstOrNull;
    if (account == null) return;
    final actions = ref.read(emailActionsProvider);
    final db = ref.read(databaseProvider);
    unawaited(HapticFeedback.selectionClick());
    try {
      switch (a) {
        case SwipeAction.markRead:
          await actions.setRead(account, e.id, e.folderId, !e.isRead);
        case SwipeAction.flag:
          await actions.setFlag(account, e.id, e.folderId, !e.isFlagged);
        // «Архив» и «Спам» — с распознаванием по названию (SpecialFolders,
        // 1.7.2+106); нет папки — строкой с подсказкой, а не молча.
        case SwipeAction.archive:
          final to = await SpecialFolders.resolve(db, ref.read(sharedPrefsProvider), e.accountId, SpecialKind.archive);
          if (to == null) showInlineError(l10n.tr('archiveFolderNotFound'));
          if (to != null && to != e.folderId) await actions.moveTo(account, e.id, e.folderId, to);
        case SwipeAction.moveToJunk:
          final junk = await SpecialFolders.resolve(db, ref.read(sharedPrefsProvider), e.accountId, SpecialKind.junk);
          if (junk == null) showInlineError(l10n.tr('junkFolderNotFound'));
          if (junk != null && junk != e.folderId) await actions.moveTo(account, e.id, e.folderId, junk);
        case SwipeAction.delete:
          await actions.delete(account, e.id, e.folderId);
        case SwipeAction.snooze:
          if (mounted) await postponeEmails(context, ref, [e]);
        case SwipeAction.control:
          await applyControl(ref, e, ControlChoice(clear: e.controlState != 0));
        case SwipeAction.reply:
          if (mounted) {
            unawaited(context.push('/compose?replyToId=${Uri.encodeQueryComponent(e.id)}'
                '&accountId=${Uri.encodeQueryComponent(e.accountId)}'));
          }
        case SwipeAction.forward:
          if (mounted) {
            unawaited(context.push('/compose?forwardFromId=${Uri.encodeQueryComponent(e.id)}'
                '&accountId=${Uri.encodeQueryComponent(e.accountId)}'));
          }
        default:
          break;
      }
    } catch (err) {
      AppLogger.warning('Беседа — действие ${a.name}: $err');
    }
  }

  /// Карточка письма по удержанию (как в ленте, 1.6.30): Ответить всем
  /// (или «Ответить», 1.6.46), Переслать, Прочитано, На контроль (или флаг),
  /// Ещё…; касание карточки — открыть письмо.
  void _peek(BuildContext cardCtx, EmailModel e, AppLocalizations l10n) {
    unawaited(HapticFeedback.mediumImpact());
    final anchor = peekAnchorOf(cardCtx);
    final control = ref.read(settingsProvider).mailControl;
    final own = {for (final a in ref.read(accountsProvider)) ...OwnAddresses.of(a)};
    final all = peekWantsReplyAll(e, own);
    final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    final invite = peekCanRespondInvite(account, e);
    unawaited(showMailPeek(
      context,
      email: e,
      anchor: anchor,
      previewLines: ref.read(settingsProvider).peekPreviewLines,
      onOpen: () => _open(e),
      fetchFile: (a) => peekFetchFile(ref, account, e, a, l10n),
      openFile: (a, path) => peekOpenFile(context, e, a, path),
      actions: [
        // Приглашение (1.6.47): ответ прямо из карточки.
        if (invite && account != null) ...peekInviteActions(context, ref, account, e, l10n),
        PeekAction(
          icon: all ? AppIcons.reply_all : AppIcons.reply,
          label: l10n.tr(all ? 'replyAll' : 'reply'),
          onTap: () => context.push('/compose?replyToId=${Uri.encodeQueryComponent(e.id)}'
              '&accountId=${Uri.encodeQueryComponent(e.accountId)}${all ? '&replyAll=true' : ''}'),
        ),
        if (!invite) ...[
          PeekAction(
            icon: AppIcons.forward,
            label: l10n.tr('forward'),
            onTap: () => unawaited(_run(SwipeAction.forward, e, l10n)),
          ),
          PeekAction(
            icon: e.isRead ? AppIcons.mark_email_unread : AppIcons.mark_email_read,
            label: l10n.tr(e.isRead ? 'peekUnread' : 'peekRead'),
            onTap: () => unawaited(_run(SwipeAction.markRead, e, l10n)),
          ),
          if (control)
            PeekAction(
              icon: AppIcons.task_alt,
              filled: e.controlState != 0,
              // На контроле — кнопка снимает (1.7.2: подпись не менялась).
              label: l10n.tr(e.controlState == 0 ? 'peekControl' : 'peekControlOff'),
              onTap: () => unawaited(_run(SwipeAction.control, e, l10n)),
            )
          else
            PeekAction(
              icon: AppIcons.flag,
              filled: e.isFlagged,
              label: l10n.tr('flag'),
              onTap: () => unawaited(_run(SwipeAction.flag, e, l10n)),
            ),
        ],
      ],
      // «Ещё» — все действия по группам здесь же (1.6.49+95), вместо шторки.
      moreLabel: l10n.tr('peekMore'),
      more: _moreGroups(e, l10n),
    ));
  }

  /// Все действия с письмом беседы по группам.
  List<PeekGroup> _moreGroups(EmailModel e, AppLocalizations l10n) {
    final control = ref.read(settingsProvider).mailControl;
    PeekAction act(SwipeAction a) {
      final (icon, label, _) = _look(a, e, l10n);
      return PeekAction(
        icon: icon,
        label: label,
        filled: (a == SwipeAction.flag && e.isFlagged) || (a == SwipeAction.control && e.controlState != 0),
        color: a == SwipeAction.delete ? AppColors.errorText(context) : null,
        onTap: () => unawaited(_run(a, e, l10n)),
      );
    }

    return [
      PeekGroup(title: l10n.tr('peekGroupReply'), items: [
        act(SwipeAction.reply),
        PeekAction(
          icon: AppIcons.reply_all,
          label: l10n.tr('replyAll'),
          onTap: () => context.push('/compose?replyToId=${Uri.encodeQueryComponent(e.id)}'
              '&accountId=${Uri.encodeQueryComponent(e.accountId)}&replyAll=true'),
        ),
        act(SwipeAction.forward),
      ]),
      PeekGroup(title: l10n.tr('peekGroupMark'), items: [
        act(SwipeAction.markRead),
        act(SwipeAction.flag),
        act(SwipeAction.snooze),
        if (control) act(SwipeAction.control),
      ]),
      PeekGroup(title: l10n.tr('peekGroupMove'), items: [
        act(SwipeAction.archive),
        act(SwipeAction.moveToJunk),
        act(SwipeAction.delete),
      ]),
    ];
  }

  /// «Без уведомлений» / «Включить уведомления» (1.8.13): новые письма
  /// беседы — молча, строкой вверху — что сделано.
  Future<void> _toggleMute(AppLocalizations l10n) async {
    unawaited(HapticFeedback.selectionClick());
    final muted = await ref.read(mutedConversationsProvider.notifier).toggle(widget.accountId, widget.conversationId);
    if (mounted) showInlineNotice(l10n.tr(muted ? 'convMutedNotice' : 'convUnmutedNotice'));
  }

  /// Подпись дня между письмами (1.6.49, как в Telegram): «Сегодня»,
  /// «Вчера», «17 октября».
  String _dayLabel(DateTime d, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return l10n.tr('today');
    if (day == today.subtract(const Duration(days: 1))) return l10n.tr('yesterday');
    return DateFormat(day.year == today.year ? 'd MMMM' : 'd MMMM y', l10n.localeCode).format(day);
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Письмо, на которое отвечает строка внизу: самое новое, не черновик.
  EmailModel? _replyTarget(List<EmailModel> emails) =>
      emails.where((e) => !e.isDraft && e.folderId != 'drafts').firstOrNull;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chat = ref.watch(convChatOrderProvider);
    final quickReply = ref.watch(quickReplyBarProvider);
    return StreamBuilder<List<EmailModel>>(
      stream: _stream,
      builder: (context, snap) {
        final emails = snap.data;
        final subject = (emails != null && emails.isNotEmpty) ? emails.first.subject : '';
        final target = emails == null ? null : _replyTarget(emails);
        final hasUnread = emails != null && emails.any((e) => !e.isRead);
        final own = {
          for (final a in ref.watch(accountsProvider)) ...OwnAddresses.of(a),
        };
        final settings = ref.watch(settingsProvider);
        final muted = ref.watch(mutedConversationsProvider
            .select((m) => m.contains(ConversationNotify.key(widget.accountId, widget.conversationId))));

        // Письмо [i] (самое новое — 0) карточкой; над ним — подпись дня,
        // если день сменился (в порядке показа).
        Widget messageAt(int i) {
          final list = emails!;
          final e = list[i];
          final mine = own.contains(e.from.email.trim().toLowerCase());
          // Над письмом в показе: в «чате» — более старое (i + 1), иначе —
          // более новое (i - 1).
          final neighbour = chat ? (i + 1 < list.length ? list[i + 1] : null) : (i > 0 ? list[i - 1] : null);
          final newDay = neighbour == null || !_sameDay(neighbour.receivedAt, e.receivedAt);
          // Свайпы в беседе — свой набор (Настройки → Свайпы → «В беседе»),
          // удержание — карточка с действиями.
          final card = Slidable(
            key: ValueKey('conv_${e.accountId}_${e.id}'),
            startActionPane: _pane(settings.swipeConvLeft, e, l10n, fromStart: true),
            endActionPane: _pane(settings.swipeConvRight, e, l10n, fromStart: false),
            // Касание — письмо читается из базы заранее (тело готовится при
            // нажатии).
            child: Listener(
              onPointerDown: (_) => ref.read(mailOpenCacheProvider).prefetch(e.accountId, e.id, body: false),
              child: Builder(
                builder: (cardCtx) => _MessageCard(
                  email: e,
                  mine: mine,
                  onTap: () => _open(e),
                  // Карточка письма с быстрыми действиями, как в ленте
                  // (1.6.30); полный список — «Ещё…».
                  onLongPress: () => _peek(cardCtx, e, l10n),
                ),
              ),
            ),
          );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (newDay) _DayChip(label: _dayLabel(e.receivedAt.toLocal(), l10n)),
            // Свои — правее, чужие — левее (1.6.49, как пузыри в чате).
            Padding(
              padding: mine ? const EdgeInsets.only(left: Space.xl) : const EdgeInsets.only(right: Space.xl),
              child: card,
            ),
          ]);
        }

        final header = Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.s),
          child: Text(
            l10n.tr('convCount').replaceAll('{n}', '${emails?.length ?? 0}'),
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );

        return Scaffold(
          // Светлая тема — белый фон, карточки писем на нём различимы (1.6.25).
          backgroundColor: theme.brightness == Brightness.dark ? null : AppColors.listFill(context),
          appBar: TextScaleCapBar(child: AppBar(
            title: Text(
              subject.isEmpty ? l10n.tr('noSubject') : subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            // «Прочитать все» и «Удалить беседу» — вверху (1.6.49): внизу —
            // строка ответа, как в мессенджере.
            actions: [
              // Беседа без уведомлений (1.8.13) — значок на виду, как у
              // чата «без звука» в Telegram; нажатие включает уведомления.
              if (muted)
                IconButton(
                  tooltip: l10n.tr('convUnmute'),
                  icon: Icon(AppIcons.notifications_off, color: theme.colorScheme.onSurfaceVariant),
                  onPressed: () => unawaited(_toggleMute(l10n)),
                ),
              if (hasUnread)
                IconButton(
                  tooltip: l10n.tr('markAllRead'),
                  icon: const Icon(AppIcons.mark_email_read),
                  onPressed: _busy ? null : () => _markAllRead(emails),
                ),
              if (emails != null && emails.isNotEmpty)
                AppMenuButton<String>(
                  tooltip: l10n.tr('more'),
                  onSelected: (v) {
                    switch (v) {
                      case 'order':
                        unawaited(ref.read(convChatOrderProvider.notifier).set(!chat));
                      case 'mute':
                        unawaited(_toggleMute(l10n));
                      case 'delete':
                        if (!_busy) unawaited(_deleteAll(emails, l10n));
                    }
                  },
                  itemBuilder: (_) => [
                    AppMenuEntry(value: 'order', icon: AppIcons.forum, label: l10n.tr('convChatOrder'), checked: chat),
                    AppMenuEntry(
                      value: 'mute',
                      icon: muted ? AppIcons.notifications_active : AppIcons.notifications_off,
                      label: l10n.tr(muted ? 'convUnmute' : 'convMute'),
                    ),
                    AppMenuEntry(value: 'delete', icon: AppIcons.delete, label: l10n.tr('convDelete'), destructive: true),
                  ],
                ),
            ],
            // Высота заголовка постоянная: полоска не сдвигает ленту.
            bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: SizedBox(height: 2, child: _busy ? const LinearProgressIndicator(minHeight: 2) : null)),
          )),
          body: emails == null
              ? const Center(child: CircularProgressIndicator())
              : emails.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xxl),
                        child: Text(l10n.tr('convEmpty'), textAlign: TextAlign.center),
                      ),
                    )
                  : ReadableWidth(
                      child: ListView.separated(
                        // «Как чат» — снизу вверх: экран открывается на
                        // последнем письме, новое появляется у строки ответа.
                        reverse: chat,
                        // Шире: меньше полей по краям (замечание 07.10.2026).
                        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.xl),
                        itemCount: emails.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: Space.xs),
                        itemBuilder: (context, i) {
                          // Счётчик писем — вверху экрана в обоих порядках.
                          if (chat) return i == emails.length ? header : messageAt(i);
                          return i == 0 ? header : messageAt(i - 1);
                        },
                      ),
                    ),
          // Строка ответа на последнее письмо (1.6.49, как в мессенджере);
          // поднимается над клавиатурой.
          bottomNavigationBar: (target == null || !quickReply)
              ? null
              : Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                  child: Material(
                    color: theme.colorScheme.surface,
                    // Плавающая карточка (1.7.3) — отступы у неё свои.
                    child: SafeArea(
                      top: false,
                      child: QuickReplyBar(key: ValueKey('qr_conv_${target.accountId}_${target.id}'), email: target),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Подпись дня посередине, как в Telegram.
class _DayChip extends StatelessWidget {
  final String label;
  const _DayChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.s, bottom: Space.s),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: Radii.chipAll,
          ),
          child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

/// Карточка письма в беседе: аватар, отправитель, время, три строки текста,
/// метка папки (в беседе бывают письма из «Входящих» и «Отправленных»).
/// Свои письма — фото справа и с лёгким оттенком, входящие — фото слева:
/// так в беседе сразу видно, кто кому писал.
class _MessageCard extends StatelessWidget {
  final EmailModel email;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _MessageCard({required this.email, required this.mine, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !email.isRead;
    final name = email.from.label;
    final preview = email.preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Фото — в серой рамке (её рисует HeroEmailAvatar для всех портретов).
    // Нажатие на аватар — карточка отправителя (должность, отдел, телефоны).
    final avatar = GestureDetector(
      onTap: () => showPersonCard(context,
          email: email.from.email, name: email.from.displayName, accountId: email.accountId),
      child: HeroEmailAvatar(
        emailId: '${email.accountId}/${email.id}',
        initial: name.isNotEmpty ? initialOf(name) : '?',
        color: HeroEmailAvatar.colorForEmail(email.from.email),
        email: email.from.email,
        radius: Sizes.avatar / 2,
        hero: false,
      ),
    );
    // Карточки — на белом фоне беседы (1.6.25): прежде фон экрана совпадал
    // с цветом чужого письма, и письма сливались. Своё письмо — с голубым
    // оттенком, непрочитанное — на ступень темнее.
    final dark = theme.brightness == Brightness.dark;
    final base = unread
        ? scheme.surfaceContainerHigh
        : (dark ? scheme.surfaceContainer : scheme.surfaceContainerLow);
    return Material(
      color: mine ? Color.alphaBlend(scheme.primary.withValues(alpha: dark ? 0.08 : 0.07), base) : base,
      borderRadius: Radii.cardAll,
      clipBehavior: Clip.antiAlias,
      // Удержание — 250 мс (1.6.46), палец можно довести до кнопки карточки.
      child: QuickLongPress(
        onLongPress: onLongPress,
        tracker: HoldPointer.instance,
        pressEffect: true,
        child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
            children: [
              avatar,
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (unread)
                          Container(
                            width: Space.s,
                            height: Space.s,
                            margin: const EdgeInsets.only(right: Space.xs + 2),
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          ),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (email.hasAttachments)
                          Padding(
                            padding: const EdgeInsets.only(left: Space.xs),
                            child: Icon(AppIcons.attach_file, size: Sizes.iconInline,
                                color: scheme.onSurfaceVariant),
                          ),
                        if (email.isFlagged)
                          Padding(
                            padding: const EdgeInsets.only(left: Space.xs),
                            child: Icon(AppIcons.flag, size: Sizes.iconInline, fill: 1, color: scheme.error),
                          ),
                        const SizedBox(width: Space.s),
                        Text(
                          AppDateFormat.listStamp(context, email.receivedAt),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    if ((email.folderName ?? '').isNotEmpty) ...[
                      const SizedBox(height: Space.s),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: Radii.chipAll,
                        ),
                        child: Text(
                          email.folderName!.toUpperCase() == 'INBOX'
                              ? AppLocalizations.of(context).tr('inbox')
                              : email.folderName!,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Письмо беседы с листанием «i / N»
// ─────────────────────────────────────────────────────────────────────────────

class ConversationPagerScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String emailId;
  final String accountId;

  const ConversationPagerScreen({
    super.key,
    required this.conversationId,
    required this.emailId,
    required this.accountId,
  });

  @override
  ConsumerState<ConversationPagerScreen> createState() => _ConversationPagerScreenState();
}

class _ConversationPagerScreenState extends ConsumerState<ConversationPagerScreen> {
  /// Только id писем беседы, и только когда их набор меняется: раньше каждое
  /// изменение таблицы писем перестраивало открытое письмо.
  late final Stream<List<String>> _stream;
  PageController? _controller;

  /// Порядок писем фиксируется при открытии: если во время чтения придёт
  /// новое письмо или текущее отметится прочитанным, страница не прыгает.
  List<String>? _ids;

  /// Страница, на которой листание остановилось: её письмо получает тело
  /// (встроенное окно браузера) и отметку «прочитано». Окно соседней
  /// страницы, созданное на ходу, давало рывок листания.
  int? _settledPage;

  void _onScrollEnd() {
    final c = _controller;
    final ids = _ids;
    if (c == null || ids == null || !c.hasClients) return;
    var p = (c.page ?? c.initialPage.toDouble()).round();
    if (p < 0) p = 0;
    if (p > ids.length - 1) p = ids.length - 1;
    if (p != _settledPage) setState(() => _settledPage = p);
    _prefetchAround(p);
  }

  /// Соседние письма — заранее: при листании шапка и текст уже готовы.
  void _prefetchAround(int p) {
    final ids = _ids;
    if (ids == null) return;
    final cache = ref.read(mailOpenCacheProvider);
    for (final i in [p - 1, p + 1]) {
      if (i >= 0 && i < ids.length) cache.prefetch(widget.accountId, ids[i]);
    }
    // Окно браузера заранее — для следующего (более раннего) письма беседы,
    // на последней странице — для предыдущего (1.5.9). В простое: запасное
    // окно забирает открытое письмо, новое создаётся после паузы открытия;
    // в той же очереди за ним — загрузка соседнего письма.
    final next = p + 1 < ids.length ? p + 1 : p - 1;
    if (next < 0 || next >= ids.length || !mounted) return;
    final theme = Theme.of(context);
    final width = MailHtmlView.bodyWidthOf(context);
    final dark = theme.brightness == Brightness.dark;
    final page = mailPageColor(theme);
    final scale = ref.read(settingsProvider).fontScale;
    final id = ids[next];
    unawaited(WorkScheduler.instance.run(WorkPriority.idle, () async {
      // Окна может ещё не быть (его забрало открытое письмо) — создать.
      await MailWebViewPool.ensureSpare(width: width, textScale: scale);
      cache.preloadWebView(widget.accountId, id, width: width, dark: dark, pageColor: page, textScale: scale);
    }));
  }

  @override
  void initState() {
    super.initState();
    _stream = ref
        .read(databaseProvider)
        .watchConversationLight(conversationId: widget.conversationId, accountId: widget.accountId)
        .map((rows) => [for (final r in rows) r.id])
        .distinct((a, b) => listEquals(a, b));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _go(int page) {
    _controller?.animateToPage(page,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<String>>(
      stream: _stream,
      builder: (context, snap) {
        final fresh = snap.data;
        if (fresh == null) {
          return Scaffold(appBar: TextScaleCapBar(child: AppBar()), body: const Center(child: CircularProgressIndicator()));
        }
        // Удалённые из беседы письма убираем, новые добавляем в конец —
        // так текущая страница остаётся на месте.
        final present = fresh.toSet();
        final known = _ids?.toSet();
        final ids = known == null
            ? fresh
            : [
                ..._ids!.where(present.contains),
                ...fresh.where((id) => !known.contains(id)),
              ];
        _ids = ids;
        if (ids.isEmpty) {
          return Scaffold(
            appBar: TextScaleCapBar(child: AppBar()),
            body: Center(child: Text(l10n.tr('convEmpty'))),
          );
        }
        if (_controller == null) {
          final start = ids.indexOf(widget.emailId);
          _controller = PageController(initialPage: start < 0 ? 0 : start);
          _settledPage = start < 0 ? 0 : start;
          final first = _settledPage!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _prefetchAround(first);
          });
        }
        final n = ids.length;
        var settled = _settledPage ?? 0;
        if (settled > n - 1) settled = n - 1;
        return NotificationListener<ScrollEndNotification>(
          // Только листание страниц (прокрутка письма внутри — глубже).
          onNotification: (note) {
            if (note.depth == 0) _onScrollEnd();
            return false;
          },
          child: PageView.builder(
            controller: _controller,
            itemCount: n,
            itemBuilder: (context, i) => MailDetailScreen(
              key: ValueKey(ids[i]),
              emailId: ids[i],
              accountId: widget.accountId,
              pagerLabel: '${i + 1} / $n',
              onPrev: i > 0 ? () => _go(i - 1) : null,
              onNext: i < n - 1 ? () => _go(i + 1) : null,
              active: i == settled,
            ),
          ),
        );
      },
    );
  }
}
