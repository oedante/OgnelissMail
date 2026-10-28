// lib/services/mail/sieve/sieve_rules.dart
// Правила Ogneliss в скрипте Sieve: модель, сборка и разбор.
//
// Правила хранятся в активном скрипте ящика ОТДЕЛЬНЫМ БЛОКОМ между строками
// «# ogneliss:begin» и «# ogneliss:end»; каждое — строкой-описанием
// («# ogneliss:rule {…}», по ней правило читается обратно) и командой Sieve.
// Остальное содержимое скрипта (правила из веб-почты, от администратора)
// не меняется. Наш «require» — первой строкой с пометкой «# ogneliss:require»
// (в Sieve require должен идти до остальных команд).

import 'dart:convert';

/// Что проверяется.
enum SieveField { from, to, subject, any }

/// Как сравнивается.
enum SieveOp { contains, isExactly }

/// Что сделать.
enum SieveAction { move, markRead, flag, delete, forward }

class SieveRule {
  final String name;
  final bool enabled;
  final SieveField field;
  final SieveOp op;
  final String value;
  final SieveAction action;

  /// Папка (для move, UTF-8 путь с разделителем сервера) или адрес (forward).
  final String arg;

  /// Не применять следующие правила (stop).
  final bool stop;

  const SieveRule({
    required this.name,
    this.enabled = true,
    required this.field,
    this.op = SieveOp.contains,
    required this.value,
    required this.action,
    this.arg = '',
    this.stop = false,
  });

  SieveRule copyWith({
    String? name,
    bool? enabled,
    SieveField? field,
    SieveOp? op,
    String? value,
    SieveAction? action,
    String? arg,
    bool? stop,
  }) =>
      SieveRule(
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        field: field ?? this.field,
        op: op ?? this.op,
        value: value ?? this.value,
        action: action ?? this.action,
        arg: arg ?? this.arg,
        stop: stop ?? this.stop,
      );

  Map<String, Object> toJson() => {
        'name': name,
        'on': enabled,
        'field': field.name,
        'op': op.name,
        'value': value,
        'action': action.name,
        'arg': arg,
        'stop': stop,
      };

  static SieveRule? fromJson(Map<String, dynamic> j) {
    T? byName<T extends Enum>(List<T> values, Object? n) => values.where((v) => v.name == n).firstOrNull;
    final field = byName(SieveField.values, j['field']);
    final action = byName(SieveAction.values, j['action']);
    if (field == null || action == null) return null;
    return SieveRule(
      name: j['name'] as String? ?? '',
      enabled: j['on'] as bool? ?? true,
      field: field,
      op: byName(SieveOp.values, j['op']) ?? SieveOp.contains,
      value: j['value'] as String? ?? '',
      action: action,
      arg: j['arg'] as String? ?? '',
      stop: j['stop'] as bool? ?? false,
    );
  }

  /// Правило можно записать: есть что искать и, где нужно, куда/кому.
  bool get isValid =>
      value.trim().isNotEmpty &&
      ((action != SieveAction.move && action != SieveAction.forward) || arg.trim().isNotEmpty) &&
      (action != SieveAction.forward || arg.contains('@'));
}

/// Разобранный скрипт: наши правила и всё остальное.
class SieveScriptParts {
  final List<SieveRule> rules;

  /// Содержимое скрипта без нашего блока и нашего require.
  final String foreign;

  const SieveScriptParts(this.rules, this.foreign);

  /// В скрипте есть чужие правила (не только комментарии и require).
  bool get hasForeignRules {
    var inRequire = false;
    for (final raw in foreign.split('\n')) {
      final l = raw.trim();
      if (inRequire) {
        if (l.contains(';')) inRequire = false;
        continue;
      }
      if (l.isEmpty || l.startsWith('#')) continue;
      if (l.startsWith('require')) {
        inRequire = !l.contains(';');
        continue;
      }
      return true;
    }
    return false;
  }
}

class SieveRules {
  SieveRules._();

  static const _begin = '# ogneliss:begin';
  static const _end = '# ogneliss:end';
  static const _rulePrefix = '# ogneliss:rule ';
  static const _requireMark = '# ogneliss:require';

  /// Имя скрипта, если активного на сервере нет.
  static const defaultScriptName = 'ogneliss';

  static String quote(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  /// Разобрать скрипт.
  static SieveScriptParts parse(String script) {
    final rules = <SieveRule>[];
    final foreign = StringBuffer();
    var inBlock = false;
    for (final raw in const LineSplitter().convert(script)) {
      final l = raw.trim();
      if (l == _begin) {
        inBlock = true;
        continue;
      }
      if (l == _end) {
        inBlock = false;
        continue;
      }
      if (inBlock) {
        if (l.startsWith(_rulePrefix)) {
          try {
            final r = SieveRule.fromJson(jsonDecode(l.substring(_rulePrefix.length)) as Map<String, dynamic>);
            if (r != null) rules.add(r);
          } catch (_) {}
        }
        continue;
      }
      if (l.endsWith(_requireMark)) continue;
      foreign.writeln(raw);
    }
    return SieveScriptParts(rules, foreign.toString().trimRight());
  }

  /// Расширения, нужные нашим правилам (с учётом того, что есть на сервере).
  static List<String> requiredExtensions(List<SieveRule> rules, Set<String> server) {
    final need = <String>{};
    for (final r in rules.where((r) => r.enabled && r.isValid)) {
      switch (r.action) {
        case SieveAction.move:
          need.add('fileinto');
        case SieveAction.markRead:
        case SieveAction.flag:
          need.add('imap4flags');
        case SieveAction.forward:
          if (server.contains('copy')) need.add('copy');
        case SieveAction.delete:
          break;
      }
    }
    if (server.contains('comparator-i;unicode-casemap') && rules.any((r) => r.enabled)) {
      need.add('comparator-i;unicode-casemap');
    }
    return need.toList()..sort();
  }

  /// Команда Sieve для правила.
  static String command(SieveRule r, Set<String> server) {
    final cmp = server.contains('comparator-i;unicode-casemap') ? ' :comparator "i;unicode-casemap"' : '';
    final match = r.op == SieveOp.isExactly ? ':is' : ':contains';
    final headers = switch (r.field) {
      SieveField.from => '"from"',
      SieveField.to => '["to", "cc"]',
      SieveField.subject => '"subject"',
      SieveField.any => '["from", "to", "cc", "subject"]',
    };
    final test = 'header $match$cmp $headers ${quote(r.value.trim())}';
    final actions = <String>[
      switch (r.action) {
        SieveAction.move => 'fileinto ${quote(r.arg.trim())};',
        SieveAction.markRead => 'addflag "\\\\Seen";',
        SieveAction.flag => 'addflag "\\\\Flagged";',
        SieveAction.delete => 'discard;',
        SieveAction.forward =>
          server.contains('copy') ? 'redirect :copy ${quote(r.arg.trim())};' : 'redirect ${quote(r.arg.trim())};',
      },
      if (r.stop || r.action == SieveAction.delete) 'stop;',
    ];
    return 'if $test {\n  ${actions.join('\n  ')}\n}';
  }

  /// Собрать скрипт: наш require, require и комментарии чужого начала,
  /// наш блок, остальное чужое.
  static String build(List<SieveRule> rules, String foreign, Set<String> server) {
    final req = requiredExtensions(rules, server);
    final block = StringBuffer()..writeln(_begin);
    for (final r in rules) {
      block.writeln('$_rulePrefix${jsonEncode(r.toJson())}');
      if (r.enabled && r.isValid) block.writeln(command(r, server));
    }
    block.write(_end);

    // Начало чужого скрипта: require (возможно, в несколько строк),
    // комментарии и пустые строки — до первой команды.
    final lines = const LineSplitter().convert(foreign);
    var i = 0;
    var inRequire = false;
    var inComment = false;
    while (i < lines.length) {
      final l = lines[i].trim();
      if (inComment) {
        if (l.contains('*/')) inComment = false;
        i++;
        continue;
      }
      if (inRequire) {
        if (l.contains(';')) inRequire = false;
        i++;
        continue;
      }
      if (l.isEmpty || l.startsWith('#')) {
        i++;
        continue;
      }
      if (l.startsWith('/*')) {
        inComment = !l.contains('*/');
        i++;
        continue;
      }
      if (l.startsWith('require')) {
        inRequire = !l.contains(';');
        i++;
        continue;
      }
      break;
    }
    final head = lines.take(i).join('\n').trimRight();
    final tail = lines.skip(i).join('\n').trim();

    final out = StringBuffer();
    if (req.isNotEmpty) {
      out.writeln('require [${req.map(quote).join(', ')}]; $_requireMark');
    }
    if (head.isNotEmpty) out.writeln(head);
    out.writeln(block.toString());
    if (tail.isNotEmpty) {
      out.writeln();
      out.writeln(tail);
    }
    return out.toString();
  }
}

/// Имя папки IMAP (modified UTF-7, RFC 3501) → UTF-8 для Sieve fileinto.
String decodeImapUtf7(String s) {
  if (!s.contains('&')) return s;
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c != '&') {
      out.write(c);
      i++;
      continue;
    }
    final end = s.indexOf('-', i + 1);
    if (end < 0) {
      out.write(s.substring(i));
      break;
    }
    if (end == i + 1) {
      out.write('&');
      i = end + 1;
      continue;
    }
    var b64 = s.substring(i + 1, end).replaceAll(',', '/');
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    try {
      final bytes = base64.decode(b64);
      final units = <int>[for (var k = 0; k + 1 < bytes.length; k += 2) (bytes[k] << 8) | bytes[k + 1]];
      out.write(String.fromCharCodes(units));
    } catch (_) {
      out.write(s.substring(i, end + 1));
    }
    i = end + 1;
  }
  return out.toString();
}
