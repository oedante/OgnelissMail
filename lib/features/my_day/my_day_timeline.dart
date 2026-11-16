// lib/features/my_day/my_day_timeline.dart
// «Мой день» шкалой (решение владельца 09.11.2026: два вида — доска по
// умолчанию и шкала; макет — docs/design/MOCKUPS_MY_DAY_TASKS.md).
//
//  · сверху — карточка «Сейчас» (часы, погода, что идёт и что дальше),
//    под ней — лоток «Без времени»: задачи на сегодня без своего времени и
//    просроченные (красным);
//  · шкала часов: встречи блоками цвета календаря (пересекающиеся —
//    рядом), задачи со временем — рамкой с кружком «выполнено», свободные
//    окна рабочего дня подписаны, линия «сейчас», прошедшее приглушено;
//    письма «На контроле» со сроком сегодня — флажком у края;
//  · задачу тянут за ручку ⋮⋮ из лотка на шкалу (шаг 15 минут) и по шкале;
//    обратно в лоток — убрать время. Время задачи — только в приложении
//    (task_blocks.dart): срок и сервер не меняются. Просроченная задача,
//    поставленная на шкалу, получает срок «сегодня»;
//  · долгое нажатие на задачу — та же карточка, что на доске.
//
// Планшет и широкое окно: шкала слева, лоток справа колонкой.

part of 'my_day_screen.dart';

const double _tlHourH = 64;
const double _tlGutter = 52;

class _TlItem {
  final String key;
  final double from;
  final double to;
  final String title;
  final String? sub;
  final Color color;
  final IconData icon;
  final Task? task;
  final bool done;
  final bool live;
  final VoidCallback onTap;
  int col = 0;
  int cols = 1;
  _TlItem({
    required this.key,
    required this.from,
    required this.to,
    required this.title,
    this.sub,
    required this.color,
    required this.icon,
    this.task,
    this.done = false,
    this.live = false,
    required this.onTap,
  });
  bool get isTask => task != null;
}

extension _MyDayTimeline on _MyDayScreenState {
  Widget _timelineBody(BuildContext context, _MyDayData d, DateTime now, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final muted = AppColors.mutedText(context);
    final hm = DateFormat('HH:mm');
    final today = DateTime(now.year, now.month, now.day);
    final blocks = ref.watch(taskBlocksProvider);
    double hourOf(DateTime t) => DayTimeline.hourOf(t, today);

    final items = <_TlItem>[];
    final allDay = <CalendarEvent>[];
    for (final e in d.events) {
      if (e.isAllDay) {
        allDay.add(e);
        continue;
      }
      final s = e.startTime.toLocal(), en = e.endTime.toLocal();
      var from = hourOf(s).clamp(0.0, 24.0), to = hourOf(en).clamp(0.0, 24.0);
      if (to - from < 0.25) to = (from + 0.25).clamp(0.0, 24.0);
      if (to <= from) continue;
      final live = !s.isAfter(now) && en.isAfter(now);
      items.add(_TlItem(
        key: 'e${e.id}',
        from: from,
        to: to,
        title: e.title.trim().isEmpty ? l10n.tr('noSubject') : e.title,
        sub: [
          '${hm.format(s)}–${hm.format(en)}',
          if ((e.location ?? '').trim().isNotEmpty) e.location!.trim(),
        ].join(' · '),
        color: e.colorValue != null ? Color(e.colorValue!) : scheme.primary,
        icon: (e.onlineMeetingUrl ?? '').isNotEmpty ? AppIcons.videocam : AppIcons.event,
        live: live,
        onTap: () => context.push(eventDetailsPath(e.id, accountId: e.accountId)),
      ));
    }

    // Задачи: со своим временем — на шкале, без — в лотке.
    final tray = <(Task, bool overdue)>[];
    final seen = <String>{};
    void addTask(Task t, {required bool done}) {
      if (!seen.add('${t.accountId}|${t.id}')) return;
      final key = taskBlockKey(t.accountId, t.id);
      final b = blocks[key];
      final when = _MyDayScreenState._taskTime(t);
      final hasTime = when != null && (when.hour != 0 || when.minute != 0);
      final day = when == null ? null : DateTime(when.year, when.month, when.day);
      DateTime? start;
      var minutes = 30;
      if (b != null && DateTime(b.start.year, b.start.month, b.start.day) == today) {
        start = b.start;
        minutes = b.minutes;
      } else if (hasTime && day == today) {
        start = when;
      }
      if (start == null) {
        if (!done) tray.add((t, day != null && day.isBefore(today)));
        return;
      }
      final from = hourOf(start).clamp(0.0, 23.75);
      items.add(_TlItem(
        key: 't$key',
        from: from,
        to: (from + minutes / 60).clamp(0.25, 24.0),
        title: t.title,
        sub: '${hm.format(start)}–${hm.format(start.add(Duration(minutes: minutes)))}',
        color: scheme.primary,
        icon: AppIcons.task_alt,
        task: t,
        done: done,
        onTap: () => showTaskEditor(context, task: taskFromRow(t), accountId: t.accountId),
      ));
    }

    for (final t in [...d.tasks, ...d.inProgress]) {
      if (t.status == TaskStatus.completed.index) continue;
      if (_doneLocal.contains('${t.accountId}|${t.id}')) continue;
      addTask(t, done: false);
    }
    for (final t in d.doneToday) {
      addTask(t, done: true);
    }

    final cols = DayTimeline.columns([for (final i in items) (from: i.from, to: i.to)]);
    for (var i = 0; i < items.length; i++) {
      items[i]
        ..col = cols[i].col
        ..cols = cols[i].cols;
    }

    // Свободные окна рабочего дня — от «сейчас» до конца рабочих часов.
    final workStart = SyncSchedule.startMinutes / 60, workEnd = SyncSchedule.endMinutes / 60;
    final nowH = hourOf(now);
    final free = workEnd <= workStart
        ? const <({double from, double to})>[]
        : DayTimeline.free(
            [for (final i in items) if (!i.done) (from: i.from, to: i.to)],
            from: nowH > workStart ? (nowH * 4).ceil() / 4 : workStart,
            to: workEnd,
          );

    // Письма «На контроле» со сроком сегодня — флажком у края шкалы.
    final markers = <(double, String)>[
      for (final m in d.control)
        if (m.controlState != ControlState.done &&
            m.followUpAt != null &&
            DateTime(m.followUpAt!.toLocal().year, m.followUpAt!.toLocal().month, m.followUpAt!.toLocal().day) ==
                today)
          (hourOf(m.followUpAt!.toLocal()), '${hm.format(m.followUpAt!.toLocal())} · ${_subjectOf(m, l10n)}'),
    ];

    // Часы шкалы: рабочий день и всё, что вне его, с запасом в час.
    var fromH = (workStart.floor() - 1).clamp(0, 23).toDouble();
    var toH = (workEnd.ceil() + 1).clamp(1, 24).toDouble();
    for (final i in items) {
      if (i.from < fromH) fromH = i.from.floorToDouble();
      if (i.to > toH) toH = i.to.ceilToDouble();
    }
    if (nowH < fromH) fromH = nowH.floorToDouble();
    if (nowH + 0.5 > toH) toH = (nowH + 1).ceilToDouble().clamp(1, 24);

    final timed = [
      for (final s in _slots(context, d, now, l10n))
        if (s.at != null) s,
    ]..sort((a, b) => a.at!.compareTo(b.at!));

    final timeline = _tlTimeline(context, items, free, markers, fromH, toH, now, today, l10n);
    final trayView = _tlTray(context, tray, l10n, muted);
    // Поручения со сроком сегодня — чипами рядом с событиями на весь день.
    final assigned = [
      for (final v in ref.watch(assignmentsProvider).value ?? const <AssignmentView>[])
        if (v.active && v.due != null && DateTime(v.due!.year, v.due!.month, v.due!.day) == today) v,
    ];
    final allDayView = allDay.isEmpty && assigned.isEmpty
        ? null
        : SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              children: [
                for (final v in assigned)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: Builder(
                      builder: (chipCtx) => GestureDetector(
                        onLongPress: () =>
                            unawaited(showAssignmentPeek(context, ref, v, anchor: peekAnchorOf(chipCtx))),
                        onSecondaryTapUp: secondaryAsHold(
                            () => unawaited(showAssignmentPeek(context, ref, v, anchor: peekAnchorOf(chipCtx)))),
                        child: ActionChip(
                          avatar: Icon(AppIcons.assignment_ind, size: 16, color: assignmentStatusColor(v.status, context)),
                          label: Text('${v.row.title} · ${v.otherName}'),
                          onPressed: () => context.push('/assignments/${v.id}'),
                        ),
                      ),
                    ),
                  ),
                for (final e in allDay)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: ActionChip(
                      avatar: Icon(AppIcons.event,
                          size: 16, color: e.colorValue != null ? Color(e.colorValue!) : scheme.primary),
                      label: Text(e.title.trim().isEmpty ? l10n.tr('noSubject') : e.title),
                      onPressed: () => context.push(eventDetailsPath(e.id, accountId: e.accountId)),
                    ),
                  ),
              ],
            ),
          );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= Breakpoints.tablet;
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0),
        child: _nowCard(context, d, timed, now, l10n),
      );
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(children: [
              header,
              ?allDayView,
              Expanded(child: timeline),
            ]),
          ),
          Container(
            width: 340,
            decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
            child: trayView,
          ),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        trayView,
        ?allDayView,
        Expanded(child: timeline),
      ]);
    });
  }

  /// Лоток «Без времени»: телефон — полосой вбок над шкалой, широкое окно —
  /// колонкой. Бросить задачу сюда — убрать её со шкалы.
  Widget _tlTray(BuildContext context, List<(Task, bool)> tray, AppLocalizations l10n, Color muted) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final column = c.maxHeight.isFinite && c.maxWidth < Breakpoints.tablet && c.maxWidth <= 400;
      final cards = [
        for (final (t, overdue) in tray) _tlTrayCard(context, t, overdue, l10n, width: column ? null : 220),
      ];
      return DragTarget<Task>(
        onWillAcceptWithDetails: (det) => ref.read(taskBlocksProvider).containsKey(taskBlockKey(det.data.accountId, det.data.id)),
        onAcceptWithDetails: (det) {
          unawaited(HapticFeedback.selectionClick());
          unawaited(ref.read(taskBlocksProvider.notifier).set(det.data.accountId, det.data.id, null));
        },
        builder: (context, candidates, _) {
          final hot = candidates.isNotEmpty;
          final title = Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
            child: Row(children: [
              Text('${l10n.tr('tlNoTime')} · ${tray.length}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(hot ? l10n.tr('tlDropToTray') : l10n.tr('tlDragHint'),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            ]),
          );
          final body = column
              ? ListView(padding: const EdgeInsets.symmetric(horizontal: Space.m), children: cards)
              : SizedBox(
                  height: tray.isEmpty ? 0 : 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.m),
                    children: cards,
                  ),
                );
          return Container(
            color: hot ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
            child: column
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, Expanded(child: body)])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    title,
                    body,
                    const SizedBox(height: Space.xs),
                  ]),
          );
        },
      );
    });
  }

  Widget _tlTrayCard(BuildContext context, Task t, bool overdue, AppLocalizations l10n, {double? width}) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final when = _MyDayScreenState._taskTime(t);
    final sub = overdue
        ? '${l10n.tr('overdue')} · ${_MyDayScreenState._whenShort(when!, DateTime.now(), l10n)}'
        : (t.status == TaskStatus.inProgress.index ? l10n.tr('boardInWork') : l10n.tr('myDayTask'));
    final card = Container(
      width: width,
      margin: EdgeInsets.only(right: width == null ? 0 : Space.s, bottom: width == null ? Space.s : 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showTaskEditor(context, task: taskFromRow(t), accountId: t.accountId),
          onLongPress: () => _taskPeek(context, t),
          onSecondaryTapUp: secondaryAsHold(() => _taskPeek(context, t)),
          child: Row(children: [
            _tlHandle(context, t, t.title, l10n),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: Space.s, top: 6, bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: overdue ? AppColors.errorText(context) : muted)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
    return KeyedSubtree(key: ValueKey('tray${t.accountId}|${t.id}'), child: card);
  }

  /// Ручка ⋮⋮: задачу тянут из лотка на шкалу и по шкале.
  Widget _tlHandle(BuildContext context, Task t, String title, AppLocalizations l10n, {double size = 20}) {
    final muted = AppColors.mutedText(context);
    return Semantics(
      label: l10n.tr('boardDragHandle'),
      child: Draggable<Task>(
        data: t,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(
          offset: const Offset(-24, -24),
          child: _dragChip(context, _BoardCard(
            key: 'drag',
            icon: AppIcons.task_alt,
            iconColor: Theme.of(context).colorScheme.primary,
            title: title,
            onTap: () {},
          )),
        ),
        onDragStarted: () => HapticFeedback.selectionClick(),
        onDragEnd: (_) => _setTlHover(null),
        onDraggableCanceled: (_, __) => _setTlHover(null),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox(width: 36, height: 40, child: Icon(AppIcons.drag_indicator, size: size, color: muted)),
        ),
      ),
    );
  }

  Widget _tlTimeline(BuildContext context, List<_TlItem> items, List<({double from, double to})> free,
      List<(double, String)> markers, double fromH, double toH, DateTime now, DateTime today, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final nowColor = AppColors.errorText(context);
    final hm = DateFormat('HH:mm');
    double y(double h) => (h - fromH) * _tlHourH;
    final nowH = DayTimeline.hourOf(now, today);
    final height = y(toH) + Space.xl;

    // Первый показ — к «сейчас» (за час до него).
    if (!_tlScrolled) {
      _tlScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_tlScroll.hasClients) return;
        final p = _tlScroll.position;
        _tlScroll.jumpTo((y(nowH - 1)).clamp(p.minScrollExtent, p.maxScrollExtent));
      });
    }

    double? hourAt(Offset global) {
      final box = _tlKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return fromH + box.globalToLocal(global).dy / _tlHourH;
    }

    // Тянут к краю — шкала прокручивается.
    void edgeScroll(Offset global) {
      final view = _tlViewKey.currentContext?.findRenderObject() as RenderBox?;
      if (view == null || !_tlScroll.hasClients) return;
      final local = view.globalToLocal(global).dy;
      final p = _tlScroll.position;
      double step = 0;
      if (local < 48) step = -16;
      if (local > view.size.height - 48) step = 16;
      if (step != 0) _tlScroll.jumpTo((p.pixels + step).clamp(p.minScrollExtent, p.maxScrollExtent));
    }

    final hover = _tlHover;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth - _tlGutter - Space.l;
      return DragTarget<Task>(
        onWillAcceptWithDetails: (_) => true,
        onMove: (det) {
          edgeScroll(det.offset);
          final h = hourAt(det.offset);
          if (h != null) _setTlHover(DayTimeline.hourOf(DayTimeline.snap(today, h), today));
        },
        onLeave: (_) => _setTlHover(null),
        onAcceptWithDetails: (det) {
          final h = hourAt(det.offset);
          _setTlHover(null);
          if (h != null) unawaited(_tlPlace(det.data, DayTimeline.snap(today, h)));
        },
        builder: (context, candidates, _) => SingleChildScrollView(
          key: _tlViewKey,
          controller: _tlScroll,
          padding: const EdgeInsets.only(top: Space.m),
          child: SizedBox(
            key: _tlKey,
            height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              // Часы и линии.
              for (var h = fromH.ceil(); h <= toH; h++) ...[
                Positioned(
                  left: 0,
                  width: _tlGutter - 8,
                  top: y(h.toDouble()) - 8,
                  child: Text(hm.format(today.add(Duration(hours: h))),
                      textAlign: TextAlign.right, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                ),
                Positioned(
                  left: _tlGutter,
                  right: Space.l,
                  top: y(h.toDouble()),
                  child: Container(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              ],
              // Свободные окна.
              for (final f in free)
                Positioned(
                  left: _tlGutter + 4,
                  right: Space.l + 2,
                  top: y(f.from) + 2,
                  height: (y(f.to) - y(f.from) - 4).clamp(0.0, double.infinity),
                  child: _tlFree(context, f, l10n),
                ),
              // Встречи и задачи.
              for (final it in items)
                Positioned(
                  left: _tlGutter + 4 + w * it.col / it.cols,
                  width: w / it.cols - 6,
                  top: y(it.from) + 1,
                  height: (y(it.to) - y(it.from) - 3).clamp(18.0, double.infinity),
                  child: KeyedSubtree(
                    key: ValueKey(it.key),
                    child: _tlBlock(context, it, past: it.to <= nowH, l10n: l10n),
                  ),
                ),
              // Письма на контроле со сроком.
              for (final (at, text) in markers)
                Positioned(
                  right: Space.l + 2,
                  top: y(at) - 11,
                  child: _tlMarker(context, text),
                ),
              // Куда встанет задача.
              if (hover != null && candidates.isNotEmpty) ...[
                Positioned(
                  left: _tlGutter,
                  right: Space.l,
                  top: y(hover),
                  child: Container(height: 2, color: theme.colorScheme.primary),
                ),
                Positioned(
                  left: _tlGutter + 6,
                  top: y(hover) + 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                    child: Text(hm.format(DayTimeline.snap(today, hover)),
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onPrimary)),
                  ),
                ),
              ],
              // Линия «сейчас».
              if (nowH >= fromH && nowH <= toH) ...[
                Positioned(
                  left: _tlGutter - 5,
                  right: Space.l,
                  top: y(nowH) - 4,
                  child: IgnorePointer(
                    child: Row(children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: nowColor, shape: BoxShape.circle)),
                      Expanded(child: Container(height: 2, color: nowColor)),
                    ]),
                  ),
                ),
                Positioned(
                  left: 0,
                  width: _tlGutter - 8,
                  top: y(nowH) - 9,
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: Text(hm.format(now),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(color: nowColor, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
    });
  }

  /// Поставить задачу на время [at] (шкала, только в приложении).
  Future<void> _tlPlace(Task t, DateTime at) async {
    unawaited(HapticFeedback.selectionClick());
    final notifier = ref.read(taskBlocksProvider.notifier);
    final old = ref.read(taskBlocksProvider)[taskBlockKey(t.accountId, t.id)];
    await notifier.set(t.accountId, t.id, TaskBlock(at, old?.minutes ?? 30));
    // Просроченная — срок «сегодня»: иначе она осталась бы в «Просрочено».
    final when = _MyDayScreenState._taskTime(t);
    final today = DateTime(at.year, at.month, at.day);
    if (when != null && DateTime(when.year, when.month, when.day).isBefore(today)) {
      await ref.read(taskActionsProvider).reschedule(t.accountId, t.id, today);
    }
  }

  Widget _tlFree(BuildContext context, ({double from, double to}) f, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final minutes = ((f.to - f.from) * 60).round();
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: minutes < 25
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.event_available, size: 16, color: muted),
              const SizedBox(width: 6),
              Text(l10n.tr('tlFree').replaceAll('{d}', _MyDayScreenState._left(Duration(minutes: minutes), l10n)),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ]),
    );
  }

  Widget _tlMarker(BuildContext context, String text) {
    final c = AppColors.warningText(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(AppIcons.bookmark, size: 13, color: c),
        const SizedBox(width: 3),
        Flexible(
          child: Text(text,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c)),
        ),
      ]),
    );
  }

  Widget _tlBlock(BuildContext context, _TlItem it, {required bool past, required AppLocalizations l10n}) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final dark = theme.brightness == Brightness.dark;
    final short = it.to - it.from <= 0.5;
    final title = Text(
      it.title,
      maxLines: short ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        decoration: it.done ? TextDecoration.lineThrough : null,
        color: it.done ? muted : null,
      ),
    );
    final sub = short || (it.sub ?? '').isEmpty
        ? null
        : Text(it.sub!,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted));
    final t = it.task;
    if (t != null) {
      final p = theme.colorScheme.primary;
      return Opacity(
        opacity: past || it.done ? 0.6 : 1,
        child: Material(
          color: p.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.withValues(alpha: 0.55), width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: it.onTap,
            onLongPress: () => _taskPeek(context, t),
            onSecondaryTapUp: secondaryAsHold(() => _taskPeek(context, t)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                tooltip: l10n.tr(it.done ? 'taskReopen' : 'taskDone'),
                icon: Icon(it.done ? AppIcons.check_circle : AppIcons.radio_button_unchecked,
                    size: 18, fill: it.done ? 1 : 0, color: it.done ? AppColors.successText(context) : p),
                onPressed: () => unawaited(_moveTask(t, it.done ? _Col.upcoming : _Col.done)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, ?sub]),
                ),
              ),
              if (!it.done) _tlHandle(context, t, it.title, l10n, size: 18),
            ]),
          ),
        ),
      );
    }
    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Material(
        color: it.color.withValues(alpha: dark ? 0.30 : 0.15),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: it.onTap,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: it.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 6, 3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(it.icon, size: 15, color: it.color),
                    const SizedBox(width: 4),
                    Expanded(child: title),
                    if (it.live)
                      Text(l10n.tr('myDayNow'),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: AppColors.successText(context), fontWeight: FontWeight.w700)),
                  ]),
                  ?sub,
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
