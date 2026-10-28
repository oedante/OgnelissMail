// lib/features/settings/screens/mail_settings_screen.dart
// Настройки почты: режим загрузки писем (ленивая/полная/полная с вложениями),
// группировка в беседы, действия свайпов.

import 'dart:async';

import '../../../widgets/ui/app_radio_tile.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/feature_flags_provider.dart';
import '../widgets/feature_settings_sections.dart';
import '../widgets/offline_store_section.dart';
import '../providers/settings_provider.dart';
import '../../mail/providers/startup_folder.dart';
import '../../mail/providers/drawer_prefs.dart'
    show quickFiltersProvider, quickReplyBarProvider, mailSwipePagerProvider, mailBarOrderProvider,
        MailBarOrderNotifier, MailBarAction, confirmMailDeleteProvider;
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../mail/widgets/mail_html_view.dart' show MailHtmlView;
import '../../compose/widgets/image_size_sheet.dart' show photoSizeLabel;

class MailSettingsScreen extends ConsumerWidget {
  const MailSettingsScreen({super.key});

  String _fetchModeLabel(EmailFetchMode m, AppLocalizations l10n) {
    switch (m) {
      case EmailFetchMode.headersOnly:
        return l10n.tr('fetchHeadersOnly');
      case EmailFetchMode.noAttachments:
        return l10n.tr('fetchNoAttachments');
      case EmailFetchMode.full:
        return l10n.tr('fetchFull');
      case EmailFetchMode.partial500k:
        return l10n.tr('fetchPartial500');
      case EmailFetchMode.partial100k:
        return l10n.tr('fetchPartial100');
      case EmailFetchMode.partial50k:
        return l10n.tr('fetchPartial50');
    }
  }

  String _barOrderLabel(List<MailBarAction> order, AppLocalizations l10n) {
    if (MailBarOrderNotifier.same(order, MailBarOrderNotifier.rightHand)) return l10n.tr('mailBarRightHand');
    if (MailBarOrderNotifier.same(order, MailBarOrderNotifier.leftHand)) return l10n.tr('mailBarLeftHand');
    return l10n.tr('mailBarCustom');
  }

  String _startupLabel(StartupFolder f, AppLocalizations l10n) => switch (f) {
        StartupFolder.allMail => l10n.allMail,
        StartupFolder.inbox => l10n.inbox,
        StartupFolder.last => l10n.tr('startupLast'),
      };

  Future<void> _pickStartup(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final current = ref.read(startupFolderProvider);
    final picked = await showAppSheet<StartupFolder>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(l10n.tr('startupFolder'), style: Theme.of(ctx).textTheme.titleMedium)),
          for (final f in StartupFolder.values)
            ListTile(
              title: Text(_startupLabel(f, l10n)),
              trailing: f == current ? Icon(AppIcons.check, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () => Navigator.pop(ctx, f),
            ),
        ]),
      ),
    );
    if (picked != null) await ref.read(startupFolderProvider.notifier).set(picked);
  }

  Future<void> _pickPhotoSize(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final current = ref.read(featureFlagsProvider).photoSize;
    final picked = await showAppSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(l10n.tr('photoSendSize'), style: Theme.of(ctx).textTheme.titleMedium)),
          for (final v in FeatureFlags.photoSizes)
            ListTile(
              title: Text(photoSizeLabel(l10n, v)),
              subtitle: v == 0 ? Text(l10n.tr('photoSizeAskDesc')) : null,
              trailing: v == current ? Icon(AppIcons.check, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]),
      ),
    );
    if (picked != null) await ref.read(featureFlagsProvider.notifier).setPhotoSize(picked);
  }

  String _fetchModeDesc(EmailFetchMode m, AppLocalizations l10n) {
    switch (m) {
      case EmailFetchMode.headersOnly:
        return l10n.tr('fetchHeadersOnlyDesc');
      case EmailFetchMode.noAttachments:
        return l10n.tr('fetchNoAttachmentsDesc');
      case EmailFetchMode.full:
        return l10n.tr('fetchFullDesc');
      default:
        return l10n.tr('fetchPartialDesc');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    // Основные режимы (вынесены наверх), остальные — в "ещё"
    const primaryModes = [
      EmailFetchMode.headersOnly,
      EmailFetchMode.noAttachments,
      EmailFetchMode.full,
    ];
    const partialModes = [
      EmailFetchMode.partial500k,
      EmailFetchMode.partial100k,
      EmailFetchMode.partial50k,
    ];

    final f = ref.watch(featureFlagsProvider);
    final fn = ref.read(featureFlagsProvider.notifier);
    final limited = partialModes.contains(settings.emailFetchMode);
    // Отмеченный пункт «Ограничить размер письма»: размер, «Полностью» или
    // ничего (только заголовки — тексты заранее не загружаются).
    final EmailFetchMode? limitGroup = limited
        ? settings.emailFetchMode
        : (settings.emailFetchMode == EmailFetchMode.headersOnly ? null : EmailFetchMode.noAttachments);

    Widget undoChip(String label, int seconds) => ChoiceChip(
          label: Text(label),
          selected: f.undoSendSeconds == seconds,
          onSelected: (_) => fn.setUndoSendSeconds(seconds),
        );

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('emailSettings')), actions: const [FaqButton(section: 'mail')])),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsSectionTitle(l10n.tr('mailListSection')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.start,
              title: l10n.tr('startupFolder'),
              subtitle: _startupLabel(ref.watch(startupFolderProvider), l10n),
              onTap: () => _pickStartup(context, ref, l10n),
            ),
            // Быстрые фильтры строкой над лентой (1.6.45).
            SettingsSwitchItem(
              icon: AppIcons.filter_list,
              title: l10n.tr('quickFilters'),
              subtitle: l10n.tr('quickFiltersDesc'),
              value: ref.watch(quickFiltersProvider),
              onChanged: (v) => ref.read(quickFiltersProvider.notifier).set(v),
            ),
            // Строка «Ответить…» внизу письма (1.6.49).
            SettingsSwitchItem(
              icon: AppIcons.quickreply,
              title: l10n.tr('quickReplyBar'),
              subtitle: l10n.tr('quickReplyBarDesc'),
              value: ref.watch(quickReplyBarProvider),
              onChanged: (v) => ref.read(quickReplyBarProvider.notifier).set(v),
            ),
            // Порядок кнопок под письмом (1.7.3): под правую руку (по
            // умолчанию), под левую или свой.
            SettingsItem(
              icon: AppIcons.view_week,
              title: l10n.tr('mailBarOrder'),
              subtitle: _barOrderLabel(ref.watch(mailBarOrderProvider), l10n),
              onTap: () => showMailBarOrderSheet(context),
            ),
            // Вопрос перед удалением кнопкой «Удалить» в письме (1.7.3).
            SettingsSwitchItem(
              icon: AppIcons.delete,
              title: l10n.tr('confirmMailDelete'),
              subtitle: l10n.tr('confirmMailDeleteDesc'),
              value: ref.watch(confirmMailDeleteProvider),
              onChanged: (v) => ref.read(confirmMailDeleteProvider.notifier).set(v),
            ),
            // Соседние письма ленты свайпом влево-вправо (1.6.49+95).
            SettingsSwitchItem(
              icon: AppIcons.swipe,
              title: l10n.tr('mailSwipePager'),
              subtitle: l10n.tr('mailSwipePagerDesc'),
              value: ref.watch(mailSwipePagerProvider),
              onChanged: (v) => ref.read(mailSwipePagerProvider.notifier).set(v),
            ),
            // ── Группировка в беседы ──
            SettingsSwitchItem(
              icon: AppIcons.forum,
              title: l10n.tr('threading'),
              subtitle: l10n.tr('threadingDesc'),
              value: settings.groupByConversation,
              onChanged: (v) => notifier.setGroupByConversation(v),
            ),
            // Сколько строк текста письма показывать (1.6.31): в ленте и в
            // карточке по удержанию — отдельно. Пустые строки пропускаются.
            SettingsItem(
              icon: AppIcons.notes,
              title: l10n.tr('previewLinesList'),
              subtitle: l10n.tr('previewLinesHint'),
              onTap: null,
              trailing: _LinesPicker(value: settings.previewLines, onChanged: notifier.setPreviewLines),
            ),
            SettingsItem(
              icon: AppIcons.open_in_full,
              title: l10n.tr('previewLinesPeek'),
              onTap: null,
              trailing: _LinesPicker(value: settings.peekPreviewLines, onChanged: notifier.setPeekPreviewLines),
            ),
            // Широкие письма (1.5.11): по умолчанию — обычный масштаб (текст
            // размера из настроек) и кнопка «По ширине экрана» над письмом.
            StatefulBuilder(
              builder: (ctx, setLocal) => SettingsSwitchItem(
                icon: AppIcons.fit_screen,
                title: l10n.tr('wideMailFit'),
                subtitle: l10n.tr('wideMailFitDesc'),
                value: MailHtmlView.fitWide,
                onChanged: (v) {
                  MailHtmlView.fitWide = v;
                  unawaited(ref.read(sharedPrefsProvider).setBool(MailHtmlView.fitWideKey, v));
                  setLocal(() {});
                },
              ),
            ),
          ]),
          // Бывшие «Возможности» (1.6.1): работа с письмами и их открытие.
          const MailWorkSection(),
          const MailOpeningSection(),
          // «Отправка» и «Антифишинг» — здесь, в почте (раньше лежали в
          // «Возможностях» среди разделов приложения).
          SettingsSectionTitle(l10n.tr('sending')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.undo,
              title: l10n.tr('undoSendWindow'),
              subtitle: l10n.tr('undoSendWindowDesc'),
              onTap: null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l + Sizes.icon + Space.l, 0, Space.l, Space.m),
              child: Wrap(
                spacing: Space.s,
                children: [
                  undoChip(l10n.tr('off'), 0),
                  undoChip('5 ${l10n.tr('secShort')}', 5),
                  undoChip('10 ${l10n.tr('secShort')}', 10),
                  undoChip('30 ${l10n.tr('secShort')}', 30),
                  // Отзыва уже отправленного письма нет — длинное окно отмены
                  // его заменяет.
                  undoChip('60 ${l10n.tr('secShort')}', 60),
                  undoChip('120 ${l10n.tr('secShort')}', 120),
                ],
              ),
            ),
            SettingsSwitchItem(
              icon: AppIcons.groups,
              title: l10n.tr('confirmRecipients'),
              subtitle: l10n.tr('confirmRecipientsDesc'),
              value: f.confirmRecipients,
              onChanged: fn.setConfirmRecipients,
            ),
            // Фото во вложениях (1.7.2+109): спрашивать при отправке или
            // сразу как есть / 75% / 50% / 25%.
            SettingsItem(
              icon: AppIcons.photo_size_select_large,
              title: l10n.tr('photoSendSize'),
              subtitle: f.photoSize == 0
                  ? l10n.tr('photoSizeAskDesc')
                  : l10n.tr('photoSizeFixedDesc').replaceAll('{size}', photoSizeLabel(l10n, f.photoSize)),
              hint: l10n.tr('imageSizeHelp'),
              onTap: () => unawaited(_pickPhotoSize(context, ref, l10n)),
            ),
          ]),
          SettingsSectionTitle(l10n.tr('antiPhishing')),
          SettingsGroup(children: [
            AppRadioTile<AntiPhishingLevel>(
              title: Text(l10n.tr('phishingOff')),
              value: AntiPhishingLevel.off,
              groupValue: f.antiPhishing,
              onChanged: (v) => fn.setAntiPhishing(v!),
            ),
            AppRadioTile<AntiPhishingLevel>(
              title: Text(l10n.tr('dangerOnly')),
              subtitle: Text(l10n.tr('dangerOnlyDesc')),
              value: AntiPhishingLevel.dangerOnly,
              groupValue: f.antiPhishing,
              onChanged: (v) => fn.setAntiPhishing(v!),
            ),
            AppRadioTile<AntiPhishingLevel>(
              title: Text(l10n.tr('allWarnings')),
              subtitle: Text(l10n.tr('allWarningsDesc')),
              value: AntiPhishingLevel.all,
              groupValue: f.antiPhishing,
              onChanged: (v) => fn.setAntiPhishing(v!),
            ),
          ]),
          SettingsSectionTitle(l10n.tr('fetchMode')),
          SettingsIntro(l10n.tr('fetchModeSubtitle')),
          SettingsGroup(children: [
            // Ограничение размера — разновидность «Письма целиком, вложения
            // по нажатию»: при нём отмечен этот режим, а размер выбран ниже.
            for (final m in primaryModes)
              AppRadioTile<EmailFetchMode>(
                title: Text(_fetchModeLabel(m, l10n)),
                subtitle: Text(_fetchModeDesc(m, l10n)),
                value: m,
                groupValue: limited ? EmailFetchMode.noAttachments : settings.emailFetchMode,
                onChanged: (v) {
                  if (v == null) return;
                  // Уже «целиком, вложения по нажатию» с ограничением — ограничение остаётся.
                  if (limited && v == EmailFetchMode.noAttachments) return;
                  notifier.setEmailFetchMode(v);
                },
              ),
            // Ограничение по сети имеет смысл только в режиме «с вложениями»:
            // в остальных вложения и так не предзагружаются.
            if (settings.emailFetchMode == EmailFetchMode.full)
              SettingsSwitchItem(
                icon: AppIcons.wifi,
                title: l10n.tr('downloadAttachmentsWifiOnly'),
                subtitle: l10n.tr('attachmentsWifiOnlyDesc'),
                value: settings.attachmentsWifiOnly,
                onChanged: notifier.setAttachmentsWifiOnly,
              ),
            ExpansionTile(
              title: Text(l10n.tr('economyModes')),
              subtitle: Text(l10n.tr('fetchPartialDesc')),
              // Выбран режим с ограничением — список открыт.
              initiallyExpanded: limited,
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                // «Полностью» — без ограничения: раньше, выбрав «до 500 КБ»,
                // вернуться к письмам любого размера отсюда было нельзя
                // (замечание 11.10.2026).
                AppRadioTile<EmailFetchMode>(
                  title: Text(l10n.tr('fetchNoLimit')),
                  subtitle: Text(l10n.tr('fetchNoLimitDesc')),
                  value: EmailFetchMode.noAttachments,
                  groupValue: limitGroup,
                  onChanged: (_) {
                    // «С вложениями» уже без ограничения — режим не меняем.
                    if (settings.emailFetchMode != EmailFetchMode.full) {
                      notifier.setEmailFetchMode(EmailFetchMode.noAttachments);
                    }
                  },
                ),
                for (final m in partialModes)
                  AppRadioTile<EmailFetchMode>(
                    title: Text(_fetchModeLabel(m, l10n)),
                    value: m,
                    groupValue: limitGroup,
                    onChanged: (v) => notifier.setEmailFetchMode(v!),
                  ),
              ],
            ),
          ]),
          // Что хранится на телефоне: текст за период синхронизации,
          // картинки — за выбранные дни (кроме «только заголовки»).
          if (settings.emailFetchMode != EmailFetchMode.headersOnly)
            const OfflineStoreSection(),
        ],
      ),
    );
  }
}

/// Выбор числа строк превью: 1–4.
class _LinesPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _LinesPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
      ),
      segments: [for (var i = 1; i <= 4; i++) ButtonSegment(value: i, label: Text('$i'))],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Порядок кнопок под письмом (1.7.3): «Под правую руку» (по умолчанию),
/// «Под левую руку» или свой — перетаскиванием. Слева направо, как на
/// экране письма.
Future<void> showMailBarOrderSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _MailBarOrderSheet(),
    );

class _MailBarOrderSheet extends ConsumerWidget {
  const _MailBarOrderSheet();

  static IconData _icon(MailBarAction a) => switch (a) {
        MailBarAction.reply => AppIcons.reply,
        MailBarAction.replyAll => AppIcons.reply_all,
        MailBarAction.forward => AppIcons.forward,
        MailBarAction.later => AppIcons.watch_later,
        MailBarAction.delete => AppIcons.delete,
        MailBarAction.more => AppIcons.more_horiz,
      };

  static String _label(MailBarAction a, AppLocalizations l10n) => switch (a) {
        MailBarAction.reply => l10n.tr('reply'),
        MailBarAction.replyAll => l10n.tr('replyAll'),
        MailBarAction.forward => l10n.tr('forward'),
        MailBarAction.later => l10n.tr('later'),
        MailBarAction.delete => l10n.delete,
        MailBarAction.more => l10n.tr('more'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final order = ref.watch(mailBarOrderProvider);
    final notifier = ref.read(mailBarOrderProvider.notifier);
    final right = MailBarOrderNotifier.same(order, MailBarOrderNotifier.rightHand);
    final left = MailBarOrderNotifier.same(order, MailBarOrderNotifier.leftHand);
    // Группа «рука»: true — правая, false — левая, null — свой порядок.
    final bool? hand = right ? true : (left ? false : null);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
              child: Row(children: [
                Expanded(child: Text(l10n.tr('mailBarOrder'), style: theme.textTheme.titleMedium)),
                HelpButton(title: l10n.tr('mailBarOrder'), text: l10n.tr('mailBarOrderHint')),
              ]),
            ),
            AppRadioTile<bool>(
              value: true,
              groupValue: hand,
              title: Text(l10n.tr('mailBarRightHand')),
              onChanged: (_) => unawaited(notifier.set(MailBarOrderNotifier.rightHand)),
            ),
            AppRadioTile<bool>(
              value: false,
              groupValue: hand,
              title: Text(l10n.tr('mailBarLeftHand')),
              onChanged: (_) => unawaited(notifier.set(MailBarOrderNotifier.leftHand)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
              child: Text(l10n.tr('mailBarDragHint'),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: order.length,
                // onReorderItem появился в Flutter 3.41; pubspec допускает 3.38.
                // ignore: deprecated_member_use
                onReorder: (from, to) => unawaited(notifier.move(from, to)),
                itemBuilder: (ctx, i) {
                  final a = order[i];
                  return ListTile(
                    key: ValueKey(a),
                    leading: Icon(_icon(a)),
                    title: Text(_label(a, l10n)),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(Space.s),
                        child: Icon(AppIcons.drag_handle),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.tr('done'))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
