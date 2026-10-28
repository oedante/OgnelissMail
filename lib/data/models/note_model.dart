// lib/data/models/note_model.dart
// Модель заметки (Notes). Синхронизируется с Exchange (EAS/EWS).

class NoteModel {
  final String id;
  final String? accountId;
  final String title;
  final String body;
  final List<String> categories;
  final int? colorValue;

  /// ServerId (EAS) или ItemId (EWS) для синхронизации правок/удаления.
  final String? serverId;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Локально изменена и ещё не отправлена на сервер.
  final bool isLocallyModified;
  final bool isDeleted;

  const NoteModel({
    required this.id,
    this.accountId,
    this.title = '',
    this.body = '',
    this.categories = const [],
    this.colorValue,
    this.serverId,
    required this.createdAt,
    required this.modifiedAt,
    this.isLocallyModified = false,
    this.isDeleted = false,
  });

  /// Заголовок для отображения: явный title или первая строка тела.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final firstLine = body.trim().split('\n').first.trim();
    return firstLine.isNotEmpty ? firstLine : 'Без названия';
  }

  /// Превью тела (для списка): несколько строк без заголовка.
  String get preview {
    final text = body.trim();
    if (title.trim().isEmpty) {
      // Если title пуст, первая строка ушла в заголовок — показываем остальное
      final lines = text.split('\n');
      return lines.length > 1 ? lines.sublist(1).join(' ').trim() : '';
    }
    return text.replaceAll('\n', ' ');
  }

  NoteModel copyWith({
    String? id,
    String? accountId,
    String? title,
    String? body,
    List<String>? categories,
    int? colorValue,
    String? serverId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isLocallyModified,
    bool? isDeleted,
  }) {
    return NoteModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      title: title ?? this.title,
      body: body ?? this.body,
      categories: categories ?? this.categories,
      colorValue: colorValue ?? this.colorValue,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// id строки заметки с сервера: «eas_<аккаунт>:<ServerId>» / «ews_…».
/// Раньше id строился из хеша ServerId без аккаунта, а ServerId у разных
/// EAS-ящиков совпадают («5:1») — заметки двух аккаунтов затирали друг друга.
String noteRowId({required bool eas, required String accountId, required String serverId}) =>
    '${eas ? 'eas' : 'ews'}_$accountId:$serverId';

/// id строки заметки IMAP (папка «Notes», 1.6.2): «imap_<аккаунт>:<UUID>».
String imapNoteRowId(String accountId, String uuid) => 'imap_$accountId:$uuid';
