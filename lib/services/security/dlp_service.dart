// lib/services/security/dlp_service.dart
// Data Loss Prevention — проверка исходящих писем.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/email_model.dart';

final dlpServiceProvider = Provider<DlpService>((ref) => DlpService());

enum DataClassification { public, internal, confidential, secret }

class DlpViolation {
  final String type;
  final String description;
  final String? matchedText;
  final DlpSeverity severity;
  final String? rule;
  bool get blocking => severity == DlpSeverity.block;
  const DlpViolation({
    required this.type,
    required this.description,
    this.matchedText,
    this.severity = DlpSeverity.warning,
    this.rule,
  });
}

enum DlpSeverity { info, warning, block }

class DlpCheckResult {
  final List<DlpViolation> violations;
  final bool blocked;
  final bool isAllowed;
  const DlpCheckResult({
    this.violations = const [],
    this.blocked = false,
    this.isAllowed = true,
  });
  bool get hasViolations => violations.isNotEmpty;
  bool get hasBlockingViolations => violations.any((v) => v.blocking);
  DataClassification get highestClassification {
    if (violations.any((v) => v.type == 'classified' && v.severity == DlpSeverity.block)) {
      return DataClassification.secret;
    }
    if (violations.any((v) => v.severity == DlpSeverity.block)) {
      return DataClassification.confidential;
    }
    if (violations.any((v) => v.severity == DlpSeverity.warning)) {
      return DataClassification.internal;
    }
    return DataClassification.public;
  }
}

class DlpService {
  DlpCheckResult checkOutgoingEmail({
    required String senderEmail,
    required List<EmailAddress> recipients,
    required String subject,
    required String body,
    List<String> attachmentNames = const [],
    // Политика из настроек DLP (по умолчанию — как было).
    bool checkPersonalData = true,
    bool checkBankData = true,
    bool checkClassified = true,
    bool checkMassSend = true,
    int massSendThreshold = 50,
    Set<String> extraInternalDomains = const {},
  }) {
    final violations = <DlpViolation>[];
    final fullText = '$subject $body'.toLowerCase();
    // Свои — домен отправителя и домены из настроек. Раньше список доменов
    // был пуст, и внешними считались все получатели, включая коллег.
    final senderDomain = senderEmail.contains('@')
        ? senderEmail.split('@').last.toLowerCase()
        : '';
    final internal = {
      if (senderDomain.isNotEmpty) senderDomain,
      ...AppConstants.internalDomains.map((d) => d.toLowerCase()),
      ...extraInternalDomains.map((d) => d.toLowerCase()),
    };
    final externalRecipients = recipients.where((r) =>
        !internal.any((d) => r.email.toLowerCase().endsWith('@$d'))).toList();

    // 1. Грифы секретности
    for (final pattern in [
      // Слово целиком: «конфиденциальность» в подписи-оговорке или «ЛДСП»
      // в смете — не гриф (\b в Dart не знает кириллицы — свои границы).
      RegExp(r'(?<![\p{L}\p{N}])(?:конфиденциально|confidential|для служебного пользования|дсп|секретно|совершенно секретно)(?![\p{L}\p{N}])',
          caseSensitive: false, unicode: true),
    ]) {
      for (final match in pattern.allMatches(fullText)) {
        if (checkClassified && externalRecipients.isNotEmpty) {
          violations.add(DlpViolation(
            type: 'classified',
            description: 'Документ с грифом отправляется внешним получателям',
            matchedText: match.group(0),
            severity: DlpSeverity.block,
          ));
        }
      }
    }

    // 2. Персональные данные
    for (final match in (checkPersonalData ? RegExp(r'\d{3}-\d{3}-\d{3}\s*\d{2}').allMatches(fullText) : const <RegExpMatch>[])) {
      violations.add(DlpViolation(type: 'personal_data', description: 'Обнаружен СНИЛС', matchedText: match.group(0), severity: DlpSeverity.warning));
    }
    for (final match in !checkPersonalData ? const <RegExpMatch>[] : RegExp(r'(?:серия|паспорт)\s*:?\s*\d{2}\s*\d{2}\s*(?:номер|№|N)\s*:?\s*\d{6}', caseSensitive: false).allMatches(fullText)) {
      violations.add(DlpViolation(type: 'personal_data', description: 'Обнаружены паспортные данные', matchedText: match.group(0), severity: DlpSeverity.warning));
    }

    // 3. Банковские реквизиты
    for (final match in !checkBankData ? const <RegExpMatch>[] : RegExp(r'(?:р/?с|расчётный счёт|р/с)\s*:?\s*\d{20}', caseSensitive: false).allMatches(fullText)) {
      violations.add(DlpViolation(type: 'bank_data', description: 'Обнаружен расчётный счёт', matchedText: match.group(0), severity: DlpSeverity.warning));
    }

    // Номер банковской карты: 13–19 цифр (с пробелами/дефисами) и верная
    // контрольная сумма Луна — так не срабатывает на телефоны и номера заявок.
    for (final match in !checkBankData ? const <RegExpMatch>[] : RegExp(r'(?<!\d)\d(?:[ -]?\d){12,18}(?!\d)').allMatches(fullText)) {
      final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
      if (_luhnValid(digits)) {
        violations.add(DlpViolation(type: 'bank_data', description: 'Обнаружен номер банковской карты', matchedText: match.group(0), severity: DlpSeverity.warning));
      }
    }

    // 4. Массовая рассылка
    if (checkMassSend && recipients.length > massSendThreshold) {
      violations.add(DlpViolation(type: 'mass_send', description: 'Массовая рассылка: ${recipients.length} получателей', severity: DlpSeverity.warning));
    }

    // 5. Подозрительные вложения
    for (final name in attachmentNames) {
      if (name.toLowerCase().endsWith('.exe') || name.toLowerCase().endsWith('.bat') || name.toLowerCase().endsWith('.cmd')) {
        violations.add(DlpViolation(type: 'suspicious_attachment', description: 'Исполняемый файл: $name', matchedText: name, severity: DlpSeverity.block));
      }
    }

    final blocked = violations.any((v) => v.severity == DlpSeverity.block);
    return DlpCheckResult(violations: violations, blocked: blocked);
  }

  static bool _luhnValid(String digits) {
    if (digits.length < 13 || digits.length > 19) return false;
    var sum = 0;
    var dbl = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (dbl) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      dbl = !dbl;
    }
    return sum % 10 == 0;
  }
}
