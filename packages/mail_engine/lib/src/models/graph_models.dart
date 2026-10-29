// lib/src/models/graph_models.dart
// Модели Microsoft Graph (Exchange Online, 1.8.11) — как их отдаёт
// GraphEngine: адресная книга, подсказки MailTips, переговорные, категории,
// правила «Входящих», письма для восстановления. Приложение переводит их в
// свои модели само.

/// Пользователь каталога или человек из /me/people.
class GraphUser {
  final String email;
  final String displayName;
  final String? givenName;
  final String? surname;
  final String? jobTitle;
  final String? department;
  final String? company;
  final String? office;
  final String? businessPhone;
  final String? mobilePhone;
  final String? city;
  final String? manager;

  const GraphUser({
    required this.email,
    required this.displayName,
    this.givenName,
    this.surname,
    this.jobTitle,
    this.department,
    this.company,
    this.office,
    this.businessPhone,
    this.mobilePhone,
    this.city,
    this.manager,
  });

  /// Должность или отдел известны.
  bool get hasPosition => (jobTitle ?? '').isNotEmpty || (department ?? '').isNotEmpty;

  /// Пустые поля — из [o].
  GraphUser mergedWith(GraphUser o) {
    String? pick(String? a, String? b) => (a ?? '').trim().isNotEmpty ? a : b;
    return GraphUser(
      email: email,
      displayName: displayName.split(' ').length >= o.displayName.split(' ').length ? displayName : o.displayName,
      givenName: pick(givenName, o.givenName),
      surname: pick(surname, o.surname),
      jobTitle: pick(jobTitle, o.jobTitle),
      department: pick(department, o.department),
      company: pick(company, o.company),
      office: pick(office, o.office),
      businessPhone: pick(businessPhone, o.businessPhone),
      mobilePhone: pick(mobilePhone, o.mobilePhone),
      city: pick(city, o.city),
      manager: pick(manager, o.manager),
    );
  }

  GraphUser withManager(String name) => GraphUser(
        email: email,
        displayName: displayName,
        givenName: givenName,
        surname: surname,
        jobTitle: jobTitle,
        department: department,
        company: company,
        office: office,
        businessPhone: businessPhone,
        mobilePhone: mobilePhone,
        city: city,
        manager: name,
      );
}

/// Подсказка Exchange (MailTips) об адресате.
class GraphMailTip {
  /// Адрес (нижний регистр).
  final String email;
  final String name;

  /// Текст автоответа без разметки; null — автоответ не включён.
  final String? autoReply;
  final bool mailboxFull;
  final int? totalMembers;
  final int? externalMembers;

  const GraphMailTip({
    required this.email,
    this.name = '',
    this.autoReply,
    this.mailboxFull = false,
    this.totalMembers,
    this.externalMembers,
  });
}

/// Переговорная или список переговорных (/places).
class GraphPlace {
  final String name;
  final String email;
  const GraphPlace({required this.name, required this.email});
}

/// Категория главного списка Outlook. [color] — номер цвета Outlook
/// (preset0…preset24 → 0…24), -1 — без цвета.
class GraphCategory {
  final String name;
  final int color;
  const GraphCategory({required this.name, required this.color});
}

/// Правило «Входящих» (messageRule) как пришло с сервера.
class GraphRule {
  final String id;
  final String name;
  final bool enabled;
  final int sequence;

  /// Правило Graph меняет только для чтения (Outlook на компьютере).
  final bool readOnly;
  final bool hasError;

  /// Что делает: move, copy, delete, forward, redirect, read, importance,
  /// category, stop.
  final Set<String> actions;
  final Map<String, dynamic> raw;

  const GraphRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.sequence,
    required this.readOnly,
    required this.hasError,
    required this.actions,
    this.raw = const {},
  });
}

/// Где проверяется условие нового правила.
enum GraphRuleField { from, to, subject, any }

/// Что делает новое правило.
enum GraphRuleAction { move, markRead, delete, forward }

/// Новое правило: одно условие, одно действие (как в редакторе приложения).
class GraphRuleSpec {
  final String name;
  final GraphRuleField field;

  /// Адрес целиком (только для «От» и «Кому»); иначе — «содержит».
  final bool exact;
  final String value;
  final GraphRuleAction action;

  /// Id папки Graph (move) или адрес пересылки (forward).
  final String arg;
  final bool stop;
  final bool enabled;
  final int sequence;

  const GraphRuleSpec({
    required this.name,
    required this.field,
    this.exact = false,
    required this.value,
    required this.action,
    this.arg = '',
    this.stop = false,
    this.enabled = true,
    this.sequence = 1,
  });

  /// Тело messageRule.
  Map<String, Object> toJson() {
    final v = value.trim();
    List<Map<String, Object>> addresses(String a) => [
          {
            'emailAddress': {'address': a}
          }
        ];
    final byAddress = exact && (field == GraphRuleField.from || field == GraphRuleField.to);
    final key = switch (field) {
      GraphRuleField.from => byAddress ? 'fromAddresses' : 'senderContains',
      GraphRuleField.to => byAddress ? 'sentToAddresses' : 'recipientContains',
      GraphRuleField.subject => 'subjectContains',
      GraphRuleField.any => 'bodyOrSubjectContains',
    };
    final a = arg.trim();
    return {
      'displayName': name.trim().isNotEmpty ? name.trim() : v,
      'sequence': sequence < 1 ? 1 : sequence,
      'isEnabled': enabled,
      'conditions': {key: byAddress ? addresses(v) : [v]},
      'actions': <String, Object>{
        if (action == GraphRuleAction.delete) 'delete': true,
        if (action == GraphRuleAction.markRead) 'markAsRead': true,
        if (action == GraphRuleAction.move) 'moveToFolder': a,
        if (action == GraphRuleAction.forward) 'forwardTo': addresses(a),
        if (stop || action == GraphRuleAction.delete) 'stopProcessingRules': true,
      },
    };
  }
}

/// Папка почты: id Graph и путь «Папка/Подпапка».
class GraphFolder {
  final String id;
  final String path;
  const GraphFolder({required this.id, required this.path});
}

/// Письмо в списке (тема, отправитель, когда получено).
class GraphMessageInfo {
  final String id;
  final String subject;
  final String from;
  final DateTime? received;
  const GraphMessageInfo({required this.id, required this.subject, required this.from, this.received});
}
