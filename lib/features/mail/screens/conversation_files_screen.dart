// lib/features/mail/screens/conversation_files_screen.dart
// «Файлы и ссылки» беседы (2.2.0, план 08.11.2026 «из мессенджеров», как
// «Медиа, ссылки и документы» чата в Telegram и WhatsApp): все вложения и
// ссылки писем беседы на одном экране, самые новые — первыми. Открывается
// из меню «⋮» беседы.
//
// Файл открывается так же, как из письма: из кэша вложений или с сервера
// (фасад движка выбирает протокол), потом — openAttachment. Ссылка — через
// LinkOpener (проверка похожих доменов и несовпадения текста и адреса).
// Ссылки — из писем, тексты которых уже на устройстве.

import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/security/link_opener.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../core/utils/conversation_links.dart';
import '../../../core/utils/format_bytes.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../widgets/common/pane_navigator.dart';
import '../../../widgets/ui/file_type_icon.dart';
import '../providers/mail_providers.dart';
import 'attachment_preview_screen.dart';

/// Вложение беседы и его письмо.
typedef ConversationFile = ({EmailAttachment file, EmailModel email});

/// Вложения писем [emails] (без картинок внутри текста), самые новые —
/// первыми.
List<ConversationFile> conversationFiles(List<EmailModel> emails) {
  final sorted = [...emails]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  return [
    for (final e in sorted)
      for (final a in e.attachments)
        if (!a.isInline) (file: a, email: e),
  ];
}

List<ConversationLink> _links(List<LinkSource> mails) => conversationLinks(mails);

/// Открыть «Файлы и ссылки» беседы: в панели рядом с лентой — в ней же.
Future<void> openConversationFiles(BuildContext context, {required String conversationId, required String accountId}) {
  final screen = ConversationFilesScreen(conversationId: conversationId, accountId: accountId);
  if (PaneNavigator.isInside(context)) return PaneNavigator.push<void>(context, screen);
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class ConversationFilesScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String accountId;
  const ConversationFilesScreen({super.key, required this.conversationId, required this.accountId});

  @override
  ConsumerState<ConversationFilesScreen> createState() => _ConversationFilesScreenState();
}

class _ConversationFilesScreenState extends ConsumerState<ConversationFilesScreen> {
  List<ConversationFile>? _files;
  List<ConversationLink>? _linkList;

  /// Вложения, которые сейчас скачиваются, и не скачавшиеся (письмо +
  /// вложение).
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getConversation(conversationId: widget.conversationId, accountId: widget.accountId);
    final emails = [for (final r in rows) emailModelFromRow(r)];
    if (!mounted) return;
    setState(() => _files = conversationFiles(emails));
    // Разбор HTML всех писем беседы — в отдельном изоляте.
    final sources = <LinkSource>[
      for (final e in emails) (id: e.id, at: e.receivedAt, from: e.from.label, html: e.bodyHtml, plain: e.bodyPlain),
    ];
    List<ConversationLink> links;
    try {
      links = await compute(_links, sources);
    } catch (e) {
      AppLogger.warning('Ссылки беседы: $e');
      links = const [];
    }
    if (mounted) setState(() => _linkList = links);
  }

  String _key(ConversationFile f) => '${f.email.id}|${f.file.id}';

  Future<void> _open(ConversationFile f) async {
    final key = _key(f);
    if (_loading.contains(key)) return;
    final e = f.email;
    final att = f.file;
    final cache = ref.read(attachmentCacheProvider);
    final cacheKey = MailEngineService.attachmentCacheKey(e.accountId, e.id, att.id);
    var path = att.localPath ?? await cache.get(cacheKey);
    if (path == null) {
      final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
      if (account == null) return;
      setState(() {
        _loading.add(key);
        _failed.remove(key);
      });
      try {
        final bytes = await ref.read(mailEngineServiceProvider).getAttachmentBytes(account, att.id, emailId: e.id);
        path = await cache.put(cacheKey, att.name, bytes);
      } catch (err) {
        // Не скачалось — значок у файла; нажатие повторит.
        AppLogger.warning('Файлы беседы: «${att.name}» не скачано — $err');
        if (mounted) setState(() => _failed.add(key));
        return;
      } finally {
        if (mounted) setState(() => _loading.remove(key));
      }
    }
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
    await openAttachment(
      context,
      PreviewItem(filePath: path, fileName: att.name, sizeBytes: att.size, mimeType: att.mimeType),
      emailSubject: e.subject,
      accountId: e.accountId,
      emailFrom: e.from.label,
      emailDate: e.receivedAt,
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  Widget _filesTab(AppLocalizations l10n, ThemeData theme) {
    final files = _files;
    if (files == null) return const Center(child: CircularProgressIndicator());
    if (files.isEmpty) return _empty(l10n.tr('convFilesNone'));
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, i) {
        final f = files[i];
        final key = _key(f);
        final sub = [
          if (f.file.size > 0) formatBytes(f.file.size, l10n),
          f.email.from.label,
          AppDateFormat.dayMonth(context, f.email.receivedAt),
        ].join(' · ');
        return ListTile(
          leading: FileTypeIcon(category: FileTypeStyle.categoryOf(f.file.mimeType, f.file.name)),
          title: Text(f.file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _loading.contains(key)
              ? const SizedBox.square(dimension: Sizes.iconRow, child: CircularProgressIndicator(strokeWidth: 2))
              : _failed.contains(key)
                  ? Tooltip(
                      message: l10n.tr('convFileRetry'),
                      child: Icon(AppIcons.error, color: AppColors.errorText(context)),
                    )
                  : null,
          onTap: () => unawaited(_open(f)),
        );
      },
    );
  }

  Widget _linksTab(AppLocalizations l10n, ThemeData theme) {
    final links = _linkList;
    if (links == null) return const Center(child: CircularProgressIndicator());
    if (links.isEmpty) return _empty(l10n.tr('convLinksNone'));
    return ListView.builder(
      itemCount: links.length,
      itemBuilder: (context, i) {
        final l = links[i];
        final sub = [l.host, l.from, AppDateFormat.dayMonth(context, l.at)].join(' · ');
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Icon(AppIcons.link, color: theme.colorScheme.onSecondaryContainer),
          ),
          title: Text(l.text.isEmpty ? l.url : l.text, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => unawaited(LinkOpener.open(context, l.url, linkText: l.text.isEmpty ? null : l.text,
              accountId: widget.accountId)),
          // Удержание — скопировать адрес (как «Копировать ссылку» в мессенджере).
          onLongPress: () {
            unawaited(Clipboard.setData(ClipboardData(text: l.url)));
            unawaited(HapticFeedback.mediumImpact());
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String count(String key, List<Object>? list) => list == null ? l10n.tr(key) : '${l10n.tr(key)} · ${list.length}';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tr('convFilesTitle')),
          bottom: TabBar(tabs: [
            Tab(text: count('convFilesTab', _files)),
            Tab(text: count('convLinksTab', _linkList)),
          ]),
        ),
        body: TabBarView(children: [_filesTab(l10n, theme), _linksTab(l10n, theme)]),
      ),
    );
  }
}
