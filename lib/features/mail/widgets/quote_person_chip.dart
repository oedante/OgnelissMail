// lib/features/mail/widgets/quote_person_chip.dart
//
// Человек из шапки цитаты — плашкой с портретом (1.10.4, «Люди в цитатах»;
// замечание владельца 03.11.2026: «сделать аналогично заголовку письма,
// тот же механизм»). Портрет — тот же HeroEmailAvatar, что в шапке письма
// и ленте: фото из контактов или адресной книги, иначе буква цвета адреса.
// Рисуется прямо в тексте письма (WidgetSpan в MailNativeBody), поэтому
// письмо остаётся «простым» и показывается виджетами в обычном размере.

import 'package:flutter/material.dart';

import '../../../core/utils/text_safe.dart' show initialOf;
import '../../../widgets/common/hero_email_transition.dart';

class QuotePersonChip extends StatelessWidget {
  final String name;

  /// Адрес; null — человек без адреса (внутренний Exchange): без портрета
  /// из контактов, только буква.
  final String? email;
  final double fontSize;
  final VoidCallback? onTap;

  /// Полное имя, когда [name] — краткое «Фамилия И.О.» (1.10.5): для
  /// чтения с экрана и подсказки.
  final String? fullName;

  const QuotePersonChip(
      {super.key, required this.name, this.email, this.fontSize = 14, this.onTap, this.fullName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = (email ?? name).toLowerCase();
    final radius = (fontSize * 0.7).clamp(8.0, 14.0);
    final chip = Container(
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
      padding: const EdgeInsets.fromLTRB(1, 1, 8, 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius + 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        HeroEmailAvatar(
          emailId: 'quote/$key',
          radius: radius,
          color: HeroEmailAvatar.colorForEmail(key),
          initial: initialOf(name.isNotEmpty ? name : (email ?? '?')),
          hero: false,
          email: email,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            name.isNotEmpty ? name : (email ?? ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, color: theme.colorScheme.onSurface),
          ),
        ),
      ]),
    );
    final e = email;
    final full = (fullName == null || fullName!.isEmpty) ? name : fullName!;
    final body = Semantics(
      button: e != null,
      label: e == null ? full : '$full, $e',
      excludeSemantics: true,
      child: e == null || onTap == null
          ? chip
          : InkWell(borderRadius: BorderRadius.circular(radius + 2), onTap: onTap, child: chip),
    );
    return full == name ? body : Tooltip(message: full, child: body);
  }
}
