// lib/core/utils/date_links.dart
// Даты в тексте письма — нажимаемые, как у iOS (1.9.x, просьба владельца
// 31.10.2026): «завтра в 15», «3 ноября в 10:00», «с 15 до 16» становятся
// ссылками со своей схемой `ogdate:` — в окне браузера письма (JavaScript
// там выключен, остаются только ссылки), в простых письмах виджетами и в
// письмах без HTML. Нажатие ведёт туда же, куда и у обычных ссылок письма
// (onLink), а экран письма открывает по `ogdate:` карточку «Создать встречу /
// Напоминание / Скопировать / Показать в календаре».
//
// Даты ищет общий разбор (DatePhrase.find) — от даты письма: «завтра» —
// день после отправки. Внутри ссылок письма даты не ищутся.

import 'dart:ui' show PlatformDispatcher;

import 'date_phrase.dart';
import 'linkify.dart';

/// Где искать даты: опорный момент (дата письма по часам устройства) и
/// порядок чисел через косую черту. Передаётся в изолят сборки письма.
class DateContext {
  final DateTime ref;

  /// «10/31» — 31 октября (США и ещё несколько стран); иначе «31/10».
  final bool monthFirst;

  const DateContext(this.ref, {this.monthFirst = false});

  /// Для письма с датой [sent] — по стране устройства.
  factory DateContext.forMail(DateTime sent) => DateContext(sent.toLocal(), monthFirst: deviceMonthFirst);

  /// Часть ключа кэша подготовленного письма.
  String get key => '${ref.millisecondsSinceEpoch}${monthFirst ? 'm' : 'd'}';

  static const _monthFirstCountries = {'US', 'PH', 'FM', 'MH', 'PW', 'GU', 'PR', 'AS', 'VI', 'UM'};

  static bool get deviceMonthFirst {
    try {
      return _monthFirstCountries.contains(PlatformDispatcher.instance.locale.countryCode?.toUpperCase());
    } catch (_) {
      return false;
    }
  }
}

/// Дата из ссылки `ogdate:`.
class DateLinkTarget {
  final DateTime from;
  final DateTime? to;
  final bool allDay;
  const DateLinkTarget(this.from, {this.to, this.allDay = false});
}

class DateLinks {
  DateLinks._();

  static const scheme = 'ogdate';

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';
  static String _at(DateTime d) => '${_day(d)}T${_two(d.hour)}${_two(d.minute)}';

  /// `ogdate:20261103` (весь день), `ogdate:20261103T1400` или
  /// `ogdate:20261103T1400-20261103T1500` — только буквы и цифры: адрес
  /// приходит из окна браузера без искажений.
  static String href(DateMention m) {
    if (m.allDay) return '$scheme:${_day(m.from)}';
    final to = m.to;
    return to == null ? '$scheme:${_at(m.from)}' : '$scheme:${_at(m.from)}-${_at(to)}';
  }

  static bool isDateLink(String url) => url.trim().toLowerCase().startsWith('$scheme:');

  static final _re = RegExp(r'^ogdate:(\d{8})(?:t(\d{4}))?(?:-(\d{8})t(\d{4}))?$', caseSensitive: false);

  static DateLinkTarget? parse(String url) {
    final m = _re.firstMatch(url.trim());
    if (m == null) return null;
    DateTime? at(String? day, String? time) {
      if (day == null) return null;
      final y = int.parse(day.substring(0, 4)), mo = int.parse(day.substring(4, 6)), d = int.parse(day.substring(6));
      final h = time == null ? 0 : int.parse(time.substring(0, 2));
      final mi = time == null ? 0 : int.parse(time.substring(2));
      final dt = DateTime(y, mo, d, h, mi);
      return dt.month == mo && dt.day == d ? dt : null;
    }

    final from = at(m.group(1), m.group(2));
    if (from == null) return null;
    return DateLinkTarget(from, to: at(m.group(3), m.group(4)), allDay: m.group(2) == null);
  }

  /// Ссылки, адреса почты ([Linkify.find]) и даты текста — по порядку; даты
  /// внутри ссылок не ищутся. [dates] null — только ссылки.
  static List<LinkMatch> find(String text, DateContext? dates) {
    final links = Linkify.find(text);
    if (dates == null || !DatePhrase.mayContain(text)) return links;
    final found = DatePhrase.find(text, ref: dates.ref, monthFirst: dates.monthFirst);
    if (found.isEmpty) return links;
    final out = <LinkMatch>[...links];
    for (final m in found) {
      if (links.any((l) => m.start < l.end && m.end > l.start)) continue;
      out.add(LinkMatch(m.start, m.end, href(m)));
    }
    if (links.isNotEmpty) out.sort((a, b) => a.start - b.start);
    return out;
  }
}
