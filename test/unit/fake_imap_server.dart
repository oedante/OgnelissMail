// test/unit/fake_imap_server.dart
// Поддельный IMAP-сервер для тестов (1.9.x, просьба владельца 31.10.2026):
// по локальному сокету, как сервер «как Яндекс» в
// smtp_yandex_xoauth2_test.dart. Умеет ровно то, что нужно синхронизации
// и push: LOGIN, CAPABILITY, ENABLE, LIST, SELECT (CONDSTORE, QRESYNC),
// FETCH / UID FETCH (CHANGEDSINCE), UID SEARCH (ESEARCH), IDLE, NOTIFY.
// Возможности — строкой CAPABILITY, как у настоящего сервера.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeMessage {
  FakeMessage(this.uid, this.subject, this.flags, this.modSeq);
  final int uid;
  final String subject;
  Set<String> flags;
  int modSeq;
}

class FakeMailbox {
  FakeMailbox(this.name, {this.uidValidity = 1000});
  final String name;
  int uidValidity;
  int uidNext = 1;
  int highestModSeq = 1;
  final messages = <FakeMessage>[];

  /// UID → MODSEQ удаления (для VANISHED).
  final expunged = <int, int>{};

  FakeMessage add(String subject, {Set<String>? flags}) {
    final m = FakeMessage(uidNext++, subject, {...?flags}, ++highestModSeq);
    messages.add(m);
    return m;
  }

  void setFlags(int uid, Set<String> flags) {
    final m = messages.firstWhere((m) => m.uid == uid);
    m.flags = {...flags};
    m.modSeq = ++highestModSeq;
  }

  void expunge(int uid) {
    messages.removeWhere((m) => m.uid == uid);
    expunged[uid] = ++highestModSeq;
  }
}

class FakeImapServer {
  FakeImapServer({
    this.caps = 'IMAP4rev1 IDLE',
    this.greetingCaps = 'IMAP4rev1 LITERAL+ AUTH=PLAIN',
    this.capsAtLogin = false,
  });

  /// Возможности после входа (ответ на CAPABILITY).
  String caps;

  /// Возможности в приветствии (до входа).
  final String greetingCaps;

  /// Присылать полный список возможностей в ответе на вход.
  final bool capsAtLogin;

  final boxes = <String, FakeMailbox>{};

  /// Команды клиента без метки, по порядку.
  final commands = <String>[];

  /// На команду, содержащую одну из строк, — BAD (сбой сервера).
  final failOn = <String>{};

  /// Отклонять NOTIFY SET (NO [BADEVENT]).
  bool rejectNotify = false;

  ServerSocket? _server;
  final _conns = <_Conn>[];

  int get port => _server!.port;

  bool get _modSeq => caps.split(' ').any((c) => c == 'CONDSTORE' || c == 'QRESYNC');

  FakeMailbox box(String name, {int uidValidity = 1000}) =>
      boxes[name] = FakeMailbox(name, uidValidity: uidValidity);

  Future<void> start() async {
    final server = _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => _conns.add(_Conn(this, s)..start()));
  }

  Future<void> close() async {
    for (final c in _conns) {
      c.socket.destroy();
    }
    await _server?.close();
  }

  /// Строка без метки соединениям, ждущим в IDLE (EXISTS, STATUS по NOTIFY).
  void pushToIdle(String line) {
    for (final c in _conns) {
      if (c.idleTag != null) c.write(line);
    }
  }

  bool get anyIdle => _conns.any((c) => c.idleTag != null);

  Future<void> waitIdle() => waitFor(() => anyIdle);
}

/// Подождать условия (не дольше 5 с).
Future<void> waitFor(bool Function() ok, {Duration limit = const Duration(seconds: 5)}) async {
  final until = DateTime.now().add(limit);
  while (!ok()) {
    if (DateTime.now().isAfter(until)) throw TimeoutException('условие не выполнилось', limit);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Conn {
  _Conn(this.srv, this.socket);
  final FakeImapServer srv;
  final Socket socket;
  var _buf = '';
  FakeMailbox? _selected;
  var _condStore = false;
  var _qresync = false;
  String? idleTag;

  void write(String s) {
    try {
      socket.write('$s\r\n');
    } catch (_) {}
  }

  void _ok(String tag, [String text = 'completed']) => write('$tag OK $text');

  void start() {
    write('* OK [CAPABILITY ${srv.greetingCaps}] Fake IMAP ready');
    socket.listen((data) {
      _buf += utf8.decode(data);
      while (true) {
        final i = _buf.indexOf('\r\n');
        if (i < 0) break;
        final line = _buf.substring(0, i);
        _buf = _buf.substring(i + 2);
        _handle(line);
      }
    }, onError: (_) {}, onDone: () {});
  }

  void _handle(String line) {
    final tag0 = idleTag;
    if (tag0 != null) {
      if (line.toUpperCase() == 'DONE') {
        idleTag = null;
        _ok(tag0, 'IDLE terminated');
      }
      return;
    }
    final sp = line.indexOf(' ');
    if (sp < 0) return;
    final tag = line.substring(0, sp);
    final cmd = line.substring(sp + 1);
    srv.commands.add(cmd);
    if (srv.failOn.any(cmd.contains)) {
      write('$tag BAD injected failure');
      return;
    }
    final upper = cmd.toUpperCase();
    if (upper == 'CAPABILITY') {
      write('* CAPABILITY ${srv.caps}');
      _ok(tag);
    } else if (upper.startsWith('LOGIN ')) {
      if (srv.capsAtLogin) write('* CAPABILITY ${srv.caps}');
      _ok(tag, 'Logged in');
    } else if (upper.startsWith('ENABLE ')) {
      final have = srv.caps.toUpperCase().split(' ');
      final on = [
        for (final w in cmd.substring(7).toUpperCase().split(' '))
          if (have.contains(w)) w,
      ];
      if (on.contains('QRESYNC')) _qresync = _condStore = true;
      write(on.isEmpty ? '* ENABLED' : '* ENABLED ${on.join(' ')}');
      _ok(tag);
    } else if (upper.startsWith('LIST ')) {
      for (final b in srv.boxes.values) {
        write('* LIST () "/" "${b.name}"');
      }
      _ok(tag);
    } else if (upper.startsWith('SELECT ')) {
      _select(tag, cmd);
    } else if (upper.startsWith('UID FETCH ')) {
      _fetch(tag, cmd.substring('UID FETCH '.length), uid: true);
    } else if (upper.startsWith('FETCH ')) {
      _fetch(tag, cmd.substring('FETCH '.length), uid: false);
    } else if (upper.startsWith('UID SEARCH ')) {
      _search(tag, cmd.substring('UID SEARCH '.length));
    } else if (upper == 'NOOP') {
      _ok(tag);
    } else if (upper == 'IDLE') {
      idleTag = tag;
      write('+ idling');
    } else if (upper.startsWith('NOTIFY ')) {
      if (srv.rejectNotify) {
        write('$tag NO [BADEVENT (MessageNew MessageExpunge)] not supported');
      } else {
        _ok(tag, 'NOTIFY completed');
      }
    } else if (upper == 'LOGOUT') {
      write('* BYE logging out');
      _ok(tag);
      socket.destroy();
    } else {
      write('$tag BAD unknown command');
    }
  }

  void _select(String tag, String cmd) {
    final m = RegExp(r'^SELECT "([^"]*)"(?: \((.*)\))?$', caseSensitive: false).firstMatch(cmd);
    final b = m == null ? null : srv.boxes[m.group(1)];
    if (b == null) {
      write('$tag NO no such mailbox');
      return;
    }
    final params = m!.group(2) ?? '';
    if (params.toUpperCase().contains('CONDSTORE')) _condStore = true;
    final q = RegExp(r'QRESYNC \((\d+) (\d+)(?: ([0-9:,*]+))?\)', caseSensitive: false).firstMatch(params);
    if (q != null && !_qresync) {
      write('$tag BAD QRESYNC is not enabled');
      return;
    }
    _selected = b;
    write(r'* FLAGS (\Seen \Flagged \Deleted)');
    write('* ${b.messages.length} EXISTS');
    write('* 0 RECENT');
    write('* OK [UIDVALIDITY ${b.uidValidity}] UIDs valid');
    write('* OK [UIDNEXT ${b.uidNext}] Predicted next UID');
    if (srv._modSeq) write('* OK [HIGHESTMODSEQ ${b.highestModSeq}] Highest');
    // RFC 7162, 3.2.5: другой UIDVALIDITY — параметры QRESYNC не действуют.
    if (q != null && int.parse(q.group(1)!) == b.uidValidity) {
      final since = int.parse(q.group(2)!);
      final known = q.group(3) == null ? null : _parseSet(q.group(3)!);
      final star = b.uidNext - 1;
      bool inKnown(int uid) => known == null || _contains(known, uid, star);
      final gone = [
        for (final e in b.expunged.entries)
          if (e.value > since && inKnown(e.key)) e.key,
      ]..sort();
      if (gone.isNotEmpty) write('* VANISHED (EARLIER) ${_compact(gone)}');
      for (var i = 0; i < b.messages.length; i++) {
        final msg = b.messages[i];
        if (msg.modSeq > since && inKnown(msg.uid)) {
          write('* ${i + 1} FETCH (UID ${msg.uid} FLAGS (${msg.flags.join(' ')}) MODSEQ (${msg.modSeq}))');
        }
      }
    }
    _ok(tag, '[READ-WRITE] SELECT completed');
  }

  void _fetch(String tag, String args, {required bool uid}) {
    final b = _selected;
    if (b == null) {
      write('$tag BAD no mailbox selected');
      return;
    }
    final sp = args.indexOf(' ');
    final set = _parseSet(args.substring(0, sp));
    var rest = args.substring(sp + 1);
    int? since;
    final cs = RegExp(r' \(CHANGEDSINCE (\d+)\)$', caseSensitive: false).firstMatch(rest);
    if (cs != null) {
      since = int.parse(cs.group(1)!);
      rest = rest.substring(0, cs.start);
      _condStore = true;
    }
    final items = rest.toUpperCase();
    final star = uid ? (b.messages.isEmpty ? 0 : b.messages.last.uid) : b.messages.length;
    for (var i = 0; i < b.messages.length; i++) {
      final m = b.messages[i];
      if (!_contains(set, uid ? m.uid : i + 1, star)) continue;
      if (since != null && m.modSeq <= since) continue;
      final parts = <String>[
        'UID ${m.uid}',
        if (items.contains('FLAGS')) 'FLAGS (${m.flags.join(' ')})',
        if (_condStore) 'MODSEQ (${m.modSeq})',
        if (items.contains('RFC822.SIZE')) 'RFC822.SIZE 100',
        if (items.contains('ENVELOPE'))
          'ENVELOPE ("Mon, 26 Oct 2026 10:00:00 +0000" "${m.subject}" (("Anna" NIL "anna" "example.com")) '
              '(("Anna" NIL "anna" "example.com")) (("Anna" NIL "anna" "example.com")) '
              '(("Me" NIL "me" "example.com")) NIL NIL NIL "<${m.uid}@example.com>")',
      ];
      write('* ${i + 1} FETCH (${parts.join(' ')})');
    }
    _ok(tag, 'FETCH completed');
  }

  void _search(String tag, String args) {
    final b = _selected;
    if (b == null) {
      write('$tag BAD no mailbox selected');
      return;
    }
    var crit = args;
    final extended = crit.toUpperCase().startsWith('RETURN (');
    if (extended) crit = crit.substring(crit.indexOf(')') + 2);
    final m = RegExp(r'^UID ([0-9:,*]+)$', caseSensitive: false).firstMatch(crit);
    final star = b.messages.isEmpty ? 0 : b.messages.last.uid;
    final set = m == null ? null : _parseSet(m.group(1)!);
    final uids = [
      for (final x in b.messages)
        if (set != null && _contains(set, x.uid, star)) x.uid,
    ];
    if (extended) {
      write('* ESEARCH (TAG "$tag") UID${uids.isEmpty ? '' : ' ALL ${_compact(uids)}'}');
    } else {
      write('* SEARCH${uids.map((u) => ' $u').join()}');
    }
    _ok(tag, 'SEARCH completed');
  }

  /// Набор «1:5,7,9:*» — пары (от, до); 0 — «*».
  static List<(int, int)> _parseSet(String s) => [
        for (final part in s.split(','))
          if (part.contains(':'))
            (_num(part.substring(0, part.indexOf(':'))), _num(part.substring(part.indexOf(':') + 1)))
          else
            (_num(part), _num(part)),
      ];

  static int _num(String s) => s == '*' ? 0 : int.parse(s);

  static bool _contains(List<(int, int)> set, int v, int star) {
    for (final (a0, b0) in set) {
      final a = a0 == 0 ? star : a0;
      final b = b0 == 0 ? star : b0;
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      if (v >= lo && v <= hi) return true;
    }
    return false;
  }

  static String _compact(List<int> ids) {
    final out = <String>[];
    var i = 0;
    while (i < ids.length) {
      var j = i;
      while (j + 1 < ids.length && ids[j + 1] == ids[j] + 1) {
        j++;
      }
      out.add(i == j ? '${ids[i]}' : '${ids[i]}:${ids[j]}');
      i = j + 1;
    }
    return out.join(',');
  }
}
