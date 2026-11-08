// Редактор письма (план 08.11.2026 п. 3, микрофризы): снимок черновика —
// когда нужен, а не на каждое нажатие; картинки data: не участвуют в
// проверке «письмо не тронуто».

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/compose/screens/compose_screen.dart';
import 'package:ogneliss/services/mail/draft_autosave_service.dart';

DraftData _d(String body) => DraftData(
      id: 'd1', accountId: 'a1', to: const [], cc: const [], bcc: const [],
      subject: 'Тема', body: body, savedAt: DateTime(2026, 11, 8));

void main() {
  test('картинка data: — без данных; остальной текст как был', () {
    final big = 'A' * 200000;
    final html = '<p>Привет</p><img src="data:image/png;base64,$big" alt="x"><p>Пока</p>'
        "<img src='data:image/gif;base64,R0lG'>";
    final out = ComposeScreen.withoutDataUris(html);
    expect(out, '<p>Привет</p><img src="data:" alt="x"><p>Пока</p><img src=\'data:\'>');
    expect(ComposeScreen.withoutDataUris('<p>текст про data: без картинки</p>'),
        '<p>текст про data: без картинки</p>');
  });

  test('правки только отмечают изменение; снимок — при сохранении, один раз', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final svc = DraftAutosaveService(db);
    addTearDown(svc.stopAutosave);
    svc.startAutosave(_d(''));
    var built = 0;
    for (var i = 0; i < 50; i++) {
      svc.markChanged(() {
        built++;
        return _d('Текст $i');
      });
    }
    expect(built, 0, reason: 'на нажатия клавиш снимок не собирается');
    expect(svc.hasUnsavedChanges, isTrue);
    expect(built, 1);
  });
}
