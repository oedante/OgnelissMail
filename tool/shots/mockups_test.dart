// ignore_for_file: prefer_const_constructors
// tool/shots/mockups_test.dart
// Макеты на согласование (план 08.11.2026, п. 9–10; просьба владельца
// 09.11.2026): «Мой день» шкалой и поручения из письма. Это картинки на
// теме, шрифтах и значках приложения, а не работающие экраны: данные
// придуманы, кнопки ничего не делают.
//   flutter test tool/shots/mockups_test.dart --update-goldens
//   → tool/shots/out/mock_*.png
// Описание и вопросы на согласование — docs/design/MOCKUPS_MY_DAY_TASKS.md.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/core/theme/tokens.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

const _phone = Size(393, 852);
const _tablet = Size(1194, 834);

// Цвета календарей и людей — из палитры категорий приложения.
const _blue = Color(0xFF4A78B0);
const _green = Color(0xFF5B8C5A);
const _purple = Color(0xFF7E5E9E);
const _orange = Color(0xFFB0703F);
const _teal = Color(0xFF3F8A8C);
const _rose = Color(0xFFA35D6A);

Color _muted(BuildContext c) => AppColors.mutedText(c);

Future<void> _mock(WidgetTester tester, String name, Widget home, {bool dark = false, Size size = _phone}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  // Тени — как на устройстве (тесты по умолчанию рисуют их чёрной рамкой);
  // вернуть до конца теста — его проверяет сама рамка тестов.
  debugDisableShadows = false;
  try {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.darkTheme(1.0) : AppTheme.lightTheme(1.0),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/mock_$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

// ───────────────────────── общие детали ─────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const _Avatar(this.name, this.color, {this.size = 28});

  @override
  Widget build(BuildContext context) {
    final parts = name.split(' ');
    final initials = parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  const _Pill(this.text, this.color, {this.icon}) : filled = false;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: filled ? Colors.white : color)),
        ]),
      );
}

/// Шапка «Моего дня», как в приложении: заголовок, дата, кнопки.
PreferredSizeWidget _myDayBar(BuildContext context, String date, {String view = 'timeline'}) {
  final theme = Theme.of(context);
  Widget viewIcon(IconData icon, String id) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          width: 36,
          height: 32,
          decoration: BoxDecoration(
            color: view == id ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: view == id ? theme.colorScheme.primary : _muted(context)),
        ),
      );
  return AppBar(
    titleSpacing: Space.l,
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Мой день'),
      Text(date, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
    ]),
    actions: [
      // Вид: список, шкала (новое), доска.
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          viewIcon(Symbols.view_agenda_rounded, 'list'),
          viewIcon(Symbols.view_timeline_rounded, 'timeline'),
          viewIcon(Symbols.view_week_rounded, 'board'),
        ]),
      ),
      const SizedBox(width: Space.m),
    ],
  );
}

/// Полоса «сейчас»: компактные часы, текущее дело, погода.
class _NowStrip extends StatelessWidget {
  final String time;
  final String line;
  final String? sub;
  const _NowStrip(this.time, this.line, {this.sub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: Radii.cardAll,
      ),
      child: Row(children: [
        Text(time,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            if (sub != null)
              Text(sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
          ]),
        ),
        Icon(Symbols.partly_cloudy_day_rounded, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 4),
        Text('+3°', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ───────────────────────── шкала дня ─────────────────────────

enum _Kind { meeting, task, free, ghost }

class _Block {
  final double from;
  final double to;
  final String title;
  final String? sub;
  final Color color;
  final _Kind kind;
  final int col;
  final int cols;
  final bool done;
  final bool live;
  final String? chip;
  final IconData? icon;
  const _Block(this.from, this.to, this.title,
      {this.sub,
      this.color = _blue,
      this.kind = _Kind.meeting,
      this.col = 0,
      this.cols = 1,
      this.done = false,
      this.live = false,
      this.chip,
      this.icon});
}

/// Письмо «на контроле» со сроком — отметка у края шкалы.
class _Marker {
  final double at;
  final String text;
  const _Marker(this.at, this.text);
}

String _hm(double h) {
  final hh = h.floor();
  final mm = ((h - hh) * 60).round();
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

class _Timeline extends StatelessWidget {
  final double fromHour;
  final double toHour;
  final double hourH;
  final double? now;
  final List<_Block> blocks;
  final List<_Marker> markers;
  final double? snap;
  const _Timeline({
    required this.blocks,
    this.fromHour = 9,
    this.hourH = 66,
    this.now,
    this.markers = const [],
    this.snap,
  }) : toHour = 19;

  double _y(double h) => (h - fromHour) * hourH;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gutter = 52.0;
    final nowColor = AppColors.errorText(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth - gutter - Space.l;
      final height = _y(toHour) + 12;
      return SizedBox(
        height: height,
        child: Stack(clipBehavior: Clip.none, children: [
          // Часы и линии.
          for (var h = fromHour.ceil(); h <= toHour; h++) ...[
            Positioned(
              left: 0,
              width: gutter - 8,
              top: _y(h.toDouble()) - 8,
              child: Text(_hm(h.toDouble()),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(color: _muted(context))),
            ),
            Positioned(
              left: gutter,
              right: Space.l,
              top: _y(h.toDouble()),
              child: Container(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
          ],
          if (snap != null)
            Positioned(
              left: gutter,
              right: Space.l,
              top: _y(snap!),
              child: Container(height: 2, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            ),
          // Встречи и задачи.
          for (final b in blocks)
            Positioned(
              left: gutter + 4 + w * b.col / b.cols,
              width: w / b.cols - 6,
              top: _y(b.from) + 1,
              height: _y(b.to) - _y(b.from) - 3,
              child: _BlockView(b, past: now != null && b.to <= now!),
            ),
          // Письма на контроле со сроком.
          for (final m in markers)
            Positioned(
              right: Space.l + 2,
              top: _y(m.at) - 11,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: AppColors.warningText(context)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Symbols.flag_rounded, size: 13, fill: 1, color: AppColors.warningText(context)),
                  const SizedBox(width: 3),
                  Text(m.text, style: TextStyle(fontSize: 11.5, color: AppColors.warningText(context))),
                ]),
              ),
            ),
          // Линия «сейчас».
          if (now != null) ...[
            Positioned(
              left: gutter - 5,
              right: Space.l,
              top: _y(now!) - 4,
              child: Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: nowColor, shape: BoxShape.circle)),
                Expanded(child: Container(height: 2, color: nowColor)),
              ]),
            ),
            Positioned(
              left: 0,
              width: gutter - 8,
              top: _y(now!) - 9,
              child: Container(
                color: theme.scaffoldBackgroundColor,
                child: Text(_hm(now!),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(color: nowColor, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      );
    });
  }
}

class _BlockView extends StatelessWidget {
  final _Block b;
  final bool past;
  const _BlockView(this.b, {this.past = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final short = b.to - b.from <= 0.5;
    final title = Text(
      b.title,
      maxLines: short ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
        decoration: b.done ? TextDecoration.lineThrough : null,
        color: b.done ? _muted(context) : null,
      ),
    );
    final sub = b.sub == null || short
        ? null
        : Text(b.sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: _muted(context)));
    switch (b.kind) {
      case _Kind.free:
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.surface.withValues(alpha: 0.4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.event_available_rounded, size: 16, color: _muted(context)),
            const SizedBox(width: 6),
            Text(b.title, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
          ]),
        );
      case _Kind.task:
      case _Kind.ghost:
        final ghost = b.kind == _Kind.ghost;
        final p = theme.colorScheme.primary;
        return Opacity(
          opacity: past && !ghost ? 0.6 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ghost
                  ? Color.alphaBlend(p.withValues(alpha: 0.16), theme.colorScheme.surface)
                  : p.withValues(alpha: 0.05),
              border: Border.all(color: p.withValues(alpha: ghost ? 0.9 : 0.55), width: ghost ? 2 : 1.2),
              borderRadius: BorderRadius.circular(10),
              boxShadow: ghost
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))]
                  : null,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(b.done ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded,
                    size: 18, fill: b.done ? 1 : 0, color: b.done ? AppColors.successText(context) : p),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  title,
                  ?sub,
                ]),
              ),
              if (ghost) Icon(Symbols.drag_indicator_rounded, size: 18, color: p),
            ]),
          ),
        );
      case _Kind.meeting:
        return Opacity(
          opacity: past ? 0.55 : 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: b.color.withValues(alpha: dark ? 0.30 : 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: b.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 6, 3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (b.icon != null) ...[
                        Icon(b.icon, size: 15, color: b.color),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: title),
                      if (b.live) _Pill('идёт', AppColors.successText(context)),
                    ]),
                    ?sub,
                    if (b.chip != null) ...[
                      const Spacer(),
                      _Pill(b.chip!, b.color, icon: Symbols.mail_rounded),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        );
    }
  }
}

/// Задача без времени в лотке над шкалой.
class _TrayCard extends StatelessWidget {
  final String title;
  final String sub;
  final IconData icon;
  final Color? color;
  final bool lifted;
  final bool faded;
  const _TrayCard(this.title, this.sub,
      {this.icon = Symbols.radio_button_unchecked_rounded, this.color, this.faded = false}) : lifted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Opacity(
      opacity: faded ? 0.35 : 1,
      child: Container(
        width: 196,
        margin: const EdgeInsets.only(right: Space.s),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardFill(context),
          border: Border.all(color: lifted ? c : theme.colorScheme.outlineVariant, width: lifted ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: _muted(context), fontSize: 11.5)),
            ]),
          ),
          Icon(Symbols.drag_indicator_rounded, size: 16, color: _muted(context)),
        ]),
      ),
    );
  }
}

Widget _trayHeader(BuildContext context, String text, String hint) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
    child: Row(children: [
      Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const Spacer(),
      Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
    ]),
  );
}

const _dayBlocks = <_Block>[
  _Block(9.25, 9.75, 'Разобрать почту', kind: _Kind.task, done: true),
  _Block(10, 11.5, 'Планёрка отдела', sub: '10:00–11:30 · Переговорная 4 · 6 чел.', live: true,
      icon: Symbols.groups_rounded, cols: 2),
  _Block(10.5, 11, 'Звонок поставщику', sub: '10:30–11:00', color: _green, col: 1, cols: 2,
      icon: Symbols.call_rounded),
  _Block(11.5, 13, 'Свободно · 1 ч 30 мин', kind: _Kind.free),
  _Block(13, 14, 'Созвон с ООО «Ромашка»', sub: '13:00–14:00 · Teams', color: _purple,
      icon: Symbols.videocam_rounded, chip: 'К встрече: 3 письма'),
  _Block(14.5, 15.5, 'Подготовить презентацию', sub: '14:30–15:30 · задача', kind: _Kind.task),
  _Block(16, 17, 'Обзор проекта «Склад»', sub: '16:00–17:00 · Переговорная 2', color: _orange,
      icon: Symbols.groups_rounded),
  _Block(17, 18, 'Свободно · 1 ч', kind: _Kind.free),
];

class _TimelineScreen extends StatelessWidget {
  final bool dragging;
  const _TimelineScreen({this.dragging = false});

  @override
  Widget build(BuildContext context) {
    final blocks = [
      for (final b in _dayBlocks)
        if (!(dragging && b.kind == _Kind.free && b.from == 11.5)) b,
      if (dragging) ...[
        _Block(12.5, 13, 'Свободно · 30 мин', kind: _Kind.free),
        _Block(11.5, 12.5, 'Отчёт за октябрь', sub: '11:30–12:30 · 1 ч', kind: _Kind.ghost),
      ],
    ];
    return Scaffold(
      appBar: _myDayBar(context, 'Понедельник, 9 ноября'),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _NowStrip('11:21', 'Сейчас: Планёрка отдела', sub: 'до 11:30 · потом свободно 1,5 ч'),
        _trayHeader(context, 'Без времени · 3', dragging ? 'Отпустите — встанет на 11:30' : 'Перетащите на шкалу'),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            children: [
              _TrayCard('Отчёт за октябрь', '≈ 1 ч · срок сегодня', faded: dragging),
              const _TrayCard('Ответить Борису по договору', '≈ 15 мин'),
              _TrayCard('График отпусков', 'письмо на контроле', icon: Symbols.flag_rounded,
                  color: AppColors.warningText(context)),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _Timeline(
                  blocks: blocks,
                  now: 11 + 21 / 60,
                  snap: dragging ? 11.5 : null,
                  markers: const [_Marker(14.25, '14:15 ждём ответ · Договор № 15')],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ───────────────────────── утро и вечер ─────────────────────────

class _SheetOver extends StatelessWidget {
  final Widget background;
  final Widget sheet;
  final double height;
  const _SheetOver({required this.background, required this.sheet, required this.height});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(children: [
      Positioned.fill(child: background),
      Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.32))),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: height,
        child: Material(
          color: theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: sheet),
          ]),
        ),
      ),
    ]);
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final double? progress;
  const _StatBox(this.icon, this.value, this.label, {this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: progress, minHeight: 5),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final bool on;
  final String title;
  final String sub;
  final Widget? trailing;
  final IconData? icon;
  final Color? iconColor;
  const _PickRow(this.on, this.title, this.sub, {this.trailing, this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
      child: Row(children: [
        Icon(icon ?? (on ? Symbols.check_box_rounded : Symbols.check_box_outline_blank_rounded),
            fill: on ? 1 : 0, color: iconColor ?? (on ? theme.colorScheme.primary : _muted(context))),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
            Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

class _MorningPlan extends StatelessWidget {
  const _MorningPlan();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SheetOver(
      height: 640,
      background: Scaffold(
        appBar: _myDayBar(context, 'Понедельник, 9 ноября'),
        body: Column(children: [
          _NowStrip('08:40', 'Первая встреча в 10:00 — Планёрка отдела'),
          const SizedBox(height: Space.l),
          Expanded(
            child: ClipRect(
              child: _Timeline(
                  blocks: _dayBlocks.where((b) => b.kind == _Kind.meeting).toList(), now: 8.67, fromHour: 8),
            ),
          ),
        ]),
      ),
      sheet: ListView(padding: const EdgeInsets.only(top: Space.m), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Row(children: [
            Icon(Symbols.wb_twilight_rounded, color: AppColors.accentOrangeText(context)),
            const SizedBox(width: Space.s),
            Text('Доброе утро! План на сегодня', style: theme.textTheme.titleLarge),
          ]),
        ),
        const SizedBox(height: Space.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
              _StatBox(Symbols.event_rounded, '4', 'встречи · 3,5 ч'),
              SizedBox(width: Space.s),
              _StatBox(Symbols.event_available_rounded, '2,5 ч', 'свободно'),
              SizedBox(width: Space.s),
              _StatBox(Symbols.flag_rounded, '2', 'ждут ответа'),
            ]),
          ),
        ),
        _trayHeader(context, 'Взять в день', '4 из 6'),
        const _PickRow(true, 'Отчёт за октябрь', 'со вчера · ≈ 1 ч', trailing: _Pill('со вчера', _rose)),
        const _PickRow(true, 'Подготовить презентацию', 'срок сегодня · ≈ 1 ч'),
        const _PickRow(true, 'Ответить Борису по договору', 'письмо от 6 ноября · ≈ 15 мин'),
        const _PickRow(true, 'График отпусков', 'на контроле · Анна Смирнова', icon: Symbols.flag_rounded,
            iconColor: Color(0xFFB8743A)),
        const _PickRow(false, 'Обновить договор аренды', 'срок пятница'),
        const _PickRow(false, 'Заказать канцелярию', 'без срока'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Symbols.auto_awesome_rounded, size: 18),
              label: const Text('Расставить по свободным окнам'),
            ),
            const SizedBox(height: Space.s),
            FilledButton(onPressed: () {}, child: const Text('Начать день')),
          ]),
        ),
      ]),
    );
  }
}

class _EveningReview extends StatelessWidget {
  const _EveningReview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget left(String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Symbols.radio_button_unchecked_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
                  Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(spacing: 6, children: [
                ActionChip(
                    avatar: const Icon(Symbols.event_upcoming_rounded, size: 16),
                    label: const Text('На завтра'),
                    onPressed: () {}),
                ActionChip(
                    avatar: const Icon(Symbols.calendar_month_rounded, size: 16),
                    label: const Text('Дата…'),
                    onPressed: () {}),
              ]),
            ),
          ]),
        );
    return _SheetOver(
      height: 660,
      background: Scaffold(
        appBar: _myDayBar(context, 'Понедельник, 9 ноября'),
        body: Column(children: [
          _NowStrip('18:10', 'Рабочий день окончен', sub: 'Завтра первая встреча в 09:30'),
          const SizedBox(height: Space.l),
          Expanded(
            child: ClipRect(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _Timeline(blocks: [for (final b in _dayBlocks) if (b.from >= 12) b], now: 18.17, fromHour: 12),
              ),
            ),
          ),
        ]),
      ),
      sheet: ListView(padding: const EdgeInsets.only(top: Space.m), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Row(children: [
            Icon(Symbols.nights_stay_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: Space.s),
            Text('Итоги дня', style: theme.textTheme.titleLarge),
          ]),
        ),
        const SizedBox(height: Space.m),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
              _StatBox(Symbols.task_alt_rounded, '5 из 7', 'задач сделано', progress: 5 / 7),
              SizedBox(width: Space.s),
              _StatBox(Symbols.event_rounded, '4', 'встречи · 3,5 ч'),
              SizedBox(width: Space.s),
              _StatBox(Symbols.reply_rounded, '23', 'ответа на письма'),
            ]),
          ),
        ),
        _trayHeader(context, 'Не сделано · 2', ''),
        left('Подготовить презентацию', 'было 14:30–15:30'),
        left('Ответить Борису по договору', 'письмо от 6 ноября'),
        _trayHeader(context, 'На контроле', ''),
        _PickRow(true, 'Договор № 15 — ответ получен', 'Борис Орлов, 16:42 · снято с контроля',
            icon: Symbols.check_circle_rounded, iconColor: AppColors.successText(context)),
        _PickRow(false, 'График отпусков — ждём до среды', 'Анна Смирнова', icon: Symbols.flag_rounded,
            iconColor: AppColors.warningText(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: () {}, child: const Text('Всё на завтра')),
            ),
            const SizedBox(width: Space.s),
            Expanded(child: FilledButton(onPressed: () {}, child: const Text('Закрыть день'))),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── планшет ─────────────────────────

class _TabletDay extends StatelessWidget {
  const _TabletDay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget side(String title, List<Widget> items) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
            child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ...items,
        ]);
    Widget task(String t, String s, {IconData icon = Symbols.radio_button_unchecked_rounded, Color? color}) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: Row(children: [Expanded(child: _TrayCard(t, s, icon: icon, color: color))]),
        );
    return Scaffold(
      appBar: _myDayBar(context, 'Понедельник, 9 ноября'),
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(children: const [
            Padding(
              padding: EdgeInsets.only(right: Space.l),
              child: _NowStrip('11:21', 'Сейчас: Планёрка отдела',
                  sub: 'до 11:30 · встреч 4 (3 ч 30 мин) · свободно 2 ч 30 мин · задач 2 из 6'),
            ),
            SizedBox(height: Space.m),
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: _Timeline(
                      blocks: _dayBlocks,
                      now: 11 + 21 / 60,
                      hourH: 70,
                      markers: [_Marker(14.25, '14:15 ждём ответ · Договор № 15')],
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Container(
          width: 340,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: ListView(children: [
            side('Без времени · 3', [
              task('Отчёт за октябрь', '≈ 1 ч · срок сегодня'),
              task('Ответить Борису по договору', '≈ 15 мин'),
              task('Заказать канцелярию', 'без срока'),
            ]),
            side('На контроле · 2', [
              task('График отпусков', 'Анна Смирнова · ждём до среды', icon: Symbols.flag_rounded,
                  color: AppColors.warningText(context)),
              task('Договор № 15', 'Борис Орлов · сегодня до 15:00', icon: Symbols.flag_rounded,
                  color: AppColors.warningText(context)),
            ]),
            side('Поручения · 1 на проверке', [
              task('Отчёт за октябрь (отдел)', 'Вера Белова · на проверке', icon: Symbols.rate_review_rounded,
                  color: _teal),
            ]),
            side('Приглашения · 1', [
              task('Демо для заказчика', 'ср, 11 ноября, 15:00 · ответить', icon: Symbols.event_rounded, color: _purple),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── поручения ─────────────────────────

/// Письмо, как его показывает экран письма (упрощённо).
class _MailMock extends StatelessWidget {
  final String from;
  final Color color;
  final String subject;
  final String when;
  final String body;
  final Widget? banner;
  const _MailMock({
    required this.from,
    required this.color,
    required this.subject,
    required this.when,
    required this.body,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Symbols.arrow_back_rounded),
        actions: const [
          Icon(Symbols.archive_rounded),
          SizedBox(width: 20),
          Icon(Symbols.delete_rounded),
          SizedBox(width: 20),
          Icon(Symbols.more_vert_rounded),
          SizedBox(width: 12),
        ],
      ),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: Space.l), children: [
        Text(subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.m),
        Row(children: [
          _Avatar(from, color, size: 40),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(from, style: theme.textTheme.titleSmall),
              Text('кому: мне · $when', style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
            ]),
          ),
        ]),
        if (banner != null) ...[const SizedBox(height: Space.m), banner!],
        const SizedBox(height: Space.l),
        Text(body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field(this.label, this.child);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: _muted(context))),
          const SizedBox(height: 6),
          child,
        ]),
      );
}

class _AssignSheet extends StatelessWidget {
  const _AssignSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(String t, {bool on = false}) => ChoiceChip(label: Text(t), selected: on, onSelected: (_) {});
    Widget toggle(String t, String s, bool v) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 4, Space.s, 0),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
                Text(s, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
              ]),
            ),
            Switch(value: v, onChanged: (_) {}),
          ]),
        );
    return _SheetOver(
      height: 740,
      background: const _MailMock(
        from: 'Анна Смирнова',
        color: _rose,
        subject: 'График отпусков на 2027 год',
        when: 'сегодня, 09:12',
        body: 'Добрый день, коллеги!\n\nПрошу до пятницы внести даты отпусков ваших отделов в общий график.',
      ),
      sheet: ListView(padding: const EdgeInsets.only(top: Space.s), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Row(children: [
            Icon(Symbols.assignment_ind_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: Space.s),
            Text('Поручить', style: theme.textTheme.titleLarge),
            const Spacer(),
            Text('из письма Анны Смирновой', style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
          ]),
        ),
        _Field(
          'Что сделать',
          Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Собрать даты отпусков отдела и внести в общий график',
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
          ),
        ),
        _Field(
          'Исполнители',
          Wrap(spacing: 6, runSpacing: 6, children: [
            InputChip(
                avatar: const _Avatar('Вера Белова', _teal, size: 24),
                label: const Text('Вера Белова'),
                onDeleted: () {}),
            InputChip(
                avatar: const _Avatar('Дмитрий Кузнецов', _orange, size: 24),
                label: const Text('Дмитрий Кузнецов'),
                onDeleted: () {}),
            ActionChip(avatar: const Icon(Symbols.person_add_rounded, size: 18), label: const Text('Ещё'), onPressed: () {}),
          ]),
        ),
        _Field(
          'Срок',
          Wrap(spacing: 6, runSpacing: 6, children: [
            chip('Сегодня'),
            chip('Завтра'),
            chip('Чт, 12 ноя', on: true),
            chip('Дата…'),
          ]),
        ),
        const SizedBox(height: Space.s),
        toggle('Письмо исполнителям', 'с текстом, сроком и ссылкой на письмо Анны', true),
        toggle('На контроле у меня', 'задача «Ждём» со сроком, напомнить за день', true),
        toggle('Каждому — отдельное поручение', 'два исполнителя — два статуса', true),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
          child: Row(children: [
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Symbols.visibility_rounded, size: 18),
              label: const Text('Как увидят'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Symbols.send_rounded, size: 18),
              label: const Text('Поручить'),
            ),
          ]),
        ),
      ]),
    );
  }
}

enum _St { fresh, work, review, done }

Widget _status(BuildContext context, _St s) => switch (s) {
      _St.fresh => _Pill('Новое', AppColors.infoText(context)),
      _St.work => _Pill('В работе', Theme.of(context).colorScheme.primary),
      _St.review => _Pill('На проверке', AppColors.warningText(context)),
      _St.done => _Pill('Выполнено', AppColors.successText(context)),
    };

class _TaskRow extends StatelessWidget {
  final String title;
  final String who;
  final Color color;
  final String due;
  final _St st;
  final bool overdue;
  final String? sub;
  const _TaskRow(this.title, this.who, this.color, this.due, this.st, {this.overdue = false, this.sub});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Avatar(who, color, size: 36),
        const SizedBox(width: Space.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(
                child: Text(who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
              ),
              Text(' · ', style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
              Icon(Symbols.schedule_rounded,
                  size: 13, color: overdue ? AppColors.errorText(context) : _muted(context)),
              const SizedBox(width: 2),
              Text(due,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue ? AppColors.errorText(context) : _muted(context),
                      fontWeight: overdue ? FontWeight.w700 : null)),
            ]),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Symbols.subdirectory_arrow_right_rounded, size: 14, color: _muted(context)),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
                ),
              ]),
            ],
          ]),
        ),
        const SizedBox(width: Space.s),
        _status(context, st),
      ]),
    );
  }
}

class _TasksList extends StatelessWidget {
  const _TasksList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget group(String t, {Color? color}) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
          child: Text(t,
              style: theme.textTheme.labelLarge?.copyWith(color: color ?? _muted(context), fontWeight: FontWeight.w700)),
        );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: Space.l,
          title: const Text('Поручения'),
          actions: const [Icon(Symbols.search_rounded), SizedBox(width: 20), Icon(Symbols.view_week_rounded), SizedBox(width: 16)],
          bottom: const TabBar(tabs: [Tab(text: 'Я поручил · 6'), Tab(text: 'Мне поручили · 2')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          icon: const Icon(Symbols.add_rounded),
          label: const Text('Поручение'),
        ),
        body: ListView(children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              children: [
                FilterChip(label: const Text('Все'), selected: true, onSelected: (_) {}),
                const SizedBox(width: 6),
                FilterChip(label: const Text('Просрочено · 1'), selected: false, onSelected: (_) {}),
                const SizedBox(width: 6),
                FilterChip(label: const Text('На проверке · 1'), selected: false, onSelected: (_) {}),
                const SizedBox(width: 6),
                FilterChip(label: const Text('Отдел'), selected: false, onSelected: (_) {}),
              ],
            ),
          ),
          group('ПРОСРОЧЕНО', color: AppColors.errorText(context)),
          const _TaskRow('Согласовать договор поставки № 15', 'Борис Орлов', _blue, 'вчера', _St.work, overdue: true),
          group('НА ПРОВЕРКЕ'),
          const _TaskRow('Отчёт отдела за октябрь', 'Вера Белова', _teal, 'сегодня', _St.review,
              sub: 'ответ «Готово», 10:48 · проверить'),
          group('НА ЭТОЙ НЕДЕЛЕ'),
          const _TaskRow('Собрать даты отпусков отдела', 'Вера Белова', _teal, 'чт, 12 ноя', _St.work,
              sub: 'подзадачи 1 из 2'),
          const _TaskRow('Собрать даты отпусков отдела', 'Дмитрий Кузнецов', _orange, 'чт, 12 ноя', _St.fresh),
          const _TaskRow('Обновить договор аренды', 'Елена Соколова', _purple, 'пт, 13 ноя', _St.fresh),
          group('ПОЗЖЕ'),
          const _TaskRow('Инвентаризация склада', 'Дмитрий Кузнецов', _orange, '20 ноя', _St.work),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 96),
            child: Row(children: [
              Icon(Symbols.expand_more_rounded, color: _muted(context)),
              const SizedBox(width: 6),
              Text('Выполнено за неделю · 4', style: theme.textTheme.bodyMedium?.copyWith(color: _muted(context))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = theme.colorScheme.primary;
    Widget step(String t, {required bool done, bool current = false, bool last = false}) => Expanded(
          child: Column(children: [
            Row(children: [
              Expanded(child: Container(height: 2, color: done || current ? p : theme.colorScheme.outlineVariant)),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done ? p : (current ? p.withValues(alpha: 0.15) : null),
                  border: Border.all(color: done || current ? p : theme.colorScheme.outlineVariant, width: 2),
                  shape: BoxShape.circle,
                ),
                child: done ? const Icon(Symbols.check_rounded, size: 14, color: Colors.white) : null,
              ),
              Expanded(
                  child: Container(height: 2, color: last ? Colors.transparent : (done ? p : theme.colorScheme.outlineVariant))),
            ]),
            const SizedBox(height: 6),
            Text(t,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: current ? FontWeight.w700 : null, color: current ? p : _muted(context))),
          ]),
        );
    Widget info(IconData icon, String label, String value, {Color? color, bool link = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 7),
          child: Row(children: [
            Icon(icon, size: 20, color: _muted(context)),
            const SizedBox(width: Space.m),
            SizedBox(width: 112, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: _muted(context)))),
            Expanded(
              child: Text(value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: link ? AppColors.linkText(context) : color, fontWeight: FontWeight.w500)),
            ),
            if (link) Icon(Symbols.chevron_right_rounded, color: _muted(context)),
          ]),
        );
    Widget event(String when, String text, {IconData icon = Symbols.history_rounded, Color? color}) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 4, Space.l, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color ?? _muted(context)),
            const SizedBox(width: Space.m),
            SizedBox(width: 92, child: Text(when, style: theme.textTheme.bodySmall?.copyWith(color: _muted(context)))),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Symbols.arrow_back_rounded),
        title: const Text('Поручение'),
        actions: const [Icon(Symbols.edit_rounded), SizedBox(width: 20), Icon(Symbols.more_vert_rounded), SizedBox(width: 12)],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
          child: Row(children: [
            IconButton.outlined(onPressed: () {}, icon: const Icon(Symbols.notifications_rounded)),
            const SizedBox(width: Space.s),
            Expanded(child: FilledButton.tonal(onPressed: () {}, child: const Text('Вернуть'))),
            const SizedBox(width: Space.s),
            Expanded(child: FilledButton(onPressed: () {}, child: const Text('Принять'))),
          ]),
        ),
      ),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
          child: Text('Собрать даты отпусков отдела и внести в общий график', style: theme.textTheme.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          child: Row(children: [
            step('Новое', done: true),
            step('В работе', done: false, current: true),
            step('На проверке', done: false),
            step('Выполнено', done: false, last: true),
          ]),
        ),
        const SizedBox(height: Space.m),
        info(Symbols.person_rounded, 'Исполнитель', 'Вера Белова'),
        info(Symbols.event_rounded, 'Срок', 'чт, 12 ноября · через 3 дня'),
        info(Symbols.flag_rounded, 'Важность', 'обычная'),
        info(Symbols.mail_rounded, 'Из письма', '«График отпусков на 2027 год»', link: true),
        const Divider(height: Space.xl),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
          child: Text('Подзадачи · 1 из 2', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        _PickRow(true, 'Опросить группу продаж', 'Вера Белова · сделано 10 ноя',
            icon: Symbols.check_circle_rounded, iconColor: AppColors.successText(context)),
        const _PickRow(false, 'Опросить склад', 'Дмитрий Кузнецов · отдельное поручение',
            icon: Symbols.radio_button_unchecked_rounded),
        const Divider(height: Space.xl),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
          child: Text('История', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        event('9 ноя, 09:20', 'Поручено. Письмо отправлено Вере Беловой', icon: Symbols.send_rounded),
        event('9 ноя, 09:41', 'Ответ Веры «Принято, сделаю к среде» — статус «В работе»',
            icon: Symbols.reply_rounded, color: theme.colorScheme.primary),
        event('10 ноя, 16:05', 'Подзадача «Опросить группу продаж» выполнена', icon: Symbols.task_alt_rounded),
        event('11 ноя, 09:00', 'Напоминание мне: срок завтра', icon: Symbols.notifications_rounded),
        const SizedBox(height: Space.l),
      ]),
    );
  }
}

class _AssigneeView extends StatelessWidget {
  const _AssigneeView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = theme.colorScheme.primary;
    return _MailMock(
      from: 'Иван Петров',
      color: _blue,
      subject: 'Поручение: собрать даты отпусков отдела — до 12.11',
      when: 'сегодня, 09:20',
      banner: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          color: p.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Symbols.assignment_ind_rounded, color: p),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text('Поручение от Ивана Петрова',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            _status(context, _St.fresh),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text('Срок: чт, 12 ноября · важность обычная',
                style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
          ),
          const SizedBox(height: Space.s),
          Wrap(spacing: 6, runSpacing: 6, children: [
            FilledButton.icon(
                onPressed: () {}, icon: const Icon(Symbols.play_arrow_rounded, size: 18), label: const Text('Принять')),
            OutlinedButton.icon(
                onPressed: () {}, icon: const Icon(Symbols.check_rounded, size: 18), label: const Text('Готово')),
            OutlinedButton.icon(
                onPressed: () {}, icon: const Icon(Symbols.help_rounded, size: 18), label: const Text('Вопрос')),
          ]),
          const SizedBox(height: 4),
          Text('Ответ уйдёт письмом — статус у Ивана обновится сам. В «Моём дне» — задача со сроком.',
              style: theme.textTheme.bodySmall?.copyWith(color: _muted(context))),
        ]),
      ),
      body: 'Вера, добрый день!\n\n'
          'Прошу собрать даты отпусков отдела и внести в общий график.\n'
          'Срок: четверг, 12 ноября.\n\n'
          'Исходное письмо: «График отпусков на 2027 год» (Анна Смирнова, 9 ноября).\n\n'
          '—\n'
          'Поручение из Ogneliss Mail. В любой почте можно просто ответить: '
          '«Принято», «Готово» или вопросом.',
    );
  }
}

void main() {
  testWidgets('макет: шкала дня', (tester) async {
    await _mock(tester, 'day_timeline', const _TimelineScreen());
    await _mock(tester, 'day_timeline_dark', const _TimelineScreen(), dark: true);
  });
  testWidgets('макет: перетаскивание задачи на шкалу', (tester) async {
    await _mock(tester, 'day_drag', const _TimelineScreen(dragging: true));
  });
  testWidgets('макет: план дня утром', (tester) async {
    await _mock(tester, 'day_morning', const _MorningPlan());
  });
  testWidgets('макет: итоги вечером', (tester) async {
    await _mock(tester, 'day_evening', const _EveningReview());
  });
  testWidgets('макет: шкала на планшете', (tester) async {
    await _mock(tester, 'day_tablet', const _TabletDay(), size: _tablet);
  });
  testWidgets('макет: поручить из письма', (tester) async {
    await _mock(tester, 'task_assign', const _AssignSheet());
  });
  testWidgets('макет: список поручений', (tester) async {
    await _mock(tester, 'task_list', const _TasksList());
  });
  testWidgets('макет: карточка поручения', (tester) async {
    await _mock(tester, 'task_card', const _TaskCard());
  });
  testWidgets('макет: поручение у исполнителя', (tester) async {
    await _mock(tester, 'task_assignee', const _AssigneeView());
  });
}
