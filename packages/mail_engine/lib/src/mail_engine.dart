// lib/src/mail_engine.dart
// Единый контракт движка. Все транспорты (EAS/EWS/IMAP-SMTP) реализуют его.

import 'models/models.dart';

abstract class MailEngine {
  /// Транспорт этого движка.
  MailTransportKind get kind;

  /// Возможности (заполняются после connect).
  Capabilities get capabilities;

  /// Политика безопасности (EAS Provision) или null.
  SecurityPolicy? get policy;

  /// Подключиться и авторизоваться. Возвращает результат с логом для диагностики.
  Future<ConnectResult> connect(AccountConfig cfg);

  /// Список папок.
  Future<List<MailFolder>> listFolders();

  /// Синхронизировать папку начиная с состояния [since] (null = с нуля).
  Future<SyncResult> syncFolder(String folderId, {SyncState? since});

  /// Дотянуть полное сообщение (тело/вложения).
  Future<MailMessage> fetchMessage(MessageRef ref);

  /// Отправить письмо.
  Future<void> send(OutgoingMessage message);

  /// Изменить флаги (прочитано/важное).
  Future<void> applyFlags(MessageRef ref, {bool? read, bool? flagged});

  /// Переместить письмо.
  Future<void> move(MessageRef ref, String toFolderId);

  /// Удалить письмо.
  Future<void> delete(MessageRef ref);

  /// Закрыть соединения/освободить ресурсы.
  Future<void> dispose();

  /// Синхронизировать PIM-папку (Calendar/Contacts/Tasks/Notes).
  /// [dataClass] — EAS-класс: 'Calendar', 'Contacts', 'Tasks', 'Notes'.
  /// По умолчанию не поддерживается (только EAS).
  Future<List<PimItem>> syncPim(String folderId,
          {required String dataClass, SyncState? since}) async =>
      throw UnsupportedError('syncPim не поддерживается этим транспортом');
}
