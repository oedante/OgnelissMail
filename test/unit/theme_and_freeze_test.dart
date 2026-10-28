// Выбор темы (меню «Ещё», 10.10.2026), общая палитра кружков с буквой и
// отметка «система замораживает приложение».
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/avatar_colors.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/services/background/foreground_sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Относительная яркость по WCAG 2.x.
double _lum(int argb) {
  double lin(int v) {
    final c = v / 255;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }
  return 0.2126 * lin((argb >> 16) & 255) + 0.7152 * lin((argb >> 8) & 255) + 0.0722 * lin(argb & 255);
}

void main() {
  group('Выбор темы', () {
    test('«Чтение» важнее остального, AMOLED — вариант тёмной', () {
      expect(const AppSettings(reading: true, themeMode: ThemeMode.light).themeChoice, AppThemeChoice.reading);
      expect(const AppSettings(amoled: true, themeMode: ThemeMode.dark).themeChoice, AppThemeChoice.amoled);
      expect(const AppSettings(themeMode: ThemeMode.dark).themeChoice, AppThemeChoice.dark);
      expect(const AppSettings(themeMode: ThemeMode.light).themeChoice, AppThemeChoice.light);
      expect(const AppSettings().themeChoice, AppThemeChoice.system);
    });
  });

  group('Кружки с буквой', () {
    test('цвет постоянный и не зависит от регистра адреса', () {
      expect(avatarColorValue('Ivan@Firm.ru'), avatarColorValue('ivan@firm.ru'));
      expect(kAvatarColorValues, contains(avatarColorValue('кто-то@почта.рф')));
    });

    test('белая буква читается на каждом цвете (≥ 4.5:1)', () {
      for (final c in kAvatarColorValues) {
        final ratio = (1.0 + 0.05) / (_lum(c) + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: c.toRadixString(16));
      }
    });
  });

  group('Заморозка приложения системой', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('нет отметки — не заморожено; свежая — да; старше 3 дней — нет', () async {
      final p = await SharedPreferences.getInstance();
      expect(ForegroundSyncController.frozenRecently(p), isFalse);
      await p.setInt(ForegroundSyncController.frozenLastKey,
          DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch);
      expect(ForegroundSyncController.frozenRecently(p), isTrue);
      await p.setInt(ForegroundSyncController.frozenLastKey,
          DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch);
      expect(ForegroundSyncController.frozenRecently(p), isFalse);
    });

    test('сброс убирает все отметки', () async {
      final p = await SharedPreferences.getInstance();
      await p.setInt(ForegroundSyncController.frozenCountKey, 3);
      await p.setInt(ForegroundSyncController.frozenLastKey, DateTime.now().millisecondsSinceEpoch);
      await p.setInt(ForegroundSyncController.frozenMinutesKey, 17);
      await ForegroundSyncController.clearFrozen(p);
      expect(p.getInt(ForegroundSyncController.frozenCountKey), isNull);
      expect(ForegroundSyncController.frozenRecently(p), isFalse);
    });
  });
}
