// lib/services/integration/mailto_service.dart
// «Написать письмо» из других приложений: ссылки mailto (RFC 6068) и
// ACTION_SENDTO на Android. Намерение разбирает MailtoBridge.kt и передаёт
// ссылку по каналу ogneliss/mailto; здесь она превращается в параметры
// экрана нового письма: «Кому», «Копия», «Скрытая», тема и текст (текст
// встаёт между приветствием и подписью).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../core/utils/charset_handler.dart';

import '../../core/logging/app_logger.dart';

class MailtoRequest {
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String? subject;
  final String? body;

  const MailtoRequest({this.to = const [], this.cc = const [], this.bcc = const [], this.subject, this.body});

  bool get isEmpty => to.isEmpty && cc.isEmpty && bcc.isEmpty && (subject ?? '').isEmpty && (body ?? '').isEmpty;

  /// Параметры маршрута /compose.
  Map<String, String> toQuery() => {
        if (to.isNotEmpty) 'to': to.join(','),
        if (cc.isNotEmpty) 'cc': cc.join(','),
        if (bcc.isNotEmpty) 'bcc': bcc.join(','),
        if ((subject ?? '').isNotEmpty) 'subject': subject!,
        if ((body ?? '').isNotEmpty) 'quick': body!,
      };

  static String _dec(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      // Не UTF-8: старые русские сайты кодируют ссылку в windows-1251
      // («%C5%F0%EC…»). Раньше текст оставался с процентами (1.6.33).
      try {
        final bytes = <int>[];
        for (var i = 0; i < s.length; i++) {
          final c = s.codeUnitAt(i);
          if (c == 0x25 && i + 2 < s.length) {
            final b = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
            if (b != null) {
              bytes.add(b);
              i += 2;
              continue;
            }
          }
          if (c > 0x7F) return s;
          bytes.add(c);
        }
        return CharsetHandler.decode(Uint8List.fromList(bytes), 'windows-1251');
      } catch (_) {
        return s;
      }
    }
  }

  static List<String> _addrs(String s) => [
        for (final a in _dec(s).split(RegExp(r'[,;]')))
          if (a.trim().contains('@')) a.trim(),
      ];

  /// Разобрать ссылку mailto:кому?cc=…&subject=…&body=…
  static MailtoRequest? parse(String? link) {
    if (link == null) return null;
    var s = link.trim();
    if (!s.toLowerCase().startsWith('mailto:')) return null;
    s = s.substring(7);
    final q = s.indexOf('?');
    final path = q < 0 ? s : s.substring(0, q);
    final to = _addrs(path);
    final cc = <String>[];
    final bcc = <String>[];
    String? subject;
    String? body;
    if (q >= 0) {
      for (final pair in s.substring(q + 1).split('&')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final k = pair.substring(0, eq).toLowerCase();
        final v = pair.substring(eq + 1);
        switch (k) {
          case 'to':
            to.addAll(_addrs(v));
          case 'cc':
            cc.addAll(_addrs(v));
          case 'bcc':
            bcc.addAll(_addrs(v));
          case 'subject':
            subject = _dec(v);
          case 'body':
            body = _dec(v);
        }
      }
    }
    final r = MailtoRequest(to: to, cc: cc, bcc: bcc, subject: subject, body: body);
    return r.isEmpty ? null : r;
  }
}

class MailtoService {
  MailtoService._();

  static const _channel = MethodChannel('ogneliss/mailto');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Слушать новые ссылки и забрать ту, с которой приложение запущено.
  static Future<void> init(void Function(MailtoRequest r) onRequest) async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        final r = await take();
        if (r != null) onRequest(r);
      }
      return null;
    });
    final first = await take();
    if (first != null) onRequest(first);
  }

  static Future<MailtoRequest?> take() async {
    if (!_supported) return null;
    try {
      final link = await _channel.invokeMethod<String>('take');
      final r = MailtoRequest.parse(link);
      if (r != null) {
        // Без адресов и текста — только что пришло и в каком виде.
        AppLogger.info('Ссылка mailto: кому ${r.to.length}, копия ${r.cc.length + r.bcc.length}, '
            'тема ${(r.subject ?? '').isNotEmpty ? 'есть' : 'нет'}, текст ${r.body?.length ?? 0} симв., '
            'имена в адресах: ${r.to.any((a) => a.contains('<')) ? 'да' : 'нет'}'
            '${link != null && link.contains('%') && !link.toUpperCase().contains('%D0') && !link.toUpperCase().contains('%D1') && RegExp(r'%[C-F][0-9A-F]', caseSensitive: false).hasMatch(link) ? ', кодировка windows-1251' : ''}');
      }
      return r;
    } catch (e) {
      AppLogger.debug('mailto: $e');
      return null;
    }
  }

  /// Адресаты и тема, пришедшие вместе с «Поделиться».
  static Future<MailtoRequest?> takeShare() async {
    if (!_supported) return null;
    try {
      return MailtoRequest.parse(await _channel.invokeMethod<String>('takeShare'));
    } catch (_) {
      return null;
    }
  }
}
