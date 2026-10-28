// test/unit/ews_distinguished_folders_test.dart
// EWS: типы стандартных папок — по id от сервера (GetFolder с
// DistinguishedFolderId), на любом языке ящика (1.7.2+107).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/mail/ews/ews_directory_extras.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_parser.dart';
import 'package:xml/xml.dart';

FolderModel _f(String id, String name, {FolderType type = FolderType.custom, String? parent}) => FolderModel(
    id: id, accountId: 'a', parentId: parent, displayName: name, type: type, showInUnified: true, sortOrder: 10);

FolderModel _by(List<FolderModel> list, String id) => list.firstWhere((f) => f.id == id);

void main() {
  test('запрос: все стандартные папки одним GetFolder, общий ящик — с адресом', () {
    final own = EwsDirectoryExtras.buildGetDistinguishedFolders(['inbox', 'sentitems']);
    expect(own, contains('<t:DistinguishedFolderId Id="inbox"></t:DistinguishedFolderId>'));
    expect(own, contains('<t:DistinguishedFolderId Id="sentitems"></t:DistinguishedFolderId>'));
    final shared = EwsDirectoryExtras.buildGetDistinguishedFolders(['inbox'], mailbox: 'team@example.com');
    expect(shared, contains('<t:Mailbox><t:EmailAddress>team@example.com</t:EmailAddress></t:Mailbox>'));
  });

  test('ответ: id по порядку запроса, ошибка одной папки — null', () {
    final doc = XmlDocument.parse('''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
<m:GetFolderResponse xmlns:m="m" xmlns:t="t"><m:ResponseMessages>
  <m:GetFolderResponseMessage ResponseClass="Success"><m:ResponseCode>NoError</m:ResponseCode>
    <m:Folders><t:Folder><t:FolderId Id="IN" ChangeKey="1"/></t:Folder></m:Folders></m:GetFolderResponseMessage>
  <m:GetFolderResponseMessage ResponseClass="Error"><m:ResponseCode>ErrorFolderNotFound</m:ResponseCode></m:GetFolderResponseMessage>
  <m:GetFolderResponseMessage ResponseClass="Success"><m:ResponseCode>NoError</m:ResponseCode>
    <m:Folders><t:Folder><t:FolderId Id="JUNK" ChangeKey="2"/></t:Folder></m:Folders></m:GetFolderResponseMessage>
</m:ResponseMessages></m:GetFolderResponse></s:Body></s:Envelope>''');
    expect(EwsDirectoryExtras.parseFolderIds(doc), ['IN', null, 'JUNK']);
  });

  test('ящик на немецком: стандартные папки получают типы, подпапка «Inbox» — обычная', () {
    final folders = [
      _f('IN', 'Posteingang'),
      _f('SENT', 'Gesendete Elemente'),
      _f('DEL', 'Gelöschte Elemente'),
      _f('JUNK', 'Junk-E-Mail'),
      _f('P', 'Projekte'),
      _f('SUB', 'Inbox', type: FolderType.inbox, parent: 'P'), // по названию — «Входящие»
    ];
    final out = EwsXmlParser.applyDistinguished(folders, {
      'IN': FolderType.inbox,
      'SENT': FolderType.sent,
      'DEL': FolderType.trash,
      'JUNK': FolderType.junk,
    });
    expect(_by(out, 'IN').type, FolderType.inbox);
    expect(_by(out, 'IN').sortOrder, 0);
    expect(_by(out, 'SENT').type, FolderType.sent);
    expect(_by(out, 'DEL').type, FolderType.trash);
    expect(_by(out, 'DEL').showInUnified, isFalse);
    expect(_by(out, 'JUNK').type, FolderType.junk);
    expect(_by(out, 'JUNK').showInUnified, isFalse);
    expect(_by(out, 'P').type, FolderType.custom);
    expect(_by(out, 'SUB').type, FolderType.custom, reason: 'настоящие «Входящие» известны по id');
    expect([for (final f in out) f.id], [for (final f in folders) f.id], reason: 'порядок не меняется');
  });

  test('тип, которого сервер не прислал, остаётся по названию', () {
    final folders = [_f('IN', 'Входящие', type: FolderType.inbox), _f('OUT', 'Исходящие', type: FolderType.outbox)];
    final out = EwsXmlParser.applyDistinguished(folders, {'IN': FolderType.inbox});
    expect(_by(out, 'OUT').type, FolderType.outbox);
  });

  test('ни один id не совпал — список без изменений', () {
    final folders = [_f('IN', 'Входящие', type: FolderType.inbox), _f('X', 'Проекты')];
    final out = EwsXmlParser.applyDistinguished(folders, {'OTHER': FolderType.inbox});
    expect(identical(out, folders), isTrue);
    expect(_by(out, 'IN').type, FolderType.inbox);
  });
}
