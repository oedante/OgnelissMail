// lib/widgets/common/tile_grid.dart
//
// Плитки в духе «Пуска» Windows 10 (1.10.2, просьба владельца 02.11.2026:
// «Избранное панелями… такой подход где-то ещё пригодится»). Сетка из
// четырёх колонок (на широком экране — больше); плитка «только значок»
// занимает одну клетку, «значок с подписью» — две. Плоские, со скруглением
// 8 dp, без теней: спокойный деловой вид. Выбранная — цветом выбора темы.
// Число (непрочитанные) — в правом верхнем углу.

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

class TileItem {
  /// Ключ (для настроек и тестов).
  final String id;
  final IconData icon;
  final String label;
  final bool iconOnly;
  final int? count;
  final Color? countColor;
  final bool selected;

  /// Приглушённо (например, у папки выключены уведомления).
  final bool muted;
  final VoidCallback? onTap;

  /// Удержание — с местом плитки на экране (карточка действий над ней).
  final void Function(Rect? anchor)? onLongPressAt;

  const TileItem({
    required this.id,
    required this.icon,
    required this.label,
    this.iconOnly = false,
    this.count,
    this.countColor,
    this.selected = false,
    this.muted = false,
    this.onTap,
    this.onLongPressAt,
  });
}

class TileGrid extends StatelessWidget {
  final List<TileItem> items;

  /// Ширина клетки, по которой считается число колонок (не меньше 4).
  final double minCell;
  final double gap;
  final double height;
  final EdgeInsetsGeometry padding;

  const TileGrid({
    super.key,
    required this.items,
    this.minCell = 58,
    this.gap = 6,
    this.height = 56,
    this.padding = const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        var cols = ((w + gap) / (minCell + gap)).floor();
        if (cols < 4) cols = 4;
        final cell = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in items)
              SizedBox(
                key: ValueKey('tile_${t.id}'),
                width: t.iconOnly ? cell : cell * 2 + gap,
                height: height,
                child: _Tile(item: t),
              ),
          ],
        );
      }),
    );
  }
}

class _Tile extends StatelessWidget {
  final TileItem item;
  const _Tile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = item;
    final fg = t.selected ? scheme.primary : scheme.onSurface.withValues(alpha: t.muted ? 0.5 : 0.85);
    final bg = t.selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh;
    final n = t.count ?? 0;
    final badge = n <= 0
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: t.countColor ?? scheme.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              n > 999 ? '999+' : '$n',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600),
            ),
          );
    // Как плитки «Пуска» Windows 10: у широкой — значок слева вверху, число
    // справа вверху, подпись внизу одной строкой; у маленькой — значок в
    // центре, число в углу. Подпись в две строки рядом со значком рвала
    // слова на узкой плитке («Проект-ы»).
    final content = t.iconOnly
        ? Center(child: Icon(t.icon, size: 24, color: fg, fill: t.selected ? 1 : 0))
        : Padding(
            padding: const EdgeInsets.fromLTRB(Space.s + 2, Space.s - 2, Space.s, Space.s - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(t.icon, size: 20, color: fg, fill: t.selected ? 1 : 0),
                  const Spacer(),
                  ?badge,
                ]),
                Text(
                  t.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    height: 1.1,
                    fontWeight: t.selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
    final tile = Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: t.onTap,
        onLongPress: t.onLongPressAt == null
            ? null
            : () {
                final box = context.findRenderObject() as RenderBox?;
                final rect = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
                t.onLongPressAt!(rect);
              },
        child: Stack(
          children: [
            Positioned.fill(child: content),
            if (badge != null && t.iconOnly) Positioned(top: 3, right: 3, child: badge),
          ],
        ),
      ),
    );
    // Только значок — подпись в подсказке и для TalkBack/VoiceOver.
    return Semantics(
      button: true,
      selected: t.selected,
      label: n > 0 ? '${t.label}, $n' : t.label,
      excludeSemantics: true,
      child: t.iconOnly ? Tooltip(message: t.label, child: tile) : tile,
    );
  }
}
