// lib/services/security/bimi/org_icon.dart
// Иконки организаций-отправителей — одна цепочка (2.6.1, решение владельца
// 16.11.2026) и одна настройка «Показывать иконки организаций»:
//  1. Локальное: фото из контактов (его показывает портрет до этой цепочки,
//     hero_email_transition.dart), затем сохранённые ответы прошлых
//     запросов — логотип BIMI и значок сайта. Сеть не трогается.
//  2. BIMI: логотип у службы погоды Ogneliss (уходит только домен).
//  3. Значок сайта отправителя — телефон спрашивает сам сайт
//     (SiteIconService).
// Нигде нет — буква. Цепочка идёт только для писем, отправителя которых
// подтвердил сервер ящика (DMARC, [bimiDmarcDomain]); рабочая почта
// Exchange не участвует; запрет внешних служб (MDM) выключает её целиком.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/settings/providers/settings_provider.dart';
import '../managed_config.dart' show ManagedPolicy;
import 'bimi_service.dart';
import 'site_icon_service.dart';

/// Иконка: SVG логотипа BIMI или PNG значка сайта.
typedef OrgIcon = ({String? svg, Uint8List? png});

/// Для чего искать: домен для BIMI ([bimi], null — BIMI для этого письма
/// не спрашивается: ящик Google) и домен для значка сайта ([site]).
typedef OrgIconKey = ({String? bimi, String? site});

/// Цепочка: сохранённое → BIMI → сайт.
Future<OrgIcon?> resolveOrgIcon(OrgIconKey k, {BimiResolver? bimi, SiteIconService? sites}) async {
  if (ManagedPolicy.current.blockExternalServices) return null;
  final b = k.bimi == null ? null : bimi;
  final s = k.site == null ? null : sites;
  var bimiKnown = false;
  var siteKnown = false;
  // 1. Сохранённое.
  if (b != null) {
    final c = await b.cached(k.bimi!);
    if (c.svg != null) return (svg: c.svg, png: null);
    bimiKnown = c.hit;
  }
  if (s != null) {
    final c = await s.cached(k.site!);
    if (c.png != null) return (svg: null, png: c.png);
    siteKnown = c.hit;
  }
  // 2. BIMI.
  if (b != null && !bimiKnown) {
    final svg = await b.logoFor(k.bimi!);
    if (svg != null) return (svg: svg, png: null);
  }
  // 3. Сайт отправителя.
  if (s != null && !siteKnown) {
    final png = await s.iconFor(k.site!);
    if (png != null) return (svg: null, png: png);
  }
  return null;
}

/// Иконка организации для портрета; null — буква.
final orgIconProvider = FutureProvider.family<OrgIcon?, OrgIconKey>((ref, k) async {
  if (!ref.watch(settingsProvider.select((s) => s.orgIcons))) return null;
  return resolveOrgIcon(k, bimi: ref.watch(bimiResolverProvider), sites: ref.watch(siteIconServiceProvider));
});
