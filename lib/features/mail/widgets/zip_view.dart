// lib/features/mail/widgets/zip_view.dart
// Архивы внутри приложения (1.8.14, просьба пользователей через владельца
// 29.10.2026: «открытие zip, даже с паролем»). Пакет archive (MIT) — уже в
// проекте: zip (и с паролем — ZipCrypto и AES), tar, tar.gz/tgz,
// tar.bz2, tar.xz; gz, bz2 и xz с одним файлом. 7z и RAR — внешним
// приложением (свободной библиотеки для них на Dart нет).
//
// Список строится без распаковки (оглавление архива), в отдельном изоляте.
// Файл распаковывается, когда его открывают, — тоже в изоляте, во
// временную папку, и открывается как вложение письма: PDF, картинка, текст,
// письмо, вложенный архив — в приложении, остальное — своей программой.
// Защита: имя файла в архиве — только последняя часть пути (без «..» и
// корня, «zip slip»); файл больше 2 ГБ не распаковывается («zip-бомба»).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/file_type_icon.dart';

enum PackedKind { zip, tar, tgz, tbz, txz, gz, bz2, xz }

/// Файл или папка в архиве.
class PackedEntry {
  /// Путь в архиве без «/» в конце: «docs/2025/отчёт.pdf».
  final String path;
  final int size;
  final DateTime? modified;
  final bool encrypted;
  final bool isDir;
  const PackedEntry(this.path, this.size, this.modified, {this.encrypted = false, this.isDir = false});

  String get name => path.split('/').last;
}

class PackedNeedsPassword implements Exception {
  const PackedNeedsPassword();
}

class PackedWrongPassword implements Exception {
  const PackedWrongPassword();
}

class PackedArchive {
  PackedArchive._();

  /// Больше — не распаковывается.
  static const maxEntryBytes = 2 * 1024 * 1024 * 1024;

  /// Больше записей — оглавление обрезается.
  static const maxEntries = 20000;

  static PackedKind? kindOf(String fileName) {
    final n = fileName.toLowerCase();
    if (n.endsWith('.zip')) return PackedKind.zip;
    if (n.endsWith('.tar')) return PackedKind.tar;
    if (n.endsWith('.tar.gz') || n.endsWith('.tgz')) return PackedKind.tgz;
    if (n.endsWith('.tar.bz2') || n.endsWith('.tbz2') || n.endsWith('.tbz')) return PackedKind.tbz;
    if (n.endsWith('.tar.xz') || n.endsWith('.txz')) return PackedKind.txz;
    if (n.endsWith('.gz')) return PackedKind.gz;
    if (n.endsWith('.bz2')) return PackedKind.bz2;
    if (n.endsWith('.xz')) return PackedKind.xz;
    return null;
  }

  /// Оглавление архива (в изоляте).
  static Future<List<PackedEntry>> list(String path, PackedKind kind, String fileName) =>
      Isolate.run(() => _list(path, kind, fileName));

  static List<PackedEntry> _list(String path, PackedKind kind, String fileName) {
    switch (kind) {
      case PackedKind.zip:
        final input = InputFileStream(path);
        try {
          final dir = ZipDirectory()..read(input);
          return [
            for (final h in dir.fileHeaders.take(maxEntries))
              if (_clean(h.filename).isNotEmpty)
                PackedEntry(
                  _clean(h.filename),
                  h.uncompressedSize,
                  _dosTime(h.lastModifiedFileDate, h.lastModifiedFileTime),
                  encrypted: h.generalPurposeBitFlag & 1 == 1,
                  isDir: h.filename.endsWith('/') || h.filename.endsWith('\\'),
                ),
          ];
        } finally {
          input.closeSync();
        }
      case PackedKind.tar:
      case PackedKind.tgz:
      case PackedKind.tbz:
      case PackedKind.txz:
        final tar = _tarArchive(path, kind);
        return [
          for (final f in tar.files.take(maxEntries))
            if (_clean(f.name).isNotEmpty)
              PackedEntry(_clean(f.name), f.size, f.lastModDateTime, isDir: !f.isFile),
        ];
      case PackedKind.gz:
      case PackedKind.bz2:
      case PackedKind.xz:
        // Один файл: имя — без расширения сжатия.
        final inner = fileName.replaceFirst(RegExp(r'\.(gz|bz2|xz)$', caseSensitive: false), '');
        return [PackedEntry(inner.isEmpty ? 'file' : inner, -1, null)];
    }
  }

  static Archive _tarArchive(String path, PackedKind kind) {
    if (kind == PackedKind.tar) return TarDecoder().decodeStream(InputFileStream(path));
    final bytes = File(path).readAsBytesSync();
    final tar = switch (kind) {
      PackedKind.tgz => const GZipDecoder().decodeBytes(bytes),
      PackedKind.tbz => BZip2Decoder().decodeBytes(bytes),
      _ => XZDecoder().decodeBytes(bytes),
    };
    return TarDecoder().decodeBytes(tar);
  }

  /// Путь без корня, «..» и «.»; «\» Windows — «/».
  static String _clean(String raw) =>
      raw.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty && s != '.' && s != '..').join('/');

  static DateTime? _dosTime(int date, int time) {
    if (date == 0) return null;
    try {
      return DateTime((date >> 9) + 1980, (date >> 5) & 0x0f, date & 0x1f, time >> 11, (time >> 5) & 0x3f,
          (time & 0x1f) * 2);
    } catch (_) {
      return null;
    }
  }

  /// Варианты пароля: как набран и в однобайтовых кодировках, которыми его
  /// мог записать архиватор (UTF-8, Windows-1251, DOS 866) — у русских
  /// паролей ZIP ровно здесь чаще всего «неверный пароль».
  static List<String> _passwordVariants(String pw) {
    final out = <String>{pw, String.fromCharCodes(utf8.encode(pw))};
    if (pw.runes.any((r) => r >= 0x410 && r <= 0x451)) {
      String map(int Function(int) f) => String.fromCharCodes([for (final r in pw.runes) f(r)]);
      out.add(map(_cp1251));
      out.add(map(_cp866));
    }
    return out.toList();
  }

  static int _cp1251(int r) {
    if (r >= 0x410 && r <= 0x44f) return r - 0x410 + 0xc0;
    if (r == 0x401) return 0xa8;
    if (r == 0x451) return 0xb8;
    return r < 0x100 ? r : 0x3f;
  }

  static int _cp866(int r) {
    if (r >= 0x410 && r <= 0x42f) return r - 0x410 + 0x80;
    if (r >= 0x430 && r <= 0x43f) return r - 0x430 + 0xa0;
    if (r >= 0x440 && r <= 0x44f) return r - 0x440 + 0xe0;
    if (r == 0x401) return 0xf0;
    if (r == 0x451) return 0xf1;
    return r < 0x100 ? r : 0x3f;
  }

  /// Проверить пароль на самом маленьком зашифрованном файле; вернуть
  /// вариант, который подошёл.
  static Future<String> checkPassword(String path, List<PackedEntry> entries, String password) =>
      Isolate.run(() => _checkPassword(path, entries, password));

  static String _checkPassword(String path, List<PackedEntry> entries, String password) {
    final enc = entries.where((e) => e.encrypted && !e.isDir).toList()..sort((a, b) => a.size.compareTo(b.size));
    if (enc.isEmpty) return password;
    final probe = enc.first;
    for (final pw in _passwordVariants(password)) {
      final input = InputFileStream(path);
      try {
        final a = ZipDecoder().decodeStream(input, password: pw);
        final f = a.files.where((x) => _clean(x.name) == probe.path).firstOrNull;
        if (f == null) continue;
        f.readBytes();
        return pw;
      } on ArchiveException {
        continue;
      } catch (_) {
        continue;
      } finally {
        input.closeSync();
      }
    }
    throw const PackedWrongPassword();
  }

  /// Распаковать файл [entry] в [destDir] (в изоляте); путь к файлу.
  static Future<String> extract(String path, PackedKind kind, PackedEntry entry, String destDir, {String? password}) =>
      Isolate.run(() => _extract(path, kind, entry, destDir, password));

  static String _extract(String path, PackedKind kind, PackedEntry entry, String destDir, String? password) {
    if (entry.size > maxEntryBytes) throw const FileSystemException('too large');
    Directory(destDir).createSync(recursive: true);
    // Только последняя часть имени: файл не выйдет за пределы папки.
    final out = '$destDir${Platform.pathSeparator}${entry.name.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')}';
    switch (kind) {
      case PackedKind.zip:
        if (entry.encrypted && password == null) throw const PackedNeedsPassword();
        final input = InputFileStream(path);
        try {
          final a = ZipDecoder().decodeStream(input, password: password);
          final f = a.files.where((x) => _clean(x.name) == entry.path).firstOrNull;
          if (f == null) throw const FileSystemException('not found');
          final o = OutputFileStream(out);
          try {
            f.writeContent(o);
          } on ArchiveException {
            throw const PackedWrongPassword();
          } finally {
            o.closeSync();
          }
        } finally {
          input.closeSync();
        }
      case PackedKind.tar:
      case PackedKind.tgz:
      case PackedKind.tbz:
      case PackedKind.txz:
        final f = _tarArchive(path, kind).files.where((x) => _clean(x.name) == entry.path).firstOrNull;
        if (f == null) throw const FileSystemException('not found');
        final o = OutputFileStream(out);
        try {
          f.writeContent(o);
        } finally {
          o.closeSync();
        }
      case PackedKind.gz:
      case PackedKind.bz2:
      case PackedKind.xz:
        final o = OutputFileStream(out);
        try {
          final input = InputFileStream(path);
          try {
            switch (kind) {
              case PackedKind.gz:
                const GZipDecoder().decodeStream(input, o);
              case PackedKind.bz2:
                BZip2Decoder().decodeStream(input, o);
              default:
                XZDecoder().decodeStream(input, o);
            }
          } finally {
            input.closeSync();
          }
        } finally {
          o.closeSync();
        }
    }
    return out;
  }

  /// Папка для распаковки этого архива (временная; старше суток — удаляются).
  static Future<String> tempDirFor(String path) async {
    final base = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}ogneliss-unpacked');
    try {
      if (await base.exists()) {
        final old = DateTime.now().subtract(const Duration(days: 1));
        await for (final d in base.list()) {
          if (d is Directory && (await d.stat()).modified.isBefore(old)) {
            unawaited(d.delete(recursive: true).then((_) {}, onError: (Object _) {}));
          }
        }
      }
    } catch (_) {}
    final id = sha1.convert(utf8.encode(path)).toString().substring(0, 12);
    return '${base.path}${Platform.pathSeparator}$id';
  }
}

/// Содержимое архива: папки, файлы, пароль.
class ZipView extends StatefulWidget {
  const ZipView({super.key, required this.path, required this.fileName, required this.onOpen, required this.onFailed});

  final String path;
  final String fileName;

  /// Открыть распакованный файл (как вложение письма).
  final Future<void> Function(String path, String name) onOpen;

  /// Архив не читается (повреждён, формат) — экран предложит другое
  /// приложение.
  final void Function(Object error) onFailed;

  @override
  State<ZipView> createState() => _ZipViewState();
}

class _ZipViewState extends State<ZipView> {
  late final PackedKind _kind = PackedArchive.kindOf(widget.fileName)!;
  List<PackedEntry>? _entries;
  String _dir = '';
  String? _password;
  bool _needPassword = false;
  bool _wrongPassword = false;
  bool _checking = false;
  final _pw = TextEditingController();
  bool _pwVisible = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await PackedArchive.list(widget.path, _kind, widget.fileName);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _needPassword = list.any((e) => e.encrypted);
      });
    } catch (e) {
      if (mounted) widget.onFailed(e);
    }
  }

  Future<void> _submitPassword() async {
    final pw = _pw.text;
    if (pw.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _wrongPassword = false;
    });
    try {
      final ok = await PackedArchive.checkPassword(widget.path, _entries ?? const [], pw);
      if (!mounted) return;
      setState(() {
        _password = ok;
        _needPassword = false;
      });
    } on PackedWrongPassword {
      if (mounted) setState(() => _wrongPassword = true);
    } catch (_) {
      if (mounted) setState(() => _wrongPassword = true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _open(PackedEntry e) async {
    if (_busy.contains(e.path)) return;
    setState(() => _busy.add(e.path));
    try {
      final dir = await PackedArchive.tempDirFor(widget.path);
      final out = await PackedArchive.extract(widget.path, _kind, e, dir, password: _password);
      if (!mounted) return;
      await widget.onOpen(out, e.name);
    } on PackedNeedsPassword {
      if (mounted) setState(() => _needPassword = true);
    } on PackedWrongPassword {
      if (mounted) {
        setState(() {
          _needPassword = true;
          _wrongPassword = true;
          _password = null;
        });
      }
    } catch (err) {
      if (mounted) widget.onFailed(err);
    } finally {
      if (mounted) setState(() => _busy.remove(e.path));
    }
  }

  /// Что лежит прямо в папке [_dir]: подпапки (и из путей файлов — у
  /// многих zip папок отдельными записями нет) и файлы.
  ({List<String> dirs, List<PackedEntry> files}) _here() {
    final prefix = _dir.isEmpty ? '' : '$_dir/';
    final dirs = <String>{};
    final files = <PackedEntry>[];
    for (final e in _entries ?? const <PackedEntry>[]) {
      if (!e.path.startsWith(prefix) || e.path == _dir) continue;
      final rest = e.path.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash >= 0) {
        dirs.add(rest.substring(0, slash));
      } else if (e.isDir) {
        dirs.add(rest);
      } else {
        files.add(e);
      }
    }
    final d = dirs.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return (dirs: d, files: files);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final entries = _entries;
    if (entries == null) return const Center(child: CircularProgressIndicator());
    final here = _here();
    final files = entries.where((e) => !e.isDir).toList();
    final total = files.fold<int>(0, (s, e) => s + (e.size > 0 ? e.size : 0));
    return ListView(
      children: [
        if (_needPassword)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(AppIcons.lock, size: 20, color: muted),
                const SizedBox(width: Space.s),
                Expanded(child: Text(l10n.tr('zipPasswordNeeded'), style: theme.textTheme.titleSmall)),
              ]),
              const SizedBox(height: Space.s),
              TextField(
                controller: _pw,
                obscureText: !_pwVisible,
                autofocus: true,
                enabled: !_checking,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.tr('zipPassword'),
                  errorText: _wrongPassword ? l10n.tr('zipWrongPassword') : null,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_pwVisible ? AppIcons.visibility_off : AppIcons.visibility),
                    onPressed: () => setState(() => _pwVisible = !_pwVisible),
                  ),
                ),
                onSubmitted: (_) => _submitPassword(),
              ),
              const SizedBox(height: Space.s),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _checking ? null : _submitPassword,
                  child: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.tr('zipOpen')),
                ),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
          child: Text(
            l10n
                .tr('zipSummary')
                .replaceAll('{n}', AppDateFormat.number(context, files.length))
                .replaceAll('{size}', AppDateFormat.bytes(context, total)),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
        if (_dir.isNotEmpty)
          ListTile(
            leading: const Icon(AppIcons.arrow_upward),
            title: Text(_dir.replaceAll('/', ' › ')),
            onTap: () => setState(() {
              final i = _dir.lastIndexOf('/');
              _dir = i < 0 ? '' : _dir.substring(0, i);
            }),
          ),
        for (final d in here.dirs)
          ListTile(
            leading: Icon(AppIcons.folder, color: muted),
            title: Text(d, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(AppIcons.chevron_right, color: muted),
            onTap: () => setState(() => _dir = _dir.isEmpty ? d : '$_dir/$d'),
          ),
        for (final f in here.files)
          ListTile(
            leading: FileTypeIcon(category: FileTypeStyle.categoryOf('', f.name)),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (f.size >= 0) AppDateFormat.bytes(context, f.size),
                if (f.modified != null) AppDateFormat.date(context, f.modified!),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            trailing: _busy.contains(f.path)
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : (f.encrypted && _password == null ? Icon(AppIcons.lock, size: 18, color: muted) : null),
            onTap: () => _open(f),
          ),
        const SizedBox(height: Space.xl),
      ],
    );
  }
}
