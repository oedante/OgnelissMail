// lib/features/mail/providers/delivery_status_provider.dart
// Отчёты о доставке (1.9.x, просьба владельца 31.10.2026): статусы адресатов
// своего письма, недоставленные письма для значка в ленте, письмо, о котором
// пришёл отчёт.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../services/mail/delivery/delivery_report.dart';

typedef DeliveryKey = ({String accountId, String messageId});

/// Ключ письма в delivery_status; null — у письма нет Message-ID.
DeliveryKey? deliveryKeyOf(EmailModel e) {
  final mid = DeliveryReport.normalizeMessageId(e.internetMessageId);
  return mid == null ? null : (accountId: e.accountId, messageId: mid);
}

/// Статусы адресатов письма.
final deliveryStatusesProvider = StreamProvider.autoDispose.family<List<DeliveryStatus>, DeliveryKey>(
    (ref, k) => ref.watch(databaseProvider).watchDeliveryStatuses(k.accountId, k.messageId));

/// Недоставленные письма: «аккаунт|Message-ID».
final undeliveredProvider = StreamProvider<Set<String>>((ref) => ref.watch(databaseProvider).watchUndelivered());

/// Не доставлено хотя бы одному адресату — красный значок в строке ленты.
bool isUndelivered(Set<String>? undelivered, EmailModel e) {
  if (undelivered == null || undelivered.isEmpty) return false;
  final k = deliveryKeyOf(e);
  return k != null && undelivered.contains('${k.accountId}|${k.messageId}');
}

/// Письмо-отчёт → своё письмо, о котором он (чип «Отчёт о доставке»).
final deliveryReportOriginalProvider =
    FutureProvider.autoDispose.family<Email?, ({String accountId, String emailId})>((ref, k) async {
  final db = ref.watch(databaseProvider);
  final mid = await db.deliveryReportTarget(k.accountId, k.emailId);
  if (mid == null) return null;
  return db.emailByMessageId(k.accountId, mid);
});
