// lib/widgets/common/bimi_avatar.dart
// Логотип отправителя BIMI вместо буквы (1.9.x, просьба владельца
// 31.10.2026): в ленте, беседе и заголовке письма. Пока логотипа нет (или
// письмо не прошло DMARC у сервера пользователя) — обычная буква.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/models/account_model.dart' show AccountType;
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../services/security/bimi/bimi_rules.dart';
import '../../services/security/bimi/bimi_service.dart';
import '../../services/security/bimi/org_icon.dart';
import 'person_photo.dart' show PhotoRing;

/// Домены серверов ящиков пользователя: логотипу верим, только если
/// Authentication-Results поставил один из них (2.0.0).
///
/// Ящики Google (Gmail и Google Workspace) сюда не входят (2.5.5): у их
/// писем логотип не ищется, и домены отправителей из Gmail на сервер
/// Ogneliss не уходят — данные пользователей Google остаются на устройстве.
/// Рабочая почта Exchange — тоже (2.6.1, правило владельца: с рабочей
/// почтой серверы Ogneliss не используются).
final bimiOwnServersProvider = Provider<Set<String>>((ref) => ownMailServerDomains([
      for (final a in ref.watch(accountsProvider))
        if (!a.isMsExchange && !isGoogleMailbox(a.type, [a.imapServer, a.smtpServer]))
          (email: a.email, hosts: [a.imapServer, a.ewsUrl, a.exchangeServer, a.smtpServer]),
    ]));

/// Серверы ящиков, чьей проверке отправителя верим для значков сайтов
/// (2.6.1): все ящики, кроме рабочей почты Exchange. Ящики Google здесь
/// есть: значок телефон берёт сам, на сервер Ogneliss ничего не уходит.
final siteIconOwnServersProvider = Provider<Set<String>>((ref) => ownMailServerDomains([
      for (final a in ref.watch(accountsProvider))
        if (!a.isMsExchange) (email: a.email, hosts: [a.imapServer, a.ewsUrl, a.exchangeServer, a.smtpServer]),
    ]));

/// Ящик Google: вход через Google или серверы Gmail (пароль приложения,
/// Google Workspace на своём домене).
bool isGoogleMailbox(AccountType type, List<String?> hosts) =>
    type == AccountType.google ||
    hosts.any((h) {
      final s = (h ?? '').trim().toLowerCase();
      return s.endsWith('gmail.com') || s.endsWith('googlemail.com');
    });

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

  /// Отправитель подтверждён для значка сайта (тот же разбор, другой набор
  /// своих серверов — [siteIconOwnServersProvider]).
  static final _siteDomains = <String, String?>{};

  static String? _siteDomainFor(String email, String? authResults, Set<String> own) {
    if (authResults == null || authResults.isEmpty) return null;
    final key = '$email\n$authResults\n${own.length}';
    if (_siteDomains.containsKey(key)) return _siteDomains[key];
    final d = bimiDmarcDomain(authResults, email, ownServers: own);
    _siteDomains[key] = d;
    if (_siteDomains.length > 500) _siteDomains.remove(_siteDomains.keys.first);
    return d;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Цепочка «сохранённое → BIMI → сайт» (org_icon.dart); фото из контактов
    // портрет показал до неё.
    final bimi = BimiResolver.configured ? _domainFor(email, authResults, ref.watch(bimiOwnServersProvider)) : null;
    final site = _siteDomainFor(email, authResults, ref.watch(siteIconOwnServersProvider));
    if (bimi == null && site == null) return fallback;
    final icon = ref.watch(orgIconProvider((bimi: bimi, site: site))).value;
    final size = radius * 2;
    if (icon?.svg case final svg?) {
      return _ring(
          SvgPicture.string(
            svg,
            width: size,
            height: size,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => fallback,
          ),
          size);
    }
    if (icon?.png case final png?) {
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(16, 512);
      return _ring(
          Image.memory(
            png,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: px,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => fallback,
          ),
          size);
    }
    return fallback;
  }

  // Круглая маска и белая подложка: логотипы рисуют для белого фона, а
  // прозрачные в тёмной теме терялись бы.
  Widget _ring(Widget image, double size) => PhotoRing(
        width: radius >= 14 ? 1.5 : 1,
        child: ClipOval(
          child: Container(width: size, height: size, color: Colors.white, child: image),
        ),
      );
}
