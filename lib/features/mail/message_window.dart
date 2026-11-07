// lib/features/mail/message_window.dart
//
// Письмо в отдельном окне — компьютер (Windows, macOS, Linux), 1.9.x, просьба
// владельца 31.10.2026. «Открыть в отдельном окне» в меню письма.
//
// Каждое окно desktop_multi_window (Apache-2.0) — свой движок Flutter: у
// него нет ни базы, ни провайдеров приложения, ни его плагинов (их пришлось
// бы регистрировать в нативном коде окна, а папки windows/, macos/, linux/
// создаёт сборка). Поэтому окно получает уже подготовленное письмо — шапку,
// очищенный HTML, встроенные картинки, список вложений — строкой JSON и
// только показывает его. Ответить, переслать, удалить, открыть ссылку или
// вложение — просит главное окно по каналу ([MessageWindow.channelName]);
// главное окно делает это у себя и выходит на передний план.
//
// iPad: отдельные окна (несколько сцен) — не сделаны. План (движок на окно
// из FlutterEngineGroup, та же строка письма) и шаги в Xcode —
// docs/guides/IPAD_WINDOWS.md; переход на сцены UIScene (шаг 0) уже сделан.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/desktop_mail_body.dart';

typedef MessageWindowPerson = ({String name, String email});

/// Письмо для отдельного окна — всё, что окну нужно без базы приложения.
class MessageWindowPayload {
  final String accountId;
  final String emailId;
  final String folderId;
  final String subject;
  final MessageWindowPerson from;
  final List<MessageWindowPerson> to;
  final List<MessageWindowPerson> cc;
  final DateTime? date;

  /// Уже очищенный HTML (как в панели письма; внешние картинки — как там).
  final String html;

  /// Встроенные картинки: Content-ID → data URI.
  final Map<String, String> images;
  final List<({String id, String name, int size})> attachments;
  final bool dark;
  final String locale;

  const MessageWindowPayload({
    required this.accountId,
    required this.emailId,
    required this.folderId,
    required this.subject,
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.date,
    required this.html,
    this.images = const {},
    this.attachments = const [],
    this.dark = false,
    this.locale = 'ru',
  });

  static Map<String, String> _p(MessageWindowPerson p) => {'name': p.name, 'email': p.email};
  static MessageWindowPerson _person(Object? m) {
    final x = (m as Map?) ?? const {};
    return (name: '${x['name'] ?? ''}', email: '${x['email'] ?? ''}');
  }

  Map<String, Object?> toJson() => {
        'kind': MessageWindow.kind,
        'accountId': accountId,
        'emailId': emailId,
        'folderId': folderId,
        'subject': subject,
        'from': _p(from),
        'to': [for (final p in to) _p(p)],
        'cc': [for (final p in cc) _p(p)],
        'date': date?.toIso8601String(),
        'html': html,
        'images': images,
        'attachments': [
          for (final a in attachments) {'id': a.id, 'name': a.name, 'size': a.size},
        ],
        'dark': dark,
        'locale': locale,
      };

  /// null — это не письмо для окна (другие аргументы, повреждённая строка).
  static MessageWindowPayload? fromJson(Object? json) {
    if (json is! Map || json['kind'] != MessageWindow.kind) return null;
    try {
      return MessageWindowPayload(
        accountId: '${json['accountId']}',
        emailId: '${json['emailId']}',
        folderId: '${json['folderId'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        from: _person(json['from']),
        to: [for (final p in (json['to'] as List? ?? const [])) _person(p)],
        cc: [for (final p in (json['cc'] as List? ?? const [])) _person(p)],
        date: DateTime.tryParse('${json['date'] ?? ''}'),
        html: '${json['html'] ?? ''}',
        images: {for (final e in ((json['images'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        attachments: [
          for (final a in (json['attachments'] as List? ?? const []))
            if (a is Map) (id: '${a['id']}', name: '${a['name'] ?? ''}', size: (a['size'] as num?)?.toInt() ?? 0),
        ],
        dark: json['dark'] == true,
        locale: '${json['locale'] ?? 'ru'}',
      );
    } catch (_) {
      return null;
    }
  }
}

abstract final class MessageWindow {
  static const kind = 'ogneliss-message';
  static const channelName = 'ogneliss_mail_main';

  /// Окна писем просят главное окно (оно одно принимает).
  static const _channel = WindowMethodChannel(channelName, mode: ChannelMode.unidirectional);

  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// В main(): этот движок — окно письма? Тогда — его письмо, иначе null.
  static Future<MessageWindowPayload?> payloadOfThisEngine() async {
    if (!supported) return null;
    try {
      final c = await WindowController.fromCurrentEngine();
      if (c.arguments.isEmpty) return null;
      return MessageWindowPayload.fromJson(jsonDecode(c.arguments));
    } catch (_) {
      return null;
    }
  }

  /// Открыть письмо [p] в новом окне.
  static Future<void> open(MessageWindowPayload p) async {
    final c = await WindowController.create(WindowConfiguration(arguments: jsonEncode(p.toJson())));
    await c.show();
  }

  /// Главное окно: просьбы окон писем — в [onAction] (method: reply,
  /// replyAll, forward, delete, openLink, openAttachment, open).
  static Future<void> serve(Future<void> Function(String method, Map<String, Object?> args) onAction) async {
    if (!supported) return;
    try {
      await _channel.setMethodCallHandler((call) async {
        final args = <String, Object?>{
          for (final e in ((call.arguments as Map?) ?? const {}).entries) '${e.key}': e.value,
        };
        await onAction(call.method, args);
        return true;
      });
    } catch (_) {
      // Плагина нет (сборка без окон) — окна писем просто не открываются.
    }
  }

  /// Окно письма → главное окно.
  static Future<void> ask(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<Object?>(method, args);
    } catch (_) {}
  }
}

/// Приложение окна письма: только показ, без базы и провайдеров.
class MessageWindowApp extends StatelessWidget {
  final MessageWindowPayload payload;
  const MessageWindowApp({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(1.0),
      darkTheme: AppTheme.darkTheme(1.0),
      themeMode: payload.dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(payload.locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MessageWindowScreen(payload: payload),
    );
  }
}

class MessageWindowScreen extends StatelessWidget {
  final MessageWindowPayload payload;

  /// Куда уходят просьбы (в тестах — подмена).
  final Future<void> Function(String method, Map<String, Object?> args) ask;

  const MessageWindowScreen({super.key, required this.payload, this.ask = MessageWindow.ask});

  Map<String, Object?> get _ids => {
        'accountId': payload.accountId,
        'emailId': payload.emailId,
        'folderId': payload.folderId,
      };

  static String _who(MessageWindowPerson p) => p.name.trim().isNotEmpty ? p.name.trim() : p.email;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final loc = MaterialLocalizations.of(context);
    final d = payload.date?.toLocal();
    final when = d == null ? '' : '${loc.formatMediumDate(d)}, ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
    Widget action(IconData icon, String tip, String method) =>
        IconButton(tooltip: tip, icon: Icon(icon), onPressed: () => unawaited(ask(method, _ids)));
    return Scaffold(
      appBar: AppBar(
        title: Text(payload.subject.isEmpty ? l10n.tr('noSubject') : payload.subject,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          action(AppIcons.reply, l10n.tr('reply'), 'reply'),
          action(AppIcons.reply_all, l10n.tr('replyAll'), 'replyAll'),
          action(AppIcons.forward, l10n.tr('forward'), 'forward'),
          action(AppIcons.open_in_new, l10n.tr('openInMainWindow'), 'open'),
          IconButton(
            tooltip: l10n.delete,
            icon: Icon(AppIcons.delete, color: theme.colorScheme.error),
            onPressed: () async {
              await ask('delete', _ids);
              // Письма больше нет — и окну незачем быть.
              if (context.mounted) await WindowController.fromCurrentEngine().then((c) => c.hide()).catchError((_) {});
            },
          ),
          const SizedBox(width: Space.s),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xl),
          children: [
            Text(_who(payload.from), style: theme.textTheme.titleMedium),
            if (payload.from.name.trim().isNotEmpty) Text(payload.from.email, style: muted),
            const SizedBox(height: Space.xs),
            if (payload.to.isNotEmpty)
              Text('${l10n.tr('to')}: ${payload.to.map(_who).join(', ')}', style: muted),
            if (payload.cc.isNotEmpty)
              Text('${l10n.tr('cc')}: ${payload.cc.map(_who).join(', ')}', style: muted),
            if (when.isNotEmpty) Text(when, style: muted),
            if (payload.attachments.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final a in payload.attachments)
                  ActionChip(
                    avatar: const Icon(AppIcons.attach_file, size: 18),
                    label: Text(a.name),
                    onPressed: () => unawaited(ask('openAttachment', {..._ids, 'attachmentId': a.id})),
                  ),
              ]),
            ],
            const Divider(height: Space.xl),
            DesktopMailBody(
              html: payload.html,
              images: payload.images,
              onLink: (url, text) => unawaited(ask('openLink', {..._ids, 'url': url, 'text': text})),
            ),
          ],
        ),
      ),
    );
  }
}
