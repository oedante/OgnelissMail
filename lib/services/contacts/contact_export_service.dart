// lib/services/contacts/contact_export_service.dart
// Экспорт/импорт контактов: VCF (vCard 3.0), CSV.

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/contact_model.dart';

final contactExportProvider = Provider<ContactExportService>((ref) => ContactExportService());

class ContactExportService {
  /// Экспорт в VCF (vCard 3.0)
  Future<String> exportToVcf(List<ContactModel> contacts) async {
    final buf = StringBuffer();
    for (final c in contacts) {
      buf.writeln('BEGIN:VCARD');
      buf.writeln('VERSION:3.0');
      buf.writeln('N:${_vcf(c.lastName)};${_vcf(c.firstName)};${_vcf(c.middleName)};;');
      buf.writeln('FN:${_vcf(c.displayName)}');
      buf.writeln('EMAIL;TYPE=INTERNET:${_vcf(c.email)}');
      if (c.phoneWork != null) buf.writeln('TEL;TYPE=WORK:${_vcf(c.phoneWork)}');
      if (c.phoneMobile != null) buf.writeln('TEL;TYPE=CELL:${_vcf(c.phoneMobile)}');
      if (c.company != null) buf.writeln('ORG:${_vcf(c.company)}${c.department != null ? ";${_vcf(c.department)}" : ""}');
      if (c.jobTitle != null) buf.writeln('TITLE:${_vcf(c.jobTitle)}');
      if (c.city != null) buf.writeln('ADR;TYPE=WORK:;;;;;;${_vcf(c.city)}');
      if (c.notes != null) buf.writeln('NOTE:${_vcf(c.notes)}');
      buf.writeln('END:VCARD');
      buf.writeln();
    }

    return _saveFile('contacts', 'vcf', buf.toString());
  }

  /// Экспорт в CSV (с BOM для Excel)
  Future<String> exportToCsv(List<ContactModel> contacts) async {
    final buf = StringBuffer();
    buf.write('\uFEFF'); // BOM
    buf.writeln('Имя,Фамилия,Отчество,Email,Телефон рабочий,Телефон мобильный,Компания,Отдел,Должность,Город');
    for (final c in contacts) {
      buf.writeln([
        c.firstName, c.lastName, c.middleName, c.email, c.phoneWork,
        c.phoneMobile, c.company, c.department, c.jobTitle, c.city,
      ].map(_csv).join(','));
    }
    return _saveFile('contacts', 'csv', buf.toString());
  }

  /// Экранирование значения vCard (RFC 2426): обратный слэш, перевод строки,
  /// запятая и точка с запятой — иначе запятая/; ломали бы структуру карточки.
  String _vcf(String? v) => (v ?? '')
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  /// Экранирование поля CSV: значение в кавычках, внутренние кавычки удваиваются,
  /// переводы строк убираются — иначе имя/компания с « " » или запятой ломали бы
  /// столбцы в Excel.
  String _csv(String? v) {
    final s = (v ?? '').replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('"', '""');
    return '"$s"';
  }

  /// Импорт VCF
  List<ContactModel> importFromVcf(String vcfContent) {
    final contacts = <ContactModel>[];
    final cards = vcfContent.split('BEGIN:VCARD');
    for (final card in cards) {
      if (card.trim().isEmpty) continue;
      String? email, fn, lastName, firstName, middleName, phone, mobile, org, title;
      for (final line in card.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('EMAIL')) email = trimmed.split(':').last.trim();
        if (trimmed.startsWith('FN:')) fn = trimmed.substring(3).trim();
        if (trimmed.startsWith('N:')) {
          final parts = trimmed.substring(2).split(';');
          if (parts.isNotEmpty) lastName = parts[0].trim();
          if (parts.length > 1) firstName = parts[1].trim();
          if (parts.length > 2) middleName = parts[2].trim();
        }
        if (trimmed.contains('TEL') && trimmed.contains('WORK')) phone = trimmed.split(':').last.trim();
        if (trimmed.contains('TEL') && trimmed.contains('CELL')) mobile = trimmed.split(':').last.trim();
        if (trimmed.startsWith('ORG:')) org = trimmed.substring(4).split(';').first.trim();
        if (trimmed.startsWith('TITLE:')) title = trimmed.substring(6).trim();
      }
      if (email != null && email.isNotEmpty) {
        contacts.add(ContactModel(
          id: 'import_${email.hashCode}_${DateTime.now().millisecondsSinceEpoch}',
          email: email, displayName: fn ?? email,
          firstName: firstName, lastName: lastName, middleName: middleName,
          phoneWork: phone, phoneMobile: mobile, company: org, jobTitle: title,
        ));
      }
    }
    return contacts;
  }

  Future<String> _saveFile(String name, String ext, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path = '${dir.path}/exports/${name}_$timestamp.$ext';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    AppLogger.info('Exported: $path');
    return path;
  }
}
