// lib/widgets/navigation/app_bottom_bar.dart
// Нижняя панель по образцу Ogneliss Dialer (решение владельца 08.10.2026):
// «Почта · Календарь · [Создать] · Контакты · Меню» (с 1.6.40 вместо «Ещё» —
// портрет ящика, открывает меню ящиков, папок и избранного). Плавающих кнопок нет —
// они перекрывали последнюю строку списка; главное действие раздела —
// крупная кнопка в центре панели («Написать» в почте, «Встреча» в
// календаре и т. д.).
//
// Вкладка — пилюля 56×32 со значком, под ней подпись. Высота определяется
// содержимым (крупный шрифт не обрезается); системный отступ снизу задаёт
// SafeArea приложения (main.dart).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../common/quick_long_press.dart';
import 'package:flutter/services.dart';

import '../../core/theme/ogneliss_look.dart';
import '../../core/theme/tokens.dart';
import '../../features/mail/providers/account_look.dart' show BarLook;
import '../common/text_scale_cap.dart';

/// Центральное действие панели.
class PanelAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Удержание кнопки (1.6.47: меню «Письмо / Встреча / Задача»); получает
  /// context самой кнопки — меню показывается над ней.
  final void Function(BuildContext button)? onLongPress;

  const PanelAction({required this.icon, required this.label, required this.onPressed, this.onLongPress});
}

class AppBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  /// Кнопка в центре (между первой и второй половинами вкладок).
  final PanelAction? center;

  /// Долгое нажатие на вкладку (у «Почты» — выбор ящика под пальцем).
  final ValueChanged<int>? onLongPressed;

  /// Слот слева от вкладок постоянной ширины (аватар ящика — открывает
  /// меню ящиков и папок).
  final Widget? leading;

  /// Окраска цветом ящика (в почте одного ящика, 1.6.2): фон, полоса,
  /// градиент или заливка — по стилю из «Цвета аккаунта».
  final BarLook? look;

  const AppBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    this.center,
    this.onLongPressed,
    this.leading,
    this.look,
  });

  /// Нижняя панель используется (телефон). На планшете и компьютере —
  /// боковая навигация, и экранам нужны свои кнопки «Создать».
  static bool inUse(BuildContext context) {
    final desktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    return !desktop && MediaQuery.sizeOf(context).width < 600;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = this.look;
    final bg = look?.background ?? theme.navigationBarTheme.backgroundColor ?? scheme.surfaceContainer;
    // Заливка: текст и значки — белые или чёрные по яркости цвета ящика.
    final fg = look?.foreground;
    final half = (destinations.length / 2).ceil();
    Widget tab(int i) => Expanded(
          child: _Item(
            destination: destinations[i],
            selected: i == selectedIndex,
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(i);
            },
            onLongPress: onLongPressed == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onLongPressed!(i);
                  },
          ),
        );
    // Подписи вкладок растут с системным шрифтом умеренно: при ×2 пять
    // подписей не помещаются и наезжают на соседние.
    Widget content = Padding(
      // Сверху — место для значка с числом непрочитанных: раньше он
      // выходил за верх панели (замечание 09.10.2026).
      padding: const EdgeInsets.only(top: Space.m, bottom: Space.s - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) SizedBox(width: Sizes.bottomLeadingWidth, child: leading),
          for (var i = 0; i < half; i++) tab(i),
          if (center != null) Expanded(child: _Center(action: center!)),
          for (var i = half; i < destinations.length; i++) tab(i),
        ],
      ),
    );
    if (fg != null) {
      content = Theme(
        data: theme.copyWith(
          colorScheme: scheme.copyWith(
            onSurface: fg,
            onSurfaceVariant: fg.withValues(alpha: 0.8),
            secondaryContainer: fg.withValues(alpha: 0.18),
            onSecondaryContainer: fg,
          ),
        ),
        child: content,
      );
    }
    // Градиент — через Ink: рисуется на слое Material, отклик касания
    // остаётся виден поверх него.
    if (look?.gradient case final g?) {
      content = Ink(decoration: BoxDecoration(gradient: g), child: content);
    }
    return TextScaleCap(
      child: Material(
        color: bg,
        // Тонкая линия сверху — граница с лентой и в светлой, и в тёмной
        // теме (1.8.0, «воздушный» вид: 1 dp, панель плоская, без тени);
        // у стиля «Полоса» — полоса цвета ящика.
        shape: look?.shape ?? Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
        child: content,
      ),
    );
  }
}

class _Center extends StatelessWidget {
  final PanelAction action;
  const _Center({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hold = action.onLongPress;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      onLongPress: hold == null ? null : () => hold(context),
      // Align с heightFactor: 1 — по высоте кнопки. Center растягивался на
      // всю доступную высоту, и панель занимала весь экран (1.4.0+22).
      child: Align(
        heightFactor: 1,
        child: Tooltip(
          message: action.label,
          // Удержание — меню над кнопкой (1.6.47); палец можно довести до
          // пункта и отпустить.
          child: Builder(builder: (button) => QuickLongPress(
          onLongPress: hold == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  hold(button);
                },
          tracker: HoldPointer.instance,
          child: Material(
            color: scheme.primaryContainer,
            shape: const StadiumBorder(),
            // Без тени (1.8.0, «воздушный» вид), тень — в высоком контрасте.
            elevation: OgnelissLook.of(context).outlined ? 1 : 0,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                action.onPressed();
              },
              child: SizedBox(
                width: Sizes.composeButton,
                height: Sizes.tapTarget,
                child: Icon(action.icon, color: scheme.onPrimaryContainer, size: Sizes.icon),
              ),
            ),
          ),
          )),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Item({required this.destination, required this.selected, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: Sizes.panelPillWidth,
              height: Sizes.panelPillHeight,
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(Sizes.panelPillHeight / 2),
              ),
              alignment: Alignment.center,
              child: IconTheme.merge(
                data: IconThemeData(color: fg, size: Sizes.icon),
                child: selected ? (destination.selectedIcon ?? destination.icon) : destination.icon,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
