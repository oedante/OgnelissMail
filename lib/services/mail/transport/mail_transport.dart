// lib/services/mail/transport/mail_transport.dart
// Единый интерфейс транспорта почты. ActiveSync — единый движок mail_engine;
// EWS и IMAP — пока прежние сервисы (переводятся на движок следующими).
// Фабрика transportFor(account) выбирает нужную реализацию по типу аккаунта,
// устраняя повторяющиеся if (usesEas)/else if (usesEws) по всему коду.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../ews/ews_service.dart';
import '../imap/imap_service.dart';
import '../engine/mail_engine_service.dart';
import '../../security/smime_service.dart';
import 'dart:typed_data';

/// Контракт транспорта почты — единый для всех протоколов.
abstract class MailTransport {
  /// Отправить письмо. Возвращает true при успехе.
  Future<bool> send(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc,
    List<EmailAddress> bcc,
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    bool saveSentCopy,
    List<({String name, String? contentType, Uint8List bytes})> attachments,
    String importance,
    String sensitivity,
    /// Постоянный id отправки (запись очереди): EAS передаёт его как
    /// ClientId, и повтор той же отправки сервер не выполняет дважды.
    String? clientId,
    /// Отправитель «от имени» (адрес отправки, 1.6.27); null — владелец ящика.
    EmailAddress? from,
  });

  Future<void> setRead(AccountModel account, {required String emailId, required String folderId, required bool isRead});
  Future<void> setFlag(AccountModel account, {required String emailId, required String folderId, required bool isFlagged});
  /// Переместить письмо. Возвращает новый id письма, если транспорт его
  /// меняет и сообщает (EWS); null — id не изменился или обновлён самим
  /// транспортом (ActiveSync, IMAP переименовывают строку сами).
  Future<String?> move(AccountModel account, {required String emailId, required String fromFolderId, required String toFolderId});
  Future<void> delete(AccountModel account, {required String emailId, required String folderId, bool hard});
}

// ─────────────────────────── EWS ───────────────────────────
class EwsTransport implements MailTransport {
  final EwsService _ews;
  final SmimeService _smime;
  EwsTransport(this._ews, this._smime);

  @override
  Future<bool> send(AccountModel account, {required List<EmailAddress> to, List<EmailAddress> cc = const [], List<EmailAddress> bcc = const [], required String subject, required String bodyHtml, String? inReplyTo, bool saveSentCopy = true, List<({String name, String? contentType, Uint8List bytes})> attachments = const [], String importance = 'Normal', String sensitivity = 'Normal', String? clientId, EmailAddress? from}) async {
    await _ews.sendEmail(account, to: to, cc: cc, bcc: bcc, subject: subject, bodyHtml: bodyHtml, inReplyTo: inReplyTo, saveSentCopy: saveSentCopy, attachments: attachments, importance: importance, sensitivity: sensitivity,
        from: from,
        mimeTransform: _smime.senderFor(account.id, sensitivity, [for (final a in [...to, ...cc, ...bcc]) a.email]));
    return true;
  }

  @override
  Future<void> setRead(AccountModel account, {required String emailId, required String folderId, required bool isRead}) =>
      _ews.markAsRead(account, emailId: emailId, isRead: isRead);
  @override
  Future<void> setFlag(AccountModel account, {required String emailId, required String folderId, required bool isFlagged}) =>
      _ews.flagEmail(account, emailId: emailId, isFlagged: isFlagged);
  @override
  Future<String?> move(AccountModel account, {required String emailId, required String fromFolderId, required String toFolderId}) =>
      _ews.moveEmail(account, emailId: emailId, targetFolderId: toFolderId);
  @override
  Future<void> delete(AccountModel account, {required String emailId, required String folderId, bool hard = false}) =>
      _ews.deleteEmail(account, emailId: emailId, hardDelete: hard);
}

// ─────────────────────────── IMAP ───────────────────────────
class ImapTransport implements MailTransport {
  final ImapService _imap;
  final SmimeService _smime;
  ImapTransport(this._imap, this._smime);

  @override
  Future<bool> send(AccountModel account, {required List<EmailAddress> to, List<EmailAddress> cc = const [], List<EmailAddress> bcc = const [], required String subject, required String bodyHtml, String? inReplyTo, bool saveSentCopy = true, List<({String name, String? contentType, Uint8List bytes})> attachments = const [], String importance = 'Normal', String sensitivity = 'Normal', String? clientId, EmailAddress? from}) async {
    await _imap.sendEmail(account, to: to, cc: cc, bcc: bcc, subject: subject, bodyHtml: bodyHtml, inReplyTo: inReplyTo, attachments: attachments, importance: importance, sensitivity: sensitivity,
        from: from,
        mimeTransform: _smime.senderFor(account.id, sensitivity, [for (final a in [...to, ...cc, ...bcc]) a.email]));
    return true;
  }

  @override
  Future<void> setRead(AccountModel account, {required String emailId, required String folderId, required bool isRead}) =>
      _imap.markAsRead(account, folderId: folderId, uid: emailId, isRead: isRead);
  @override
  Future<void> setFlag(AccountModel account, {required String emailId, required String folderId, required bool isFlagged}) =>
      _imap.flagEmail(account, folderId: folderId, uid: emailId, isFlagged: isFlagged);
  @override
  Future<String?> move(AccountModel account, {required String emailId, required String fromFolderId, required String toFolderId}) async {
    await _imap.moveEmail(account, fromFolderId: fromFolderId, toFolderId: toFolderId, uid: emailId);
    return null;
  }
  @override
  Future<void> delete(AccountModel account, {required String emailId, required String folderId, bool hard = false}) =>
      _imap.deleteEmail(account, folderId: folderId, uid: emailId, hard: hard);
}

// ─────────────────────────── Единый движок (mail_engine) ───────────────────────────
class EngineTransport implements MailTransport {
  final MailEngineService _engine;
  // ignore: unused_field
  final AccountModel _account;
  EngineTransport(this._engine, this._account);

  @override
  Future<bool> send(AccountModel account, {required List<EmailAddress> to, List<EmailAddress> cc = const [], List<EmailAddress> bcc = const [], required String subject, required String bodyHtml, String? inReplyTo, bool saveSentCopy = true, List<({String name, String? contentType, Uint8List bytes})> attachments = const [], String importance = 'Normal', String sensitivity = 'Normal', String? clientId, EmailAddress? from}) =>
      _engine.send(account,
          to: to,
          cc: cc,
          bcc: bcc,
          subject: subject,
          bodyHtml: bodyHtml,
          attachments: attachments,
          inReplyTo: inReplyTo,
          importance: importance,
          sensitivity: sensitivity,
          clientId: clientId,
          from: from);

  @override
  Future<void> setRead(AccountModel account, {required String emailId, required String folderId, required bool isRead}) =>
      _engine.setRead(account, folderId: folderId, serverId: emailId, isRead: isRead);
  @override
  Future<void> setFlag(AccountModel account, {required String emailId, required String folderId, required bool isFlagged}) =>
      _engine.setFlag(account, folderId: folderId, serverId: emailId, isFlagged: isFlagged);
  @override
  Future<String?> move(AccountModel account, {required String emailId, required String fromFolderId, required String toFolderId}) async {
    await _engine.moveMessage(account, fromFolderId: fromFolderId, serverId: emailId, toFolderId: toFolderId);
    return null;
  }
  @override
  Future<void> delete(AccountModel account, {required String emailId, required String folderId, bool hard = false}) =>
      _engine.deleteMessage(account, folderId: folderId, serverId: emailId);
}

// ─────────────────────────── Фабрика ───────────────────────────
class MailTransportFactory {
  final Ref _ref;
  MailTransportFactory(this._ref);

  /// Выбрать транспорт по типу аккаунта — единая точка маршрутизации.
  /// EAS-аккаунты обслуживает единый движок mail_engine; остальные — пока прежние сервисы.
  MailTransport forAccount(AccountModel account) {
    if (account.usesEas) {
      return EngineTransport(_ref.read(mailEngineServiceProvider), account);
    } else if (account.usesEws || account.isExchange) {
      return EwsTransport(_ref.read(ewsServiceProvider), _ref.read(smimeServiceProvider));
    } else {
      return ImapTransport(_ref.read(imapServiceProvider), _ref.read(smimeServiceProvider));
    }
  }
}

final mailTransportFactoryProvider = Provider<MailTransportFactory>((ref) {
  return MailTransportFactory(ref);
});
