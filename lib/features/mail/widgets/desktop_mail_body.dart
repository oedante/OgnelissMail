// lib/features/mail/widgets/desktop_mail_body.dart
// Письмо без окна браузера — там, где его нет: компьютер (Windows, macOS,
// Linux), 1.8.14. Для вложенных писем (.eml, .msg) и писем архива — так же,
// как в экране письма: простое письмо виджетами, сложная вёрстка — упрощённо
// (buildNativeMailForced). Прежний показ — flutter_html с расширением таблиц
// — на вёрстке таблицами рассылок падал при раскладке, и вместо письма были
// пустые и серые места.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../../core/security/mail_body_processor.dart';
import 'mail_native_body.dart';

class DesktopMailBody extends StatefulWidget {
  const DesktopMailBody({
    super.key,
    required this.html,
    required this.onLink,
    this.images = const {},
    this.textScale = 1,
  });

  /// Уже очищенный HTML письма (санитайзер со стилями).
  final String html;
  final void Function(String url, String? linkText) onLink;

  /// Встроенные картинки: Content-ID (нижний регистр, без «<>») → data URI.
  final Map<String, String> images;
  final double textScale;

  @override
  State<DesktopMailBody> createState() => _DesktopMailBodyState();
}

class _DesktopMailBodyState extends State<DesktopMailBody> {
  late Future<NativeMail?> _mail;

  @override
  void initState() {
    super.initState();
    _mail = _build();
  }

  @override
  void didUpdateWidget(DesktopMailBody old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _mail = _build();
  }

  Future<NativeMail?> _build() =>
      MailBodyProcessor.heavy(widget.html, buildNativeMailDesktop).catchError((Object _) => null);

  static final _styleBlock = RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NativeMail?>(
      future: _mail,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 120);
        final m = snap.data;
        if (m != null) {
          return MailNativeBody(mail: m, images: widget.images, textScale: widget.textScale, onLink: widget.onLink);
        }
        // Разбор не удался — flutter_html без таблиц и без <style> письма.
        return SelectionArea(
          child: Html(
            data: widget.html.replaceAll(_styleBlock, ''),
            onLinkTap: (url, _, el) {
              if (url != null) widget.onLink(url, el?.text);
            },
          ),
        );
      },
    );
  }
}
