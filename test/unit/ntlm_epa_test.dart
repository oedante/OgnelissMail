import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ntlm_client.dart';

void main() {
  test('withChannelBindings вставляет MsvAvChannelBindings перед EOL', () {
    // NbDomainName «A» (AvId 2) + EOL
    final info = Uint8List.fromList([2, 0, 2, 0, 0x41, 0, 0, 0, 0, 0]);
    final hash = Uint8List.fromList(List.generate(16, (i) => i));
    final out = NtlmClient.withChannelBindings(info, hash);
    expect(out.sublist(0, 6), [2, 0, 2, 0, 0x41, 0]);
    expect(out.sublist(6, 10), [0x0A, 0, 0x10, 0]);
    expect(out.sublist(10, 26), hash);
    expect(out.sublist(26), [0, 0, 0, 0]);
  });

  test('повторная привязка заменяет прежнюю', () {
    final first = NtlmClient.withChannelBindings(Uint8List.fromList([0, 0, 0, 0]), Uint8List(16));
    final second = NtlmClient.withChannelBindings(first, Uint8List.fromList(List.filled(16, 7)));
    expect(second.length, 4 + 16 + 4);
    expect(second.sublist(4, 20), List.filled(16, 7));
  });

  test('channelBindingsHash — 16 байт MD5, не падает на мусоре', () {
    expect(NtlmClient.channelBindingsHash(Uint8List.fromList([1, 2, 3])).length, 16);
  });
}
