// lib/features/settings/screens/automation_screen.dart
// Раздел «Автоматизация» — правила обработки писем (AutoRule).
//
// Вкладка правил категоризации ИИ убрана вместе с локальным ИИ (этап 1
// плана); маршрут /settings/automation сохранён, чтобы не менять точки входа.

import 'package:flutter/material.dart';

import 'rules_screen.dart';

class AutomationScreen extends StatelessWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context) => const RulesScreen();
}
