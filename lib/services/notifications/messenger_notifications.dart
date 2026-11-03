// lib/services/notifications/messenger_notifications.dart
// Уведомления о письмах «как в мессенджерах» (1.9.x, просьба владельца
// 31.10.2026): отправитель — собеседник с фото из контактов или кружком с
// буквой тех же цветов, что в списке писем.
//
//  · Android — MessagingStyle с Person отправителя; у VIP — ещё ярлык беседы
//    (ShortcutManagerCompat, MainActivity.kt → ConversationShortcuts), и
//    письмо попадает в раздел «Беседы»: его можно сделать приоритетным.
//  · iPhone — Communication Notifications: уведомление показывается
//    нативно (AppDelegate.swift, INSendMessageIntent) с аватаром
//    отправителя. Без возможности в Xcode — обычное уведомление
//    (docs/guides/IOS_COMMUNICATION_NOTIFICATIONS.md).
//
// Выключено в настройках или натив не ответил — уведомление прежнего вида.
// Тексты — те же правила NotificationText: жирным только отправитель, ниже
// тема, в раскрытом — начало письма.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/avatar_colors.dart';
import '../../core/utils/text_safe.dart' show initialOf, fixUtf16;
import 'notification_service.dart' show NotificationService;
import 'notification_text.dart' show NotificationText;

class MessengerNotify {
  MessengerNotify._();

  // Ключи совпадают с settings_provider._K (notificationMessengerStyle,
  // notificationVipConversations): настройки читаются и в фоновом изоляте.
  static const prefStyle = 's_notif_messenger';
  static const prefVipConversations = 's_notif_vip_conv';

  /// «Уведомления как в мессенджерах» (по умолчанию включено).
  static bool styleOn(SharedPreferences? p) => p?.getBool(prefStyle) ?? true;

  /// «Беседы для VIP» на Android (по умолчанию включено).
  static bool vipConversationsOn(SharedPreferences? p) => p?.getBool(prefVipConversations) ?? true;

  static const _channel = MethodChannel('ogneliss/messenger');

  /// Начало id ярлыка беседы — по нему натив снимает только свои ярлыки,
  /// а не быстрые действия значка (quick_actions).
  static const shortcutPrefix = 'conv_';

  /// Ярлык беседы — один на отправителя (по адресу, без учёта регистра):
  /// письма человека во все ящики — одна беседа, как в мессенджере. В id —
  /// хэш, а не сам адрес. Без адреса беседы нет (null).
  static String? shortcutId(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    final at = e.indexOf('@');
    if (at <= 0 || at == e.length - 1) return null;
    return '$shortcutPrefix${NotificationService.stableId('conv|$e').toRadixString(36)}';
  }

  /// Публиковать ли ярлык беседы: Android, оба тумблера включены, VIP с
  /// адресом. Раздел «Беседы» требует MessagingStyle, поэтому без вида
  /// «как в мессенджерах» ярлык не нужен.
  static bool wantsShortcut({
    required bool android,
    required bool styleOn,
    required bool vipConversationsOn,
    required bool isVip,
    String? email,
  }) =>
      android && styleOn && vipConversationsOn && isVip && shortcutId(email) != null;

  /// Что открыть ярлыком беседы — тот же формат, что у виджета «Почта»
  /// (AppShortcuts.openType, путь /message/…): последнее письмо человека.
  static String openTarget(String accountId, String emailId) =>
      Uri(path: 'email', queryParameters: {'id': emailId, 'acc': accountId}).toString();

  /// Буква кружка — как в списке писем: первая буква имени, иначе адреса.
  static String initial(String name, String? email) {
    final n = name.trim();
    return initialOf(n.isNotEmpty ? n : (email ?? ''));
  }

  /// Цвета кружка (ARGB) — как у аватара в приложении (avatarTones, светлая
  /// тема): светлая заливка оттенком человека и буква тем же оттенком
  /// темнее; в высоком контрасте — насыщенный круг и белая буква. Оттенок —
  /// по адресу (как HeroEmailAvatar.colorForEmail), без адреса — по имени.
  static ({int fill, int letter}) avatarColors(String? email, String name, {bool highContrast = false}) {
    final key = (email ?? '').trim().isNotEmpty ? email!.trim() : name.trim();
    final base = avatarColorValue(key);
    if (highContrast) return (fill: base, letter: 0xFFFFFFFF);
    return (fill: _lerp(0xFFFFFFFF, base, 0.16), letter: _lerp(base, 0xFF000000, 0.25));
  }

  static int _lerp(int a, int b, double t) {
    int ch(int shift) {
      final x = (a >> shift) & 0xFF, y = (b >> shift) & 0xFF;
      return (x + (y - x) * t).round().clamp(0, 255);
    }
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  /// Фото из контактов (data URI из contacts.avatarUrl) — байты картинки.
  /// Ссылки https (Google) не загружаем: уведомление не ждёт сети. Большие
  /// фото — мимо (уведомление и ярлык передаются через Binder, лимит ~1 МБ).
  static Uint8List? photoBytes(String? photo, {int maxBytes = 300 * 1024}) {
    if (photo == null || !photo.startsWith('data:image/')) return null;
    final comma = photo.indexOf(',');
    if (comma < 0 || !photo.substring(0, comma).contains(';base64')) return null;
    try {
      final b = base64.decode(photo.substring(comma + 1));
      return b.isEmpty || b.length > maxBytes ? null : b;
    } catch (_) {
      return null;
    }
  }

  /// Кружок с буквой в PNG ([size]×[size], прозрачные углы). Не вышло
  /// (нет отрисовки в фоне) — null: Android нарисует свою букву, iPhone
  /// покажет уведомление без фото.
  static Future<Uint8List?> renderInitials({
    required String letter,
    required int fill,
    required int letterColor,
    int size = 192,
  }) async {
    ui.Picture? picture;
    ui.Image? image;
    try {
      final s = size.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, s, s));
      canvas.drawCircle(ui.Offset(s / 2, s / 2), s / 2, ui.Paint()..color = ui.Color(fill));
      final tp = TextPainter(
        text: TextSpan(
          // Половинка эмодзи без пары роняла отрисовку — страховка.
          text: fixUtf16(letter),
          style: TextStyle(color: ui.Color(letterColor), fontSize: s * 0.45, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, ui.Offset((s - tp.width) / 2, (s - tp.height) / 2));
      tp.dispose();
      picture = recorder.endRecording();
      image = await picture.toImage(size, size).timeout(const Duration(seconds: 2));
      final data = await image.toByteData(format: ui.ImageByteFormat.png).timeout(const Duration(seconds: 2));
      return data?.buffer.asUint8List();
    } catch (e) {
      AppLogger.debug('Аватар уведомления: $e');
      return null;
    } finally {
      image?.dispose();
      picture?.dispose();
    }
  }

  /// Фото в кружке: PNG [size]×[size] с прозрачными углами, середина
  /// снимка (1.10.5, замечание владельца 03.11.2026: «в оповещениях
  /// портреты квадратные» — оболочка nubia не скругляет значок человека, как
  /// это делает обычный Android). Не вышло — null (тогда фото как есть).
  static Future<Uint8List?> circlePhoto(Uint8List bytes, {int size = 192}) async {
    ui.Codec? codec;
    ui.Image? src;
    ui.Picture? picture;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes).timeout(const Duration(seconds: 2));
      src = (await codec.getNextFrame().timeout(const Duration(seconds: 2))).image;
      final w = src.width.toDouble(), h = src.height.toDouble();
      final side = w < h ? w : h;
      final from = ui.Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side);
      final s = size.toDouble();
      final to = ui.Rect.fromLTWH(0, 0, s, s);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, to);
      canvas.clipPath(ui.Path()..addOval(to));
      canvas.drawImageRect(src, from, to, ui.Paint()..filterQuality = ui.FilterQuality.medium);
      picture = recorder.endRecording();
      image = await picture.toImage(size, size).timeout(const Duration(seconds: 2));
      final data = await image.toByteData(format: ui.ImageByteFormat.png).timeout(const Duration(seconds: 2));
      return data?.buffer.asUint8List();
    } catch (e) {
      AppLogger.debug('Фото для уведомления: $e');
      return null;
    } finally {
      image?.dispose();
      picture?.dispose();
      src?.dispose();
      codec?.dispose();
    }
  }

  /// Аватар отправителя: фото из контактов (кружком), иначе кружок с буквой.
  /// [vip] — с золотым кольцом и звёздочкой (vipBadge).
  static Future<Uint8List?> avatar({
    required String name,
    String? email,
    String? photo,
    bool highContrast = false,
    bool vip = false,
  }) async {
    final p = photoBytes(photo);
    Uint8List? out;
    if (p != null) {
      out = await circlePhoto(p) ?? p;
    } else {
      final c = avatarColors(email, name, highContrast: highContrast);
      out = await renderInitials(letter: initial(name, email), fill: c.fill, letterColor: c.letter);
    }
    if (!vip || out == null) return out;
    return await vipBadge(out) ?? out;
  }

  /// Отметка VIP на портрете (1.10.5, замечание владельца 03.11.2026:
  /// «звёздочка в уведомлении у VIP жирным шрифтом не очень выглядит.
  /// Может как-то по-другому обозначим акцент?»): золотое кольцо вокруг
  /// кружка и золотая звёздочка в белой обводке внизу справа — как значки
  /// на аватарах в мессенджерах. Портрет внутри кольца немного меньше.
  /// Не вышло — null (портрет без отметки).
  static Future<Uint8List?> vipBadge(Uint8List circle, {int size = 192}) async {
    ui.Codec? codec;
    ui.Image? src;
    ui.Picture? picture;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(circle).timeout(const Duration(seconds: 2));
      src = (await codec.getNextFrame().timeout(const Duration(seconds: 2))).image;
      final s = size.toDouble();
      const gold = ui.Color(NotificationText.vipColor);
      final ring = s * 0.05;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, s, s));
      // Портрет — внутри кольца с просветом.
      final inset = ring + s * 0.025;
      final inner = ui.Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset);
      canvas.save();
      canvas.clipPath(ui.Path()..addOval(inner));
      canvas.drawImageRect(src, ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()), inner,
          ui.Paint()..filterQuality = ui.FilterQuality.medium);
      canvas.restore();
      canvas.drawCircle(ui.Offset(s / 2, s / 2), s / 2 - ring / 2,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = ring
            ..color = gold
            ..isAntiAlias = true);
      // Звёздочка: золотой кружок в белой обводке, внутри белая звезда.
      final c = ui.Offset(s * 0.81, s * 0.81);
      final r = s * 0.17;
      canvas.drawCircle(c, r, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      canvas.drawCircle(c, r - s * 0.025, ui.Paint()..color = gold);
      canvas.drawPath(_star(c, r * 0.62), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      picture = recorder.endRecording();
      image = await picture.toImage(size, size).timeout(const Duration(seconds: 2));
      final data = await image.toByteData(format: ui.ImageByteFormat.png).timeout(const Duration(seconds: 2));
      return data?.buffer.asUint8List();
    } catch (e) {
      AppLogger.debug('Отметка VIP на портрете: $e');
      return null;
    } finally {
      image?.dispose();
      picture?.dispose();
      src?.dispose();
      codec?.dispose();
    }
  }

  /// Пятиконечная звезда с центром [c] и внешним радиусом [r].
  static ui.Path _star(ui.Offset c, double r) {
    final path = ui.Path();
    final inner = r * 0.45;
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = ui.Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// Отправитель для Android: имя (заголовок, как NotificationText.title),
  /// mailto: — по нему Android находит человека в контактах для режима «Не
  /// беспокоить», ключ — id беседы.
  static Person androidSender({required String title, String? email, Uint8List? avatar, bool vip = false}) {
    final e = (email ?? '').trim();
    return Person(
      name: title,
      key: shortcutId(e) ?? (e.isEmpty ? null : e.toLowerCase()),
      uri: e.contains('@') ? 'mailto:$e' : null,
      important: vip,
      icon: avatar == null ? null : ByteArrayAndroidIcon(avatar),
    );
  }

  /// MessagingStyle: «я» — владелец ящика (Android требует имя), одно
  /// сообщение от отправителя: тема, ниже начало письма.
  static MessagingStyleInformation androidStyle({
    required String selfName,
    required Person sender,
    required String text,
    required DateTime when,
  }) =>
      MessagingStyleInformation(
        Person(name: selfName.trim().isEmpty ? 'Ogneliss Mail' : selfName.trim()),
        groupConversation: false,
        messages: [Message(text, when, sender)],
      );

  /// Опубликовать ярлык беседы (Android 11+). id ярлыка — или null, если
  /// не вышло (старый Android, фоновый движок без канала): тогда уведомление
  /// без беседы, как раньше.
  static Future<String?> pushShortcut({
    required String name,
    required String email,
    required String accountId,
    required String emailId,
    Uint8List? avatar,
  }) async {
    final id = shortcutId(email);
    if (id == null) return null;
    try {
      final ok = await _channel.invokeMethod<bool>('pushShortcut', {
        'id': id,
        'name': name.trim(),
        'email': email.trim(),
        'open': openTarget(accountId, emailId),
        'avatar': avatar,
      });
      return ok == true ? id : null;
    } catch (e) {
      AppLogger.debug('Ярлык беседы: $e');
      return null;
    }
  }

  /// Снять все ярлыки бесед («Беседы для VIP» выключили).
  static Future<void> removeShortcuts() async {
    try {
      await _channel.invokeMethod<void>('removeShortcuts');
    } catch (e) {
      AppLogger.debug('Ярлыки бесед: $e');
    }
  }

  /// Аргументы нативного уведомления iPhone (AppDelegate.showCommunication):
  /// те же заголовок, подзаголовок, текст, группа, категория кнопок, звук и
  /// значок, что у обычного, плюс отправитель для INSendMessageIntent.
  static Map<String, Object?> iosArgs({
    required int id,
    required String title,
    required String subtitle,
    required String body,
    required String threadId,
    required String category,
    required bool sound,
    required int badge,
    required String payload,
    String? senderEmail,
    Uint8List? avatar,
  }) {
    final e = (senderEmail ?? '').trim();
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'body': body,
      'thread': threadId,
      'category': category,
      'sound': sound,
      'badge': badge,
      'payload': payload,
      'senderName': title,
      'senderEmail': e,
      // Беседа — тот же отправитель (как ярлык на Android).
      'conversation': shortcutId(e) ?? 'mail_${NotificationService.stableId(title)}',
      'avatar': avatar,
    };
  }

  /// Показать уведомление нативно (iPhone). false — не показано (старый
  /// iOS, ошибка): показывает плагин, как раньше.
  static Future<bool> showIos(Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<bool>('show', args) ?? false;
    } catch (e) {
      AppLogger.debug('Уведомление как в мессенджерах: $e');
      return false;
    }
  }
}
