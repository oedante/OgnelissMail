// lib/widgets/ui/wheel_pickers.dart
// Выбор даты и времени «барабанами» в нижней шторке.
//
// Замечание владельца (10.10.2026): стандартные окна Material (сетка
// календаря и циферблат часов) неудобны — крупные цифры, циферблат
// промахивается, а дата и время выбираются в двух окнах подряд. Теперь —
// одна шторка: прокручиваемые барабаны (дата, часы, минуты; с 1.6.2 —
// свои, широкие, строки 52 dp, выбор и нажатием; с 1.6.49+95 — 60 dp,
// крупные цифры, у каждой колонки свой барабан, щелчок на шаге), сверху —
// выбранное значение словами, с днём недели («Понедельник, 12 октября,
// 14:30»), чтобы не ошибиться днём. Быстрые кнопки — «Сегодня», «Завтра».
//
// 1.6.49: значок «Месяц» рядом с выбранным — дата сеткой месяца вместо
// барабана (дату через месяц-другой барабаном крутить долго; листать месяцы
// — стрелками или проведением по сетке; выбор вида запоминается до
// перезапуска). Быстрые варианты даты и времени сразу ([presets]: «Через
// час», «Завтра в 9:00») — чипами вместо «Сегодня/Завтра».
//
// Все выборы даты и времени в приложении открываются через эти функции.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../common/app_sheet.dart';
import 'section_band.dart';

enum WheelMode { date, time, dateTime }

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Дата (без времени): день · месяц · год.
Future<DateTime?> showWheelDatePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  String? title,
}) =>
    _show(context, mode: WheelMode.date, initial: initial, first: first, last: last, title: title);

/// Дата и время в одной шторке. [presets] — быстрые варианты (подпись и
/// дата со временем) чипами над барабанами.
Future<DateTime?> showWheelDateTimePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  String? title,
  int minuteInterval = 5,
  List<(String, DateTime)> presets = const [],
}) =>
    _show(context,
        mode: WheelMode.dateTime,
        initial: initial,
        first: first,
        last: last,
        title: title,
        minuteInterval: minuteInterval,
        presets: presets);

/// Только время (часы · минуты).
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  String? title,
  int minuteInterval = 1,
}) async {
  final now = DateTime.now();
  final r = await _show(context,
      mode: WheelMode.time,
      initial: DateTime(now.year, now.month, now.day, initial.hour, initial.minute),
      title: title,
      minuteInterval: minuteInterval);
  return r == null ? null : TimeOfDay(hour: r.hour, minute: r.minute);
}

Future<DateTime?> _show(
  BuildContext context, {
  required WheelMode mode,
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  String? title,
  int minuteInterval = 1,
  List<(String, DateTime)> presets = const [],
}) {
  return showAppSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WheelSheet(
      mode: mode,
      initial: initial,
      first: first,
      last: last,
      title: title,
      minuteInterval: minuteInterval,
      presets: presets,
    ),
  );
}

class _WheelSheet extends StatefulWidget {
  final WheelMode mode;
  final DateTime initial;
  final DateTime? first;
  final DateTime? last;
  final String? title;
  final int minuteInterval;
  final List<(String, DateTime)> presets;

  const _WheelSheet({
    required this.mode,
    required this.initial,
    required this.first,
    required this.last,
    required this.title,
    required this.minuteInterval,
    this.presets = const [],
  });

  @override
  State<_WheelSheet> createState() => _WheelSheetState();
}

class _WheelSheetState extends State<_WheelSheet> {
  late DateTime _value = _normalize(widget.initial);

  /// Дата сеткой месяца (1.6.49). Выбор вида — до перезапуска приложения.
  static bool _gridPref = false;
  late bool _grid = _gridPref && widget.mode != WheelMode.time;

  /// Месяц, показанный сеткой (первое число).
  late DateTime _gridMonth = DateTime(_value.year, _value.month);

  // Барабаны (1.6.2, замечание 13.10.2026: «барабаны удобны, но слишком
  // узкие — боишься промахнуться»). Свои вместо CupertinoDatePicker: строки
  // высотой 52 (было 32), колонки во всю ширину шторки, крупные цифры,
  // нажатие на строку выбирает её, полоса выбора видна.
  // 1.6.49+95 (замечание владельца 20.10.2026: «барабаны не очень удобны,
  // можно крупнее»): строки 60 (было 52), крупные цифры, щелчок вибрацией на
  // каждом шаге.
  // 1.8.12 (замечание 30.10.2026: «давай улучшим барабаны»): как в iOS —
  // одна полоса выбора через все колонки вместо рамки у каждой колонки,
  // настоящий изгиб барабана, центральная строка чуть увеличена лупой,
  // строки к краям затухают; колонки по бокам слегка повёрнуты к центру.
  // Размер строк и цифр — прежний, крупный.
  // Без лупы (проверка размеров 1.8.12): лупа увеличивала строку от центра
  // колонки, и выбранная «Сегодня» стояла правее соседних строк — выбранная
  // строка чуть крупнее сама.
  static const _extent = 60.0;
  static const _visible = 5;
  static const _font = 24.0;
  static const _fontSelected = 27.0;
  // Слова (день недели, месяц) — чуть мельче чисел: «Ср, 30 сент.» целиком.
  static const _fontWords = 20.0;
  static const _fontWordsSelected = 22.0;

  late final DateTime _base = _dateBase();
  late final int _dayCount = _dateCount();
  final _dateCtl = <String, FixedExtentScrollController>{};

  int get _interval => widget.mode == WheelMode.date ? 1 : widget.minuteInterval;

  DateTime? get _min {
    final f = widget.first;
    if (f == null) return null;
    return widget.mode == WheelMode.date ? DateTime(f.year, f.month, f.day) : f;
  }

  DateTime? get _max {
    final l = widget.last;
    if (l == null) return null;
    return widget.mode == WheelMode.date ? DateTime(l.year, l.month, l.day, 23, 59) : l;
  }

  /// Первый день колонки дат: граница или два года назад.
  DateTime _dateBase() {
    final mn = _min;
    final from = mn ?? DateTime(widget.initial.year - 2, widget.initial.month, widget.initial.day);
    return DateTime(from.year, from.month, from.day);
  }

  int _dateCount() {
    final mx = _max;
    final to = mx ?? DateTime(widget.initial.year + 3, widget.initial.month, widget.initial.day);
    return DateTime(to.year, to.month, to.day).difference(_base).inDays + 1;
  }

  /// Значение в допустимых пределах и кратное шагу минут.
  DateTime _normalize(DateTime v) {
    var x = widget.mode == WheelMode.date ? DateTime(v.year, v.month, v.day) : v;
    if (_interval > 1) {
      final m = (x.minute / _interval).round() * _interval;
      x = DateTime(x.year, x.month, x.day, x.hour).add(Duration(minutes: m));
    }
    x = DateTime(x.year, x.month, x.day, x.hour, x.minute);
    final mn = _min, mx = _max;
    if (mn != null && x.isBefore(mn)) {
      x = mn;
      if (_interval > 1 && x.minute % _interval != 0) {
        x = DateTime(x.year, x.month, x.day, x.hour, x.minute - x.minute % _interval)
            .add(Duration(minutes: _interval));
      }
    }
    if (mx != null && x.isAfter(mx)) {
      x = DateTime(mx.year, mx.month, mx.day, mx.hour, mx.minute - mx.minute % _interval);
    }
    return x;
  }

  FixedExtentScrollController _ctl(String key, int index) =>
      _dateCtl.putIfAbsent(key, () => FixedExtentScrollController(initialItem: index));

  int get _dayIndex => DateTime(_value.year, _value.month, _value.day).difference(_base).inDays;

  /// Перевести барабаны на [_value] (быстрые кнопки, поправка по пределам).
  void _syncWheels() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncing = true;
      void go(String key, int index) {
        final c = _dateCtl[key];
        if (c == null || !c.hasClients) return;
        final cur = c.selectedItem;
        // Колонка по кругу (часы, минуты): ближайший путь к нужной строке.
        final n = key == 'h' ? 24 : (key == 'm' ? 60 ~/ _interval : 0);
        var target = index;
        if (n > 0) target = cur + (((index - cur % n) + n + n ~/ 2) % n) - n ~/ 2;
        // Переход сразу (не анимацией): при прокрутке через десятки строк
        // каждая промежуточная меняла бы значение.
        if (target != cur) c.jumpToItem(target);
      }

      go('d', _dayIndex);
      go('dd', _value.day - 1);
      go('mo', _value.month - 1);
      go('y', _value.year - _base.year);
      go('h', _value.hour);
      go('m', _value.minute ~/ _interval);
      _syncing = false;
    });
  }

  /// Барабаны переводятся программно — их события не меняют значение.
  bool _syncing = false;

  void _set(DateTime v) {
    final n = _normalize(v);
    if (n == _value) return;
    setState(() => _value = n);
    // Поправка по пределам или короткому месяцу — барабаны к значению
    // (go() ничего не делает, если барабан уже на месте).
    _syncWheels();
  }

  void _jump(DateTime day) {
    setState(() {
      _value = _normalize(DateTime(day.year, day.month, day.day, _value.hour, _value.minute));
      _gridMonth = DateTime(_value.year, _value.month);
    });
    _syncWheels();
  }

  /// Быстрый вариант: дата и время сразу.
  void _preset(DateTime at) {
    setState(() {
      _value = _normalize(at);
      _gridMonth = DateTime(_value.year, _value.month);
    });
    _syncWheels();
  }

  void _toggleGrid() {
    setState(() {
      _grid = !_grid;
      _gridPref = _grid;
      _gridMonth = DateTime(_value.year, _value.month);
    });
    // Барабаны дат создаются заново — на текущее значение. Старые
    // контроллеры освобождаются после кадра, когда их барабаны уже сняты.
    final old = [for (final k in const ['d', 'dd', 'mo', 'y']) ?_dateCtl.remove(k)];
    if (old.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in old) {
          c.dispose();
        }
      });
    }
    _syncWheels();
  }

  @override
  void dispose() {
    for (final c in _dateCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _wheel({
    required String key,
    required int count,
    required int selected,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
    bool looping = false,
    int flex = 1,
    TextAlign align = TextAlign.center,
    bool words = false,
    double offAxis = 0,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ctl = _ctl(key, selected);
    Widget item(int i) {
      final idx = looping ? i % count : i;
      final sel = idx == (looping ? (ctl.hasClients ? ctl.selectedItem % count : selected) : selected);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Нажатие на строку — выбрать её (не только прокрутка).
        onTap: () => ctl.animateToItem(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic),
        child: Container(
          alignment: align == TextAlign.center
              ? Alignment.center
              : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Text(
            label(idx),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: words ? (sel ? _fontWordsSelected : _fontWords) : (sel ? _fontSelected : _font),
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
              color: sel ? scheme.onSurface : scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }

    // Ключ — барабан не пересоздаётся при смене вида даты (сетка/барабан):
    // иначе часы и минуты встали бы на начальное значение.
    return Expanded(
      key: ValueKey('wheel_$key'),
      flex: flex,
      child: ListWheelScrollView.useDelegate(
        controller: ctl,
        itemExtent: _extent,
        physics: const FixedExtentScrollPhysics(),
        // Изгиб барабана: строки у краёв уходят назад и сжимаются.
        diameterRatio: 1.5,
        perspective: 0.003,
        offAxisFraction: offAxis,
        overAndUnderCenterOpacity: 0.55,
        onSelectedItemChanged: (i) {
          if (_syncing) return;
          // Щелчок на каждом шаге — как у механического барабана.
          unawaited(HapticFeedback.selectionClick());
          onChanged(looping ? i % count : i);
        },
        childDelegate: looping
            ? ListWheelChildLoopingListDelegate(children: [for (var i = 0; i < count; i++) item(i)])
            : ListWheelChildBuilderDelegate(childCount: count, builder: (_, i) => item(i)),
      ),
    );
  }

  /// Промежуток между барабанами.
  static const _gap = SizedBox(width: Space.s);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loc = l10n.localeCode;
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat || loc != 'en';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final gridMode = _grid && widget.mode != WheelMode.time;

    // Выбранное — словами, с днём недели.
    final dateText = _cap(DateFormat('EEEE, d MMMM${_value.year != now.year ? ' y' : ''}', loc).format(_value));
    final timeText = use24 ? DateFormat('HH:mm').format(_value) : DateFormat('h:mm a', loc).format(_value);
    final summary = switch (widget.mode) {
      WheelMode.date => dateText,
      WheelMode.time => timeText,
      WheelMode.dateTime => '$dateText, $timeText',
    };
    final day = DateTime(_value.year, _value.month, _value.day);
    final rel = day == today
        ? l10n.tr('today')
        : day == today.add(const Duration(days: 1))
            ? l10n.tr('tomorrow')
            : null;

    bool allowed(DateTime d) {
      final mn = _min, mx = _max;
      final endOfDay = DateTime(d.year, d.month, d.day, 23, 59);
      if (mn != null && endOfDay.isBefore(mn)) return false;
      if (mx != null && DateTime(d.year, d.month, d.day).isAfter(mx)) return false;
      return true;
    }

    bool inRange(DateTime t) {
      final mn = _min, mx = _max;
      return (mn == null || !t.isBefore(mn)) && (mx == null || !t.isAfter(mx));
    }

    final quick = <(String, DateTime)>[
      (l10n.tr('today'), today),
      (l10n.tr('tomorrow'), today.add(const Duration(days: 1))),
      // Ближайший понедельник (если сегодня не понедельник).
      if (now.weekday != DateTime.monday)
        (_cap(DateFormat('EEEE', loc).format(today.add(Duration(days: 8 - now.weekday)))),
            today.add(Duration(days: 8 - now.weekday))),
    ].where((q) => allowed(q.$2)).toList();
    // Быстрые варианты даты и времени (1.6.49) — вместо «Сегодня/Завтра».
    final presets = widget.mode == WheelMode.dateTime
        ? [for (final p in widget.presets) if (inRange(p.$2)) p]
        : const <(String, DateTime)>[];

    final two = NumberFormat('00');
    final columns = <Widget>[];
    // Часы и минуты.
    void time() {
      // Колонки по бокам слегка повёрнуты к центру (как в iOS); рядом с
      // датой время — правая часть общего барабана.
      final withDate = widget.mode == WheelMode.dateTime && !gridMode;
      columns.add(_wheel(
        key: 'h',
        offAxis: withDate ? 0.05 : -0.1,
        // Часы и минуты — вдвое шире (1.6.8, замечание владельца: узкие
        // колонки неудобно крутить пальцем).
        flex: 2,
        count: 24,
        selected: _value.hour,
        looping: true,
        label: (h) => use24 ? two.format(h) : '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? ' AM' : ' PM'}',
        onChanged: (h) => _set(DateTime(_value.year, _value.month, _value.day, h, _value.minute)),
      ));
      columns.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Text(':', style: theme.textTheme.titleLarge?.copyWith(fontSize: _fontSelected, fontWeight: FontWeight.w600)),
      ));
      columns.add(_wheel(
        key: 'm',
        offAxis: withDate ? 0.15 : 0.1,
        flex: 2,
        count: 60 ~/ _interval,
        selected: _value.minute ~/ _interval,
        looping: true,
        label: (i) => two.format(i * _interval),
        onChanged: (i) => _set(DateTime(_value.year, _value.month, _value.day, _value.hour, i * _interval)),
      ));
    }

    switch (widget.mode) {
      case WheelMode.date:
        if (!gridMode) {
          final years = (_base.add(Duration(days: _dayCount - 1)).year - _base.year) + 1;
          final daysInMonth = DateTime(_value.year, _value.month + 1, 0).day;
          columns
            ..add(_wheel(
              key: 'dd',
              offAxis: -0.15,
              count: daysInMonth,
              selected: _value.day - 1,
              flex: 2,
              label: (i) => '${i + 1}',
              onChanged: (i) => _set(DateTime(_value.year, _value.month, i + 1)),
            ))
            ..add(_gap)
            ..add(_wheel(
              key: 'mo',
              count: 12,
              selected: _value.month - 1,
              flex: 4,
              words: true,
              label: (i) => _cap(DateFormat('LLLL', loc).format(DateTime(2000, i + 1))),
              onChanged: (i) {
                final last = DateTime(_value.year, i + 2, 0).day;
                _set(DateTime(_value.year, i + 1, _value.day > last ? last : _value.day));
              },
            ))
            ..add(_gap)
            ..add(_wheel(
              key: 'y',
              offAxis: 0.15,
              count: years,
              selected: _value.year - _base.year,
              flex: 3,
              label: (i) => '${_base.year + i}',
              onChanged: (i) {
                final y = _base.year + i;
                final last = DateTime(y, _value.month + 1, 0).day;
                _set(DateTime(y, _value.month, _value.day > last ? last : _value.day));
              },
            ));
        }
      case WheelMode.time:
        columns.add(const Spacer());
        time();
        columns.add(const Spacer());
      case WheelMode.dateTime:
        if (gridMode) {
          // Дата — сеткой выше, здесь только время.
          columns.add(const Spacer());
          time();
          columns.add(const Spacer());
        } else {
          columns.add(_wheel(
            key: 'd',
            offAxis: -0.12,
            count: _dayCount,
            selected: _dayIndex.clamp(0, _dayCount - 1),
            flex: 5,
            // К времени, как в iOS: под лупой (она увеличивает от центра)
            // строка, прижатая влево, обрезалась.
            align: TextAlign.right,
            words: true,
            label: (i) {
              final d = _base.add(Duration(days: i));
              if (d == today) return l10n.tr('today');
              return _cap(DateFormat(d.year == now.year ? 'EE, d MMM' : 'd MMM y', loc).format(d));
            },
            onChanged: (i) {
              final d = _base.add(Duration(days: i));
              _set(DateTime(d.year, d.month, d.day, _value.hour, _value.minute));
            },
          ));
          columns.add(_gap);
          time();
        }
    }

    // Под сеткой месяца — три строки времени вместо пяти: шторка не
    // вырастает выше экрана.
    final visible = gridMode ? 3 : _visible;
    final scheme = theme.colorScheme;
    final picker = columns.isEmpty
        ? null
        : SizedBox(
            height: _extent * visible,
            child: Stack(children: [
              // Одна полоса выбора через все колонки (как в iOS).
              Center(
                child: Container(
                  height: _extent,
                  // Края полосы — по краям кнопок «Отмена» и «Готово».
                  margin: const EdgeInsets.symmetric(horizontal: Space.l),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              // Строки к верху и низу затухают — глубина барабана.
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                  stops: [0, 0.22, 0.78, 1],
                ).createShader(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                  child: Row(children: columns),
                ),
              ),
            ]),
          );

    final canGrid = widget.mode != WheelMode.time;
    return MediaQuery(
      // Барабаны не растут с крупным шрифтом системы — иначе цифры
      // наезжают друг на друга (подпись сверху растёт как обычно).
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.title != null) SectionBand(title: widget.title!),
          Padding(
            padding: EdgeInsets.only(
                left: canGrid ? Space.xxl + Space.l : Space.l, top: Space.s, right: canGrid ? Space.s : Space.l),
            child: Row(children: [
              // Узкий экран (320 dp) — строка уменьшается, а не переносит
              // время на вторую строку.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(summary,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
              // Дата сеткой месяца или барабаном (1.6.49).
              if (canGrid)
                IconButton(
                  tooltip: l10n.tr(gridMode ? 'pickerWheels' : 'pickerMonth'),
                  isSelected: gridMode,
                  icon: const Icon(AppIcons.calendar_month),
                  selectedIcon: Icon(AppIcons.calendar_month, fill: 1, color: theme.colorScheme.primary),
                  onPressed: _toggleGrid,
                ),
            ]),
          ),
          if (rel != null && widget.mode != WheelMode.time)
            Text(rel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (presets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: Wrap(alignment: WrapAlignment.center, spacing: Space.s, runSpacing: Space.xs, children: [
                for (final q in presets)
                  ChoiceChip(
                    label: Text(q.$1),
                    showCheckmark: false,
                    // Не меньше 48 dp под палец (у компактных чипов — 32).
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: _value == _normalize(q.$2),
                    onSelected: (_) => _preset(q.$2),
                  ),
              ]),
            )
          else if (widget.mode != WheelMode.time && quick.isNotEmpty && !gridMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: Wrap(alignment: WrapAlignment.center, spacing: Space.s, children: [
                for (final q in quick)
                  ChoiceChip(
                    label: Text(q.$1),
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    selected: day == q.$2,
                    onSelected: (_) => _jump(q.$2),
                  ),
              ]),
            ),
          const SizedBox(height: Space.s),
          if (gridMode)
            _MonthGrid(
              month: _gridMonth,
              selected: day,
              today: today,
              allowed: allowed,
              canPrev: _min == null || DateTime(_min!.year, _min!.month).isBefore(_gridMonth),
              canNext: _max == null || DateTime(_max!.year, _max!.month).isAfter(_gridMonth),
              onMonth: (m) => setState(() => _gridMonth = m),
              onPick: _jump,
            ),
          if (picker != null) picker,
          const SizedBox(height: Space.s),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
            child: Row(children: [
              // Кнопки — во всю высоту пальца (1.6.49+95).
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Sizes.tapTarget + Space.xs)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Sizes.tapTarget + Space.xs)),
                  onPressed: () => Navigator.of(context).pop(_value),
                  child: Text(l10n.tr('done')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Месяц сеткой (1.6.49): заголовок со стрелками, дни недели, числа.
/// Сегодня — кольцом, выбранный день — заливкой; дни вне пределов — бледные.
/// Проведение по сетке влево-вправо — соседний месяц.
class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final bool Function(DateTime) allowed;
  final bool canPrev;
  final bool canNext;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onPick;

  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.allowed,
    required this.canPrev,
    required this.canNext,
    required this.onMonth,
    required this.onPick,
  });

  static const _cell = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final loc = l10n.localeCode;
    // 0 — воскресенье (как у MaterialLocalizations).
    final firstDow = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final lead = (month.weekday % 7 - firstDow + 7) % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final prev = DateTime(month.year, month.month - 1);
    final next = DateTime(month.year, month.month + 1);

    Widget dayCell(int index) {
      final n = index - lead + 1;
      if (n < 1 || n > days) return const SizedBox(height: _cell);
      final d = DateTime(month.year, month.month, n);
      final ok = allowed(d);
      final sel = d == selected;
      final isToday = d == today;
      final color = sel
          ? scheme.onPrimary
          : !ok
              ? scheme.onSurface.withValues(alpha: 0.3)
              : isToday
                  ? scheme.primary
                  : scheme.onSurface;
      return Semantics(
        button: ok,
        selected: sel,
        label: DateFormat.yMMMMEEEEd(loc).format(d),
        excludeSemantics: true,
        child: InkResponse(
          onTap: ok ? () => onPick(d) : null,
          radius: _cell / 2,
          child: SizedBox(
            height: _cell,
            child: Center(
              child: Container(
                width: _cell - Space.xs,
                height: _cell - Space.xs,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: sel ? scheme.primary : null,
                  border: isToday && !sel ? Border.all(color: scheme.primary) : null,
                ),
                child: Text('$n',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: sel || isToday ? FontWeight.w600 : FontWeight.w400,
                    )),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200 && canNext) onMonth(next);
        if (v > 200 && canPrev) onMonth(prev);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(
              tooltip: _cap(DateFormat('LLLL', loc).format(prev)),
              icon: const Icon(AppIcons.chevron_left),
              onPressed: canPrev ? () => onMonth(prev) : null,
            ),
            Expanded(
              child: Text(_cap(DateFormat('LLLL y', loc).format(month)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: _cap(DateFormat('LLLL', loc).format(next)),
              icon: const Icon(AppIcons.chevron_right),
              onPressed: canNext ? () => onMonth(next) : null,
            ),
          ]),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  // 1 января 2023 — воскресенье.
                  _cap(DateFormat('EE', loc).format(DateTime(2023, 1, 1 + (firstDow + i) % 7))),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ]),
          const SizedBox(height: Space.xs),
          for (var r = 0; r < rows; r++)
            Row(children: [
              for (var c = 0; c < 7; c++) Expanded(child: dayCell(r * 7 + c)),
            ]),
        ]),
      ),
    );
  }
}
