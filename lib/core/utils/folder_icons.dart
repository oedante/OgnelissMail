// lib/core/utils/folder_icons.dart
// Значки папок — одни и те же в меню, при переносе писем и в настройках
// синхронизации. Системные папки — по типу; распространённые служебные
// папки серверов (Заметки, Чаты Gmail, Шаблоны, Важное, Помеченные,
// Календарь, Контакты, Задачи, Журнал) — по имени, остальные — папкой.

import 'package:flutter/material.dart';
import '../theme/app_icons.dart';

import '../../data/models/folder_model.dart';

IconData folderTypeIcon(FolderType type) => switch (type) {
      FolderType.inbox => AppIcons.inbox,
      FolderType.sent => AppIcons.send,
      FolderType.drafts => AppIcons.drafts,
      FolderType.trash => AppIcons.delete,
      FolderType.junk => AppIcons.report,
      FolderType.archive => AppIcons.archive,
      FolderType.outbox => AppIcons.outbox,
      FolderType.custom => AppIcons.folder,
    };

IconData folderIconOf(FolderModel f) {
  if (f.type != FolderType.custom) return folderTypeIcon(f.type);
  // Последняя часть пути: «[Gmail]/Важные», «INBOX.Notes».
  final raw = f.displayName.toLowerCase();
  final name = raw.split(RegExp(r'[/.\\]')).last.trim();
  bool any(List<String> words) => words.any((w) => name == w || name.startsWith(w));
  if (any(['notes', 'заметки', 'notizen'])) return AppIcons.sticky_note_2;
  if (any(['chats', 'чаты', 'conversation history', 'журнал бесед'])) return AppIcons.chat_bubble;
  if (any(['template', 'шаблон', 'vorlagen', 'modèles'])) return AppIcons.description;
  if (any(['important', 'важн', 'wichtig'])) return AppIcons.label_important;
  if (any(['starred', 'flagged', 'помечен', 'отмечен', 'избранн'])) return AppIcons.star;
  if (any(['all mail', 'вся почта', 'alle nachrichten', 'tous les messages'])) return AppIcons.all_inbox;
  if (any(['calendar', 'календарь', 'kalender', 'calendrier'])) return AppIcons.calendar_today;
  if (any(['contacts', 'контакты', 'kontakte'])) return AppIcons.contacts;
  if (any(['tasks', 'задачи', 'aufgaben', 'tâches'])) return AppIcons.task_alt;
  if (any(['journal', 'дневник'])) return AppIcons.book;
  if (any(['rss', 'новостные'])) return AppIcons.rss_feed;
  if (any(['archive', 'архив'])) return AppIcons.archive;
  if (any(['social', 'соцсети', 'promotions', 'рассылки', 'newsletters'])) return AppIcons.campaign;
  if (any(['sync issues', 'проблемы синхронизации', 'conflicts', 'конфликты'])) return AppIcons.sync_problem;
  return AppIcons.folder;
}
