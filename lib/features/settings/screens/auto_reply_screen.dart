// lib/features/settings/screens/auto_reply_screen.dart
// Автоответ «Нет на месте»: отпуск, без связи, больничный.
//
// Exchange (ActiveSync и EWS) — автоответ на СЕРВЕРЕ: работает, когда
// телефон выключен, виден и меняется в Outlook/OWA. По расписанию сервер
// сам включит его в начале периода и выключит в конце.
// Остальные ящики (IMAP: Яндекс, Mail.ru, Gmail…) — серверного автоответа по
// IMAP нет: отвечает телефон, когда получает почту; рядом — ссылка на
// настройки почты на сайте, где включить надёжнее.
//
// Готовые тексты по причине (4 языка) с датой возвращения и тем, кто
// замещает; текст можно поправить. Итог и ошибки — строкой на экране.

import '../../../widgets/ui/wheel_pickers.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/auto_reply_status.dart';
import '../../../services/mail/auto_responder_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/ews/ews_service.dart' show OofSettings;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart';

enum _Reason { vacation, offline, sick, custom }

class AutoReplyScreen extends ConsumerStatefulWidget {
  const AutoReplyScreen({super.key, this.accountId});

  /// Аккаунт, для которого открыт экран (из экрана аккаунта); null — активный.
  final String? accountId;

  @override
  ConsumerState<AutoReplyScreen> createState() => _AutoReplyScreenState();
}

class _AutoReplyScreenState extends ConsumerState<AutoReplyScreen> {
  bool _enabled = false;
  bool _scheduled = false;
  late DateTime _start = _defaultStart();
  late DateTime _end = _defaultEnd();
  bool _sendExternal = false;
  _Reason _reason = _Reason.vacation;
  final _internal = TextEditingController();
  final _external = TextEditingController();
  final _substitute = TextEditingController();
  bool _externalEdited = false;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _error;
  String? _done;
  OofSettings? _server;

  static DateTime _defaultStart() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, n.hour).add(const Duration(hours: 1));
  }

  static DateTime _defaultEnd() {
    final n = DateTime.now().add(const Duration(days: 7));
    return DateTime(n.year, n.month, n.day, 18);
  }

  @override
  void initState() {
    super.initState();
    // После первого кадра: _load использует локализацию (context).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _internal.dispose();
    _external.dispose();
    _substitute.dispose();
    super.dispose();
  }

  bool _serverSide(AccountModel? a) => a != null && a.isMsExchange;

  Future<void> _load() async {
    final account = ref.read(accountOrActiveProvider(widget.accountId));
    if (account == null) {
      setState(() => _loading = false);
      return;
    }
    if (_serverSide(account)) {
      final oof = await ref.read(mailEngineServiceProvider).getOof(account);
      if (!mounted) return;
      setState(() {
        _server = oof;
        _loadFailed = oof == null;
        if (oof != null) {
          _enabled = oof.enabled;
          _scheduled = oof.scheduled && oof.start != null && oof.end != null;
          if (_scheduled) {
            _start = oof.start!;
            _end = oof.end!;
          }
          _internal.text = oof.internalReply;
          _external.text = oof.externalReply;
          _sendExternal = oof.externalOn;
          _externalEdited = oof.externalReply.trim().isNotEmpty && oof.externalReply != oof.internalReply;
          _reason = oof.internalReply.trim().isEmpty ? _Reason.vacation : _Reason.custom;
          ref.read(autoReplyStatusProvider.notifier).set(account.id,
              OofStatus(on: oof.enabled, from: _scheduled ? _start : null, until: _scheduled ? _end : null));
        }
        _loading = false;
      });
    } else {
      final st = ref.read(autoResponderProvider);
      setState(() {
        _enabled = st.isEnabled;
        _internal.text = st.internalMessage;
        _external.text = st.externalMessage;
        _sendExternal = st.sendToExternal;
        _externalEdited = st.externalMessage.trim().isNotEmpty && st.externalMessage != st.internalMessage;
        _scheduled = st.startDate != null || st.endDate != null;
        if (st.startDate != null) _start = st.startDate!;
        if (st.endDate != null) _end = st.endDate!;
        _reason = st.internalMessage.trim().isEmpty ? _Reason.vacation : _Reason.custom;
        _loading = false;
      });
    }
    if (_internal.text.trim().isEmpty && mounted) _applyTemplate();
  }

  /// Текст по причине, дате окончания и замещающему (на языке приложения).
  void _applyTemplate() {
    if (_reason == _Reason.custom) return;
    final l10n = AppLocalizations.of(context);
    final date = DateFormat(l10n.localeCode == 'de' ? 'd. MMMM' : 'd MMMM', l10n.localeCode).format(_end);
    final until = _scheduled ? l10n.tr('oofUntilDate').replaceAll('{date}', date) : '';
    final who = _substitute.text.trim();
    final sub = who.isEmpty ? '' : l10n.tr('oofSub').replaceAll('{name}', who);
    final key = switch (_reason) {
      _Reason.vacation => 'oofTplVacation',
      _Reason.offline => 'oofTplOffline',
      _Reason.sick => 'oofTplSick',
      _Reason.custom => 'oofTplVacation',
    };
    final text = l10n.tr(key).replaceAll('{until}', until).replaceAll('{sub}', sub);
    setState(() {
      _internal.text = text;
      if (!_externalEdited) _external.text = text;
    });
  }

  Future<DateTime?> _pick(DateTime initial) async {
    // Автоответ уже идёт (начало в прошлом) — начало не может быть позже
    // исходного значения.
    return showWheelDateTimePicker(context,
        initial: initial,
        first: initial.isBefore(DateTime.now()) ? initial : DateTime.now().subtract(const Duration(days: 1)),
        last: DateTime.now().add(const Duration(days: 730)),
        minuteInterval: 1);
  }

  Future<void> _save() async {
    final account = ref.read(accountOrActiveProvider(widget.accountId));
    final l10n = AppLocalizations.of(context);
    if (account == null) return;
    setState(() {
      _error = null;
      _done = null;
    });
    if (_enabled && _scheduled && !_end.isAfter(_start)) {
      setState(() => _error = l10n.tr('oofEndBeforeStart'));
      return;
    }
    if (_enabled && _internal.text.trim().isEmpty) {
      setState(() => _error = l10n.tr('oofTextEmpty'));
      return;
    }
    setState(() => _saving = true);
    final external = _externalEdited && _external.text.trim().isNotEmpty ? _external.text : _internal.text;
    var ok = true;
    if (_serverSide(account)) {
      ok = await ref.read(mailEngineServiceProvider).setOof(
            account,
            enabled: _enabled,
            startTime: _enabled && _scheduled ? _start : null,
            endTime: _enabled && _scheduled ? _end : null,
            internalReply: _internal.text,
            externalReply: external,
            sendToExternal: _sendExternal,
          );
    } else {
      final n = ref.read(autoResponderProvider.notifier);
      await n.setAccountId(account.id);
      await n.setInternalMessage(_internal.text);
      await n.setExternalMessage(external);
      await n.setSendToExternal(_sendExternal);
      await n.setDates(_scheduled ? _start : null, _scheduled ? _end : null);
      await n.setEnabled(_enabled); // сбрасывает «кому уже ответили» — последним
    }
    if (!mounted) return;
    if (ok) {
      ref.read(autoReplyStatusProvider.notifier).set(account.id,
          OofStatus(on: _enabled, from: _scheduled ? _start : null, until: _scheduled ? _end : null));
    }
    setState(() {
      _saving = false;
      // Строка состояния вверху — по сохранённому, а не по прочитанному при входе.
      if (ok && _serverSide(account)) {
        _server = OofSettings(
          enabled: _enabled,
          scheduled: _scheduled,
          start: _scheduled ? _start : null,
          end: _scheduled ? _end : null,
          internalReply: _internal.text,
          externalReply: external,
          externalOn: _sendExternal,
        );
      }
      if (ok) {
        _done = !_enabled ? l10n.tr('oofSavedOff') : l10n.tr(_serverSide(account) ? 'oofSaved' : 'oofSavedDevice');
      } else {
        _error = l10n.tr('oofSaveFailed');
      }
    });
  }

  String? _webSettingsUrl(AccountModel a) {
    final host = '${a.imapServer ?? ''} ${a.email.split('@').last}'.toLowerCase();
    if (a.type == AccountType.google || host.contains('gmail') || host.contains('google')) {
      return 'https://mail.google.com/mail/u/0/#settings/general';
    }
    if (a.type == AccountType.yandex || host.contains('yandex') || host.contains('ya.ru')) {
      return 'https://mail.yandex.ru/#setup/filters';
    }
    if (a.type == AccountType.mailru ||
        host.contains('mail.ru') ||
        host.contains('inbox.ru') ||
        host.contains('list.ru') ||
        host.contains('bk.ru')) {
      return 'https://e.mail.ru/settings/filters';
    }
    if (a.type == AccountType.outlook || host.contains('outlook') || host.contains('hotmail')) {
      return 'https://outlook.live.com/mail/0/options/mail/automaticReplies';
    }
    return null;
  }

  String _status(AppLocalizations l10n) {
    final s = _server;
    if (s == null) return '';
    final fmt = DateFormat('d MMM, HH:mm', l10n.localeCode);
    if (!s.enabled) return l10n.tr('oofStatusOff');
    if (s.scheduled && s.start != null && s.end != null) {
      return l10n.tr('oofStatusScheduled')
          .replaceAll('{from}', fmt.format(s.start!))
          .replaceAll('{to}', fmt.format(s.end!));
    }
    return l10n.tr('oofStatusOn');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final account = ref.watch(accountOrActiveProvider(widget.accountId));
    final serverSide = _serverSide(account);
    final muted = AppColors.mutedText(context);
    final fmt = DateFormat('EEE, d MMM, HH:mm', l10n.localeCode);

    Widget note(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color ?? muted),
            const SizedBox(width: Space.s),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color ?? muted))),
          ]),
        );

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('autoReplies')),
        actions: [
          if (account != null)
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(Space.l),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(tooltip: l10n.tr('save'), icon: const Icon(AppIcons.check), onPressed: _save),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : account == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Text(l10n.tr('noActiveAccount'), textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
                      child: Text(account.email, style: theme.textTheme.titleSmall),
                    ),
                    if (serverSide && _status(l10n).isNotEmpty) note(AppIcons.info, _status(l10n)),
                    if (_loadFailed) note(AppIcons.error, l10n.tr('oofLoadFailed'), color: AppColors.errorText(context)),
                    note(serverSide ? AppIcons.cloud_done : AppIcons.smartphone,
                        l10n.tr(serverSide ? 'oofServerNote' : 'oofDeviceNote')),
                    if (!serverSide && _webSettingsUrl(account) != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.l, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(AppIcons.open_in_new, size: 18),
                            label: Text(l10n.tr('oofOpenWeb')),
                            onPressed: () => launchUrl(Uri.parse(_webSettingsUrl(account)!),
                                mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ),
                    const SizedBox(height: Space.s),
                    SettingsGroup(children: [
                      SettingsSwitchItem(
                        icon: AppIcons.beach_access,
                        title: l10n.tr('sendAutoReplies'),
                        value: _enabled,
                        onChanged: (v) {
                          setState(() => _enabled = v);
                          if (v && _internal.text.trim().isEmpty) _applyTemplate();
                        },
                      ),
                    ]),
                    if (_enabled) ...[
                      SettingsSectionTitle(l10n.tr('oofReason')),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s),
                        child: Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
                          for (final r in _Reason.values)
                            ChoiceChip(
                              label: Text(l10n.tr(switch (r) {
                                _Reason.vacation => 'oofVacation',
                                _Reason.offline => 'oofOffline',
                                _Reason.sick => 'oofSick',
                                _Reason.custom => 'oofCustom',
                              })),
                              selected: _reason == r,
                              onSelected: (_) {
                                setState(() => _reason = r);
                                _applyTemplate();
                              },
                            ),
                        ]),
                      ),
                      const SizedBox(height: Space.s),
                      SettingsGroup(children: [
                        SettingsSwitchItem(
                          icon: AppIcons.date_range,
                          title: l10n.tr('oofSchedule'),
                          subtitle: l10n.tr(serverSide ? 'oofScheduleDesc' : 'oofScheduleDescDevice'),
                          value: _scheduled,
                          onChanged: (v) {
                            setState(() => _scheduled = v);
                            _applyTemplate();
                          },
                        ),
                        if (_scheduled) ...[
                          ListTile(
                            leading: const Icon(AppIcons.event),
                            title: Text(l10n.tr('oofFrom')),
                            subtitle: Text(fmt.format(_start)),
                            onTap: () async {
                              final d = await _pick(_start);
                              if (d == null) return;
                              setState(() {
                                _start = d;
                                if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 1));
                              });
                              _applyTemplate();
                            },
                          ),
                          ListTile(
                            leading: const Icon(AppIcons.event_available),
                            title: Text(l10n.tr('oofTo')),
                            subtitle: Text(fmt.format(_end)),
                            onTap: () async {
                              final d = await _pick(_end);
                              if (d == null) return;
                              setState(() => _end = d);
                              _applyTemplate();
                            },
                          ),
                        ],
                      ]),
                      if (_reason != _Reason.custom)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                          child: TextField(
                            controller: _substitute,
                            onChanged: (_) => _applyTemplate(),
                            decoration: InputDecoration(
                              labelText: l10n.tr('oofSubstitute'),
                              hintText: l10n.tr('oofSubstituteHint'),
                              prefixIcon: const Icon(AppIcons.person),
                            ),
                          ),
                        ),
                      SettingsSectionTitle(l10n.tr(serverSide ? 'replyInsideOrg' : 'oofTextReply')),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s),
                        child: TextField(
                          controller: _internal,
                          minLines: 4,
                          maxLines: 10,
                          // Правка руками — текст свой, шаблон его больше не трогает.
                          onChanged: (_) {
                            if (_reason != _Reason.custom) setState(() => _reason = _Reason.custom);
                            if (!_externalEdited) _external.text = _internal.text;
                          },
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(height: Space.s),
                      SettingsGroup(children: [
                        SettingsSwitchItem(
                          icon: AppIcons.public,
                          title: l10n.tr('replyToExternal'),
                          subtitle: l10n.tr('oofExternalDesc'),
                          value: _sendExternal,
                          onChanged: (v) => setState(() => _sendExternal = v),
                        ),
                      ]),
                      if (_sendExternal)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
                          child: TextField(
                            controller: _external,
                            minLines: 3,
                            maxLines: 8,
                            onChanged: (_) => _externalEdited = true,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: l10n.tr('replyForExternal'),
                            ),
                          ),
                        ),
                    ],
                    if (_error != null) note(AppIcons.error, _error!, color: AppColors.errorText(context)),
                    if (_done != null) note(AppIcons.check_circle, _done!, color: AppColors.successText(context)),
                    Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(AppIcons.check),
                        label: Text(l10n.tr('save')),
                      ),
                    ),
                  ],
                ),
    );
  }
}
