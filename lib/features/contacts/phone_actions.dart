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
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static final _extSplit = RegExp(r'(доб|ext|вн\.|#)', caseSensitive: false);

  /// Номер без добавочного — цифры и «+» (для SMS и проверки полноты).
  @visibleForTesting
  static String clean(String phone) => phone.split(_extSplit).first.replaceAll(RegExp(r'[^\d+]'), '');

  /// Добавочный из записи «… доб. 123» (цифры); пусто — его нет.
  static String _extOf(String phone) {
    final parts = phone.split(_extSplit);
    return parts.length < 2 ? '' : parts.sublist(1).join().replaceAll(RegExp(r'\D'), '');
  }

  /// Набор для tel: — номер, а добавочный — после паузы («,»): телефон
  /// наберёт его сам, когда ответят (2.7.5; прежде цифры добавочного
  /// дописывались к номеру).
  @visibleForTesting
  static String dialString(String phone) {
    final main = clean(phone);
    final ext = _extOf(phone);
    return ext.isEmpty || main.isEmpty ? main : '$main,$ext';
  }

  /// Добавочный без основного номера («39-397»): до 6 цифр, без «+».
  /// С мобильного на него звонят через основной номер организации
  /// (замечание владельца 28.11.2026).
  static bool isExtension(String? phone) {
    final c = clean(phone ?? '');
    final digits = c.replaceAll('+', '').length;
    return !c.startsWith('+') && digits >= 2 && digits <= 6 && _extOf(phone ?? '').isEmpty;
  }

  /// Набор добавочного [ext] через основной номер [main].
  @visibleForTesting
  static String viaMain(String main, String ext) {
    final m = dialString(main);
    final e = clean(ext).replaceAll('+', '');
    return m.isEmpty ? e : '$m,$e';
  }

  // Основные номера организаций: домен почты → номер. Спрашиваются при
  // первом звонке на добавочный и запоминаются.
  static const _mainKey = 'org_main_phones_v1';

  static String _domainOf(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    final at = e.lastIndexOf('@');
    return at < 0 || at == e.length - 1 ? '' : e.substring(at + 1);
  }

  static Future<Map<String, String>> _mains() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_mainKey);
      if (raw == null) return {};
      return {for (final e in (jsonDecode(raw) as Map).entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  /// Основной номер организации для адреса [email] (по домену); null — не задан.
  static Future<String?> mainNumberFor(String? email) async {
    final m = await _mains();
    return m[_domainOf(email)] ?? m[''];
  }

  /// Запомнить основной номер организации [email] (пусто — забыть).
  static Future<void> setMainNumber(String? email, String number) async {
    final m = await _mains();
    final key = _domainOf(email);
    if (number.trim().isEmpty) {
      m.remove(key);
    } else {
      m[key] = number.trim();
    }
    try {
      await (await SharedPreferences.getInstance()).setString(_mainKey, jsonEncode(m));
    } catch (e) {
      AppLogger.debug('Основной номер организации: $e');
    }
  }

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

  /// На номер можно написать SMS: полный и без добавочного.
  static bool canSms(String? phone) => isFull(phone) && _extOf(phone ?? '').isEmpty;

  /// Номер для SMS: полный мобильный, иначе полный рабочий; null — некуда.
  static String? smsNumber({String? mobile, String? work}) =>
      [mobile, work].map((p) => (p ?? '').trim()).where(canSms).firstOrNull;

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

  /// Позвонить (системное приложение телефона). Добавочный («39-397») —
  /// через основной номер организации адреса [email]: его набор, после
  /// ответа — добавочный. Основной номер не задан — спросить ([context]).
  static Future<void> call(String phone, AppLocalizations l10n, {BuildContext? context, String? email}) async {
    if (isExtension(phone) && context != null && context.mounted) {
      var main = await mainNumberFor(email);
      if (main == null) {
        if (!context.mounted) return;
        final asked = await askMainNumber(context, phone, email);
        if (asked == null) return; // отмена
        main = asked.isEmpty ? null : asked; // пусто — «Набрать как есть»
      }
      if (main != null) return _open(Uri.parse('tel:${viaMain(main, phone)}'), phone, l10n);
    }
    return _open(Uri.parse('tel:${dialString(phone)}'), phone, l10n);
  }

  /// Окно «Добавочный номер»: основной номер организации (запоминается).
  /// Возвращает номер; '' — набрать добавочный как есть; null — отмена.
  static Future<String?> askMainNumber(BuildContext context, String ext, String? email) async {
    final l10n = AppLocalizations.of(context);
    final domain = _domainOf(email);
    final current = await mainNumberFor(email);
    if (!context.mounted) return null;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _MainNumberDialog(
        body: l10n
            .tr('phoneExtBody')
            .replaceAll('{ext}', ext.trim())
            .replaceAll('{org}', domain.isEmpty ? '' : ' ($domain)'),
        initial: current ?? '',
      ),
    );
    if (result == null) return null;
    // Пустое поле у «Позвонить» — как «Набрать как есть»; номер — запомнить.
    if (result.isNotEmpty && clean(result).replaceAll('+', '').length >= 5) {
      await setMainNumber(email, result);
      return result;
    }
    return '';
  }

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

  /// Лист действий номера: позвонить, SMS, мессенджеры, скопировать. У
  /// добавочного — без SMS и с основным номером организации [email].
  static Future<void> show(BuildContext context, String phone, {String? email}) async {
    final l10n = AppLocalizations.of(context);
    final number = phone.trim();
    if (number.isEmpty) return;
    unawaited(HapticFeedback.mediumImpact());
    final ext = isExtension(number);
    final apps = ext ? const <PhoneApp>[] : await appsFor(number);
    final main = ext ? await mainNumberFor(email) : null;
    if (!context.mounted) return;
    final picked = await showActionSheet<String>(
      context,
      title: number,
      leading: const Icon(AppIcons.smartphone),
      items: [
        ActionSheetItem(icon: AppIcons.phone, label: l10n.tr('call'), subtitle: main, value: 'call'),
        if (!ext && _extOf(number).isEmpty)
          ActionSheetItem(icon: AppIcons.chat_bubble, label: l10n.tr('phoneSms'), value: 'sms'),
        if (ext)
          ActionSheetItem(
              icon: AppIcons.business, label: l10n.tr('phoneExtMain'), subtitle: main, value: 'main'),
        for (var i = 0; i < apps.length; i++)
          ActionSheetItem(icon: AppIcons.forum, label: apps[i].label, subtitle: apps[i].app, value: 'app$i'),
        ActionSheetItem(icon: AppIcons.content_copy, label: l10n.tr('copyPhone'), value: 'copy'),
      ],
    );
    switch (picked) {
      case null:
        return;
      case 'call':
        if (context.mounted) await call(number, l10n, context: context, email: email);
      case 'main':
        if (!context.mounted) return;
        final main = await askMainNumber(context, number, email);
        if (main == null) return;
        await _open(Uri.parse('tel:${main.isEmpty ? dialString(number) : viaMain(main, number)}'), number, l10n);
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

/// Окно «Добавочный номер»: поле основного номера, «Набрать как есть»,
/// «Отмена», «Позвонить». Поле живёт, пока окно не закрылось совсем.
class _MainNumberDialog extends StatefulWidget {
  final String body;
  final String initial;
  const _MainNumberDialog({required this.body, required this.initial});

  @override
  State<_MainNumberDialog> createState() => _MainNumberDialogState();
}

class _MainNumberDialogState extends State<_MainNumberDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.tr('phoneExtTitle')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.body),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('phone_ext_main'),
            controller: _field,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l10n.tr('phoneExtMain'), hintText: '+7 …'),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ]),
      ),
      actions: [
        TextButton(
          key: const ValueKey('phone_ext_as_is'),
          onPressed: () => Navigator.pop(context, ''),
          child: Text(l10n.tr('phoneExtDialAsIs')),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.tr('cancel'))),
        FilledButton(
          key: const ValueKey('phone_ext_call'),
          onPressed: () => Navigator.pop(context, _field.text.trim()),
          child: Text(l10n.tr('call')),
        ),
      ],
    );
  }
}
