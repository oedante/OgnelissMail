// lib/features/mail/screens/attachment_hub_screen.dart
// Файлы — все вложения из писем всех ящиков: «найти документ» быстро.
//
// Поиск — по имени файла, теме письма и отправителю (несколько слов — все
// сразу). Вкладки по типу; период; порядок (новые, крупные, по имени);
// «Без повторов» — один и тот же файл (имя и размер) из цепочки ответов
// показывается один раз, из самого нового письма, с числом писем; «Все
// файлы отправителя» — из карточки письма и из меню файла. Сверху — недавно
// открытые. Группы по месяцам — серыми полосами.
//
// Список строится из лёгкой выборки (без тел писем), разбор JSON вложений —
// в отдельном изоляте, если писем много.

import '../../../core/platform/download_saver.dart';
import '../../../core/platform/file_opener.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/app_router.dart' show mailDetailPath;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/theme/tokens.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/file_type_icon.dart';
import '../../../widgets/ui/help_hint.dart';
import '../../../widgets/ui/section_band.dart';
import '../../mail/providers/mail_providers.dart';
import 'attachment_preview_screen.dart';

/// Модель вложения в хабе
class AttachmentHubItem {
  final String attachmentId;
  final String name;
  final String mimeType;
  final int size;
  final String emailId;
  final String emailSubject;
  final String senderName;
  final String senderEmail;
  final DateTime receivedAt;
  final String accountId;

  /// В скольких письмах встречается этот файл (имя и размер) — для
  /// «Без повторов»; 1 — только в этом.
  final int copies;

  const AttachmentHubItem({
    required this.attachmentId,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.emailId,
    required this.emailSubject,
    required this.senderName,
    this.senderEmail = '',
    required this.receivedAt,
    required this.accountId,
    this.copies = 1,
  });

  AttachmentHubItem withCopies(int n) => AttachmentHubItem(
        attachmentId: attachmentId,
        name: name,
        mimeType: mimeType,
        size: size,
        emailId: emailId,
        emailSubject: emailSubject,
        senderName: senderName,
        senderEmail: senderEmail,
        receivedAt: receivedAt,
        accountId: accountId,
        copies: n,
      );

  /// Тип по имени и MIME (общий с карточкой письма).
  String get category => FileTypeStyle.categoryOf(mimeType, name);

  /// Вкладка хаба: презентации и текст — к документам, приглашения — к прочему.
  String get tab => switch (category) {
        'presentation' || 'text' => 'document',
        'calendar' => 'other',
        final c => c,
      };

  /// Один и тот же файл в разных письмах (цепочка ответов, копии Gmail).
  String get fileKey => size > 0 ? '${name.toLowerCase()}|$size' : '$accountId|$emailId|$attachmentId';

  /// Ключ этого вложения в этом письме.
  String get key => '$accountId|$emailId|$attachmentId';

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Строка выборки для разбора вне UI-изолята (только переносимые типы).
typedef _HubRow = ({
  String id,
  String accountId,
  String subject,
  String? fromName,
  String fromEmail,
  DateTime receivedAt,
  String json,
});

List<AttachmentHubItem> _parseRows(List<_HubRow> rows) {
  final items = <AttachmentHubItem>[];
  for (final row in rows) {
    try {
      final list = jsonDecode(row.json) as List;
      for (final att in list) {
        final m = att as Map<String, dynamic>;
        // Картинки в тексте (логотипы подписей «image001.png») — не файлы.
        if (m['isInline'] == true ||
            ((m['contentId'] as String? ?? '').isNotEmpty &&
                (m['mimeType'] as String? ?? '').startsWith('image/'))) {
          continue;
        }
        items.add(AttachmentHubItem(
          attachmentId: m['id'] as String? ?? '',
          name: m['name'] as String? ?? 'file',
          mimeType: m['mimeType'] as String? ?? 'application/octet-stream',
          size: (m['size'] as num?)?.toInt() ?? 0,
          emailId: row.id,
          emailSubject: row.subject,
          senderName: (row.fromName ?? '').trim().isEmpty ? row.fromEmail : row.fromName!.trim(),
          senderEmail: row.fromEmail.trim().toLowerCase(),
          receivedAt: row.receivedAt,
          accountId: row.accountId,
        ));
      }
    } catch (_) {}
  }
  return items;
}

/// Ящики, скрытые в «Файлах» (как в календаре: строка ящиков сверху,
/// нажатие — показать/скрыть, долгое — только этот).
class _HiddenFilesAccounts extends StateNotifier<Set<String>> {
  final Ref _ref;
  _HiddenFilesAccounts(this._ref)
      : super({...?_ref.read(sharedPrefsProvider).getStringList('files_hidden_accounts')});

  void set(Set<String> ids) {
    state = {...ids};
    _ref.read(sharedPrefsProvider).setStringList('files_hidden_accounts', state.toList());
  }

  void toggle(String id) => set(state.contains(id) ? ({...state}..remove(id)) : {...state, id});
}

final filesHiddenAccountsProvider =
    StateNotifierProvider<_HiddenFilesAccounts, Set<String>>((ref) => _HiddenFilesAccounts(ref));

/// Сколько последних писем с вложениями просматривать.
const _kHubEmailLimit = 3000;

/// Письма изменились (новые, удалённые, перемещённые) — не чаще раза в
/// 2 секунды после серии изменений: синхронизация пишет письма пачками.
final _hubEmailsTickProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  var n = 0;
  Timer? t;
  final c = StreamController<int>();
  final sub = db.tableUpdates(TableUpdateQuery.onAllTables([db.emails])).listen((_) {
    t?.cancel();
    t = Timer(const Duration(seconds: 2), () => c.add(++n));
  });
  ref.onDispose(() {
    t?.cancel();
    sub.cancel();
    c.close();
  });
  return c.stream;
});

/// Провайдер вложений из БД (все, по убыванию даты письма). Перечитывается
/// при изменении писем и при каждом открытии экрана (1.8.0: раньше список
/// собирался один раз за запуск — новые файлы и удалённые письма не
/// отражались до перезапуска).
final attachmentHubProvider = FutureProvider.autoDispose<List<AttachmentHubItem>>((ref) async {
  ref.watch(_hubEmailsTickProvider);
  final db = ref.watch(databaseProvider);
  final accounts = ref.watch(accountsProvider);
  final hidden = ref.watch(filesHiddenAccountsProvider);
  final activeIds = accounts.where((a) => a.isActive && !hidden.contains(a.id)).map((a) => a.id).toList();

  if (activeIds.isEmpty) return [];

  // Только нужные колонки: прежде читались письма целиком (с HTML),
  // поэтому и предел был 500 писем.
  final e = db.emails;
  final q = db.selectOnly(e)
    ..addColumns([e.id, e.accountId, e.subject, e.fromName, e.fromEmail, e.receivedAt, e.attachmentsJson])
    // Свои черновики и Исходящие — не здесь: их файлы ещё не на сервере
    // (1.7.2+111, черновики хранят файлы).
    ..where(e.accountId.isIn(activeIds) &
        e.hasAttachments.equals(true) &
        e.attachmentsJson.isNotNull() &
        e.folderId.isNotIn(const ['drafts', 'outbox']))
    ..orderBy([OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
    ..limit(_kHubEmailLimit);
  final rows = <_HubRow>[
    for (final r in await q.get())
      if ((r.read(e.attachmentsJson) ?? '').length > 2)
        (
          id: r.read(e.id)!,
          accountId: r.read(e.accountId)!,
          subject: r.read(e.subject) ?? '',
          fromName: r.read(e.fromName),
          fromEmail: r.read(e.fromEmail) ?? '',
          receivedAt: r.read(e.receivedAt)!,
          json: r.read(e.attachmentsJson)!,
        ),
  ];
  return _parseRowsAsync(rows);
});

/// Разбор в отдельном изоляте, если писем много. Отдельная функция — чтобы
/// замыкание для изолята захватывало только [rows].
Future<List<AttachmentHubItem>> _parseRowsAsync(List<_HubRow> rows) async {
  if (kIsWeb || rows.length < 200) return _parseRows(rows);
  try {
    return await Isolate.run(() => _parseRows(rows));
  } on UnsupportedError {
    return _parseRows(rows);
  }
}

enum _Period { all, week, month, year }

enum _Sort { newest, largest, name }

class AttachmentHubScreen extends ConsumerStatefulWidget {
  /// Показать только файлы этого отправителя (адрес) — «Файлы отправителя»
  /// из карточки письма.
  final String? sender;
  const AttachmentHubScreen({super.key, this.sender});

  @override
  ConsumerState<AttachmentHubScreen> createState() => _AttachmentHubScreenState();
}

class _AttachmentHubScreenState extends ConsumerState<AttachmentHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// Файлы, которые сейчас скачиваются (ключ — письмо и вложение).
  final _busy = <String>{};

  _Period _period = _Period.all;
  _Sort _sort = _Sort.newest;
  bool _dedup = true;

  /// Отбор по отправителю: адрес (строчными) и имя для подписи.
  String? _sender;
  String? _senderName;

  static const _tabs = ['all', 'pdf', 'document', 'spreadsheet', 'image', 'archive', 'other'];
  static const _kRecent = 'files_recent';
  static const _kSort = 'files_sort';
  static const _kDedup = 'files_dedup';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    final prefs = ref.read(sharedPrefsProvider);
    _sort = _Sort.values.elementAtOrNull(prefs.getInt(_kSort) ?? 0) ?? _Sort.newest;
    _dedup = prefs.getBool(_kDedup) ?? true;
    final s = widget.sender?.trim().toLowerCase();
    if (s != null && s.isNotEmpty) _sender = s;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────── действия ───────────────────────────

  /// Файл на телефоне: из кэша или скачать с сервера (как в письме).
  Future<String?> _ensureLocal(AttachmentHubItem item, AppLocalizations l10n) async {
    final cacheKey = MailEngineService.attachmentCacheKey(item.accountId, item.emailId, item.attachmentId);
    final cache = ref.read(attachmentCacheProvider);
    final cached = await cache.get(cacheKey);
    if (cached != null) return cached;
    final account = ref.read(accountsProvider).where((a) => a.id == item.accountId).firstOrNull;
    if (account == null) return null;
    setState(() => _busy.add(item.key));
    try {
      final bytes = await ref
          .read(mailEngineServiceProvider)
          .getAttachmentBytes(account, item.attachmentId, emailId: item.emailId);
      return await cache.put(cacheKey, item.name, bytes);
    } catch (e) {
      showInlineError('${l10n.tr('attachDownloadFailed')}: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy.remove(item.key));
    }
  }

  /// Запомнить открытый файл — для «Недавно открытых».
  void _remember(AttachmentHubItem item) {
    final prefs = ref.read(sharedPrefsProvider);
    final list = [item.key, ...?prefs.getStringList(_kRecent)?.where((k) => k != item.key)];
    unawaited(prefs.setStringList(_kRecent, list.take(8).toList()));
  }

  /// Нажатие: скачать (если нужно) и открыть во внешнем приложении
  /// (1.5.10; письмо — в почте, см. openAttachment).
  Future<void> _open(AttachmentHubItem item, AppLocalizations l10n) async {
    if (_busy.contains(item.key)) return;
    unawaited(HapticFeedback.selectionClick());
    final path = await _ensureLocal(item, l10n);
    if (path == null || !mounted) return;
    _remember(item);
    await openAttachment(
      context,
      PreviewItem(filePath: path, fileName: item.name, sizeBytes: item.size, mimeType: item.mimeType),
      emailSubject: item.emailSubject,
      accountId: item.accountId,
    );
    if (mounted) setState(() {});
  }

  /// Долгое нажатие: письмо, другое приложение, «Поделиться», файлы
  /// отправителя.
  Future<void> _actions(AttachmentHubItem item, AppLocalizations l10n) async {
    unawaited(HapticFeedback.selectionClick());
    final action = await showActionSheet<String>(
      context,
      title: item.name,
      subtitle: '${item.sizeFormatted} · ${item.senderName}',
      leading: FileTypeIcon(category: item.category),
      items: [
        ActionSheetItem(icon: AppIcons.open_in_new, label: l10n.tr('openExternallyApp'), value: 'open'),
        if (DownloadSaver.supported)
          ActionSheetItem(icon: AppIcons.save_alt, label: l10n.tr('saveToDownloads'), value: 'save'),
        ActionSheetItem(
            icon: AppIcons.ios_share,
            label: l10n.tr(DownloadSaver.supported ? 'share' : 'attachShareSave'),
            value: 'share'),
        ActionSheetItem(icon: AppIcons.mail, label: l10n.tr('openEmail'), value: 'mail'),
        if (item.senderEmail.isNotEmpty && _sender != item.senderEmail)
          ActionSheetItem(
              icon: AppIcons.person,
              label: l10n.tr('filesFromSender'),
              subtitle: item.senderName,
              value: 'sender'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'open') return _open(item, l10n);
    if (action == 'mail') {
      unawaited(context.push(mailDetailPath(item.emailId, accountId: item.accountId)));
      return;
    }
    if (action == 'sender') {
      setState(() {
        _sender = item.senderEmail;
        _senderName = item.senderName;
      });
      return;
    }
    final path = await _ensureLocal(item, l10n);
    if (path == null || !mounted) return;
    _remember(item);
    if (action == 'save') {
      await DownloadSaver.saveWithFeedback(context, [(path: path, name: item.name)]);
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(await FileOpener.namedCopy(path, item.name), name: item.name)]));
  }

  Future<void> _pickPeriod(AppLocalizations l10n) async {
    final v = await showActionSheet<_Period>(
      context,
      title: l10n.tr('filesPeriod'),
      items: [
        for (final p in _Period.values)
          ActionSheetItem(
            icon: p == _period ? AppIcons.check : AppIcons.date_range,
            label: _periodLabel(p, l10n),
            value: p,
          ),
      ],
    );
    if (v != null && mounted) setState(() => _period = v);
  }

  Future<void> _pickSort(AppLocalizations l10n) async {
    final v = await showActionSheet<_Sort>(
      context,
      title: l10n.tr('filesSort'),
      items: [
        for (final s in _Sort.values)
          ActionSheetItem(
            icon: s == _sort ? AppIcons.check : AppIcons.sort,
            label: _sortLabel(s, l10n),
            value: s,
          ),
      ],
    );
    if (v == null || !mounted) return;
    setState(() => _sort = v);
    unawaited(ref.read(sharedPrefsProvider).setInt(_kSort, v.index));
  }

  void _toggleDedup() {
    setState(() => _dedup = !_dedup);
    unawaited(ref.read(sharedPrefsProvider).setBool(_kDedup, _dedup));
  }

  static String _periodLabel(_Period p, AppLocalizations l10n) => switch (p) {
        _Period.all => l10n.tr('filesPeriodAll'),
        _Period.week => l10n.tr('filesPeriodWeek'),
        _Period.month => l10n.tr('filesPeriodMonth'),
        _Period.year => l10n.tr('filesPeriodYear'),
      };

  static String _sortLabel(_Sort s, AppLocalizations l10n) => switch (s) {
        _Sort.newest => l10n.tr('filesSortNew'),
        _Sort.largest => l10n.tr('filesSortSize'),
        _Sort.name => l10n.tr('filesSortName'),
      };

  // ─────────────────────────── отбор ───────────────────────────

  bool get _filtersActive => _searchQuery.isNotEmpty || _period != _Period.all || _sender != null;

  /// Поиск, период, отправитель, «без повторов» и порядок.
  List<AttachmentHubItem> _filterItems(List<AttachmentHubItem> items) {
    final words = _searchQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final now = DateTime.now();
    final since = switch (_period) {
      _Period.all => null,
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.year => now.subtract(const Duration(days: 365)),
    };
    var out = items.where((i) {
      if (since != null && i.receivedAt.isBefore(since)) return false;
      if (_sender != null && i.senderEmail != _sender) return false;
      if (words.isEmpty) return true;
      final hay = '${i.name} ${i.emailSubject} ${i.senderName} ${i.senderEmail}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();

    if (_dedup) {
      // Список уже по убыванию даты: первое вхождение — самое новое письмо.
      final first = <String, int>{};
      final emails = <String, Set<String>>{};
      final kept = <AttachmentHubItem>[];
      for (final i in out) {
        final k = i.fileKey;
        (emails[k] ??= <String>{}).add('${i.accountId}|${i.emailId}');
        if (!first.containsKey(k)) {
          first[k] = kept.length;
          kept.add(i);
        }
      }
      out = [
        for (final i in kept) i.withCopies(emails[i.fileKey]!.length),
      ];
    }

    switch (_sort) {
      case _Sort.newest:
        break; // уже по дате
      case _Sort.largest:
        out.sort((a, b) => b.size.compareTo(a.size));
      case _Sort.name:
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return out;
  }

  /// Строки списка: заголовки-полосы (String) и файлы.
  List<Object> _rows(List<AttachmentHubItem> tabItems, List<AttachmentHubItem> all, String tab,
      AppLocalizations l10n) {
    final rows = <Object>[];
    // Недавно открытые — на вкладке «Все» без поиска и отборов.
    if (tab == 'all' && !_filtersActive) {
      final keys = ref.read(sharedPrefsProvider).getStringList(_kRecent) ?? const <String>[];
      final byKey = {for (final i in all) i.key: i};
      final recent = [for (final k in keys) if (byKey[k] != null) byKey[k]!].take(5).toList();
      if (recent.isNotEmpty) {
        rows.add(l10n.tr('filesRecent'));
        rows.addAll(recent);
      }
    }
    if (_sort == _Sort.newest) {
      // Группы по месяцам.
      final fmt = DateFormat('LLLL yyyy', l10n.localeCode);
      String? last;
      for (final i in tabItems) {
        final m = fmt.format(i.receivedAt);
        if (m != last) {
          rows.add(m);
          last = m;
        }
        rows.add(i);
      }
    } else {
      if (rows.isNotEmpty) rows.add(_sortLabel(_sort, l10n));
      rows.addAll(tabItems);
    }
    return rows;
  }

  // ─────────────────────────── экран ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hubAsync = ref.watch(attachmentHubProvider);
    ref.watch(accountsProvider); // метки ящиков у файлов

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('fileHub')),
        actions: [HelpButton(text: l10n.tr('filesHelp'), title: l10n.tr('fileHub'))],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: const Icon(AppIcons.folder, size: 20), text: l10n.tr('all')),
            const Tab(icon: Icon(AppIcons.picture_as_pdf, size: 20), text: 'PDF'),
            Tab(icon: const Icon(AppIcons.description, size: 20), text: l10n.tr('docsCategory')),
            Tab(icon: const Icon(AppIcons.table_chart, size: 20), text: l10n.tr('sheetsCategory')),
            Tab(icon: const Icon(AppIcons.image, size: 20), text: l10n.tr('imagesCategory')),
            Tab(icon: const Icon(AppIcons.folder_zip, size: 20), text: l10n.tr('archivesCategory')),
            Tab(icon: const Icon(AppIcons.insert_drive_file, size: 20), text: l10n.tr('otherCategory')),
          ],
        ),
      )),
      body: Column(
        children: [
          _FilesAccountChips(),
          // Поиск
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.tr('filesSearchHint'),
                prefixIcon: const Icon(AppIcons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: l10n.tr('clear'),
                        icon: const Icon(AppIcons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Space.m)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
          _filterBar(theme, l10n),

          // Список
          Expanded(
            child: hubAsync.when(
              // Перечитывание после новых писем — без крутилки поверх списка.
              skipLoadingOnReload: true,
              data: (items) {
                final filtered = _filterItems(items);
                return TabBarView(
                  controller: _tabController,
                  children: _tabs.map((tab) {
                    final tabItems = tab == 'all' ? filtered : filtered.where((i) => i.tab == tab).toList();
                    if (tabItems.isEmpty) return _empty(theme, l10n);
                    final rows = _rows(tabItems, items, tab, l10n);
                    return ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, index) {
                        final r = rows[index];
                        if (r is String) return SectionBand.light(title: r);
                        return _buildItem(r as AttachmentHubItem, theme, l10n);
                      },
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
    );
  }

  /// Строка отборов: период, порядок, «без повторов», отправитель.
  Widget _filterBar(ThemeData theme, AppLocalizations l10n) {
    Widget chip({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      VoidCallback? onDeleted,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: Space.s),
          child: FilterChip(
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
            avatar: Icon(icon, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
            selected: selected,
            onSelected: (_) => onTap(),
            onDeleted: onDeleted,
            deleteIcon: onDeleted == null ? null : const Icon(AppIcons.close, size: 16),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
        children: [
          if (_sender != null)
            chip(
              label: l10n.tr('filesFrom').replaceAll('{name}', _senderName ?? _sender!),
              icon: AppIcons.person,
              selected: true,
              onTap: () {},
              onDeleted: () => setState(() {
                _sender = null;
                _senderName = null;
              }),
            ),
          chip(
            label: _periodLabel(_period, l10n),
            icon: AppIcons.date_range,
            selected: _period != _Period.all,
            onTap: () => unawaited(_pickPeriod(l10n)),
          ),
          chip(
            label: _sortLabel(_sort, l10n),
            icon: AppIcons.sort,
            selected: _sort != _Sort.newest,
            onTap: () => unawaited(_pickSort(l10n)),
          ),
          chip(
            label: l10n.tr('filesNoRepeats'),
            icon: AppIcons.filter_list,
            selected: _dedup,
            onTap: _toggleDedup,
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme, AppLocalizations l10n) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.attach_file, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: Space.l),
            Text(l10n.tr('noAttachmentsFound'), style: theme.textTheme.bodyMedium),
            if (_filtersActive) ...[
              const SizedBox(height: Space.s),
              TextButton(
                onPressed: () => setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _period = _Period.all;
                  _sender = null;
                  _senderName = null;
                }),
                child: Text(l10n.tr('reset')),
              ),
            ],
          ],
        ),
      );

  Widget _buildItem(AttachmentHubItem item, ThemeData theme, AppLocalizations l10n) {
    final accounts = ref.read(accountsProvider);
    final acc = accounts.length > 1 ? accounts.where((a) => a.id == item.accountId).firstOrNull : null;
    final parts = [
      item.sizeFormatted,
      item.senderName,
      DateFormat('d MMM yyyy', l10n.localeCode).format(item.receivedAt),
      if (item.copies > 1) l10n.tr('filesInEmails').replaceAll('{n}', '${item.copies}'),
    ];
    return ListTile(
      leading: Stack(clipBehavior: Clip.none, children: [
        FileTypeIcon(category: item.category),
        // Метка ящика — когда ящиков несколько.
        if (acc != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color(acc.colorValue),
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
      ]),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(parts.join(' • '), style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          // Тема письма — по ней чаще всего и вспоминают документ.
          if (item.emailSubject.trim().isNotEmpty)
            Text(item.emailSubject,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
      // Нажатие — скачать и открыть файл; долгое — письмо, другое
      // приложение, «Поделиться», файлы отправителя.
      trailing: _busy.contains(item.key)
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              tooltip: l10n.tr('more'),
              icon: const Icon(AppIcons.more_vert),
              onPressed: () => _actions(item, l10n),
            ),
      onTap: () => _open(item, l10n),
      onLongPress: () => _actions(item, l10n),
    );
  }
}

/// Строка ящиков «Файлов»: нажатие — показать/скрыть файлы ящика, долгое
/// нажатие — только этот. Один ящик — строки нет.
class _FilesAccountChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).where((a) => a.isActive).toList();
    if (accounts.length < 2) return const SizedBox.shrink();
    final hidden = ref.watch(filesHiddenAccountsProvider);
    final n = ref.read(filesHiddenAccountsProvider.notifier);
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
        children: [
          for (final a in accounts)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: GestureDetector(
                onLongPress: () => n.set({for (final o in accounts) if (o.id != a.id) o.id}),
                child: FilterChip(
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  selected: !hidden.contains(a.id),
                  onSelected: (_) => n.toggle(a.id),
                  avatar: CircleAvatar(
                    radius: 6,
                    backgroundColor: hidden.contains(a.id) ? theme.colorScheme.outlineVariant : Color(a.colorValue),
                  ),
                  label: Text(a.displayName.trim().isNotEmpty ? a.displayName.trim() : a.email.split('@').first,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
