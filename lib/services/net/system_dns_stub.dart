// lib/services/net/system_dns_stub.dart
// Браузер: системного DNS нет — записей нет (см. system_dns.dart).

import 'system_dns.dart';

Future<List<List<DnsRecord>?>?> platformLookup(List<DnsQuestion> questions) async => null;
