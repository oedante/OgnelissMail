// lib/widgets/common/account_avatar.dart
//
// Портрет ящика в списках выбора (1.10.3, замечание владельца 02.11.2026:
// «здесь лучше не только цвета, но и аватары указывать; в календаре (задачи
// и встречи) и контактах такой же выбор сделать»). Фото ящика или логотип
// службы — как в меню и на нижней панели (HeroEmailAvatar), вокруг — кольцо
// цвета ящика: цвет по-прежнему различает ящики с похожими фото.

import 'package:flutter/material.dart';

import '../../core/utils/text_safe.dart' show initialOf;
import '../../data/models/account_model.dart';
import 'hero_email_transition.dart';
import 'peek_card.dart' show AppMenuEntry;

class AccountAvatar extends StatelessWidget {
  final AccountModel account;
  final double radius;

  /// Цвет кольца; null — цвет ящика.
  final Color? ringColor;

  const AccountAvatar({super.key, required this.account, this.radius = 13, this.ringColor});

  @override
  Widget build(BuildContext context) {
    final color = Color(account.colorValue);
    final name = account.displayName.trim();
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ringColor ?? color, width: 1.5)),
      child: HeroEmailAvatar(
        emailId: 'account/${account.id}',
        radius: radius,
        color: color,
        initial: initialOf(name.isNotEmpty ? name : account.email),
        hero: false,
        email: account.email,
        photo: account.avatarUrl,
      ),
    );
  }
}

/// Буквы портретов ящиков без фото — разные (оценка интерфейса 12.11.2026:
/// пять ящиков с одним именем владельца давали ряд «Я Я Я»). Первая буква
/// имени; совпала с другим ящиком — первая буква адреса (до @); совпала и
/// она — две буквы: адрес и домен («ОЯ» — o@yandex, «ОG» — o@gmail).
Map<String, String> distinctAccountInitials(List<AccountModel> accounts) {
  String nameOf(AccountModel a) {
    final n = a.displayName.trim();
    return n.isNotEmpty ? n : a.email;
  }

  final byName = <String, int>{};
  for (final a in accounts) {
    final k = initialOf(nameOf(a));
    byName[k] = (byName[k] ?? 0) + 1;
  }
  final login = <String, int>{};
  for (final a in accounts) {
    final k = initialOf(a.email);
    login[k] = (login[k] ?? 0) + 1;
  }
  final out = <String, String>{};
  for (final a in accounts) {
    final first = initialOf(nameOf(a));
    if ((byName[first] ?? 0) < 2) {
      out[a.id] = first;
      continue;
    }
    final l = initialOf(a.email);
    if ((login[l] ?? 0) < 2) {
      out[a.id] = l;
      continue;
    }
    final at = a.email.indexOf('@');
    final domain = at >= 0 ? a.email.substring(at + 1) : '';
    final d = initialOf(domain);
    out[a.id] = d == '?' ? l : '$l$d';
  }
  return out;
}

/// Пункт меню выбора ящика: портрет, имя (или адрес) и адрес под ним.
AppMenuEntry<String> accountMenuEntry(
  AccountModel a, {
  String? value,
  String? label,
  String? subtitle,
  Color? ringColor,
  bool enabled = true,
}) {
  final name = a.displayName.trim();
  final login = a.email.split('@').first.toLowerCase();
  final plain = name.isEmpty || name.toLowerCase() == login || name.toLowerCase() == a.email.toLowerCase();
  return AppMenuEntry<String>(
    value: value ?? a.id,
    label: label ?? (plain ? a.email : name),
    subtitle: subtitle ?? (plain ? null : a.email),
    leading: AccountAvatar(account: a, ringColor: ringColor),
    enabled: enabled,
  );
}
