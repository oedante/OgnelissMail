// lib/widgets/common/peek_card.dart
// Карточка по удержанию «как в Telegram» (1.6.29 — письма) и меню по
// удержанию кнопки (1.6.47). С 1.6.47 — общая: письма, письма в беседе,
// встречи календаря, контакты, кнопка «Написать».
//
// Фон затемняется и размывается, карточка «приподнимается» на месте строки
// (или у пальца), под ней — круглые кнопки быстрых действий; касание
// карточки — открыть; касание мимо — закрыть. Палец после удержания можно не
// отпускать: провести на кнопку и отпустить ([HoldPointer]).
//
// Место карточки считается по её настоящей высоте (CustomSingleChildLayout):
// раньше высота бралась «на глаз» (300), и высокая карточка (вложения,
// время встречи) уходила за нижний край.
//
// «Ещё» (1.6.49+95, замечание владельца 20.10.2026: «не нравится
// выезжающая панель при нажатии «Ещё»»): все действия разворачиваются здесь
// же, под кнопками, — по группам ([PeekGroup]: «Ответ», «Отметки», «Создать»,
// «Переместить»…), а не шторкой снизу. Повторное нажатие — свернуть. С 1.7.0
// группы — рядами круглых кнопок, как ряд под карточкой (столбик пунктов
// выталкивал карточку вверх). Карточки по удержанию — у писем, встреч,
// контактов, заметок и задач.

import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import 'quick_long_press.dart';

/// Кнопка под карточкой (или пункт меню).
class PeekAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Значок с заливкой (отметка уже стоит: «На контроле», флаг).
  final bool filled;

  /// Цвет значка (ответ на встречу: принять, под вопросом, отклонить);
  /// null — обычный.
  final Color? color;

  /// Карточка не закрывается (кнопка «Ещё» — развернуть список).
  final bool keepOpen;

  const PeekAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.color,
    this.keepOpen = false,
  });
}

/// Группа действий в развёрнутом «Ещё» (1.6.49+95). [title] — серая подпись
/// над группой; null — без подписи.
class PeekGroup {
  final String? title;
  final List<PeekAction> items;
  const PeekGroup({this.title, required this.items});
}

/// Показать карточку над [anchor] (глобальные координаты строки; null — по
/// центру экрана). [card] — содержимое карточки (поля внутри — свои).
/// [more] — все действия по группам: последней кнопкой ряда становится
/// «Ещё» ([moreLabel]), нажатие разворачивает их под кнопками. [moreOpen] —
/// группы развёрнуты сразу и без кнопки «Ещё» (1.8.8: «Ещё» в письме —
/// эта же карточка, а не шторка снизу).
Future<void> showPeekCard(
  BuildContext context, {
  required Rect? anchor,
  required Widget card,
  required List<PeekAction> actions,
  VoidCallback? onOpen,
  List<PeekGroup> more = const [],
  String moreLabel = '…',
  bool moreOpen = false,
}) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _PeekOverlay(
        anchor: anchor,
        card: card,
        actions: actions,
        onOpen: onOpen,
        more: more,
        moreLabel: moreLabel,
        moreOpen: moreOpen),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// Прямоугольник строки на экране по её context; null — не на экране.
Rect? peekAnchorOf(BuildContext? ctx) {
  final ro = (ctx != null && ctx.mounted) ? ctx.findRenderObject() : null;
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
  return ro.localToGlobal(Offset.zero) & ro.size;
}

/// Место у пальца, когда строка не знает своего места (встречи календаря):
/// полоса во всю ширину экрана на высоте пальца.
Rect? peekAnchorAtFinger(BuildContext context) {
  final at = HoldPointer.instance.pressedAt;
  if (at == null) return null;
  final w = MediaQuery.sizeOf(context).width;
  return Rect.fromLTWH(0, at.dy - Sizes.mailRow / 2, w, Sizes.mailRow);
}

/// Фон: затемнение и размытие; касание — закрыть.
class _PeekBackdrop extends StatelessWidget {
  const _PeekBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: ColoredBox(color: Colors.black.withValues(alpha: dark ? 0.45 : 0.28)),
        ),
      ),
    );
  }
}

/// Поля экрана для карточки: строка состояния, панель навигации, клавиатура.
EdgeInsets _safe(MediaQueryData mq) => EdgeInsets.fromLTRB(
      Space.m,
      mq.padding.top + Space.s,
      Space.m,
      mq.padding.bottom + mq.viewInsets.bottom + Space.s,
    );

class _PeekOverlay extends StatefulWidget {
  final Rect? anchor;
  final Widget card;
  final List<PeekAction> actions;
  final VoidCallback? onOpen;
  final List<PeekGroup> more;
  final String moreLabel;
  final bool moreOpen;

  const _PeekOverlay({
    required this.anchor,
    required this.card,
    required this.actions,
    this.onOpen,
    this.more = const [],
    this.moreLabel = '…',
    this.moreOpen = false,
  });

  @override
  State<_PeekOverlay> createState() => _PeekOverlayState();
}

class _PeekOverlayState extends State<_PeekOverlay> {
  late bool _expanded = widget.moreOpen;
  final _scroll = ScrollController();
  final _listKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle() {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _expanded = !_expanded);
    if (!_expanded) return;
    // Список — целиком на экране: карточка поднимается сама (место по
    // высоте), а если всё не помещается — прокрутка к списку.
    final reduce = MediaQuery.of(context).disableAnimations;
    unawaited(Future<void>.delayed(reduce ? Duration.zero : const Duration(milliseconds: 220), () {
      final ctx = _listKey.currentContext;
      if (!mounted || ctx == null || !ctx.mounted) return;
      unawaited(Scrollable.ensureVisible(ctx,
          alignment: 1.0, duration: reduce ? Duration.zero : const Duration(milliseconds: 180)));
    }));
  }

  @override
  Widget build(BuildContext context) {
    final insets = _safe(MediaQuery.of(context));
    final open = widget.onOpen;
    final reduce = MediaQuery.of(context).disableAnimations;
    final actions = [
      ...widget.actions,
      if (widget.more.isNotEmpty && !widget.moreOpen)
        PeekAction(
          icon: _expanded ? AppIcons.expand_less : AppIcons.more_horiz,
          label: widget.moreLabel,
          keepOpen: true,
          onTap: _toggle,
        ),
    ];
    return Stack(
      children: [
        const _PeekBackdrop(),
        Positioned.fill(
          child: Padding(
            padding: insets,
            child: CustomSingleChildLayout(
              delegate: _PeekLayout(anchor: widget.anchor, insets: insets),
              child: _Lift(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: AppColors.cardFill(context),
                        elevation: 12,
                        shadowColor: Colors.black.withValues(alpha: 0.35),
                        borderRadius: Radii.cardAll,
                        clipBehavior: Clip.antiAlias,
                        // Касание карточки — открыть (1.6.46).
                        child: InkWell(
                          onTap: open == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  open();
                                },
                          child: widget.card,
                        ),
                      ),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: Space.m),
                        PeekActionsRow(
                            actions: actions, highlight: _expanded && !widget.moreOpen ? actions.length - 1 : null),
                      ],
                      // «Ещё» — все действия по группам, здесь же.
                      AnimatedSize(
                        duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _expanded
                            ? Padding(
                                key: _listKey,
                                padding: const EdgeInsets.only(top: Space.s),
                                child: _PeekMoreList(groups: widget.more),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Развёрнутое «Ещё»: группы с серой подписью, действия — рядами круглых
/// кнопок, как ряд под карточкой (1.7.0, замечание владельца 20.10.2026:
/// столбик пунктов был высоким — карточка письма уезжала вверх за экран).
/// В ряду 4–6 кнопок по ширине: «Отметки» из шести действий — два ряда, а
/// не шесть строк.
class _PeekMoreList extends StatelessWidget {
  final List<PeekGroup> groups;
  const _PeekMoreList({required this.groups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final shown = [for (final g in groups) if (g.items.isNotEmpty) g];
    return Material(
      color: AppColors.cardFill(context),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: Radii.cardAll,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.xs),
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 76).floor().clamp(4, 6);
          final cell = c.maxWidth / cols;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (gi, g) in shown.indexed) ...[
              if (gi > 0) const Divider(height: Space.s, indent: Space.m, endIndent: Space.m),
              if ((g.title ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: Space.m, top: Space.xs, right: Space.m),
                  child: Text(g.title!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.6)),
                ),
              Wrap(children: [
                for (final a in g.items) SizedBox(width: cell, child: _PeekGridButton(action: a)),
              ]),
            ],
          ]);
        }),
      ),
    );
  }
}

/// Круглая кнопка развёрнутого «Ещё» — как в ряду под карточкой.
class _PeekGridButton extends StatelessWidget {
  final PeekAction action;
  const _PeekGridButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = action;
    return Semantics(
      button: true,
      label: a.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!a.keepOpen) Navigator.of(context).pop();
          a.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: 2),
          child: ExcludeSemantics(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.secondaryContainer.withValues(alpha: 0.7),
                ),
                child: Icon(a.icon, size: 20, fill: a.filled ? 1 : 0, color: a.color ?? scheme.onSecondaryContainer),
              ),
              const SizedBox(height: Space.xs),
              Text(a.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(color: a.color)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Карточка — на месте строки (верх карточки чуть выше верха строки), по
/// центру строки, целиком на экране; ширина — как у строки, 280…560.
class _PeekLayout extends SingleChildLayoutDelegate {
  final Rect? anchor;
  final EdgeInsets insets;
  const _PeekLayout({required this.anchor, required this.insets});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final want = (anchor?.width ?? constraints.maxWidth + 2 * Space.m).clamp(280.0, 560.0).toDouble() - 2 * Space.m;
    final w = math.min(want, constraints.maxWidth);
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: constraints.maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    final maxLeft = math.max(0.0, size.width - child.width);
    final maxTop = math.max(0.0, size.height - child.height);
    if (a == null) return Offset(maxLeft / 2, maxTop / 2);
    final left = (a.center.dx - insets.left - child.width / 2).clamp(0.0, maxLeft).toDouble();
    final top = (a.top - insets.top - Space.s).clamp(0.0, maxTop).toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PeekLayout old) => old.anchor != anchor || old.insets != insets;
}

/// «Подъём» карточки: появляется с 0,96 и тенью, доходит до 1,0 — как
/// сообщение в Telegram по удержанию.
class _Lift extends StatelessWidget {
  final Widget child;
  const _Lift({required this.child});

  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || MediaQuery.of(context).disableAnimations) return child;
    return ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
      child: child,
    );
  }
}

/// Ряд круглых кнопок под карточкой. Кнопка под пальцем, который ещё не
/// отпущен после удержания, — крупнее и ярче (1.6.46).
class PeekActionsRow extends StatefulWidget {
  final List<PeekAction> actions;

  /// Кнопка, отмеченная как нажатая (развёрнутое «Ещё»).
  final int? highlight;
  const PeekActionsRow({super.key, required this.actions, this.highlight});

  @override
  State<PeekActionsRow> createState() => _PeekActionsRowState();
}

class _PeekActionsRowState extends State<PeekActionsRow> implements HoldTarget {
  late final List<GlobalKey> _keys = [for (final _ in widget.actions) GlobalKey()];

  /// Кнопка под пальцем, который ещё не отпущен после удержания.
  int? _hi;

  @override
  void initState() {
    super.initState();
    HoldPointer.instance.attach(this);
  }

  @override
  void dispose() {
    HoldPointer.instance.detach(this);
    super.dispose();
  }

  @override
  void holdHover(Offset global) {
    if (!mounted) return;
    final hit = _hitIndex(_keys, global);
    if (hit == _hi) return;
    setState(() => _hi = hit);
    if (hit != null) unawaited(HapticFeedback.selectionClick());
  }

  @override
  void holdRelease() {
    final i = _hi;
    if (!mounted || i == null || i >= widget.actions.length) return;
    _run(widget.actions[i]);
  }

  void _run(PeekAction a) {
    if (!a.keepOpen) Navigator.of(context).pop();
    a.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = widget.actions;
    // Ряд мог вырасти («Ещё» добавлено после первой сборки) — ключи по числу.
    while (_keys.length < actions.length) {
      _keys.add(GlobalKey());
    }
    final reduce = MediaQuery.of(context).disableAnimations;
    return Material(
      color: AppColors.cardFill(context),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: Radii.cardAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.xs),
        child: Row(
          children: [
            for (final (i, a) in actions.indexed)
              Expanded(
                child: Semantics(
                  button: true,
                  label: a.label,
                  child: InkWell(
                    key: _keys[i],
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _run(a),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.xs),
                      child: ExcludeSemantics(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          AnimatedScale(
                            scale: _hi == i ? 1.15 : 1.0,
                            duration: reduce ? Duration.zero : const Duration(milliseconds: 120),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _hi == i
                                    ? scheme.primary
                                    : widget.highlight == i
                                        ? scheme.secondaryContainer
                                        : scheme.secondaryContainer.withValues(alpha: 0.7),
                              ),
                              child: Icon(a.icon,
                                  size: 22,
                                  fill: a.filled ? 1 : 0,
                                  color: _hi == i ? scheme.onPrimary : (a.color ?? scheme.onSecondaryContainer)),
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(a.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Индекс виджета под точкой [global] (по GlobalKey); null — ни под одним.
int? _hitIndex(List<GlobalKey> keys, Offset global) {
  for (var i = 0; i < keys.length; i++) {
    final ro = keys[i].currentContext?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize && (ro.localToGlobal(Offset.zero) & ro.size).contains(global)) {
      return i;
    }
  }
  return null;
}

// ───────────────────────── Меню по удержанию кнопки ─────────────────────────

/// Меню по удержанию кнопки (1.6.47: «Написать» — письмо, встреча, задача):
/// столбик пунктов над кнопкой [anchor], фон размыт. Провести палец на пункт
/// и отпустить — пункт выполнен; или отпустить и коснуться.
Future<void> showHoldMenu(BuildContext context, {required Rect anchor, required List<PeekAction> items}) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => _HoldMenuOverlay(anchor: anchor, items: items),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _HoldMenuOverlay extends StatelessWidget {
  final Rect anchor;
  final List<PeekAction> items;
  const _HoldMenuOverlay({required this.anchor, required this.items});

  @override
  Widget build(BuildContext context) {
    final insets = _safe(MediaQuery.of(context));
    return Stack(children: [
      const _PeekBackdrop(),
      Positioned.fill(
        child: Padding(
          padding: insets,
          child: CustomSingleChildLayout(
            delegate: _MenuLayout(anchor: anchor, insets: insets),
            child: _Lift(child: _HoldMenuList(items: items)),
          ),
        ),
      ),
    ]);
  }
}

/// Меню — над кнопкой (не помещается — под ней), по центру кнопки.
class _MenuLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final EdgeInsets insets;
  const _MenuLayout({required this.anchor, required this.insets});

  static const _width = 260.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = math.min(_width, constraints.maxWidth);
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: constraints.maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final maxLeft = math.max(0.0, size.width - child.width);
    final maxTop = math.max(0.0, size.height - child.height);
    final left = (anchor.center.dx - insets.left - child.width / 2).clamp(0.0, maxLeft).toDouble();
    final above = anchor.top - insets.top - Space.s - child.height;
    final top = above >= 0 ? above : (anchor.bottom - insets.top + Space.s);
    return Offset(left, top.clamp(0.0, maxTop).toDouble());
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.anchor != anchor || old.insets != insets;
}

class _HoldMenuList extends StatefulWidget {
  final List<PeekAction> items;
  const _HoldMenuList({required this.items});

  @override
  State<_HoldMenuList> createState() => _HoldMenuListState();
}

class _HoldMenuListState extends State<_HoldMenuList> implements HoldTarget {
  late final List<GlobalKey> _keys = [for (final _ in widget.items) GlobalKey()];
  int? _hi;

  @override
  void initState() {
    super.initState();
    HoldPointer.instance.attach(this);
  }

  @override
  void dispose() {
    HoldPointer.instance.detach(this);
    super.dispose();
  }

  @override
  void holdHover(Offset global) {
    if (!mounted) return;
    final hit = _hitIndex(_keys, global);
    if (hit == _hi) return;
    setState(() => _hi = hit);
    if (hit != null) unawaited(HapticFeedback.selectionClick());
  }

  @override
  void holdRelease() {
    final i = _hi;
    if (!mounted || i == null || i >= widget.items.length) return;
    _run(widget.items[i]);
  }

  void _run(PeekAction a) {
    Navigator.of(context).pop();
    a.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: AppColors.cardFill(context),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: Radii.cardAll,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, a) in widget.items.indexed)
            Material(
              key: _keys[i],
              color: _hi == i ? scheme.secondaryContainer : Colors.transparent,
              child: InkWell(
                onTap: () => _run(a),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Sizes.tapTarget + Space.xs),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: Row(children: [
                      Icon(a.icon, size: Sizes.icon, color: a.color ?? scheme.onSurfaceVariant),
                      const SizedBox(width: Space.l),
                      Expanded(child: Text(a.label, style: theme.textTheme.bodyLarge)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── Меню кнопки («⋮», выбор значения) ─────────────────────────
//
// 1.8.6 (замечание владельца 28.10.2026: всплывающие панели — как карточка
// по удержанию письма). Раньше меню «⋮» и выбор значения в настройках были
// стандартными меню Material: другой фон, другие отступы и тени, без
// размытия. Теперь — тот же размытый фон и та же карточка, что у удержания:
// меню у кнопки (под ней; не помещается — над ней), строки как в меню
// кнопки «Написать», выбранное значение — с галочкой.

/// Пункт меню кнопки ([showAnchoredMenu], [AppMenuButton]).
class AppMenuEntry<T> {
  final T? value;
  final String label;
  final IconData? icon;

  /// Цвет значка (образец цвета текста в панели форматирования); null — обычный.
  final Color? iconColor;
  final String? subtitle;

  /// Необратимое действие («Удалить», «Очистить») — цветом ошибки.
  final bool destructive;
  final bool enabled;

  /// Переключатель включён (например, «На контроле при отправке») — галочка
  /// справа, как у выбранного значения.
  final bool checked;
  final bool isDivider;

  /// Уровень вложенности (дерево папок): отступ слева.
  final int indent;

  const AppMenuEntry({
    required T this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.destructive = false,
    this.enabled = true,
    this.checked = false,
    this.indent = 0,
  }) : isDivider = false;

  /// Черта между группами пунктов.
  const AppMenuEntry.divider()
      : value = null,
        label = '',
        icon = null,
        iconColor = null,
        subtitle = null,
        destructive = false,
        enabled = false,
        checked = false,
        indent = 0,
        isDivider = true;
}

/// Меню у [anchor] (прямоугольник кнопки на экране). Возвращает value
/// выбранного пункта или null (закрыли мимо, «Назад»). [selected] — текущее
/// значение: пункт с ним отмечен галочкой.
///
/// 1.8.8 (замечание владельца 29.10.2026: всплывающие панели — как карточка
/// по удержанию): [anchor] null — карточка по центру экрана (шторки действий
/// [showActionSheet] стали такими); [header] — шапка с объектом (значок, имя,
/// подпись) над пунктами, [footer] — пояснение под ними.
Future<T?> showAnchoredMenu<T>(
  BuildContext context, {
  required Rect? anchor,
  required List<AppMenuEntry<T>> entries,
  T? selected,
  Widget? header,
  Widget? footer,
}) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) => _AnchoredMenuOverlay<T>(
        anchor: anchor, entries: entries, selected: selected, header: header, footer: footer),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _AnchoredMenuOverlay<T> extends StatelessWidget {
  final Rect? anchor;
  final List<AppMenuEntry<T>> entries;
  final T? selected;
  final Widget? header;
  final Widget? footer;
  const _AnchoredMenuOverlay(
      {required this.anchor, required this.entries, required this.selected, this.header, this.footer});

  @override
  Widget build(BuildContext context) {
    final insets = _safe(MediaQuery.of(context));
    return Stack(children: [
      const _PeekBackdrop(),
      Positioned.fill(
        child: Padding(
          padding: insets,
          child: CustomSingleChildLayout(
            delegate: _AnchoredMenuLayout(anchor: anchor, insets: insets, wide: header != null || footer != null),
            child: _Lift(
                child: _AnchoredMenuList<T>(entries: entries, selected: selected, header: header, footer: footer)),
          ),
        ),
      ),
    ]);
  }
}

/// Меню — под кнопкой (не помещается — над ней), правым краем к правому краю
/// кнопки, если кнопка в правой половине экрана, иначе левым к левому. Без
/// кнопки — по центру экрана. [wide] — с шапкой: шире, как карточка письма.
class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  final Rect? anchor;
  final EdgeInsets insets;
  final bool wide;
  const _AnchoredMenuLayout({required this.anchor, required this.insets, this.wide = false});

  static const _minWidth = 200.0;
  static const _maxWidth = 320.0;
  static const _wideMin = 280.0;
  static const _wideMax = 400.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final max = math.min(wide ? _wideMax : _maxWidth, constraints.maxWidth);
    final min = math.min(wide || anchor == null ? _wideMin : _minWidth, max);
    return BoxConstraints(minWidth: min, maxWidth: max, maxHeight: constraints.maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final maxLeft = math.max(0.0, size.width - child.width);
    final maxTop = math.max(0.0, size.height - child.height);
    final anchor = this.anchor;
    if (anchor == null) return Offset(maxLeft / 2, maxTop / 2);
    final a = anchor.translate(-insets.left, -insets.top);
    final rightSide = a.center.dx > size.width / 2;
    final left = (rightSide ? a.right - child.width : a.left).clamp(0.0, maxLeft).toDouble();
    final below = a.bottom + Space.xs;
    final top = below + child.height <= size.height ? below : a.top - Space.xs - child.height;
    return Offset(left, top.clamp(0.0, maxTop).toDouble());
  }

  @override
  bool shouldRelayout(_AnchoredMenuLayout old) => old.anchor != anchor || old.insets != insets || old.wide != wide;
}

class _AnchoredMenuList<T> extends StatelessWidget {
  final List<AppMenuEntry<T>> entries;
  final T? selected;
  final Widget? header;
  final Widget? footer;
  const _AnchoredMenuList({required this.entries, required this.selected, this.header, this.footer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Место под значок — у всех строк, если он есть хоть у одной: подписи
    // начинаются с одной линии.
    final withIcons = entries.any((e) => e.icon != null);
    final withCheck = selected != null || entries.any((e) => e.checked);
    return Material(
      color: AppColors.cardFill(context),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: Radii.cardAll,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (header != null) ...[
              header!,
              const Divider(height: Space.s),
            ],
            for (final e in entries)
              if (e.isDivider)
                const Divider(height: Space.s, indent: Space.l, endIndent: Space.l)
              else
                _row(context, theme, scheme, e, withIcons, withCheck),
            if (footer != null) ...[
              const Divider(height: Space.s),
              footer!,
            ],
          ]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ThemeData theme, ColorScheme scheme, AppMenuEntry<T> e, bool withIcons,
      bool withCheck) {
    // Выбранное значение — с подложкой и галочкой; включённый переключатель —
    // только с галочкой.
    final isSelected = selected != null && e.value == selected;
    final isChecked = isSelected || e.checked;
    final fg = !e.enabled
        ? theme.disabledColor
        : e.destructive
            ? scheme.error
            : scheme.onSurface;
    return Semantics(
      selected: isChecked,
      button: true,
      child: Material(
        color: isSelected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: e.enabled ? () => Navigator.of(context).pop(e.value) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.tapTarget),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                  Space.l + e.indent.clamp(0, 5) * Space.l, Space.s, Space.l, Space.s),
              child: Row(children: [
                if (withIcons) ...[
                  Icon(e.icon,
                      size: Sizes.icon,
                      color: e.iconColor ?? (e.enabled && !e.destructive ? scheme.onSurfaceVariant : fg)),
                  const SizedBox(width: Space.l),
                ],
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.label, style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
                    if (e.subtitle != null)
                      Text(e.subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                if (withCheck) ...[
                  const SizedBox(width: Space.m),
                  SizedBox(
                    width: Sizes.iconRow,
                    child: isChecked ? Icon(AppIcons.check, size: Sizes.iconRow, color: scheme.primary) : null,
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
