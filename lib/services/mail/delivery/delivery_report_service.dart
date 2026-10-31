// lib/services/mail/delivery/delivery_report_service.dart
// Отчёты о доставке среди новых писем (1.9.x, просьба владельца 31.10.2026).
//
// Синхронизация передаёт сюда новые письма папки. Похожие на отчёт (робот-
// отправитель, тема отчёта, структура multipart/report) скачиваются целиком
// и разбираются (DeliveryReportParser); статусы адресатов сохраняются в
// delivery_status по Message-ID исходного письма. Само письмо-отчёт остаётся
// в ящике — почту пользователя не удаляем.
//
// Для Exchange (EWS, ActiveSync) это единственный источник: DSN при
// отправке там не запрашивается, но отчёты сервер присылает сам.

import '../../../core/logging/app_logger.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../own_addresses.dart';
import 'delivery_report.dart';

/// Своё недоставленное письмо, о котором стоит уведомить.
typedef DeliveryFailure = ({Email original, List<RecipientDelivery> failed});

/// Ключ строки l10n с причиной простыми словами.
extension DeliveryReasonText on DeliveryReason {
  String get l10nKey => switch (this) {
        DeliveryReason.noSuchUser => 'dsnReasonNoSuchUser',
        DeliveryReason.domainNotFound => 'dsnReasonDomain',
        DeliveryReason.mailboxFull => 'dsnReasonFull',
        DeliveryReason.blocked => 'dsnReasonBlocked',
        DeliveryReason.tooLarge => 'dsnReasonTooLarge',
        DeliveryReason.delayed => 'dsnReasonDelayed',
        DeliveryReason.delivered => 'dsnDeliveredNote',
        DeliveryReason.other => 'dsnReasonOther',
      };
}

class DeliveryReportService {
  DeliveryReportService._();

  /// Сколько писем одной пачки скачивается для проверки: первая загрузка
  /// ящика с годом истории не должна качать сотни отчётов.
  static const maxPerBatch = 10;

  /// Отчёт с исходным письмом и вложениями бывает большим — такие не качаем.
  static const maxSize = 5 * 1024 * 1024;

  /// Отчёты старше — не разбираются (первая загрузка ящика).
  static const lookBack = Duration(days: 30);

  /// «Письмо не доставлено» — только о письмах, отправленных недавно.
  static const notifyWithin = Duration(days: 5);

  /// Разобрать новые письма. [fetchRaw] — MIME письма целиком; [isNew] — id
  /// писем, пришедших сейчас (не первая загрузка папки): только о них
  /// уведомляем. Возвращает id писем-отчётов, о которых обычное уведомление
  /// «новое письмо» не нужно: отчёт привязан к своему письму, и о недоставке
  /// сказано своим уведомлением [onFailure], а задержка и доставка видны на
  /// самом письме.
  static Future<Set<String>> process({
    required AppDatabase db,
    required AccountModel account,
    required List<EmailModel> fresh,
    required Future<String?> Function(EmailModel e) fetchRaw,
    Set<String> isNew = const {},
    Future<void> Function(DeliveryFailure f)? onFailure,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final since = t.subtract(lookBack);
    final candidates = [
      for (final e in fresh)
        if (!e.isDraft &&
            e.receivedAt.isAfter(since) &&
            (e.size ?? 0) <= maxSize &&
            DeliveryReportParser.isCandidate(
              fromEmail: e.from.email,
              fromName: e.from.displayName,
              subject: e.subject,
              reportType: DeliveryReportHints.take(account.id, e.id),
            ))
          e,
    ];
    final handled = <String>{};
    for (final e in candidates.take(maxPerBatch)) {
      String? raw;
      try {
        raw = await fetchRaw(e).timeout(const Duration(seconds: 20));
      } catch (err) {
        AppLogger.debug('Отчёт о доставке: письмо не скачано — $err');
        continue;
      }
      if (raw == null || raw.isEmpty) continue;
      final parsed = DeliveryReportParser.parse(raw, own: [account.email]);
      if (parsed == null) continue;
      final recipients = [for (final r in parsed.recipients) if (!OwnAddresses.isMine(account, r.recipient)) r];
      final ids = parsed.messageIds;
      if (recipients.isEmpty || ids.isEmpty) {
        AppLogger.info('Отчёт о доставке без адресата или Message-ID исходного письма — пропущен');
        continue;
      }
      // Исходное письмо — по Message-ID вложенных заголовков, затем по ENVID.
      // Не найдено (копия ещё не в «Отправленных») — статус всё равно
      // сохраняется и появится на письме, когда оно придёт.
      Email? original;
      var key = ids.first;
      for (final id in ids) {
        final o = await db.emailByMessageId(account.id, id);
        if (o != null) {
          original = o;
          key = id;
          break;
        }
      }
      final changed = await db.saveDeliveryStatuses(
        account.id,
        key,
        [
          for (final r in recipients)
            (recipient: r.recipient, action: r.action.name, status: r.status, diagnostic: r.diagnostic),
        ],
        reportEmailId: e.id,
        at: e.receivedAt,
      );
      AppLogger.info('Отчёт о доставке${parsed.standard ? '' : ' (текст)'}: '
          '${recipients.map((r) => '${AppLogger.mask(r.recipient)} ${r.action.name} ${r.status ?? ''}').join(', ')}'
          '${original == null ? ' — своё письмо пока не найдено' : ''}');
      if (original == null) continue;
      final failed = [for (final r in recipients) if (r.action == DeliveryAction.failed) r];
      if (failed.isEmpty) {
        handled.add(e.id);
        continue;
      }
      final sent = original.sentAt ?? original.receivedAt;
      if (t.difference(sent) > notifyWithin) continue; // давнее письмо — обычное уведомление
      handled.add(e.id);
      final news = [for (final r in failed) if (changed.contains(r.recipient)) r];
      // Тот же отчёт во второй папке (ярлыки Gmail) — повторно не уведомляем.
      if (news.isEmpty || !isNew.contains(e.id) || onFailure == null) continue;
      try {
        await onFailure((original: original, failed: news));
      } catch (err) {
        AppLogger.warning('Уведомление «не доставлено»: $err');
      }
    }
    return handled;
  }
}
