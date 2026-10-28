// lib/features/archive/archive_sheets.dart
// Шторки архива Ogneliss (1.7.3): создать архив (пароль → код
// восстановления), открыть паролем или кодом, сменить пароль, новый код,
// подключить копию (.ogna), «Архивировать сейчас». Ошибки — строкой в самой
// шторке, без всплывающих окон.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform/file_pick.dart' show FilePick;
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/app_date_format.dart';
import '../../l10n/app_localizations.dart';
import '../../services/archive/archive_container.dart';
import '../../services/archive/archive_db.dart' show ArchiveMergeReport;
import '../../services/archive/archive_runner.dart';
import '../../services/archive/archive_settings.dart';
import '../../services/archive/archive_vault.dart';
import '../../widgets/common/app_sheet.dart';
import '../../widgets/ui/app_radio_tile.dart';

/// Архив открыт; закрыт — спросить пароль. false — архива нет или не открыли.
Future<bool> ensureArchiveOpen(BuildContext context, WidgetRef ref) async {
  final s = await ref.read(archiveVaultProvider.future);
  if (s.isOpen) return true;
  if (s.status != ArchiveStatus.locked || !context.mounted) return false;
  return showArchiveUnlockSheet(context);
}

Future<bool> showArchiveCreateSheet(BuildContext context) async =>
    await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateSheet(),
    ) ==
    true;

Future<bool> showArchiveUnlockSheet(BuildContext context) async =>
    await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _UnlockSheet(),
    ) ==
    true;

Future<void> showArchivePasswordSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PasswordSheet(),
    );

Future<void> showArchiveNewCodeSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewCodeSheet(),
    );

/// Подключить копию архива (.ogna). [merge] — на устройстве уже есть свой
/// архив: копия с ним объединяется (28.10.2026).
Future<bool> showArchiveConnectSheet(BuildContext context, {bool merge = false}) async =>
    await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConnectSheet(merge: merge),
    ) ==
    true;

Future<void> showArchiveRunSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RunSheet(),
    );

/// Текст ошибки архива по ключу ArchiveFormatException или исключению.
String archiveErrorText(AppLocalizations l10n, Object e) {
  if (e is ArchiveFormatException) return l10n.tr(e.key);
  return '${l10n.tr('errorLbl')}: $e';
}

// ─────────────────────────── общие части ───────────────────────────

/// Каркас шторки: заголовок, содержимое, отступ под клавиатуру.
class _SheetFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SheetFrame({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: Space.m),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ]),
            const SizedBox(height: Space.m),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final bool error;
  const _Note(this.text, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = error ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (error) ...[
          Icon(AppIcons.error, size: 18, color: c),
          const SizedBox(width: Space.s),
        ],
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: c))),
      ]),
    );
  }
}

class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  const _PasswordField(this.controller, this.label, {this.autofocus = false, this.onSubmitted});

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autofocus,
        obscureText: !_show,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(AppIcons.key),
          suffixIcon: IconButton(
            tooltip: l10n.tr(_show ? 'hidePassword' : 'showPassword'),
            icon: Icon(_show ? AppIcons.visibility_off : AppIcons.visibility),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
      ),
    );
  }
}

Widget _busyIcon(bool busy, IconData icon) => busy
    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
    : Icon(icon);

/// Код восстановления: крупно, «Копировать», «Сохранить» и отметка «Код
/// записан» — без неё «Готово» не нажать.
class _CodeView extends StatefulWidget {
  final String code;
  final VoidCallback onDone;
  const _CodeView({required this.code, required this.onDone});

  @override
  State<_CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<_CodeView> {
  bool _saved = false;
  bool _copied = false;

  Future<void> _share(AppLocalizations l10n) async {
    final text = '${l10n.tr('archiveCodeFileTitle')}\n\n${widget.code}\n\n${l10n.tr('archiveCodeFileNote')}';
    try {
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'ogneliss-archive-recovery-code.txt'));
      await f.writeAsString(text, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: l10n.tr('archiveCodeFileTitle')));
      // Временный файл с кодом на телефоне не оставляем.
      unawaited(Future<void>.delayed(const Duration(minutes: 2), () async {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }));
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(l10n.tr('archiveCodeIntro'), style: theme.textTheme.bodyMedium),
      const SizedBox(height: Space.m),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.l),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: Radii.cardAll,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: SelectableText(
          widget.code,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Courier', 'RobotoMono'],
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: Space.s),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(_copied ? AppIcons.check : AppIcons.content_copy, size: 18),
            label: Text(l10n.tr(_copied ? 'copied' : 'copy')),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.code));
              if (!mounted) return;
              setState(() => _copied = true);
              unawaited(Future<void>.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              }));
            },
          ),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(AppIcons.save_alt, size: 18),
            label: Text(l10n.tr('save')),
            onPressed: () => _share(l10n),
          ),
        ),
      ]),
      const SizedBox(height: Space.s),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _saved,
        title: Text(l10n.tr('archiveCodeSaved')),
        onChanged: (v) => setState(() => _saved = v ?? false),
      ),
      FilledButton(onPressed: _saved ? widget.onDone : null, child: Text(l10n.tr('done'))),
    ]);
  }
}

// ─────────────────────────── создать ───────────────────────────

class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet();

  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _code;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _create(AppLocalizations l10n) async {
    setState(() => _error = null);
    if (_pw1.text.length < ArchiveVault.minPassword) {
      setState(() => _error = l10n.tr('archivePwShort'));
      return;
    }
    if (_pw1.text != _pw2.text) {
      setState(() => _error = l10n.tr('backupPwMismatch'));
      return;
    }
    setState(() => _busy = true);
    try {
      final code =
          await ref.read(archiveVaultProvider.notifier).create(password: _pw1.text, name: l10n.tr('ognaArchive'));
      // Настройки приложения — в архив сразу (25.10.2026).
      if (ref.read(archiveSettingsProvider).appSettings) {
        unawaited(ref.read(archiveRunnerProvider.notifier).saveAppSettings());
      }
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) setState(() => _error = archiveErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final code = _code;
    if (code != null) {
      return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archiveCodeTitle'), children: [
        _CodeView(code: code, onDone: () => Navigator.of(context).pop(true)),
      ]);
    }
    return _SheetFrame(icon: AppIcons.inventory_2, title: l10n.tr('archiveCreateTitle'), children: [
      Text(l10n.tr('archiveCreateIntro'), style: Theme.of(context).textTheme.bodyMedium),
      _PasswordField(_pw1, l10n.tr('archivePw'), autofocus: true),
      _PasswordField(_pw2, l10n.tr('backupPwRepeat'), onSubmitted: (_) => _create(l10n)),
      _Note(l10n.tr('archivePwHint')),
      if (_error != null) _Note(_error!, error: true),
      const SizedBox(height: Space.m),
      FilledButton.icon(
        onPressed: _busy ? null : () => _create(l10n),
        icon: _busyIcon(_busy, AppIcons.inventory_2),
        label: Text(l10n.tr('archiveCreate')),
      ),
    ]);
  }
}

// ─────────────────────────── открыть ───────────────────────────

/// Новый пароль (после входа кодом восстановления).
class _NewPasswordView extends ConsumerStatefulWidget {
  final String intro;
  final VoidCallback onDone;
  const _NewPasswordView({required this.intro, required this.onDone});

  @override
  ConsumerState<_NewPasswordView> createState() => _NewPasswordViewState();
}

class _NewPasswordViewState extends ConsumerState<_NewPasswordView> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save(AppLocalizations l10n) async {
    setState(() => _error = null);
    if (_pw1.text.length < ArchiveVault.minPassword) {
      setState(() => _error = l10n.tr('archivePwShort'));
      return;
    }
    if (_pw1.text != _pw2.text) {
      setState(() => _error = l10n.tr('backupPwMismatch'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(archiveVaultProvider.notifier).setPassword(_pw1.text);
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = archiveErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.intro, style: Theme.of(context).textTheme.bodyMedium),
      _PasswordField(_pw1, l10n.tr('archivePwNew'), autofocus: true),
      _PasswordField(_pw2, l10n.tr('backupPwRepeat'), onSubmitted: (_) => _save(l10n)),
      _Note(l10n.tr('archivePwHint')),
      if (_error != null) _Note(_error!, error: true),
      const SizedBox(height: Space.m),
      FilledButton.icon(
        onPressed: _busy ? null : () => _save(l10n),
        icon: _busyIcon(_busy, AppIcons.key),
        label: Text(l10n.tr('archivePwSave')),
      ),
    ]);
  }
}

class _UnlockSheet extends ConsumerStatefulWidget {
  const _UnlockSheet();

  @override
  ConsumerState<_UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends ConsumerState<_UnlockSheet> {
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _byCode = false;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _open(AppLocalizations l10n) async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final r = await ref.read(archiveVaultProvider.notifier).unlock(_secret.text);
      if (!mounted) return;
      switch (r) {
        case ArchiveUnlock.wrong:
          setState(() => _error = l10n.tr('archiveWrongSecret'));
        case ArchiveUnlock.password:
          Navigator.of(context).pop(true);
        case ArchiveUnlock.code:
          setState(() => _byCode = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = archiveErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_byCode) {
      return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archivePwNewTitle'), children: [
        _NewPasswordView(intro: l10n.tr('archiveOpenedByCode'), onDone: () => Navigator.of(context).pop(true)),
      ]);
    }
    return _SheetFrame(icon: AppIcons.lock_open, title: l10n.tr('archiveOpenTitle'), children: [
      Text(l10n.tr('archiveOpenIntro'), style: Theme.of(context).textTheme.bodyMedium),
      _PasswordField(_secret, l10n.tr('archivePwOrCode'), autofocus: true, onSubmitted: (_) => _open(l10n)),
      if (_error != null) _Note(_error!, error: true),
      const SizedBox(height: Space.m),
      FilledButton.icon(
        onPressed: _busy ? null : () => _open(l10n),
        icon: _busyIcon(_busy, AppIcons.lock_open),
        label: Text(l10n.tr('archiveOpen')),
      ),
    ]);
  }
}

// ─────────────────────────── пароль и код ───────────────────────────

class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _old = TextEditingController();
  bool _checked = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    super.dispose();
  }

  Future<void> _check(AppLocalizations l10n) async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final ok = await ref.read(archiveVaultProvider.notifier).checkSecret(_old.text);
      if (!mounted) return;
      setState(() => ok ? _checked = true : _error = l10n.tr('archiveWrongSecret'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_checked) {
      return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archivePwChange'), children: [
        _NewPasswordView(intro: l10n.tr('archivePwChangeIntro'), onDone: () => Navigator.of(context).pop()),
      ]);
    }
    return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archivePwChange'), children: [
      _PasswordField(_old, l10n.tr('archivePwOrCode'), autofocus: true, onSubmitted: (_) => _check(l10n)),
      if (_error != null) _Note(_error!, error: true),
      const SizedBox(height: Space.m),
      FilledButton(onPressed: _busy ? null : () => _check(l10n), child: Text(l10n.tr('next'))),
    ]);
  }
}

class _NewCodeSheet extends ConsumerStatefulWidget {
  const _NewCodeSheet();

  @override
  ConsumerState<_NewCodeSheet> createState() => _NewCodeSheetState();
}

class _NewCodeSheetState extends ConsumerState<_NewCodeSheet> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _code;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _renew(AppLocalizations l10n) async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final vault = ref.read(archiveVaultProvider.notifier);
      if (!await vault.checkSecret(_pw.text)) {
        if (mounted) setState(() => _error = l10n.tr('archiveWrongSecret'));
        return;
      }
      final code = await vault.renewRecoveryCode();
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) setState(() => _error = archiveErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final code = _code;
    if (code != null) {
      return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archiveCodeTitle'), children: [
        _CodeView(code: code, onDone: () => Navigator.of(context).pop()),
      ]);
    }
    return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archiveNewCode'), children: [
      Text(l10n.tr('archiveNewCodeIntro'), style: Theme.of(context).textTheme.bodyMedium),
      _PasswordField(_pw, l10n.tr('archivePw'), autofocus: true, onSubmitted: (_) => _renew(l10n)),
      if (_error != null) _Note(_error!, error: true),
      const SizedBox(height: Space.m),
      FilledButton(onPressed: _busy ? null : () => _renew(l10n), child: Text(l10n.tr('archiveNewCodeGet'))),
    ]);
  }
}

// ─────────────────────────── подключить копию ───────────────────────────

class _ConnectSheet extends ConsumerStatefulWidget {
  /// Объединить с архивом на устройстве, а не подключить вместо него.
  final bool merge;
  const _ConnectSheet({this.merge = false});

  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  final _secret = TextEditingController();
  File? _file;
  String? _name;
  ArchiveHeader? _header;
  bool _busy = false;
  String? _error;
  bool _byCode = false;

  /// Объединение: сколько писем перенесено из скольких; итог.
  int _done = 0;
  int _total = 0;
  ArchiveMergeReport? _report;

  /// Копия, выбранная без пути (Android отдал только содержимое), — во
  /// временной папке; удаляется после подключения.
  bool _temp = false;

  @override
  void dispose() {
    _secret.dispose();
    _dropTemp();
    super.dispose();
  }

  void _dropTemp() {
    final f = _file;
    if (_temp && f != null) {
      unawaited(() async {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }());
    }
  }

  Future<void> _pick(AppLocalizations l10n) async {
    setState(() => _error = null);
    final picked = await FilePick.file();
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      _dropTemp();
      File f;
      var temp = false;
      if (picked.path != null) {
        f = File(picked.path!);
      } else {
        final dir = await getTemporaryDirectory();
        f = File(p.join(dir.path, 'import-${DateTime.now().millisecondsSinceEpoch}.ogna'));
        await f.writeAsBytes(await picked.readBytes(), flush: true);
        temp = true;
      }
      final h = await ArchiveContainer.readHeader(f);
      if (!mounted) return;
      setState(() {
        _file = f;
        _temp = temp;
        _name = picked.name;
        _header = h.header;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _file = null;
          _header = null;
          _error = archiveErrorText(l10n, e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(AppLocalizations l10n) async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (widget.merge) {
        final r = await ref.read(archiveVaultProvider.notifier).merge(f, _secret.text, onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        });
        if (!mounted) return;
        // Пароль архива на устройстве не меняется — вход кодом копии нового
        // пароля не требует.
        setState(() => r.how == ArchiveUnlock.wrong ? _error = l10n.tr('archiveWrongSecret') : _report = r.report);
        return;
      }
      final r = await ref.read(archiveVaultProvider.notifier).connect(f, _secret.text);
      if (!mounted) return;
      switch (r) {
        case ArchiveUnlock.wrong:
          setState(() => _error = l10n.tr('archiveWrongSecret'));
        case ArchiveUnlock.password:
          Navigator.of(context).pop(true);
        case ArchiveUnlock.code:
          setState(() => _byCode = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = archiveErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_byCode) {
      return _SheetFrame(icon: AppIcons.key, title: l10n.tr('archivePwNewTitle'), children: [
        _NewPasswordView(intro: l10n.tr('archiveOpenedByCode'), onDone: () => Navigator.of(context).pop(true)),
      ]);
    }
    final report = _report;
    if (report != null) {
      return _SheetFrame(icon: AppIcons.merge, title: l10n.tr('archiveMergeTitle'), children: [
        Text(
            l10n
                .tr('archiveMergeDone')
                .replaceAll('{n}', AppDateFormat.number(context, report.messages))
                .replaceAll('{skipped}', AppDateFormat.number(context, report.skipped)),
            style: theme.textTheme.bodyMedium),
        if (report.events + report.tasks + report.contacts > 0)
          _Note(l10n
              .tr('archiveStatOther')
              .replaceAll('{events}', '${report.events}')
              .replaceAll('{tasks}', '${report.tasks}')
              .replaceAll('{contacts}', '${report.contacts}')),
        _Note(l10n.tr('archiveMergeAfter')),
        const SizedBox(height: Space.m),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.tr('done'))),
      ]);
    }
    final h = _header;
    final merging = widget.merge && _busy && h != null;
    return _SheetFrame(
        icon: widget.merge ? AppIcons.merge : AppIcons.folder_open,
        title: l10n.tr(widget.merge ? 'archiveMergeTitle' : 'archiveConnectTitle'),
        children: [
      Text(l10n.tr(widget.merge ? 'archiveMergeIntro' : 'archiveConnectIntro'), style: theme.textTheme.bodyMedium),
      const SizedBox(height: Space.s),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _pick(l10n),
        icon: const Icon(AppIcons.folder_open),
        label: Text(_name ?? l10n.tr('archiveConnectPick'), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      if (h != null)
        _Note(l10n
            .tr('archiveConnectFound')
            .replaceAll('{name}', h.name.isEmpty ? l10n.tr('ognaArchive') : h.name)
            .replaceAll('{date}', AppDateFormat.date(context, h.created))),
      if (h != null) _PasswordField(_secret, l10n.tr('archivePwOrCode'), onSubmitted: (_) => _connect(l10n)),
      if (_error != null) _Note(_error!, error: true),
      if (merging && _total > 0) ...[
        const SizedBox(height: Space.m),
        LinearProgressIndicator(value: _done / _total),
        _Note(l10n.tr('archiveMerging').replaceAll('{done}', '$_done').replaceAll('{total}', '$_total')),
      ],
      const SizedBox(height: Space.m),
      FilledButton.icon(
        onPressed: _busy || h == null ? null : () => _connect(l10n),
        icon: _busyIcon(_busy && h != null, widget.merge ? AppIcons.merge : AppIcons.lock_open),
        label: Text(l10n.tr(widget.merge ? 'archiveMergeRun' : 'archiveConnect')),
      ),
    ]);
  }
}

// ─────────────────────────── архивировать сейчас ───────────────────────────

class _RunSheet extends ConsumerStatefulWidget {
  const _RunSheet();

  @override
  ConsumerState<_RunSheet> createState() => _RunSheetState();
}

class _RunSheetState extends ConsumerState<_RunSheet> {
  late int _months = ref.read(archiveSettingsProvider).months;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(archiveSettingsProvider);
    final options = {...ArchiveSettings.monthOptions, _months}.toList()..sort();
    return _SheetFrame(icon: AppIcons.inventory_2, title: l10n.tr('archiveRunNow'), children: [
      Text(l10n.tr('archiveRunWhat'), style: Theme.of(context).textTheme.bodyMedium),
      for (final m in [...options.where((m) => m > 0), 0])
        AppRadioTile<int>(
          value: m,
          groupValue: _months,
          onChanged: (v) => setState(() => _months = v ?? _months),
          title: Text(m == 0 ? l10n.tr('archiveAllMail') : l10n.plural('archiveOlderThanN', m)),
        ),
      _Note(l10n.tr(s.deleteFromServer ? 'archiveRunDeletes' : 'archiveRunCopies')),
      if (!s.includeFlagged) _Note(l10n.tr('archiveRunSkipsFlagged')),
      const SizedBox(height: Space.m),
      FilledButton.icon(
        icon: const Icon(AppIcons.play_arrow),
        label: Text(l10n.tr('archiveRunStart')),
        onPressed: () {
          Navigator.of(context).pop();
          unawaited(ref.read(archiveRunnerProvider.notifier).run(manual: true, months: _months));
        },
      ),
    ]);
  }
}
