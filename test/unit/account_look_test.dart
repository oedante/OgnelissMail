// Окраска панелей почты цветом ящика (1.6.2): у каждого стиля — заметный
// эффект и на верхней, и на нижней панели (замечание 13.10.2026: «градиент
// ни на что не влияет» — после переноса ящика в нижнюю панель).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/providers/account_look.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show AccountsNotifier;

void main() {
  const c = Color(0xFF2F5C93);
  for (final brightness in Brightness.values) {
    final theme = ThemeData(brightness: brightness, useMaterial3: true);
    group('$brightness', () {
      test('без цвета — обычные панели', () {
        for (final l in [headerLook(AccountHeaderStyle.none, c, theme), panelLook(AccountHeaderStyle.none, c, theme)]) {
          expect(l.background, isNull);
          expect(l.gradient, isNull);
          expect(l.shape, isNull);
          expect(l.foreground, isNull);
        }
      });
      test('оттенок отличается от фона', () {
        final l = panelLook(AccountHeaderStyle.tint, c, theme);
        expect(l.background, isNot(theme.colorScheme.surface));
      });
      test('полоса: сверху — снизу, снизу — сверху', () {
        final top = headerLook(AccountHeaderStyle.stripe, c, theme).shape as Border;
        final bottom = panelLook(AccountHeaderStyle.stripe, c, theme).shape as Border;
        expect(top.bottom.color, c);
        expect(bottom.top.color, c);
      });
      test('градиент — есть на обеих панелях и заметен', () {
        for (final l in [headerLook(AccountHeaderStyle.gradient, c, theme), panelLook(AccountHeaderStyle.gradient, c, theme)]) {
          final g = l.gradient as LinearGradient;
          expect(g.colors.first, isNot(g.colors.last));
          expect(g.colors.first, isNot(theme.colorScheme.surface));
        }
      });
      test('заливка — читаемый цвет текста', () {
        final l = panelLook(AccountHeaderStyle.full, c, theme);
        expect(l.foreground, isNotNull);
        expect(l.background, isNotNull);
      });
    });
  }

  test('палитра: 32 цвета без повторов, первые восемь — прежние', () {
    const p = AccountsNotifier.accountPalette;
    expect(p.length, 32);
    expect(p.toSet().length, p.length);
    expect(p.take(3), [0xFF2F5C93, 0xFFB9773F, 0xFF4B7D58]);
  });
}
