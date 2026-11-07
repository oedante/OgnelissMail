// lib/services/documents/xls_crypt.dart
// Расшифровка книги Excel 97–2003 (BIFF8) с записью FilePass (1.15.1,
// технические хвосты по решению владельца 07.11.2026).
//
// Excel шифрует книгу и тогда, когда пароля на открытие нет: при защите
// структуры или «только для чтения» — стандартным паролем «VelvetSweatshop»
// ([defaultPassword]). Такие книги открываются в Excel без вопросов, а
// приложение раньше называло их «защищёнными паролем». Свой пароль на
// открытие приложению не известен — такие книги по-прежнему «защищены».
//
// По открытым спецификациям Microsoft [MS-OFFCRYPTO] 2.3.6 (RC4) и 2.3.5
// (RC4 CryptoAPI), [MS-XLS] 2.2.10: поток шифруется RC4 блоками по 1024
// байта от начала потока (ключ для каждого блока свой), заголовки записей
// не шифруются, но место в потоке занимают; не шифруются и данные записей
// BOF, FilePass, UsrExcl, FileLock, InterfaceHdr, RRDInfo, RRDHead и первые
// 4 байта BoundSheet8 (смещение листа). Обфускация XOR (старый способ) не
// поддерживается.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

class XlsCrypt {
  XlsCrypt._();

  /// Пароль, которым Excel шифрует книгу без пароля на открытие.
  static const defaultPassword = 'VelvetSweatshop';

  static const _bof = 0x0809;
  static const _filePass = 0x002F;
  static const _boundSheet = 0x0085;
  static const _clear = {0x0809, 0x002F, 0x0194, 0x0195, 0x00E1, 0x0196, 0x0138};
  static const _block = 1024;

  /// Есть ли в начале потока (общая часть книги) запись FilePass.
  static bool isEncrypted(Uint8List w) => _filePassAt(w) >= 0;

  /// Смещение данных записи FilePass в общей части книги; −1 — нет.
  static int _filePassAt(Uint8List w) {
    final bd = ByteData.sublistView(w);
    var p = 0;
    var depth = 0;
    while (p + 4 <= w.length) {
      final type = bd.getUint16(p, Endian.little), len = bd.getUint16(p + 2, Endian.little);
      if (type == _filePass) return p + 4;
      if (type == _bof) depth++;
      // FilePass стоит сразу после BOF общей части; дальше не ищем.
      if (type == 0x000A || (depth > 0 && p > 4096)) return -1;
      p += 4 + len;
    }
    return -1;
  }

  /// Расшифрованная копия потока книги; null — способ не поддерживается или
  /// пароль не подошёл.
  static Uint8List? decrypt(Uint8List w, {String password = defaultPassword}) {
    final at = _filePassAt(w);
    if (at < 0) return null;
    final bd = ByteData.sublistView(w);
    final len = bd.getUint16(at - 2, Endian.little);
    if (len < 6 || bd.getUint16(at, Endian.little) != 1) return null; // 0 — XOR
    final major = bd.getUint16(at + 2, Endian.little), minor = bd.getUint16(at + 4, Endian.little);
    _KeyFor? keyFor;
    if (major == 1 && minor == 1 && len >= 6 + 48) {
      keyFor = _rc4Binary(Uint8List.sublistView(w, at + 6, at + 6 + 48), password);
    } else if (major >= 2 && major <= 4 && minor == 2) {
      keyFor = _rc4CryptoApi(Uint8List.sublistView(w, at + 6, at + len), password);
    }
    if (keyFor == null) return null;
    return _decryptStream(w, keyFor);
  }

  // RC4 [MS-OFFCRYPTO] 2.3.6: соль, зашифрованные проверочное число и его MD5.
  static _KeyFor? _rc4Binary(Uint8List h, String password) {
    final salt = Uint8List.sublistView(h, 0, 16);
    final h0 = hash.md5.convert(_utf16le(password)).bytes.sublist(0, 5);
    final buf = BytesBuilder();
    for (var i = 0; i < 16; i++) {
      buf
        ..add(h0)
        ..add(salt);
    }
    final trunc = hash.md5.convert(buf.takeBytes()).bytes.sublist(0, 5);
    Uint8List keyFor(int block) => Uint8List.fromList(hash.md5.convert([...trunc, ..._le32(block)]).bytes);
    final rc4 = _rc4(keyFor(0));
    final verifier = _apply(rc4, Uint8List.sublistView(h, 16, 32));
    final verifierHash = _apply(rc4, Uint8List.sublistView(h, 32, 48));
    if (!_same(hash.md5.convert(verifier).bytes, verifierHash)) return null;
    return keyFor;
  }

  // RC4 CryptoAPI [MS-OFFCRYPTO] 2.3.5: заголовок с длиной ключа, затем
  // проверочные данные (соль, число, его SHA-1).
  static _KeyFor? _rc4CryptoApi(Uint8List h, String password) {
    if (h.length < 8) return null;
    final bd = ByteData.sublistView(h);
    final headerSize = bd.getUint32(4, Endian.little);
    const hdr = 8;
    if (headerSize < 32 || hdr + headerSize + 4 > h.length) return null;
    var keyBits = bd.getUint32(hdr + 16, Endian.little);
    if (keyBits == 0) keyBits = 40;
    if (keyBits < 40 || keyBits > 128 || keyBits % 8 != 0) return null;
    var v = hdr + headerSize;
    final saltSize = bd.getUint32(v, Endian.little);
    if (saltSize != 16 || v + 4 + 16 + 16 + 4 > h.length) return null;
    final salt = Uint8List.sublistView(h, v + 4, v + 20);
    final encVerifier = Uint8List.sublistView(h, v + 20, v + 36);
    final hashSize = bd.getUint32(v + 36, Endian.little);
    v += 40;
    if (hashSize != 20 || v + 20 > h.length) return null;
    final encHash = Uint8List.sublistView(h, v, v + 20);
    final h0 = hash.sha1.convert([...salt, ..._utf16le(password)]).bytes;
    Uint8List keyFor(int block) {
      final f = hash.sha1.convert([...h0, ..._le32(block)]).bytes;
      // 40-битный ключ дополняется нулями до 128 бит.
      return keyBits == 40
          ? Uint8List.fromList([...f.sublist(0, 5), ...List.filled(11, 0)])
          : Uint8List.fromList(f.sublist(0, keyBits ~/ 8));
    }

    final rc4 = _rc4(keyFor(0));
    final verifier = _apply(rc4, encVerifier);
    final verifierHash = _apply(rc4, encHash);
    if (!_same(hash.sha1.convert(verifier).bytes, verifierHash)) return null;
    return keyFor;
  }

  static Uint8List _decryptStream(Uint8List w, _KeyFor keyFor) {
    final out = Uint8List.fromList(w);
    final bd = ByteData.sublistView(w);
    // Ключевой поток блока по смещению — по мере надобности.
    var curBlock = -1;
    var ks = Uint8List(0);
    int ksAt(int pos) {
      final b = pos ~/ _block;
      if (b != curBlock) {
        curBlock = b;
        ks = _apply(_rc4(keyFor(b)), Uint8List(_block));
      }
      return ks[pos % _block];
    }

    var p = 0;
    var started = false;
    while (p + 4 <= w.length) {
      final type = bd.getUint16(p, Endian.little), len = bd.getUint16(p + 2, Endian.little);
      final at = p + 4;
      if (at + len > w.length) break;
      if (started && !_clear.contains(type)) {
        final from = type == _boundSheet ? at + 4 : at;
        for (var i = from; i < at + len; i++) {
          out[i] = w[i] ^ ksAt(i);
        }
      }
      if (type == _filePass) started = true;
      p = at + len;
    }
    return out;
  }

  static RC4Engine _rc4(Uint8List key) => RC4Engine()..init(false, KeyParameter(key));

  static Uint8List _apply(RC4Engine e, Uint8List data) {
    final out = Uint8List(data.length);
    e.processBytes(data, 0, data.length, out, 0);
    return out;
  }

  static Uint8List _utf16le(String s) {
    final out = BytesBuilder();
    for (final c in s.codeUnits) {
      out
        ..addByte(c & 0xFF)
        ..addByte(c >> 8);
    }
    return out.takeBytes();
  }

  static List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// Для журнала: способ защиты по записи FilePass.
  static String describe(Uint8List w) {
    final at = _filePassAt(w);
    if (at < 0) return 'none';
    final bd = ByteData.sublistView(w);
    if (bd.getUint16(at, Endian.little) == 0) return 'xor';
    return 'rc4 ${bd.getUint16(at + 2, Endian.little)}.${bd.getUint16(at + 4, Endian.little)}';
  }

}

typedef _KeyFor = Uint8List Function(int block);
