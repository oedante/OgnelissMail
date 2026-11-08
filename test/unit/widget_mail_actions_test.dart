// Действия из виджета «Почта» (08.11.2026): очередь из виджета — только
// записи с действием, письмом и ящиком; мусор пропускается.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/widget_mail_actions.dart';

void main() {
  test('очередь виджета: разбор и мусор', () {
    expect(WidgetMailActions.parseQueue(null), isEmpty);
    expect(WidgetMailActions.parseQueue('not json'), isEmpty);
    expect(WidgetMailActions.parseQueue('{"op":"read"}'), isEmpty);
    final q = WidgetMailActions.parseQueue(
        '[{"op":"read","id":"m1","acc":"a1","at":1},{"op":"archive","id":"m2"},{"op":"archive","id":"m3","acc":"a1"},5]');
    expect([for (final m in q) '${m['op']}:${m['id']}'], ['read:m1', 'archive:m3']);
  });
}
