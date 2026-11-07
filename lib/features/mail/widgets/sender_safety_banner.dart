// lib/features/mail/widgets/sender_safety_banner.dart
// Баннер антифишинга над телом письма. Считает сигналы локально
// (sender_safety_service) и показывает предупреждения + «Пожаловаться на фишинг».
//
// 1.15.1 (замечание владельца 07.11.2026: «масштаб, отписка, предупреждения —
// в пилюли над текстом, где перевод; иначе они увеличивают длину письма»):
// экран письма показывает предупреждение пилюлей в строке сведений
// ([pillLevel], [pillLabel], [colorOf], [iconOf], [summary]), а эта карточка
// — то, что раскрывается по нажатию ([report] уже посчитан экраном).

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/security/sender_safety_service.dart';
import '../../settings/providers/feature_flags_provider.dart';

class SenderSafetyBanner extends ConsumerStatefulWidget {
  final AccountModel account;
  final EmailModel email;

  /// Проверка уже сделана (пилюля экрана письма) — карточка её показывает,
  /// а не считает заново.
  final SenderSafetyReport? report;
  const SenderSafetyBanner({super.key, required this.account, required this.email, this.report});

  /// Уровень, который показывать при настройках антифишинга [flags]; null —
  /// показывать нечего.
  static SafetyLevel? pillLevel(SenderSafetyReport? report, FeatureFlags flags) {
    if (report == null || report.isEmpty) return null;
    final level = report.level;
    if (level == SafetyLevel.none || !flags.showSafetyLevel(level.index)) return null;
    return level;
  }

  /// Подпись пилюли — коротко: «Признаки фишинга», «Осторожно», «Внешний
  /// отправитель» (полный заголовок — в карточке).
  static String pillLabel(SafetyLevel level, AppLocalizations l10n) => l10n.tr(switch (level) {
        SafetyLevel.danger => 'noticeSafetyDanger',
        SafetyLevel.warning => 'noticeSafetyCaution',
        _ => 'noticeSafetyExternal',
      });

  /// Заголовок карточки и причины одной строкой — подсказка и чтение с экрана.
  static String summary(SenderSafetyReport report, AppLocalizations l10n) =>
      [_title(report.level, l10n), for (final s in report.signals) _signalText(s, l10n)].join('. ');

  static String _title(SafetyLevel level, AppLocalizations l10n) => level == SafetyLevel.danger
      ? l10n.safetyBannerDanger
      : (level == SafetyLevel.warning ? l10n.safetyBannerCaution : l10n.safetyExternalSender);

  static String _signalText(SafetySignal s, AppLocalizations l10n) {
    // Имя похоже на чужой адрес или сайт (1.5.10): прямо — какое имя и откуда
    // письмо на самом деле. Было «Отображаемое имя маскирует другой адрес:
    // 1c.base.svc» — непонятно, что с чем не сходится.
    if (s.reason == SafetyReason.displayNameSpoof && s.detail != null && s.extra != null) {
      return l10n
          .tr(s.detail!.contains('@') ? 'safetyNameLikeAddress' : 'safetyNameLikeSite')
          .replaceAll('{name}', s.detail!)
          .replaceAll('{email}', s.extra!);
    }
    // Похожий домен — с тем, на что похож (1.10.x).
    if (s.reason == SafetyReason.lookalikeDomain && s.detail != null && s.extra != null) {
      return l10n.tr('safetyLookalikeOf').replaceAll('{domain}', s.detail!).replaceAll('{like}', s.extra!);
    }
    if (s.reason == SafetyReason.contactImpersonation && s.detail != null && s.extra != null) {
      return l10n.tr('safetyContactImpersonation').replaceAll('{name}', s.detail!).replaceAll('{email}', s.extra!);
    }
    if (s.reason == SafetyReason.replyToMismatch && s.detail != null) {
      return l10n.tr('safetyReplyToElsewhere').replaceAll('{email}', s.detail!);
    }
    String base;
    switch (s.reason) {
      case SafetyReason.externalSender: base = l10n.safetyExternalSender; break;
      case SafetyReason.firstContact: base = l10n.safetyFirstContact; break;
      case SafetyReason.displayNameSpoof: base = l10n.safetyDisplayNameSpoof; break;
      case SafetyReason.lookalikeDomain: base = l10n.safetyLookalikeDomain; break;
      case SafetyReason.dangerousAttachment: base = l10n.safetyDangerousAttach; break;
      case SafetyReason.linkMismatch: base = l10n.safetyLinkMismatch; break;
      case SafetyReason.authenticationFail: base = l10n.safetyAuthFail; break;
      case SafetyReason.contactImpersonation: base = l10n.safetyDisplayNameSpoof; break;
      case SafetyReason.replyToMismatch: base = l10n.tr('safetyReplyToElsewhere').replaceAll(': {email}', ''); break;
    }
    return s.detail != null ? '$base: ${s.detail}' : base;
  }

  static Color colorOf(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.danger: return AppColors.errorRed;
      case SafetyLevel.warning: return AppColors.accentOrange;
      case SafetyLevel.info: return AppColors.infoBlue;
      case SafetyLevel.none: return AppColors.infoBlue;
    }
  }

  static IconData iconOf(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.danger: return AppIcons.gpp_bad;
      case SafetyLevel.warning: return AppIcons.warning;
      case SafetyLevel.info: return AppIcons.info;
      case SafetyLevel.none: return AppIcons.info;
    }
  }

  @override
  ConsumerState<SenderSafetyBanner> createState() => _SenderSafetyBannerState();
}

class _SenderSafetyBannerState extends ConsumerState<SenderSafetyBanner> {
  // Проверка — один раз на письмо. Раньше запускалась заново при каждой
  // перестройке экрана письма, и баннер мог пропасть и появиться снова.
  late Future<SenderSafetyReport> _report;
  String _key = '';

  // Пересчёт — только когда пришло то, от чего зависит проверка: тело
  // (ссылки), вложения, заголовки подлинности.
  String get _keyNow {
    final e = widget.email;
    return '${widget.account.id}|${e.id}|${e.from.email}|${e.bodyHtml?.length ?? e.bodyPlain?.length ?? 0}'
        '|${e.attachments.length}|${e.authResults?.length ?? 0}';
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _key = _keyNow;
    final given = widget.report;
    _report = given != null
        ? Future.value(given)
        : ref.read(senderSafetyServiceProvider).analyze(widget.account, widget.email);
  }

  @override
  void didUpdateWidget(SenderSafetyBanner old) {
    super.didUpdateWidget(old);
    if (_keyNow != _key) _start();
  }

  AccountModel get account => widget.account;
  EmailModel get email => widget.email;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flags = ref.watch(featureFlagsProvider);
    return FutureBuilder<SenderSafetyReport>(
      future: _report,
      initialData: widget.report,
      builder: (context, snap) {
        final report = snap.data;
        if (report == null || report.isEmpty) return const SizedBox.shrink();
        final level = report.level;
        if (level == SafetyLevel.none) return const SizedBox.shrink();
        // Порог показа задаётся профилем (Базовый — только danger).
        if (!flags.showSafetyLevel(level.index)) return const SizedBox.shrink();

        final color = SenderSafetyBanner.colorOf(level);
        final title = SenderSafetyBanner._title(level, l10n);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
          padding: const EdgeInsets.all(Space.m),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(SenderSafetyBanner.iconOf(level), size: 18, color: color),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...report.signals.map((s) => Padding(
                    padding: const EdgeInsets.only(top: 2, left: 26),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
                        Expanded(
                          child: Text(
                            SenderSafetyBanner._signalText(s, l10n),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )),
              if (level.index >= SafetyLevel.warning.index) ...[
                const SizedBox(height: Space.s),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push(
                        '/compose?forwardFromId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}'),
                    icon: Icon(AppIcons.report, size: 18, color: color),
                    style: TextButton.styleFrom(foregroundColor: color),
                    label: Text(l10n.safetyReportPhishing),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
