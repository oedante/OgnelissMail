// lib/features/settings/screens/appearance_screen.dart
// «Оформление» (1.9.x, просьба владельца 31.10.2026: «темы как в
// Telegram»). Вверху — живой пример (строки ленты и «пузыри» беседы в
// выбранной теме), ниже — тема (светлая, тёмная…), цвета от обоев,
// цветовая тема, акцент, оттенок фона ленты, скругление, плотность ленты и
// анимация открытия письма. Всё применяется сразу во всём приложении.
//
// Выбор темы (светлая/тёмная/AMOLED/«Чтение») и «Цвета от обоев» раньше
// были в «Общих» — теперь здесь, в «Общих» осталась строка-ссылка.

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/appearance.dart';
import '../../../core/theme/theme_palette.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/widgets/email_list_tile.dart';
import '../providers/settings_provider.dart';

/// Подписи цветовых тем.
String presetLabel(AppLocalizations l10n, ThemePreset p) => l10n.tr(switch (p) {
  ThemePreset.classic => 'apPresetClassic',
  ThemePreset.sky => 'apPresetSky',
  ThemePreset.ocean => 'apPresetOcean',
  ThemePreset.forest => 'apPresetForest',
  ThemePreset.sunset => 'apPresetSunset',
  ThemePreset.graphite => 'apPresetGraphite',
  ThemePreset.midnight => 'apPresetMidnight',
});

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final android = !kIsWeb && Platform.isAndroid;
    // Цветовая тема и акцент не применяются при высоком контрасте и в
    // «Чтении» (свои палитры); цвета обоев их заменяют.
    final locked = settings.highContrast || settings.reading;
    final wallpaper = android && settings.dynamicColor && !locked;
    final hint = theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));

    // Выбор темы или акцента при цветах обоев выключает обои: иначе выбор
    // ни на что бы не влиял.
    Future<void> pickPreset(ThemePreset p) async {
      if (wallpaper) await notifier.setDynamicColor(false);
      await notifier.setAccentColor(null);
      await notifier.setThemePreset(p);
    }

    Future<void> pickAccent(int? argb) async {
      if (wallpaper) await notifier.setDynamicColor(false);
      await notifier.setAccentColor(argb);
    }

    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
      child: Text(text, style: hint),
    );

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('appearanceTitle')))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          const AppearancePreview(),

          // ── Тема ──
          SettingsSectionTitle(l10n.tr('theme')),
          SettingsGroup(
            children: [
              for (final t in [
                (AppThemeChoice.system, l10n.tr('systemTheme'), null),
                (AppThemeChoice.light, l10n.tr('lightTheme'), null),
                (AppThemeChoice.dark, l10n.tr('darkTheme'), null),
                (AppThemeChoice.amoled, l10n.tr('amoledTheme'), l10n.tr('amoledThemeHint')),
                (AppThemeChoice.reading, l10n.tr('readingTheme'), l10n.tr('readingThemeHint')),
              ])
                AppRadioTile<AppThemeChoice>(
                  title: Text(t.$2),
                  subtitle: t.$3 == null ? null : Text(t.$3!),
                  value: t.$1,
                  groupValue: settings.themeChoice,
                  onChanged: (v) => notifier.setThemeChoice(v!),
                ),
            ],
          ),

          // ── Цветовая тема ──
          SettingsSectionTitle(l10n.tr('apColorTheme'), help: l10n.tr('apColorThemeHelp')),
          SettingsGroup(
            children: [
              // Цвета от обоев — Android 12+ (на iOS и компьютере системной
              // палитры нет). Пока включены, тема и акцент — от обоев.
              if (android)
                SettingsSwitchItem(
                  icon: AppIcons.palette,
                  title: l10n.tr('dynamicColor'),
                  subtitle: l10n.tr(
                    settings.highContrast
                        ? 'dynamicColorHc'
                        : (settings.reading ? 'dynamicColorReading' : 'apDynamicDesc'),
                  ),
                  value: settings.dynamicColor,
                  onChanged: locked ? null : notifier.setDynamicColor,
                ),
              _PresetStrip(
                selected: (wallpaper || locked) ? null : settings.themePreset,
                enabled: !locked,
                onPick: pickPreset,
              ),
              if (locked)
                note(l10n.tr(settings.highContrast ? 'apColorsHc' : 'apColorsReading'))
              else if (wallpaper)
                note(l10n.tr('apDynamicOverrides')),
            ],
          ),

          // ── Акцент ──
          SettingsSectionTitle(l10n.tr('apAccent')),
          SettingsGroup(
            children: [
              _AccentPalette(
                preset: settings.themePreset,
                accent: (wallpaper || locked) ? -1 : settings.accentColor,
                enabled: !locked,
                onPick: pickAccent,
              ),
            ],
          ),

          // ── Фон ленты и беседы ──
          SettingsSectionTitle(l10n.tr('apListTint')),
          SettingsGroup(
            children: [
              _Chips<ListTint>(
                value: settings.listTint,
                options: [
                  (ListTint.none, l10n.tr('apTintNone'), null),
                  (ListTint.subtle, l10n.tr('apTintSubtle'), null),
                  (ListTint.soft, l10n.tr('apTintSoft'), null),
                ],
                onChanged: notifier.setListTint,
              ),
            ],
          ),

          // ── Скругление углов ──
          SettingsSectionTitle(l10n.tr('apCorners')),
          SettingsGroup(
            children: [
              _Chips<CornerSize>(
                value: settings.corners,
                options: [
                  (CornerSize.small, l10n.tr('apCornersSmall'), const _CornerGlyph(radius: 2)),
                  (CornerSize.medium, l10n.tr('apCornersMedium'), const _CornerGlyph(radius: 5)),
                  (CornerSize.large, l10n.tr('apCornersLarge'), const _CornerGlyph(radius: 8)),
                ],
                onChanged: notifier.setCorners,
              ),
            ],
          ),

          // ── Плотность ленты ──
          SettingsSectionTitle(l10n.tr('apDensity')),
          SettingsGroup(
            children: [
              for (final o in [
                (ListDensity.compact, l10n.tr('apDensityCompact'), l10n.tr('apDensityCompactHint')),
                (ListDensity.normal, l10n.tr('apDensityNormal'), null),
                (ListDensity.comfortable, l10n.tr('apDensityComfortable'), l10n.tr('apDensityComfortableHint')),
              ])
                AppRadioTile<ListDensity>(
                  title: Text(o.$2),
                  subtitle: o.$3 == null ? null : Text(o.$3!),
                  value: o.$1,
                  groupValue: settings.listDensity,
                  onChanged: (v) => notifier.setListDensity(v ?? ListDensity.normal),
                ),
            ],
          ),

          // ── Движение ──
          SettingsSectionTitle(l10n.tr('a11yMotion')),
          SettingsGroup(
            children: [
              // Выключено по умолчанию: прежние анимации были медленными.
              // «Уменьшить движение» (Специальные возможности) важнее.
              SettingsSwitchItem(
                icon: AppIcons.swipe_down,
                title: l10n.tr('apOpenAnimation'),
                subtitle: l10n.tr(settings.reduceMotion ? 'apOpenAnimationReduced' : 'apOpenAnimationDesc'),
                value: settings.openAnimation && !settings.reduceMotion,
                onChanged: settings.reduceMotion ? null : notifier.setOpenAnimation,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Пример ─────────────────────────

/// Живой пример оформления: две строки ленты (настоящие — с плотностью,
/// оттенком и акцентом) и два «пузыря» беседы. Только для показа: нажатия
/// и экранный диктор его не видят.
class AppearancePreview extends StatelessWidget {
  const AppearancePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    // Адреса без «@»: пример не просит фото у адресной книги организации.
    EmailModel row(
      String id,
      String from,
      String subject,
      String text, {
      bool read = true,
      bool att = false,
      bool flagged = false,
      int minutes = 12,
    }) => EmailModel(
      id: id,
      accountId: 'appearance-preview',
      folderId: 'inbox',
      from: EmailAddress(email: 'preview-$id', displayName: from),
      to: const [],
      subject: subject,
      bodyPreview: text,
      receivedAt: now.subtract(Duration(minutes: minutes)),
      isRead: read,
      hasAttachments: att,
      isFlagged: flagged,
    );
    final rows = [
      row('p1', l10n.tr('apPreviewFrom1'), l10n.tr('apPreviewSubject1'), l10n.tr('apPreviewText1'), read: false),
      row(
        'p2',
        l10n.tr('apPreviewFrom2'),
        l10n.tr('apPreviewSubject2'),
        l10n.tr('apPreviewText2'),
        att: true,
        minutes: 95,
      ),
    ];
    // Фон беседы — как на экране беседы: светлая тема — фон ленты, тёмная —
    // фон экрана или оттенок ленты.
    final convFill = dark
        ? (AppearanceLook.of(context).listFill ?? theme.scaffoldBackgroundColor)
        : AppColors.listFill(context);
    final base = dark ? scheme.surfaceContainer : scheme.surfaceContainerLow;
    final mine = Color.alphaBlend(scheme.primary.withValues(alpha: dark ? 0.08 : 0.07), base);

    Widget bubble(String text, {String? name, required bool own}) => Align(
      alignment: own ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: own ? Space.xxl : 0, end: own ? 0 : Space.xxl),
        child: Material(
          color: own ? mine : base,
          borderRadius: Radii.cardAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s + Space.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != null) Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );

    return ExcludeSemantics(
      child: IgnorePointer(
        child: Material(
          color: AppColors.cardFill(context),
          shape: RoundedRectangleBorder(borderRadius: Radii.cardAll, side: AppColors.cardSide(context)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColoredBox(
                color: AppColors.listFill(context),
                child: Column(
                  children: [for (final e in rows) EmailListTile(email: e, onTap: () {})],
                ),
              ),
              ColoredBox(
                color: convFill,
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(
                    children: [
                      bubble(l10n.tr('apPreviewBubbleIn'), name: l10n.tr('apPreviewFrom1'), own: false),
                      const SizedBox(height: Space.xs + Space.xxs),
                      bubble(l10n.tr('apPreviewBubbleOut'), own: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Цветовые темы ─────────────────────────

/// Палитры тем без своего акцента — постоянны, строятся один раз.
final _presetPalettes = <(ThemePreset, Brightness), ThemePalette>{};

ThemePalette _paletteOf(ThemePreset p, Brightness b) => _presetPalettes.putIfAbsent((
  p,
  b,
), () => b == Brightness.dark ? ThemePalette.dark(Appearance(preset: p)) : ThemePalette.light(Appearance(preset: p)));

/// Плитки цветовых тем в ряд (листаются вбок): круг пополам — фон светлой и
/// тёмной темы, в центре — акцент; ниже — название.
class _PresetStrip extends StatelessWidget {
  const _PresetStrip({required this.selected, required this.enabled, required this.onPick});

  final ThemePreset? selected;
  final bool enabled;
  final ValueChanged<ThemePreset> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SizedBox(
        height: 104 + 16 * (scale - 1),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
          children: [
            for (final p in ThemePreset.values)
              _PresetTile(
                preset: p,
                label: presetLabel(l10n, p),
                selected: p == selected,
                onTap: enabled ? () => onPick(p) : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.label, required this.selected, required this.onTap});

  final ThemePreset preset;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = _paletteOf(preset, Brightness.light);
    final dark = _paletteOf(preset, Brightness.dark);
    final accent = (theme.brightness == Brightness.dark ? dark : light).scheme.primary;
    // «Полночь»: тёмный вариант — чистый чёрный.
    final darkFill = PresetSpec.of(preset).blackDark ? Colors.black : dark.scaffold;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chipAll,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              const SizedBox(height: Space.xs),
              SizedBox(
                width: 56,
                height: 56,
                child: CustomPaint(
                  painter: _PresetSwatchPainter(
                    light: light.scaffold,
                    lightCard: light.card,
                    dark: darkFill,
                    accent: accent,
                    ring: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    selected: selected,
                  ),
                  child: selected
                      ? Center(
                          child: Icon(
                            AppIcons.check,
                            size: 16,
                            color: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: Space.xs),
              SizedBox(
                width: 72,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? theme.colorScheme.primary : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круг плитки: левая верхняя половина — фон светлой темы (с полоской
/// карточки), правая нижняя — тёмной; акцент — кружок в центре; выбранная —
/// с кольцом цвета акцента приложения.
class _PresetSwatchPainter extends CustomPainter {
  const _PresetSwatchPainter({
    required this.light,
    required this.lightCard,
    required this.dark,
    required this.accent,
    required this.ring,
    required this.selected,
  });

  final Color light;
  final Color lightCard;
  final Color dark;
  final Color accent;
  final Color ring;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - (selected ? 4 : 1);
    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawRect(circle, Paint()..color = dark);
    final tl = Path()
      ..moveTo(circle.left, circle.top)
      ..lineTo(circle.right, circle.top)
      ..lineTo(circle.left, circle.bottom)
      ..close();
    canvas.drawPath(tl, Paint()..color = light);
    // Белая «карточка» на светлой половине — видно, что фон тонирован.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(circle.left + r * 0.28, circle.top + r * 0.42, r * 0.7, r * 0.26),
        Radius.circular(r * 0.1),
      ),
      Paint()..color = lightCard,
    );
    canvas.restore();
    canvas.drawCircle(c, r * 0.36, Paint()..color = accent);
    canvas.drawCircle(
      c,
      selected ? r + 2.5 : r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 1
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_PresetSwatchPainter old) =>
      old.light != light ||
      old.lightCard != lightCard ||
      old.dark != dark ||
      old.accent != accent ||
      old.ring != ring ||
      old.selected != selected;
}

// ───────────────────────── Акцент ─────────────────────────

/// 12 готовых акцентов, «Как в теме» и «Свой цвет». [accent] -1 — ничего не
/// выбрано (цвета обоев).
class _AccentPalette extends StatelessWidget {
  const _AccentPalette({required this.preset, required this.accent, required this.enabled, required this.onPick});

  final ThemePreset preset;
  final int? accent;
  final bool enabled;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Образцы — такой яркости, какой акцент будет в этой теме.
    final pal = _paletteOf(preset, theme.brightness);
    final on = pal.scheme.surfaceContainerHighest;
    Color shown(Color c) => dark ? AccentFit.dark(c, on) : AccentFit.light(c, on);
    final custom = accent != null && accent != -1 && !accentSwatches.any((c) => c.toARGB32() == accent);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.s),
        child: Wrap(
          alignment: WrapAlignment.start,
          children: [
            _Swatch(
              color: pal.scheme.primary,
              selected: accent == null,
              tooltip: l10n.tr('apAccentAuto'),
              icon: AppIcons.format_paint,
              onTap: enabled ? () => onPick(null) : null,
            ),
            for (final (i, c) in accentSwatches.indexed)
              _Swatch(
                color: shown(c),
                selected: accent == c.toARGB32(),
                tooltip: '${l10n.tr('apAccent')} ${i + 1}',
                onTap: enabled ? () => onPick(c.toARGB32()) : null,
              ),
            _Swatch(
              color: custom ? shown(Color(accent!)) : null,
              selected: custom,
              tooltip: l10n.tr('apAccentCustom'),
              icon: AppIcons.colorize,
              onTap: enabled
                  ? () async {
                      final start = custom ? Color(accent!) : PresetSpec.of(preset).accent;
                      final picked = await showDialog<Color>(
                        context: context,
                        builder: (_) => _CustomColorDialog(initial: start),
                      );
                      if (picked != null) onPick(picked.toARGB32());
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Кружок акцента 36 dp в области нажатия 48 dp. [color] null — радуга
/// («Свой цвет», ещё не выбран).
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.tooltip, this.icon, this.onTap});

  final Color? color;
  final bool selected;
  final String tooltip;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color;
    final fg = fill == null
        ? Colors.white
        : (ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : Colors.black);
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: Sizes.tapTarget,
            height: Sizes.tapTarget,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  gradient: fill == null
                      ? const SweepGradient(
                          colors: [
                            Color(0xFFE53935),
                            Color(0xFFFDD835),
                            Color(0xFF43A047),
                            Color(0xFF00ACC1),
                            Color(0xFF3949AB),
                            Color(0xFF8E24AA),
                            Color(0xFFE53935),
                          ],
                        )
                      : null,
                  border: selected
                      ? Border.all(color: scheme.onSurface, width: 2.5, strokeAlign: BorderSide.strokeAlignOutside)
                      : Border.all(color: scheme.outlineVariant),
                ),
                child: selected
                    ? Icon(AppIcons.check, size: 18, color: fg)
                    : (icon == null ? null : Icon(icon, size: 18, color: fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Свой цвет»: оттенок и насыщенность (яркость под светлую и тёмную тему
/// подбирается сама — текст всегда читается). Без сторонних пакетов.
class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});

  final Color initial;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late double _hue = HSLColor.fromColor(widget.initial).hue;
  late double _sat = math.max(HSLColor.fromColor(widget.initial).saturation, 0.0);

  Color get _base => AccentFit.hsl(_hue, _sat, 0.45);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final on = theme.colorScheme.surfaceContainerHighest;
    final shown = dark ? AccentFit.dark(_base, on) : AccentFit.light(_base, on);
    final onShown = ThemeData.estimateBrightnessForColor(shown) == Brightness.dark ? Colors.white : Colors.black;
    return AlertDialog(
      title: Text(l10n.tr('apAccentCustom')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Пример: кнопка и подпись цветом акцента — как в приложении.
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: shown, shape: BoxShape.circle),
                  child: Icon(AppIcons.check, color: onShown, size: 20),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    l10n.tr('apAccent'),
                    style: theme.textTheme.titleMedium?.copyWith(color: shown, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.l),
            Text(l10n.tr('apHue'), style: theme.textTheme.labelLarge),
            _GradientSlider(
              value: _hue / 360,
              colors: [for (var h = 0; h <= 360; h += 30) AccentFit.hsl(h.toDouble(), 0.85, 0.5)],
              onChanged: (v) => setState(() => _hue = v * 360),
              semantic: '${_hue.round()}°',
            ),
            Text(l10n.tr('apSaturation'), style: theme.textTheme.labelLarge),
            _GradientSlider(
              value: _sat,
              colors: [AccentFit.hsl(_hue, 0, 0.5), AccentFit.hsl(_hue, 1, 0.45)],
              onChanged: (v) => setState(() => _sat = v),
              semantic: '${(_sat * 100).round()}%',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(_base), child: Text(l10n.tr('done'))),
      ],
    );
  }
}

/// Ползунок на цветной полосе (оттенок, насыщенность).
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({required this.value, required this.colors, required this.onChanged, required this.semantic});

  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final String semantic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: Sizes.tapTarget,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 24,
            right: 24,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(colors: colors),
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 12,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: scheme.onSurface.withValues(alpha: 0.08),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 2),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
              semanticFormatterCallback: (_) => semantic,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Выбор чипами ─────────────────────────

/// Выбор одного из немногих вариантов чипами (как «Масштаб интерфейса» в
/// «Общих»).
class _Chips<T> extends StatelessWidget {
  const _Chips({required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String, Widget?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
    child: Wrap(
      spacing: Space.s,
      runSpacing: Space.xs,
      children: [
        for (final o in options)
          ChoiceChip(
            avatar: o.$3,
            label: Text(o.$2),
            selected: value == o.$1,
            showCheckmark: o.$3 == null,
            onSelected: (_) => onChanged(o.$1),
          ),
      ],
    ),
  );
}

/// Значок скругления для чипа: уголок рамки с радиусом [radius].
class _CornerGlyph extends StatelessWidget {
  const _CornerGlyph({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return CustomPaint(size: const Size(16, 16), painter: _CornerPainter(radius, c));
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.radius, this.color);

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 2.0;
    final path = Path()
      ..moveTo(w / 2, size.height)
      ..lineTo(w / 2, w / 2 + radius)
      ..arcToPoint(Offset(w / 2 + radius, w / 2), radius: Radius.circular(radius))
      ..lineTo(size.width, w / 2);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.radius != radius || old.color != color;
}
