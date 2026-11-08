// lib/widgets/common/bimi_avatar.dart
// Логотип отправителя BIMI вместо буквы (1.9.x, просьба владельца
// 31.10.2026): в ленте, беседе и заголовке письма. Пока логотипа нет (или
// письмо не прошло DMARC у сервера пользователя) — обычная буква.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../services/security/bimi/bimi_rules.dart';
import '../../services/security/bimi/bimi_service.dart';
import 'person_photo.dart' show PhotoRing;

/// Домены серверов ящиков пользователя: логотипу верим, только если
/// Authentication-Results поставил один из них (2.0.0).
final bimiOwnServersProvider = Provider<Set<String>>((ref) => ownMailServerDomains([
      for (final a in ref.watch(accountsProvider))
        (email: a.email, hosts: [a.imapServer, a.ewsUrl, a.exchangeServer, a.smtpServer]),
    ]));

class BimiAvatar extends ConsumerWidget {
  const BimiAvatar({
    super.key,
    required this.email,
    required this.authResults,
    required this.radius,
    required this.fallback,
  });

  /// Адрес отправителя (From).
  final String email;

  /// Authentication-Results письма (верхний заголовок).
  final String? authResults;
  final double radius;

  /// Буква — до ответа сервера и когда логотипа нет.
  final Widget fallback;

  // Разбор заголовка — на каждое построение строки ленты; результат
  // запоминается (адрес и заголовок у письма не меняются).
  static final _domains = <String, String?>{};

  static String? _domainFor(String email, String? authResults, Set<String> own) {
    if (authResults == null || authResults.isEmpty) return null;
    final key = '$email\n$authResults\n${own.length}';
    if (_domains.containsKey(key)) return _domains[key];
    final d = bimiDmarcDomain(authResults, email, ownServers: own);
    _domains[key] = d;
    if (d != null) BimiStats.eligible(d);
    if (_domains.length > 500) _domains.remove(_domains.keys.first);
    return d;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!BimiResolver.configured) return fallback;
    final domain = _domainFor(email, authResults, ref.watch(bimiOwnServersProvider));
    if (domain == null) return fallback;
    final svg = ref.watch(bimiLogoProvider(domain)).value;
    if (svg == null) return fallback;
    final size = radius * 2;
    // Круглая маска и белая подложка: логотипы рисуют для белого фона, а
    // прозрачные в тёмной теме терялись бы.
    return PhotoRing(
      width: radius >= 14 ? 1.5 : 1,
      child: ClipOval(
        child: Container(
          width: size,
          height: size,
          color: Colors.white,
          child: SvgPicture.string(
            svg,
            width: size,
            height: size,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }
}
