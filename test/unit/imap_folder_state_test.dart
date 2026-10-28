import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  test('состояние папки IMAP сохраняется и читается', () {
    const st = ImapFolderState(uidValidity: 1700000000, minUid: 120, maxUid: 4567);
    final back = ImapFolderState.fromJson('{"v":1700000000,"min":120,"max":4567}');
    expect(back, isNotNull);
    expect(back!.uidValidity, st.uidValidity);
    expect(back.minUid, st.minUid);
    expect(back.maxUid, st.maxUid);
    expect(st.toJson(), {'v': 1700000000, 'min': 120, 'max': 4567});
  });

  test('повреждённое или пустое состояние — первая загрузка', () {
    expect(ImapFolderState.fromJson(null), isNull);
    expect(ImapFolderState.fromJson(''), isNull);
    expect(ImapFolderState.fromJson('{"v":"x"}'), isNull);
  });
}
