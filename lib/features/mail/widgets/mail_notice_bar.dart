// lib/features/mail/widgets/mail_notice_bar.dart
// Строка сведений письма (1.12.x, просьба владельца 04.11.2026: «несколько
// плашек с предложением отписаться, предложение перевода и что-нибудь ещё
// съедают место — может, таблетками с раскрытием по нажатию»).
//
// Вместо стопки плашек во всю ширину — одна строка чипов под шапкой письма:
// «Перевести · английский», «Отписаться», «Показать изображения», «На
// контроле», «Позже», «Не доставлено», «Подпись верна», «Спам», теги…
// Нажатие раскрывает под строкой ту же плашку, что была раньше (с её
// кнопками), повторное нажатие или другой чип — сворачивает: раскрыта одна.
// Чип с одним очевидным действием (перевод, изображения) выполняет его
// сразу, остальные варианты — «▾» на чипе, долгое нажатие или правая кнопка
// мыши. Телефон — одна строка с прокруткой вбок и тенью у края; планшет и
// компьютер — перенос на следующую строку.
//
// Карточки, которые сами — содержание письма с кнопками ответа
// (предупреждение о подделке отправителя, приглашение, бронирование),
// остаются карточками: экран письма ставит их отдельно.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/peek_card.dart' show AppMenuEntry, peekAnchorOf, showAnchoredMenu;
import '../../../widgets/common/scroll_edge_fade.dart';

/// Тон чипа: обычный; сведения (предложение перевода — цвет акцента);
/// предупреждение («Не доставлено», подпись не сходится — цвет ошибки).
enum MailNoticeTone { neutral, info, warning }

/// Одно сведение о письме — чип строки сведений.
class MailNotice {
  /// Постоянный ключ: по нему строка помнит, какой чип раскрыт.
  final String id;
  final IconData? icon;

  /// Цвет значка (успех, «Позже»); null — по тону.
  final Color? iconColor;

  /// Значок закрашенный (как у плашки «Исполнено»).
  final bool iconFilled;

  /// Короткая надпись чипа.
  final String label;

  /// Полный текст — подсказка при наведении и для чтения с экрана; null —
  /// надпись.
  final String? detail;
  final MailNoticeTone tone;

  /// Свой цвет (теги): фон — им же, прозрачнее; null — по тону.
  final Color? color;

  /// Идёт работа (перевод, проверка подписи): вместо значка — индикатор.
  final bool busy;

  /// Действие чипа — сразу, без раскрытия («Перевести», «Показать
  /// изображения», теги).
  final VoidCallback? onTap;

  /// Раскрытая плашка под строкой — прежняя плашка письма с её кнопками.
  final WidgetBuilder? expanded;

  /// Остальные варианты — «▾» на чипе, долгое нажатие, правая кнопка.
  final List<AppMenuEntry<String>> menu;
  final ValueChanged<String>? onMenu;

  const MailNotice({
    required this.id,
    required this.label,
    this.icon,
    this.iconColor,
    this.iconFilled = false,
    this.detail,
    this.tone = MailNoticeTone.neutral,
    this.color,
    this.busy = false,
    this.onTap,
    this.expanded,
    this.menu = const [],
    this.onMenu,
  });

  bool get expandable => onTap == null && expanded != null;
  bool get hasMenu => menu.isNotEmpty && onMenu != null;
}

/// Строка сведений: чипы и раскрытая плашка под ними.
class MailNoticeBar extends StatefulWidget {
  final List<MailNotice> notices;

  /// Перенос на следующую строку (планшет, компьютер); false — одна строка
  /// с прокруткой вбок (телефон).
  final bool wrap;

  /// Мелкая подпись под строкой — «Переведено Google», пока показан
  /// перевод (условие ML Kit: подпись рядом с переведённым текстом).
  final String? note;

  const MailNoticeBar({super.key, required this.notices, this.wrap = false, this.note});

  @override
  State<MailNoticeBar> createState() => _MailNoticeBarState();
}

class _MailNoticeBarState extends State<MailNoticeBar> with SingleTickerProviderStateMixin {
  /// Раскрытый чип (null — ни одного).
  String? _open;

  /// Чья плашка видна: при сворачивании — до конца анимации.
  String? _shown;

  late final AnimationController _anim = AnimationController(vsync: this, duration: _duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);

  static const _duration = Duration(milliseconds: 200);

  MailNotice? _byId(String? id) =>
      id == null ? null : widget.notices.where((n) => n.id == id && n.expandable).firstOrNull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // «Уменьшить движение» (настройка и системная) — раскрытие без анимации.
    _anim.duration = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : _duration;
  }

  @override
  void didUpdateWidget(MailNoticeBar old) {
    super.didUpdateWidget(old);
    // Сведение ушло (уведомление о прочтении отправлено, письмо восстановлено
    // из «Спама») — его плашка закрывается сразу: строить её уже не из чего.
    if (_byId(_shown) == null) {
      _open = null;
      _shown = null;
      _anim.value = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle(MailNotice n) {
    if (_open == n.id) {
      _collapse();
      return;
    }
    setState(() {
      _open = n.id;
      _shown = n.id;
    });
    _anim.forward();
  }

  void _collapse() {
    if (_open == null) return;
    setState(() => _open = null);
    _anim.reverse().whenCompleteOrCancel(() {
      if (mounted && _open == null && _anim.isDismissed) setState(() => _shown = null);
    });
  }

  void _tap(MailNotice n) {
    final action = n.onTap;
    if (action != null) {
      // Другой чип сворачивает раскрытую плашку.
      _collapse();
      action();
      return;
    }
    if (n.expanded != null) _toggle(n);
  }

  Future<void> _menu(BuildContext chipContext, MailNotice n) async {
    final onMenu = n.onMenu;
    if (!n.hasMenu || onMenu == null) return;
    final v = await showAnchoredMenu<String>(chipContext, anchor: peekAnchorOf(chipContext), entries: n.menu);
    if (v != null) onMenu(v);
  }

  @override
  Widget build(BuildContext context) {
    final notices = widget.notices;
    if (notices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final shown = _byId(_shown);
    final note = widget.note;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: LayoutBuilder(builder: (context, c) {
        // Длинная надпись (тег, имя рассылки) — с многоточием, а не шире строки.
        final maxChip = math.max(96.0, c.maxWidth - 2 * Space.l);
        final chips = [
          for (final n in notices)
            ConstrainedBox(
              key: ValueKey('notice-${n.id}'),
              constraints: BoxConstraints(maxWidth: maxChip),
              child: Builder(
                builder: (chipContext) => _NoticeChip(
                  notice: n,
                  open: _open == n.id,
                  onTap: () => _tap(n),
                  onMenu: n.hasMenu ? () => _menu(chipContext, n) : null,
                ),
              ),
            ),
        ];
        final row = widget.wrap
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: Wrap(spacing: Space.s, runSpacing: Space.s, children: chips),
              )
            : ScrollEdgeFade(
                axis: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    for (var i = 0; i < chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: Space.s),
                      chips[i],
                    ],
                  ]),
                ),
              );
        final panel = shown == null
            ? const SizedBox(width: double.infinity)
            : KeyedSubtree(key: ValueKey('notice-open-${shown.id}'), child: shown.expanded!(context));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          row,
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
              child: Text(note,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          // Раскрытая плашка: плавно выезжает под строкой; смена одной на
          // другую — плавно по высоте. Без анимации — без AnimatedSize: с
          // нулевой длительностью он перестраивается посреди своей вёрстки.
          SizeTransition(
            sizeFactor: _curve,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _curve,
              child: _anim.duration == Duration.zero
                  ? panel
                  : AnimatedSize(
                      duration: _duration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: panel,
                    ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _NoticeChip extends StatelessWidget {
  final MailNotice notice;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  const _NoticeChip({required this.notice, required this.open, required this.onTap, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final n = notice;
    // Цвета: обычный — как плашка изображений (surfaceContainerHigh), тона —
    // прозрачным цветом, как прежние плашки; раскрытый — плотнее и с рамкой.
    final custom = n.color;
    final (Color bg, Color fg, Color icon) = switch (n.tone) {
      _ when custom != null => (custom.withValues(alpha: open ? 0.2 : 0.1), custom, custom),
      MailNoticeTone.info => (scheme.primary.withValues(alpha: open ? 0.18 : 0.1), scheme.primary, scheme.primary),
      MailNoticeTone.warning => (
          AppColors.errorRed.withValues(alpha: open ? 0.2 : 0.1),
          AppColors.errorText(context),
          AppColors.errorText(context),
        ),
      MailNoticeTone.neutral => (
          open ? scheme.surfaceContainerHighest : scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          scheme.onSurfaceVariant,
        ),
    };
    // Высота — по шрифту: при крупном тексте чип растёт, а не обрезает надпись.
    final height = math.max(32.0, MediaQuery.textScalerOf(context).scale(20) + Space.s);
    final full = n.detail ?? n.label;
    final lead = n.busy
        ? SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : n.icon == null
            ? null
            : Icon(n.icon, size: 16, color: n.iconColor ?? icon, fill: n.iconFilled ? 1 : 0);
    final menu = onMenu;
    final main = Semantics(
      container: true,
      button: true,
      label: full,
      expanded: n.expandable ? open : null,
      onTap: onTap,
      onLongPress: menu,
      excludeSemantics: true,
      child: Tooltip(
        message: full,
        // С меню долгое нажатие открывает его; подсказка — при наведении мыши.
        triggerMode: menu != null ? TooltipTriggerMode.manual : TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          onLongPress: menu,
          onSecondaryTap: menu,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                  lead == null ? Space.m : Space.s + 2, Space.xs, menu != null ? Space.xs + 2 : Space.m, Space.xs),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (lead != null) ...[lead, const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    n.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: fg),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.chipAll,
        side: open ? BorderSide(color: fg.withValues(alpha: 0.45)) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: main),
        if (menu != null) ...[
          Container(width: 1, height: math.min(18.0, height - Space.m), color: fg.withValues(alpha: 0.2)),
          Semantics(
            button: true,
            label: '${l10n.tr('more')}: ${n.label}',
            onTap: menu,
            excludeSemantics: true,
            child: Tooltip(
              message: l10n.tr('more'),
              excludeFromSemantics: true,
              child: InkWell(
                onTap: menu,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height, minWidth: 28),
                  child: Icon(AppIcons.arrow_drop_down, size: 20, color: fg),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
