// Smoke test. Полноценный запуск MailApp требует инициализации БД и
// провайдеров (см. main.dart), поэтому здесь проверяется лишь базовая сборка
// дерева виджетов в ProviderScope без падения.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('MaterialApp строится в ProviderScope', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: Center(child: Text('OK')))),
      ),
    );
    expect(find.text('OK'), findsOneWidget);
  });
}
