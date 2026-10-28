// lib/widgets/common/person_photo.dart
// Фото людей и аккаунтов: из контактов (CardDAV PHOTO, Exchange Picture,
// адресная книга организации) — по адресу почты. Хранится в contacts.avatarUrl
// и accounts.avatarUrl как data URI (base64) или https-ссылка (Google).

import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart' show Theme, Brightness;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart' show AppColors;
import '../../core/theme/ogneliss_look.dart';
import '../../data/providers/database_provider.dart';
import '../../services/mail/own_addresses.dart';
import '../../services/mail/own_identity_service.dart' show ownAddressesRevisionProvider;

/// Адрес почты (в нижнем регистре) → фото. Аккаунты поверх контактов:
/// своё фото владельца важнее старой карточки в адресной книге.
final personPhotosProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  ref.watch(ownAddressesRevisionProvider);
  final contacts = (db.select(db.contacts)..where((c) => c.avatarUrl.isNotNull())).watch();
  // Фото ящиков — тоже живым потоком: выбранное своё фото сразу становится
  // фото владельца во всей почте (список, письмо, беседа, подсказки).
  // Раньше карта пересобиралась только при изменении контактов, и в
  // письмах оставалось старое фото из адресной книги.
  final accounts = (db.select(db.accounts)..where((a) => a.avatarUrl.isNotNull())).watch();
  Map<String, String>? lastContacts;
  Map<String, String>? lastAccounts;
  final out = StreamController<Map<String, String>>();
  Map<String, String>? lastSent;
  void emit() {
    if (lastContacts == null || lastAccounts == null) return;
    final m = {...lastContacts!, ...lastAccounts!};
    // Таблица ящиков меняется после каждой синхронизации (время, счётчики),
    // контакты — при каждой синхронизации адресной книги. Фото при этом
    // обычно те же: без проверки все аватары ленты и письма перестраивались
    // каждые несколько минут (аудит 11.10.2026).
    if (lastSent != null && mapEquals(lastSent, m)) return;
    lastSent = m;
    out.add(m);
  }
  final s1 = contacts.listen((rows) {
    lastContacts = {
      for (final r in rows)
        if (r.email.isNotEmpty && (r.avatarUrl ?? '').isNotEmpty) r.email.toLowerCase(): r.avatarUrl!,
    };
    emit();
  }, onError: out.addError);
  final s2 = accounts.listen((rows) {
    // Своё фото — на всех адресах ящика: вход под одним адресом, письма —
    // с основного адреса с сервера (иначе к своим письмам цеплялось старое
    // фото из адресной книги, а выбранное — нет).
    lastAccounts = {
      for (final a in rows)
        if ((a.avatarUrl ?? '').isNotEmpty) ...{
          a.email.toLowerCase(): a.avatarUrl!,
          for (final e in OwnAddresses.extraFor(a.id)) e: a.avatarUrl!,
        },
    };
    emit();
  }, onError: out.addError);
  ref.onDispose(() {
    s1.cancel();
    s2.cancel();
    out.close();
  });
  return out.stream;
});

final Map<String, ImageProvider> _cache = {};

/// Картинка для фото: data URI декодируется один раз, ссылку кэширует Flutter.
ImageProvider? photoImage(String? photo) {
  if (photo == null || photo.isEmpty) return null;
  final cached = _cache[photo];
  if (cached != null) return cached;
  ImageProvider? img;
  if (photo.startsWith('data:')) {
    final comma = photo.indexOf(',');
    if (comma > 0) {
      try {
        final Uint8List bytes = base64.decode(photo.substring(comma + 1));
        if (bytes.isNotEmpty) img = MemoryImage(bytes);
      } catch (_) {}
    }
  } else if (photo.startsWith('https://')) {
    img = NetworkImage(photo);
  } else if (photo.startsWith('http://')) {
    // Открытый http Android не загружает (cleartext запрещён); почти все
    // серверы фото отдают и по https. Раньше такие фото отбрасывались молча.
    img = NetworkImage('https://${photo.substring(7)}');
  }
  if (img != null) {
    // Фото на экране — не больше 96 dp (карточка контакта, ×3 на плотных
    // экранах). Фото из адресной книги Exchange бывают 648×648:
    // раскодированное в полный размер — 1,6 МБ памяти на человека, а в
    // ленте — десятки людей.
    img = ResizeImage(img, width: 288, policy: ResizeImagePolicy.fit);
    if (_cache.length > 500) _cache.clear();
    _cache[photo] = img;
  }
  return img;
}

/// Рамка вокруг круглого фото: светлые портреты сливались с белым фоном,
/// тёмные — с тёмным. Цвет — AppColors.avatarRing (≈2:1 к фону светлой
/// темы, ≈3:1 к тёмной; прежний outlineVariant — 1.3:1, почти не виден).
/// Размер не меняется — рамка рисуется поверх края.
class PhotoRing extends StatelessWidget {
  final Widget child;
  final double width;
  /// Толщина кольца: 1 px (мягкий стиль 1.6.20; было 1,5).
  const PhotoRing({super.key, required this.child, this.width = 1.0});

  @override
  Widget build(BuildContext context) {
    // «Воздушный» вид (1.8.0, как Ogneliss Dialer): без кольца; кольцо —
    // в высококонтрастной теме, где граница важнее вида.
    if (!OgnelissLook.of(context).outlined) return child;
    return Container(
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.avatarRing(context), width: width),
      ),
      child: child,
    );
  }
}

/// Цвета кружка с буквой (фото нет). «Воздушный» вид (1.8.0, как Ogneliss
/// Dialer): светлая заливка оттенком человека, буква — тем же оттенком,
/// темнее (в тёмной теме — светлее). Высокий контраст — как раньше:
/// насыщенный круг и белая буква.
({Color fill, Color letter}) avatarTones(BuildContext context, Color base) {
  final theme = Theme.of(context);
  if (OgnelissLook.of(context).outlined) return (fill: base, letter: const Color(0xFFFFFFFF));
  final surface = theme.colorScheme.surface;
  if (theme.brightness == Brightness.dark) {
    return (
      fill: Color.alphaBlend(base.withValues(alpha: 0.32), surface),
      letter: Color.lerp(base, const Color(0xFFFFFFFF), 0.55)!,
    );
  }
  return (
    fill: Color.alphaBlend(base.withValues(alpha: 0.16), surface),
    letter: Color.lerp(base, const Color(0xFF000000), 0.25)!,
  );
}
