// lib/features/settings/widgets/feature_settings_sections.dart
// Функции, которые до 1.6.1 жили на отдельном экране «Возможности»
// (бывшие «Экспериментальные функции»). Решение владельца 13.10.2026: всё
// проверено тестированием — это основные функции, их настройки — в общих
// разделах: работа с почтой и открытие писем — в «Почте», «Мой день» и
// календарь — в «Календаре». Ключи настроек прежние (ExperimentalKeys):
// выбор тестировщиков сохраняется.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../widgets/ui/action_sheet.dart';
import '../../../core/theme/app_icons.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../calendar/calendar_data.dart' show calendarHubProvider;
import '../../mail/widgets/mail_html_view.dart' show MailWebViewPool;
import '../../mail/widgets/mail_header.dart' show RecipientsLayout;

/// Ключи выключателей, которых нет в других настройках (имена — с 1.5.x,
/// не менять: выбор пользователей сохраняется).
class ExperimentalKeys {
  ExperimentalKeys._();
  static const deviceRules = 'device_rules_on';
  static const easSession = 'eas_session_cache';
  /// «К встрече» в карточке встречи (MeetingPrep.prefKey).
  static const meetingPrep = 'meeting_prep_on';
  /// Окно письма заранее (1.5.9, MailWebViewPool).
  static const webViewSpare = 'webview_spare_on';
  /// Простые письма без WebView (1.5.9, MailNativeBody).
  static const nativeMail = 'native_mail_on';
  /// Встроенные картинки отдельно от документа письма (1.5.9).
  static const inlineByRequest = 'inline_by_request_on';
  /// Вид получателей в шапке письма (1.5.9): RecipientsLayout.name.
  static const recipientsLayout = 'recipients_layout';

  // ── «Экспериментальный функционал» (1.10.3): по умолчанию выключено ──

  /// Люди в шапках цитат — выключатель 1.10.3–1.10.4 (в «Экспериментальном»,
  /// по умолчанию выключено). С 1.10.5 — [quotePeopleNames]; выключенный
  /// вручную остаётся выключенным (quotePeopleMode).
  static const quotePeople = 'exp_quote_people';

  /// Люди в шапках цитат (1.10.5, «Почта → Работа с письмами»): имена
  /// «Фамилия И.О.», полностью или выключено — QuotePeopleMode.name.
  static const quotePeopleNames = 'quote_people_names';
}

/// Люди в шапках цитат (1.10.5, просьба владельца 03.11.2026: «режим
/// распознавания можно включить по умолчанию… два варианта "Фамилия И.О."
/// или "Фамилия И." и полный вариант. По умолчанию сокращённый»).
enum QuotePeopleMode { short, full, off }

QuotePeopleMode quotePeopleMode(SharedPreferences p) {
  final v = p.getString(ExperimentalKeys.quotePeopleNames);
  final m = QuotePeopleMode.values.where((e) => e.name == v).firstOrNull;
  if (m != null) return m;
  return p.getBool(ExperimentalKeys.quotePeople) == false ? QuotePeopleMode.off : QuotePeopleMode.short;
}

mixin _Prefs<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool pref(String key, {bool def = true}) => ref.read(sharedPrefsProvider).getBool(key) ?? def;

  void setPref(String key, bool v) {
    unawaited(ref.read(sharedPrefsProvider).setBool(key, v));
    setState(() {});
  }
}

/// «Почта → Работа с письмами»: вид получателей, правила на телефоне,
/// расписание доставки («На контроле» — в «Разделах приложения»).
class MailWorkSection extends ConsumerStatefulWidget {
  const MailWorkSection({super.key});

  @override
  ConsumerState<MailWorkSection> createState() => _MailWorkSectionState();
}

class _MailWorkSectionState extends ConsumerState<MailWorkSection> with _Prefs {
  RecipientsLayout get _recipLayout {
    final v = ref.read(sharedPrefsProvider).getString(ExperimentalKeys.recipientsLayout);
    return RecipientsLayout.values.where((l) => l.name == v).firstOrNull ?? RecipientsLayout.overlap;
  }

  Future<void> _pickRecipLayout(AppLocalizations l10n) async {
    final cur = _recipLayout;
    // Карточкой по центру (1.8.8), как меню «⋮»; выбранное — с галочкой.
    final picked = await showActionSheet<RecipientsLayout>(
      context,
      title: l10n.tr('expRecipTitle'),
      items: [
        for (final l in RecipientsLayout.values)
          ActionSheetItem(
            icon: l == cur ? AppIcons.radio_button_checked : AppIcons.radio_button_unchecked,
            label: l10n.tr('recip_${l.name}'),
            subtitle: l10n.tr('recip_${l.name}_desc'),
            value: l,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await ref.read(sharedPrefsProvider).setString(ExperimentalKeys.recipientsLayout, picked.name);
    if (mounted) setState(() {});
  }

  static const _quoteModeLabel = {
    QuotePeopleMode.short: 'quotePeopleShort',
    QuotePeopleMode.full: 'quotePeopleFull',
    QuotePeopleMode.off: 'disabled',
  };
  static const _quoteModeDesc = {
    QuotePeopleMode.short: 'quotePeopleShortDesc',
    QuotePeopleMode.full: 'quotePeopleFullDesc',
    QuotePeopleMode.off: 'quotePeopleOffDesc',
  };

  Future<void> _pickQuotePeople(AppLocalizations l10n) async {
    final cur = quotePeopleMode(ref.read(sharedPrefsProvider));
    final picked = await showActionSheet<QuotePeopleMode>(
      context,
      title: l10n.tr('quotePeopleTitle'),
      items: [
        for (final m in QuotePeopleMode.values)
          ActionSheetItem(
            icon: m == cur ? AppIcons.radio_button_checked : AppIcons.radio_button_unchecked,
            label: l10n.tr(_quoteModeLabel[m]!),
            subtitle: l10n.tr(_quoteModeDesc[m]!),
            value: m,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await ref.read(sharedPrefsProvider).setString(ExperimentalKeys.quotePeopleNames, picked.name);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quoteMode = quotePeopleMode(ref.read(sharedPrefsProvider));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionTitle(l10n.tr('expSectionMail')),
      SettingsGroup(children: [
        SettingsItem(
          icon: AppIcons.group,
          title: l10n.tr('expRecipTitle'),
          subtitle: l10n.tr('recip_${_recipLayout.name}'),
          hint: l10n.tr('expRecipHint'),
          onTap: () => unawaited(_pickRecipLayout(l10n)),
        ),
        // Люди в шапках цитат (1.10.5: из «Экспериментального», включено).
        SettingsItem(
          key: const ValueKey('quote_people_names'),
          icon: AppIcons.groups,
          title: l10n.tr('quotePeopleTitle'),
          subtitle: l10n.tr(_quoteModeLabel[quoteMode]!),
          hint: l10n.tr('quotePeopleDesc'),
          onTap: () => unawaited(_pickQuotePeople(l10n)),
        ),
        SettingsSwitchItem(
          icon: AppIcons.rule,
          title: l10n.tr('expRulesTitle'),
          subtitle: l10n.tr('expRulesDesc'),
          hint: l10n.tr('expRulesHint'),
          value: pref(ExperimentalKeys.deviceRules),
          onChanged: (v) => setPref(ExperimentalKeys.deviceRules, v),
        ),
        // «Расписание доставки» — в «Расширенных» (синхронизация) и у ящика
        // при выборе «по расписанию» (перегруппировка 08.11.2026).
      ]),
    ]);
  }
}

/// «Почта → Открытие писем»: окно письма заранее, простые письма без
/// браузера, сеанс Exchange, картинки письма отдельно. Каждое — выключатель
/// на случай, если на каком-то телефоне ведёт себя не так.
class MailOpeningSection extends ConsumerStatefulWidget {
  const MailOpeningSection({super.key});

  @override
  ConsumerState<MailOpeningSection> createState() => _MailOpeningSectionState();
}

class _MailOpeningSectionState extends ConsumerState<MailOpeningSection> with _Prefs {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionTitle(l10n.tr('mailOpeningSection')),
      SettingsGroup(children: [
        SettingsSwitchItem(
          icon: AppIcons.bolt,
          title: l10n.tr('expSpareTitle'),
          subtitle: l10n.tr('expSpareDesc'),
          hint: l10n.tr('expSpareHint'),
          value: pref(ExperimentalKeys.webViewSpare),
          onChanged: (v) {
            MailWebViewPool.enabled = v;
            if (!v) unawaited(MailWebViewPool.release());
            setPref(ExperimentalKeys.webViewSpare, v);
          },
        ),
        SettingsSwitchItem(
          icon: AppIcons.article,
          title: l10n.tr('expNativeTitle'),
          subtitle: l10n.tr('expNativeDesc'),
          hint: l10n.tr('expNativeHint'),
          value: pref(ExperimentalKeys.nativeMail),
          onChanged: (v) => setPref(ExperimentalKeys.nativeMail, v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.image,
          title: l10n.tr('expInlineReqTitle'),
          subtitle: l10n.tr('expInlineReqDesc'),
          hint: l10n.tr('expInlineReqHint'),
          value: pref(ExperimentalKeys.inlineByRequest, def: false),
          onChanged: (v) => setPref(ExperimentalKeys.inlineByRequest, v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.sync,
          title: l10n.tr('expEasSessionTitle'),
          subtitle: l10n.tr('expEasSessionDesc'),
          hint: l10n.tr('expEasSessionHint'),
          value: pref(ExperimentalKeys.easSession),
          onChanged: (v) => setPref(ExperimentalKeys.easSession, v),
        ),
      ]),
    ]);
  }
}

/// «Календарь → Мой день и календарь»: доска «Моего дня», «К встрече»,
/// общий календарь («Мой день» и утренняя сводка — в «Разделах приложения»).
class DayFeaturesSection extends ConsumerStatefulWidget {
  const DayFeaturesSection({super.key});

  @override
  ConsumerState<DayFeaturesSection> createState() => _DayFeaturesSectionState();
}

class _DayFeaturesSectionState extends ConsumerState<DayFeaturesSection> with _Prefs {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hub = ref.watch(calendarHubProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionTitle(l10n.tr('expSectionDay')),
      SettingsGroup(children: [
        SettingsSwitchItem(
          icon: AppIcons.groups,
          title: l10n.tr('meetingPrepTitle'),
          subtitle: l10n.tr('expMeetingPrepDesc'),
          hint: l10n.tr('meetingPrepHelp'),
          value: pref(ExperimentalKeys.meetingPrep),
          onChanged: (v) => setPref(ExperimentalKeys.meetingPrep, v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.calendar_today,
          title: l10n.tr('expHubTitle'),
          subtitle: l10n.tr('expHubDesc'),
          hint: l10n.tr('expHubHint'),
          value: hub,
          onChanged: (v) => ref.read(calendarHubProvider.notifier).set(v),
        ),
      ]),
    ]);
  }
}
