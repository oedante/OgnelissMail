// lib/features/settings/widgets/account_label_dialog.dart
// Название ящика (2.6.1, просьба владельца 16.11.2026): окно ввода — на
// экране ящика и сразу после добавления ящика ([ask]: «Как назвать ящик?»,
// можно пропустить). Название показывается вместо логина в уведомлениях и
// под заголовком почты (AccountLabels).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/accounts/account_labels.dart';

/// Спросить название ящика [account] и сохранить. [ask] — предложение после
/// добавления ящика: заголовок-вопрос, пояснение и «Пропустить».
Future<void> showAccountLabelDialog(BuildContext context, WidgetRef ref, AccountModel account,
    {bool ask = false}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => _AccountLabelDialog(
      account: account,
      initial: ref.read(accountLabelsProvider)[account.id] ?? '',
      ask: ask,
    ),
  );
  if (value == null) return;
  await ref.read(accountLabelsProvider.notifier).set(account.id, value);
}

// Окно со своим полем ввода: поле освобождается вместе с окном, после
// анимации закрытия (раньше — сразу после закрытия, пока окно ещё
// рисовалось).
class _AccountLabelDialog extends StatefulWidget {
  const _AccountLabelDialog({required this.account, required this.initial, required this.ask});
  final AccountModel account;
  final String initial;
  final bool ask;

  @override
  State<_AccountLabelDialog> createState() => _AccountLabelDialogState();
}

class _AccountLabelDialogState extends State<_AccountLabelDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.tr(widget.ask ? 'accountLabelAsk' : 'accountLabel')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.ask) ...[
              Text(l10n.tr('accountLabelAskBody')),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const Key('account_label_field'),
              controller: _ctl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: AccountLabels.maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r\t]'))],
              decoration:
                  InputDecoration(hintText: l10n.tr('accountLabelHint'), helperText: widget.account.email),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.ask ? l10n.tr('skip') : l10n.cancel),
        ),
        FilledButton(
          key: const Key('account_label_save'),
          onPressed: () => Navigator.pop(context, _ctl.text),
          child: Text(l10n.tr('save')),
        ),
      ],
    );
  }
}
