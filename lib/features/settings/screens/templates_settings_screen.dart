// lib/features/settings/screens/templates_settings_screen.dart
// Настройки подписи (с динамическими полями) и шаблонов ответов.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../compose/providers/templates_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../../widgets/common/app_sheet.dart';

class TemplatesSettingsScreen extends ConsumerStatefulWidget {
  const TemplatesSettingsScreen({super.key});
  @override
  ConsumerState<TemplatesSettingsScreen> createState() => _TemplatesSettingsScreenState();
}

class _TemplatesSettingsScreenState extends ConsumerState<TemplatesSettingsScreen> {
  late final TextEditingController _sigCtrl;
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    final sig = ref.read(signatureProvider);
    _sigCtrl = TextEditingController(text: sig.template);
    _phoneCtrl = TextEditingController(text: sig.phone);
  }

  @override
  void dispose() {
    _sigCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final sigN = ref.read(signatureProvider.notifier);
    final templates = [for (final t in ref.watch(templatesProvider)) t.resolve(l10n.tr)];

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('templatesSignature')))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
        children: [
          // ── Подпись ── Подписи живут в разделе «Подписи» (у каждого
          // ящика свои). Телефон ниже — для поля {телефон} в шаблонах
          // ответов; в подписи его подставляет карточка из адресной книги.
          SettingsSectionTitle(l10n.tr('signature')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.draw,
              title: l10n.tr('signatures'),
              onTap: () => context.push('/settings/signatures'),
            ),
          ]),

          // ── Шаблоны ──
          SettingsSectionTitle(l10n.tr('replyTemplates')),
          SettingsGroup(children: [
            if (templates.isEmpty)
              SettingsItem(icon: AppIcons.article, title: l10n.tr('noTemplatesYet'), onTap: null),
            for (var i = 0; i < templates.length; i++)
              ListTile(
                contentPadding: const EdgeInsets.only(left: Space.l, right: Space.xs),
                title: Text(templates[i].title),
                subtitle: Text(templates[i].body, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _editTemplate(context, ru, i),
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.delete, size: Sizes.iconRow),
                  onPressed: () => ref.read(templatesProvider.notifier).removeAt(i),
                ),
              ),
            SettingsItem(
              icon: AppIcons.add,
              title: l10n.tr('newTemplate'),
              trailing: const SizedBox.shrink(),
              onTap: () => _editTemplate(context, ru, null),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _phoneCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('phoneForField'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: sigN.setPhone,
                  ),
                  const SizedBox(height: Space.s),
                  Text(
                    l10n.tr('signatureFieldsHelp'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _editTemplate(BuildContext context, bool ru, int? index) async {
    final l10n = AppLocalizations.of(context);
    final existing = index != null ? ref.read(templatesProvider)[index].resolve(l10n.tr) : null;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    // Шторка, как правка подписи (замечание владельца 27.10.2026: окно
    // шаблонов отличалось от остального приложения).
    final saved = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: Space.l,
          right: Space.l,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.tr(index == null ? 'newTemplate' : 'editTemplate'),
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: Space.m),
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.tr('titleField')),
              ),
              const SizedBox(height: Space.m),
              TextField(
                controller: bodyCtrl,
                maxLines: 8,
                minLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.tr('templateBodyHint'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Space.m),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.tr('cancel'))),
                  const SizedBox(width: Space.s),
                  FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('save'))),
                ],
              ),
              const SizedBox(height: Space.l),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final t = ReplyTemplate(title: titleCtrl.text.trim(), body: bodyCtrl.text.trim());
    if (t.title.isEmpty && t.body.isEmpty) return;
    final n = ref.read(templatesProvider.notifier);
    if (index == null) {
      await n.add(t);
    } else {
      await n.update(index, t);
    }
  }
}
