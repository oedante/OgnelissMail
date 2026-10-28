// lib/features/mail/widgets/peek_helpers.dart
// Действия карточки письма (1.6.47), общие для ленты и беседы:
//   · ответ на приглашение прямо из карточки — «Принять», «Под вопросом»,
//     «Отклонить» (ответ сразу уходит организатору, как из уведомления);
//   · файл письма из карточки — скачать (или взять из кэша) и открыть, не
//     открывая письма.
//
// Сервисы берутся до первого ожидания: экран (беседа) могут закрыть, пока
// идёт ответ или загрузка, а ref закрытого экрана читать уже нельзя.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/pending_invites.dart' show markInviteAnswered;
import '../../../services/mail/attachment_cache_service.dart' show attachmentCacheProvider;
import '../../../services/mail/draft_files.dart' show DraftFiles;
import '../../../services/mail/email_actions_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../services/mail/transport_capabilities.dart';
import '../../../widgets/common/haptic_wrapper.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/common/peek_card.dart';
import '../providers/mail_providers.dart' show emailsProvider;
import '../screens/attachment_preview_screen.dart' show PreviewItem, openAttachment;

/// Можно ли ответить на приглашение прямо из карточки: запрос на встречу от
/// сервера Exchange (ActiveSync MeetingRequest, EWS), ещё без ответа, не
/// своё, и ящик умеет отвечать. Приглашения по почте (.ics у Gmail и
/// Яндекса) — в письме: их сначала нужно прочитать из вложения.
bool peekCanRespondInvite(AccountModel? account, EmailModel e) {
  final m = e.meeting;
  if (account == null || m == null || !m.isRequest || e.isReplied) return false;
  if (!TransportCapabilities.forAccount(account).meetingResponse) return false;
  final end = m.end ?? m.start;
  if (end != null && end.isBefore(DateTime.now())) return false;
  final org = RegExp(r'[\w.+-]+@[\w.-]+').firstMatch(m.organizer ?? '')?.group(0);
  return !OwnAddresses.isMine(account, e.from.email) && !OwnAddresses.isMine(account, org);
}

/// Кнопки ответа на приглашение для карточки.
List<PeekAction> peekInviteActions(
  BuildContext context,
  WidgetRef ref,
  AccountModel account,
  EmailModel e,
  AppLocalizations l10n,
) {
  PeekAction act(String response, IconData icon, String label, Color color) => PeekAction(
        icon: icon,
        label: label,
        color: color,
        onTap: () => unawaited(peekRespondInvite(ref, account, e, response, l10n)),
      );
  return [
    act('accept', AppIcons.check, l10n.tr('accept'), AppColors.successText(context)),
    act('tentative', AppIcons.help, l10n.tr('meetingTentative'), AppColors.accentOrangeText(context)),
    act('decline', AppIcons.close, l10n.tr('decline'), AppColors.errorText(context)),
  ];
}

/// Ответить на приглашение сразу («Отправить ответ сейчас»): сервер
/// отправляет ответ организатору и ставит встречу в календарь. Комментарий,
/// «не отправлять» и новое время — в письме.
Future<bool> peekRespondInvite(
  WidgetRef ref,
  AccountModel account,
  EmailModel e,
  String response,
  AppLocalizations l10n,
) async {
  final engine = ref.read(mailEngineServiceProvider);
  final db = ref.read(databaseProvider);
  final actions = ref.read(emailActionsProvider);
  final emails = ref.read(emailsProvider.notifier);
  final kind = switch (response) { 'accept' => 'Accept', 'tentative' => 'Tentative', _ => 'Decline' };
  final title = e.subject;
  try {
    final r = await engine.respondToMeeting(
      account,
      itemId: e.id,
      response: response,
      folderId: e.folderId,
      meeting: e.meeting,
      title: title,
      mailSubject: l10n.tr('imipSubj$kind').replaceAll('{s}', title),
      mailBody: l10n.tr('imipBody$kind').replaceAll('{s}', title),
    );
    if (!r.ok) {
      showInlineError(l10n.tr('couldNotSendResponse'));
      return false;
    }
    unawaited(HapticHelper.success());
    // Из «Ждут ответа» в календаре и «Моём дне» — сразу.
    await markInviteAnswered(db, accountId: e.accountId, emailId: e.id);
    try {
      await actions.setRead(account, e.id, e.folderId, true);
    } catch (_) {}
    unawaited(emails.refresh().catchError((Object _) {}));
    return true;
  } catch (err) {
    showInlineError('${l10n.tr('couldNotSendResponse')}: $err');
    return false;
  }
}

/// Файл письма на телефоне: из кэша вложений, из письма (если сохранён) или
/// с сервера. null — не удалось (ошибка — строкой вверху экрана).
Future<String?> peekFetchFile(WidgetRef ref, AccountModel? account, EmailModel e, EmailAttachment a,
    AppLocalizations l10n) async {
  // Свой файл черновика (1.7.2+111) — с телефона, сервер его не знает.
  if (a.id.startsWith('draft:')) {
    final path = await DraftFiles.pathFor(e.id, a.id);
    if (path == null) showInlineError(l10n.tr('attachDownloadFailed'));
    return path;
  }
  final cache = ref.read(attachmentCacheProvider);
  final engine = ref.read(mailEngineServiceProvider);
  final key = MailEngineService.attachmentCacheKey(e.accountId, e.id, a.id);
  try {
    final cached = await cache.get(key);
    if (cached != null) return cached;
    final local = a.localPath;
    if (local != null && local.isNotEmpty && await File(local).exists()) return local;
    if (account == null) return null;
    final bytes = await engine.getAttachmentBytes(account, a.id, emailId: e.id);
    return await cache.put(key, a.name, bytes);
  } catch (err) {
    showInlineError('${l10n.tr('attachDownloadFailed')}: $err');
    return null;
  }
}

/// Открыть скачанный файл письма (внешнее приложение; вложенное письмо и
/// S/MIME — в почте).
void peekOpenFile(BuildContext context, EmailModel e, EmailAttachment a, String path) {
  if (!context.mounted) return;
  unawaited(openAttachment(
    context,
    PreviewItem(filePath: path, fileName: a.name, sizeBytes: a.size, mimeType: a.mimeType),
    emailSubject: e.subject,
    accountId: e.accountId,
    emailFrom: e.from.label,
    emailDate: e.receivedAt,
  ));
}
