// lib/services/mail/pkpass_parser.dart
// Электронные билеты и посадочные .pkpass (Apple Wallet) во вложениях —
// просмотр карточкой прямо в приложении (план П3, пункт 16, 11.10.2026).
//
// .pkpass — zip-архив с pass.json: организация, описание, поля (рейс, место,
// выход, время), штрихкод (текст сообщения и формат), дата, цвета карточки.
// Подпись Apple (signature) не проверяется — это просмотр, а не добавление
// в кошелёк. Локализованные строки (ru.lproj/pass.strings) подставляются,
// если есть язык приложения или английский.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class PkPassField {
  final String label;
  final String value;
  const PkPassField(this.label, this.value);
}

class PkPass {
  final String organization;
  final String description;
  final String logoText;

  /// boardingPass, eventTicket, coupon, storeCard, generic.
  final String style;
  final List<PkPassField> header;
  final List<PkPassField> primary;
  final List<PkPassField> secondary;
  final List<PkPassField> auxiliary;
  final List<PkPassField> back;
  final String? barcodeMessage;
  final String? barcodeFormat;
  final String? barcodeAltText;
  final DateTime? relevantDate;
  final int? background; // 0xFFRRGGBB
  final int? foreground;
  final int? labelColor;
  final Uint8List? logo;

  const PkPass({
    required this.organization,
    required this.description,
    required this.logoText,
    required this.style,
    this.header = const [],
    this.primary = const [],
    this.secondary = const [],
    this.auxiliary = const [],
    this.back = const [],
    this.barcodeMessage,
    this.barcodeFormat,
    this.barcodeAltText,
    this.relevantDate,
    this.background,
    this.foreground,
    this.labelColor,
    this.logo,
  });

  /// Все лицевые поля по порядку — для краткого вида.
  List<PkPassField> get front => [...header, ...primary, ...secondary, ...auxiliary];
}

class PkPassParser {
  PkPassParser._();

  static const _styles = ['boardingPass', 'eventTicket', 'coupon', 'storeCard', 'generic'];

  /// Разобрать .pkpass. null — не архив или нет pass.json.
  static PkPass? parse(Uint8List bytes, {String lang = 'en'}) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    ArchiveFile? find(String name) {
      for (final f in zip.files) {
        if (f.isFile && f.name.toLowerCase() == name.toLowerCase()) return f;
      }
      return null;
    }

    final passFile = find('pass.json');
    if (passFile == null) return null;
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(_text(passFile.content as List<int>)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final strings = <String, String>{
      ..._strings(find('en.lproj/pass.strings')),
      if (lang != 'en') ..._strings(find('$lang.lproj/pass.strings')),
    };
    String t(Object? v) {
      final s = v == null ? '' : '$v';
      return strings[s] ?? s;
    }

    final style = _styles.firstWhere((s) => j[s] is Map, orElse: () => 'generic');
    final body = (j[style] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    List<PkPassField> fields(String key) => [
          for (final f in (body[key] as List? ?? const []))
            if (f is Map && f['value'] != null)
              PkPassField(t(f['label']), _value(f['value'], t)),
        ];

    final barcodes = (j['barcodes'] as List?)?.whereType<Map>().toList() ?? const [];
    final barcode = barcodes.isNotEmpty ? barcodes.first : (j['barcode'] is Map ? j['barcode'] as Map : null);

    final logoFile = find('logo@2x.png') ?? find('logo.png');
    return PkPass(
      organization: t(j['organizationName']),
      description: t(j['description']),
      logoText: t(j['logoText']),
      style: style,
      header: fields('headerFields'),
      primary: fields('primaryFields'),
      secondary: fields('secondaryFields'),
      auxiliary: fields('auxiliaryFields'),
      back: fields('backFields'),
      barcodeMessage: barcode?['message'] as String?,
      barcodeFormat: (barcode?['format'] as String?)?.replaceFirst('PKBarcodeFormat', ''),
      barcodeAltText: barcode?['altText'] as String?,
      relevantDate: DateTime.tryParse('${j['relevantDate'] ?? ''}')?.toLocal(),
      background: parseColor(j['backgroundColor'] as String?),
      foreground: parseColor(j['foregroundColor'] as String?),
      labelColor: parseColor(j['labelColor'] as String?),
      logo: logoFile == null ? null : Uint8List.fromList(logoFile.content as List<int>),
    );
  }

  /// «rgb(23, 187, 82)» или «#17BB52» → 0xFF17BB52.
  static int? parseColor(String? s) {
    if (s == null) return null;
    final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(s);
    if (rgb != null) {
      int c(int i) => int.parse(rgb.group(i)!).clamp(0, 255);
      return 0xFF000000 | (c(1) << 16) | (c(2) << 8) | c(3);
    }
    final hex = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s.trim());
    if (hex != null) return 0xFF000000 | int.parse(hex.group(1)!, radix: 16);
    return null;
  }

  static String _value(Object v, String Function(Object?) t) {
    if (v is num) return v % 1 == 0 ? v.toInt().toString() : v.toString();
    final s = '$v';
    // Дата и время ISO 8601 — коротко, по-местному.
    final d = RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s) ? DateTime.tryParse(s) : null;
    if (d != null) {
      final l = d.toLocal();
      String two(int x) => x.toString().padLeft(2, '0');
      return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
    }
    return t(s);
  }

  /// pass.strings: «"ключ" = "значение";», файл в UTF-16 или UTF-8.
  static Map<String, String> _strings(ArchiveFile? f) {
    if (f == null) return const {};
    final text = _text(f.content as List<int>);
    final out = <String, String>{};
    for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;').allMatches(text)) {
      String un(String s) => s.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').replaceAll(r'\\', '\\');
      out[un(m.group(1)!)] = un(m.group(2)!);
    }
    return out;
  }

  static String _text(List<int> b) {
    // UTF-16 с меткой порядка байтов (так часто сохраняют pass.strings).
    if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
      final le = b[0] == 0xFF;
      final units = <int>[];
      for (var i = 2; i + 1 < b.length; i += 2) {
        units.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(b, allowMalformed: true);
  }
}
