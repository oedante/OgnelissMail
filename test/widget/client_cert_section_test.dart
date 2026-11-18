// «Безопасность → Сертификаты клиента» (2.6.5): список, сертификат
// организации — без кнопок изменения и удаления.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/client_cert_store.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/features/settings/widgets/client_certificates_section.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/security/managed_config.dart';

const _rsa = '''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
hgQIGphuZEy75ogCAggA''';
const _ec = '''MIIEfAIBAzCCBDIGCSqGSIb3DQEHAaCCBCMEggQfMIIEGzCCAtIGCSqGSIb3DQEHBqCCAsMwggK/AgEAMIICuAYJKoZIhvcNAQcB
MFcGCSqGSIb3DQEFDTBKMCkGCSqGSIb3DQEFDDAcBAjRa69KwGxM9AICCAAwDAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEEH6D
w46TwYI+1e+rq1fnW5GAggJQEi0CZXDZirXyW+Wr5h2gKh7tczK+EefLR968HPZF7Xn52myHX0+inPVjIgFj/ezh1fYWwT0wwVeZ
r1OZsAclzxW4a9S1U5EQMJ13ywxGI5hn5GPsEi115IdnPF/pgN9oM/YCqLnM5crFRwyTdusIMP24U4H7I+6RGrxe5gVSlxYBB/z7
S+ucsGYh6492xxcwVcwCuzXuTogooeEtio76yDFxs6E3buUAuOccgf6DXg7sV/+7qCFEJowuapU5sL1qxdtoqsnfErWppWa6gZyw
wU9L3w5ubncfWoQJNgq/tHvPCSGWDS9abTuJRD6iK4Yl5AYiG38WBBCcn4oiMmfoIF8xjeSYrl7S6QqFxfcFD96Ut8V40jjRkvXW
U0eDbjX5a/hM2MqAsQ5qQkaJfsCRnYEaNS2O209svnI35JpWM+7XWr/WU2MbTKU03CB6G503yqtdhyza8D5LTgLrJaf7Xn9h3izK
ZJAq7oOUOn82U6aPLRL66th7DTC+8jczgqm+lfJdgJyLD0FmqQ1yBNCMJAKE4HfixZcgfdm+RA9f1HCGEc1OEGP2b7ueM50NHrDR
2ttLiAZKRzyMmSFe6GZHy9gDsJ2ske02uSQLPa6keCj2erEAObs6RuT5lNYXw2+s3hKXckBJG49HcLWcYfiLaUh09EiTb6mVIL21
LOIvzGuaZws0jSP1/82S+0bEZRBlRiJHlsY6hsblXcX2xLBVh/akB3yAWvWJ6HqtngiDtn93WB6C9sRePhDKG8K9C54l0X1dgpva
FInUU7oLWZ5mKzCCAUEGCSqGSIb3DQEHAaCCATIEggEuMIIBKjCCASYGCyqGSIb3DQEMCgECoIHvMIHsMFcGCSqGSIb3DQEFDTBK
MCkGCSqGSIb3DQEFDDAcBAgev+xaDbUNMAICCAAwDAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEEAOItDQJ6eCP5RHlrnaCCr0E
gZDxRwIFFlG1TpzBV+vatGuuwBxXlwyrBX2Q+L5OloabHDyVsUDGZJylxzdh/6yWEAyuCQQksHOwHAixglNL2kxZq53bcYzk+JL8
dmCTB2T2AjAtgc3GKEIFwLvGoiuVIgRMZ+D/oLTOByrTQ2xLI5T2idHM+edmjvehkIEd9qeIyp9gF4kNiDyyPCKPbANVZsYxJTAj
BgkqhkiG9w0BCRUxFgQUmoI6g1gkOqK17K43bo4Tsc6+zIgwQTAxMA0GCWCGSAFlAwQCAQUABCBvETu/VqOQsih1Jvz7d4rVtLrz
iibf454gY+TTW1v10wQIqrT/kN+pC+cCAggA''';

class _MemStorage extends SecureStorageService {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

void main() {
  tearDown(ClientCertStore.debugReset);

  testWidgets('свой сертификат — изменить и удалить; организации — только просмотр', (tester) async {
    final store = (await tester.runAsync(() async {
      final s = await ClientCertStore.init(_MemStorage(), policy: ManagedPolicy.none);
      await s.applyPolicy(ManagedPolicy.fromMap(const {
        'client_cert_pkcs12': _rsa,
        'client_cert_password': 'secret',
        'client_cert_domains': 'corp.test',
      }));
      await s.importBytes(base64.decode(_ec.replaceAll(RegExp(r'\s+'), '')), 'secret', ['lab.example']);
      return s;
    }))!;
    expect(store.items, hasLength(2));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: SingleChildScrollView(child: ClientCertificatesSection())),
      ),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(ClientCertificatesSection)));
    expect(find.text(l10n.tr('clientCertTitle')), findsOneWidget);
    expect(find.text('Ivanov Ivan'), findsOneWidget);
    expect(find.text('EC User'), findsOneWidget);
    expect(find.textContaining(l10n.tr('clientCertManaged')), findsOneWidget);
    // Кнопки — только у своего.
    expect(find.byTooltip(l10n.tr('clientCertEditDomains')), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.tr('delete')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('EC User'), findsNothing);
    expect(find.text('Ivanov Ivan'), findsOneWidget);
    expect(find.text(l10n.tr('clientCertAdd')), findsOneWidget);
  });
}
