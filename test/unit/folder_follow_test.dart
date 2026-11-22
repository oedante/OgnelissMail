// Смена ящика, когда открыта папка (2.6.8, замечание владельца 22.11.2026:
// в «Отправленных» ящика «Работа» сменил ящик на Google — заголовок
// «Входящие», писем нет).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/features/mail/providers/folder_follow.dart';

FolderModel _f(String acc, String id, String name, FolderType type, {String? parent}) =>
    FolderModel(id: id, accountId: acc, displayName: name, type: type, parentId: parent);

void main() {
  final work = [
    _f('w', 'AAMkInbox', 'Входящие', FolderType.inbox),
    _f('w', 'AAMkSent', 'Отправленные', FolderType.sent),
    _f('w', 'AAMkProj', 'Проекты', FolderType.custom),
    _f('w', 'AAMkOld', 'Старое', FolderType.custom),
  ];
  final google = [
    _f('g', 'INBOX', 'INBOX', FolderType.inbox),
    _f('g', '[Gmail]/Sent Mail', 'Sent Mail', FolderType.sent),
    _f('g', 'Проекты', 'Проекты', FolderType.custom),
    _f('g', 'INBOX/Отправленные', 'Отправленные', FolderType.sent, parent: 'INBOX'),
  ];
  FolderModel w(String id) => work.firstWhere((f) => f.id == id);

  test('системная папка — того же вида, верхнего уровня', () {
    expect(followFolder(selectedId: 'AAMkSent', old: w('AAMkSent'), target: google, homeInbox: false),
        const FollowFolder('[Gmail]/Sent Mail'));
  });

  test('своя папка — по названию', () {
    expect(followFolder(selectedId: 'AAMkProj', old: w('AAMkProj'), target: google, homeInbox: false),
        const FollowFolder('Проекты'));
  });

  test('нет такой — «Вся почта» или «Входящие» по настройке', () {
    expect(followFolder(selectedId: 'AAMkOld', old: w('AAMkOld'), target: google, homeInbox: false),
        const FollowAllMail());
    expect(followFolder(selectedId: 'AAMkOld', old: w('AAMkOld'), target: google, homeInbox: true),
        const FollowFolder('INBOX'));
  });

  test('тот же id есть в новом ящике (IMAP «INBOX») — остаёмся', () {
    final yandex = [_f('y', 'INBOX', 'Входящие', FolderType.inbox)];
    expect(
        followFolder(selectedId: 'INBOX', old: _f('g', 'INBOX', 'INBOX', FolderType.inbox), target: yandex, homeInbox: false),
        const FollowStay());
  });
}
