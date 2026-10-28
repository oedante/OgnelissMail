// lib/features/settings/widgets/offline_store_section.dart
// Настройки → Почта → «На телефоне»: сколько писем уже хранится целиком
// (текст для чтения без сети и поиска) и сколько дней держать встроенные
// картинки. Модель — OfflineStoreService.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/theme/tokens.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sync/offline_store_service.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;

class OfflineStoreSection extends ConsumerStatefulWidget {
  const OfflineStoreSection({super.key});

  @override
  ConsumerState<OfflineStoreSection> createState() => _OfflineStoreSectionState();
}

class _OfflineStoreSectionState extends ConsumerState<OfflineStoreSection> {
  late int _imageDays;
  ({int stored, int waiting})? _stats;

  @override
  void initState() {
    super.initState();
    _imageDays = ref.read(sharedPrefsProvider).getInt(OfflineStoreService.imagesPrefKey) ??
        OfflineStoreService.defaultImageDays;
    unawaited(_count());
  }

  /// Письма периода синхронизации (кроме «Корзины», «Спама» и выключенных
  /// папок): с текстом на телефоне и те, что ещё докачаются. Правила — те
  /// же, что у докачки (OfflineStoreService.stats): раньше «ждут загрузки»
  /// считало все письма базы без текста, включая старые и копии «Вся почта»
  /// Gmail, которые не докачиваются (замечание 11.10.2026: 2615 «ждут»).
  Future<void> _count() async {
    try {
      final s = await ref.read(offlineStoreProvider).stats(ref.read(accountsProvider));
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _setImageDays(int d) async {
    await ref.read(sharedPrefsProvider).setInt(OfflineStoreService.imagesPrefKey, d);
    if (mounted) setState(() => _imageDays = d);
  }

  String _daysLabel(int d, AppLocalizations l10n) => switch (d) {
        3 => l10n.tr('onPhone3Days'),
        7 => l10n.tr('onPhoneWeek'),
        14 => l10n.tr('onPhone2Weeks'),
        _ => l10n.tr('onPhoneMonth'),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = _stats;
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.tr('onPhoneSection'), help: l10n.tr('onPhoneHelp')),
        SettingsGroup(children: [
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tr('onPhoneIntro'), style: theme.textTheme.bodyMedium),
                const SizedBox(height: Space.xs),
                Text(
                  s == null
                      ? ' '
                      : l10n
                          .tr('onPhoneStats')
                          .replaceAll('{n}', '${s.stored}')
                          .replaceAll('{m}', '${s.waiting}'),
                  style: muted,
                ),
                const SizedBox(height: Space.l),
                Text(l10n.tr('onPhoneImages'), style: theme.textTheme.bodyMedium),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: Space.s,
                  runSpacing: Space.xs,
                  children: [
                    for (final d in OfflineStoreService.imageChoices)
                      ChoiceChip(
                        label: Text(_daysLabel(d, l10n)),
                        selected: _imageDays == d,
                        onSelected: (_) => _setImageDays(d),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(l10n.tr('onPhoneImagesHint'), style: muted),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}
