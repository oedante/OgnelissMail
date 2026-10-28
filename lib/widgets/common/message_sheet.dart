// lib/widgets/common/message_sheet.dart
// Шторка «несколько слов перед отправкой» (1.6.38): пересылка приглашения,
// комментарий к ответу на встречу. Раньше — системные окна AlertDialog с
// полем в рамке, не похожие на остальное приложение (замечание 18.10.2026:
// «окно с сообщением при пересылке сделать в соответствии с остальным
// интерфейсом»). Теперь — как остальные шторки: ручка сверху, заголовок со
// значком, получатели — с портретами (можно убрать и добавить), поле — в
// стиле полей приложения (заливка, без рамки), кнопка во всю ширину.

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_safe.dart';
import '../../l10n/app_localizations.dart';
import 'app_sheet.dart';
import 'hero_email_transition.dart';
import '../../core/theme/ogneliss_look.dart';

/// Получатель в шторке.
class SheetPerson {
  final String email;
  final String? name;
  const SheetPerson(this.email, [this.name]);

  String get label => (name ?? '').trim().isNotEmpty ? name!.trim() : email;
}

/// Итог шторки: текст и (если были получатели) окончательный список.
typedef MessageSheetResult = ({String text, List<SheetPerson> people});

/// Показать шторку. null — закрыли без отправки.
///
/// [people] — получатели (null — шторка без строки «Кому»), [onAddPeople] —
/// выбрать ещё (кнопка «Добавить»; получает адреса уже выбранных).
Future<MessageSheetResult?> showMessageSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData icon = AppIcons.send,
  Color? iconColor,
  List<SheetPerson>? people,
  Future<List<SheetPerson>> Function(Set<String> exclude)? onAddPeople,
  required String hint,
  required String actionLabel,
  IconData actionIcon = AppIcons.send,
}) {
  return showAppSheet<MessageSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MessageSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      people: people,
      onAddPeople: onAddPeople,
      hint: hint,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
    ),
  );
}

class _MessageSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final List<SheetPerson>? people;
  final Future<List<SheetPerson>> Function(Set<String> exclude)? onAddPeople;
  final String hint;
  final String actionLabel;
  final IconData actionIcon;

  const _MessageSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.people,
    required this.onAddPeople,
    required this.hint,
    required this.actionLabel,
    required this.actionIcon,
  });

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  final _ctrl = TextEditingController();
  late final List<SheetPerson>? _people = widget.people == null ? null : [...widget.people!];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final add = widget.onAddPeople;
    if (add == null) return;
    final have = {for (final p in _people ?? const <SheetPerson>[]) p.email.toLowerCase()};
    final more = await add(have);
    if (!mounted || more.isEmpty) return;
    setState(() {
      for (final p in more) {
        if (have.add(p.email.toLowerCase())) _people!.add(p);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = widget.iconColor ?? scheme.primary;
    final people = _people;
    final canSend = people == null || people.isNotEmpty;
    return Padding(
      // Клавиатура не закрывает поле и кнопку.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Заголовок: значок в круге, название, пояснение.
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(widget.icon, size: 22, color: accent),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if ((widget.subtitle ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                ]),
              ),
            ]),
            if (people != null) ...[
              const SizedBox(height: Space.l),
              // Подпись раздела — как SectionBand: с 1.8.0 синим, обычным
              // регистром; в высоком контрасте — прописными серыми.
              OgnelissLook.of(context).outlined
                  ? Text(l10n.tr('toLbl').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.8))
                  : Text(l10n.tr('toLbl'),
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w500)),
              const SizedBox(height: Space.s),
              Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                for (final p in people)
                  InputChip(
                    avatar: HeroEmailAvatar(
                      emailId: 'sheet_${p.email}',
                      initial: initialOf(p.label),
                      color: HeroEmailAvatar.colorForEmail(p.email),
                      email: p.email,
                      radius: 12,
                      hero: false,
                    ),
                    label: Text(p.label, overflow: TextOverflow.ellipsis),
                    tooltip: p.email,
                    onDeleted: () => setState(() => people.remove(p)),
                  ),
                if (widget.onAddPeople != null)
                  ActionChip(
                    avatar: Icon(AppIcons.person_add, size: 18, color: scheme.primary),
                    label: Text(l10n.tr('add')),
                    onPressed: _add,
                  ),
              ]),
            ],
            const SizedBox(height: Space.l),
            // Поле — в стиле полей приложения (тема: заливка, без рамки).
            TextField(
              controller: _ctrl,
              autofocus: people == null || people.isNotEmpty,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: widget.hint),
            ),
            const SizedBox(height: Space.l),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Sizes.tapTarget)),
              icon: Icon(widget.actionIcon, size: 18),
              label: Text(widget.actionLabel),
              onPressed: canSend
                  ? () => Navigator.of(context).pop<MessageSheetResult>(
                      (text: _ctrl.text, people: people ?? const <SheetPerson>[]))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
