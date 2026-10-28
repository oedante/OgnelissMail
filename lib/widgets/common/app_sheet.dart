// lib/widgets/common/app_sheet.dart
// Нижняя шторка с учётом системных отступов (edge-to-edge).
//
// С targetSdk 35+ Android рисует приложение под строкой состояния и панелью
// навигации, отключить это нельзя (Android 16). showModalBottomSheet сам
// отступы не добавляет — кнопки внизу шторки уходили под жестовую полосу или
// кнопки навигации. Все шторки приложения открываются через эту функцию.

import 'package:flutter/material.dart';

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  Color? backgroundColor,
  bool? showDragHandle,
  BoxConstraints? constraints,
}) {
  return showModalBottomSheet<T>(
    context: context,
    shape: shape,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor,
    showDragHandle: showDragHandle,
    constraints: constraints,
    useSafeArea: true,
    // Над всем приложением: в навигаторе вкладки шторку перекрывали
    // плавающая кнопка и нижняя панель (календарь, 07.10.2026).
    useRootNavigator: true,
    builder: (ctx) => SafeArea(top: false, child: builder(ctx)),
  );
}
