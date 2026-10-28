// lib/features/mail/widgets/auto_reply_strip.dart
// Строка вверху ленты, пока включён автоответ: «Автоответ включён · ящик ·
// до 20 окт» и «Выключить». Нажатие на строку — настройки автоответа.
// Ошибка выключения — строкой здесь же, без всплывающих окон.
//
// 1.7.2 (замечание 20.10.2026: «плашка начинает мешать»): строку можно
// скрыть крестиком, не выключая автоответ. Скрыта — до следующего включения
// автоответа (другая дата окончания) или до перезапуска не нужна: ключ
// «ящик|до» хранится в настройках. О работающем автоответе напоминает значок
// на портрете ящика в нижней панели ([AutoReplyBadge]): облачко с молнией
// (quickreply, замечание 24.10.2026 — круглые стрелки читались как
// синхронизация).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/auto_reply_status.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/mail/auto_responder_service.dart';
import '../providers/mail_providers.dart' show accountsProvider;

/// Ящики, у которых автоответ работает сейчас: Exchange — по состоянию с
/// сервера, остальные — автоответчик телефона (одна строка на все ящики без
/// своего).
List<(AccountModel, OofStatus)> activeAutoReplies(WidgetRef ref) {
  final status = ref.watch(autoReplyStatusProvider);
  final device = ref.watch(autoResponderProvider);
  final accounts = ref.watch(accountsProvider).where((a) => a.isActive).toList();
  final now = DateTime.now();
  final rows = <(AccountModel, OofStatus)>[];
  var deviceShown = false;
  for (final a in accounts) {
    if (a.isMsExchange) {
      final s = status[a.id];
      if (s != null && s.activeAt(now)) rows.add((a, s));
    } else if (!deviceShown && device.isActive && (device.accountId == null || device.accountId == a.id)) {
      deviceShown = true;
      rows.add((a, OofStatus(on: true, until: device.endDate)));
    }
  }
  return rows;
}

String _hideKey(AccountModel a, OofStatus s) => '${a.id}|${s.until?.millisecondsSinceEpoch ?? 0}';

/// Скрытые строки автоответа: «ящик|до».
final oofStripHiddenProvider =
    NotifierProvider<OofStripHiddenNotifier, Set<String>>(OofStripHiddenNotifier.new);

class OofStripHiddenNotifier extends Notifier<Set<String>> {
  static const _key = 'oof_strip_hidden';

  @override
  Set<String> build() {
    try {
      return (ref.read(sharedPrefsProvider).getStringList(_key) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  void hide(String key) {
    state = {...state, key};
    try {
      unawaited(ref.read(sharedPrefsProvider).setStringList(_key, state.toList()));
    } catch (_) {}
  }
}

/// Значок «автоответ включён» на портрете ящика (нижняя панель): строку в
/// ленте можно скрыть, а забыть про автоответ не хочется. [accountId] —
/// ящик портрета; null — «Все ящики» или группа (любой ящик).
class AutoReplyBadge extends ConsumerWidget {
  final Widget child;
  final String? accountId;
  const AutoReplyBadge({super.key, required this.child, this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = activeAutoReplies(ref);
    final on = rows.any((r) => accountId == null || r.$1.id == accountId);
    if (!on) return child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(clipBehavior: Clip.none, children: [
      child,
      Positioned(
        right: -5,
        bottom: -4,
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.surfaceContainer, width: 1.5),
          ),
          alignment: Alignment.center,
          // Зонтик — тот же значок, что у строки «Автоответ включён», в
          // настройках автоответа и в поиске настроек (1.7.2+109, замечание
          // владельца 24.10.2026: «значок автоответа непонятный»). Прежние —
          // круглые стрелки (похожи на синхронизацию) и облачко с молнией
          // (это значок «Быстрых ответов»). Залитый: тонкий контур в 10 пт
          // не читается.
          child: Icon(AppIcons.beach_access, size: 10, fill: 1, color: scheme.onPrimary),
        ),
      ),
    ]);
  }
}

class AutoReplyStrip extends ConsumerStatefulWidget {
  const AutoReplyStrip({super.key});

  @override
  ConsumerState<AutoReplyStrip> createState() => _AutoReplyStripState();
}

class _AutoReplyStripState extends ConsumerState<AutoReplyStrip> {
  final _busy = <String>{};
  final _failed = <String>{};

  @override
  void initState() {
    super.initState();
    // Состояние с сервера Exchange — раз за запуск (виден и автоответ,
    // включённый в Outlook).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(autoReplyStatusProvider.notifier).refreshOnce(ref.read(accountsProvider)));
    });
  }

  Future<void> _off(AccountModel a) async {
    setState(() {
      _busy.add(a.id);
      _failed.remove(a.id);
    });
    final ok = await ref.read(autoReplyStatusProvider.notifier).turnOff(a);
    if (!mounted) return;
    setState(() {
      _busy.remove(a.id);
      if (!ok) _failed.add(a.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(oofStripHiddenProvider);
    final accounts = ref.watch(accountsProvider).where((a) => a.isActive).toList();
    final rows = [
      for (final r in activeAutoReplies(ref))
        if (!hidden.contains(_hideKey(r.$1, r.$2)) || _failed.contains(r.$1.id)) r,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final fmt = DateFormat('d MMM, HH:mm', l10n.localeCode);
    final many = accounts.length > 1;
    return Column(children: [
      for (final (a, s) in rows)
        Container(
          margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/settings/auto-reply?accountId=${Uri.encodeQueryComponent(a.id)}'),
            child: Padding(
              padding: const EdgeInsets.only(left: Space.m),
              child: Row(children: [
                Icon(AppIcons.beach_access, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    _failed.contains(a.id)
                        ? l10n.tr('oofTurnOffFailed')
                        : [
                            l10n.tr('oofStripOn'),
                            if (many) a.email,
                            if (s.until != null) l10n.tr('oofStripUntil').replaceAll('{date}', fmt.format(s.until!)),
                          ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                        color: _failed.contains(a.id) ? AppColors.errorText(context) : muted),
                  ),
                ),
                _busy.contains(a.id)
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: Space.l),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton(onPressed: () => _off(a), child: Text(l10n.tr('oofTurnOff'))),
                // Скрыть строку, автоответ остаётся (1.7.2).
                IconButton(
                  tooltip: l10n.tr('oofStripHide'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(AppIcons.close, size: 18, color: muted),
                  onPressed: () => ref.read(oofStripHiddenProvider.notifier).hide(_hideKey(a, s)),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}
