// lib/features/mail/widgets/quick_reply_bar.dart
// Строка «Ответить…» внизу письма (1.6.49, как поле ввода в Telegram):
// короткий ответ отправителю без редактора — письмом (приветствие, текст,
// подпись ящика для ответов), через очередь отправки (QuickReplyService, тот
// же, что у ответа из уведомления). Выключается в «Настройки → Почта».
//
// 1.7.3 (замечания тестировщиков 25.10.2026: строка сливалась с кнопками под
// письмом, подсказка с длинным именем переносилась на две строки, «Ответить»
// стояла прямо над «Удалить»):
//  · плавающая карточка — со скруглением и тенью, как карточка письма по
//    удержанию, с отступом от кнопок под письмом;
//  · в письме — только поле и «Очистить»: отправляют кнопки «Ответить» /
//    «Ответить всем» под письмом (текст набран — отправить быстрым ответом,
//    поле пусто — полный редактор), связь — [QuickReplyController];
//  · в беседе (кнопок под письмом нет) — своя круглая кнопка: поле пусто —
//    полный редактор, текст набран — отправить; слева — переключатель
//    «Ответить всем» (по умолчанию — только отправителю).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../services/mail/quick_reply_service.dart';
import '../../../widgets/common/haptic_wrapper.dart';
import '../providers/mail_providers.dart' show accountsProvider;

/// Связь строки быстрого ответа с кнопками под письмом (1.7.3): кнопки
/// «Ответить» и «Ответить всем» узнают, набран ли текст, и отправляют его.
class QuickReplyController extends ChangeNotifier {
  _QuickReplyBarState? _bar;

  /// В поле есть текст — «Ответить» отправит его, а не откроет редактор.
  bool get hasText => _bar?._hasText ?? false;

  /// Идёт отправка.
  bool get sending => _bar?._sending ?? false;

  /// Отправить набранный текст отправителю ([all] — и остальным участникам).
  Future<void> send({bool all = false}) async {
    final bar = _bar;
    if (bar != null) await bar._send(all: all);
  }

  /// Забрать набранный текст (для полного редактора) — поле очищается.
  String take() => _bar?._take() ?? '';

  void _changed() => notifyListeners();
}

class QuickReplyBar extends ConsumerStatefulWidget {
  final EmailModel email;

  /// Кнопки отправки — снаружи, под письмом: в карточке только поле и
  /// «Очистить». null — карточка со своей кнопкой (беседа).
  final QuickReplyController? controller;

  const QuickReplyBar({super.key, required this.email, this.controller});

  @override
  ConsumerState<QuickReplyBar> createState() => _QuickReplyBarState();
}

class _QuickReplyBarState extends ConsumerState<QuickReplyBar> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;

  /// «Ответить всем» (1.6.49) — переключатель в беседе.
  bool _all = false;

  /// Был ли текст при прошлой проверке — кнопкам под письмом сообщается
  /// только смена «пусто ↔ есть текст», а не каждая буква.
  bool _hadText = false;

  bool get _hasText => _text.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller?._bar = this;
    _text.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant QuickReplyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._bar == this) oldWidget.controller?._bar = null;
      widget.controller?._bar = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._bar == this) widget.controller?._bar = null;
    _text.removeListener(_onText);
    _text.dispose();
    super.dispose();
  }

  void _onText() {
    final has = _hasText;
    if (has == _hadText) return;
    _hadText = has;
    if (mounted) setState(() {});
    widget.controller?._changed();
  }

  /// Кому: отправителю (или адресу «Ответить на»); своё письмо — его
  /// адресатам. «Всем» — плюс остальные адресаты и копия, без своих адресов.
  ({List<EmailAddress> to, List<EmailAddress> cc}) _recipients(bool all) {
    final e = widget.email;
    final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    bool mine(String email) => account != null && OwnAddresses.isMine(account, email);
    final fromMine = mine(e.from.email);
    final base = fromMine ? e.to : (e.replyTo.isNotEmpty ? e.replyTo : [e.from]);
    if (!all) return (to: base, cc: const <EmailAddress>[]);
    final seen = <String>{};
    List<EmailAddress> uniq(Iterable<EmailAddress> list) => [
          for (final a in list)
            if (a.email.trim().isNotEmpty && !mine(a.email) && seen.add(a.email.trim().toLowerCase())) a,
        ];
    final to = uniq([...base, ...e.to]);
    return (to: to, cc: uniq(e.cc));
  }

  /// Есть ли кому «ответить всем» кроме отправителя.
  bool _canAll() {
    final one = _recipients(false);
    final all = _recipients(true);
    return all.to.length + all.cc.length > one.to.length;
  }

  /// [all] — от кнопки «Ответить всем» под письмом; null — по переключателю.
  Future<void> _send({bool? all}) async {
    final l10n = AppLocalizations.of(context);
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    final e = widget.email;
    final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    final r = _recipients((all ?? _all) && _canAll());
    final to = r.to;
    if (account == null || to.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    widget.controller?._changed();
    try {
      await ref.read(quickReplyServiceProvider).send(
            account: account,
            to: to,
            cc: r.cc,
            subject: e.subject,
            text: text,
            originalEmailId: e.id,
          );
      if (!mounted) return;
      _text.clear();
      FocusScope.of(context).unfocus();
      unawaited(HapticHelper.success());
    } catch (err) {
      if (mounted) setState(() => _error = '${l10n.tr('sendError')}: $err');
    } finally {
      // Экран могли закрыть, пока шла отправка: тогда и связь уже снята.
      if (mounted) {
        setState(() => _sending = false);
        widget.controller?._changed();
      }
    }
  }

  /// Набранный текст — забрать и очистить поле.
  String _take() {
    final text = _text.text.trim();
    _text.clear();
    return text;
  }

  void _clear() {
    _text.clear();
    setState(() => _error = null);
  }

  /// Полный редактор ответа (с набранным текстом, если он есть).
  void _expand() {
    final e = widget.email;
    final all = _all && _canAll();
    final text = _take();
    unawaited(context.push(Uri(path: '/compose', queryParameters: {
      'replyToId': e.id,
      'accountId': e.accountId,
      if (all) 'replyAll': 'true',
      if (text.isNotEmpty) 'quick': text,
    }).toString()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final external = widget.controller != null;
    // В письме «всем» — отдельная кнопка под письмом, переключатель не нужен.
    final canAll = !external && _canAll();
    final all = _all && canAll;
    final r = _recipients(all);
    final who = r.to.isEmpty ? '' : r.to.first.label;
    final hasText = _hasText;
    final hint = all
        ? l10n.tr('quickReplyHintAll').replaceAll('{n}', '${r.to.length + r.cc.length}')
        : who.isEmpty
            ? l10n.tr('quickReplyHintNoName')
            : l10n.tr('quickReplyHint').replaceAll('{name}', who);
    const spinner = SizedBox.square(
      dimension: Sizes.iconRow,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Padding(
      // Плавающая карточка: отступ от краёв и от кнопок под письмом.
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          color: AppColors.cardFill(context),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          borderRadius: Radii.cardAll,
          clipBehavior: Clip.antiAlias,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Ответить всем / только отправителю (беседа).
            if (canAll)
              Padding(
                padding: const EdgeInsets.only(left: Space.xs, bottom: Space.xs),
                child: IconButton(
                  tooltip: l10n.tr(all ? 'quickReplyToSender' : 'replyAll'),
                  isSelected: all,
                  icon: const Icon(AppIcons.reply),
                  selectedIcon: Icon(AppIcons.reply_all, color: scheme.primary),
                  onPressed: () => setState(() => _all = !all),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  hintText: hint,
                  // Длинное имя — многоточием, а не второй строкой.
                  hintMaxLines: 1,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.fromLTRB(canAll ? Space.xs : Space.l, Space.m, Space.s, Space.m),
                ),
              ),
            ),
            if (external && _sending)
              const Padding(padding: EdgeInsets.all(Space.m), child: spinner)
            else if (hasText)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: IconButton(
                  tooltip: l10n.tr('quickReplyClear'),
                  icon: const Icon(AppIcons.close),
                  onPressed: _sending ? null : _clear,
                ),
              ),
            // Беседа: поле пусто — полный редактор, текст набран — отправить.
            if (!external)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, Space.xs, Space.xs, Space.xs),
                child: IconButton.filled(
                  tooltip: l10n.tr(hasText ? 'send' : 'quickReplyExpand'),
                  onPressed: _sending ? null : (hasText ? () => unawaited(_send()) : _expand),
                  icon: _sending ? spinner : Icon(hasText ? AppIcons.send : AppIcons.open_in_full),
                ),
              ),
          ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs, left: Space.s),
            child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.errorText(context))),
          ),
      ]),
    );
  }
}
