// lib/core/security/attachment_safety.dart
// Защита при открытии вложений.
//
// Раньше любое вложение открывалось системой одной кнопкой: .exe, .hta,
// .js, .lnk, .scr на Windows запускались сразу, а Windows не знала, что файл
// пришёл из интернета (не было «метки интернета», Zone.Identifier), поэтому
// SmartScreen и защищённый режим Office не срабатывали.
//
// Теперь:
// - исполняемые и скриптовые файлы приложение не открывает (можно сохранить
//   и проверить антивирусом — решение за пользователем и администратором);
// - документы с макросами и архивы-образы открываются после предупреждения;
// - двойное расширение («счёт.pdf.exe») и символ смены направления текста
//   (U+202E, «exe.fdp» выглядит как «pdf.exe») распознаются;
// - на Windows каждому сохранённому вложению ставится метка интернета.

import 'dart:io';
import '../theme/app_icons.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../platform/file_opener.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';

enum AttachmentRisk { safe, warn, blocked }

class AttachmentSafety {
  AttachmentSafety._();

  static const _blocked = {
    'exe', 'com', 'scr', 'pif', 'bat', 'cmd', 'ps1', 'psm1', 'psd1', 'vbs', 'vbe',
    'js', 'jse', 'wsf', 'wsh', 'wsc', 'hta', 'msi', 'msp', 'mst', 'msc', 'cpl',
    'jar', 'lnk', 'reg', 'scf', 'inf', 'dll', 'sys', 'drv', 'ocx', 'url',
    'application', 'appref-ms', 'gadget', 'xll', 'xbap', 'library-ms',
    'settingcontent-ms', 'search-ms', 'searchconnector-ms', 'chm', 'hlp',
    'apk', 'xapk', 'appx', 'appxbundle', 'msix', 'msixbundle',
    'sh', 'command', 'app', 'pkg', 'run', 'desktop', 'deb', 'rpm',
  };

  static const _warn = {
    'docm', 'dotm', 'xlsm', 'xltm', 'xlam', 'pptm', 'potm', 'ppam', 'sldm',
    'iso', 'img', 'vhd', 'vhdx', 'dmg', 'one', 'svg', 'html', 'htm', 'xhtml',
    'mht', 'mhtml', 'rtf', 'iqy', 'slk',
  };

  static const _docLike = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'jpg', 'jpeg',
    'png', 'gif', 'zip', 'rar', '7z', 'csv',
  };

  static AttachmentRisk riskOf(String fileName) {
    final name = fileName.trim().toLowerCase();
    // Смена направления текста — только для маскировки.
    if (name.contains('\u202E') || name.contains('\u202D')) return AttachmentRisk.blocked;
    final cleaned = name.replaceAll(RegExp(r'[\s.]+$'), '');
    final parts = cleaned.split('.');
    if (parts.length < 2) return AttachmentRisk.safe;
    final ext = parts.last;
    if (_blocked.contains(ext)) return AttachmentRisk.blocked;
    if (_warn.contains(ext)) return AttachmentRisk.warn;
    // «отчёт.pdf.zip» — обычно нормально; но «отчёт.pdf.js» уже поймано выше.
    if (parts.length >= 3 && _docLike.contains(parts[parts.length - 2]) &&
        !_docLike.contains(ext)) {
      return AttachmentRisk.warn;
    }
    return AttachmentRisk.safe;
  }

  /// Открыть вложение во внешнем приложении с проверкой риска.
  static Future<void> openExternally(BuildContext context, String path, String fileName) async {
    final l10n = AppLocalizations.of(context);
    switch (riskOf(fileName)) {
      case AttachmentRisk.blocked:
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(AppIcons.gpp_bad),
            title: Text(l10n.tr('attBlockedTitle')),
            content: Text(l10n.tr('attBlockedBody').replaceAll('{name}', fileName)),
            actions: [
              FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.ok)),
            ],
          ),
        );
        return;
      case AttachmentRisk.warn:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(AppIcons.warning),
            title: Text(l10n.tr('attWarnTitle')),
            content: Text(l10n.tr('attWarnBody').replaceAll('{name}', fileName)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('openLink'))),
            ],
          ),
        );
        if (ok != true) return;
      case AttachmentRisk.safe:
        break;
    }
    await markFromInternet(path);
    final res = await FileOpener.open(path, mime: mimeOf(fileName), name: fileName);
    if (res == OpenFileOutcome.done || !context.mounted) return;
    // Приложения для формата нет или система отказала — предлагаем
    // «Поделиться»: так файл можно отправить в любое приложение (Документы,
    // Диск, мессенджер). Раньше кнопка молча ничего не делала.
    final share = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('noAppToOpenTitle')),
        content: Text(l10n.tr('noAppToOpenBody').replaceAll('{name}', fileName)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('share'))),
        ],
      ),
    );
    if (share != true) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(await FileOpener.namedCopy(path, fileName), name: fileName)]));
  }

  /// MIME-тип по расширению: без него часть приложений (Office, WPS)
  /// не предлагается для открытия.
  static String? mimeOf(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return const {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'odt': 'application/vnd.oasis.opendocument.text',
      'ods': 'application/vnd.oasis.opendocument.spreadsheet',
      'rtf': 'application/rtf',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'eml': 'message/rfc822',
      'ics': 'text/calendar',
      'vcf': 'text/x-vcard',
      'xml': 'text/xml',
    }[ext];
  }

  /// Windows: «метка интернета» (поток Zone.Identifier, зона 3 — Интернет).
  /// По ней SmartScreen проверяет программы, а Office открывает документ в
  /// защищённом режиме. На файловых системах без потоков (FAT, сеть) молча
  /// пропускается.
  static Future<void> markFromInternet(String path) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await File('$path:Zone.Identifier')
          .writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n', flush: true);
    } catch (_) {}
  }
}
