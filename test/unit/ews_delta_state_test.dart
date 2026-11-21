// EWS SyncFolderItems: состояние папки при ошибке (2.6.8, план 2026-11,
// «сохранение состояния EWS при единичной ошибке»). Раньше любая ошибка
// ответа (сервер занят, тайм-аут) стирала состояние — следующая
// синхронизация перечитывала папку с нуля.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_delta_sync.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_parser.dart';
import 'package:xml/xml.dart';

// Как в ews_service: префиксы m:, t:, s: снимает EwsXmlParser.parseResponse.
XmlDocument _error(String code, String text) => EwsXmlParser.parseResponse('''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
  <s:Body>
    <m:SyncFolderItemsResponse>
      <m:ResponseMessages>
        <m:SyncFolderItemsResponseMessage ResponseClass="Error">
          <m:MessageText>$text</m:MessageText>
          <m:ResponseCode>$code</m:ResponseCode>
          <m:DescriptiveLinkKey>0</m:DescriptiveLinkKey>
        </m:SyncFolderItemsResponseMessage>
      </m:ResponseMessages>
    </m:SyncFolderItemsResponse>
  </s:Body>
</s:Envelope>''');

void main() {
  test('код ошибки ответа читается', () {
    final r = EwsDeltaSync.parseResponse(_error('ErrorServerBusy', 'The server cannot service this request right now.'), 'a', 'inbox');
    expect(r.error, isNotNull);
    expect(r.responseCode, 'ErrorServerBusy');
  });

  test('временная ошибка — состояние сохраняется, третья подряд — сброс', () {
    expect(EwsDeltaSyncResult.keepStateAfterError('ErrorServerBusy', 1), isTrue);
    expect(EwsDeltaSyncResult.keepStateAfterError('ErrorTimeoutExpired', 2), isTrue);
    expect(EwsDeltaSyncResult.keepStateAfterError(null, 1), isTrue);
    expect(EwsDeltaSyncResult.keepStateAfterError('ErrorServerBusy', 3), isFalse);
  });

  test('негодное состояние или нет папки — сброс сразу', () {
    expect(EwsDeltaSyncResult.keepStateAfterError('ErrorInvalidSyncStateData', 1), isFalse);
    expect(EwsDeltaSyncResult.keepStateAfterError('ErrorSyncFolderNotFound', 1), isFalse);
    expect(EwsDeltaSyncResult.keepStateAfterError('ErrorFolderNotFound', 1), isFalse);
  });
}
