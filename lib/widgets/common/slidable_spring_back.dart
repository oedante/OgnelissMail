// lib/widgets/common/slidable_spring_back.dart
// Строка ленты с одним действием на стороне свайпа не остаётся полуоткрытой
// (1.14.0, замечание владельца 05.11.2026: «Свайпы зависают на середине. И
// так у нескольких писем.»).
//
// Почему зависали. У стороны с одним действием панель занимает 28 % ширины
// строки, а действие срабатывает, если отпустить дальше 40 %. flutter_slidable
// в обоих промежуточных случаях ОТКРЫВАЕТ панель и оставляет её открытой:
//  · отпустили между 28 % и 40 % — DismissiblePane не дотянули до порога, и он
//    вызывает openCurrentActionPane();
//  · отпустили до 28 %, но пальцем «вперёд» или дальше половины панели —
//    ActionPane открывает панель по своим порогам;
//  · протянули за порог и вернули пальцем назад — снова открытие.
// Строка застывала со значком сбоку; групповое автозакрытие в ленте не было
// подключено, поэтому так оставалось сразу несколько писем.
//
// Что делает этот виджет: стоит внутри панели с одним действием и, когда палец
// отпущен и действие не сработает, возвращает строку на место. Кнопку в
// открытой панели нажимать не нужно — при одном действии весь смысл свайпа в
// том, чтобы протянуть до порога. Две кнопки (выбор действия) открываются, как
// раньше, — их закрывает SlidableAutoCloseBehavior ленты.

import 'package:flutter/widgets.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class SlidableSpringBack extends StatefulWidget {
  /// Порог полного свайпа (DismissiblePane.dismissThreshold): дальше него
  /// действие выполняется — строку здесь не трогаем.
  final double dismissThreshold;
  final Widget child;

  const SlidableSpringBack({super.key, required this.dismissThreshold, required this.child});

  @override
  State<SlidableSpringBack> createState() => _SlidableSpringBackState();
}

class _SlidableSpringBackState extends State<SlidableSpringBack> {
  SlidableController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = Slidable.of(context);
    if (identical(c, _controller)) return;
    _detach();
    _controller = c;
    // Слушатели панели (ActionPane, DismissiblePane) добавлены раньше — наш
    // вызывается после них и отменяет начатое ими открытие.
    c?.endGesture.addListener(_onEndGesture);
    c?.animation.addStatusListener(_onStatus);
  }

  void _detach() {
    _controller?.endGesture.removeListener(_onEndGesture);
    _controller?.animation.removeStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  /// Палец отпущен до порога: DismissiblePane действие не выполнит (ему
  /// нужен порог), а библиотека откроет панель — возвращаем строку сразу.
  /// За порогом решает DismissiblePane: выполнить действие, увести строку или
  /// (палец шёл назад) открыть панель — последний случай ловит [_onStatus].
  void _onEndGesture() {
    final c = _controller;
    if (c == null || c.endGesture.value == null) return;
    if (springsBackAt(c.animation.value, widget.dismissThreshold)) c.close();
  }

  /// Страховка: панель всё-таки доехала до открытого положения (быстрый
  /// жест, повтор жеста библиотекой) — закрыть. Полный уход строки (1.0) —
  /// это выполнение действия, его не трогаем.
  void _onStatus(AnimationStatus status) {
    final c = _controller;
    if (c == null || status != AnimationStatus.completed) return;
    final v = c.animation.value;
    if (v > 0 && v < widget.dismissThreshold) c.close();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Вернётся ли строка на место сразу, если отпустить её в положении
/// [position] (доля ширины строки).
@visibleForTesting
bool springsBackAt(double position, double dismissThreshold) => position > 0 && position < dismissThreshold;
