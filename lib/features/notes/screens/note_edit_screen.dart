// lib/features/notes/screens/note_edit_screen.dart
// Создание/редактирование заметки. Соответствует эталону «Create a note»:
// поле заголовка, аккаунт-папка, поле текста. Сохранение локально + на сервер.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../mail/providers/mail_providers.dart';
import '../providers/notes_provider.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;

class NoteEditScreen extends ConsumerStatefulWidget {
  /// id существующей заметки (null — создание новой).
  final String? noteId;
  /// Панель справа от списка (планшет): вместо возврата назад — этот вызов,
  /// вместо стрелки «Назад» — крестик; несохранённое сохраняется при смене
  /// заметки или закрытии панели.
  final VoidCallback? onDone;
  const NoteEditScreen({super.key, this.noteId, this.onDone});

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _loading = false;
  bool _dirty = false;
  bool _saved = false;
  late final NotesNotifier _notes;
  String? _accountId;

  bool get _embedded => widget.onDone != null;

  void _close() {
    if (_embedded) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _notes = ref.read(notesNotifierProvider);
    _accountId = ref.read(activeAccountProvider)?.id;
    if (widget.noteId != null) {
      _load();
    }
    _titleController.addListener(() => _dirty = true);
    _bodyController.addListener(() => _dirty = true);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final note = await ref.read(notesNotifierProvider).getById(widget.noteId!);
    if (note != null && mounted) {
      _titleController.text = note.title;
      _bodyController.text = note.body;
      _dirty = false;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    // Панель планшета: открыли другую заметку или закрыли панель — правка
    // не теряется (на телефоне по-прежнему «Сохранить» или назад без записи).
    if (_embedded && _dirty && !_saved) {
      final title = _titleController.text.trim();
      final body = _bodyController.text;
      if (title.isNotEmpty || body.trim().isNotEmpty) {
        if (widget.noteId == null) {
          unawaited(_notes.create(title: title, body: body, accountId: _accountId));
        } else {
          unawaited(_notes.update(widget.noteId!, title: title, body: body));
        }
      }
    }
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final title = _titleController.text.trim();
    final body = _bodyController.text;
    if (title.isEmpty && body.trim().isEmpty) {
      _close();
      return;
    }

    final account = ref.read(activeAccountProvider);
    final notifier = ref.read(notesNotifierProvider);
    try {
      if (widget.noteId == null) {
        await notifier.create(title: title, body: body, accountId: account?.id);
      } else {
        await notifier.update(widget.noteId!, title: title, body: body);
      }
      unawaited(HapticFeedback.mediumImpact());
      _saved = true;
      if (mounted) _close();
    } catch (e) {
      if (mounted) {
        showInlineError('${l10n.error}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(activeAccountProvider);
    final canSave = _titleController.text.trim().isNotEmpty || _bodyController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        leading: _embedded
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(AppIcons.close),
                onPressed: _close,
              )
            : const BackButton(),
        title: Text(widget.noteId == null ? l10n.tr('createNote') : l10n.tr('editNote')),
        actions: [
          TextButton(
            onPressed: canSave ? _save : null,
            child: Text(l10n.save,
                style: TextStyle(
                  color: canSave ? AppColors.accent(context) : Theme.of(context).disabledColor,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
                  child: TextField(
                    controller: _titleController,
                    style: Theme.of(context).textTheme.titleLarge,
                    decoration: InputDecoration(
                      hintText: l10n.tr('enterTitle'),
                      border: InputBorder.none,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                // Папка заметок (аккаунт), как в эталоне
                if (account != null)
                  ListTile(
                    leading: Icon(AppIcons.folder, color: AppColors.accent(context)),
                    title: Text(l10n.tr('notes')),
                    subtitle: Text(account.email),
                    dense: true,
                  ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: l10n.tr('noteHint'),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
