// Превью без пометок картинок (2.2.1, снимок владельца 10.11.2026: «почему-то
// всегда тэг [image: Google]»): Gmail и Outlook пишут картинки в текстовой
// части письма пометками — в ленте и уведомлении их нет.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/text_safe.dart';
import 'package:ogneliss/services/notifications/notification_text.dart';

void main() {
  test('Gmail «[image: Google]», Outlook «[cid:…]» и «[image001.png]» — убраны', () {
    expect(previewOf('[image: Google]\nВход в аккаунт на устройстве Android'),
        'Вход в аккаунт на устройстве Android');
    expect(previewKeepingLines('[image: Google]\nВход в аккаунт'), 'Вход в аккаунт');
    expect(previewOf('Добрый день! [cid:image001.png@01DA3F2B.5C6E7A80] Отчёт во вложении'),
        'Добрый день! Отчёт во вложении');
    expect(previewOf('[image001.png]\nСчёт за ноябрь'), 'Счёт за ноябрь');
    expect(NotificationText.preview('[image: Google] У приложения "Ogneliss Mail" есть доступ'),
        'У приложения "Ogneliss Mail" есть доступ');
  });

  test('обычные квадратные скобки — на месте', () {
    expect(previewOf('[Важно] Встреча в 10:00'), '[Важно] Встреча в 10:00');
    expect(previewOf('Задача [JIRA-123] закрыта'), 'Задача [JIRA-123] закрыта');
    expect(previewOf('см. [1] и [image]'), 'см. [1] и [image]');
  });
}
