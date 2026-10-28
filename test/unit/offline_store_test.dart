// «На телефоне» (11.10.2026): ограничение размера письма по режиму загрузки
// считает текст и встроенные картинки; «только заголовки» — заранее ничего.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/services/sync/offline_store_service.dart';

void main() {
  test('ограничение размера письма по режиму', () {
    expect(OfflineStoreService.bodyLimit(EmailFetchMode.headersOnly), 0);
    expect(OfflineStoreService.bodyLimit(EmailFetchMode.noAttachments), isNull);
    expect(OfflineStoreService.bodyLimit(EmailFetchMode.full), isNull);
    expect(OfflineStoreService.bodyLimit(EmailFetchMode.partial50k), 50 * 1024);
    expect(OfflineStoreService.bodyLimit(EmailFetchMode.partial100k), 100 * 1024);
    expect(OfflineStoreService.bodyLimit(EmailFetchMode.partial500k), 500 * 1024);
  });

  test('срок картинок по умолчанию — неделя', () {
    expect(OfflineStoreService.defaultImageDays, 7);
    expect(OfflineStoreService.imageChoices, contains(OfflineStoreService.defaultImageDays));
  });
}
