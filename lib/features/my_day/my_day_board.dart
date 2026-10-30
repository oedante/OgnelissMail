// lib/features/my_day/my_day_board.dart
// «Мой день» доской (канбан): «Предстоит» · «В работе» · «Готово».
//
// Правило владельца (09.10.2026): прошедшие встречи переходят в «Готово»
// сами, по времени окончания. Задачи и напоминания переносятся только
// вручную: перетащить за ручку ⋮⋮ слева или меню ⋮. Просроченная задача
// не пропадает — остаётся в своей колонке, срок красным.
//
// 10.10.2026 (замечания владельца): тянуть — только за ручку, а не за всю
// карточку долгим нажатием (карточка «плыла», список прокручивался);
// карточки, которые не переносятся (встречи, письма), отмечены серым
// замком; под пальцем — компактная плашка, а не копия карточки во всю
// ширину. Перенос виден сразу (локально), экран не перерисовывается целиком.
//
// Телефон (11.10.2026): три панели во всю ширину друг под другом —
// «Предстоит», «В работе», «Готово», компактные строки, до четырёх дел в
// панели и «Показать все»; задачу бросают на нужную панель. Планшет и
// широкое окно: три колонки рядом.

part of 'my_day_screen.dart';

enum _Col { upcoming, work, done }

class _BoardCard {
  final String key;
  final DateTime? sort;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final bool faded;
  final VoidCallback onTap;
  final Task? task;
  final Widget? trailing;
  const _BoardCard({
    required this.key,
    this.sort,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.faded = false,
    required this.onTap,
    this.task,
    this.trailing,
  });
}

extension _MyDayBoard on _MyDayScreenState {
  Widget _boardBody(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final cols = _boardColumns(context, d, now, l10n);
    final titles = {
      _Col.upcoming: l10n.tr('boardUpcoming'),
      _Col.work: l10n.tr('boardInWork'),
      _Col.done: l10n.tr('boardDone'),
    };
    final timed = [
      for (final s in _slots(context, d, now, l10n))
        if (s.at != null) s,
    ]..sort((a, b) => a.at!.compareTo(b.at!));

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= Breakpoints.tablet;
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0),
        child: _nowCard(context, d, timed, now, l10n),
      );
      final hint = Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.xs),
        child: Text(l10n.tr('boardHint'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
      );
      if (wide) {
        return Column(children: [
          header,
          hint,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final col in _Col.values)
                  Expanded(child: _boardColumn(context, col, titles[col]!, cols[col]!, l10n, c.maxWidth / 3)),
              ]),
            ),
          ),
        ]);
      }
      // Телефон (11.10.2026, замечание владельца): панели во всю ширину
      // друг под другом — «Предстоит», ниже «В работе», ещё ниже «Готово»;
      // компактные строки, в панели до четырёх дел и «Показать все». Раньше
      // колонки листались вбок, и их приходилось двигать.
      return ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          header,
          hint,
          for (final col in _Col.values)
            _boardPanel(context, col, titles[col]!, cols[col]!, l10n),
        ],
      );
    });
  }

  /// Панель доски во всю ширину (телефон): заголовок полосой с числом,
  /// компактные строки; бросить задачу можно на всю панель.
  Widget _boardPanel(BuildContext context, _Col col, String title, List<_BoardCard> cards, AppLocalizations l10n) {
    final theme = Theme.of(context);
    const collapsed = 4;
    final open = _boardExpanded.contains(col);
    final shown = open || cards.length <= collapsed + 1 ? cards : cards.take(collapsed).toList();
    return DragTarget<Task>(
      onWillAcceptWithDetails: (det) => _colOf(det.data) != col,
      onAcceptWithDetails: (det) => _moveTask(det.data, col),
      builder: (context, candidates, _) {
        final hot = candidates.isNotEmpty;
        return Container(
          margin: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
          decoration: BoxDecoration(
            color: hot ? theme.colorScheme.primary.withValues(alpha: 0.08) : theme.colorScheme.surfaceContainerHigh,
            borderRadius: Radii.cardAll,
          ),
          // Рамка — поверх содержимого (1.7.2+106, замечание владельца
          // 24.10.2026: «границы подписи заголовка выходят за границы
          // области»). Рамкой в decoration содержимое обрезалось по внешнему
          // краю рамки, и полоса заголовка на скруглённых углах закрашивала
          // рамку, а её верхняя линия торчала за скругление.
          foregroundDecoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            // Рамка — когда над колонкой дело (hot) и в высоком контрасте,
            // AMOLED, «Чтении»; в «воздушном» виде (1.8.0) колонку отделяет тон.
            border: hot
                ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5))
                : (OgnelissLook.of(context).cardBorder ? Border.all(color: AppColors.cardEdge(context)) : null),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionBand(title: title, count: cards.length),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, Space.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.s),
                    child: Text(l10n.tr('boardEmpty'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                  ),
                for (final c in shown) KeyedSubtree(key: ValueKey(c.key), child: _boardTile(context, c, dense: true)),
                if (shown.length < cards.length || (open && cards.length > collapsed + 1))
                  TextButton(
                    onPressed: () => _toggleBoardExpanded(col),
                    child: Text(open
                        ? l10n.tr('boardShowLess')
                        : l10n.tr('boardShowAll').replaceAll('{n}', '${cards.length}')),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Map<_Col, List<_BoardCard>> _boardColumns(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final muted = AppColors.mutedText(context);
    final err = AppColors.errorText(context);
    final hm = DateFormat('HH:mm');
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = <_BoardCard>[];
    final work = <_BoardCard>[];
    final done = <_BoardCard>[];

    // Встречи: идущие и будущие — «Предстоит», закончившиеся — «Готово» (сами).
    for (final e in d.events) {
      final s = e.startTime.toLocal(), en = e.endTime.toLocal();
      final ended = !e.isAllDay && !en.isAfter(now);
      final live = !e.isAllDay && !s.isAfter(now) && en.isAfter(now);
      final card = _BoardCard(
        key: 'e${e.id}',
        sort: e.isAllDay ? today : s,
        icon: (e.onlineMeetingUrl ?? '').isNotEmpty ? AppIcons.videocam : AppIcons.event,
        iconColor: ended ? muted : (e.colorValue != null ? Color(e.colorValue!) : scheme.primary),
        title: e.title.trim().isEmpty ? l10n.tr('noSubject') : e.title,
        subtitle: [
          e.isAllDay ? l10n.tr('myDayAllDay') : '${hm.format(s)}–${hm.format(en)}',
          if (live) l10n.tr('myDayNow'),
          if ((e.location ?? '').trim().isNotEmpty) e.location!.trim(),
        ].join(' · '),
        subtitleColor: live ? AppColors.successText(context) : null,
        faded: ended,
        onTap: () => context.push(eventDetailsPath(e.id, accountId: e.accountId)),
      );
      (ended ? done : upcoming).add(card);
    }

    // Задачи: колонка — по статусу, который меняет только пользователь.
    final seen = <String>{};
    _BoardCard taskCard(Task t, _Col col) {
      final when = _MyDayScreenState._taskTime(t);
      final hasTime = when != null && (when.hour != 0 || when.minute != 0);
      final overdue = col != _Col.done &&
          when != null &&
          (DateTime(when.year, when.month, when.day).isBefore(today) || (hasTime && when.isBefore(now)));
      return _BoardCard(
        key: 't${t.accountId}|${t.id}',
        sort: col == _Col.done ? t.completedAt?.toLocal() : (when ?? today),
        icon: col == _Col.done ? AppIcons.check_circle : AppIcons.task_alt,
        iconColor: col == _Col.done ? AppColors.successText(context) : (overdue ? err : scheme.primary),
        title: t.title,
        subtitle: col == _Col.done
            ? (t.completedAt == null ? l10n.tr('boardDone') : '${l10n.tr('boardDone')} · ${hm.format(t.completedAt!.toLocal())}')
            : (when == null ? l10n.tr('myDayTask') : _MyDayScreenState._whenShort(when, now, l10n)),
        subtitleColor: overdue ? err : null,
        faded: col == _Col.done,
        task: t,
        onTap: () => showTaskEditor(context, task: taskFromRow(t), accountId: t.accountId),
        trailing: _taskMenu(t, col, l10n),
      );
    }

    // Перенос, ещё не дошедший до базы, — сразу в новой колонке.
    void place(Task t, _Col stored) {
      final key = 't${t.accountId}|${t.id}';
      var col = stored;
      final moved = _boardMoves[key];
      if (moved != null) {
        if (moved == stored) {
          _boardMoves.remove(key); // база догнала
        } else {
          col = moved;
        }
      }
      (switch (col) { _Col.upcoming => upcoming, _Col.work => work, _Col.done => done }).add(taskCard(t, col));
    }

    for (final t in [...d.tasks, ...d.inProgress]) {
      if (!seen.add('${t.accountId}|${t.id}')) continue;
      place(t, t.status == TaskStatus.inProgress.index ? _Col.work : _Col.upcoming);
    }
    for (final t in d.doneToday) {
      if (!seen.add('${t.accountId}|${t.id}')) continue;
      place(t, _Col.done);
    }

    // «Позже»: вернётся сегодня — «Предстоит», вернулось — «В работе».
    for (final m in d.later) {
      final at = m.remindAt?.toLocal();
      final returned = m.laterState == LaterState.returned;
      if (!returned && (at == null || !at.isAfter(now))) continue;
      (returned ? work : upcoming).add(_BoardCard(
        key: 'l${m.id}',
        sort: at ?? now,
        icon: AppIcons.watch_later,
        iconColor: AppColors.accentOrangeText(context),
        title: _subjectOf(m, l10n),
        subtitle: returned
            ? '${l10n.tr('laterReturned')} · ${m.fromName ?? m.fromEmail}'
            : '${l10n.tr('myDayLaterReturns')} ${hm.format(at!)} · ${m.fromName ?? m.fromEmail}',
        onTap: () => pushMailDetail(GoRouter.of(context), m.id, accountId: m.accountId),
      ));
    }

    // «На контроле»: ждут — «В работе», исполнено — «Готово».
    for (final m in d.control) {
      final isDone = m.controlState == ControlState.done;
      final overdue = !isDone && m.followUpAt != null && m.followUpAt!.isBefore(now);
      final label = l10n.tr(isDone
          ? 'controlDone'
          : (m.controlState == ControlState.awaitingReply ? 'controlAwaiting' : 'controlMustReply'));
      (isDone ? done : work).add(_BoardCard(
        key: 'c${m.id}',
        sort: m.followUpAt?.toLocal() ?? m.receivedAt.toLocal(),
        icon: isDone ? AppIcons.bookmark_added : AppIcons.bookmark,
        iconColor: isDone
            ? AppColors.successText(context)
            : (m.controlState == ControlState.mustReply ? AppColors.accentOrange : scheme.primary),
        title: _subjectOf(m, l10n),
        subtitle: [
          label,
          if (!isDone && m.followUpAt != null)
            l10n.tr('controlUntil').replaceAll('{when}', controlDeadlineLabel(m.followUpAt!.toLocal(), l10n)),
        ].join(' · '),
        subtitleColor: overdue ? err : null,
        faded: isDone,
        onTap: () => pushMailDetail(GoRouter.of(context), m.id, accountId: m.accountId),
      ));
    }

    // Приглашения без ответа — «В работе»: на них нужно ответить.
    for (final m in d.invites) {
      final start = EmailMeeting.parse(m.meetingJson)?.start;
      work.add(_BoardCard(
        key: 'i${m.id}',
        sort: start ?? m.receivedAt,
        icon: AppIcons.event_available,
        iconColor: scheme.primary,
        title: _subjectOf(m, l10n),
        subtitle: [
          l10n.tr('myDayInvite'),
          if (start != null) DateFormat('EEE, d MMM, HH:mm', l10n.localeCode).format(start.toLocal()),
        ].join(' · '),
        onTap: () => pushMailDetail(GoRouter.of(context), m.id, accountId: m.accountId),
      ));
    }

    int bySort(_BoardCard a, _BoardCard b) =>
        (a.sort ?? today).compareTo(b.sort ?? today);
    upcoming.sort(bySort);
    work.sort(bySort);
    // «Готово» — свежее сверху.
    done.sort((a, b) => bySort(b, a));
    return {_Col.upcoming: upcoming, _Col.work: work, _Col.done: done};
  }

  /// Перенос задачи — только руками: меню ⋮ (и перетаскивание).
  Widget _taskMenu(Task t, _Col col, AppLocalizations l10n) => AppMenuButton<_Col>(
        tooltip: l10n.tr('more'),
        icon: const Icon(AppIcons.more_vert, size: 20),
        onSelected: (to) => _moveTask(t, to),
        itemBuilder: (_) => [
          if (col != _Col.upcoming)
            AppMenuEntry(value: _Col.upcoming, icon: AppIcons.event_upcoming, label: l10n.tr('boardMoveBack')),
          if (col != _Col.work) AppMenuEntry(value: _Col.work, icon: AppIcons.work, label: l10n.tr('boardMoveWork')),
          if (col != _Col.done) AppMenuEntry(value: _Col.done, icon: AppIcons.task_alt, label: l10n.tr('boardMoveDone')),
        ],
      );

  Future<void> _moveTask(Task t, _Col to) async {
    _markBoardMove('t${t.accountId}|${t.id}', to);
    final actions = ref.read(taskActionsProvider);
    final wasDone = t.status == TaskStatus.completed.index;
    switch (to) {
      case _Col.done:
        await actions.setDone(t.accountId, t.id, true);
      case _Col.work:
        if (wasDone) await actions.setDone(t.accountId, t.id, false);
        await actions.update(t.accountId, t.id, TasksCompanion(status: Value(TaskStatus.inProgress.index)));
      case _Col.upcoming:
        if (wasDone) {
          await actions.setDone(t.accountId, t.id, false);
        } else {
          await actions.update(t.accountId, t.id, TasksCompanion(status: Value(TaskStatus.pending.index)));
        }
    }
    if (mounted) ref.invalidate(_myDayProvider);
  }

  Widget _boardColumn(BuildContext context, _Col col, String title, List<_BoardCard> cards, AppLocalizations l10n,
      double width) {
    final theme = Theme.of(context);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (det) => _colOf(det.data) != col,
      onAcceptWithDetails: (det) => _moveTask(det.data, col),
      builder: (context, candidates, _) {
        final hot = candidates.isNotEmpty;
        return Container(
          margin: const EdgeInsets.fromLTRB(0, Space.xs, Space.s, Space.s),
          decoration: BoxDecoration(
            color: hot
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: Radii.cardAll,
            // Колонка видна на фоне экрана в любой теме (раньше заливка
            // совпадала с фоном светлой темы), карточки дел на ней — светлее.
            border: hot
                ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5))
                : (OgnelissLook.of(context).cardBorder ? Border.all(color: AppColors.cardEdge(context)) : null),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
              child: Row(children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text('${cards.length}', style: theme.textTheme.labelMedium?.copyWith(color: AppColors.mutedText(context))),
              ]),
            ),
            Expanded(
              child: cards.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Text(l10n.tr('boardEmpty'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.l),
                      itemCount: cards.length,
                      itemBuilder: (context, i) {
                        final c = cards[i];
                        return KeyedSubtree(key: ValueKey(c.key), child: _boardTile(context, c));
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }

  /// Колонка задачи с учётом переноса, ещё не дошедшего до базы.
  _Col _colOf(Task t) =>
      _boardMoves['t${t.accountId}|${t.id}'] ??
      (t.status == TaskStatus.completed.index
          ? _Col.done
          : (t.status == TaskStatus.inProgress.index ? _Col.work : _Col.upcoming));

  /// Под пальцем при переносе — компактная плашка с названием.
  Widget _dragChip(BuildContext context, _BoardCard c) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      borderRadius: Radii.chipAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(c.icon, size: 18, color: c.iconColor),
            const SizedBox(width: Space.s),
            Flexible(
              child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ),
          ]),
        ),
      ),
    );
  }

  /// Ручка переноса (задачи) или серый замок (встречи и письма — их
  /// колонку задаёт время или состояние письма).
  Widget _boardLead(BuildContext context, _BoardCard c, AppLocalizations l10n) {
    final muted = AppColors.mutedText(context);
    final t = c.task;
    if (t == null) {
      return Tooltip(
        message: l10n.tr('boardFixed'),
        child: SizedBox(
          width: 36,
          height: 40,
          child: Icon(AppIcons.lock, size: 14, color: muted.withValues(alpha: 0.6)),
        ),
      );
    }
    final handle = SizedBox(
      width: 36,
      height: 40,
      child: Icon(AppIcons.drag_indicator, size: 20, color: muted),
    );
    // Draggable (не LongPress): тянется сразу и только за ручку — список
    // под пальцем не прокручивается, карточку не нужно «нащупывать».
    return Semantics(
      label: l10n.tr('boardDragHandle'),
      child: Draggable<Task>(
        data: t,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(offset: const Offset(-24, -24), child: _dragChip(context, c)),
        onDragStarted: () {
          HapticFeedback.selectionClick();
          _setBoardDragging(c.key);
        },
        onDragEnd: (_) => _setBoardDragging(null),
        onDraggableCanceled: (_, __) => _setBoardDragging(null),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: handle),
      ),
    );
  }

  Widget _boardTile(BuildContext context, _BoardCard c, {bool dense = false}) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final l10n = AppLocalizations.of(context);
    return AnimatedOpacity(
      opacity: _boardDragging == c.key ? 0.35 : 1,
      duration: const Duration(milliseconds: 120),
      child: Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: Radii.cardAll,
        child: InkWell(
          borderRadius: Radii.cardAll,
          onTap: c.onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, dense ? 0 : Space.xs, c.trailing == null ? Space.m : 0, dense ? 0 : Space.xs),
            child: Row(children: [
              _boardLead(context, c, l10n),
              Icon(c.icon, size: 20, color: c.iconColor),
              const SizedBox(width: Space.s),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.title,
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: c.faded ? muted : null,
                        decoration: c.faded && c.task != null ? TextDecoration.lineThrough : null,
                      )),
                  if ((c.subtitle ?? '').isNotEmpty)
                    Text(c.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: c.subtitleColor ?? muted)),
                ]),
              ),
              if (c.trailing != null) c.trailing!,
            ]),
          ),
        ),
      ),
      ),
    );
  }
}
