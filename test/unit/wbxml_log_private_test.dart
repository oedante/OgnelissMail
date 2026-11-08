// Подробный журнал EAS без содержимого писем (план 08.11.2026 п. 2):
// текст, тема, адреса — только длиной; структура и коды — как были.

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart';

void main() {
  test('тема, тело и адреса скрыты; статус, ключи и папки видны', () {
    final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
    root.addChild('Status', namespace: 'AirSync', text: '1');
    final app = root.addChild('ApplicationData', namespace: 'AirSync');
    app.addChild('Subject', namespace: 'Email', text: 'Зарплата за октябрь');
    app.addChild('From', namespace: 'Email', text: 'boss@example.com');
    app.addChild('Data', namespace: 'AirSyncBase', text: 'Секретный текст письма');
    app.addChild('DisplayName', namespace: 'FolderHierarchy', text: 'Входящие');
    final out = wbxmlTree(root);
    expect(out, contains('<Status> "1"'));
    expect(out, contains('<DisplayName> "Входящие"'));
    expect(out, isNot(contains('Зарплата')));
    expect(out, isNot(contains('boss@example.com')));
    expect(out, isNot(contains('Секретный')));
    expect(out, contains('<Subject> «…19 знаков»'));
  });
}
