// lib/features/mail/screens/triage_screen.dart
// «Разобрать непрочитанные» — непрочитанные письма по одному (план, раздел
// «На развитие», сделано 10.10.2026; 11.10 — переименовано: письма не только
// из «Входящих», а из всех папок, кроме удалённых, спама, отправленных,
// черновиков и исходящих).
//
// Одна карточка на экране: от кого, тема, начало текста, вложения. Под ней —
// шесть действий: В архив · Удалить · Прочитано · Позже · На контроль ·
// Пропустить; на карточке — «Открыть» и «Ответить». Свайпы — как в ленте
// (первые действия вправо и влево) или свой набор в «Настройки → Свайпы».
// Сверху — сколько разобрано из скольких. В конце — итог: сколько в
// архиве, удалено, отложено, на контроле.
//
// Область — как у ленты: текущий ящик, группа или «Все ящики». Письма —
// из базы телефона (свежие сверху, до 300); действия — те же, что в ленте,
// с выгрузкой на сервер через очередь. Открывается из «Избранного» бокового
// меню — пункт включается в настройке избранного (по умолчанию скрыт).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_router.dart' show pushMailDetail;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/text_safe.dart' show initialOf;
import '../../../data/database/app_database.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart' show FolderType;
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/email_actions_service.dart';
import '../../../services/mail/special_folders.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../settings/providers/account_groups_provider.dart' show activeGroupAccountIdsProvider;
import '../../settings/providers/settings_provider.dart' show settingsProvider, SwipeAction;
import '../providers/mail_providers.dart';
import '../widgets/control_sheet.dart';
import '../widgets/later_sheet.dart';

enum _Act { archive, delete, read, later, control, skip, flag }

class TriageScreen extends ConsumerStatefulWidget {
  const TriageScreen({super.key});

  @override
  ConsumerState<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends ConsumerState<TriageScreen> {
  List<EmailModel> _queue = const [];
  int _index = 0;
  bool _loading = true;
  bool _busy = false;
  final Map<_Act, int> _done = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Ящики области — как у ленты: «Все ящики», группа или текущий.
  List<String> _scope() {
    final accounts = ref.read(accountsProvider).where((a) => a.isActive).toList();
    if (ref.read(allAccountsModeProvider)) return [for (final a in accounts) a.id];
    final group = ref.read(activeGroupAccountIdsProvider);
    if (group.isNotEmpty) return [for (final a in accounts) if (group.contains(a.id)) a.id];
    final active = ref.read(activeAccountProvider);
    return active == null ? const [] : [active.id];
  }

  Future<void> _load() async {
    final ids = _scope();
    final db = ref.read(databaseProvider);
    var rows = <Email>[];
    if (ids.isNotEmpty) {
      // Все папки с почтой, кроме «Удалённых», «Спама», «Отправленных»,
      // «Черновиков» и «Исходящих»: непрочитанные бывают и в папках, куда их
      // разложили правила (11.10.2026 — «Разобрать непрочитанные»).
      final skip = [
        FolderType.trash.index, FolderType.junk.index, FolderType.sent.index,
        FolderType.drafts.index, FolderType.outbox.index,
      ];
      final inbox = await (db.selectOnly(db.folders)
            ..addColumns([db.folders.id])
            ..where(db.folders.accountId.isIn(ids) & db.folders.type.isNotIn(skip)))
          .map((r) => r.read(db.folders.id)!)
          .get();
      if (inbox.isNotEmpty) {
        rows = await (db.select(db.emails)
              ..where((e) => e.accountId.isIn(ids) & e.folderId.isIn(inbox) & e.isRead.equals(false))
              ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
              ..limit(300))
            .get();
      }
    }
    if (!mounted) return;
    setState(() {
      _queue = [for (final r in rows) emailModelFromRow(r)];
      _index = 0;
      _loading = false;
    });
  }

  EmailModel? get _current => _index < _queue.length ? _queue[_index] : null;

  void _next(_Act act) {
    setState(() {
      _done[act] = (_done[act] ?? 0) + 1;
      _index++;
    });
  }

  Future<void> _act(_Act act) async {
    final email = _current;
    if (email == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    final actions = ref.read(emailActionsProvider);
    final list = ref.read(emailsProvider.notifier);
    setState(() => _busy = true);
    try {
      switch (act) {
        case _Act.archive:
          final archiveId = await SpecialFolders.resolve(
              ref.read(databaseProvider), ref.read(sharedPrefsProvider), email.accountId, SpecialKind.archive);
          if (archiveId == null) {
            showInlineError(l10n.tr('archiveFolderNotFound'));
            return;
          }
          unawaited(HapticFeedback.selectionClick());
          list.hideLocally(email);
          await actions.setRead(account, email.id, email.folderId, true);
          await actions.moveTo(account, email.id, email.folderId, archiveId);
        case _Act.delete:
          unawaited(HapticFeedback.selectionClick());
          list.hideLocally(email);
          await actions.delete(account, email.id, email.folderId);
        case _Act.read:
          list.applyLocalFlags(email.id, isRead: true);
          await actions.setRead(account, email.id, email.folderId, true);
        case _Act.later:
          final choice = await showLaterSheet(context, current: email);
          if (choice == null || !mounted) return;
          await applyLater(ref, [email], choice);
        case _Act.control:
          final c = await showControlSheet(context, ref, email);
          if (c == null || !mounted) return;
          await applyControl(ref, email, c);
          // На контроле — значит, прочитано и в работе.
          list.applyLocalFlags(email.id, isRead: true);
          await actions.setRead(account, email.id, email.folderId, true);
        case _Act.flag:
          list.applyLocalFlags(email.id, isFlagged: true, isRead: true);
          await actions.setFlag(account, email.id, email.folderId, true);
          await actions.setRead(account, email.id, email.folderId, true);
        case _Act.skip:
          break;
      }
      if (mounted) _next(act);
    } catch (e) {
      showInlineError('${l10n.tr('error')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(EmailModel e) async {
    await pushMailDetail(GoRouter.of(context), e.id, accountId: e.accountId);
    if (!mounted) return;
    // Открыли — письмо прочитано; в разборе — следующее.
    _next(_Act.read);
  }

  Future<void> _reply(EmailModel e) async {
    await context.push('/compose?replyToId=${Uri.encodeQueryComponent(e.id)}'
        '&accountId=${Uri.encodeQueryComponent(e.accountId)}');
    if (!mounted) return;
    final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    if (account != null) {
      ref.read(emailsProvider.notifier).applyLocalFlags(e.id, isRead: true);
      unawaited(ref.read(emailActionsProvider).setRead(account, e.id, e.folderId, true));
    }
    _next(_Act.read);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = _queue.length;
    final current = _current;
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.tr('triageTitle')),
          if (!_loading && total > 0)
            Text(
              l10n.tr('triageProgress')
                  .replaceAll('{n}', '${(_index + 1).clamp(1, total)}')
                  .replaceAll('{total}', '$total'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
            ),
        ]),
        bottom: _loading || total == 0
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : _index / total,
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : current == null
              ? _summary(context, l10n, total)
              : SafeArea(
                  top: false,
                  child: Column(children: [
                    Expanded(child: _card(context, l10n, current)),
                    _actions(context, l10n),
                  ]),
                ),
    );
  }

  Widget _card(BuildContext context, AppLocalizations l10n, EmailModel e) {
    final theme = Theme.of(context);
    final text = (e.bodyPlain ?? e.bodyPreview ?? '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    final shown = text.length > 1500 ? '${text.substring(0, 1500)}…' : text;
    final files = e.attachments.where((a) => !a.isInline).length;
    final now = DateTime.now();
    final r = e.receivedAt.toLocal();
    final when = DateUtils.isSameDay(r, now)
        ? DateFormat('HH:mm').format(r)
        : DateFormat('d MMM, HH:mm', l10n.localeCode).format(r);
    // Свайпы — как в ленте (первые действия) или свой набор: «Настройки →
    // Свайпы → Разобрать входящие».
    final (right, left) = ref.watch(settingsProvider.select((s) => s.triageSwipes));
    final dir = right != SwipeAction.none && left != SwipeAction.none
        ? DismissDirection.horizontal
        : right != SwipeAction.none
            ? DismissDirection.startToEnd
            : left != SwipeAction.none
                ? DismissDirection.endToStart
                : DismissDirection.none;
    Widget bg(SwipeAction a, Alignment align) {
      final danger = a == SwipeAction.delete;
      return _swipeBg(context, _swipeIcon(a), _swipeLabel(a, l10n), align,
          danger ? theme.colorScheme.errorContainer : theme.colorScheme.primaryContainer,
          danger ? theme.colorScheme.onErrorContainer : theme.colorScheme.onPrimaryContainer);
    }
    return Dismissible(
      key: ValueKey('triage_${e.accountId}_${e.id}'),
      direction: dir,
      background: bg(right == SwipeAction.none ? left : right, Alignment.centerLeft),
      secondaryBackground: bg(left == SwipeAction.none ? right : left, Alignment.centerRight),
      confirmDismiss: (d) async {
        await _swipe(d == DismissDirection.startToEnd ? right : left, e);
        return false; // карточку меняет _next, а не Dismissible
      },
      child: Card(
        margin: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
        elevation: 0,
        color: AppColors.cardFill(context),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardAll,
          side: AppColors.cardSide(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              HeroEmailAvatar(
                emailId: 'triage_${e.id}',
                hero: false,
                radius: 22,
                email: e.from.email,
                initial: e.from.label.isEmpty ? '?' : initialOf(e.from.label),
                color: HeroEmailAvatar.colorForEmail(e.from.email),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.from.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(when, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                ]),
              ),
            ]),
            const SizedBox(height: Space.m),
            Text(e.subject.trim().isEmpty ? l10n.tr('noSubject') : e.subject.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (files > 0) ...[
              const SizedBox(height: Space.s),
              Row(children: [
                Icon(AppIcons.attach_file, size: Sizes.iconRow, color: AppColors.mutedText(context)),
                const SizedBox(width: Space.xs),
                Text(l10n.tr('triageFiles').replaceAll('{n}', '$files'),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
              ]),
            ],
            const Divider(height: Space.xl),
            Expanded(
              child: SingleChildScrollView(
                child: Text(shown.isEmpty ? l10n.tr('triageNoText') : shown,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      color: shown.isEmpty ? AppColors.mutedText(context) : null,
                    )),
              ),
            ),
            const SizedBox(height: Space.s),
            Row(children: [
              TextButton.icon(
                icon: const Icon(AppIcons.open_in_new, size: Sizes.iconRow),
                label: Text(l10n.tr('triageOpen')),
                onPressed: _busy ? null : () => _open(e),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(AppIcons.reply, size: Sizes.iconRow),
                label: Text(l10n.tr('reply')),
                onPressed: _busy ? null : () => _reply(e),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _swipe(SwipeAction a, EmailModel e) async {
    switch (a) {
      case SwipeAction.archive:
        await _act(_Act.archive);
      case SwipeAction.delete:
        await _act(_Act.delete);
      case SwipeAction.markRead:
        await _act(_Act.read);
      case SwipeAction.snooze:
        await _act(_Act.later);
      case SwipeAction.control:
        await _act(_Act.control);
      case SwipeAction.flag:
        await _act(_Act.flag);
      case SwipeAction.reply:
        await _reply(e);
      default:
        // Действия ленты, которых нет в разборе (переместить, спам…), —
        // как «пропустить»: письмо остаётся, показывается следующее.
        await _act(_Act.skip);
    }
  }

  static IconData _swipeIcon(SwipeAction a) => switch (a) {
        SwipeAction.archive => AppIcons.archive,
        SwipeAction.delete => AppIcons.delete,
        SwipeAction.markRead => AppIcons.mark_email_read,
        SwipeAction.snooze => AppIcons.watch_later,
        SwipeAction.control => AppIcons.bookmark,
        SwipeAction.flag => AppIcons.flag,
        SwipeAction.reply => AppIcons.reply,
        _ => AppIcons.skip_next,
      };

  static String _swipeLabel(SwipeAction a, AppLocalizations l10n) => switch (a) {
        SwipeAction.archive => l10n.tr('archive'),
        SwipeAction.delete => l10n.delete,
        SwipeAction.markRead => l10n.tr('triageRead'),
        SwipeAction.snooze => l10n.tr('later'),
        SwipeAction.control => l10n.tr('triageControl'),
        SwipeAction.flag => l10n.tr('flag'),
        SwipeAction.reply => l10n.tr('reply'),
        _ => l10n.tr('triageSkip'),
      };

  Widget _swipeBg(BuildContext context, IconData icon, String label, Alignment align, Color bg, Color fg) =>
      Container(
        margin: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
        decoration: BoxDecoration(color: bg, borderRadius: Radii.cardAll),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        alignment: align,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: fg),
          const SizedBox(height: Space.xs),
          Text(label, style: TextStyle(color: fg)),
        ]),
      );

  /// Шесть действий сеткой 3 × 2 — одного размера, под большим пальцем.
  Widget _actions(BuildContext context, AppLocalizations l10n) {
    Widget b(_Act a, IconData icon, String label, {Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(Space.xs),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.s),
                foregroundColor: color,
                shape: const RoundedRectangleBorder(borderRadius: Radii.cardAll),
              ),
              onPressed: _busy ? null : () => _act(a),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: Sizes.icon),
                const SizedBox(height: 2),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          b(_Act.archive, AppIcons.archive, l10n.tr('archive')),
          b(_Act.delete, AppIcons.delete, l10n.delete, color: AppColors.errorText(context)),
          b(_Act.read, AppIcons.mark_email_read, l10n.tr('triageRead')),
        ]),
        Row(children: [
          b(_Act.later, AppIcons.watch_later, l10n.tr('later')),
          b(_Act.control, AppIcons.bookmark, l10n.tr('triageControl')),
          b(_Act.skip, AppIcons.skip_next, l10n.tr('triageSkip')),
        ]),
      ]),
    );
  }

  Widget _summary(BuildContext context, AppLocalizations l10n, int total) {
    final parts = <String>[
      if ((_done[_Act.archive] ?? 0) > 0) '${l10n.tr('triageSumArchive')} ${_done[_Act.archive]}',
      if ((_done[_Act.delete] ?? 0) > 0) '${l10n.tr('triageSumDelete')} ${_done[_Act.delete]}',
      if ((_done[_Act.later] ?? 0) > 0) '${l10n.tr('triageSumLater')} ${_done[_Act.later]}',
      if ((_done[_Act.control] ?? 0) > 0) '${l10n.tr('triageSumControl')} ${_done[_Act.control]}',
      if ((_done[_Act.read] ?? 0) > 0) '${l10n.tr('triageSumRead')} ${_done[_Act.read]}',
      if ((_done[_Act.skip] ?? 0) > 0) '${l10n.tr('triageSumSkip')} ${_done[_Act.skip]}',
    ];
    return EmptyState(
      icon: AppIcons.done_all,
      title: total == 0 ? l10n.tr('triageNothing') : l10n.tr('triageDone'),
      message: parts.isEmpty ? null : parts.join(' · '),
      actionLabel: l10n.tr('done'),
      actionIcon: AppIcons.check,
      onAction: () => Navigator.of(context).maybePop(),
    );
  }
}
