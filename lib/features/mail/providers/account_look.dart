// lib/features/mail/providers/account_look.dart
// Оформление ящиков: стиль окраски шапки списка писем и фото, выбранные
// вручную. Хранится в SharedPreferences — это вид, а не данные ящика.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../data/providers/shared_prefs_provider.dart';

/// Оформление панели: фон, цвет текста и значков, граница, градиент.
typedef BarLook = ({Color? background, Color? foreground, ShapeBorder? shape, Gradient? gradient});

/// Как окрашивать верхнюю панель почты (заголовок ленты) цветом ящика.
/// В 1.6.2 окрашивалась и нижняя; с 1.6.4 она всегда по теме (решение
/// владельца 13.10.2026), [panelLook] не используется.
enum AccountHeaderStyle {
  /// Обычная шапка.
  none,
  /// Лёгкий оттенок цвета ящика (как было раньше, чуть заметнее).
  tint,
  /// Обычная шапка с полосой цвета ящика снизу.
  stripe,
  /// Цвет слева, плавно уходящий в обычный фон к кнопкам справа.
  gradient,
  /// Шапка целиком цвета ящика; текст и кнопки — белые или чёрные по
  /// яркости цвета, чтобы читались на любом.
  full,
}

const _kHeaderStyle = 'account_header_style';
const _kManualPhotos = 'account_photo_manual';

class HeaderStyleNotifier extends Notifier<AccountHeaderStyle> {
  @override
  AccountHeaderStyle build() {
    final v = ref.read(sharedPrefsProvider).getString(_kHeaderStyle);
    return AccountHeaderStyle.values.firstWhere((s) => s.name == v,
        orElse: () => AccountHeaderStyle.tint);
  }

  Future<void> set(AccountHeaderStyle s) async {
    state = s;
    await ref.read(sharedPrefsProvider).setString(_kHeaderStyle, s.name);
  }
}

final accountHeaderStyleProvider =
    NotifierProvider<HeaderStyleNotifier, AccountHeaderStyle>(HeaderStyleNotifier.new);

/// Цвет текста и значков поверх [bg]: белый на тёмном, почти чёрный на светлом.
Color onAccountColor(Color bg) =>
    ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : const Color(0xFF1B1C1F);

/// Оформление шапки для ящика цвета [color] при стиле [style].
///
/// 1.5.11 (замечание 12.10.2026: «часть вариантов ни на что не влияют»):
/// «Оттенок» (12 %) почти не отличался от фона ленты и плашек дат, а
/// «Градиент» (28 % у края) — от «Без цвета»; на тёмной теме оба были не
/// видны. Теперь у каждого стиля заметная разница: оттенок — 20 % (на
/// тёмной теме 32 %), градиент — от 55 % (тёмная — 65 %) через всю шапку,
/// полоса — 3 точки.
BarLook headerLook(AccountHeaderStyle style, Color color, ThemeData theme) {
  final surface = theme.colorScheme.surface;
  final dark = theme.brightness == Brightness.dark;
  switch (style) {
    case AccountHeaderStyle.none:
      return (background: null, foreground: null, shape: null, gradient: null);
    case AccountHeaderStyle.tint:
      return (
        background: Color.alphaBlend(color.withValues(alpha: dark ? 0.32 : 0.20), surface),
        foreground: null, shape: null, gradient: null,
      );
    case AccountHeaderStyle.stripe:
      return (
        background: null, foreground: null,
        shape: Border(bottom: BorderSide(color: color, width: 3)),
        gradient: null,
      );
    case AccountHeaderStyle.gradient:
      // Тёмный текст темы читается и на самом цветном краю: цвет ящика
      // разбавлен фоном.
      return (
        background: surface, foreground: null, shape: null,
        gradient: LinearGradient(colors: [
          Color.alphaBlend(color.withValues(alpha: dark ? 0.65 : 0.55), surface),
          Color.alphaBlend(color.withValues(alpha: 0.06), surface),
        ]),
      );
    case AccountHeaderStyle.full:
      // Заливка — чуть разбавленным цветом ящика: спокойнее, чем чистый цвет.
      final bg = Color.alphaBlend(color.withValues(alpha: 0.85), surface);
      return (background: bg, foreground: onAccountColor(bg), shape: null, gradient: null);
  }
}

/// То же для нижней панели почты (1.6.2). Полоса — сверху, на границе с
/// лентой; градиент — от вкладки «Почта» с аватаром ящика слева.
BarLook panelLook(AccountHeaderStyle style, Color color, ThemeData theme) {
  if (style == AccountHeaderStyle.stripe) {
    return (background: null, foreground: null,
        shape: Border(top: BorderSide(color: color, width: 3)), gradient: null);
  }
  return headerLook(style, color, theme);
}

/// Ящики, у которых фото выбрано вручную: синхронизация не заменяет его
/// фото из адресной книги организации.
class ManualPhotosNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      (ref.read(sharedPrefsProvider).getStringList(_kManualPhotos) ?? const []).toSet();

  Future<void> mark(String accountId, bool manual) async {
    final next = {...state};
    manual ? next.add(accountId) : next.remove(accountId);
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(_kManualPhotos, next.toList());
  }
}

final manualPhotosProvider =
    NotifierProvider<ManualPhotosNotifier, Set<String>>(ManualPhotosNotifier.new);

/// Фото → квадрат 256×256 по центру, JPEG → data URI. Вне UI-изолята:
/// декодирование снимка с камеры занимает сотни миллисекунд.
Future<String?> photoToDataUri(Uint8List bytes) => compute(_photoToDataUri, bytes);

String? _photoToDataUri(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  final oriented = img.bakeOrientation(src);
  final side = oriented.width < oriented.height ? oriented.width : oriented.height;
  final square = img.copyCrop(oriented,
      x: (oriented.width - side) ~/ 2, y: (oriented.height - side) ~/ 2, width: side, height: side);
  final small = img.copyResize(square, width: 256, height: 256, interpolation: img.Interpolation.average);
  return 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(small, quality: 85))}';
}
