// lib/features/settings/screens/signatures_settings_screen.dart
// Управление подписями: список, создание, редактирование, удаление,
// выбор подписи по умолчанию, автовставка.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/mail/signature_service.dart';
import '../providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../compose/widgets/mail_editor.dart';
import '../../../services/mail/signature_import_service.dart';
import '../../mail/providers/mail_providers.dart' show accountOrActiveProvider;
import '../../../widgets/common/app_sheet.dart';
import '../../../services/mail/greeting_mode.dart';
import '../../../core/utils/greeting_helper.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../../widgets/ui/app_menu_button.dart';

class SignaturesSettingsScreen extends ConsumerWidget {
  const SignaturesSettingsScreen({super.key, this.accountId});

  /// Аккаунт, для которого открыт экран (из экрана аккаунта); null — активный.
  final String? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(signaturesProvider);
    final choices = ref.watch(signatureChoicesProvider);
    final settings = ref.watch(settingsProvider);
    final account = ref.watch(accountOrActiveProvider(accountId));
    // Подписи аккаунта: общие и его собственные (раньше — все подряд).
    final signatures = account == null
        ? all
        : SignatureChoicesNotifier.forAccount(all, account.id);

    String choiceLabel(bool reply) {
      if (account == null) return '';
      final s = SignatureChoicesNotifier.resolve(all, choices, account.id, reply: reply);
      return s?.name ?? l10n.tr('noSignature');
    }

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('signatures')),
        bottom: account == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(account.email, style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
      )),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editSignature(context, ref, null),
        child: const Icon(AppIcons.add),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.tr('autoSignature')),
            subtitle: Text(l10n.tr('autoInsertSignatureDesc')),
            value: settings.autoInsertSignature,
            onChanged: (v) => ref.read(settingsProvider.notifier).setAutoInsertSignature(v),
          ),
          if (account != null) ...[
            // Приветствие в начале письма — своё для ящика.
            ListTile(
              leading: const Icon(AppIcons.waving_hand),
              title: Text(l10n.tr('greetingSetting')),
              subtitle: Text(_greetingLabel(
                  l10n, ref.watch(greetingModeProvider)[account.id] ?? GreetingMode.helloName)),
              onTap: () => _pickGreeting(context, ref, account.id),
            ),
            ListTile(
              enabled: settings.autoInsertSignature,
              leading: const Icon(AppIcons.edit),
              title: Text(l10n.tr('signatureForNew')),
              subtitle: Text(choiceLabel(false)),
              onTap: () => _pickChoice(context, ref, account.id, signatures, reply: false),
            ),
            ListTile(
              enabled: settings.autoInsertSignature,
              leading: const Icon(AppIcons.reply),
              title: Text(l10n.tr('signatureForReplies')),
              subtitle: Text(choiceLabel(true)),
              onTap: () => _pickChoice(context, ref, account.id, signatures, reply: true),
            ),
          ],
          const Divider(),
          if (signatures.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Center(child: Text(l10n.tr('noSignatures'))),
            ),
          ...signatures.map((sig) => ListTile(
                leading: Icon(sig.isDefault ? AppIcons.star : AppIcons.draw,
                    color: sig.isDefault ? AppColors.brandAmber : null),
                title: Text(sig.name),
                subtitle: Text(sig.plainContent,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _editSignature(context, ref, sig),
                trailing: AppMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'default') {
                      ref.read(signaturesProvider.notifier).setDefault(sig.id);
                    } else if (action == 'delete') {
                      ref.read(signaturesProvider.notifier).deleteSignature(sig.id);
                    }
                  },
                  itemBuilder: (_) => [
                    AppMenuEntry(value: 'default', icon: AppIcons.star, label: l10n.tr('makeDefault')),
                    AppMenuEntry(value: 'delete', icon: AppIcons.delete, label: l10n.tr('delete'), destructive: true),
                  ],
                ),
              )),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  /// Образцы — из тех же шаблонов, что вставляются в письмо (на языке
  /// приложения): «Добрый день!», «Добрый день, Имя Отчество,».
  static String _greetingLabel(AppLocalizations l10n, GreetingMode m) => switch (m) {
        GreetingMode.off => l10n.tr('greetingOff'),
        GreetingMode.hello => GreetingHelper.sample(l10n.localeCode, withName: false),
        GreetingMode.helloName => GreetingHelper.sample(l10n.localeCode),
      };

  /// Приветствие: нет / «Добрый день!» / «Добрый день, Имя Отчество,».
  Future<void> _pickGreeting(BuildContext context, WidgetRef ref, String accId) async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(greetingModeProvider.notifier).of(accId);
    // Карточкой (1.8.8), как меню «⋮»; текущее — с галочкой.
    final picked = await showChoiceSheet<GreetingMode>(
      context,
      title: l10n.tr('greetingSetting'),
      subtitle: l10n.tr('greetingSettingDesc'),
      selected: current,
      entries: [for (final m in GreetingMode.values) AppMenuEntry(value: m, label: _greetingLabel(l10n, m))],
    );
    if (picked != null) await ref.read(greetingModeProvider.notifier).set(accId, picked);
  }

  /// Выбор подписи для новых писем или для ответов и пересылки.
  void _pickChoice(BuildContext context, WidgetRef ref, String accId,
      List<SignatureModel> signatures, {required bool reply}) {
    final l10n = AppLocalizations.of(context);
    final current = SignatureChoicesNotifier.resolve(
        ref.read(signaturesProvider), ref.read(signatureChoicesProvider), accId,
        reply: reply);
    // Карточкой (1.8.8), как меню «⋮»; текущая — с галочкой ('' — без подписи).
    unawaited(showChoiceSheet<String>(
      context,
      title: l10n.tr(reply ? 'signatureForReplies' : 'signatureForNew'),
      selected: current?.id ?? '',
      entries: [
        AppMenuEntry(value: '', label: l10n.tr('noSignature')),
        for (final s in signatures)
          AppMenuEntry(
            value: s.id,
            label: s.name,
            icon: AppIcons.draw,
            subtitle: () {
              final t = s.plainContent.replaceAll('\n', ' ').trim();
              return t.length > 60 ? '${t.substring(0, 60)}…' : t;
            }(),
          ),
      ],
    ).then((id) {
      if (id != null) ref.read(signatureChoicesProvider.notifier).set(accId, reply: reply, signatureId: id);
    }));
  }

  void _editSignature(BuildContext context, WidgetRef ref, SignatureModel? existing) {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: existing?.name ?? '');
    final plainController = TextEditingController(text: existing?.plainContent ?? '');
    final htmlController = MailEditorController();
    final useHtml = mailEditorSupported;
    // Редактор не загрузился — переходим на простое поле.
    var editorFailed = false;
    String? lastHtml = existing?.htmlContent;

    showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: Space.l, right: Space.l, top: Space.l,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: l10n.tr('signatureName')),
              ),
              const SizedBox(height: Space.m),
              // Редактор подписи: HugeRTE (таблицы, форматирование) или простое поле.
              if (useHtml)
                StatefulBuilder(
                  builder: (context, setLocal) => editorFailed
                      ? TextField(
                          controller: plainController,
                          maxLines: 6,
                          decoration: InputDecoration(
                            labelText: l10n.tr('signatureText'),
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        )
                      : MailEditor(
                          controller: htmlController,
                          initialHtml: existing?.htmlContent ?? '',
                          placeholder: l10n.tr('signatureText'),
                          height: 320,
                          onChanged: (h) => lastHtml = h,
                          onPickImage: pickInlineImageDataUri,
                          onFailed: () => setLocal(() => editorFailed = true),
                        ),
                )
              else
                TextField(
                  controller: plainController,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: l10n.tr('signatureText'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: Space.m),
              // Импорт подписи из почтового ящика (Gmail/Exchange/эвристика по «Отправленным»).
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(AppIcons.cloud_download, size: 18),
                  label: Text(l10n.tr('importFromMailbox')),
                  onPressed: () async {
                    final account = ref.read(accountOrActiveProvider(accountId));
                    if (account == null) return;
                    showInlineNotice(l10n.tr('importingSignature'));
                    final imported =
                        await ref.read(signatureImportServiceProvider).importSignature(account);
                    if (!ctx.mounted) return;
                    if (imported == null) {
                      showInlineError(l10n.tr('signatureNotFound'));
                    } else {
                      if (useHtml && !editorFailed) {
                        unawaited(htmlController.setHtml(imported.html));
                        lastHtml = imported.html;
                      } else {
                        plainController.text = imported.plain;
                      }
                      if (nameController.text.trim().isEmpty) {
                        nameController.text = account.email;
                      }
                      showInlineNotice(l10n.tr('signatureImported'));
                    }
                  },
                ),
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        String html;
                        String plain;
                        if (useHtml && !editorFailed) {
                          html = await htmlController.getHtml() ?? lastHtml ?? '';
                          plain = html
                              .replaceAll(RegExp(r'<br\s*/?>'), '\n')
                              .replaceAll(RegExp(r'<[^>]*>'), '')
                              .trim();
                        } else {
                          plain = plainController.text.trim();
                          html = '<div>${plain.replaceAll('\n', '<br>')}</div>';
                        }
                        if (name.isEmpty || (html.trim().isEmpty && plain.isEmpty)) return;
                        final notifier = ref.read(signaturesProvider.notifier);
                        if (existing == null) {
                          // Создана на экране аккаунта — подпись этого аккаунта.
                          unawaited(notifier.addSignature(SignatureModel(
                            id: 'sig_${DateTime.now().millisecondsSinceEpoch}',
                            name: name,
                            htmlContent: html,
                            plainContent: plain,
                            accountId: accountId,
                          )));
                        } else {
                          unawaited(notifier.updateSignature(existing.copyWith(
                            name: name,
                            plainContent: plain,
                            htmlContent: html,
                          )));
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(l10n.tr('save')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
            ],
          ),
        ),
      ),
    );
  }
}
