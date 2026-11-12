// Движок рисования (08.11.2026, чёрный экран на HUAWEI DEL-LX9: падение
// Impeller на OpenGL ES при передаче картинки в видеопамять). Проверяем:
// разбор состояния из Android, строки для журнала и диагностики, пункт
// «Расширенные → Графика» (выбор и «Перезапустить» только когда нужно) и
// ограничение размера декодируемых картинок.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/graphics_mode.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/settings/widgets/graphics_item.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/photo_viewer.dart';

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.lightTheme(1.0),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: home),
    );

Future<void> _settle(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 30));
    if (ready()) break;
  }
}

/// Как отвечает Android после падения Impeller 08.11.2026 09:59.
Map<Object?, Object?> _afterCrash({String mode = 'auto', String next = 'skia'}) => {
      'mode': mode,
      'active': 'skia',
      'next': next,
      'backend': null,
      'autoSkia': true,
      'autoAt': DateTime(2026, 11, 8, 9, 59, 24).millisecondsSinceEpoch,
      'autoReason': '[FATAL:flutter/impeller/renderer/backend/gles/blit_pass_gles.cc(88)] Check failed: result.',
      'memory': {
        'totalMb': 3712,
        'availMb': 905,
        'thresholdMb': 216,
        'low': false,
        'lowRamDevice': false,
        'appLimitMb': 256,
        'appPssMb': 183,
      },
      'gpu': 'чип mt6765, EGL mali, Vulkan 1.1+',
    };

void main() {
  group('GraphicsState', () {
    test('после сбоя Impeller: Skia, причина, память', () {
      final s = GraphicsState.fromMap(_afterCrash());
      expect(s.active, 'skia');
      expect(s.autoSkia, isTrue);
      expect(s.autoAt, DateTime(2026, 11, 8, 9, 59, 24));
      expect(s.restartNeeded, isFalse);
      expect(s.summary, 'Skia (совместимость), автоматически после сбоя Impeller 2026-11-08T09:59');
      expect(s.memorySummary,
          'всего 3712 МБ, свободно 905 МБ (порог 216), мало: нет; приложению до 256 МБ, занято 183 МБ');
      expect(s.gpu, 'чип mt6765, EGL mali, Vulkan 1.1+');
    });

    test('Impeller с известным путём; выбор вступит после перезапуска', () {
      final s = GraphicsState.fromMap({
        'mode': 'skia',
        'active': 'impeller',
        'next': 'skia',
        'backend': 'OpenGLES',
        'autoSkia': false,
        'autoAt': 0,
      });
      expect(s.restartNeeded, isTrue);
      expect(s.autoAt, isNull);
      expect(s.memorySummary, isEmpty);
      expect(s.gpu, isNull);
      expect(s.summary, 'Impeller (OpenGLES), выбрано вручную; после перезапуска — Skia');
    });

    test('Huawei: Impeller был бы на OpenGL ES — Skia сразу, без сбоя', () {
      final s = GraphicsState.fromMap({
        'mode': 'auto',
        'active': 'skia',
        'next': 'skia',
        'glesReason': 'Huawei',
        'autoSkia': false,
      });
      expect(s.glesReason, 'Huawei');
      expect(s.restartNeeded, isFalse);
      expect(s.summary, 'Skia (совместимость), автоматически: Impeller здесь работал бы через OpenGL ES (Huawei)');
      expect(GraphicsState.fromMap(const {'glesReason': ''}).glesReason, isNull);
    });

    test('HCPP: выключатель применяется после перезапуска; в журнале — работает ли', () {
      final off = GraphicsState.fromMap(const {'hcppSupported': true});
      expect(off.hcpp, isFalse);
      expect(off.restartNeeded, isFalse);
      final picked = GraphicsState.fromMap(const {'hcpp': true, 'hcppNext': true, 'hcppSupported': true});
      expect(picked.restartNeeded, isTrue);
      expect(picked.summary, 'Impeller, автоматически; после перезапуска HCPP включится');
      final on = GraphicsState.fromMap(
          const {'hcpp': true, 'hcppNext': true, 'hcppActive': true, 'hcppSupported': true, 'backend': 'Vulkan'});
      expect(on.restartNeeded, isFalse);
      expect(on.summary, 'Impeller (Vulkan), автоматически; встроенные окна — HCPP');
      // Включён, но телефон не подходит (нет Vulkan) или выбран Skia — не работает и не просит перезапуска.
      expect(GraphicsState.fromMap(const {'hcpp': true}).restartNeeded, isFalse);
    });

    test('пустой ответ — значения по умолчанию', () {
      final s = GraphicsState.fromMap(const {});
      expect(s.mode, 'auto');
      expect(s.active, 'impeller');
      expect(s.restartNeeded, isFalse);
      expect(s.summary, 'Impeller, автоматически');
    });

    test('не Android — состояния нет, канал не трогаем', () async {
      expect(GraphicsMode.supported, Platform.isAndroid);
      if (!Platform.isAndroid) expect(await GraphicsMode.state(), isNull);
    });
  });

  testWidgets('пункт «Графика»: режим, сейчас, дата сбоя', (tester) async {
    await tester.pumpWidget(_app(GraphicsItem(load: () async => GraphicsState.fromMap(_afterCrash()))));
    await _settle(tester, () => find.text('Графика').evaluate().isNotEmpty);
    expect(find.text('Графика'), findsOneWidget);
    expect(find.textContaining('Автоматически · Сейчас: Skia (после сбоя 08.11.2026)'), findsOneWidget);
  });

  testWidgets('выбор в окне: «Перезапустить» — только когда выбор ещё не применён', (tester) async {
    final picked = <String>[];
    var restarts = 0;
    await tester.pumpWidget(_app(GraphicsDialog(
      initial: GraphicsState.fromMap(_afterCrash()),
      setMode: (m) async {
        picked.add(m);
        return GraphicsState.fromMap(_afterCrash(mode: m, next: m == 'impeller' ? 'impeller' : 'skia'));
      },
      restart: () async => restarts++,
    )));
    await tester.pump();
    expect(find.text('Перезапустить'), findsNothing, reason: 'Skia уже работает');

    await tester.tap(find.text('Новый движок (Impeller)'));
    await _settle(tester, () => find.text('Перезапустить').evaluate().isNotEmpty);
    expect(picked, ['impeller']);
    expect(find.textContaining('Изменение применится после перезапуска'), findsOneWidget);
    await tester.tap(find.text('Перезапустить'));
    await tester.pump();
    expect(restarts, 1);

    await tester.tap(find.text('Совместимость (Skia)'));
    await _settle(tester, () => find.text('Перезапустить').evaluate().isEmpty);
    expect(picked, ['impeller', 'skia']);
    expect(find.text('Перезапустить'), findsNothing);
  });

  testWidgets('HCPP: выключатель — только на подходящем телефоне; включение просит перезапуск', (tester) async {
    await tester.pumpWidget(_app(GraphicsDialog(initial: GraphicsState.fromMap(_afterCrash()))));
    await tester.pump();
    expect(find.byKey(const ValueKey('graphics_hcpp')), findsNothing, reason: 'телефон не подходит');

    final asked = <bool>[];
    await tester.pumpWidget(_app(GraphicsDialog(
      key: UniqueKey(),
      initial: GraphicsState.fromMap(const {'mode': 'auto', 'active': 'impeller', 'next': 'impeller', 'hcppSupported': true}),
      setHcpp: (on) async {
        asked.add(on);
        return GraphicsState.fromMap(
            {'mode': 'auto', 'active': 'impeller', 'next': 'impeller', 'hcppSupported': true, 'hcpp': on, 'hcppNext': on});
      },
    )));
    await tester.pump();
    expect(find.text('Новое встраивание окна письма (HCPP)'), findsOneWidget);
    expect(find.text('Перезапустить'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('graphics_hcpp')));
    await _settle(tester, () => find.text('Перезапустить').evaluate().isNotEmpty);
    expect(asked, [true]);
    expect(find.text('Перезапустить'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('graphics_hcpp')));
    await _settle(tester, () => find.text('Перезапустить').evaluate().isEmpty);
    expect(asked, [true, false]);
    expect(find.text('Перезапустить'), findsNothing);
  });

  test('картинки на весь экран декодируются не больше 4096 точек', () {
    final img = MemoryImage(Uint8List(4));
    final p = limitDecode(img);
    expect(p, isA<ResizeImage>());
    final r = p as ResizeImage;
    expect(r.width, 4096);
    expect(r.height, 4096);
    expect(r.policy, ResizeImagePolicy.fit);
    expect(r.allowUpscaling, isFalse, reason: 'маленькие картинки — как есть');
    expect(identical(limitDecode(p), p), isTrue, reason: 'второй раз не оборачиваем');
  });
}
