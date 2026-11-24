// Тема из тех же настроек — та же тема (2.7.1, микрофризы 24.11.2026).
//
// Расширения темы (AppearanceLook, OgnelissLook) не умели сравниваться, и
// тема, собранная заново из тех же настроек, считалась другой. Корень
// приложения перестраивается при любой настройке — в том числе при смене
// ящика, — и MaterialApp 350 мс «перетекал» из темы в такую же, каждый кадр
// перестраивая всё, что зависит от темы (весь интерфейс): 44 кадра на
// смену ящика.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/core/theme/appearance.dart';
import 'package:ogneliss/core/theme/ogneliss_look.dart';

void main() {
  const fancy = Appearance(
    preset: ThemePreset.forest,
    accent: 0xFF3366CC,
    tint: ListTint.soft,
    corners: CornerSize.large,
    density: ListDensity.compact,
  );
  final variants = <String, ThemeData Function()>{
    'светлая': () => AppTheme.lightTheme(1.0),
    'светлая, высокий контраст, крупный шрифт': () => AppTheme.lightTheme(1.2, highContrast: true, dyslexiaFont: true),
    'светлая, своё оформление': () => AppTheme.lightTheme(1.0, appearance: fancy),
    'светлая, цвета обоев': () =>
        AppTheme.lightTheme(1.0, dynamicScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A5CFA))),
    'тёмная': () => AppTheme.darkTheme(1.0, appearance: fancy),
    'AMOLED': () => AppTheme.amoledTheme(1.0),
    '«Чтение»': () => AppTheme.readingTheme(1.0, appearance: fancy),
  };

  for (final v in variants.entries) {
    test('${v.key}: собранная дважды — равна', () {
      final a = AppTheme.withTransitions(v.value(), true);
      final b = AppTheme.withTransitions(v.value(), true);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  }

  test('расширения темы сравниваются по значению', () {
    // ignore: prefer_const_constructors — сравнение не-const экземпляра с const
    expect(const OgnelissLook(outlined: true), OgnelissLook(outlined: true, cardBorder: false));
    expect(const OgnelissLook(outlined: true) == const OgnelissLook(), isFalse);
    expect(
        const AppearanceLook(density: ListDensity.compact, listFill: Color(0xFF010203)),
        // ignore: prefer_const_constructors — сравнение не-const экземпляра с const
        AppearanceLook(density: ListDensity.compact, listFill: const Color(0xFF010203)));
    expect(const AppearanceLook(openAnimation: true) == const AppearanceLook(), isFalse);
  });

  testWidgets('корень перестроился с той же темой — без анимации темы и пересборки экранов', (tester) async {
    var builds = 0;
    Widget app(ThemeData theme) => MaterialApp(
          theme: theme,
          themeAnimationDuration: const Duration(milliseconds: 350),
          home: Builder(builder: (c) {
            Theme.of(c);
            builds++;
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(app(AppTheme.withTransitions(AppTheme.lightTheme(1.0, appearance: fancy), true)));
    builds = 0;
    await tester.pumpWidget(app(AppTheme.withTransitions(AppTheme.lightTheme(1.0, appearance: fancy), true)));
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'анимация смены темы не запускается');
    expect(builds, lessThanOrEqualTo(1));
    // Настоящая смена темы — по-прежнему плавная.
    await tester.pumpWidget(app(AppTheme.withTransitions(AppTheme.darkTheme(1.0), true)));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
  });
}
