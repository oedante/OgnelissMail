// packages/mail_engine/lib/src/transport/notify_imap_client.dart
// IMAP-клиент enough_mail с командой NOTIFY (RFC 5465; 1.9.x, просьба
// владельца 31.10.2026): одно соединение push узнаёт об изменениях во всех
// синхронизируемых папках, а не только во «Входящих».
//
// В enough_mail 2.1.7 команды NOTIFY нет, а классы команд и разборщики
// ответов лежат во внутренней части пакета (src/private) — их не трогаем и
// не подключаем. Используем только открытые методы клиента:
//  · writeText — команда пишется в сокет со своей меткой («ogn1 NOTIFY …»);
//  · onServerResponse — его переопределяем, как onServerResponse у
//    TolerantSmtpClient: ответ с нашей меткой завершает команду,
//    «* STATUS папка (…)» — изменение в другой папке, «* OK
//    [NOTIFICATIONOVERFLOW]» — сервер перестал сообщать об изменениях.
// Всё остальное разбирает enough_mail, как обычно. Пока NOTIFY не включён,
// клиент ничем не отличается от ImapClient.
//
// Команда идёт только на отдельном соединении push, где все команды
// последовательны (SELECT → NOTIFY → IDLE): очередь enough_mail в этот момент
// пуста, и ответы не перемешиваются.

import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as em;

/// Изменение, о котором сообщил сервер по NOTIFY.
class ImapNotifyChange {
  /// В папке [mailbox] (путь как в LIST) что-то изменилось.
  const ImapNotifyChange.mailbox(String this.mailbox) : overflow = false;

  /// Сервер не успевал сообщать и перестал (NOTIFICATIONOVERFLOW): нужно
  /// синхронизировать всё и включить NOTIFY заново.
  const ImapNotifyChange.overflow()
      : mailbox = null,
        overflow = true;

  /// Изменение в выбранной папке, о котором сервер сообщил в ответ на саму
  /// команду NOTIFY (она подразумевает NOOP): enough_mail такие строки не
  /// ждёт — без этого новое письмо осталось бы незамеченным до следующего цикла.
  const ImapNotifyChange.selected()
      : mailbox = null,
        overflow = false;

  final String? mailbox;
  final bool overflow;

  @override
  String toString() => overflow ? 'NOTIFICATIONOVERFLOW' : mailbox == null ? 'SELECTED' : 'STATUS $mailbox';
}

/// Сервер отклонил NOTIFY SET (NO или BAD).
class ImapNotifyRejected implements Exception {
  const ImapNotifyRejected(this.response);
  final String response;

  @override
  String toString() => 'NOTIFY отклонён сервером: $response';
}

class NotifyImapClient extends em.ImapClient {
  NotifyImapClient({
    super.isLogEnabled,
    super.logName,
    super.defaultWriteTimeout,
    super.defaultResponseTimeout,
    super.onBadCertificate,
  });

  static const capabilityNotify = 'NOTIFY';

  /// Больше папок — фильтр «personal» (все личные папки) вместо списка:
  /// строка команды не растёт без конца, а лишние события отсеет приложение.
  static const maxMailboxes = 100;

  /// Сервер назвал NOTIFY среди возможностей (после входа).
  bool get supportsNotify => serverInfo.supports(capabilityNotify);

  // Синхронный поток: событие доходит до слушателя сразу, в порядке ответов
  // сервера, а не после ответа на следующую команду.
  final _changes = StreamController<ImapNotifyChange>.broadcast(sync: true);

  /// Изменения в других папках (и переполнение) по NOTIFY.
  Stream<ImapNotifyChange> get notifyChanges => _changes.stream;

  bool _active = false;

  /// NOTIFY SET принят сервером на этом соединении.
  bool get notifyActive => _active;

  String? _tag;
  Completer<String>? _done;
  int _seq = 0;

  /// Включить уведомления: выбранная папка и [mailboxes] (пути как в LIST).
  /// [flagChanges] — и об изменении флагов. Отказ сервера —
  /// [ImapNotifyRejected], молчание дольше [timeout] — TimeoutException
  /// (соединение после этого лучше закрыть).
  Future<void> notifySet(List<String> mailboxes,
      {bool flagChanges = true, Duration timeout = const Duration(seconds: 30)}) async {
    final r = await _send(notifySetCommand(mailboxes, flagChanges: flagChanges), timeout);
    if (!r.toUpperCase().startsWith('OK')) throw ImapNotifyRejected(r);
    _active = true;
  }

  Future<String> _send(String command, Duration timeout) async {
    if (_done != null) throw StateError('NOTIFY: предыдущая команда ещё не завершена');
    final tag = 'ogn${++_seq}';
    final done = _done = Completer<String>();
    _tag = tag;
    try {
      await writeText('$tag $command', null, timeout);
      return await done.future.timeout(timeout);
    } finally {
      _tag = null;
      _done = null;
    }
  }

  // Тип параметра выводится из ImapClient (внутренний класс enough_mail, его
  // не подключаем): нужен только текст ответа parseText.
  @override
  void onServerResponse(imapResponse) {
    final text = imapResponse.parseText;
    final tag = _tag;
    if (tag != null && text.startsWith('$tag ')) {
      final done = _done;
      if (done != null && !done.isCompleted) done.complete(text.substring(tag.length + 1));
      return;
    }
    if (_active || tag != null) {
      final change = parseNotifyLine(text);
      if (change != null) {
        if (!_changes.isClosed) _changes.add(change);
        // STATUS другой папки enough_mail не ждёт — дальше не передаём;
        // «* OK […]» — передаём: это обычный ответ для него.
        if (!change.overflow) return;
      } else if (tag != null && _selectedChange.hasMatch(text) && !_changes.isClosed) {
        _changes.add(const ImapNotifyChange.selected());
      }
    }
    super.onServerResponse(imapResponse);
  }

  static final _selectedChange = RegExp(r'^\* \d+ (EXISTS|EXPUNGE|FETCH)\b', caseSensitive: false);

  /// Команда NOTIFY SET. Выбранная папка (её слушает IDLE) — фильтр
  /// SELECTED; остальные — MAILBOXES со списком или PERSONAL, если их много.
  /// MessageNew и MessageExpunge по RFC 5465 указываются вместе, FlagChange —
  /// только вместе с ними. Пути, которые нельзя записать строкой в кавычках
  /// (не ASCII, управляющие символы), пропускаются — эти папки обновит
  /// обычная синхронизация.
  static String notifySetCommand(List<String> mailboxes, {bool flagChanges = true}) {
    final events = flagChanges ? '(MessageNew MessageExpunge FlagChange)' : '(MessageNew MessageExpunge)';
    final names = [
      for (final m in mailboxes)
        if (_quotable(m)) '"${m.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"',
    ];
    final b = StringBuffer('NOTIFY SET (SELECTED $events)');
    if (names.length > maxMailboxes) {
      b.write(' (PERSONAL $events)');
    } else if (names.isNotEmpty) {
      b.write(' (MAILBOXES (${names.join(' ')}) $events)');
    }
    return b.toString();
  }

  static bool _quotable(String s) => s.isNotEmpty && s.codeUnits.every((c) => c >= 0x20 && c < 0x7f);

  /// Разбор строки ответа сервера: «* STATUS папка (…)» — изменение в папке,
  /// «* OK [NOTIFICATIONOVERFLOW]» — переполнение; остальное — null.
  static ImapNotifyChange? parseNotifyLine(String text) {
    if (!text.startsWith('* ')) return null;
    final t = text.substring(2);
    final upper = t.toUpperCase();
    if (upper.startsWith('OK [NOTIFICATIONOVERFLOW]')) return const ImapNotifyChange.overflow();
    if (!upper.startsWith('STATUS ')) return null;
    final rest = t.substring('STATUS '.length).trimLeft();
    String name;
    if (rest.startsWith('"')) {
      final b = StringBuffer();
      var i = 1;
      var closed = false;
      for (; i < rest.length; i++) {
        final c = rest[i];
        if (c == r'\' && i + 1 < rest.length) {
          b.write(rest[++i]);
        } else if (c == '"') {
          closed = true;
          break;
        } else {
          b.write(c);
        }
      }
      if (!closed) return null;
      name = b.toString();
    } else {
      final end = rest.indexOf(' ');
      name = end < 0 ? rest : rest.substring(0, end);
    }
    if (name.isEmpty || name.startsWith('(') || name.startsWith('{')) return null;
    return ImapNotifyChange.mailbox(name);
  }
}
