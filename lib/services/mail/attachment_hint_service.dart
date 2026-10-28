// lib/services/mail/attachment_hint_service.dart
//
// «Вы упомянули вложение, но не прикрепили файл».
//
// Классическая защита деловой переписки: человек пишет «во вложении смета»,
// нажимает «Отправить» — и уходит письмо без файла. Приходится извиняться и
// слать повторно, а в переписке с подрядчиком это ещё и потеря времени.
//
// Проверка идёт ЛОКАЛЬНО по тексту письма. Ищем упоминания вложения, но
// исключаем случаи, когда речь о вложении в ЦИТИРУЕМОМ письме («вы писали:
// во вложении…») — иначе предупреждение будет срабатывать на каждый ответ.

class AttachmentHintService {
  AttachmentHintService._();

  /// Маркеры упоминания вложения. Русские — основные, английские нужны для
  /// переписки с внешними контрагентами.
  /// Маркеры упоминания вложения.
  ///
  /// ВАЖНО: `\b` здесь НЕ используется. В Dart граница слова `\b` определяется
  /// по ASCII-классу `[A-Za-z0-9_]`, и рядом с кириллицей она не срабатывает:
  /// в строке «Коллеги, во вложении» между пробелом и «в» ASCII-границы нет,
  /// поэтому шаблон `\bво` не совпадал — русские маркеры не работали вовсе.
  /// Вместо этого начало слова проверяется явно: начало строки либо пробел
  /// или знак препинания перед ним.
  static const _wordStart = r'(?:^|[\s.,;:!?(«"\-])';

  static final _markers = <RegExp>[
    // Русский
    RegExp('$_wordStartво\\s+влож', caseSensitive: false),
    RegExp('$_wordStartв\\s+прилож', caseSensitive: false),
    RegExp('$_wordStartприклад(ыва|аю|ываем)', caseSensitive: false),
    RegExp('$_wordStartприлага(ю|ем|ется|ются)', caseSensitive: false),
    RegExp('$_wordStartприлож(ил|ила|или|ен|ена|ено|ены)(\$|[\\s.,;:!?)»])', caseSensitive: false),
    RegExp('$_wordStartвлож(ил|ила|или)(\$|[\\s.,;:!?)»])', caseSensitive: false),
    RegExp('$_wordStartвложенн(ый|ом|ые|ых|ую)\\s+(файл|документ|скан)', caseSensitive: false),
    RegExp('$_wordStart(направля|высыла|отправля|посыла|пересыла)(ю|ем)\\s+(вам\\s+)?(файл|документ|скан|копи|договор|сч[её]т|акт|смет|презентаци|таблиц)',
        caseSensitive: false),
    RegExp('$_wordStartсм\\.\\s*(влож|прилож)', caseSensitive: false),
    RegExp('$_wordStartприкреп(ил|ила|или|лен|лён|лена|лено|лены|ляю|ляем)', caseSensitive: false),
    // English — здесь \b работает корректно.
    RegExp(r'\battach(ed|ing|ment|ments)\b', caseSensitive: false),
    RegExp(r'\benclosed\b', caseSensitive: false),
    // Deutsch
    RegExp(r'\bim\s+anhang\b', caseSensitive: false),
    RegExp(r'\banbei\b', caseSensitive: false),
    RegExp(r'\b(angeh[äa]ngt|beigef[üu]gt|als\s+anhang|anh[äa]nge|h[äa]nge\s+ich)', caseSensitive: false),
    // Français
    RegExp(r'\bci-joint(e|s|es)?\b', caseSensitive: false),
    RegExp(r'\bpi[èe]ces?\s+jointes?', caseSensitive: false),
    RegExp(r'\b(je|nous)\s+(vous\s+)?(joins|joignons|transmets)\b', caseSensitive: false),
    RegExp(r'\ben\s+pj\b', caseSensitive: false),
  ];

  /// Нужно ли предупредить об отсутствующем вложении.
  ///
  /// [bodyText] — текст письма (для HTML сначала снимите разметку),
  /// [hasAttachments] — есть ли реально прикреплённые файлы.
  static bool shouldWarn({required String bodyText, required bool hasAttachments}) {
    if (hasAttachments) return false;
    final own = _stripQuoted(bodyText);
    if (own.trim().isEmpty) return false;
    return _markers.any((r) => r.hasMatch(own));
  }

  /// Отсекает цитируемую часть письма: при ответе там почти наверняка есть
  /// «во вложении» из исходного сообщения, и без этого фильтра предупреждение
  /// показывалось бы почти всегда.
  static String _stripQuoted(String text) {
    // 1) Явные разделители цитаты.
    // Цитата начинается строкой-разделителем на любом из 4 языков или блоком
    // заголовков Outlook («От:/From:/Von:/De :» в начале строки).
    final sep = RegExp(
      r'(^|\n)\s*(-{2,}\s*(Original Message|Исходное сообщение|Ursprüngliche Nachricht|Message d.origine)|'
      r'-{5,}|_{5,}|On .{5,80} wrote:|Am .{5,80} schrieb .{0,80}:|Le .{5,80} a [ée]crit\s*:|'
      r'\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}.{0,60}(пишет|wrote|написал|написала)\s*:|'
      r'(От|From|Von|De)\s?:\s*\S.*\n\s*(Отправлено|Sent|Gesendet|Envoy[ée]|Дата|Date|Datum)\s?:)',
      caseSensitive: false,
    ).firstMatch(text);
    var own = sep != null ? text.substring(0, sep.start) : text;

    // 2) Строки, начинающиеся с «>» — типовая разметка цитаты.
    own = own
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('>'))
        .join('\n');
    return own;
  }
}
