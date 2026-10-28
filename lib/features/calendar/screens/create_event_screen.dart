// lib/features/calendar/screens/create_event_screen.dart
// Экран создания встречи/события. Автозаполнение из письма,
// выбор участников из GAL, повторения, напоминания, цвет,
// ссылка на онлайн-встречу.

import '../../../widgets/ui/wheel_pickers.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsGroup, SettingsSectionTitle;
import '../../../core/utils/text_safe.dart';
import '../../settings/providers/module_settings_provider.dart';
import '../../../core/theme/app_icons.dart';
import 'dart:async';
import 'dart:io' show File;
import '../../../core/logging/app_logger.dart';
import 'package:drift/drift.dart' show Value, InsertMode, BooleanExpressionOperators;
import '../../../data/database/app_database.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../../data/models/email_model.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/attachment_cache_service.dart' show attachmentCacheProvider;
import '../../mail/providers/mail_providers.dart';
import '../../../data/providers/database_provider.dart';
import 'calendar_screen.dart';
import '../../../services/mail/transport_capabilities.dart';
import '../../../data/models/free_busy_view.dart';
import 'dart:convert';
import '../../../services/notifications/reminder_scheduler_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../compose/widgets/people_picker_sheet.dart';
import '../../../core/utils/person_names.dart';
import '../../../core/utils/category_colors.dart';
import '../../../services/contacts/person_name_directory.dart';
import '../calendar_event_actions.dart';
import '../event_conflicts.dart';
import '../widgets/room_picker_sheet.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../services/mail/ews/ews_directory_extras.dart' show DirectoryRoom;
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../data/models/account_model.dart';
import '../../../services/calendar/event_reminders.dart';
import '../../../widgets/ui/help_hint.dart' show TitleWithHelp;
import '../widgets/reminder_list_editor.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  /// Письмо-источник (если создаём из письма)
  final EmailModel? sourceEmail;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final String? initialLocation;
  final String? initialTitle;
  /// Описание (например, номер брони из письма).
  final String? initialDescription;

  /// Правка существующей встречи (иначе — создание новой).
  final CalendarEvent? editEvent;

  /// Новая встреча — копия этой (тот же аккаунт, текст, участники; время
  /// можно поменять до сохранения).
  final CalendarEvent? duplicateOf;

  const CreateEventScreen({
    super.key,
    this.sourceEmail,
    this.initialStart,
    this.initialEnd,
    this.initialLocation,
    this.initialTitle,
    this.initialDescription,
    this.editEvent,
    this.duplicateOf,
  });

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  String? _titleError;
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _onlineLinkController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Новая встреча — с ближайшего получаса (19:48 → 20:00) на 30 минут, как
  // в Outlook (1.6.8, замечание владельца: было «сейчас + час» — 20:47).
  DateTime _startDate = nextHalfHour(DateTime.now());
  DateTime _endDate = nextHalfHour(DateTime.now()).add(defaultMeetingLength);
  bool _isAllDay = false;
  RecurrenceType _recurrence = RecurrenceType.none;
  EventPriority _priority = EventPriority.normal;
  /// Напоминания (минуты до начала, по возрастанию; 1.7.2+110 — несколько,
  /// раньше одно). По умолчанию — из настроек календаря.
  List<int> _reminders = const [15];

  /// Ящик, в календарь которого сохраняется встреча (1.7.2+110): выбранный
  /// в почте или первый с календарём; у правки — ящик самой встречи.
  String? _accountId;
  int _selectedColor = AppColors.primaryBlue.toARGB32();
  bool _isPrivate = false;
  bool _isSaving = false;

  final List<EventAttendee> _attendees = [];

  /// Собрание — встреча с участниками: им уходит приглашение, они отвечают
  /// (1.6.7). С 1.7.2+110 выбора «Встреча / Собрание» нет (замечание
  /// владельца 24.10.2026: «пользователям непонятно, почему встреча, если нет
  /// приглашённых»): одна форма, добавили участников — это собрание.
  bool get _isMeeting => _attendees.isNotEmpty;

  /// Участники у встречи — можно добавить. У новой — всегда; у правки — если
  /// встреча уже с участниками (личную встречу в собрание правкой не
  /// превращаем: сервер разослал бы приглашения задним числом).
  bool get _canInvite => widget.editEvent == null || _originalAttendees.isNotEmpty;
  bool _responseRequested = true;
  bool _allowNewTime = true;

  /// Участники до правки — чтобы при изменении собрания предложить
  /// разослать обновление только добавленным и удалённым (1.6.7).
  final Set<String> _originalAttendees = {};

  /// Вложения письма-источника, кроме встроенных картинок (1.6.12).
  List<EmailAttachment> get _emailFiles => [
        for (final a in widget.sourceEmail?.attachments ?? const <EmailAttachment>[])
          if (!(a.isInline && a.mimeType.toLowerCase().startsWith('image/'))) a,
      ];
  bool _attachEmailFiles = true;

  /// Загрузки файлов письма: одна на файл — фоновая докачка при открытии
  /// окна и сохранение встречи ждут одну и ту же (1.6.18).
  final Map<String, Future<Uint8List?>> _fileTasks = {};

  /// Файл письма: из кэша вложений или с сервера (и в кэш). null — не вышло.
  Future<Uint8List?> _emailFile(EmailAttachment a) {
    final email = widget.sourceEmail!;
    return _fileTasks[a.id] ??= () async {
      final account = ref.read(accountsProvider).where((x) => x.id == email.accountId).firstOrNull;
      if (account == null) return null;
      final cache = ref.read(attachmentCacheProvider);
      final key = MailEngineService.attachmentCacheKey(account.id, email.id, a.id);
      try {
        final path = await cache.get(key);
        if (path != null && await File(path).exists()) return await File(path).readAsBytes();
        final bytes = Uint8List.fromList(
            await ref.read(mailEngineServiceProvider).getAttachmentBytes(account, a.id, emailId: email.id));
        if (bytes.isEmpty) throw StateError('сервер вернул пустое вложение');
        try {
          await cache.put(key, a.name, bytes);
        } catch (_) {}
        return bytes;
      } catch (e) {
        AppLogger.warning('Встреча из письма: вложение «${a.name}» не получено: $e');
        _fileTasks.remove(a.id)?.ignore(); // при сохранении — ещё одна попытка
        return null;
      }
    }();
  }

  /// Файлы письма для новой встречи. Больше 25 МБ вместе — остальные
  /// пропускаются (сервер всё равно не примет). [failed] — не скачались:
  /// раньше они молча пропадали, и встреча создавалась без них.
  Future<({List<({String name, String? contentType, Uint8List bytes})> files, List<String> failed})>
      _collectEmailFiles() async {
    final email = widget.sourceEmail;
    if (email == null || !_attachEmailFiles || _emailFiles.isEmpty) {
      return (files: const <({String name, String? contentType, Uint8List bytes})>[], failed: const <String>[]);
    }
    final out = <({String name, String? contentType, Uint8List bytes})>[];
    final failed = <String>[];
    var total = 0;
    for (final a in _emailFiles) {
      final bytes = await _emailFile(a);
      if (bytes == null || bytes.isEmpty) {
        failed.add(a.name);
        continue;
      }
      if (total + bytes.length > 25 * 1024 * 1024) {
        AppLogger.warning('Встреча из письма: «${a.name}» не приложен — вместе больше 25 МБ');
        continue;
      }
      total += bytes.length;
      out.add((name: a.name, contentType: a.mimeType.isEmpty ? null : a.mimeType, bytes: bytes));
    }
    return (files: out, failed: failed);
  }

  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefilled) {
      _prefilled = true;
      // Напоминание новой встречи — из настроек календаря (0 там = «Нет»).
      final def = ref.read(moduleSettingsProvider).defaultReminderMinutes;
      // «Нет» в настройках — без напоминаний (раньше оставалось «за 15 мин»).
      _reminders = def > 0 ? [def] : const [];
      _accountId = _defaultAccountId();
      _prefillFromEmail();
      // Файлы письма — качаем сразу, в фоне (1.6.18): к сохранению встречи
      // они уже на телефоне, даже если письмо не открывали до конца.
      if (widget.editEvent == null && widget.sourceEmail != null) {
        for (final a in _emailFiles) {
          unawaited(_emailFile(a));
        }
      }
      _originalAttendees.addAll(_attendees.map((a) => a.email.trim().toLowerCase()));
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillAttendeeNames());
    }
  }

  /// Полные ФИО участников (1.6.4): адресная книга Exchange и заголовки писем
  /// дают «Смирнов, Андрей», а в компании много однофамильцев — нужно ФИО.
  /// Ищется в контактах, письмах и адресной книге ([PersonNameDirectory]);
  /// найденное показывается в плашке и уходит на сервер в приглашении.
  final Set<String> _nameAsked = {};
  void _fillAttendeeNames() {
    if (!mounted) return;
    final acc = _account;
    for (final a in List<EventAttendee>.of(_attendees)) {
      final key = a.email.trim().toLowerCase();
      if (key.isEmpty || _nameAsked.contains(key)) continue;
      final dn = a.displayName ?? '';
      if (PersonNames.words(dn) >= 3 && !dn.contains(',')) continue;
      _nameAsked.add(key);
      unawaited(ref.read(personNameDirectoryProvider).fullName(a.email, account: acc).then((full) {
        if (!mounted || full == null || !PersonNames.better(dn, full)) return;
        setState(() {
          for (var i = 0; i < _attendees.length; i++) {
            final x = _attendees[i];
            if (x.email.trim().toLowerCase() != key) continue;
            _attendees[i] = EventAttendee(
                email: x.email, displayName: full, isRequired: x.isRequired, response: x.response);
          }
        });
      }, onError: (Object _) {}));
    }
  }

  /// Конец не позже начала — сервер отклонил бы встречу (ActiveSync: Status 6).
  bool get _endBeforeStart => _isAllDay
      ? DateTime(_endDate.year, _endDate.month, _endDate.day)
          .isBefore(DateTime(_startDate.year, _startDate.month, _startDate.day))
      : !_endDate.isAfter(_startDate);

  /// Заполнить форму из редактируемой встречи.
  void _prefillFromEvent(CalendarEvent e) {
    _titleController.text = e.title;
    _descriptionController.text = e.description ?? '';
    _locationController.text = e.location ?? '';
    _onlineLinkController.text = e.onlineMeetingUrl ?? '';
    _isAllDay = e.isAllDay;
    _startDate = e.startTime.toLocal();
    final end = e.endTime.toLocal();
    // Весь день хранится с концом «полночь после последнего дня» — в форме
    // показываем последний день.
    _endDate = e.isAllDay ? end.subtract(const Duration(days: 1)) : end;
    if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    _recurrence = RecurrenceType.values[e.recurrence.clamp(0, RecurrenceType.values.length - 1)];
    _priority = EventPriority.values[e.priority.clamp(0, EventPriority.values.length - 1)];
    if (e.colorValue != null) _selectedColor = e.colorValue!;
    _isPrivate = e.isPrivate;
    // Все напоминания встречи (свои с сервера и телефонные); не заданы —
    // остаются из настроек календаря (они и действуют).
    final own = ReminderSchedulerService.remindersOf(e.remindersJson);
    if (own != null) _reminders = EventReminders.normalize(own);
    try {
      for (final a in (jsonDecode(e.attendeesJson ?? '[]') as List).whereType<Map>()) {
        final email = (a['email'] ?? '').toString();
        if (email.isEmpty) continue;
        _attendees.add(EventAttendee(
          email: email,
          displayName: a['displayName'] as String?,
          isRequired: a['isRequired'] as bool? ?? true,
        ));
      }
    } catch (_) {}
  }

  void _prefillFromEmail() {
    final edit = widget.editEvent ?? widget.duplicateOf;
    if (edit != null) {
      _prefillFromEvent(edit);
      // Принятие предложенного участником времени (1.6.7): открывается
      // правка собрания с этим временем — организатор проверяет и сохраняет.
      if (widget.editEvent != null && widget.initialStart != null) {
        _startDate = widget.initialStart!;
        _endDate = widget.initialEnd ?? _startDate.add(defaultMeetingLength);
      }
      return;
    }
    if (widget.sourceEmail != null) {
      final l10n = AppLocalizations.of(context);
      final email = widget.sourceEmail!;
      _titleController.text = '${l10n.tr('discussionPrefix')}: ${email.subject}';
      _descriptionController.text =
          '${l10n.tr('createdFromEmail')}: ${email.subject}\n${l10n.tr('from')}: ${email.from.label}';

      // Добавляем отправителя как участника
      _attendees.add(EventAttendee(
        email: email.from.email,
        displayName: email.from.displayName,
        isRequired: true,
      ));

      // Добавляем получателей
      for (final to in email.to.take(5)) {
        _attendees.add(EventAttendee(
          email: to.email,
          displayName: to.displayName,
          isRequired: true,
        ));
      }
    }

    // Предзаполнение из умной подсказки (детекция даты/времени/места/темы).
    if ((widget.initialTitle?.isNotEmpty ?? false) && _titleController.text.isEmpty) {
      _titleController.text = widget.initialTitle!;
    }
    if (widget.initialStart != null) {
      _startDate = widget.initialStart!;
      _endDate = widget.initialEnd ?? widget.initialStart!.add(defaultMeetingLength);
    }
    if (widget.initialLocation?.isNotEmpty ?? false) {
      _locationController.text = widget.initialLocation!;
    }
    if ((widget.initialDescription?.isNotEmpty ?? false) && _descriptionController.text.isEmpty) {
      _descriptionController.text = widget.initialDescription!;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _onlineLinkController.dispose();
    _descriptionController.dispose();
    _conflictTimer?.cancel();
    super.dispose();
  }

  // ── Ящик встречи (1.7.2+110) ──

  /// Ящики, в календарь которых можно сохранить встречу: включённые, без
  /// общих ящиков и архива Exchange (у копии встречи — и её ящик).
  List<AccountModel> _calendarAccounts() {
    final keep = widget.duplicateOf?.accountId ?? widget.editEvent?.accountId;
    return [
      for (final a in ref.read(accountsProvider))
        if (a.id == keep || (a.isActive && !a.isSharedMailbox && !a.isOnlineArchive)) a,
    ];
  }

  /// По умолчанию: ящик встречи (правка, копия), иначе выбранный в почте,
  /// если у него есть календарь, иначе первый ящик с календарём.
  String? _defaultAccountId() {
    final own = widget.editEvent?.accountId ?? widget.duplicateOf?.accountId;
    if (own != null) return own;
    final list = _calendarAccounts();
    final active = ref.read(activeAccountProvider);
    if (list.isEmpty) return active?.id;
    final engine = ref.read(mailEngineServiceProvider);
    if (active != null && list.any((a) => a.id == active.id) && engine.canWriteCalendar(active)) return active.id;
    return (list.where(engine.canWriteCalendar).firstOrNull ?? list.first).id;
  }

  AccountModel? get _account {
    final id = _accountId;
    final accounts = ref.read(accountsProvider);
    return (id == null ? null : accounts.where((a) => a.id == id).firstOrNull) ?? ref.read(activeAccountProvider);
  }

  /// «Ермишин Олег» или адрес, если имени нет.
  static String _accountTitle(AccountModel a) {
    final n = a.displayName.trim();
    return n.isEmpty || n.toLowerCase() == a.email.toLowerCase() ? a.email : n;
  }

  /// Строка «Календарь»: цвет и имя ящика, адрес; нажатие — выбор ящика (у
  /// новой встречи, если ящиков с календарём несколько).
  Widget _calendarRow(AppLocalizations l10n) {
    final acc = _account;
    if (acc == null) return const SizedBox.shrink();
    final engine = ref.read(mailEngineServiceProvider);
    final pickable = widget.editEvent == null && _calendarAccounts().length > 1;
    final title = _accountTitle(acc);
    final sub = engine.canWriteCalendar(acc)
        ? (title == acc.email ? null : acc.email)
        : l10n.tr('eventCalendarPhoneOnly').replaceAll('{email}', acc.email);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
      // Значок цвета ящика — как метки ящиков в ленте и календаре.
      leading: Icon(AppIcons.calendar_month, color: Color(acc.colorValue)),
      title: TitleWithHelp(title, hint: l10n.tr('eventCalendarHelp')),
      subtitle: sub == null ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: pickable ? const Icon(AppIcons.arrow_drop_down) : null,
      onTap: pickable ? () => unawaited(_pickAccount(l10n)) : null,
    );
  }

  Future<void> _pickAccount(AppLocalizations l10n) async {
    final engine = ref.read(mailEngineServiceProvider);
    final list = _calendarAccounts();
    final picked = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(title: Text(l10n.tr('eventSaveTo'), style: theme.textTheme.titleMedium)),
                for (final a in list)
                  ListTile(
                    leading: Icon(AppIcons.calendar_month, color: Color(a.colorValue)),
                    title: Text(_accountTitle(a), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      engine.canWriteCalendar(a)
                          ? a.email
                          : l10n.tr('eventCalendarPhoneOnly').replaceAll('{email}', a.email),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: a.id == _account?.id ? Icon(AppIcons.check, color: theme.colorScheme.primary) : null,
                    onTap: () => Navigator.pop(ctx, a.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted || picked == _accountId) return;
    setState(() {
      _accountId = picked;
      // Переговорные и занятость — у другого сервера; участники остаются.
      _roomEmails.clear();
    });
  }

  /// Exchange хранит одно напоминание: под списком — какое уйдёт на сервер.
  String? _reminderNote(AppLocalizations l10n) {
    final acc = _account;
    if (acc == null || _reminders.length < 2) return null;
    final engine = ref.read(mailEngineServiceProvider);
    if (!engine.canWriteCalendar(acc) || engine.keepsManyReminders(acc)) return null;
    final first = EventReminders.normalize(_reminders).first;
    return l10n.tr('reminderExchangeOne').replaceAll('{first}', reminderLabel(first, l10n));
  }

  /// remindersJson встречи ящика [account] (см. EventReminders.encode).
  String _remindersJsonFor(AccountModel? account) {
    final engine = ref.read(mailEngineServiceProvider);
    final keepsAll = account == null || !engine.canWriteCalendar(account) || engine.keepsManyReminders(account);
    return EventReminders.encode(_reminders, serverKeepsAll: keepsAll);
  }

  // ── Пересечения с назначенными встречами (1.6.49) ──

  List<CalendarEvent> _conflicts = const [];
  Timer? _conflictTimer;
  (DateTime, DateTime, bool)? _conflictKey;

  /// Время поменялось — через 0,3 с пересчитать пересечения (из базы).
  void _watchConflicts() {
    final key = (_startDate, _endDate, _isAllDay);
    if (key == _conflictKey) return;
    _conflictKey = key;
    _conflictTimer?.cancel();
    _conflictTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      if (_isAllDay) {
        if (_conflicts.isNotEmpty) setState(() => _conflicts = const []);
        return;
      }
      final ids = {for (final a in ref.read(accountsProvider)) if (!a.isSharedMailbox) a.id};
      try {
        final list = await eventConflicts(ref.read(databaseProvider),
            start: _startDate, end: _endDate, accountIds: ids, excludeId: widget.editEvent?.id);
        if (mounted && _conflictKey == key) setState(() => _conflicts = list);
      } catch (e) {
        AppLogger.debug('Пересечения встречи: $e');
      }
    });
  }

  /// Адреса переговорных среди участников — значок комнаты вместо фото.
  final Set<String> _roomEmails = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _watchConflicts();
    ref.watch(accountsProvider); // ящики поменялись — строка «Календарь» тоже
    final roomsPossible = _account?.isMsExchange == true;
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    const rowPad = EdgeInsets.symmetric(horizontal: Space.l);

    // Поле — строкой в белой карточке, без серой заливки (как в правке
    // контакта, 1.7.2+106); фокус — тонкой линией акцента под полем.
    Widget field(TextEditingController c, String? label, IconData icon,
            {String? hint,
            String? error,
            TextInputType? type,
            bool multiline = false,
            Widget? suffix,
            ValueChanged<String>? onChanged,
            TextCapitalization cap = TextCapitalization.sentences}) =>
        Padding(
          padding: EdgeInsets.fromLTRB(Space.l, Space.xs, suffix == null ? Space.l : Space.xs, Space.xs),
          child: Row(
            crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: multiline ? Space.m : 0),
                child: Icon(icon, color: muted),
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: TextField(
                  controller: c,
                  keyboardType: multiline ? TextInputType.multiline : type,
                  textCapitalization: cap,
                  minLines: multiline ? 3 : 1,
                  maxLines: multiline ? 10 : 1,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    errorText: error,
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
                    focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(vertical: Space.s),
                  ),
                ),
              ),
              if (suffix != null) suffix,
            ],
          ),
        );

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr(widget.editEvent != null ? 'editMeeting' : 'createMeeting')),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )),
      // Форма — строками в белых карточках по разделам, как настройки,
      // правка контакта и карточка встречи (1.7.2+110, замечание владельца
      // 24.10.2026: «экраны создать встречу и задачу сильно отличаются —
      // сплошные серые»). Поля — без серой заливки, фокус — тонкой линией.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xxl),
        children: [
          // Название
          SettingsGroup(dividerIndent: Space.l, children: [
            field(_titleController, l10n.tr('meetingTitle'), AppIcons.title,
                hint: l10n.tr('meetingTitleHint'),
                // Всплывающие сообщения отключены — ошибка у самого поля.
                error: _titleError,
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                }),
          ]),
          // В календарь какого ящика (1.7.2+110).
          SettingsSectionTitle(l10n.calendarLabel),
          SettingsGroup(children: [_calendarRow(l10n)]),

          // Разделы (1.6.2, замечание 13.10.2026: «непонятно, что за что
          // отвечает»): когда — время, повтор и напоминания вместе; где;
          // участники; дополнительно; описание.
          SettingsSectionTitle(l10n.tr('eventWhen')),
          SettingsGroup(children: [
            SwitchListTile(
              contentPadding: rowPad,
              secondary: Icon(AppIcons.today, color: muted),
              title: Text(l10n.tr('allDay')),
              value: _isAllDay,
              onChanged: (v) => setState(() => _isAllDay = v),
            ),
            ListTile(
              contentPadding: rowPad,
              leading: Icon(AppIcons.schedule, color: muted),
              title: Text(l10n.tr('start')),
              subtitle: Text(
                _isAllDay
                    ? DateFormat('EEEE, d MMMM yyyy', l10n.localeCode).format(_startDate)
                    : DateFormat('EEEE, d MMMM yyyy, HH:mm', l10n.localeCode).format(_startDate),
              ),
              onTap: () => _pickDateTime(true),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: rowPad,
                  leading: Icon(AppIcons.schedule, color: muted),
                  title: Text(l10n.tr('end')),
                  subtitle: Text(
                    (_isAllDay
                            ? DateFormat('EEEE, d MMMM yyyy', l10n.localeCode).format(_endDate)
                            : '${DateFormat('EEEE, d MMMM yyyy, HH:mm', l10n.localeCode).format(_endDate)}'
                                '${_durationText(l10n)}') +
                        (_endBeforeStart ? '\n${l10n.tr('endBeforeStart')}' : ''),
                    style: _endBeforeStart ? TextStyle(color: theme.colorScheme.error) : null,
                  ),
                  onTap: () => _pickDateTime(false),
                ),
                // Длительность одним касанием (1.6.49): конец = начало + N.
                if (!_isAllDay) _durationChips(l10n),
                // «Пересекается: …» — уже назначенные встречи в это время.
                if (_conflicts.isNotEmpty && !_isAllDay) _conflictLine(l10n),
              ],
            ),
            ListTile(
              contentPadding: rowPad,
              leading: Icon(AppIcons.repeat, color: muted),
              title: Text(l10n.tr('repeat')),
              trailing: DropdownButton<RecurrenceType>(
                value: _recurrence,
                underline: const SizedBox.shrink(),
                items: RecurrenceType.values.map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text(_recurrenceLabel(r, l10n)),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _recurrence = v!),
              ),
            ),
            // Напоминания — несколько (1.7.2+110): строками, «×» убирает,
            // «Добавить напоминание» — ещё одно.
            ReminderListEditor(
              value: _reminders,
              onChanged: (v) => setState(() => _reminders = v),
              note: _reminderNote(l10n),
              contentPadding: rowPad,
            ),
          ]),

          SettingsSectionTitle(l10n.tr('eventWhere')),
          SettingsGroup(children: [
            field(_locationController, l10n.tr('location'), AppIcons.location_on,
                hint: l10n.tr('locationHint'),
                // Переговорная из списка организации (1.6.49).
                suffix: roomsPossible
                    ? IconButton(
                        tooltip: l10n.tr('roomPickTitle'),
                        icon: Icon(AppIcons.meeting_room, color: muted),
                        onPressed: () => unawaited(_pickRoom()),
                      )
                    : null),
            field(_onlineLinkController, l10n.tr('onlineMeetingLink'), AppIcons.videocam,
                hint: 'https://...', type: TextInputType.url, cap: TextCapitalization.none),
          ]),

          // Участники (1.7.2+110 — сразу в форме, без выбора «Собрание»):
          // нет участников — встреча только в вашем календаре, есть —
          // приглашение, ответы, предложение другого времени.
          if (_canInvite) ...[
            SettingsSectionTitle('${l10n.tr('participants')}${_attendees.isEmpty ? '' : ' · ${_attendees.length}'}'),
            SettingsGroup(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.s,
                      runSpacing: Space.xs,
                      children: [
                        // Фото участников (1.6.49), у переговорной — значок комнаты.
                        ..._attendees.map((a) => Chip(
                              avatar: _roomEmails.contains(a.email.toLowerCase())
                                  ? const Icon(AppIcons.meeting_room, size: Sizes.iconInline)
                                  : HeroEmailAvatar(
                                      emailId: 'att_${a.email}',
                                      hero: false,
                                      initial: initialOf(a.displayName ?? a.email),
                                      color: HeroEmailAvatar.colorForEmail(a.email),
                                      email: a.email,
                                      radius: 12,
                                    ),
                              label: Text(a.displayName ?? a.email),
                              onDeleted: () {
                                setState(() => _attendees.remove(a));
                              },
                            )),
                        ActionChip(
                          avatar: const Icon(AppIcons.add, size: 18),
                          label: Text(l10n.tr('add')),
                          onPressed: _addAttendee,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text(l10n.tr(_isMeeting ? 'eventKindMeetingHint' : 'eventInviteHint'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    ),
                    if (_attendees.isNotEmpty && _account != null && TransportCapabilities.forAccount(_account!).freeBusy)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Wrap(
                          spacing: Space.s,
                          children: [
                            TextButton.icon(
                              onPressed: _checkAvailability,
                              icon: const Icon(AppIcons.event_busy, size: 18),
                              label: Text(l10n.tr('checkAvailability')),
                            ),
                            TextButton.icon(
                              onPressed: _findFreeSlot,
                              icon: const Icon(AppIcons.event_available, size: 18),
                              label: Text(l10n.tr('findFreeSlot')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Параметры собрания — как флажки Outlook «Параметры ответа».
              if (widget.editEvent == null && _isMeeting) ...[
                SwitchListTile(
                  contentPadding: rowPad,
                  title: Text(l10n.tr('meetingRequestResponses')),
                  subtitle: Text(l10n.tr('meetingRequestResponsesHint')),
                  value: _responseRequested,
                  onChanged: (v) => setState(() => _responseRequested = v),
                ),
                SwitchListTile(
                  contentPadding: rowPad,
                  title: Text(l10n.tr('meetingAllowNewTime')),
                  value: _allowNewTime,
                  onChanged: (v) => setState(() => _allowNewTime = v),
                ),
              ],
            ]),
          ],

          SettingsSectionTitle(l10n.tr('eventMore')),
          SettingsGroup(children: [
            // Приоритет — подписью и переключателем во всю ширину: в строке
            // справа три кнопки сжимались и подписи обрезались.
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(AppIcons.flag, color: muted),
                    const SizedBox(width: Space.l),
                    Text(l10n.tr('priority'), style: theme.textTheme.bodyLarge),
                  ]),
                  const SizedBox(height: Space.s),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<EventPriority>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: EventPriority.low, label: Text(l10n.tr('priorityLow'))),
                        ButtonSegment(value: EventPriority.normal, label: Text(l10n.tr('priorityNormal'))),
                        ButtonSegment(value: EventPriority.high, label: Text(l10n.tr('priorityHigh'))),
                      ],
                      selected: {_priority},
                      onSelectionChanged: (v) => setState(() => _priority = v.first),
                    ),
                  ),
                ],
              ),
            ),
            // Приватность
            SwitchListTile(
              contentPadding: rowPad,
              secondary: Icon(AppIcons.lock, color: muted),
              title: Text(l10n.tr('privateMeeting')),
              subtitle: Text(l10n.tr('privateMeetingHint')),
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
            // Цвет — категорией Outlook (1.6.5): если с сервера получен
            // главный список категорий ящика — его категории с именами
            // («Лиловая категория», «Праздники»), иначе стандартные цвета.
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(AppIcons.palette, color: muted),
                    const SizedBox(width: Space.l),
                    Text(l10n.tr('eventCategory'), style: theme.textTheme.bodyLarge),
                  ]),
                  const SizedBox(height: Space.s),
                  Padding(
                    padding: const EdgeInsets.only(left: Sizes.icon + Space.l),
                    child: Wrap(
                      spacing: Space.s,
                      runSpacing: Space.s,
                      children: [
                        for (final (name, color) in <(String, Color)>[
                          (l10n.tr('eventNoCategory'), AppColors.primaryBlue),
                          if (CategoryColors.serverList.isNotEmpty)
                            for (final c in CategoryColors.serverList) (c.name, c.color)
                          else
                            for (final p in CategoryColors.presets)
                              (l10n.isRussian ? p.ru : p.en, p.color),
                        ])
                          ChoiceChip(
                            avatar: CircleAvatar(backgroundColor: color, radius: 8),
                            label: Text(name),
                            selected: _selectedColor == color.toARGB32(),
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _selectedColor = color.toARGB32()),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ]),

          SettingsSectionTitle(l10n.tr('description')),
          SettingsGroup(children: [
            field(_descriptionController, null, AppIcons.notes, hint: l10n.tr('description'), multiline: true),
          ]),

          // Вложения письма, из которого создаётся встреча (1.6.12, как
          // «Собрание» из письма в Outlook): уходят вместе с приглашением.
          if (widget.editEvent == null && _emailFiles.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            SettingsGroup(children: [
              SwitchListTile(
                contentPadding: rowPad,
                secondary: Icon(AppIcons.attach_file, color: muted),
                title: Text(l10n.tr('eventAttachEmailFiles').replaceAll('{n}', '${_emailFiles.length}')),
                subtitle: Text(_emailFiles.map((a) => a.name).join(', '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                value: _attachEmailFiles,
                onChanged: (v) => setState(() => _attachEmailFiles = v),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// « · 1 ч 30 мин» — длительность встречи у строки «Конец».
  String _durationText(AppLocalizations l10n) {
    final m = _endDate.difference(_startDate).inMinutes;
    if (m <= 0) return '';
    final t = m < 60
        ? l10n.tr('myDayMinutes').replaceAll('{m}', '$m')
        : m % 60 == 0
            ? '${m ~/ 60} ${l10n.tr('hourShort')}'
            : l10n.tr('myDayHours').replaceAll('{h}', '${m ~/ 60}').replaceAll('{m}', '${m % 60}');
    return ' · $t';
  }

  /// Чипы длительности: 15 мин … 2 ч; выбранный — текущая длительность.
  Widget _durationChips(AppLocalizations l10n) {
    final current = _endDate.difference(_startDate).inMinutes;
    String label(int m) => m < 60
        ? l10n.tr('myDayMinutes').replaceAll('{m}', '$m')
        : m % 60 == 0
            ? '${m ~/ 60} ${l10n.tr('hourShort')}'
            : l10n.tr('myDayHours').replaceAll('{h}', '${m ~/ 60}').replaceAll('{m}', '${m % 60}');
    return Padding(
      // С линии текста строк карточки (поле 16 · значок 24 · 16).
      padding: const EdgeInsets.fromLTRB(Space.l + Sizes.icon + Space.l, 0, Space.l, Space.m),
      child: Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
        for (final m in const [15, 30, 45, 60, 90, 120])
          ChoiceChip(
            label: Text(label(m)),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selected: current == m,
            onSelected: (_) => setState(() => _endDate = _startDate.add(Duration(minutes: m))),
          ),
      ]),
    );
  }

  /// «Пересекается: «Планёрка», 10:00–11:00 и ещё 2».
  Widget _conflictLine(AppLocalizations l10n) {
    final c = _conflicts.first;
    final color = AppColors.accentOrangeText(context);
    final time = '${AppDateFormat.time(context, c.startTime.toLocal())}–${AppDateFormat.time(context, c.endTime.toLocal())}';
    final title = c.title.trim().isEmpty ? l10n.tr('noSubject') : c.title.trim();
    final more = _conflicts.length > 1 ? ' ${l10n.tr('conflictMore').replaceAll('{n}', '${_conflicts.length - 1}')}' : '';
    return Padding(
      // С линии текста строк карточки (поле 16 · значок 24 · 16).
      padding: const EdgeInsets.fromLTRB(Space.l + Sizes.icon + Space.l, 0, Space.l, Space.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(AppIcons.event_busy, size: Sizes.iconInline, color: color),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            l10n.tr('conflictWith').replaceAll('{title}', title).replaceAll('{time}', time) + more,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ]),
    );
  }

  /// Переговорная (1.6.49): из списков организации с занятостью на время
  /// встречи или поиском в адресной книге. Становится местом и участником
  /// (приглашение бронирует комнату), встреча — собранием.
  Future<void> _pickRoom() async {
    final account = _account;
    if (account == null) return;
    final start = _isAllDay ? DateTime(_startDate.year, _startDate.month, _startDate.day) : _startDate;
    final end = _isAllDay ? DateTime(_endDate.year, _endDate.month, _endDate.day + 1) : _endDate;
    final choice = await showRoomPicker(context, account: account, start: start, end: end);
    if (!mounted || choice == null) return;
    final DirectoryRoom room;
    switch (choice) {
      case RoomPicked(room: final r):
        room = r;
      case RoomSearchDirectory():
        final picked = await showPeoplePicker(context, account: account);
        if (picked.isEmpty || !mounted) return;
        final c = picked.first;
        room = DirectoryRoom(name: c.displayName.trim().isNotEmpty ? c.displayName.trim() : c.email, email: c.email.trim());
    }
    setState(() {
      _locationController.text = room.name;
      // Комнату бронирует приглашение: переговорная — участник, и новая
      // встреча становится собранием.
      if (_canInvite && !_attendees.any((a) => a.email.toLowerCase() == room.email.toLowerCase())) {
        _attendees.add(EventAttendee(email: room.email, displayName: room.name, isRequired: true));
        _roomEmails.add(room.email.toLowerCase());
      }
    });
  }

  Future<void> _pickDateTime(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;

    // Барабаны (10.10.2026): дата и время одной шторкой, с днём недели.
    final first = DateTime(2020), last = DateTime(DateTime.now().year + 10);
    final date = _isAllDay
        ? await showWheelDatePicker(context, initial: initial, first: first, last: last)
        : await showWheelDateTimePicker(context, initial: initial, first: first, last: last);

    if (date == null || !mounted) return;

    if (_isAllDay) {
      setState(() {
        if (isStart) {
          _startDate = date;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = date;
        }
      });
      return;
    }

    final dateTime = date;

    setState(() {
      if (isStart) {
        // Сдвиг начала сохраняет длительность (как в Outlook): 30 минут
        // остаются 30 минутами, окончание не надо переставлять вручную.
        final length = _endDate.difference(_startDate);
        _startDate = dateTime;
        _endDate = _startDate.add(length > Duration.zero ? length : defaultMeetingLength);
      } else {
        _endDate = dateTime;
      }
    });
  }

  Future<void> _checkAvailability() async {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final account = _account;
    if (account == null || _attendees.isEmpty) return;
    final emails = _attendees.map((a) => a.email).toList();
    final day = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final start = day.add(const Duration(hours: 8));
    final end = day.add(const Duration(hours: 20));
    unawaited(showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator())));
    try {
      final view = await ref.read(mailEngineServiceProvider).getFreeBusy(
            account, emails: emails, startLocal: start, endLocal: end, intervalMinutes: 30);
      if (mounted) Navigator.of(context).pop();
      if (!mounted) return;
      _showAvailabilitySheet(view, ru);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      // Плашки скрыты (19.10) — ошибка строкой на экране.
      showInlineError('${l10n.error}: $e');
    }
  }

  /// «Найти время» (1.6.7): ближайшие окна текущей длительности, свободные
  /// у всех участников и у себя, в рабочие часы ближайших пяти рабочих дней.
  Future<void> _findFreeSlot() async {
    final l10n = AppLocalizations.of(context);
    final account = _account;
    if (account == null || _attendees.isEmpty) return;
    final length = _endDate.difference(_startDate);
    final duration = length.inMinutes <= 0 ? const Duration(minutes: 30) : length;
    final emails = {account.email.trim().toLowerCase(), ..._attendees.map((a) => a.email.trim().toLowerCase())}
        .where((e) => e.isNotEmpty)
        .toList();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    var workDays = 0;
    var last = day;
    while (workDays < 5) {
      if (last.weekday <= DateTime.friday) workDays++;
      if (workDays < 5) last = DateTime(last.year, last.month, last.day + 1);
    }
    final start = day.add(const Duration(hours: 8));
    final end = DateTime(last.year, last.month, last.day, 18);
    unawaited(showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator())));
    try {
      final view = await ref.read(mailEngineServiceProvider).getFreeBusy(
            account, emails: emails, startLocal: start, endLocal: end, intervalMinutes: 30);
      if (mounted) Navigator.of(context).pop();
      if (!mounted) return;
      // Ближайший шаг 30 минут после «сейчас».
      final soon = now.add(Duration(minutes: 30 - now.minute % 30));
      final slots = view.freeSlots(duration, notBefore: soon);
      _showFreeSlots(view.isEmpty, slots, duration);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      showInlineError('${l10n.error}: $e');
    }
  }

  void _showFreeSlots(bool noData, List<DateTime> slots, Duration length) {
    final l10n = AppLocalizations.of(context);
    final dayFmt = DateFormat('EEE, d MMMM', l10n.localeCode);
    final t = DateFormat.Hm();
    showAppSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.tr('findFreeSlot'), style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: Space.xs),
              Text(l10n.tr('freeSlotsHint'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(ctx))),
              const SizedBox(height: Space.s),
              if (noData)
                Text(l10n.tr('noAvailabilityData'))
              else if (slots.isEmpty)
                Text(l10n.tr('noFreeSlots'))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in slots)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(AppIcons.event_available, color: AppColors.successGreen),
                          title: Text('${t.format(s)} – ${t.format(s.add(length))}'),
                          subtitle: Text(dayFmt.format(s)),
                          onTap: () {
                            setState(() {
                              _startDate = s;
                              _endDate = s.add(length);
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAvailabilitySheet(FreeBusyView view, bool ru) {
    final l10n = AppLocalizations.of(context);
    final windows = view.busyWindows();
    final df = DateFormat.Hm();
    showAppSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.tr('attendeeAvailability'),
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: Space.s),
              if (!view.isEmpty) ...[
                _availabilityStrip(view, ru),
                const SizedBox(height: Space.m),
              ],
              if (view.isEmpty)
                Text(l10n.tr('noAvailabilityData'))
              else if (windows.isEmpty)
                Text(l10n.tr('everyoneFree'))
              else ...[
                Text(l10n.tr('busyIntervals'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: Space.xs),
                ...windows.map((w) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        const Icon(AppIcons.event_busy, size: 16, color: AppColors.errorRed),
                        const SizedBox(width: Space.s),
                        Text('${df.format(w.start)} – ${df.format(w.end)}'),
                      ]),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Цветная полоса занятости на весь запрошенный день + метки времени и легенда.
  Widget _availabilityStrip(FreeBusyView view, bool ru) {
    final l10n = AppLocalizations.of(context);
    final df = DateFormat.Hm();
    final endTime = view.startLocal.add(Duration(minutes: view.statuses.length * view.intervalMinutes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 20,
            child: Row(
              children: [
                for (final s in view.statuses) Expanded(child: ColoredBox(color: _statusColor(s))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(df.format(view.startLocal),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText(context))),
            Text(df.format(endTime),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.mutedText(context))),
          ],
        ),
        const SizedBox(height: Space.s),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _legendDot(_statusColor(0), l10n.tr('freeStatus')),
          _legendDot(_statusColor(2), l10n.tr('busyStatus')),
          _legendDot(_statusColor(1), l10n.tr('tentativeStatus')),
        ]),
      ],
    );
  }

  Color _statusColor(int status) {
    switch (status) {
      case 0: return AppColors.successGreen.withValues(alpha: 0.5); // свободен
      case 1: return AppColors.accentOrange;                  // под вопросом
      case 2: return AppColors.errorRed;                      // занят
      case 3: return AppColors.tagMaintenance;                // нет на месте
      default: return Theme.of(context).colorScheme.outlineVariant; // нет данных
    }
  }

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: Space.xs),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );

  /// Добавить участников: поиск по контактам и адресной книге организации,
  /// «Моё подразделение», ввод адреса вручную (раньше — только адрес).
  Future<void> _addAttendee() async {
    final account = _account;
    final picked = await showPeoplePicker(
      context,
      account: account,
      exclude: {for (final a in _attendees) a.email.toLowerCase()},
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final c in picked) {
        if (_attendees.any((a) => a.email.toLowerCase() == c.email.toLowerCase())) continue;
        _attendees.add(EventAttendee(
          email: c.email.trim(),
          displayName: c.displayName.isNotEmpty && c.displayName != c.email ? c.displayName : null,
          isRequired: true,
        ));
      }
    });
    _fillAttendeeNames();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = l10n.tr('enterMeetingTitle'));
      return;
    }
    // Подпись у строки «Окончание» уже красная — не отправляем.
    if (_endBeforeStart) {
      setState(() {});
      return;
    }

    setState(() => _isSaving = true);

    if (widget.editEvent != null) {
      await _saveEdit(l10n, widget.editEvent!);
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    try {
      // Ящик из строки «Календарь» (копия встречи — по умолчанию её ящик).
      final account = _account ?? ref.read(activeAccountProvider);
      if (account == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      final event = CalendarEventModel(
        id: const Uuid().v4(),
        accountId: account.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        onlineMeetingUrl: _onlineLinkController.text.trim().isNotEmpty
            ? _onlineLinkController.text.trim()
            : null,
        // Событие на весь день: от полуночи первого дня до полуночи после
        // последнего (как хранит Exchange). Раньше уходило время из полей —
        // и событие «на день» оказывалось 10:00–10:00 того же дня.
        startTime: _isAllDay
            ? DateTime(_startDate.year, _startDate.month, _startDate.day)
            : _startDate,
        endTime: _isAllDay
            ? DateTime(_endDate.year, _endDate.month, _endDate.day + 1)
            : _endDate,
        isAllDay: _isAllDay,
        attendees: _attendees,
        organizerEmail: account.email,
        recurrence: _recurrence,
        priority: _priority,
        colorValue: _selectedColor,
        isPrivate: _isPrivate,
        reminders: [for (final m in EventReminders.normalize(_reminders)) EventReminder(minutesBefore: m)],
        linkedEmailId: widget.sourceEmail?.id,
        responseRequested: _responseRequested,
        allowNewTimeProposal: _allowNewTime,
        createdAt: DateTime.now(),
      );

      // Сохраняем на сервере (Exchange: EWS или ActiveSync). id в базе — тот,
      // под которым событие придёт при синхронизации; иначе после синка
      // появлялся дубль (локальный uuid + серверная копия).
      String localId = event.id;
      var serverCreated = false;
      // Exchange (EWS/ActiveSync) и CalDAV (Google, Яндекс, Mail.ru, Yahoo).
      if (ref.read(mailEngineServiceProvider).canWriteCalendar(account)) {
        final collected = await _collectEmailFiles();
        if (collected.failed.isNotEmpty) {
          // Часть файлов письма не скачалась (нет связи с сервером):
          // спрашиваем, а не создаём встречу молча без них.
          if (!mounted) return;
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(AppIcons.warning),
              title: Text(l10n.tr('eventFilesFailedTitle')),
              content: Text(l10n.tr('eventFilesFailedBody')
                  .replaceAll('{files}', collected.failed.take(3).join(', '))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('eventCreateWithout'))),
              ],
            ),
          );
          if (go != true) return; // встреча не создана; можно повторить «Сохранить»
        }
        final files = collected.files;
        final r = await ref.read(mailEngineServiceProvider).createEvent(account, event, attachments: files);
        serverCreated = r.created;
        if (r.id != null) {
          localId = r.id!;
        } else if (r.created) {
          // id заранее неизвестен (встреча создана через EWS-спутник) —
          // событие придёт ближайшей синхронизацией.
          unawaited(ref.read(syncServiceProvider).syncAll());
        } else {
          // Сервер не принял событие — сохраняем локально, чтобы оно не
          // пропало (раньше в этом случае оно терялось совсем).
          AppLogger.warning('createEvent: сервер не создал событие — сохранено локально');
        }
        if (r.created && event.recurrence != RecurrenceType.none) {
          unawaited(ref.read(syncServiceProvider).syncAll());
        }
      }

      // Сохраняем в локальную БД, чтобы событие сразу появилось в списке
      final db = ref.read(databaseProvider);
      if (serverCreated && localId == event.id) {
        // Локальную копию не пишем: её заменит синхронизация.
        ref.invalidate(calendarEventsProvider);
        if (mounted) {
          AppLogger.info(l10n.tr('meetingCreated'));
          Navigator.of(context).pop();
        }
        return;
      }
      await db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          id: localId,
          accountId: event.accountId,
          title: event.title,
          description: Value(event.description),
          location: Value(event.location),
          onlineMeetingUrl: Value(event.onlineMeetingUrl),
          startTime: event.startTime,
          endTime: event.endTime,
          isAllDay: Value(event.isAllDay),
          organizerEmail: Value(event.organizerEmail),
          recurrence: Value(event.recurrence.index),
          priority: Value(event.priority.index),
          colorValue: Value(event.colorValue),
          isPrivate: Value(event.isPrivate),
          // Напоминания: колонка была, но в неё никто не писал — из-за этого
          // выбранное «за 15 минут» терялось и уведомление не приходило.
          // Несколько (1.7.2+110): у Exchange на сервере — ближайшее,
          // остальные помечены «только телефон»; пусто — явно без них.
          remindersJson: Value(_remindersJsonFor(account)),
          createdAt: event.createdAt,
        ),
        mode: InsertMode.insertOrReplace,
      );
      ref.invalidate(calendarEventsProvider);
      // Уведомление планируется в ОС заранее — перевыставляем после правки.

      await ref.read(reminderSchedulerProvider).rescheduleAll();

      unawaited(HapticFeedback.mediumImpact());

      if (mounted) {
        AppLogger.info(l10n.tr('meetingCreated'));
        // true — встреча создана (карточка бронирования отмечает «Добавлено»).
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      // Плашки в приложении скрыты — ошибка строкой вверху экрана (раньше
      // «не сохранилось» уходило в невидимую плашку).
      if (mounted) showInlineError(_saveErrorText(e, l10n));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Сохранить правку встречи: на сервере (ActiveSync — Change, EWS —
  /// UpdateItem с рассылкой участникам) и в локальной базе. Раньше
  /// изменить встречу в приложении было нельзя — только удалить.
  Future<void> _saveEdit(AppLocalizations l10n, CalendarEvent old) async {
    final account = ref.read(accountsProvider).where((a) => a.id == old.accountId).firstOrNull;
    final start = _isAllDay ? DateTime(_startDate.year, _startDate.month, _startDate.day) : _startDate;
    final end = _isAllDay ? DateTime(_endDate.year, _endDate.month, _endDate.day + 1) : _endDate;
    final event = CalendarEventModel(
      id: old.id,
      accountId: old.accountId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      onlineMeetingUrl: _onlineLinkController.text.trim().isEmpty ? null : _onlineLinkController.text.trim(),
      startTime: start,
      endTime: end,
      isAllDay: _isAllDay,
      attendees: _attendees,
      organizerEmail: old.organizerEmail,
      recurrence: _recurrence,
      priority: _priority,
      colorValue: _selectedColor,
      isPrivate: _isPrivate,
      reminders: [for (final m in EventReminders.normalize(_reminders)) EventReminder(minutesBefore: m)],
      createdAt: old.createdAt,
    );
    final engine = ref.read(mailEngineServiceProvider);
    var wholeSeries = false;
    var onlyChanged = false;
    // 1.6.7: как в Outlook — у вхождения серии спросить, менять его одно или
    // всю серию; при изменении состава участников — кому слать обновление.
    if (account != null && engine.canManageMeetings(account)) {
      bool inSeries;
      try {
        inSeries = await engine.isSeriesOccurrence(account, old.id, old.recurrence);
      } catch (_) {
        inSeries = MailEngineService.isOccurrenceId(old.id);
      }
      if (inSeries) {
        if (!mounted) return;
        final c = await CalendarEventActions.askSeriesScope(context, delete: false);
        if (c == null) return;
        wholeSeries = c;
      }
      final now = {for (final a in _attendees) a.email.trim().toLowerCase()};
      final changed = now.length != _originalAttendees.length || !now.containsAll(_originalAttendees);
      if (changed && _originalAttendees.isNotEmpty && now.isNotEmpty) {
        if (!mounted) return;
        final c = await CalendarEventActions.askUpdateRecipients(context);
        if (c == null) return;
        onlyChanged = c;
      }
    }
    try {
      if (account != null) {
        await engine.updateEvent(account, event,
            onlyChanged: onlyChanged,
            wholeSeries: wholeSeries,
            original: (start: old.startTime, end: old.endTime, title: old.title));
      }
      if (wholeSeries) unawaited(ref.read(syncServiceProvider).syncAll());
      final db = ref.read(databaseProvider);
      await (db.update(db.calendarEvents)
            ..where((t) => t.id.equals(old.id) & t.accountId.equals(old.accountId)))
          .write(CalendarEventsCompanion(
        title: Value(event.title),
        description: Value(event.description),
        location: Value(event.location),
        onlineMeetingUrl: Value(event.onlineMeetingUrl),
        startTime: Value(event.startTime),
        endTime: Value(event.endTime),
        isAllDay: Value(event.isAllDay),
        priority: Value(event.priority.index),
        colorValue: Value(event.colorValue),
        isPrivate: Value(event.isPrivate),
        remindersJson: Value(_remindersJsonFor(account)),
      ));
      ref.invalidate(calendarEventsProvider);
      await ref.read(reminderSchedulerProvider).rescheduleAll();
      unawaited(HapticFeedback.mediumImpact());
      if (mounted) {
        AppLogger.info(l10n.tr('meetingUpdated'));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showInlineError(e is UnsupportedError ? '${e.message}' : _saveErrorText(e, l10n));
    }
  }

  /// Понятный текст отказа сервера вместо «Bad state: EAS Sync (Calendar)
  /// элемент: Status=6» (1.6.4). Код остаётся в журнале.
  String _saveErrorText(Object e, AppLocalizations l10n) {
    final code = RegExp(r'элемент: Status=(\d+)').firstMatch('$e')?.group(1);
    if (code != null) {
      AppLogger.warning('Встреча: сервер отверг, Status=$code ($e)');
      return l10n.tr('eventRejectedByServer').replaceAll('{code}', code);
    }
    return '${l10n.tr('error')}: $e';
  }

  String _recurrenceLabel(RecurrenceType type, AppLocalizations l10n) {
    switch (type) {
      case RecurrenceType.none:
        return l10n.tr('none');
      case RecurrenceType.daily:
        return l10n.tr('recurDaily');
      case RecurrenceType.weekly:
        return l10n.tr('recurWeekly');
      case RecurrenceType.biweekly:
        return l10n.tr('recurBiweekly');
      case RecurrenceType.monthly:
        return l10n.tr('recurMonthly');
      case RecurrenceType.yearly:
        return l10n.tr('recurYearly');
    }
  }
}

/// Длительность новой встречи по умолчанию (1.6.8).
const defaultMeetingLength = Duration(minutes: 30);

/// Ближайшие :00 или :30 не раньше [t] (секунды отбрасываются): 19:48 → 20:00,
/// 20:00 → 20:00, 20:01 → 20:30.
DateTime nextHalfHour(DateTime t) {
  final base = DateTime(t.year, t.month, t.day, t.hour);
  final m = t.minute + (t.second > 0 || t.millisecond > 0 ? 1 : 0);
  if (m == 0) return base;
  if (m <= 30) return base.add(const Duration(minutes: 30));
  return base.add(const Duration(hours: 1));
}
