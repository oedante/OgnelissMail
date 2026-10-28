// lib/features/mail/widgets/booking_card.dart
// Карточка бронирования в письме (билет, отель, мероприятие, столик, авто):
// что, когда, где, номер брони и кнопка «Добавить в календарь».
//
// Данные — только из структурированной разметки schema.org в письме
// (booking_parser.dart). Защита от спама: карточка показывается лишь при
// пройденной проверке отправителя (DKIM/DMARC pass) и без признаков
// подделки; в календарь ничего не попадает без нажатия пользователя.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/booking_parser.dart';
import '../../../services/mail/unsubscribe_service.dart' show senderAuthenticated;
import '../../../services/security/sender_safety_service.dart';

class BookingCards extends ConsumerStatefulWidget {
  final AccountModel account;
  final EmailModel email;

  /// Исходный HTML письма (до очистки: в очищенном разметки уже нет).
  final String? rawHtml;

  const BookingCards({super.key, required this.account, required this.email, required this.rawHtml});

  @override
  ConsumerState<BookingCards> createState() => _BookingCardsState();
}

class _BookingCardsState extends ConsumerState<BookingCards> {
  static const _kAdded = 'booking_added_v1';
  List<Booking> _items = const [];
  String? _parsedFrom;
  bool _danger = false;

  @override
  void initState() {
    super.initState();
    _checkSafety();
  }

  Future<void> _checkSafety() async {
    try {
      final report = await ref.read(senderSafetyServiceProvider).analyze(widget.account, widget.email);
      if (mounted && report.level == SafetyLevel.danger) setState(() => _danger = true);
    } catch (_) {}
  }

  String _key(Booking b) => '${widget.email.accountId}|${widget.email.id}|${b.kind.name}|${b.start?.millisecondsSinceEpoch}';

  bool _isAdded(Booking b) => (ref.read(sharedPrefsProvider).getStringList(_kAdded) ?? const []).contains(_key(b));

  Future<void> _markAdded(Booking b) async {
    final prefs = ref.read(sharedPrefsProvider);
    final list = {...(prefs.getStringList(_kAdded) ?? const <String>[]), _key(b)}.toList();
    await prefs.setStringList(_kAdded, list.length > 300 ? list.sublist(list.length - 300) : list);
  }

  static IconData iconOf(BookingKind k) => switch (k) {
        BookingKind.flight => AppIcons.flight,
        BookingKind.train => AppIcons.train,
        BookingKind.bus => AppIcons.directions_bus,
        BookingKind.hotel => AppIcons.hotel,
        BookingKind.event => AppIcons.local_activity,
        BookingKind.restaurant => AppIcons.restaurant,
        BookingKind.car => AppIcons.car_rental,
      };

  static String kindKey(BookingKind k) => switch (k) {
        BookingKind.flight => 'bookingFlight',
        BookingKind.train => 'bookingTrain',
        BookingKind.bus => 'bookingBus',
        BookingKind.hotel => 'bookingHotel',
        BookingKind.event => 'bookingEvent',
        BookingKind.restaurant => 'bookingRestaurant',
        BookingKind.car => 'bookingCar',
      };

  String _when(Booking b, String loc) {
    final s = b.start;
    if (s == null) return '';
    final day = DateFormat('EEE, d MMM', loc);
    final t = DateFormat.Hm(loc);
    final e = b.end;
    if (e == null) return '${day.format(s)}, ${t.format(s)}';
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    return sameDay
        ? '${day.format(s)}, ${t.format(s)}–${t.format(e)}'
        : '${day.format(s)}, ${t.format(s)} — ${day.format(e)}, ${t.format(e)}';
  }

  Future<void> _addToCalendar(Booking b, AppLocalizations l10n) async {
    final kind = l10n.tr(kindKey(b.kind));
    final desc = [
      if (b.reservationNumber != null) '${l10n.tr('bookingNumber')}: ${b.reservationNumber}',
      if (b.details != null) b.details!,
      '${l10n.tr('createdFromEmail')}: ${widget.email.subject}',
    ].join('\n');
    // Письмо не передаём: отправитель (авиакомпания, отель) не должен
    // попасть в участники и получить приглашение.
    final created = await context.push<Object?>('/create-event', extra: {
      'start': b.start,
      'end': b.end ?? b.start?.add(const Duration(hours: 1)),
      'location': b.location,
      'title': '$kind: ${b.title}',
      'description': desc,
    });
    if (created == true) {
      await _markAdded(b);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_danger || !senderAuthenticated(widget.email.authResults)) return const SizedBox.shrink();
    if (!identical(_parsedFrom, widget.rawHtml)) {
      _parsedFrom = widget.rawHtml;
      _items = BookingParser.parseHtml(widget.rawHtml).where((b) => b.start != null).take(4).toList();
    }
    if (_items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final loc = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    return Column(children: [
      for (final b in _items)
        Container(
          margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.m),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: Radii.cardAll,
          ),
          // 1.7.2 (замечание 22.10.2026: кнопка «прикреплена к нижней
          // границе, а не по середине»): «В календарь» — справа по центру
          // карточки, а не отдельной строкой внизу.
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Icon(iconOf(b.kind), size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l10n.tr(kindKey(b.kind)), style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                  const SizedBox(height: 2),
                  Text(b.title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Space.xs),
                  Text(_when(b, loc), style: theme.textTheme.bodyMedium),
                  if (b.location != null)
                    Text(b.location!,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  if (b.reservationNumber != null || b.details != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: SelectableText(
                        [
                          if (b.reservationNumber != null) '${l10n.tr('bookingNumber')}: ${b.reservationNumber}',
                          if (b.details != null) b.details!,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: Space.xs),
              _isAdded(b)
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(AppIcons.event_available, size: Sizes.iconInline, color: AppColors.successText(context)),
                        const SizedBox(height: 2),
                        Text(l10n.tr('bookingAdded'),
                            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.successText(context))),
                      ]),
                    )
                  : (b.end ?? b.start!).isBefore(now)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.s),
                          child: Text(l10n.tr('bookingPast'), style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                        )
                      // Значок над подписью: на узком экране надпись в строку
                      // съела бы ширину у сведений о брони.
                      : SizedBox(
                          width: 84,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.s),
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: () => _addToCalendar(b, l10n),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(AppIcons.event, size: 22),
                              const SizedBox(height: 2),
                              Text(l10n.tr('addToCalendar'),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                            ]),
                          ),
                        ),
          ]),
        ),
    ]);
  }
}
