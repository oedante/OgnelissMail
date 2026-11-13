// lib/features/assignments/assignment_edit.dart
// «Изменить» и «Права постановщика» (просьба владельца 13.11.2026).
//
//  · Изменить поручение или этап: название, описание, сроки, порядок,
//    исполнитель, соисполнители, контролирующий, наблюдатели, чек-лист,
//    файлы. Участникам уходит письмо — что изменилось и полные сведения;
//    у кого Ogneliss Mail, поручение обновится само.
//  · Права постановщика другому человеку: заместитель (права у обоих —
//    начальник и заместитель) или передать полностью (смена вахты: новый
//    постановщик, я — наблюдатель). Снять права заместителя.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_safe.dart' show initialOf;
import '../../data/models/email_model.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/assignments/assignment_store.dart' show AssignmentTree;
import '../../widgets/common/app_sheet.dart';
import '../../widgets/common/hero_email_transition.dart';
import '../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../compose/widgets/people_picker_sheet.dart' show showPeoplePicker;
import '../mail/providers/mail_providers.dart' show accountsProvider;
import 'project_editor.dart' show showStageEditor;

/// «Изменить» поручение или этап [v] (постановщик или заместитель).
Future<void> editAssignment(BuildContext context, WidgetRef ref, AssignmentView v) async {
  final l10n = AppLocalizations.of(context);
  final all = ref.read(assignmentsProvider).value ?? const <AssignmentView>[];
  final account = ref.read(accountsProvider).where((a) => a.id == v.row.accountId).firstOrNull;
  // Этап проекта — среди этапов (выбор «после этапа N»), иначе — один.
  final parent = all.parentOf(v);
  final stage = parent != null && parent.isProject;
  final list = stage
      ? (all.childrenOf(parent.id)
        ..sort((a, b) {
          final o = a.row.stageOrder.compareTo(b.row.stageOrder);
          return o != 0 ? o : a.row.createdAt.compareTo(b.row.createdAt);
        }))
      : [v];
  final idx = {for (var i = 0; i < list.length; i++) list[i].id: i};
  final draft = ProjectDraft(
    start: parent?.start,
    stages: [for (final s in list) StageDraft.fromView(s, after: idx[s.row.afterId])],
  );
  final i = list.indexWhere((s) => s.id == v.id);
  final res = await showStageEditor(context, ref,
      project: draft,
      index: i < 0 ? 0 : i,
      account: account,
      heading: stage ? '${l10n.tr('projStage')} ${(i < 0 ? 0 : i) + 1}' : l10n.tr('assignEditTitle'),
      showOrder: stage);
  if (res == null) return;
  final a = res.after;
  final afterId = !stage ? v.row.afterId : (a == null || a < 0 || a >= list.length ? null : list[a].id);
  assignmentFire(ref.read(assignmentServiceProvider).editTask(v, res, afterId: afterId).then((_) {}));
}

/// «Права постановщика»: заместители, назначить заместителя, передать
/// полностью, снять права.
Future<void> showRightsSheet(BuildContext context, WidgetRef ref, AssignmentView v) async {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  String label(String email, String? name) => (name ?? '').trim().isNotEmpty ? name!.trim() : email;
  Widget avatar(String email, String? name) => HeroEmailAvatar(
        emailId: 'rights_$email',
        initial: initialOf(label(email, name)),
        color: HeroEmailAvatar.colorForEmail(email),
        radius: 16,
        hero: false,
        email: email,
      );
  final choice = await showAppSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text(l10n.tr('assignRights'), style: theme.textTheme.titleMedium),
          subtitle: Text(l10n.tr('assignRightsHint')),
        ),
        ListTile(
          leading: avatar(v.row.ownerEmail, v.owner?.displayName),
          title: Text(v.iOwn ? l10n.tr('assignMe') : label(v.row.ownerEmail, v.owner?.displayName)),
          subtitle: Text(l10n.tr('projRoleOwner')),
        ),
        for (final d in v.deputies)
          ListTile(
            leading: avatar(d.email, d.displayName),
            title: Text(label(d.email, d.displayName)),
            subtitle: Text(l10n.tr('projDeputy')),
            trailing: TextButton(
              onPressed: () => Navigator.pop(ctx, 'revoke:${d.email}'),
              child: Text(l10n.tr('assignRightsRemove')),
            ),
          ),
        const Divider(height: Space.m),
        ListTile(
          key: const ValueKey('rights_deputy'),
          leading: const Icon(AppIcons.supervisor_account),
          title: Text(l10n.tr('assignRightsDeputy')),
          subtitle: Text(l10n.tr('assignRightsDeputyDesc')),
          onTap: () => Navigator.pop(ctx, 'deputy'),
        ),
        ListTile(
          key: const ValueKey('rights_handover'),
          leading: const Icon(AppIcons.manage_accounts),
          title: Text(l10n.tr('assignRightsHandover')),
          subtitle: Text(l10n.tr('assignRightsHandoverDesc')),
          onTap: () => Navigator.pop(ctx, 'handover'),
        ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final svc = ref.read(assignmentServiceProvider);
  if (choice.startsWith('revoke:')) {
    final email = choice.substring('revoke:'.length);
    final d = v.deputies.where((p) => p.email == email).firstOrNull;
    final ok = await confirmDestructive(context,
        title: l10n.tr('assignRightsRemove'),
        message: l10n.tr('assignRightsRevoked').replaceAll('{name}', label(email, d?.displayName)));
    if (ok) assignmentFire(svc.revokeRights(v, email));
    return;
  }
  final account = ref.read(accountsProvider).where((a) => a.id == v.row.accountId).firstOrNull;
  final picked = await showPeoplePicker(context, account: account, exclude: {
    v.row.ownerEmail.toLowerCase(),
    for (final d in v.deputies) d.email.toLowerCase(),
  });
  if (picked.isEmpty || !context.mounted) return;
  final c = picked.first;
  final person = EmailAddress(email: c.email, displayName: c.displayName.trim().isEmpty ? null : c.displayName);
  final handover = choice == 'handover';
  if (handover) {
    final ok = await confirmDestructive(context,
        title: l10n.tr('assignRightsHandover'),
        message: l10n.tr('assignRightsHandoverConfirm').replaceAll('{name}', person.label));
    if (!ok) return;
  }
  assignmentFire(svc.grantRights(v, person, handover: handover));
}
