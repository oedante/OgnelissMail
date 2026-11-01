// lib/core/theme/app_theme.dart
// Корпоративные темы с полной палитрой.

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'appearance.dart';
import 'ogneliss_look.dart';
import 'theme_palette.dart';
import 'tokens.dart';

class AppColors {
  AppColors._();

  // ── Бренд: деловая палитра ──
  // Основной цвет — глубокий синий (спокойный для глаз при долгой работе,
  // контраст с белым 8.1:1). Тёплый янтарный — только для знака приложения и
  // мелких акцентов (звёзды, VIP), не для заливок интерфейса.
  static const brandBlue = Color(0xFF1D4F91);
  static const brandNavy = Color(0xFF0F2742); // тёмная база (заставка, блокировка)
  static const brandAmber = Color(0xFFE39B2D); // знак приложения

  // Старые имена (широко используются): primaryBlue — основной синий,
  // brandDark — тёмная база, brandYellow — янтарь знака.
  static const primaryBlue = brandBlue;
  static const primaryDark = brandNavy;
  static const brandDark = brandNavy;
  static const brandYellow = brandAmber;
  // Цвета состояний — приглушённые (09.10.2026): прежние «бутстраповские»
  // #FF8C00 / #28A745 / #DC3545 / #FFC107 / #17A2B8 были кричащими для
  // делового приложения, которое держат открытым весь день.
  static const accentOrange = Color(0xFFD9822B);
  static const successGreen = Color(0xFF2E8B57);
  static const errorRed = Color(0xFFC9443C);
  static const warningYellow = Color(0xFFE0B03A);
  static const infoBlue = Color(0xFF2B8A9E);
  // Читаемый цвет ссылок (жёлтый для текста-ссылок не подходит по контрасту).
  static const linkBlue = Color(0xFF2F6FE0);

  /// Нейтральный цвет ПЕРЕДНЕГО плана для иконок/текста: тёмный на светлой
  /// теме, светлый на тёмной (через onSurface). Требует BuildContext.
  static Color accent(BuildContext context) => Theme.of(context).colorScheme.onSurface;

  // ─────────── Варианты, БЕЗОПАСНЫЕ ДЛЯ ТЕКСТА И ИКОНОК (WCAG AA) ───────────
  // Константы выше рассчитаны на ЗАЛИВКУ (бейджи, полосы, индикаторы) — там они
  // соседствуют с белым/чёрным текстом и работают. Как ЦВЕТ ТЕКСТА на фоне темы
  // многие из них контраст НЕ проходят. Замеры (норма AA для обычного текста —
  // 4.5:1), палитра 09.10.2026:
  //   фон #FFFFFF (светлая): brandBlue 8.1 ✓ · warningYellow 2.0 ✗ ·
  //                          accentOrange 2.9 ✗ · infoBlue 4.0 ✗ ·
  //                          successGreen 4.25 ✗ · errorRed 4.8 ✓ · linkBlue 4.70 ✓
  //   фон #161A20 (тёмная):  errorRed 3.6 ✗ · successGreen 4.1 ✗ · infoBlue 4.35 ✗ ·
  //                          linkBlue 3.36 ✗ · остальные ✓
  // Ниже — варианты с сохранённым тоном, подобранные до AA. Осветлённые варианты
  // проходят и на AMOLED (≈6.0:1), поэтому наборов два, а не три.
  //
  // Использовать ТАМ, ГДЕ ЦВЕТ — ЭТО ТЕКСТ ИЛИ ИКОНКА на фоне поверхности.
  // Для заливок оставляйте исходные константы.
  static bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  /// Успех как текст: ≈5.0:1 на светлой, 6.7:1 на тёмной.
  static Color successText(BuildContext c) =>
      _isDark(c) ? const Color(0xFF4FB37E) : const Color(0xFF277A4C);

  /// Ошибка как текст: 4.8:1 на светлой, 5.3:1 на тёмной (6.4:1 на AMOLED).
  static Color errorText(BuildContext c) => errorTextOn(Theme.of(c));

  /// То же по теме (там, где под рукой ThemeData, а не BuildContext). 1.6.44:
  /// «Удалить» в меню и текст ошибок шли константой [errorRed] — на тёмной
  /// теме это 3.6:1, ниже нормы AA для текста.
  static Color errorTextOn(ThemeData t) =>
      t.brightness == Brightness.dark ? const Color(0xFFE06A62) : errorRed;

  /// Предупреждение как текст: 5.1:1 на светлой, 8.7:1 на тёмной.
  static Color warningText(BuildContext c) =>
      _isDark(c) ? warningYellow : const Color(0xFF8A6A00);

  /// Информация как текст: 5.5:1 на светлой, 6.9:1 на тёмной.
  static Color infoText(BuildContext c) =>
      _isDark(c) ? const Color(0xFF4FB0C4) : const Color(0xFF1F7383);

  /// Оранжевый акцент как текст: 4.9:1 на светлой, 7.5:1 на тёмной.
  static Color accentOrangeText(BuildContext c) =>
      _isDark(c) ? const Color(0xFFE59A4E) : const Color(0xFFA85F12);

  /// Ссылка как текст: 4.70:1 на светлой, 4.51:1 на тёмной (6.02:1 на AMOLED).
  static Color linkText(BuildContext c) =>
      _isDark(c) ? const Color(0xFF5388E5) : linkBlue;

  /// Приглушённый текст (подписи, вторичное). Замена россыпи Colors.grey.shadeN,
  /// которая не адаптируется к теме.
  static Color mutedText(BuildContext c) =>
      Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.65);

  // ─────────── Границы и подложки (аудит цветов 10.10.2026) ───────────
  // Замеры: подложка групп настроек (surfaceContainerLow) на светлой теме
  // совпадала с фоном экрана (1.00:1), рамка фото (outlineVariant) — 1.3:1,
  // карточки в AMOLED — 1.06:1. Ниже — значения, которые отличимы от фона.

  /// Рамка вокруг фото человека/ящика: ≈2:1 к фону на светлой теме,
  /// ≈3:1 на тёмной и AMOLED, ≈2.4:1 в «Чтении».
  static Color avatarRing(BuildContext c) {
    final t = Theme.of(c);
    // Мягче (1.6.20): кольцо светлее и тоньше (PhotoRing, 1 px).
    if (t.brightness == Brightness.dark) return const Color(0xFF4A5462);
    return t.scaffoldBackgroundColor == AppTheme.readingScaffold
        ? const Color(0xFFBDB3A2)
        : const Color(0xFFC3CBD6);
  }

  /// Фон ленты писем и беседы (1.6.25, замечание владельца «интерфейс стал
  /// очень серым, беседы сливаются»): светлая тема — белый, строки разделены
  /// тонкой линией; тёмная — на ступень светлее фона экрана. С оттенком из
  /// «Оформления» (1.9.x) — чуть цвета акцента поверх.
  static Color listFill(BuildContext c) => AppearanceLook.of(c).listFill ?? Theme.of(c).colorScheme.surface;

  /// Подложка карточки или группы строк — отличима от фона экрана в любой
  /// теме: светлая — белая на светло-сером фоне, тёмная — на ступень светлее.
  static Color cardFill(BuildContext c) {
    final s = Theme.of(c).colorScheme;
    return _isDark(c) ? s.surfaceContainer : s.surfaceContainerLowest;
  }

  /// Тонкая граница карточки: там, где подложка почти как фон (AMOLED,
  /// «Чтение»), карточка всё равно видна.
  static Color cardEdge(BuildContext c) => Theme.of(c).colorScheme.outlineVariant;

  /// Рамка карточки по виду (1.8.0): в «воздушном» виде её нет — карточку
  /// отделяет тон; в высоком контрасте, AMOLED и «Чтении» — тонкая линия.
  static BorderSide cardSide(BuildContext c, {double alpha = 1}) => OgnelissLook.of(c).cardBorder
      ? BorderSide(color: cardEdge(c).withValues(alpha: alpha))
      : BorderSide.none;


  // Теги и цвета-метки (встречи, статусы) — приглушённые средние тона
  // (09.10.2026, вместо ярких Material 500): различимы, белый текст
  // читается, не пестрят при долгой работе.
  static const tagProduction = Color(0xFF456EA3);
  static const tagMaintenance = Color(0xFF7E5A9E);
  static const tagFinance = Color(0xFF467E59);
  static const tagHR = Color(0xFF9E6B2A);
  static const tagHSE = Color(0xFFB0504B);
  static const tagLogistics = Color(0xFF357F7A);
  static const tagManagement = Color(0xFF5E4F9A);
  static const tagIT = Color(0xFF5E6E7E);
  static const tagAssignment = Color(0xFFA3536F);
  static const tagGeneral = Color(0xFF8A9099);
  static const tagPurchasing = Color(0xFF7D6456);
  static const tagLegal = Color(0xFF555FA0);
}

/// Цвета действий свайпа — тональные, как контейнеры Material 3: светлая
/// заливка и тёмный значок того же тона (в тёмной теме — наоборот). Прежние
/// насыщенные заливки с белым значком утомляли глаза (09.10.2026). Контраст
/// значка к заливке — не ниже 5.3:1.
abstract final class SwipeTone {
  static const _light = <int, (Color, Color)>{
    0xFFC9443C: (Color(0xFFF6DCDA), Color(0xFF8C2F2B)), // удалить
    0xFFD9822B: (Color(0xFFF5E6CC), Color(0xFF7A4E0E)), // спам, позже
    0xFF1D4F91: (Color(0xFFDCE5F2), Color(0xFF1D4F91)), // архив, ответ, переслать
    0xFF2B8A9E: (Color(0xFFD8ECEF), Color(0xFF1F5F6B)), // прочитано
    0xFF2E8B57: (Color(0xFFDDEEDF), Color(0xFF2E6B3F)), // задача, на контроль
    0xFFE0B03A: (Color(0xFFF4EBC8), Color(0xFF6E5A12)), // флаг
  };
  static const _dark = <int, (Color, Color)>{
    0xFFC9443C: (Color(0xFF4A2624), Color(0xFFF2B8B5)),
    0xFFD9822B: (Color(0xFF45351E), Color(0xFFEAC48A)),
    0xFF1D4F91: (Color(0xFF22324A), Color(0xFFA9C3E8)),
    0xFF2B8A9E: (Color(0xFF1E3A3F), Color(0xFF9FD0D8)),
    0xFF2E8B57: (Color(0xFF1F3A28), Color(0xFFA8D5B2)),
    0xFFE0B03A: (Color(0xFF403820), Color(0xFFE4D28E)),
  };

  /// Заливка и цвет значка для действия, обозначенного цветом [base]
  /// (одна из констант AppColors). Неизвестный цвет — нейтральный серый.
  static (Color, Color) of(BuildContext context, Color base) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hit = (dark ? _dark : _light)[base.toARGB32()];
    if (hit != null) return hit;
    return dark
        ? (const Color(0xFF2C3138), const Color(0xFFC2C8D0))
        : (const Color(0xFFE4E7EB), const Color(0xFF4A5361));
  }
}

class AppTheme {
  AppTheme._();

  /// Шрифт интерфейса (pubspec.yaml → fonts): Roboto из пакета приложения на
  /// всех платформах — Android, iPhone, Mac и Windows выглядят одинаково.
  static const robotoFamily = 'AppRoboto';

  /// Medeo Sans (1.8.8, OFL 1.1, github.com/DNFDEVS/medeo-font) — на выбор в
  /// «Общих». Латиница и кириллица; остальные письменности — системным
  /// шрифтом, как и с Roboto.
  static const medeoFamily = 'MedeoSans';

  /// Шрифт интерфейса, выбранный в «Общих» (`uiFont`); main.dart ставит его
  /// до сборки тем.
  static String fontFamily = robotoFamily;

  static String familyFor(String uiFont) => uiFont == 'medeo' ? medeoFamily : robotoFamily;

  /// Переходы между экранами — без анимации (замечание 07.10.2026: переходы
  /// были рваными и не к месту). Прежние: Android — предиктивный «назад»,
  /// iOS/macOS — Cupertino, Windows/Linux — FadeForwards.
  /// iPhone и iPad (1.8.13) — системный сдвиг всегда: вместе с ним работает
  /// свайп «назад» от левого края — главный жест навигации iOS, без него
  /// вернуться можно было только кнопкой в углу.
  static const _pageTransitions = PageTransitionsTheme(builders: {
    TargetPlatform.android: NoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: NoPageTransitionsBuilder(),
    TargetPlatform.windows: NoPageTransitionsBuilder(),
    TargetPlatform.linux: NoPageTransitionsBuilder(),
  });

  /// Переходы при включённых «Анимациях интерфейса»: Android и десктоп —
  /// сдвиг с проявлением, как «затухание вперёд» Android 14, но короче
  /// ([SlideFadePageTransitionsBuilder]); iOS/macOS — системный сдвиг со
  /// свайпом «назад».
  static const _animatedTransitions = PageTransitionsTheme(builders: {
    TargetPlatform.android: SlideFadePageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: SlideFadePageTransitionsBuilder(),
    TargetPlatform.linux: SlideFadePageTransitionsBuilder(),
  });

  /// Цвет выделения текста: спокойный синий. Тот же цвет — у ручек выделения
  /// в письме (WebView берёт его из темы Android: colorAccent в styles.xml).
  static const selectionBlueLight = Color(0xFF2F6DB5);
  static const selectionBlueDark = Color(0xFF8AB1E6);

  static TextSelectionThemeData _selection(Brightness b) {
    final c = b == Brightness.dark ? selectionBlueDark : selectionBlueLight;
    return TextSelectionThemeData(
      cursorColor: c,
      selectionColor: c.withValues(alpha: 0.28),
      selectionHandleColor: c,
    );
  }

  /// Шапка одного цвета при прокрутке. scrolledUnderElevation: 0 убирает
  /// тень, но Material 3 (Flutter 3.22+) без явного цвета шапки при прокрутке
  /// берёт surfaceContainer — шапка серела под списком (замечание 11.10.2026).
  static ThemeData _fixedBar(ThemeData t) => t.appBarTheme.backgroundColor != null
      ? t
      : t.copyWith(appBarTheme: t.appBarTheme.copyWith(backgroundColor: t.colorScheme.surface));

  /// Тема с переходами между экранами или без них.
  static ThemeData withTransitions(ThemeData t, bool animated) =>
      t.copyWith(pageTransitionsTheme: animated ? _animatedTransitions : _pageTransitions);

  /// «Оформление» поверх собранной темы (1.9.x, просьба владельца
  /// 31.10.2026): плотность, оттенок ленты и анимация — расширением темы
  /// (AppearanceLook), скругление — формой карточек, полей, кнопок, меню,
  /// диалогов и шторок. Среднее скругление тему не трогает.
  static ThemeData _withAppearance(ThemeData t, Appearance a, {bool tint = true}) {
    final s = t.colorScheme;
    final dark = s.brightness == Brightness.dark;
    // Оттенок фона ленты — доля акцента поверх поверхности: заметно, но
    // текст строк остаётся выше AA (проверка — theme_presets_test).
    final alpha = switch (a.tint) {
      ListTint.none => 0.0,
      ListTint.subtle => dark ? 0.05 : 0.035,
      ListTint.soft => dark ? 0.09 : 0.07,
    };
    final look = AppearanceLook(
      density: a.density,
      listFill: tint && alpha > 0 ? Color.alphaBlend(s.primary.withValues(alpha: alpha), s.surface) : null,
      openAnimation: a.openAnimation,
    );
    final themed = t.copyWith(extensions: [
      for (final e in t.extensions.values)
        if (e is! AppearanceLook) e,
      look,
    ]);
    final k = a.radiusScale;
    return k == 1.0 ? themed : _scaledCorners(themed, k);
  }

  /// Формы темы со скруглением ×[k]. Диалоги и шторки (у Material 3 — 28)
  /// — не больше 32, чтобы верх шторки не становился «капсулой».
  static ThemeData _scaledCorners(ThemeData t, double k) {
    ShapeBorder? sh(ShapeBorder? s) => s is RoundedRectangleBorder ? s.copyWith(borderRadius: s.borderRadius * k) : s;
    OutlinedBorder? ob(OutlinedBorder? s) =>
        s is RoundedRectangleBorder ? s.copyWith(borderRadius: s.borderRadius * k) : s;
    InputBorder? ib(InputBorder? b) => b is OutlineInputBorder ? b.copyWith(borderRadius: b.borderRadius * k) : b;
    ButtonStyle? btn(ButtonStyle? st) {
      final shape = st?.shape?.resolve(const <WidgetState>{});
      return shape == null ? st : st!.copyWith(shape: WidgetStatePropertyAll(ob(shape)));
    }

    final big = (28 * k).clamp(0.0, 32.0);
    final menu = t.dropdownMenuTheme.menuStyle;
    return t.copyWith(
      cardTheme: t.cardTheme.copyWith(shape: sh(t.cardTheme.shape)),
      inputDecorationTheme: t.inputDecorationTheme.copyWith(border: ib(t.inputDecorationTheme.border)),
      chipTheme: t.chipTheme.copyWith(shape: ob(t.chipTheme.shape)),
      listTileTheme: t.listTileTheme.copyWith(shape: sh(t.listTileTheme.shape)),
      filledButtonTheme: FilledButtonThemeData(style: btn(t.filledButtonTheme.style)),
      textButtonTheme: TextButtonThemeData(style: btn(t.textButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: btn(t.outlinedButtonTheme.style)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: btn(t.elevatedButtonTheme.style)),
      floatingActionButtonTheme: t.floatingActionButtonTheme.copyWith(shape: sh(t.floatingActionButtonTheme.shape)),
      popupMenuTheme: t.popupMenuTheme.copyWith(shape: sh(t.popupMenuTheme.shape)),
      dropdownMenuTheme: menu == null
          ? t.dropdownMenuTheme
          : t.dropdownMenuTheme.copyWith(
              menuStyle: menu.copyWith(
                  shape: WidgetStatePropertyAll(ob(menu.shape?.resolve(const <WidgetState>{}))))),
      snackBarTheme: t.snackBarTheme.copyWith(shape: sh(t.snackBarTheme.shape)),
      dialogTheme: t.dialogTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(big))),
      bottomSheetTheme: t.bottomSheetTheme.copyWith(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(big)))),
    );
  }

  /// [dynamicScheme] — цвета от обоев (Android 12+). Высокий контраст важнее:
  /// с ним цвета обоев не применяются. [appearance] — «Оформление» (1.9.x):
  /// цветовая тема и акцент (не при обоях и высоком контрасте), скругление,
  /// плотность ленты, анимация открытия письма.
  static ThemeData lightTheme(double fontScale,
          {bool highContrast = false,
          bool dyslexiaFont = false,
          ColorScheme? dynamicScheme,
          Appearance appearance = Appearance.classic}) =>
      _withAppearance(
          _lightBase(fontScale,
              highContrast: highContrast,
              dyslexiaFont: dyslexiaFont,
              dynamicScheme: dynamicScheme,
              palette: ThemePalette.light(appearance)),
          appearance,
          tint: !highContrast);

  static ThemeData _lightBase(double fontScale,
      {bool highContrast = false, bool dyslexiaFont = false, ColorScheme? dynamicScheme, required ThemePalette palette}) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: highContrast
          ? const ColorScheme.highContrastLight(
              primary: Color(0xFF003087),
              secondary: Color(0xFFE31E24),
            )
          // Цвета «Классики» (прежние) и других тем — ThemePalette (1.9.x).
          : dynamicScheme ?? palette.scheme,
      // Фон чуть темнее (1.6.20): белые карточки отделяются тоном, без рамки.
      scaffoldBackgroundColor: highContrast ? null : palette.scaffold,
      fontFamily: (dyslexiaFont || fontScale > 1.5) ? 'OpenDyslexic' : fontFamily,
      // Один вид на всех платформах (1.6.20): плотность, размер областей
      // нажатия и «волна» при касании не зависят от ОС. По умолчанию Flutter
      // на компьютере делает элементы плотнее, а на Android рисует другую
      // волну (InkSparkle) — вид различался.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkRipple.splashFactory,
      // Стиль строки состояния без цвета: прозрачной её делает
      // enableEdgeToEdge(), а setStatusBarColor в Android 15 устарел.
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        // Шапка одного цвета всегда: при прокрутке Material 3 подкрашивал
        // её тенью-оттенком, и она была то белой, то серой (09.10.2026).
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      // Карточка — белая с тонкой границей: по умолчанию Material 3 красит её
      // в surfaceContainerLow, а это и есть фон экрана (#F6F8FB) — карточки
      // сливались с фоном (аудит цветов 10.10.2026).
      cardTheme: CardThemeData(
        elevation: 0,
        color: highContrast ? null : palette.card,
        // Без рамки (1.6.20): карточку отделяет тон фона, а не линия.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: highContrast ? const BorderSide(color: Colors.black) : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // #E9EDF2: заметно и на фоне экрана, и на белой карточке (было
        // #EFF2F6 — 1.06:1 к фону, поле «пропадало»).
        filled: true, fillColor: highContrast ? Colors.white : palette.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: highContrast ? const BorderSide(color: Colors.black, width: 2) : BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      dividerTheme: DividerThemeData(space: 1, thickness: highContrast ? 2 : 1, color: highContrast ? Colors.black : palette.divider),
      // ── Компоненты, которых не хватало: без них кнопки/переключатели/меню
      // берут дефолты Material 3 и, что важнее, НЕ учитывают высокий контраст.
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // В высококонтрастном режиме плотность не сжимаем: цели касания важнее.
        visualDensity: highContrast ? VisualDensity.standard : null,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44), // цель касания не меньше 44 px
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44),
        ),
      ),
      textSelectionTheme: highContrast ? null : _selection(Brightness.light),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44),
          side: highContrast ? const BorderSide(width: 2) : null,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(strokeWidth: 3),
      pageTransitionsTheme: _pageTransitions,
      // Нижняя навигация — цвета фона: сливается с полосой под жестовой
      // панелью (см. MailApp.builder), строгий «плоский» вид.
      navigationBarTheme: NavigationBarThemeData(
        // Светло-серо-голубая, как фон экрана (1.8.0, «воздушный» вид, как
        // Ogneliss Dialer 1.7.0; было #E8ECF1): от белой ленты панель
        // отделяет тонкая линия сверху (AppBottomBar), а не тёмный тон.
        backgroundColor: highContrast ? null : palette.navBar,
        elevation: 0,
        // 80 dp по умолчанию плюс системная панель снизу давали заметную
        // пустоту под подписями. 64 dp — пилюля 56×32 и подпись.
        height: 64,
      ),
      tabBarTheme: TabBarThemeData(
        dividerHeight: 0,
        labelColor: highContrast ? null : palette.tab,
        indicatorColor: highContrast ? null : palette.tab,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // «Воздушный» вид (1.8.0); высокий контраст — с полосами и линиями.
      extensions: [OgnelissLook(outlined: highContrast, cardBorder: highContrast)],
    );
    return _softIcons(
        _cardDialogs(_fixedBar((dynamicScheme != null && !highContrast) ? _withDynamic(base, dynamicScheme) : base)),
        highContrast: highContrast);
  }

  /// Значки тоньше (1.6.20, «мягкий» стиль): Material Symbols с толщиной 300
  /// вместо 400 — везде, включая шапку экранов (её значки берут свою тему,
  /// поэтому цвета заданы явно, как у Material 3: слева — основной цвет
  /// текста, справа — вторичный). В высоком контрасте — как было.
  static ThemeData _softIcons(ThemeData t, {required bool highContrast}) {
    if (highContrast) return t;
    final s = t.colorScheme;
    return t.copyWith(
      iconTheme: t.iconTheme.copyWith(weight: 300),
      appBarTheme: t.appBarTheme.copyWith(
        iconTheme: IconThemeData(color: s.onSurface, size: 24, weight: 300),
        actionsIconTheme: IconThemeData(color: s.onSurfaceVariant, size: 24, weight: 300),
      ),
    );
  }

  /// Фон, поля ввода, разделители, выделение текста и панели — из цветов
  /// обоев, а не фирменных оттенков (иначе синеватый фон под розовой схемой).
  /// Диалоги — фоном карточки (1.8.6): по умолчанию Material 3 красит их в
  /// surfaceContainerHigh, и серый диалог рядом с белыми карточками и меню
  /// «⋮» (AppMenuButton) выглядел чужим. Шторки не трогаем: в них белые
  /// группы настроек отделяются от фона именно тоном шторки.
  static ThemeData _cardDialogs(ThemeData t) {
    final s = t.colorScheme;
    final fill = s.brightness == Brightness.dark ? s.surfaceContainer : s.surfaceContainerLowest;
    return t.copyWith(
      dialogTheme: t.dialogTheme.copyWith(backgroundColor: fill, surfaceTintColor: Colors.transparent),
    );
  }

  static ThemeData _withDynamic(ThemeData t, ColorScheme s) => t.copyWith(
        scaffoldBackgroundColor: s.surfaceContainerLow,
        inputDecorationTheme: t.inputDecorationTheme.copyWith(fillColor: s.surfaceContainerHigh),
        // Без рамки (1.8.0, «воздушный» вид), как в светлой и тёмной.
        cardTheme: t.cardTheme.copyWith(
          color: s.brightness == Brightness.dark ? s.surfaceContainer : s.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        dividerTheme: t.dividerTheme.copyWith(color: s.outlineVariant),
        // Выделение текста — всегда спокойный синий, а не цвет обоев (с
        // зелёными обоями ручки выделения были ярко-зелёными, 08.10.2026).
        textSelectionTheme: _selection(s.brightness),
        navigationBarTheme: t.navigationBarTheme.copyWith(backgroundColor: s.surfaceContainerHigh),
        tabBarTheme: t.tabBarTheme.copyWith(labelColor: s.primary, indicatorColor: s.primary),
      );

  static ThemeData darkTheme(double fontScale,
          {bool highContrast = false,
          bool dyslexiaFont = false,
          ColorScheme? dynamicScheme,
          Appearance appearance = Appearance.classic}) =>
      _withAppearance(
          _darkBase(fontScale,
              highContrast: highContrast,
              dyslexiaFont: dyslexiaFont,
              dynamicScheme: dynamicScheme,
              palette: ThemePalette.dark(appearance)),
          appearance,
          tint: !highContrast);

  static ThemeData _darkBase(double fontScale,
      {bool highContrast = false, bool dyslexiaFont = false, ColorScheme? dynamicScheme, required ThemePalette palette}) {
    final t = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: highContrast
          ? const ColorScheme.highContrastDark(
              primary: Color(0xFF6BA3FF),
              secondary: Color(0xFFFF6B70),
            )
          // Цвета «Классики» (прежние) и других тем — ThemePalette (1.9.x).
          : dynamicScheme ?? palette.scheme,
      scaffoldBackgroundColor: palette.scaffold,
      fontFamily: (dyslexiaFont || fontScale > 1.5) ? 'OpenDyslexic' : fontFamily,
      // Один вид на всех платформах (1.6.20): плотность, размер областей
      // нажатия и «волна» при касании не зависят от ОС. По умолчанию Flutter
      // на компьютере делает элементы плотнее, а на Android рисует другую
      // волну (InkSparkle) — вид различался.
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        // Шапка одного цвета всегда: при прокрутке Material 3 подкрашивал
        // её тенью-оттенком, и она была то белой, то серой (09.10.2026).
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      // Карточка на ступень светлее фона и с тонкой границей (по умолчанию
      // surfaceContainerLow — 1.07:1 к фону).
      cardTheme: CardThemeData(
        elevation: 0,
        color: highContrast ? null : palette.card,
        // Без рамки (1.6.20): карточка на ступень светлее фона и так видна.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: highContrast ? const BorderSide(color: Colors.white) : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: palette.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: highContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 14),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      dividerTheme: DividerThemeData(space: 1, thickness: highContrast ? 2 : 1, color: highContrast ? Colors.white : palette.divider),
      // ── Компоненты, которых не хватало: без них кнопки/переключатели/меню
      // берут дефолты Material 3 и, что важнее, НЕ учитывают высокий контраст.
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // В высококонтрастном режиме плотность не сжимаем: цели касания важнее.
        visualDensity: highContrast ? VisualDensity.standard : null,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44), // цель касания не меньше 44 px
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44),
          side: highContrast ? const BorderSide(width: 2) : null,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(64, 44),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(strokeWidth: 3),
      pageTransitionsTheme: _pageTransitions,
      textSelectionTheme: highContrast ? null : _selection(Brightness.dark),
      navigationBarTheme: NavigationBarThemeData(
        // Чуть светлее фона экрана (#12161B) — панель отделена от ленты.
        backgroundColor: highContrast ? null : palette.navBar,
        elevation: 0,
        // 80 dp по умолчанию плюс системная панель снизу давали заметную
        // пустоту под подписями. 64 dp — пилюля 56×32 и подпись.
        height: 64,
      ),
      tabBarTheme: const TabBarThemeData(dividerHeight: 0),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // «Воздушный» вид (1.8.0); высокий контраст — с полосами и линиями.
      extensions: [OgnelissLook(outlined: highContrast, cardBorder: highContrast)],
    );
    return _softIcons(
        _cardDialogs(_fixedBar((dynamicScheme != null && !highContrast) ? _withDynamic(t, dynamicScheme) : t)),
        highContrast: highContrast);
  }

  /// AMOLED-тема: чистый чёрный фон (экономия батареи на OLED, максимальный
  /// контраст). С 1.9.x — и тёмный вариант цветовой темы «Полночь».
  static ThemeData amoledTheme(double fontScale,
          {bool highContrast = false,
          bool dyslexiaFont = false,
          ColorScheme? dynamicScheme,
          Appearance appearance = Appearance.classic}) =>
      _withAppearance(
          _amoledBase(fontScale,
              highContrast: highContrast,
              dyslexiaFont: dyslexiaFont,
              dynamicScheme: dynamicScheme,
              palette: ThemePalette.dark(appearance)),
          appearance,
          tint: !highContrast);

  static ThemeData _amoledBase(double fontScale,
      {bool highContrast = false, bool dyslexiaFont = false, ColorScheme? dynamicScheme, required ThemePalette palette}) {
    final dark = _darkBase(fontScale,
        highContrast: highContrast, dyslexiaFont: dyslexiaFont, dynamicScheme: dynamicScheme, palette: palette);
    final scheme = dark.colorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF101010),
      surfaceContainerHigh: const Color(0xFF161616),
      surfaceContainerHighest: const Color(0xFF1C1C1C),
      // Границы на чёрном: прежние #353E4A/#222222 почти не видны.
      outlineVariant: highContrast ? null : const Color(0xFF282C32),
    );
    return dark.copyWith(
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      colorScheme: scheme,
      appBarTheme: dark.appBarTheme.copyWith(backgroundColor: Colors.black),
      // Карточка на чёрном — с границей: заливка #101010 сама по себе
      // почти не отличается от фона (1.1:1).
      cardTheme: dark.cardTheme.copyWith(
        color: const Color(0xFF101010),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: highContrast ? Colors.white : const Color(0xFF24282E)),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF0A0A0A)),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.black),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.black, height: 64),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: Colors.black),
      drawerTheme: const DrawerThemeData(backgroundColor: Colors.black),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: highContrast ? 2 : 1,
        color: highContrast ? Colors.white : const Color(0xFF222222),
      ),
      // На чёрном карточка без рамки не видна — рамка остаётся (1.8.0).
      extensions: [OgnelissLook(outlined: highContrast, cardBorder: true)],
    );
  }

  /// Фон экрана темы «Чтение» (по нему AppColors узнаёт тему).
  static const readingScaffold = Color(0xFFF4EFE6);

  /// «Чтение»: светлая тема на тёплой «бумаге» во всём приложении — меньше
  /// синего света и мягче контраст, чем белый экран. Цвет действий —
  /// приглушённый синий. Контраст: текст 13:1, вторичный текст 6.3:1,
  /// кнопка 6.7:1 (замеры 10.10.2026). Цвета обоев не применяются.
  /// Цветовая тема и акцент к «Чтению» не применяются (у него своя
  /// палитра); скругление, плотность и анимация из [appearance] — да.
  static ThemeData readingTheme(double fontScale, {bool dyslexiaFont = false, Appearance appearance = Appearance.classic}) =>
      _withAppearance(_readingBase(fontScale, dyslexiaFont: dyslexiaFont), appearance);

  static ThemeData _readingBase(double fontScale, {bool dyslexiaFont = false}) {
    final light = _lightBase(fontScale, dyslexiaFont: dyslexiaFont, palette: ThemePalette.light(Appearance.classic));
    final scheme = light.colorScheme.copyWith(
      primary: const Color(0xFF3F5D84),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE2E1D8),
      onPrimaryContainer: const Color(0xFF1E2C40),
      secondary: const Color(0xFF6A5E4C),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE6DBC6),
      onSecondaryContainer: const Color(0xFF2E2213),
      tertiary: const Color(0xFF8F5419),
      surface: const Color(0xFFFBF8F2),
      onSurface: const Color(0xFF2B2620),
      onSurfaceVariant: const Color(0xFF5E564A),
      surfaceContainerLowest: const Color(0xFFFBF8F2),
      surfaceContainerLow: readingScaffold,
      surfaceContainer: const Color(0xFFEEE8DD),
      surfaceContainerHigh: const Color(0xFFE8E1D5),
      surfaceContainerHighest: const Color(0xFFE1D9CB),
      outline: const Color(0xFF8C8273),
      outlineVariant: const Color(0xFFDED5C6),
    );
    return light.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: readingScaffold,
      canvasColor: const Color(0xFFFBF8F2),
      appBarTheme: light.appBarTheme.copyWith(backgroundColor: readingScaffold),
      cardTheme: light.cardTheme.copyWith(
        color: const Color(0xFFFBF8F2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2D9CB)),
        ),
      ),
      inputDecorationTheme: light.inputDecorationTheme.copyWith(fillColor: const Color(0xFFE9E2D5)),
      dividerTheme: light.dividerTheme.copyWith(color: const Color(0xFFEAE2D5)),
      navigationBarTheme: light.navigationBarTheme.copyWith(backgroundColor: const Color(0xFFE8E0D2)),
      tabBarTheme: light.tabBarTheme.copyWith(
          labelColor: const Color(0xFF3F5D84), indicatorColor: const Color(0xFF3F5D84)),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFFF7F3EC)),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFFF7F3EC)),
      drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFFF7F3EC)),
      // «Бумага»: карточка почти как фон — с рамкой (1.8.0).
      extensions: const [OgnelissLook(cardBorder: true)],
    );
  }

  /// Цвет промышленного тега
  static Color getTagColor(String tag) {
    switch (tag) {
      case 'Производство': return AppColors.tagProduction;
      case 'ТОиР': return AppColors.tagMaintenance;
      case 'Финансы': return AppColors.tagFinance;
      case 'Кадры': return AppColors.tagHR;
      case 'HSE': return AppColors.tagHSE;
      case 'Логистика': return AppColors.tagLogistics;
      case 'Руководство': return AppColors.tagManagement;
      case 'IT': return AppColors.tagIT;
      case 'Поручения': return AppColors.tagAssignment;
      case 'Закупки': return AppColors.tagPurchasing;
      case 'Юридический': return AppColors.tagLegal;
      case 'Общая рассылка': return AppColors.tagGeneral;
      default: return AppColors.tagGeneral;
    }
  }
}

/// Переход между экранами (1.5.6): новый экран выезжает справа на четверть
/// ширины и проявляется, прежний уходит влево и гаснет — рисунок
/// «затухания вперёд» Android 14, но 300 мс вместо 450 и с плавным
/// торможением вместо «выразительной» кривой (у неё экран долго «доезжает»).
/// Тело письма показывается после конца перехода — встроенное окно
/// браузера нельзя создавать на ходу (рывки), — поэтому длинный переход
/// прямо задерживал письмо (замечание 11.10.2026).
class SlideFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlideFadePageTransitionsBuilder();

  // Без @override — как у NoPageTransitionsBuilder ниже.
  // ignore: annotate_overrides
  Duration get transitionDuration => const Duration(milliseconds: 300);
  // ignore: annotate_overrides
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  static const Curve _curve = Curves.easeOutCubic;

  // Новый экран: справа к месту и обратно.
  static final Animatable<Offset> _inFromRight =
      Tween<Offset>(begin: const Offset(0.25, 0), end: Offset.zero).chain(CurveTween(curve: _curve));
  static final Animatable<Offset> _outToRight =
      Tween<Offset>(begin: Offset.zero, end: const Offset(0.25, 0)).chain(CurveTween(curve: _curve));
  // Прежний экран: влево, пока открыт новый, и обратно.
  static final Animatable<Offset> _outToLeft =
      Tween<Offset>(begin: Offset.zero, end: const Offset(-0.25, 0)).chain(CurveTween(curve: _curve));
  static final Animatable<Offset> _inFromLeft =
      Tween<Offset>(begin: const Offset(-0.25, 0), end: Offset.zero).chain(CurveTween(curve: _curve));
  // Появляющийся экран проявляется за 70 % перехода, уходящий гаснет за 30 %.
  static final Animatable<double> _fadeIn = CurveTween(curve: const Interval(0.0, 0.7, curve: Curves.easeOut));
  static final Animatable<double> _fadeOut =
      Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: const Interval(0.0, 0.3)));

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Этот экран, пока поверх него открывается другой (и закрывается).
    final behind = DualTransitionBuilder(
      animation: ReverseAnimation(secondaryAnimation),
      forwardBuilder: (context, a, child) => FadeTransition(
        opacity: _fadeIn.animate(a),
        child: SlideTransition(position: _inFromLeft.animate(a), child: child),
      ),
      reverseBuilder: (context, a, child) => FadeTransition(
        opacity: _fadeOut.animate(a),
        child: SlideTransition(position: _outToLeft.animate(a), child: child),
      ),
      child: child,
    );
    // Фон под гаснущим экраном — цвет страницы, а не чёрный (дерево виджетов
    // одно и то же во всех состояниях — состояние экрана не теряется).
    final opaque = ModalRoute.opaqueOf(context) ?? true;
    final page = ColoredBox(
      color: opaque && secondaryAnimation.isAnimating ? Theme.of(context).colorScheme.surface : Colors.transparent,
      child: behind,
    );
    // Сам экран: открытие и закрытие.
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder: (context, a, child) => FadeTransition(
        opacity: _fadeIn.animate(a),
        child: SlideTransition(position: _inFromRight.animate(a), child: child),
      ),
      reverseBuilder: (context, a, child) => IgnorePointer(
        ignoring: a.status == AnimationStatus.forward,
        child: FadeTransition(
          opacity: _fadeOut.animate(a),
          child: SlideTransition(position: _outToRight.animate(a), child: child),
        ),
      ),
      child: page,
    );
  }
}

/// Переход между экранами без анимации: новый экран появляется сразу.
class NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoPageTransitionsBuilder();

  // Длительность перехода — ноль (иначе Hero и затемнение шли бы 300 мс).
  // ignore: annotate_overrides
  Duration get transitionDuration => Duration.zero;
  // ignore: annotate_overrides
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}
