// lib/services/mail/ews/ews_server_tools.dart
// Exchange (EWS): серверные правила и «Восстановить удалённые» (план П3,
// пункты 12–13, сделано 10.10.2026).
//
// Серверные правила. Правила, заведённые в Outlook или OWA, выполняет сам
// Exchange — и при выключенном телефоне. Здесь их можно посмотреть и
// включить/выключить. EWS не умеет менять одно поле правила: SetRule
// заменяет правило целиком. Поэтому правило берётся как пришло из
// GetInboxRules (все условия и действия), меняется только IsEnabled, и
// отправляется обратно. RemoveOutlookRuleBlob = false: если в ящике есть
// правила, которые выполняет только Outlook на компьютере, Exchange откажет
// (ErrorOutlookRuleBlobExists), и приложение так и скажет, — а не сотрёт
// эти правила молча (с true сервер удаляет их).
//
// Восстановить удалённые. Exchange хранит удалённое из «Удалённых» ещё
// ~14 дней (папка Recoverable Items → Deletions). Список — FindItem в
// recoverableitemsdeletions, восстановление — MoveItem во «Входящие»
// (исходную папку EWS не сообщает).
//
// Нужен доступ к EWS (основной транспорт или «спутник» ActiveSync —
// AccountModel.hasEwsExtras). У шлюзов, закрывающих EWS, — понятная ошибка.
//
// 1.7.3: новые правила (одно условие, одно действие и «остановить
// обработку» — как у фильтров Sieve, редактор общий) и удаление правила.
// RemoveOutlookRuleBlob = false и здесь: правила Outlook на компьютере не
// стираются, а при их наличии Exchange откажет — и приложение так и скажет.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/folder_model.dart';
import '../sieve/sieve_rules.dart';
import 'ews_service.dart';

final ewsServerToolsProvider = Provider<EwsServerTools>((ref) => EwsServerTools(ref.watch(ewsServiceProvider)));

/// Правила сервера и «Восстановить удалённые» (1.8.10): по EWS
/// ([EwsServerTools]) или через Microsoft Graph у Exchange Online
/// (graph_server_tools.dart) — экран не знает, через что.
abstract class ServerTools {
  Future<ServerRulesResult> getRules(AccountModel account);
  Future<String?> setEnabled(AccountModel account, ServerRule rule, bool enabled);
  Future<String?> createRule(AccountModel account, SieveRule rule, {required int priority});
  Future<String?> deleteRule(AccountModel account, ServerRule rule);
  Future<List<({String id, String label})>> ruleFolders(AccountModel account);
  Future<List<RecoverableItem>> getRecoverable(AccountModel account, {int max = 100});
  Future<int> restore(AccountModel account, List<RecoverableItem> items);
}

/// Серверное правило Exchange (как пришло с сервера).
class ServerRule {
  final String id;
  final String name;
  final bool enabled;
  final int priority;

  /// Правило не поддерживается EWS (создано Outlook с условиями, которых
  /// EWS не знает) или в ошибке — менять его отсюда нельзя.
  final bool readOnly;
  final bool inError;

  /// Что делает правило — коды действий для подписи (move, copy, delete,
  /// forward, redirect, read, flag, category, importance, stop, reply).
  final List<String> actions;

  /// Как пришло с сервера: элемент Rule у EWS (для SetRule — правило
  /// заменяется целиком), объект правила у Graph.
  final Object? raw;

  const ServerRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.priority,
    required this.readOnly,
    required this.inError,
    required this.actions,
    required this.raw,
  });
}

class ServerRulesResult {
  final List<ServerRule> rules;

  /// В ящике есть правила, которые выполняет только Outlook на компьютере.
  final bool outlookBlob;
  final String? error;
  const ServerRulesResult(this.rules, {this.outlookBlob = false, this.error});
}

/// Письмо в «Восстановить удалённые».
class RecoverableItem {
  final String id;
  final String changeKey;
  final String subject;
  final String from;
  final DateTime? received;
  final String itemClass;
  const RecoverableItem({
    required this.id,
    required this.changeKey,
    required this.subject,
    required this.from,
    required this.received,
    required this.itemClass,
  });
  bool get isMail => itemClass.isEmpty || itemClass.startsWith('IPM.Note');
}

class EwsServerTools implements ServerTools {
  final EwsService _ews;
  EwsServerTools(this._ews);

  static const _actionMap = {
    'MoveToFolder': 'move',
    'CopyToFolder': 'copy',
    'Delete': 'delete',
    'PermanentDelete': 'delete',
    'ForwardToRecipients': 'forward',
    'ForwardAsAttachmentToRecipients': 'forward',
    'RedirectToRecipients': 'redirect',
    'MarkAsRead': 'read',
    'FlagMessage': 'flag',
    'AssignCategories': 'category',
    'MarkImportance': 'importance',
    'StopProcessingRules': 'stop',
    'ServerReplyWithMessage': 'reply',
    'SendSMSAlertToRecipients': 'sms',
  };

  // ── Правила ──

  @override
  Future<ServerRulesResult> getRules(AccountModel account) async {
    try {
      final doc = await _ews.rawSoapRequest(account, '<m:GetInboxRules/>');
      final blob = doc.findAllElements('OutlookRuleBlobExists', namespace: '*').firstOrNull?.innerText.trim() == 'true';
      final out = <ServerRule>[];
      for (final r in doc.findAllElements('Rule', namespace: '*')) {
        String? f(String n) => r.findElements(n, namespace: '*').firstOrNull?.innerText.trim();
        final id = f('RuleId');
        if (id == null || id.isEmpty) continue;
        final actions = <String>{};
        final actionsEl = r.findElements('Actions', namespace: '*').firstOrNull;
        if (actionsEl != null) {
          for (final a in actionsEl.childElements) {
            final code = _actionMap[a.name.local];
            if (code != null) actions.add(code);
          }
        }
        out.add(ServerRule(
          id: id,
          name: f('DisplayName') ?? '',
          enabled: (f('IsEnabled') ?? 'true') == 'true',
          priority: int.tryParse(f('Priority') ?? '') ?? 1,
          readOnly: f('IsNotSupported') == 'true',
          inError: f('IsInError') == 'true',
          actions: actions.toList(),
          raw: r.copy(),
        ));
      }
      out.sort((a, b) => a.priority.compareTo(b.priority));
      return ServerRulesResult(out, outlookBlob: blob);
    } catch (e) {
      AppLogger.warning('EWS GetInboxRules: $e');
      return ServerRulesResult(const [], error: '$e');
    }
  }

  /// Включить/выключить правило. null — успех; иначе код ошибки:
  /// 'outlookBlob' (есть правила Outlook на компьютере), 'readOnly' или текст.
  @override
  Future<String?> setEnabled(AccountModel account, ServerRule rule, bool enabled) async {
    final raw = rule.raw;
    if (rule.readOnly || raw is! XmlElement) return 'readOnly';
    try {
      final body = '<m:UpdateInboxRules>'
          '<m:RemoveOutlookRuleBlob>false</m:RemoveOutlookRuleBlob>'
          '<m:Operations><t:SetRuleOperation>${ruleXmlForSet(raw, enabled)}</t:SetRuleOperation></m:Operations>'
          '</m:UpdateInboxRules>';
      final doc = await _ews.rawSoapRequest(account, body);
      final code = doc.findAllElements('ResponseCode', namespace: '*').firstOrNull?.innerText.trim();
      if (code != null && code != 'NoError') {
        return code.contains('OutlookRuleBlob') ? 'outlookBlob' : code;
      }
      return null;
    } catch (e) {
      final t = '$e';
      if (t.contains('OutlookRuleBlob')) return 'outlookBlob';
      AppLogger.warning('EWS SetRule: $e');
      return t;
    }
  }

  /// Правило для SetRuleOperation: то же, что пришло с сервера, с новым
  /// IsEnabled; служебные поля только для чтения (IsNotSupported, IsInError)
  /// убраны. Все элементы — с префиксом t: (пространство имён types в
  /// конверте), какой бы префикс ни прислал сервер.
  static String ruleXmlForSet(XmlElement rule, bool enabled) {
    final b = StringBuffer();
    void write(XmlElement e) {
      final name = e.name.local;
      if (name == 'IsNotSupported' || name == 'IsInError') return;
      b.write('<t:$name');
      for (final a in e.attributes) {
        if (a.name.prefix == 'xmlns' || a.name.local == 'xmlns') continue;
        b.write(' ${a.name.local}="${_esc(a.value)}"');
      }
      b.write('>');
      if (name == 'IsEnabled') {
        b.write(enabled ? 'true' : 'false');
      } else {
        for (final c in e.children) {
          if (c is XmlElement) {
            write(c);
          } else if (c is XmlText || c is XmlCDATA) {
            final v = c.value ?? '';
            // Отступы между элементами не переносим.
            if (v.trim().isNotEmpty) b.write(_esc(v));
          }
        }
      }
      b.write('</t:$name>');
    }

    write(rule);
    // У правила без IsEnabled (сервер не прислал) — добавить после Priority.
    var s = b.toString();
    if (!s.contains('<t:IsEnabled>')) {
      s = s.replaceFirst('</t:Priority>', '</t:Priority><t:IsEnabled>$enabled</t:IsEnabled>');
    }
    return s;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ── Новое правило и удаление (1.7.3) ──

  /// Условие правила → элемент Conditions (EWS RulePredicatesType).
  /// У темы и «где угодно» EWS умеет только «содержит».
  static String conditionsXml(SieveRule r) {
    final v = _esc(r.value.trim());
    final exact = r.op == SieveOp.isExactly;
    String strings(String tag) => '<t:$tag><t:String>$v</t:String></t:$tag>';
    String addresses(String tag) => '<t:$tag><t:Address><t:EmailAddress>$v</t:EmailAddress></t:Address></t:$tag>';
    return switch (r.field) {
      SieveField.from => exact ? addresses('FromAddresses') : strings('ContainsSenderStrings'),
      SieveField.to => exact ? addresses('SentToAddresses') : strings('ContainsRecipientStrings'),
      SieveField.subject => strings('ContainsSubjectStrings'),
      SieveField.any => strings('ContainsSubjectOrBodyStrings'),
    };
  }

  /// Действие → элементы Actions в порядке RuleActionsType (Delete,
  /// ForwardToRecipients, MarkAsRead, MoveToFolder, StopProcessingRules).
  /// «Отметить флажком» в правилах EWS нет. [r.arg] — FolderId папки
  /// (или имя стандартной папки) / адрес пересылки.
  static String actionsXml(SieveRule r) {
    final b = StringBuffer();
    switch (r.action) {
      case SieveAction.delete:
        b.write('<t:Delete>true</t:Delete>');
      case SieveAction.forward:
        b.write('<t:ForwardToRecipients><t:Address><t:EmailAddress>${_esc(r.arg.trim())}</t:EmailAddress>'
            '</t:Address></t:ForwardToRecipients>');
      case SieveAction.markRead:
        b.write('<t:MarkAsRead>true</t:MarkAsRead>');
      case SieveAction.move:
        b.write('<t:MoveToFolder>${_folderXml(r.arg.trim())}</t:MoveToFolder>');
      case SieveAction.flag:
        break;
    }
    if (r.stop || r.action == SieveAction.delete) b.write('<t:StopProcessingRules>true</t:StopProcessingRules>');
    return b.toString();
  }

  static const _distinguished = {'inbox', 'deleteditems', 'junkemail', 'drafts', 'sentitems', 'archive', 'outbox'};

  static String _folderXml(String id) => _distinguished.contains(id)
      ? '<t:DistinguishedFolderId Id="$id"/>'
      : '<t:FolderId Id="${_esc(id)}"/>';

  /// Тело запроса UpdateInboxRules с новым правилом [r] (последним по
  /// порядку — [priority]).
  static String createRuleBody(SieveRule r, int priority) {
    final name = r.name.trim().isNotEmpty ? r.name.trim() : r.value.trim();
    return '<m:UpdateInboxRules>'
        '<m:RemoveOutlookRuleBlob>false</m:RemoveOutlookRuleBlob>'
        '<m:Operations><t:CreateRuleOperation><t:Rule>'
        '<t:DisplayName>${_esc(name)}</t:DisplayName>'
        '<t:Priority>${priority < 1 ? 1 : priority}</t:Priority>'
        '<t:IsEnabled>${r.enabled}</t:IsEnabled>'
        '<t:Conditions>${conditionsXml(r)}</t:Conditions>'
        '<t:Actions>${actionsXml(r)}</t:Actions>'
        '</t:Rule></t:CreateRuleOperation></m:Operations>'
        '</m:UpdateInboxRules>';
  }

  /// Создать правило. null — успех; иначе 'outlookBlob' или текст ошибки.
  @override
  Future<String?> createRule(AccountModel account, SieveRule rule, {required int priority}) =>
      _update(account, createRuleBody(rule, priority), 'CreateRule');

  /// Удалить правило. null — успех.
  @override
  Future<String?> deleteRule(AccountModel account, ServerRule rule) => _update(
      account,
      '<m:UpdateInboxRules>'
          '<m:RemoveOutlookRuleBlob>false</m:RemoveOutlookRuleBlob>'
          '<m:Operations><t:DeleteRuleOperation><t:RuleId>${_esc(rule.id)}</t:RuleId></t:DeleteRuleOperation></m:Operations>'
          '</m:UpdateInboxRules>',
      'DeleteRule');

  Future<String?> _update(AccountModel account, String body, String what) async {
    try {
      final doc = await _ews.rawSoapRequest(account, body);
      final code = doc.findAllElements('ResponseCode', namespace: '*').firstOrNull?.innerText.trim();
      if (code != null && code != 'NoError') {
        final text = doc.findAllElements('MessageText', namespace: '*').firstOrNull?.innerText.trim() ?? '';
        AppLogger.warning('EWS $what: $code ${text.isEmpty ? '' : '— $text'}');
        return code.contains('OutlookRuleBlob') ? 'outlookBlob' : (text.isEmpty ? code : '$code: $text');
      }
      AppLogger.info('EWS $what: готово');
      return null;
    } catch (e) {
      final t = '$e';
      if (t.contains('OutlookRuleBlob')) return 'outlookBlob';
      AppLogger.warning('EWS $what: $e');
      return t;
    }
  }

  /// Папки ящика для «Переложить в папку» (FolderId EWS — у ящика ActiveSync
  /// id из ActiveSync не подходят): подпись — путь «Папка/Подпапка».
  @override
  Future<List<({String id, String label})>> ruleFolders(AccountModel account) async {
    final folders = await _ews.getFolders(account);
    final byId = {for (final f in folders) f.id: f};
    String path(FolderModel f) {
      final parts = <String>[f.displayName];
      var p = f.parentId;
      var guard = 0;
      while (p != null && byId[p] != null && guard++ < 20) {
        parts.insert(0, byId[p]!.displayName);
        p = byId[p]!.parentId;
      }
      return parts.join('/');
    }
    final out = [
      for (final f in folders)
        if (f.type != FolderType.outbox && f.type != FolderType.drafts) (id: f.id, label: path(f)),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  // ── Восстановить удалённые ──

  @override
  Future<List<RecoverableItem>> getRecoverable(AccountModel account, {int max = 100}) async {
    final body = '<m:FindItem Traversal="Shallow">'
        '<m:ItemShape><t:BaseShape>IdOnly</t:BaseShape><t:AdditionalProperties>'
        '<t:FieldURI FieldURI="item:Subject"/>'
        '<t:FieldURI FieldURI="item:DateTimeReceived"/>'
        '<t:FieldURI FieldURI="item:ItemClass"/>'
        '<t:FieldURI FieldURI="message:From"/>'
        '</t:AdditionalProperties></m:ItemShape>'
        '<m:IndexedPageItemView MaxEntriesReturned="$max" Offset="0" BasePoint="Beginning"/>'
        '<m:SortOrder><t:FieldOrder Order="Descending"><t:FieldURI FieldURI="item:DateTimeReceived"/></t:FieldOrder></m:SortOrder>'
        '<m:ParentFolderIds><t:DistinguishedFolderId Id="recoverableitemsdeletions"/></m:ParentFolderIds>'
        '</m:FindItem>';
    final doc = await _ews.rawSoapRequest(account, body);
    return parseRecoverable(doc);
  }

  static List<RecoverableItem> parseRecoverable(XmlDocument doc) {
    final out = <RecoverableItem>[];
    final items = doc.findAllElements('Items', namespace: '*').firstOrNull;
    if (items == null) return out;
    for (final it in items.childElements) {
      final idEl = it.findElements('ItemId', namespace: '*').firstOrNull;
      final id = idEl?.getAttribute('Id');
      if (id == null || id.isEmpty) continue;
      String f(String n) => it.findElements(n, namespace: '*').firstOrNull?.innerText.trim() ?? '';
      final mailbox = it.findAllElements('Mailbox', namespace: '*').firstOrNull;
      final name = mailbox?.findElements('Name', namespace: '*').firstOrNull?.innerText.trim() ?? '';
      final addr = mailbox?.findElements('EmailAddress', namespace: '*').firstOrNull?.innerText.trim() ?? '';
      out.add(RecoverableItem(
        id: id,
        changeKey: idEl?.getAttribute('ChangeKey') ?? '',
        subject: f('Subject'),
        from: name.isNotEmpty ? name : addr,
        received: DateTime.tryParse(f('DateTimeReceived'))?.toLocal(),
        itemClass: f('ItemClass'),
      ));
    }
    return out;
  }

  /// Вернуть письма во «Входящие». Возвращает, сколько восстановлено.
  @override
  Future<int> restore(AccountModel account, List<RecoverableItem> items) async {
    if (items.isEmpty) return 0;
    final ids = items.map((i) => '<t:ItemId Id="${_esc(i.id)}"/>').join();
    final body = '<m:MoveItem><m:ToFolderId><t:DistinguishedFolderId Id="inbox"/></m:ToFolderId>'
        '<m:ItemIds>$ids</m:ItemIds></m:MoveItem>';
    final doc = await _ews.rawSoapRequest(account, body);
    return doc
        .findAllElements('MoveItemResponseMessage', namespace: '*')
        .where((m) => m.getAttribute('ResponseClass') == 'Success')
        .length;
  }
}
