// lib/features/settings/screens/dlp_settings_screen.dart
// Экран настроек DLP (Data Loss Prevention).
// Управление политиками: какие данные блокировать,
// внутренние домены, уровни классификации, отчёт нарушений.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'dart:async';
import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../providers/settings_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../services/security/dlp_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';

/// Провайдер настроек DLP. Раньше настройки жили только в памяти (терялись
/// при перезапуске) и ни на что не влияли: проверка перед отправкой брала
/// встроенные правила. Теперь они сохраняются и передаются в проверку, а
/// главный переключатель — тот же, что читает экран письма (s_dlp_on).
final dlpSettingsProvider =
    StateNotifierProvider<DlpSettingsNotifier, DlpSettings>((ref) {
  return DlpSettingsNotifier(ref);
});

/// Запись журнала проверки: что найдено и когда. Найденный текст (номер
/// паспорта, счёта, карты) не хранится — только вид нарушения.
class DlpLogEntry {
  final String description;
  final bool blocking;
  final DateTime at;
  const DlpLogEntry(this.description, this.blocking, this.at);

  Map<String, dynamic> toJson() => {'d': description, 'b': blocking, 't': at.millisecondsSinceEpoch};

  static DlpLogEntry? fromJson(Object? o) {
    if (o is! Map) return null;
    final d = o['d'], t = o['t'];
    if (d is! String || t is! num) return null;
    return DlpLogEntry(d, o['b'] == true, DateTime.fromMillisecondsSinceEpoch(t.toInt()));
  }
}

class DlpSettings {
  final bool isEnabled;
  final bool blockPersonalData;
  final bool blockBankData;
  final bool blockClassified;
  final bool warnMassSend;
  final int massSendThreshold;
  final Set<String> internalDomains;
  final List<DlpLogEntry> recentViolations;

  const DlpSettings({
    this.isEnabled = true,
    this.blockPersonalData = true,
    this.blockBankData = true,
    this.blockClassified = true,
    this.warnMassSend = true,
    this.massSendThreshold = 20,
    this.internalDomains = const {},
    this.recentViolations = const [],
  });

  DlpSettings copyWith({
    bool? isEnabled,
    bool? blockPersonalData,
    bool? blockBankData,
    bool? blockClassified,
    bool? warnMassSend,
    int? massSendThreshold,
    Set<String>? internalDomains,
    List<DlpLogEntry>? recentViolations,
  }) {
    return DlpSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      blockPersonalData: blockPersonalData ?? this.blockPersonalData,
      blockBankData: blockBankData ?? this.blockBankData,
      blockClassified: blockClassified ?? this.blockClassified,
      warnMassSend: warnMassSend ?? this.warnMassSend,
      massSendThreshold: massSendThreshold ?? this.massSendThreshold,
      internalDomains: internalDomains ?? this.internalDomains,
      recentViolations: recentViolations ?? this.recentViolations,
    );
  }
}

class DlpSettingsNotifier extends StateNotifier<DlpSettings> {
  final Ref _ref;
  DlpSettingsNotifier(Ref ref)
      : _ref = ref,
        super(_load(ref));

  static const _k = 'dlp_policy_v1';
  static const _kLog = 'dlp_log_v1';
  static const _logMax = 30;

  static List<DlpLogEntry> _loadLog(Ref ref) {
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_kLog);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List).map(DlpLogEntry.fromJson).whereType<DlpLogEntry>().toList();
    } catch (_) {
      return const [];
    }
  }

  static DlpSettings _load(Ref ref) {
    final p = ref.read(sharedPrefsProvider);
    final enabled = ref.read(settingsProvider).dlpEnabled;
    final base = DlpSettings(
      isEnabled: enabled,
      internalDomains: AppConstants.subsidiaryDomains.values.toSet(),
      recentViolations: _loadLog(ref),
    );
    try {
      final raw = p.getString(_k);
      if (raw == null) return base;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return base.copyWith(
        blockPersonalData: m['pd'] as bool?,
        blockBankData: m['bank'] as bool?,
        blockClassified: m['cls'] as bool?,
        warnMassSend: m['mass'] as bool?,
        massSendThreshold: (m['massN'] as num?)?.toInt(),
        internalDomains: (m['domains'] as List?)?.map((e) => '$e').toSet(),
      );
    } catch (_) {
      return base;
    }
  }

  void _save() {
    unawaited(_ref.read(sharedPrefsProvider).setString(_k, jsonEncode({
      'pd': state.blockPersonalData,
      'bank': state.blockBankData,
      'cls': state.blockClassified,
      'mass': state.warnMassSend,
      'massN': state.massSendThreshold,
      'domains': state.internalDomains.toList(),
    })));
  }

  void _set(DlpSettings s) {
    state = s;
    _save();
  }

  void setEnabled(bool v) {
    state = state.copyWith(isEnabled: v);
    unawaited(_ref.read(settingsProvider.notifier).setDlpEnabled(v));
  }

  void setBlockPersonalData(bool v) => _set(state.copyWith(blockPersonalData: v));
  void setBlockBankData(bool v) => _set(state.copyWith(blockBankData: v));
  void setBlockClassified(bool v) => _set(state.copyWith(blockClassified: v));
  void setWarnMassSend(bool v) => _set(state.copyWith(warnMassSend: v));
  void setMassSendThreshold(int v) => _set(state.copyWith(massSendThreshold: v));

  void addInternalDomain(String domain) {
    final d = domain.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (d.isEmpty) return;
    _set(state.copyWith(internalDomains: {...state.internalDomains, d}));
  }

  void removeInternalDomain(String domain) {
    _set(state.copyWith(internalDomains: {...state.internalDomains}..remove(domain)));
  }

  /// Записать найденное при отправке в журнал экрана (раньше журнал
  /// никто не пополнял — он всегда был пуст). Одинаковые нарушения одного
  /// письма — одной строкой.
  void logViolations(List<DlpViolation> violations) {
    if (violations.isEmpty) return;
    final now = DateTime.now();
    final seen = <String>{};
    final fresh = [
      for (final v in violations)
        if (seen.add(v.description)) DlpLogEntry(v.description, v.blocking, now),
    ];
    final updated = [...fresh, ...state.recentViolations].take(_logMax).toList();
    state = state.copyWith(recentViolations: updated);
    unawaited(_ref.read(sharedPrefsProvider).setString(
        _kLog, jsonEncode(updated.map((e) => e.toJson()).toList())));
  }

  void clearLog() {
    state = state.copyWith(recentViolations: const []);
    unawaited(_ref.read(sharedPrefsProvider).remove(_kLog));
  }
}

class DlpSettingsScreen extends ConsumerWidget {
  const DlpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dlp = ref.watch(dlpSettingsProvider);
    final notifier = ref.read(dlpSettingsProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('dlpTitle')),
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          // Главный переключатель
          // Где и как работает проверка — за «?» (раньше нигде не было
          // сказано, что она действует только для ящиков Exchange и что
          // исполняемые вложения блокируются всегда).
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.shield,
              title: l10n.tr('dlpEnable'),
              subtitle: dlp.isEnabled ? l10n.tr('enabled') : l10n.tr('disabled'),
              hint: l10n.tr('dlpScopeHint'),
              value: dlp.isEnabled,
              onChanged: (v) => notifier.setEnabled(v),
            ),
          ]),

          // ── ПОЛИТИКИ ──
          SettingsSectionTitle(l10n.tr('dlpPoliciesHeader')),
          SettingsGroup(children: [

          SwitchListTile(
            title: Text(l10n.tr('dlpPersonalData')),
            subtitle: Text(
                l10n.tr('dlpPersonalDataDesc')),
            value: dlp.blockPersonalData,
            onChanged: dlp.isEnabled
                ? (v) => notifier.setBlockPersonalData(v)
                : null,
          ),

          SwitchListTile(
            title: Text(l10n.tr('dlpBankDetails')),
            subtitle: Text(
                l10n.tr('dlpBankDetailsDesc')),
            value: dlp.blockBankData,
            onChanged: dlp.isEnabled
                ? (v) => notifier.setBlockBankData(v)
                : null,
          ),

          SwitchListTile(
            title: Text(l10n.tr('dlpClassified')),
            subtitle: Text(
                l10n.tr('dlpClassifiedDesc')),
            value: dlp.blockClassified,
            onChanged: dlp.isEnabled
                ? (v) => notifier.setBlockClassified(v)
                : null,
          ),

          SwitchListTile(
            title: Text(l10n.tr('dlpMassSend')),
            subtitle: Text(
                '${l10n.tr('dlpMassSendWarnOver')} ${dlp.massSendThreshold} ${l10n.tr('recipients')}'),
            value: dlp.warnMassSend,
            onChanged: dlp.isEnabled
                ? (v) => notifier.setWarnMassSend(v)
                : null,
          ),

          if (dlp.warnMassSend)
            ListTile(
              title: Text(l10n.tr('dlpMassThreshold')),
              trailing: SizedBox(
                width: 80,
                child: DropdownButton<int>(
                  value: dlp.massSendThreshold,
                  isExpanded: true,
                  items: [5, 10, 15, 20, 30, 50].map((v) {
                    return DropdownMenuItem(
                        value: v, child: Text('$v'));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) notifier.setMassSendThreshold(v);
                  },
                ),
              ),
            ),
          ]),

          // ── ВНУТРЕННИЕ ДОМЕНЫ ──
          SettingsSectionTitle(l10n.tr('dlpInternalDomains')),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Text(
              l10n.tr('dlpInternalDomainsDesc'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          SettingsGroup(children: [

          ...dlp.internalDomains.map((domain) => ListTile(
                leading: const Icon(AppIcons.domain, size: 20),
                title: Text(domain),
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.remove_circle,
                      size: 20, color: AppColors.errorRed),
                  onPressed: () => notifier.removeInternalDomain(domain),
                ),
                dense: true,
              )),

          SettingsItem(
            icon: AppIcons.add,
            title: l10n.tr('addDomain'),
            onTap: () => _addDomain(context, notifier),
          ),
          ]),

          // ── ЖУРНАЛ НАРУШЕНИЙ ──
          SettingsSectionTitle(l10n.tr('dlpRecentViolations')),
          SettingsGroup(children: [

          if (dlp.recentViolations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(l10n.tr('dlpNoViolations'),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
          ...[
            ...dlp.recentViolations.take(10).map((v) => ListTile(
                  leading: Icon(
                    v.blocking ? AppIcons.block : AppIcons.warning,
                    color: v.blocking
                        ? AppColors.errorRed
                        : AppColors.warningYellow,
                  ),
                  title: Text(v.description,
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text(AppDateFormat.dateTime(context, v.at),
                      style: theme.textTheme.bodySmall),
                  dense: true,
                )),
            SettingsItem(
              icon: AppIcons.clear_all,
              title: l10n.tr('trackerClearLog'),
              onTap: notifier.clearLog,
            ),
          ],
          ]),
        ],
      ),
    );
  }

  void _addDomain(BuildContext context, DlpSettingsNotifier notifier) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('addDomain')),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'example.com',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final domain = controller.text.trim().toLowerCase();
              if (domain.isNotEmpty && domain.contains('.')) {
                notifier.addInternalDomain(domain);
                Navigator.of(ctx).pop();
              }
            },
            child: Text(l10n.tr('add')),
          ),
        ],
      ),
    );
  }
}
