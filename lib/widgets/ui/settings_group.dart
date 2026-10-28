// lib/widgets/ui/settings_group.dart
// Карточки-группы настроек по принципам Ogneliss Dialer (docs/plan/
// UI_REDESIGN.md, Ф0/Ф4): заголовок раздела цветом акцента, группа строк на
// подложке AppColors.cardFill с тонкой границей, скругление 16 и разделителями от текста,
// строка — значок цвета акцента, название, пояснение, «›» если ведёт дальше.
// Раньше главный экран настроек был плоским списком с кружками-значками, а
// экран аккаунта — карточками: два вида в одном приложении.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart' show AppColors;
import '../../core/theme/ogneliss_look.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import 'help_hint.dart';
// «?» с пояснением нужен почти всем экранам настроек.
export 'help_hint.dart';

/// Заголовок раздела над группой.
class SettingsSectionTitle extends StatelessWidget {
  final String text;
  /// Пояснение к разделу — за значком «?» справа от заголовка.
  final String? help;

  /// Кнопка справа в полосе (например, «Добавить» над списком).
  final Widget? trailing;

  /// Число справа от заголовка (сколько участников, 1.7.2+106).
  final int? count;
  const SettingsSectionTitle(this.text, {super.key, this.help, this.trailing, this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // «Воздушный» вид (1.8.0, как Ogneliss Dialer): подпись раздела синим,
    // обычным регистром, без полосы — над карточкой, вровень с текстом
    // строк. Полоса — только в высококонтрастной теме.
    if (!OgnelissLook.of(context).outlined) {
      final style = theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
      );
      final caption = Text(text, style: style);
      return Semantics(
        header: true,
        child: Container(
          margin: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
          constraints: const BoxConstraints(minHeight: 28),
          padding: EdgeInsetsDirectional.fromSTEB(
              Space.l, 0, help == null && trailing == null ? Space.l : Space.xs, 0),
          alignment: AlignmentDirectional.centerStart,
          child: help == null && trailing == null && count == null
              ? caption
              : Row(children: [
                  Expanded(child: caption),
                  if (count != null)
                    Padding(
                      padding: EdgeInsetsDirectional.only(end: help == null && trailing == null ? 0 : Space.s),
                      child: Text('$count', style: style),
                    ),
                  if (help != null) HelpButton(text: help!, title: text, compact: true),
                  if (trailing != null) trailing!,
                ]),
        ),
      );
    }
    // Высокий контраст: полоса раздела, как в боковом меню до 1.8.0 —
    // прописные серые буквы на чуть более тёмной подложке (10.10.2026).
    final title = Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
    return Semantics(
      header: true,
      child: Container(
        margin: const EdgeInsets.only(top: Space.l, bottom: Space.s),
        constraints: const BoxConstraints(minHeight: 32),
        padding: EdgeInsets.fromLTRB(Space.l, 0, help == null && trailing == null ? Space.l : Space.xs, 0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        alignment: Alignment.centerLeft,
        child: help == null && trailing == null && count == null
            ? title
            : Row(children: [
                Expanded(child: title),
                if (count != null)
                  Padding(
                    padding: EdgeInsets.only(right: help == null && trailing == null ? 0 : Space.s),
                    child: Text('$count', style: title.style),
                  ),
                if (help != null) HelpButton(text: help!, title: text, compact: true),
                if (trailing != null) trailing!,
              ]),
      ),
    );
  }
}

/// Группа строк в карточке. Пустые элементы (SizedBox.shrink) не нужны —
/// условные строки добавляйте через `if`.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  /// Отступ разделителя слева: по умолчанию — от текста строки со значком
  /// (16 + 24 + 16); у строк без значка — [Space.l] (поля ФИО в контакте).
  final double? dividerIndent;
  const SettingsGroup({super.key, required this.children, this.dividerIndent});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final look = OgnelissLook.of(context);
    // Подложка отличима от фона экрана (раньше surfaceContainerLow = фон
    // светлой темы, группы сливались — аудит цветов 10.10.2026). С 1.8.0
    // («воздушный» вид) — без рамки и без линий между строками: карточку
    // отделяет тон, строки — поля. Рамка — в высоком контрасте, AMOLED и
    // «Чтении», линии — в высоком контрасте.
    return Material(
      color: AppColors.cardFill(context),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: look.cardBorder
            ? BorderSide(color: AppColors.cardEdge(context).withValues(alpha: look.outlined ? 1 : 0.7))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && look.outlined)
              Divider(
                height: 1,
                indent: dividerIndent ?? Space.l + Sizes.icon + Space.l,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Строка группы. [color] — для опасных действий (значок и текст этим цветом,
/// без «›»). [leading] заменяет значок (например, фото аккаунта).
class SettingsItem extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? trailing;
  /// Подробное пояснение — за значком «?» после названия.
  final String? hint;
  const SettingsItem({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.color,
    required this.onTap,
    this.trailing,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
      minTileHeight: Sizes.tapTarget,
      leading: leading ?? (icon == null ? null : Icon(icon, color: color ?? scheme.primary)),
      title: TitleWithHelp(title, hint: hint, style: color == null ? null : TextStyle(color: color)),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
      trailing: trailing ?? (color == null && onTap != null ? const Icon(AppIcons.chevron_right) : null),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
    );
  }
}

/// Переключатель в группе.
class SettingsSwitchItem extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  /// Подробное пояснение — за значком «?» после названия.
  final String? hint;
  const SettingsSwitchItem({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
      secondary: icon == null ? null : Icon(icon, color: scheme.primary),
      title: TitleWithHelp(title, hint: hint),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Короткая строка-пояснение под заголовком экрана или раздела, со значком
/// «?» для подробностей. Вместо абзаца текста на входе в экран.
class SettingsIntro extends StatelessWidget {
  final String text;
  final String? more;
  final String? moreTitle;
  const SettingsIntro(this.text, {super.key, this.more, this.moreTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.s, Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          if (more != null && more!.isNotEmpty) HelpButton(text: more!, title: moreTitle, compact: true),
        ],
      ),
    );
  }
}

