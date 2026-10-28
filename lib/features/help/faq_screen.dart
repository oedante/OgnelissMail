// lib/features/help/faq_screen.dart
// «Вопросы и ответы» (1.7.1): разделы серыми полосами, как в настройках,
// вопросы — карточками, ответ раскрывается касанием; поиск по вопросам и
// ответам. Если ответ про настройку — кнопка «Открыть» ведёт к ней.
// Открывается из «Настройки → Вопросы и ответы» и из поиска по настройкам;
// с ?section=<id> — сразу нужный раздел (кнопка «?» в разделах приложения).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/text_scale_cap.dart';
import '../../widgets/ui/settings_group.dart';
import 'faq_content.dart';

class FaqScreen extends StatefulWidget {
  /// Раздел, который открыть сразу (id из [faqSections]).
  final String? section;
  const FaqScreen({super.key, this.section});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final _search = TextEditingController();
  final _open = <String>{};
  final _sectionKeys = <String, GlobalKey>{};
  String _q = '';

  @override
  void initState() {
    super.initState();
    final s = widget.section;
    if (s != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _sectionKeys[s]?.currentContext;
        if (ctx != null && ctx.mounted) unawaited(Scrollable.ensureVisible(ctx, duration: Duration.zero));
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(FaqItem it, AppLocalizations l10n) {
    if (_q.isEmpty) return true;
    return it.q(l10n).toLowerCase().contains(_q) || it.a(l10n).toLowerCase().contains(_q);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sections = [
      for (final s in faqSections)
        (s, [for (final it in s.items) if (_matches(it, l10n)) it]),
    ].where((e) => e.$2.isNotEmpty).toList();

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('faqTitle')))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
        children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.tr('faqSearchHint'),
              prefixIcon: const Icon(AppIcons.search),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.tr('clear'),
                      icon: const Icon(AppIcons.clear),
                      onPressed: () => setState(() {
                        _search.clear();
                        _q = '';
                      }),
                    ),
              filled: true,
              border: const OutlineInputBorder(borderRadius: Radii.cardAll, borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xl),
              child: Text(l10n.tr('faqNothing'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
            ),
          for (final (s, items) in sections) ...[
            KeyedSubtree(
              key: _sectionKeys.putIfAbsent(s.id, GlobalKey.new),
              child: SettingsSectionTitle(s.title(l10n)),
            ),
            SettingsGroup(children: [
              for (final (i, it) in items.indexed)
                _FaqTile(
                  icon: i == 0 ? s.icon : null,
                  item: it,
                  // Найденное поиском — сразу раскрыто; раздел из ?section= —
                  // первый вопрос раскрыт.
                  open: _q.isNotEmpty || _open.contains('${s.id}/$i') ||
                      (widget.section == s.id && i == 0 && !_open.contains('${s.id}/$i:closed')),
                  onToggle: (v) => setState(() {
                    if (v) {
                      _open.add('${s.id}/$i');
                      _open.remove('${s.id}/$i:closed');
                    } else {
                      _open.remove('${s.id}/$i');
                      _open.add('${s.id}/$i:closed');
                    }
                  }),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final IconData? icon;
  final FaqItem item;
  final bool open;
  final ValueChanged<bool> onToggle;
  const _FaqTile({this.icon, required this.item, required this.open, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final route = item.route;
    return InkWell(
      onTap: () {
        unawaited(HapticFeedback.selectionClick());
        onToggle(!open);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: Sizes.icon,
            child: icon == null ? null : Icon(icon, color: scheme.primary),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.q(l10n), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
              AnimatedSize(
                duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 160),
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SelectableText(item.a(l10n),
                              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
                          if (route != null)
                            Padding(
                              padding: const EdgeInsets.only(top: Space.xs),
                              child: TextButton.icon(
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                icon: const Icon(AppIcons.open_in_new, size: Sizes.iconInline),
                                label: Text(l10n.tr('faqOpenSetting')),
                                onPressed: () => context.push(route),
                              ),
                            ),
                        ]),
                      ),
              ),
            ]),
          ),
          Icon(open ? AppIcons.expand_less : AppIcons.expand_more, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// Значок «Вопросы и ответы» в шапке экрана настроек (1.7.1): открывает
/// FAQ сразу на разделе [section].
class FaqButton extends StatelessWidget {
  final String section;
  const FaqButton({super.key, required this.section});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: AppLocalizations.of(context).tr('faqTitle'),
        icon: const Icon(AppIcons.help),
        onPressed: () => context.push('/settings/faq?section=$section'),
      );
}
