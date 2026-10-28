// lib/widgets/ui/app_radio_tile.dart
// Строка выбора одного варианта. Во Flutter 3.35+ groupValue/onChanged у
// RadioListTile устарели — состоянием управляет RadioGroup. Обёртка
// сохраняет прежнюю форму вызова (value, groupValue, onChanged) и строит
// RadioGroup вокруг одной строки: выбранной считается строка, у которой
// value == groupValue, нажатие вызывает onChanged.

import 'package:flutter/material.dart';

class AppRadioTile<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?> onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;

  const AppRadioTile({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: RadioListTile<T>(
          value: value,
          title: title,
          subtitle: subtitle,
          secondary: secondary,
        ),
      );
}
