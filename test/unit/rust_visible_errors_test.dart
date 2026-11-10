// Сборка ядра Rust (2.3.0): причина ошибки rustc — строками «error: …»,
// иначе Xcode показывает только «could not compile `cfg-if` due to 1
// previous error» (сборка владельца для iPhone 10.11.2026).

import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: implementation_imports, depend_on_referenced_packages, invalid_use_of_internal_member
import 'package:native_toolchain_rust/src/build_runner.dart';

void main() {
  test('error[E…] и = note: — видны Xcode', () {
    const stderr = 'error[E0463]: can\'t find crate for `core`\n'
        '  |\n'
        '  = note: the `aarch64-apple-ios` target may not be installed\n'
        '  = help: consider downloading the target with `rustup target add aarch64-apple-ios`\n'
        'error: could not compile `cfg-if` (lib) due to 1 previous error';
    final out = visibleRustErrors(stderr).split('\n');
    expect(out[0], 'error: rustc error[E0463]: can\'t find crate for `core`');
    expect(out[2], startsWith('error: rustc = note: the `aarch64-apple-ios` target'));
    expect(out[3], startsWith('error: rustc = help:'));
    expect(out[4], 'error: could not compile `cfg-if` (lib) due to 1 previous error');
  });
}
