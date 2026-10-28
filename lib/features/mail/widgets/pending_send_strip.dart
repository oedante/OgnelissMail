// lib/features/mail/widgets/pending_send_strip.dart
// Письма с задержкой отправки — строками, пока не ушли:
// «Отправка через 12 с · Кому: … · Тема» и кнопка «Отменить» (письмо
// возвращается в редактор). Раньше отменить можно было только из
// всплывающего сообщения, а всплывающих сообщений в приложении больше нет.
//
// С 1.7.2+106 — поверх ленты внизу, вместе с «Письмо удалено · Вернуть»
// (undo_strip.dart): строка над лентой при исчезновении сдвигала всю ленту.

import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/offline_send_service.dart';
import '../../../widgets/common/undo_strip.dart';
import '../providers/mail_providers.dart';

/// Письма в Исходящих с окном отмены (id «undosend_…»); срок — в sentAt.
final pendingSendsProvider = StreamProvider.autoDispose<List<Email>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.emails)
        ..where((e) => e.folderId.equals('outbox') & e.id.like('undosend_%'))
        ..orderBy([(e) => OrderingTerm(expression: e.receivedAt)]))
      .watch();
});

class PendingSendStrip extends ConsumerStatefulWidget {
  const PendingSendStrip({super.key});

  @override
  ConsumerState<PendingSendStrip> createState() => _PendingSendStripState();
}

class _PendingSendStripState extends ConsumerState<PendingSendStrip> {
  Timer? _tick;
  final _cancelled = <String>{};

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _ensureTicker(bool needed) {
    if (needed && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  Future<void> _cancel(Email e) async {
    setState(() => _cancelled.add(e.id));
    final ok = await ref.read(offlineSendProvider).cancelUndoSend(e.id);
    if (!mounted) return;
    if (ok) {
      unawaited(ref.read(emailsProvider.notifier).refresh());
      // Письмо — снова в редакторе: поправить и отправить заново.
      unawaited(context.push(Uri(path: '/compose', queryParameters: {
        'draftId': e.id,
        'accountId': e.accountId,
      }).toString()));
    } else {
      setState(() => _cancelled.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(pendingSendsProvider).value ?? const <Email>[];
    final visible = [for (final e in list) if (!_cancelled.contains(e.id)) e];
    _ensureTicker(visible.isNotEmpty);
    if (visible.isEmpty) return const FloatingStripSwitcher(child: null);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final now = DateTime.now();
    return FloatingStripSwitcher(
        child: Column(key: const ValueKey('sends'), mainAxisSize: MainAxisSize.min, children: [
      for (final e in visible)
        FloatingStripSurface(
          child: Row(children: [
            Icon(AppIcons.schedule_send, size: Sizes.iconInline, color: theme.colorScheme.primary),
            const SizedBox(width: Space.s),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  () {
                    final left = e.sentAt == null ? 0 : e.sentAt!.difference(now).inSeconds;
                    return left > 0
                        ? l10n.tr('sendingIn').replaceAll('{secs}', '$left')
                        : l10n.tr('sendingNow');
                  }(),
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  e.subject.trim().isEmpty ? l10n.tr('noSubject') : e.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ]),
            ),
            TextButton(
              onPressed: e.sentAt != null && e.sentAt!.isAfter(now) ? () => _cancel(e) : null,
              child: Text(l10n.tr('undo')),
            ),
          ]),
        ),
    ]));
  }
}
