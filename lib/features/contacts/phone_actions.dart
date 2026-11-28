// lib/features/contacts/phone_actions.dart
// Удержание номера телефона (2.7.2, просьба пользователя 24.11.2026): кроме
// звонка — SMS приложением по умолчанию и мессенджеры, с которыми этот
// номер связан в контактах телефона (Google или самого телефона): WhatsApp,
// Telegram, Viber и другие — те же пункты, что в системных «Контактах»
// («Сообщение +7 …», «Голосовой звонок …»; подписи задают сами приложения).
// Связи нет — пунктов мессенджеров нет.
//
// Мессенджеры — только Android (на iPhone чужие приложения в контактах
// таких строк не оставляют).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/app_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/action_sheet.dart';
import '../../widgets/common/inline_notice.dart' show showInlineError;

/// Мессенджер, связанный с номером в контактах телефона.
class PhoneApp {
  final int id;
  final String mime;

  /// Подпись действия от самого приложения («Сообщение +7 912 …»).
  final String label;

  /// Название приложения («WhatsApp»).
  final String app;
  const PhoneApp({required this.id, required this.mime, required this.label, required this.app});
}

abstract final class PhoneActions {
  static const _channel = MethodChannel('ogneliss/device_contacts');

  /// Номер для ссылок tel: и sms: — цифры и «+»; добавочный («доб. 123»,
  /// «ext. 12») отбрасывается — иначе его цифры уходили в номер.
  @visibleForTesting
  static String clean(String phone) =>
      phone.split(RegExp(r'(доб|ext|вн\.|#)', caseSensitive: false)).first.replaceAll(RegExp(r'[^\d+]'), '');

  /// Полный номер — с кодом страны или города (2.7.5, просьба владельца
  /// 28.11.2026): на него можно позвонить с мобильного и написать SMS.
  /// Короткий внутренний («39-397») — нет.
  static bool isFull(String? phone) {
    final c = clean(phone ?? '');
    final digits = c.replaceAll('+', '').length;
    return digits >= 10 || (c.startsWith('+') && digits >= 8);
  }

  /// Номер для звонка: первый полный, иначе первый какой есть; null — нет.
  static String? callNumber(Iterable<String?> phones) {
    final list = [for (final p in phones) if ((p ?? '').trim().isNotEmpty) p!.trim()];
    return list.where(isFull).firstOrNull ?? list.firstOrNull;
  }

  /// Номер для SMS: полный мобильный, иначе полный рабочий; null — некуда.
  static String? smsNumber({String? mobile, String? work}) =>
      [mobile, work].map((p) => (p ?? '').trim()).where(isFull).firstOrNull;

  /// Мессенджеры, связанные с номером в контактах телефона (Android).
  static Future<List<PhoneApp>> appsFor(String phone) async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      final list = await _channel
          .invokeListMethod<Object?>('phoneApps', {'phone': phone})
          .timeout(const Duration(seconds: 2));
      return [
        for (final e in list ?? const <Object?>[])
          if (e is Map && e['id'] is num && e['mime'] is String && e['label'] is String)
            PhoneApp(
              id: (e['id'] as num).toInt(),
              mime: e['mime'] as String,
              label: e['label'] as String,
              app: (e['app'] as String?) ?? '',
            ),
      ];
    } catch (e) {
      // Старая сборка без метода, нет разрешения — просто без мессенджеров.
      AppLogger.debug('Мессенджеры номера: $e');
      return const [];
    }
  }

  /// Позвонить (системное приложение телефона).
  static Future<void> call(String phone, AppLocalizations l10n) => _open(Uri.parse('tel:${clean(phone)}'), phone, l10n);

  /// SMS приложением по умолчанию.
  static Future<void> sms(String phone, AppLocalizations l10n) => _open(Uri.parse('sms:${clean(phone)}'), phone, l10n);

  static Future<void> _open(Uri uri, String phone, AppLocalizations l10n) async {
    if (uri.path.isEmpty) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      // Нечем открыть — нужно действие человека (поставить приложение).
      if (!ok) showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', phone));
    } catch (_) {
      showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', phone));
    }
  }

  /// Лист действий номера: позвонить, SMS, мессенджеры, скопировать.
  static Future<void> show(BuildContext context, String phone) async {
    final l10n = AppLocalizations.of(context);
    final number = phone.trim();
    if (number.isEmpty) return;
    unawaited(HapticFeedback.mediumImpact());
    final apps = await appsFor(number);
    if (!context.mounted) return;
    final picked = await showActionSheet<String>(
      context,
      title: number,
      leading: const Icon(AppIcons.smartphone),
      items: [
        ActionSheetItem(icon: AppIcons.phone, label: l10n.tr('call'), value: 'call'),
        ActionSheetItem(icon: AppIcons.chat_bubble, label: l10n.tr('phoneSms'), value: 'sms'),
        for (var i = 0; i < apps.length; i++)
          ActionSheetItem(icon: AppIcons.forum, label: apps[i].label, subtitle: apps[i].app, value: 'app$i'),
        ActionSheetItem(icon: AppIcons.content_copy, label: l10n.tr('copyPhone'), value: 'copy'),
      ],
    );
    switch (picked) {
      case null:
        return;
      case 'call':
        await call(number, l10n);
      case 'sms':
        await sms(number, l10n);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: number));
      default:
        final i = int.tryParse(picked.substring(3));
        if (i == null || i >= apps.length) return;
        try {
          final ok = await _channel.invokeMethod<bool>('openData', {'id': apps[i].id, 'mime': apps[i].mime});
          if (ok != true) showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', apps[i].app));
        } catch (_) {
          showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', apps[i].app));
        }
    }
  }
}
