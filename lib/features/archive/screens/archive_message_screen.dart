// lib/features/archive/screens/archive_message_screen.dart
// Письмо из архива Ogneliss (1.7.3): шапка, текст с оформлением и
// картинками, вложения; ответить, переслать (с вложениями), удалить из
// архива. Всё — без сети: письмо целиком лежит в архиве.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/security/html_sanitizer.dart';
import '../../../core/security/link_opener.dart';
import '../../../core/security/mail_body_processor.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mail_page_color.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/archive/archive_db.dart';
import '../../../services/archive/archive_vault.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../widgets/ui/section_band.dart';
import '../../mail/providers/mail_open_cache.dart' show MailOpenCache;
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../../mail/screens/attachment_preview_screen.dart' show PreviewItem, openAttachment;
import '../../mail/widgets/desktop_mail_body.dart';
import '../../mail/widgets/mail_html_view.dart';

class ArchiveMessageScreen extends ConsumerStatefulWidget {
  final int id;
  const ArchiveMessageScreen({super.key, required this.id});

  @override
  ConsumerState<ArchiveMessageScreen> createState() => _ArchiveMessageScreenState();
}

class _ArchiveMessageScreenState extends ConsumerState<ArchiveMessageScreen> {
  ArchiveMessage? _m;
  String? _html;
  MailHtmlDocument? _doc;

  /// Встроенные картинки письма (cid → data URI) — для показа виджетами.
  Map<String, String> _images = const {};
  bool _loading = true;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = ref.read(archiveDbProvider);
    if (db == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final m = await db.message(widget.id);
      if (m == null) {
        if (mounted) {
          setState(() {
            _missing = true;
            _loading = false;
          });
        }
        return;
      }
      if (!m.head.isRead) unawaited(db.setRead(widget.id, true));
      String? html;
      final rawHtml = (m.bodyHtml ?? '').trim();
      if (rawHtml.isNotEmpty) {
        // Стили письма — и на компьютере (1.8.14): по ним показ виджетами
        // решает, что скрыто и простое ли письмо.
        html = await MailBodyProcessor.heavy(rawHtml, HtmlSanitizer.sanitizeKeepingStyles);
      } else if ((m.bodyText ?? '').trim().isNotEmpty) {
        html = '<pre style="white-space:pre-wrap;word-wrap:break-word;font-family:inherit;margin:0">'
            '${const HtmlEscape(HtmlEscapeMode.element).convert(m.bodyText!)}</pre>';
      }
      MailHtmlDocument? doc;
      var images = const <String, String>{};
      if (html != null) images = await _inlineImages(db, m, rawHtml.toLowerCase());
      if (html != null && mailWebViewSupported) {
        doc = await MailHtmlDocument.buildAsync(html, allowRemoteImages: false, inlineImages: images);
      }
      if (!mounted) return;
      setState(() {
        _m = m;
        _html = html;
        _doc = doc;
        _images = images;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showInlineError('${AppLocalizations.of(context).tr('errorLbl')}: $e');
      }
    }
  }

  /// Картинки в тексте (cid:) — из вложений архива, data URI.
  static Future<Map<String, String>> _inlineImages(ArchiveDb db, ArchiveMessage m, String lowerHtml) async {
    if (!lowerHtml.contains('cid:')) return const {};
    final out = <String, String>{};
    for (final a in m.attachments) {
      final cid = _normCid(a.contentId);
      if (cid == null || !lowerHtml.contains('cid:$cid')) continue;
      final bytes = await db.attachmentData(a.id);
      if (bytes == null || bytes.length > 8 * 1024 * 1024) continue;
      final mime = MailOpenCache.imageMimeOf(bytes);
      if (mime == null) continue;
      out[cid] = 'data:$mime;base64,${base64Encode(bytes)}';
    }
    return out;
  }

  static String? _normCid(String? raw) {
    if (raw == null) return null;
    var c = raw.trim();
    if (c.startsWith('<') && c.endsWith('>')) c = c.substring(1, c.length - 1);
    c = c.trim().toLowerCase();
    return c.isEmpty ? null : c;
  }

  /// Вложение — во временный файл (открыть, сохранить, переслать).
  Future<File?> _file(ArchiveAttachmentInfo a) async {
    final db = ref.read(archiveDbProvider);
    if (db == null) return null;
    final bytes = await db.attachmentData(a.id);
    if (bytes == null) return null;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'ogna_view', '${widget.id}'));
    await dir.create(recursive: true);
    final safe = a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final f = File(p.join(dir.path, '${a.id}_${safe.isEmpty ? 'file' : safe}'));
    if (!await f.exists() || await f.length() != bytes.length) await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> _open(ArchiveAttachmentInfo a) async {
    final l10n = AppLocalizations.of(context);
    try {
      final f = await _file(a);
      if (f == null || !mounted) return;
      await openAttachment(
        context,
        PreviewItem(filePath: f.path, fileName: a.name, sizeBytes: a.size, mimeType: a.mime),
        emailSubject: _m?.head.subject,
      );
    } catch (e) {
      showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', '$e'));
    }
  }

  /// Ответ или пересылка — новое письмо из ящика, откуда пришло письмо
  /// (если он ещё подключён): тема, адресат и текст письма цитатой.
  Future<void> _compose({required bool forward}) async {
    final m = _m;
    if (m == null) return;
    final l10n = AppLocalizations.of(context);
    final h = m.head;
    final accounts = ref.read(accountsProvider);
    final account = accounts.where((a) => a.id == h.accountId).firstOrNull;
    final subject = h.subject.trim();
    final prefix = forward ? 'Fwd: ' : 'Re: ';
    final lower = subject.toLowerCase();
    final newSubject = (forward ? lower.startsWith('fwd:') || lower.startsWith('fw:') : lower.startsWith('re:'))
        ? subject
        : '$prefix$subject';
    var text = (m.bodyText ?? '').trim();
    if (text.isEmpty && (m.bodyHtml ?? '').isNotEmpty) {
      text = await MailBodyProcessor.heavy(m.bodyHtml!, MailBodyProcessor.htmlToPlain);
    }
    if (text.length > 20000) text = '${text.substring(0, 20000)}…';
    if (!mounted) return;
    String people(List<ArchivePerson> l) =>
        l.map((x) => x.name.trim().isEmpty ? x.email : '${x.name} <${x.email}>').join(', ');
    final head = [
      forward ? '---------- ${l10n.tr('forwardedMessage')} ----------' : '',
      '${l10n.tr('from')}: ${h.fromName.trim().isEmpty ? h.fromEmail : '${h.fromName} <${h.fromEmail}>'}',
      '${l10n.tr('date')}: ${AppDateFormat.dateTime(context, h.date)}',
      if (m.to.isNotEmpty) '${l10n.tr('to')}: ${people(m.to)}',
      if (m.cc.isNotEmpty) '${l10n.tr('cc')}: ${people(m.cc)}',
      '${l10n.tr('subject')}: $subject',
    ].where((s) => s.isNotEmpty).join('\n');
    final body = forward
        ? '\n\n$head\n\n$text'
        : '\n\n$head\n\n${text.split('\n').map((l) => '> $l').join('\n')}';
    final files = <String>[];
    if (forward) {
      for (final a in m.attachments.where((a) => !a.isInline)) {
        final f = await _file(a);
        if (f != null) files.add(f.path);
      }
    }
    if (!mounted) return;
    final q = <String, String>{
      if (account != null) 'accountId': account.id,
      if (!forward && h.fromEmail.isNotEmpty) 'to': h.fromEmail,
      'subject': newSubject,
      'body': body,
      if (files.isNotEmpty) 'attachments': files.join('|'),
    };
    unawaited(context.push(Uri(path: '/compose', queryParameters: q).toString()));
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final m = _m;
    if (m == null) return;
    final ok = await confirmDestructive(
      context,
      title: l10n.tr('archiveDeleteMsgAsk'),
      message: m.head.subject.trim().isEmpty ? null : m.head.subject.trim(),
    );
    if (!ok || !mounted) return;
    final db = ref.read(archiveDbProvider);
    if (db == null) return;
    await db.deleteMessage(widget.id);
    ref.read(archiveVaultProvider.notifier).touch();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // Временные файлы вложений письма — не оставляем.
    unawaited(() async {
      try {
        final tmp = await getTemporaryDirectory();
        final dir = Directory(p.join(tmp.path, 'ogna_view', '${widget.id}'));
        // Пересылка могла взять файлы в черновик — убираем позже.
        await Future<void>.delayed(const Duration(minutes: 30));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: Text(l10n.tr('ognaArchive')),
          actions: [
            if (_m != null) ...[
              IconButton(tooltip: l10n.tr('reply'), icon: const Icon(AppIcons.reply), onPressed: () => _compose(forward: false)),
              IconButton(tooltip: l10n.tr('forward'), icon: const Icon(AppIcons.forward), onPressed: () => _compose(forward: true)),
              IconButton(tooltip: l10n.tr('archiveDeleteMsg'), icon: const Icon(AppIcons.delete), onPressed: _delete),
            ],
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _m == null
              ? Center(child: Text(l10n.tr(_missing ? 'archiveMsgMissing' : 'archiveLockedIntro'), textAlign: TextAlign.center))
              : _view(l10n, _m!),
    );
  }

  Widget _view(AppLocalizations l10n, ArchiveMessage m) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final h = m.head;
    String people(List<ArchivePerson> l) => l.map((x) => x.name.trim().isEmpty ? x.email : x.name.trim()).join(', ');
    Widget field(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Tooltip(
              message: label,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: Space.s),
                child: Icon(icon, size: 18, color: muted, semanticLabel: label),
              ),
            ),
            Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
          ]),
        );
    final files = [for (final a in m.attachments) if (!a.isInline) a];
    final html = _html;
    final doc = _doc;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.m),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: Radii.cardAll),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.subject.trim().isEmpty ? l10n.tr('noSubject') : h.subject.trim(),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: Space.xs),
              field(AppIcons.person, l10n.tr('from'),
                  h.fromName.trim().isEmpty ? h.fromEmail : '${h.fromName.trim()} <${h.fromEmail}>'),
              if (m.to.isNotEmpty) field(AppIcons.mailTo, l10n.tr('to'), people(m.to)),
              if (m.cc.isNotEmpty) field(AppIcons.mailCc, l10n.tr('cc'), people(m.cc)),
              field(AppIcons.schedule, l10n.tr('date'), AppDateFormat.dateTime(context, h.date)),
              field(AppIcons.inventory_2, l10n.tr('ognaArchive'),
                  '${h.folderPath.replaceAll('/', ' › ')} · ${l10n.tr('archiveArchivedOn').replaceAll('{date}', AppDateFormat.date(context, m.archivedAt))}'),
            ]),
          ),
        ),
        const SizedBox(height: Space.m),
        if (html == null)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(l10n.tr('emlNoText'), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          )
        else if (doc != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MailHtmlView(
                key: ValueKey('ogna_${widget.id}_${theme.brightness.name}'),
                document: doc,
                allowRemoteImages: false,
                // Размер текста — как на экране письма (1.8.12).
                textScale: MailHtmlView.textScaleOf(context),
                pageColor: mailPageColor(theme),
                dark: theme.brightness == Brightness.dark,
                onLink: (url, text) => LinkOpener.open(context, url, linkText: text),
              ),
            ),
          )
        else
          // Компьютер (1.8.14): виджетами, как в экране письма.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: DesktopMailBody(
              html: html,
              images: _images,
              textScale: MailHtmlView.textScaleOf(context),
              onLink: (url, text) => LinkOpener.open(context, url, linkText: text),
            ),
          ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          SectionBand(title: l10n.tr('attachments'), count: files.length),
          for (final a in files)
            ListTile(
              leading: Icon(_iconFor(a)),
              title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(AppDateFormat.bytes(context, a.size)),
              onTap: () => _open(a),
            ),
        ],
      ],
    );
  }

  static IconData _iconFor(ArchiveAttachmentInfo a) {
    final ext = a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '';
    final ct = a.mime.toLowerCase();
    if (ext == 'eml' || ct == 'message/rfc822') return AppIcons.mail;
    if (ext == 'pdf') return AppIcons.picture_as_pdf;
    if (ct.startsWith('image/')) return AppIcons.image;
    return AppIcons.insert_drive_file;
  }
}
