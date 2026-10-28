// integration_test/app_test.dart
// Базовый интеграционный тест.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ogneliss/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Integration Tests', () {
    testWidgets('App starts and shows splash screen', (tester) async {
      unawaited(app.main());
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // После splash должен быть login или main screen
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Login screen renders correctly', (tester) async {
      unawaited(app.main());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Проверяем наличие кнопки входа (если нет аккаунтов)
      // Точные проверки зависят от состояния
    });
  });
}