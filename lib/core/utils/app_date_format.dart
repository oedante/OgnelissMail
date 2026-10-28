// lib/core/utils/app_date_format.dart
// Локале-зависимое форматирование дат, времени и чисел для ИНТЕРФЕЙСА.
//
// Зачем: шаблоны вроде DateFormat('dd.MM.yyyy') и DateFormat('HH:mm') — это
// РУССКИЙ формат, зашитый в код. Для en дата должна быть 7/17/2026, а время —
// 12-часовым (2:30 PM). Здесь всё это выводится из локали приложения.
//
// ВАЖНО: для документов на экспорт (отчёты, .eml) локаль интерфейса не нужна —
// там формат определяется языком документа. Эта утилита только для UI.

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

class AppDateFormat {
  AppDateFormat._();

  /// Код локали для intl из локализации приложения.
  static String localeOf(BuildContext context) =>
      AppLocalizations.of(context).localeCode;

  // DateFormat дорого разбирает шаблон, а тайлы списка перестраиваются часто —
  // поэтому экземпляры кэшируем по паре «вид формата + локаль». Локалей две,
  // видов немного: кэш крошечный и живёт всё время работы приложения.
  static final Map<String, DateFormat> _cache = {};
  static DateFormat _fmt(String kind, String locale, DateFormat Function() build) =>
      _cache.putIfAbsent('$kind.$locale', build);

  // ─────────────────────────── Даты ───────────────────────────

  /// Короткая дата: «17.07.2026» (ru) / «7/17/2026» (en).
  static String date(BuildContext c, DateTime d) {
    final l = localeOf(c);
    return _fmt('yMd', l, () => DateFormat.yMd(l)).format(d.toLocal());
  }

  /// День и месяц: «17 июл.» (ru) / «Jul 17» (en).
  static String dayMonth(BuildContext c, DateTime d) {
    final l = localeOf(c);
    return _fmt('MMMd', l, () => DateFormat.MMMd(l)).format(d.toLocal());
  }

  /// Месяц и год: «июль 2026» (ru) / «July 2026» (en).
  static String monthYear(BuildContext c, DateTime d) {
    final l = localeOf(c);
    return _fmt('yMMMM', l, () => DateFormat.yMMMM(l)).format(d.toLocal());
  }

  /// День недели полностью: «пятница» / «Friday».
  static String weekday(BuildContext c, DateTime d) {
    final l = localeOf(c);
    return _fmt('EEEE', l, () => DateFormat.EEEE(l)).format(d.toLocal());
  }

  // ─────────────────────────── Время ──────────────────────────

  /// Время в формате локали: «14:30» (ru) / «2:30 PM» (en).
  static String time(BuildContext c, DateTime d) {
    final l = localeOf(c);
    return _fmt('jm', l, () => DateFormat.jm(l)).format(d.toLocal());
  }

  /// Дата и время: «17.07.2026, 14:30» / «7/17/2026, 2:30 PM».
  static String dateTime(BuildContext c, DateTime d) =>
      '${date(c, d)}, ${time(c, d)}';

  /// День, месяц и время: «17 июл., 14:30» / «Jul 17, 2:30 PM».
  static String dayMonthTime(BuildContext c, DateTime d) =>
      '${dayMonth(c, d)}, ${time(c, d)}';

  // ────────────────────── Умное время списка ──────────────────

  /// Как в почтовых клиентах: сегодня — время, в этом году — день и месяц,
  /// иначе — дата целиком.
  static String listStamp(BuildContext c, DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return time(c, local);
    if (local.year == now.year) return dayMonth(c, local);
    return date(c, local);
  }

  // ───────────────────── Относительное время ──────────────────

  /// «только что» / «5 мин назад» / «2 ч назад» / «вчера» / дата.
  /// Для en — «just now» / «5 min ago» / «2 h ago» / «yesterday».
  static String relative(BuildContext c, DateTime d) {
    final l10n = AppLocalizations.of(c);
    final local = d.toLocal();
    final diff = DateTime.now().difference(local);

    if (diff.isNegative) return dateTime(c, local); // будущее — показываем как есть
    if (diff.inSeconds < 60) return l10n.tr('justNow');
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return l10n.plural('minutesAgoN', m);
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return l10n.plural('hoursAgoN', h);
    }
    if (diff.inDays == 1) return l10n.tr('yesterday');
    if (diff.inDays < 7) {
      final dd = diff.inDays;
      return l10n.plural('daysAgoN', dd);
    }
    return date(c, local);
  }

  // ───────────────────────── Числа ────────────────────────────

  static final Map<String, NumberFormat> _numCache = {};

  /// Разделители по локали: «1 234,5» (ru) / «1,234.5» (en).
  static String number(BuildContext c, num n) {
    final l = localeOf(c);
    return _numCache
        .putIfAbsent('dec.$l', () => NumberFormat.decimalPattern(l))
        .format(n);
  }

  /// Проценты: «12,5 %» / «12.5%».
  static String percent(BuildContext c, double fraction, {int decimals = 1}) =>
      NumberFormat.decimalPercentPattern(
        locale: localeOf(c),
        decimalDigits: decimals,
      ).format(fraction);

  /// Размер в байтах с единицами по локали: «1,5 МБ» / «1.5 MB».
  static String bytes(BuildContext c, int b) {
    final l10n = AppLocalizations.of(c);
    final units = [
      l10n.tr('unitB'), l10n.tr('unitKB'), l10n.tr('unitMB'),
      l10n.tr('unitGB'), l10n.tr('unitTB'),
    ];
    var value = b.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    final l = localeOf(c);
    final pattern = i == 0 ? '#,##0' : '#,##0.#';
    final fmt = _numCache.putIfAbsent(
        'bytes$i.$l', () => NumberFormat(pattern, l));
    return '${fmt.format(value)} ${units[i]}';
  }
}
