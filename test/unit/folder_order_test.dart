// Порядок папок в меню и скрытие несинхронизируемых (1.6.10).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/features/mail/folder_order.dart';

FolderModel _f(String id, {String? parent, bool synced = true}) => FolderModel(
      id: id,
      accountId: 'a',
      parentId: parent,
      displayName: id,
      type: FolderType.custom,
      isSynced: synced,
    );

void main() {
  test('свой порядок; новые папки — после расставленных', () {
    final defaults = [_f('A'), _f('B'), _f('C'), _f('D')];
    final r = applyFolderOrder(defaults, ['C', 'A', 'gone']);
    expect(r.map((f) => f.id), ['C', 'A', 'B', 'D']);
    expect(identical(applyFolderOrder(defaults, null), defaults), isTrue);
  });

  test('несинхронизируемые скрыты, если нет включённых подпапок', () {
    final all = [
      _f('Inbox'),
      _f('Arch', synced: false),
      _f('Arch2025', parent: 'Arch', synced: false),
      _f('Proj', synced: false),
      _f('ProjActive', parent: 'Proj'),
    ];
    expect(withoutUnsynced(all).map((f) => f.id), ['Inbox', 'Proj', 'ProjActive']);
  });
}
