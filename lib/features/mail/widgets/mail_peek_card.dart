// lib/features/mail/widgets/mail_peek_card.dart
// Карточка письма по удержанию строки (1.6.29, идея владельца 18.10.2026 —
// «как в Telegram»): строка приподнимается и чуть увеличивается, фон
// затемняется и размывается, под карточкой — круглые кнопки быстрых действий
// (Ответить всем, Переслать, Прочитано, На контроль, Ещё…). Вместо шторки
// снизу с длинным списком: самые частые действия — одним касанием, рядом с
// письмом; остальное — «Ещё…» (прежняя шторка).
//
// 1.6.46: удержание 250 мс вместо 500 (QuickLongPress); палец можно не
// отпускать — провести на кнопку и отпустить (HoldPointer); касание
// карточки открывает письмо; письмо лично мне — «Ответить», а не
// «Ответить всем».
//
// 1.6.47: сама карточка, фон и ряд кнопок — общие (widgets/common/
// peek_card.dart: письма, встречи, контакты). Здесь — содержимое письма:
// у приглашения — время и место встречи (кнопки «Принять / Под вопросом /
// Отклонить» задаёт лента, см. peek_invite.dart), у письма с файлами — сами
// файлы: нажатие скачивает и открывает файл, не открывая письма.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../core/utils/text_safe.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/peek_card.dart';
import '../../../widgets/ui/file_type_icon.dart';
import '../providers/mail_open_cache.dart' show MailOpenCache;
import 'preview_text.dart';

export '../../../widgets/common/peek_card.dart' show PeekAction, PeekGroup;

/// Нужна ли «Ответить всем» (1.6.46): только когда кроме отправителя и меня
/// есть кому ответить. Письмо лично мне — просто «Ответить». Своё письмо —
/// как раньше («Ответить всем»: ответ уйдёт его адресатам). [own] — свои
/// адреса в нижнем регистре.
bool peekWantsReplyAll(EmailModel e, Set<String> own) {
  final from = e.from.email.trim().toLowerCase();
  if (from.isEmpty || own.contains(from)) return true;
  final others = {for (final a in [...e.to, ...e.cc]) a.email.trim().toLowerCase()}
    ..removeAll(own)
    ..remove(from)
    ..remove('');
  return others.isNotEmpty;
}

/// Файлы письма для карточки (1.6.47): без картинок, показанных в тексте
/// (подпись), запасных картинок Outlook (.wmz/.emz) и подписи S/MIME.
List<EmailAttachment> peekFiles(EmailModel e) {
  final html = (e.bodyHtml ?? '').toLowerCase();
  bool signature(EmailAttachment a) {
    final n = a.name.toLowerCase();
    final m = a.mimeType.toLowerCase();
    return n.endsWith('.p7s') || m.contains('pkcs7-signature');
  }

  // Свой черновик (1.7.2+111): только файлы на телефоне — не скачанные
  // файлы пересылки открываются в самом черновике.
  final ownDraft = e.folderId == 'drafts';
  return [
    for (final a in e.attachments)
      if (!a.isInline && !a.isVmlPreview && !signature(a) && !(html.isNotEmpty && MailOpenCache.embeddedIn(a, html)))
        if (!ownDraft || a.id.startsWith('draft:')) a,
  ];
}

/// Скачать файл письма (или взять из кэша): путь на телефоне; null — не
/// удалось (ошибка уже показана строкой вверху экрана).
typedef PeekFetchFile = Future<String?> Function(EmailAttachment a);

/// Открыть скачанный файл.
typedef PeekOpenFile = void Function(EmailAttachment a, String path);

/// Показать карточку письма над строкой [anchor] (глобальные координаты
/// строки; null — по центру экрана). Кнопка закрывает карточку и выполняет
/// действие; касание карточки — [onOpen] (открыть письмо); касание мимо —
/// просто закрывает. [fetchFile] и [openFile] — файлы письма в карточке.
Future<void> showMailPeek(
  BuildContext context, {
  required EmailModel email,
  required Rect? anchor,
  required List<PeekAction> actions,
  int conversationCount = 1,
  int previewLines = 3,
  VoidCallback? onOpen,
  PeekFetchFile? fetchFile,
  PeekOpenFile? openFile,
  List<PeekGroup> more = const [],
  String moreLabel = '…',
}) =>
    showPeekCard(
      context,
      anchor: anchor,
      actions: actions,
      onOpen: onOpen,
      more: more,
      moreLabel: moreLabel,
      card: _MailCard(
        email: email,
        conversationCount: conversationCount,
        previewLines: previewLines,
        fetchFile: fetchFile,
        openFile: openFile,
        onMore: onOpen,
      ),
    );

class _MailCard extends StatelessWidget {
  final EmailModel email;
  final int conversationCount;
  final int previewLines;
  final PeekFetchFile? fetchFile;
  final PeekOpenFile? openFile;

  /// «+N» файлов — открыть письмо.
  final VoidCallback? onMore;

  const _MailCard({
    required this.email,
    required this.conversationCount,
    required this.previewLines,
    this.fetchFile,
    this.openFile,
    this.onMore,
  });

  static const _maxFiles = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final name = email.from.label;
    final preview = email.preview.trim();
    final tags = [...email.categories, ...email.tags.where((t) => !email.categories.contains(t))];
    final meeting = email.meeting;
    final files = (fetchFile != null && openFile != null) ? peekFiles(email) : const <EmailAttachment>[];
    // Скрепка — только если файлов списком нет (ещё не известны).
    final clip = email.hasAttachments && files.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeroEmailAvatar(
              emailId: '${email.accountId}/${email.id}',
              initial: name.isNotEmpty ? initialOf(name) : '?',
              color: HeroEmailAvatar.colorForEmail(email.from.email),
              email: email.from.email,
              radius: 22,
              hero: false,
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: Space.s),
                  Text(AppDateFormat.listStamp(context, email.receivedAt),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ]),
                const SizedBox(height: 2),
                Text(email.subject.isEmpty ? l10n.tr('noSubject') : email.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: email.isRead ? FontWeight.w500 : FontWeight.w700)),
              ]),
            ),
          ]),
          // Приглашение — когда и где (1.6.47): решить, идти ли, можно прямо
          // по карточке.
          if (meeting != null && (meeting.start != null || meeting.isCanceled)) ...[
            const SizedBox(height: Space.s),
            _MeetingLine(meeting: meeting),
          ],
          if (tags.isNotEmpty || clip || conversationCount > 1) ...[
            const SizedBox(height: Space.s),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final t in tags.take(3))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.getTagColor(t).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(t,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppTheme.getTagColor(t), fontWeight: FontWeight.w600)),
                ),
              if (clip) Icon(AppIcons.attach_file, size: 16, color: muted),
              if (conversationCount > 1)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(AppIcons.forum, size: 14, color: muted),
                  const SizedBox(width: 2),
                  Text('$conversationCount', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                ]),
            ]),
          ],
          if (preview.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            // Строк — по настройке «Карточка письма» (1–4, 1.6.31).
            PreviewText(preview,
                lines: previewLines, style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.35)),
          ],
          // Файлы письма (1.6.47): нажатие — скачать и открыть, не открывая
          // письма.
          if (files.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            Wrap(spacing: Space.s, runSpacing: Space.s, children: [
              for (final a in files.take(_maxFiles)) _FileChip(file: a, fetch: fetchFile!, open: openFile!),
              if (files.length > _maxFiles)
                ActionChip(
                  label: Text('+${files.length - _maxFiles}'),
                  onPressed: onMore == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          onMore!();
                        },
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Время и место встречи из приглашения.
class _MeetingLine extends StatelessWidget {
  final EmailMeeting meeting;
  const _MeetingLine({required this.meeting});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = meeting.isCanceled ? AppColors.errorText(context) : AppColors.infoText(context);
    final String text;
    if (meeting.isCanceled) {
      text = l10n.tr('meetingCanceled');
    } else {
      final s = meeting.start!.toLocal();
      final e = meeting.end?.toLocal();
      final sameDay = e != null && e.year == s.year && e.month == s.month && e.day == s.day;
      final when = meeting.allDay
          ? '${AppDateFormat.dayMonth(context, s)} · ${l10n.tr('allDay')}'
          : (sameDay
              ? '${AppDateFormat.dayMonthTime(context, s)}–${AppDateFormat.time(context, e)}'
              : AppDateFormat.dayMonthTime(context, s));
      final where = (meeting.location ?? '').trim();
      text = where.isEmpty ? when : '$when · $where';
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(meeting.isCanceled ? AppIcons.event_busy : AppIcons.schedule, size: 18, color: color),
      const SizedBox(width: Space.s),
      Expanded(
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Файл письма плашкой: значок типа, имя, размер. Нажатие — скачать
/// (кружок на месте значка), закрыть карточку и открыть файл.
class _FileChip extends StatefulWidget {
  final EmailAttachment file;
  final PeekFetchFile fetch;
  final PeekOpenFile open;
  const _FileChip({required this.file, required this.fetch, required this.open});

  @override
  State<_FileChip> createState() => _FileChipState();
}

class _FileChipState extends State<_FileChip> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    final path = await widget.fetch(widget.file);
    if (!mounted) return;
    setState(() => _busy = false);
    if (path == null) return;
    final nav = Navigator.of(context);
    nav.pop();
    widget.open(widget.file, path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.file;
    final style = FileTypeStyle.of(context, FileTypeStyle.categoryOf(a.mimeType, a.name));
    return Semantics(
      button: true,
      label: a.name,
      child: Material(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: Radii.chipAll,
        child: InkWell(
          borderRadius: Radii.chipAll,
          onTap: () => unawaited(_tap()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220, minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
              child: ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox.square(
                    dimension: Sizes.iconRow,
                    child: _busy
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Icon(style.icon, size: Sizes.iconRow, color: style.color),
                  ),
                  const SizedBox(width: Space.s),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium),
                      if (a.size > 0)
                        Text(AppDateFormat.bytes(context, a.size),
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
