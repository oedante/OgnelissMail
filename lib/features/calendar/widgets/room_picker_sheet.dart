// lib/features/calendar/widgets/room_picker_sheet.dart
// Выбор переговорной при создании собрания (1.6.49, как «Помощник выбора
// помещений» Outlook): списки переговорных организации (здания, этажи —
// EWS GetRoomLists) чипами, ниже — переговорные выбранного списка (GetRooms)
// с занятостью на время собрания: свободные — первыми. Ящик ActiveSync — через
// EWS того же сервера. Списков в организации нет — «Найти в адресной книге».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/ews/ews_directory_extras.dart' show DirectoryRoom;
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/section_band.dart';

/// Итог выбора: переговорная или «искать в адресной книге».
sealed class RoomChoice {
  const RoomChoice();
}

class RoomPicked extends RoomChoice {
  final DirectoryRoom room;
  const RoomPicked(this.room);
}

class RoomSearchDirectory extends RoomChoice {
  const RoomSearchDirectory();
}

Future<RoomChoice?> showRoomPicker(
  BuildContext context, {
  required AccountModel account,
  required DateTime start,
  required DateTime end,
}) =>
    showAppSheet<RoomChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoomSheet(account: account, start: start, end: end),
    );

class _RoomSheet extends ConsumerStatefulWidget {
  final AccountModel account;
  final DateTime start;
  final DateTime end;
  const _RoomSheet({required this.account, required this.start, required this.end});

  @override
  ConsumerState<_RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends ConsumerState<_RoomSheet> {
  List<DirectoryRoom>? _lists;
  String? _list;
  List<DirectoryRoom>? _rooms;
  Map<String, int> _busy = const {};
  bool _busyLoading = false;
  String? _error;

  String get _prefKey => 'room_list_${widget.account.id}';

  @override
  void initState() {
    super.initState();
    unawaited(_loadLists());
  }

  Future<void> _loadLists() async {
    final engine = ref.read(mailEngineServiceProvider);
    try {
      final lists = await engine.roomLists(widget.account);
      if (!mounted) return;
      final saved = ref.read(sharedPrefsProvider).getString(_prefKey);
      final pick = lists.where((l) => l.email == saved).firstOrNull ?? lists.firstOrNull;
      setState(() {
        _lists = lists;
        _list = pick?.email;
      });
      if (pick != null) await _loadRooms(pick.email);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadRooms(String listEmail) async {
    final engine = ref.read(mailEngineServiceProvider);
    setState(() {
      _list = listEmail;
      _rooms = null;
      _busy = const {};
      _error = null;
    });
    unawaited(ref.read(sharedPrefsProvider).setString(_prefKey, listEmail));
    try {
      final rooms = await engine.roomsOf(widget.account, listEmail);
      if (!mounted || _list != listEmail) return;
      setState(() {
        _rooms = rooms;
        _busyLoading = rooms.isNotEmpty;
      });
      if (rooms.isEmpty) return;
      // Занятость — отдельно: список виден сразу, отметки — когда придут.
      try {
        final busy = await engine
            .busyStatus(widget.account, [for (final r in rooms.take(100)) r.email], widget.start, widget.end)
            .timeout(const Duration(seconds: 25));
        if (mounted && _list == listEmail) setState(() => _busy = busy);
      } catch (_) {
        // Занятость неизвестна — переговорные всё равно можно выбрать.
      } finally {
        if (mounted && _list == listEmail) setState(() => _busyLoading = false);
      }
    } catch (e) {
      if (mounted && _list == listEmail) setState(() => _error = '$e');
    }
  }

  int _order(DirectoryRoom r) => switch (_busy[r.email.toLowerCase()]) {
        0 => 0,
        null => 1,
        1 => 2,
        _ => 3,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final s = widget.start, e = widget.end;
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    final when = sameDay
        ? '${AppDateFormat.dayMonth(context, s)}, ${AppDateFormat.time(context, s)}–${AppDateFormat.time(context, e)}'
        : '${AppDateFormat.dayMonthTime(context, s)} – ${AppDateFormat.dayMonthTime(context, e)}';
    final lists = _lists;
    final rooms = _rooms;
    final shown = [...?rooms]..sort((a, b) => _order(a).compareTo(_order(b)));

    Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(l10n.tr('roomLoadError').replaceAll('{e}', _error!),
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.errorText(context))),
      );
    } else if (lists == null || (lists.isNotEmpty && rooms == null)) {
      body = const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()));
    } else if (lists.isEmpty || shown.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(l10n.tr(lists.isEmpty ? 'roomNoLists' : 'roomNoRooms'),
            textAlign: TextAlign.center, style: TextStyle(color: muted)),
      );
    } else {
      body = Flexible(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final r = shown[i];
            final st = _busy[r.email.toLowerCase()];
            final (label, color) = switch (st) {
              0 => (l10n.tr('roomFree'), AppColors.successText(context)),
              1 => (l10n.tr('tentativeStatus'), AppColors.accentOrangeText(context)),
              2 || 3 => (l10n.tr('roomBusy'), AppColors.errorText(context)),
              _ => (_busyLoading ? '…' : l10n.tr('roomUnknown'), muted),
            };
            return ListTile(
              leading: Icon(AppIcons.meeting_room, color: st == 0 ? color : null),
              title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
              onTap: () => Navigator.of(context).pop(RoomPicked(r)),
            );
          },
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionBand(title: l10n.tr('roomPickTitle')),
        Padding(
          padding: const EdgeInsets.only(left: Space.l, top: Space.s, right: Space.l),
          child: Text(when, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        ),
        if (lists != null && lists.length > 1)
          SizedBox(
            height: Sizes.tapTarget,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
              children: [
                for (final l in lists)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: ChoiceChip(
                      label: Text(l.name),
                      showCheckmark: false,
                      selected: l.email == _list,
                      onSelected: (_) => unawaited(_loadRooms(l.email)),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Space.xs),
        body,
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).pop(const RoomSearchDirectory()),
            icon: const Icon(AppIcons.search),
            label: Text(l10n.tr('roomSearchDirectory')),
          ),
        ),
      ]),
    );
  }
}
