// lib/features/mail/widgets/eml_translate_button.dart
// «Перевести» во вложенном письме (.eml, .msg) — просьба владельца
// 21.11.2026. Тот же переводчик и те же настройки показа, что у обычного
// письма (MailTranslationController): переведённый HTML отдаётся экрану
// предпросмотра, «Показать оригинал» возвращает исходный.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import 'mail_translation.dart';

class EmlTranslateButton extends ConsumerStatefulWidget {
  const EmlTranslateButton({
    super.key,
    required this.id,
    required this.subject,
    required this.html,
    required this.onChanged,
  });

  /// Постоянный id вложения (кэш перевода).
  final String id;
  final String subject;

  /// Исходный HTML письма (уже очищенный).
  final String html;

  /// Показать этот HTML и тему; null — исходные.
  final void Function(String? html, String? subject) onChanged;

  @override
  ConsumerState<EmlTranslateButton> createState() => _EmlTranslateButtonState();
}

class _EmlTranslateButtonState extends ConsumerState<EmlTranslateButton> {
  late final MailTranslationController _c = MailTranslationController(ref)..addListener(_changed);
  late final EmailModel _email = EmailModel(
    id: 'eml:${widget.id}',
    accountId: '',
    folderId: '',
    from: const EmailAddress(email: ''),
    to: const [],
    subject: widget.subject,
    bodyHtml: widget.html,
    receivedAt: DateTime.now(),
  );
  String? _shown;

  @override
  void initState() {
    super.initState();
    // Как в окне письма: язык письма определяется, «Всегда переводить с …»
    // срабатывает и здесь.
    _c.detect(_email);
  }

  void _changed() {
    if (!mounted) return;
    final html = _c.showing ? _c.apply(_email).bodyHtml : null;
    final next = html == widget.html ? null : html;
    if (next != _shown) {
      _shown = next;
      final s = _c.subjectFor(_email);
      final subject = s.second == null ? s.main : '${s.main}\n${s.second}';
      widget.onChanged(next, next == null || subject == widget.subject ? null : subject);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _c.phase == MailTranslationPhase.working;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: busy
            ? null
            : () => _c.showing ? _c.showOriginal() : unawaited(_c.translate(context, _email)),
        icon: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(AppIcons.translate, size: 18),
        label: Text(l10n.tr(_c.showing ? 'translateShowOriginal' : 'translate')),
      ),
    );
  }
}
