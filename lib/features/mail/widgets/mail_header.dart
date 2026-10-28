// lib/features/mail/widgets/mail_header.dart
// Шапка письма (1.5.9): отправитель в верхней панели и получатели под темой.
// Вынесено из экрана письма (mail_detail_screen.dart, 3 000+ строк) —
// первый шаг его разделения на виджеты (разбор производительности 12.10.2026,
// раздел 5): шапка зависит только от письма и не тянет за собой состояние
// экрана.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/text_safe.dart';
import '../../../core/utils/person_names.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../contacts/widgets/person_card.dart';

/// Размер портрета в шапке: отправитель (верхняя панель) и получатели —
/// одинаковые.
const double kMailFaceRadius = 16;

/// Отправитель в верхней панели: портрет, ФИО, под ним дата (в беседе —
/// и номер письма). Нажатие — карточка человека (должность, телефоны,
/// руководитель).
class MailSenderTitle extends StatelessWidget {
  const MailSenderTitle({super.key, required this.email, this.hero = true, this.pagerLabel});

  final EmailModel email;

  /// Портрет летит из строки ленты (Hero) — не во встроенной панели планшета.
  final bool hero;

  /// «1 / 2» в беседе.
  final String? pagerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final date = DateFormat('d MMM, HH:mm', l10n.localeCode).format(email.receivedAt);
    final sub = pagerLabel == null ? date : '$date · $pagerLabel';
    final name = email.from.displayName ?? email.from.email;
    return InkWell(
      borderRadius: Radii.chipAll,
      onTap: () => showPersonCard(context,
          email: email.from.email, name: email.from.displayName, accountId: email.accountId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(children: [
          HeroEmailAvatar(
            emailId: '${email.accountId}/${email.id}',
            hero: hero,
            initial: name.isNotEmpty ? initialOf(name) : '?',
            color: HeroEmailAvatar.colorForEmail(email.from.email),
            email: email.from.email,
            radius: kMailFaceRadius,
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(email.from.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Получатели группы («Кому» или «Копия») друг под другом: значок группы —
/// у первой строки, у каждого — портрет того же размера, что у отправителя,
/// и ФИО обычным шрифтом. «Кому» — до трёх человек, «Копия» — до двух,
/// остальные — строкой «ещё N» ([onShowAll] — весь список). Нажатие на
/// человека — его карточка.
class MailRecipientList extends StatelessWidget {
  const MailRecipientList({
    super.key,
    required this.email,
    required this.people,
    required this.cc,
    required this.onShowAll,
  });

  final EmailModel email;
  final List<EmailAddress> people;
  final bool cc;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final what = l10n.tr(cc ? 'cc' : 'to');
    final icon = cc ? AppIcons.mailCc : AppIcons.mailTo;
    // Если скрыт всего один человек — он показывается вместо «ещё 1».
    final limit = cc ? 2 : 3;
    final shown = people.length <= limit + 1 ? people : people.take(limit).toList();
    final more = people.length - shown.length;
    final muted = AppColors.mutedText(context);

    Widget lead(bool first) => SizedBox(
          width: 20,
          child: first
              ? Tooltip(message: what, child: Icon(icon, size: 20, color: muted, semanticLabel: what))
              : null,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l - Space.s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var k = 0; k < shown.length; k++)
          InkWell(
            borderRadius: Radii.chipAll,
            onTap: () => showPersonCard(context,
                email: shown[k].email, name: shown[k].displayName, accountId: email.accountId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
              child: Row(children: [
                lead(k == 0),
                const SizedBox(width: Space.m),
                HeroEmailAvatar(
                  emailId: 'face_${email.id}_${cc ? 'cc' : 'to'}_$k',
                  hero: false,
                  radius: kMailFaceRadius,
                  email: shown[k].email,
                  initial: shown[k].label.isEmpty ? '?' : initialOf(shown[k].label),
                  color: HeroEmailAvatar.colorForEmail(shown[k].email),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(shown[k].label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
              ]),
            ),
          ),
        if (more > 0)
          InkWell(
            borderRadius: Radii.chipAll,
            onTap: onShowAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
              child: Row(children: [
                lead(false),
                const SizedBox(width: Space.m + kMailFaceRadius * 2 + Space.m),
                Text(l10n.tr('moreN').replaceAll('{n}', '$more'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────── компактные получатели (1.5.9) ─────────────────────────

/// Вид получателей в шапке письма — на выбор в «Настройки → Почта →
/// Получатели в письме»:
///  · [rows] — «Кому» и «Копия» строками: до двух человек (портрет 20 dp,
///    «Фамилия И.О.»), остальные — «+N», нажатие плавно раскрывает список
///    (≈ 48–56 dp вместо 130–170);
///  · [overlap] — одна строка: три монограммы внахлёст, «+N», «Морозов А.Н.
///    и ещё 11»; «Копия» — кнопкой справа;
///  · [line] — одна строка без портретов, главное — кому письмо: «вам», «вам
///    в копии» или первый получатель и число остальных (≈ 28 dp);
///  · [list] — списком, как в первой сборке 1.5.9.
enum RecipientsLayout { rows, overlap, line, list }

class MailRecipientsPanel extends StatefulWidget {
  const MailRecipientsPanel({
    super.key,
    required this.email,
    required this.layout,
    required this.onShowAll,
    this.isMine,
  });

  final EmailModel email;
  final RecipientsLayout layout;

  /// Весь список (шторка) — для вида [RecipientsLayout.list].
  final VoidCallback onShowAll;

  /// Адрес — свой (ящика): для «вам» в виде [RecipientsLayout.line].
  final bool Function(String email)? isMine;

  @override
  State<MailRecipientsPanel> createState() => _MailRecipientsPanelState();
}

class _MailRecipientsPanelState extends State<MailRecipientsPanel> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final e = widget.email;
    if (widget.layout == RecipientsLayout.list) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MailRecipientList(email: e, people: e.to, cc: false, onShowAll: widget.onShowAll),
        if (e.cc.isNotEmpty) MailRecipientList(email: e, people: e.cc, cc: true, onShowAll: widget.onShowAll),
      ]);
    }
    if (e.to.isEmpty && e.cc.isEmpty && e.bcc.isEmpty) return const SizedBox.shrink();
    final collapsed = switch (widget.layout) {
      RecipientsLayout.overlap => _overlap(context),
      RecipientsLayout.line => _line(context),
      _ => _rows(context),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        collapsed,
        // Плавное раскрытие полного списка.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open ? _full(context) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  String _short(EmailAddress a) => PersonNames.short(a.displayName, email: a.email);

  Widget _chevron(BuildContext context) => Icon(
        _open ? AppIcons.keyboard_arrow_up : AppIcons.keyboard_arrow_down,
        size: 20,
        color: AppColors.mutedText(context),
      );

  // ── Вариант 1: строками, до двух человек ──
  Widget _rows(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final e = widget.email;
    final muted = AppColors.mutedText(context);

    Widget group(bool cc, List<EmailAddress> people, bool chevron) {
      final shown = people.take(2).toList();
      final more = people.length - shown.length;
      final what = l10n.tr(cc ? 'cc' : 'to');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Tooltip(
            message: what,
            child: Icon(cc ? AppIcons.mailCc : AppIcons.mailTo, size: 18, color: muted, semanticLabel: what),
          ),
          const SizedBox(width: Space.s),
          for (var k = 0; k < shown.length; k++) ...[
            if (k > 0) const SizedBox(width: Space.s),
            Flexible(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _MailFace(email: e, person: shown[k], tag: '${cc ? 'cc' : 'to'}_$k', radius: 10),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_short(shown[k]),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
              ]),
            ),
          ],
          if (more > 0) ...[
            const SizedBox(width: Space.s),
            Text('+$more',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
          ],
          const Spacer(),
          if (chevron) _chevron(context),
        ]),
      );
    }

    final groups = <Widget>[
      if (e.to.isNotEmpty) group(false, e.to, true),
      if (e.cc.isNotEmpty) group(true, e.cc, e.to.isEmpty),
    ];
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: Radii.chipAll,
        onTap: _toggle,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: groups),
      ),
    );
  }

  // ── Вариант 2: портреты внахлёст, «Копия» — кнопкой ──
  Widget _overlap(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final e = widget.email;
    final main = e.to.isNotEmpty ? e.to : e.cc;
    final faces = main.take(3).toList();
    final more = main.length - faces.length;
    const r = 14.0, step = 20.0;
    final ring = theme.colorScheme.surface;
    final rest = main.length - 1;
    final chipText = _open
        ? l10n.tr('collapse')
        : (e.to.isNotEmpty && e.cc.isNotEmpty ? '${l10n.tr('cc')}: ${e.cc.length}' : '');
    return InkWell(
      borderRadius: Radii.chipAll,
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(children: [
          SizedBox(
            width: r * 2 + step * (faces.length - 1 + (more > 0 ? 1 : 0)) + 2,
            height: r * 2 + 2,
            child: Stack(children: [
              if (more > 0)
                Positioned(
                  left: step * faces.length,
                  child: _Bubble(
                    text: '+$more',
                    radius: r,
                    color: theme.colorScheme.surfaceContainerHighest,
                    fg: theme.colorScheme.onSurfaceVariant,
                    ring: ring,
                  ),
                ),
              // Портреты (фото из контактов и адресной книги, без фото —
              // буква), с кольцом цвета фона (1.5.10: были только
              // монограммы, фото не показывались).
              for (var i = faces.length - 1; i >= 0; i--)
                Positioned(
                  left: step * i,
                  child: Container(
                    width: r * 2 + 2,
                    height: r * 2 + 2,
                    decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: _MailFace(email: e, person: faces[i], tag: 'over_$i', radius: r),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: main.isEmpty ? '' : _short(main.first),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (rest > 0)
                  TextSpan(
                    text: ' ${l10n.tr('andNMore').replaceAll('{n}', '$rest')}',
                    style: TextStyle(color: AppColors.mutedText(context)),
                  ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Space.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (chipText.isNotEmpty)
                Text(chipText, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.mutedText(context))),
              _chevron(context),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Вариант 3: одна строка — кому письмо ──
  Widget _line(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final e = widget.email;
    final mine = widget.isMine ?? (_) => false;
    final muted = AppColors.mutedText(context);
    final strong = TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600);

    List<InlineSpan> part(List<EmailAddress> people, {required bool cc}) {
      final me = people.any((p) => mine(p.email));
      final others = people.length - 1;
      if (me) {
        return [
          TextSpan(text: l10n.tr(cc ? 'toYouCc' : 'toYou'), style: strong),
          if (others > 0) TextSpan(text: ' ${l10n.tr('andNMore').replaceAll('{n}', '$others')}'),
        ];
      }
      if (cc) return [TextSpan(text: '${people.length}')];
      return [
        TextSpan(text: _short(people.first), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (others > 0) TextSpan(text: ' ${l10n.tr('andNMore').replaceAll('{n}', '$others')}'),
      ];
    }

    WidgetSpan icon(IconData i) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(i, size: 16, color: muted)),
        );

    return InkWell(
      borderRadius: Radii.chipAll,
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (e.to.isNotEmpty) ...[icon(AppIcons.mailTo), ...part(e.to, cc: false)],
                if (e.to.isNotEmpty && e.cc.isNotEmpty) TextSpan(text: '   ·   ', style: TextStyle(color: muted)),
                if (e.cc.isNotEmpty) ...[icon(AppIcons.mailCc), ...part(e.cc, cc: true)],
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          _chevron(context),
        ]),
      ),
    );
  }

  // ── Полный список (раскрытый) ──
  Widget _full(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final e = widget.email;
    final muted = AppColors.mutedText(context);

    Widget section(String title, List<EmailAddress> people, String tag) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Space.s, bottom: 2),
              child: Text('$title · ${people.length}', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
            ),
            for (var k = 0; k < people.length; k++)
              InkWell(
                borderRadius: Radii.chipAll,
                onTap: () => showPersonCard(context,
                    email: people[k].email, name: people[k].displayName, accountId: e.accountId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    _MailFace(email: e, person: people[k], tag: 'full_${tag}_$k', radius: 12),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(people[k].label,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                    ),
                  ]),
                ),
              ),
          ],
        );

    // Длинный список (20–50 адресатов) прокручивается сам: шапка письма
    // закреплена, и список не должен занимать весь экран.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (e.to.isNotEmpty) section(l10n.tr('to'), e.to, 'to'),
          if (e.cc.isNotEmpty) section(l10n.tr('cc'), e.cc, 'cc'),
          if (e.bcc.isNotEmpty) section(l10n.tr('bcc'), e.bcc, 'bcc'),
          const SizedBox(height: Space.xs),
        ]),
      ),
    );
  }
}

/// Портрет получателя: фото из контактов или круглая цветная буква.
class _MailFace extends StatelessWidget {
  const _MailFace({required this.email, required this.person, required this.tag, required this.radius});
  final EmailModel email;
  final EmailAddress person;
  final String tag;
  final double radius;

  @override
  Widget build(BuildContext context) => HeroEmailAvatar(
        emailId: 'face_${email.id}_$tag',
        hero: false,
        radius: radius,
        email: person.email,
        initial: person.label.isEmpty ? '?' : initialOf(person.label),
        color: HeroEmailAvatar.colorForEmail(person.email),
      );
}

/// Кружок с монограммой или счётчиком «+N» (с кольцом цвета фона — круги
/// внахлёст не сливаются).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.radius, required this.color, required this.fg, required this.ring});
  final String text;
  final double radius;
  final Color color;
  final Color fg;
  final Color ring;

  @override
  Widget build(BuildContext context) => Container(
        width: radius * 2 + 2,
        height: radius * 2 + 2,
        decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            text,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: TextStyle(color: fg, fontSize: radius * 0.75, fontWeight: FontWeight.w600),
          ),
        ),
      );
}
