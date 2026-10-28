// lib/widgets/ui/section_band.dart
// Заголовок раздела. С 1.8.0 («воздушный» вид, как Ogneliss Dialer) —
// подпись синим, обычным регистром, без полосы; в высококонтрастной теме —
// прежняя полоса: прописные серые буквы на чуть более тёмной подложке с
// тонкими линиями сверху и снизу (боковое меню почты с 09.10.2026, весь
// интерфейс с 10.10.2026).

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart' show AppColors;
import '../../core/theme/ogneliss_look.dart';
import '../../core/theme/tokens.dart';

class SectionBand extends StatelessWidget {
  final String title;
  final Widget? trailing;

  /// Число справа от заголовка (например, сколько получателей).
  final int? count;

  /// Цвет заголовка (например, «Просрочено» — цветом ошибки).
  final Color? color;

  /// Лёгкий вид для лент (1.6.39): «СЕГОДНЯ», «ВЧЕРА», «16 ОКТЯБРЯ» —
  /// скруглённая плашка с отступами, как разделы настроек, но светлее и без
  /// рамки, на фоне ленты. Сплошная полоса с линиями во всю ширину
  /// перегружала ленту (замечание 18.10.2026).
  final bool light;

  /// Фон подписи в «воздушном» виде: закреплённая над прокруткой подпись
  /// (боковое меню) — цвета панели, иначе строки просвечивали бы под ней.
  final Color? background;

  const SectionBand({super.key, required this.title, this.trailing, this.count, this.color, this.background})
      : light = false;

  const SectionBand.light({super.key, required this.title, this.trailing, this.count, this.color, this.background})
      : light = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // «Воздушный» вид (1.8.0, как Ogneliss Dialer): подпись раздела синим,
    // обычным регистром, без полосы. Полосы — только в высоком контрасте.
    if (!OgnelissLook.of(context).outlined) {
      final style = theme.textTheme.titleSmall?.copyWith(
        color: color ?? theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
      );
      final caption = Semantics(
        header: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: EdgeInsetsDirectional.fromSTEB(
              Space.l, light ? Space.m : Space.s, trailing == null ? Space.l : Space.xs, Space.xxs),
          alignment: AlignmentDirectional.bottomStart,
          child: Row(children: [
            Expanded(child: Text(title, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (count != null) Text('$count', style: style),
            if (trailing != null) trailing!,
          ]),
        ),
      );
      // На ленте подпись лежит на её фоне (при закреплении поверх строк).
      return ColoredBox(color: light ? AppColors.listFill(context) : (background ?? Colors.transparent), child: caption);
    }
    if (light) {
      final style = theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      );
      return Semantics(
        header: true,
        child: ColoredBox(
          color: AppColors.listFill(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
            child: Container(
              constraints: const BoxConstraints(minHeight: 28),
              padding: EdgeInsets.fromLTRB(Space.m, 0, trailing == null ? Space.m : Space.xs, 0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.centerLeft,
              child: Row(children: [
                Expanded(child: Text(title.toUpperCase(), style: style)),
                if (count != null) Text('$count', style: style),
                if (trailing != null) trailing!,
              ]),
            ),
          ),
        ),
      );
    }
    final line = BorderSide(color: theme.colorScheme.outlineVariant, width: 1);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: color ?? theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );
    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 36),
        padding: EdgeInsets.fromLTRB(Space.l, 0, trailing == null ? Space.l : Space.xs, 0),
        decoration: BoxDecoration(
          // Светлее (1.6.25): на белой ленте тёмно-серая полоса была тяжёлой.
          color: theme.colorScheme.surfaceContainer,
          border: Border(top: line, bottom: line),
        ),
        child: Row(children: [
          Expanded(child: Text(title.toUpperCase(), style: style)),
          if (count != null) Text('$count', style: style),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}
