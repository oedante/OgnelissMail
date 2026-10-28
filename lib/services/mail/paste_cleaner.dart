// lib/services/mail/paste_cleaner.dart
//
// Очистка HTML, вставленного из Word, Excel и веб-страниц.
//
// Проблема, знакомая любому, кто вставлял таблицу из Excel в письмо: вместе с
// данными приходит гора служебной разметки Office — условные комментарии,
// `mso-*` стили, классы `MsoNormal`, разметка `<o:p>`. Таблица на десять строк
// превращается в письмо весом в сотни килобайт, которое к тому же по-разному
// выглядит у получателей.
//
// Чистим ПЕРЕД отправкой, а не при вставке: редактор работает в WebView, и
// перехватывать там буфер обмена ненадёжно — поведение отличается на Android,
// iOS и десктопе. Обработка готового HTML одинакова везде.
//
// Что НЕ трогаем: сам текст, структуру таблиц, ссылки, форматирование, которое
// пользователь задал сознательно (жирный, курсив, цвет, выравнивание).

class PasteCleaner {
  PasteCleaner._();

  /// Порог, после которого стоит предупредить о размере письма.
  /// 2 МБ — многие серверы режут письма около 10 МБ, а base64 раздувает
  /// картинки на треть; при таком теле легко упереться в лимит.
  static const int warnBodyBytes = 2 * 1024 * 1024;

  /// Очищает HTML от служебной разметки Office и веб-страниц.
  static String clean(String html) {
    if (html.isEmpty) return html;
    var s = html;

    // 1. Условные комментарии Word: <!--[if gte mso 9]>…<![endif]-->
    s = s.replaceAll(RegExp(r'<!--\[if[\s\S]*?<!\[endif\]-->', caseSensitive: false), '');

    // 2. Блоки <style> из Office: там сотни правил mso-*, которые почтовые
    //    клиенты всё равно игнорируют или трактуют по-своему.
    s = s.replaceAll(
        RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');

    // 3. Теги пространства имён Office: <o:p>, <w:WordDocument>, <v:shape>.
    s = s.replaceAll(RegExp(r'</?(o|w|v|m|x):[^>]*>', caseSensitive: false), '');

    // 4. Свойства mso-* внутри style="…" — оставляем остальные стили.
    s = s.replaceAllMapped(
      RegExp(r'style\s*=\s*"([^"]*)"', caseSensitive: false),
      (m) {
        final props = m
            .group(1)!
            .split(';')
            .where((p) => p.trim().isNotEmpty)
            .where((p) => !p.trimLeft().toLowerCase().startsWith('mso-'))
            // Word задаёт огромные отступы страницы — в письме они не нужны.
            .where((p) => !RegExp(r'^\s*(margin|padding)-(top|bottom)\s*:\s*0(cm|pt|in)',
                    caseSensitive: false)
                .hasMatch(p))
            .join(';');
        return props.isEmpty ? '' : 'style="$props"';
      },
    );

    // 5. Классы Office: MsoNormal, MsoListParagraph и т.п. Они ссылаются на
    //    удалённый <style>, поэтому без него бесполезны.
    s = s.replaceAllMapped(
      RegExp(r'class\s*=\s*"([^"]*)"', caseSensitive: false),
      (m) {
        final classes = m
            .group(1)!
            .split(RegExp(r'\s+'))
            .where((c) => c.isNotEmpty)
            .where((c) => !c.toLowerCase().startsWith('mso'))
            .where((c) => !c.toLowerCase().startsWith('x_'))
            .join(' ');
        return classes.isEmpty ? '' : 'class="$classes"';
      },
    );

    // 6. Пустые атрибуты и лишние пробелы после чисток.
    s = s.replaceAll(RegExp(r'\s(style|class)\s*=\s*""'), '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');

    // 7. Пустые абзацы, которыми Word разделяет блоки.
    s = s.replaceAll(
        RegExp(r'<p[^>]*>(\s|&nbsp;)*</p>', caseSensitive: false), '');

    return s.trim();
  }

  /// Примерный размер тела письма в байтах. Считаем по длине строки: HTML в
  /// основном ASCII, а base64-картинки — тем более.
  static int bodyBytes(String html) => html.length;

  /// Сколько в теле встроенных base64-картинок и сколько они весят.
  ///
  /// Такие картинки появляются, когда скриншот вставляют прямо в письмо.
  /// Формально это работает, но письмо распухает, а некоторые серверы и
  /// клиенты режут или не показывают data-URI.
  static ({int count, int bytes}) inlineImages(String html) {
    var count = 0;
    var bytes = 0;
    for (final m in RegExp(r'data:image/[a-z+]+;base64,([A-Za-z0-9+/=]+)',
            caseSensitive: false)
        .allMatches(html)) {
      count++;
      // base64 длиннее исходных данных примерно на треть.
      bytes += (m.group(1)!.length * 3 / 4).round();
    }
    return (count: count, bytes: bytes);
  }
}
