// lib/data/models/contact_model.dart

import '../../core/utils/text_safe.dart';
import '../../core/utils/avatar_colors.dart';

/// Источник контакта. Новые значения — только в конец (в базе — индекс).
/// fromMail — собран из переписки (MailContactsService).
enum ContactSource { exchangeGal, personal, device, fromMail }

class ContactModel {
  final String id;
  final String? accountId;
  final String email;
  final List<String> additionalEmails;
  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? middleName;
  final String? jobTitle;
  final String? department;
  final String? company;
  final String? phoneWork;
  final String? phoneMobile;
  final String? phoneExtension;
  final String? office;
  /// Руководитель (имя из адресной книги организации).
  final String? manager;
  final String? city;
  final String? avatarPath;
  final String? avatarUrl;
  final ContactSource source;
  final bool isFavorite;
  final bool isVip;
  final int interactionCount;
  final DateTime? lastInteraction;
  final String? notes;
  final DateTime? birthday;

  /// Группа рассылки организации (список рассылки Exchange): письмо уходит
  /// всем её участникам. Не хранится в базе — признак из адресной книги.
  final bool isGroup;

  const ContactModel({
    required this.id, this.accountId, required this.email,
    this.additionalEmails = const [], required this.displayName,
    this.firstName, this.lastName, this.middleName,
    this.jobTitle, this.department, this.company,
    this.phoneWork, this.phoneMobile, this.phoneExtension,
    this.office, this.manager, this.city, this.avatarPath, this.avatarUrl,
    this.source = ContactSource.personal,
    this.isFavorite = false, this.isVip = false,
    this.interactionCount = 0, this.lastInteraction,
    this.notes, this.birthday,
    this.isGroup = false,
  });

  String get fullName => [lastName, firstName, middleName].where((s) => s != null && s.isNotEmpty).join(' ');
  String get initials {
    final parts = displayName.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return displayName.isNotEmpty ? initialOf(displayName) : '?';
  }
  String get subtitle => [jobTitle, department, company].where((s) => s != null && s.isNotEmpty).join(' · ');
  /// Цвет кружка с буквой — общая палитра (раньше случайный цвет из хэша).
  int get avatarColor => avatarColorValue(email);
}

/// Строка БД → модель контакта со ВСЕМИ полями. Используется при выгрузке
/// правок: модель, собранная только из полей диалога, стирала на сервере
/// остальные (отчество, отдел, мобильный — по Supported пустое = удалить).
ContactModel contactFromRow(dynamic r) => ContactModel(
      id: r.id as String,
      accountId: r.accountId as String?,
      email: r.email as String,
      additionalEmails: ((r.additionalEmails as String?) ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      displayName: r.displayName as String,
      firstName: r.firstName as String?,
      lastName: r.lastName as String?,
      middleName: r.middleName as String?,
      jobTitle: r.jobTitle as String?,
      department: r.department as String?,
      company: r.company as String?,
      phoneWork: r.phoneWork as String?,
      phoneMobile: r.phoneMobile as String?,
      phoneExtension: r.phoneExtension as String?,
      office: r.office as String?,
      manager: r.manager as String?,
      city: r.city as String?,
      avatarPath: r.avatarPath as String?,
      avatarUrl: r.avatarUrl as String?,
      source: ContactSource.values[((r.source as int?) ?? 1).clamp(0, ContactSource.values.length - 1)],
      isFavorite: r.isFavorite as bool,
      isVip: r.isVip as bool,
      interactionCount: r.interactionCount as int,
      lastInteraction: r.lastInteraction as DateTime?,
      notes: r.notes as String?,
      birthday: r.birthday as DateTime?,
    );

/// Разбор отображаемого имени на имя и фамилию с сохранением прежнего
/// порядка: если раньше имя было «Фамилия Имя», так и остаётся.
({String? first, String? last}) splitDisplayName(String name,
    {String? oldDisplay, String? oldFirst, String? oldLast}) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return (first: null, last: null);
  if (parts.length == 1) return (first: parts.first, last: null);
  final lastFirst = oldLast != null &&
      oldLast.isNotEmpty &&
      (oldDisplay ?? '').trim().startsWith(oldLast);
  return lastFirst
      ? (first: parts.sublist(1).join(' '), last: parts.first)
      : (first: parts.first, last: parts.sublist(1).join(' '));
}
