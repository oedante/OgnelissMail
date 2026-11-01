// lib/core/utils/mail_clip.dart
// Очень длинные письма — только начало и кнопка «Показать письмо целиком»
// (1.9.x, просьба владельца 31.10.2026; так делают Gmail — «[Сообщение
// обрезано]» — и K-9).
//
// Огромные рассылки, длинные цепочки с цитатами, журналы и выгрузки делают
// окно письма очень высоким: память окна браузера растёт с его высотой, а
// при нехватке памяти система завершает процесс страницы (окно потом
// создаётся заново — MailHtmlView._onWebGone). Простое письмо виджетами и
// письмо без HTML — это сотни абзацев, которые раскладываются все сразу.
// Поэтому показывается начало, а письмо целиком — по кнопке. Ответ,
// пересылка, печать и PDF берут письмо целиком: обрезается только показ.
//
// Пороги:
//  · HTML — 150 тысяч знаков разметки (~150 КБ латиницей) без картинок
//    data: (они высоты не добавляют, а подпись с фото — это мегабайты
//    base64), без <style> и комментариев. Gmail обрезает от 102 КБ, обычная
//    рассылка со стилями в разметке — 20–100 тысяч знаков, так что
//    обрезаются только исключительные письма. Остаётся 100 тысяч: если
//    обрезать, то заметно (не «спрятана последняя строка»), а 100 тысяч
//    знаков текста — это уже ~40 000 точек высоты на телефоне, под пределом
//    высоты окна письма (60 000, MailHtmlView). Размер, а не число узлов:
//    узлы рассылки — это в основном ячейки вёрстки, высоту даёт текст.
//  · Текст (без HTML и простое письмо виджетами) — 100 000 знаков, остаётся
//    60 000 (~2 500 строк на телефоне): один абзац Flutter раскладывается
//    целиком, и такой текст — десятки миллисекунд на каждый кадр с
//    выделением или поворотом.

import 'package:html/dom.dart' as dom;

class MailClip {
  MailClip._();

  static const htmlLimit = 150 * 1024;
  static const htmlKeep = 100 * 1024;
  static const textLimit = 100000;
  static const textKeep = 60000;

  /// Меньше этого остатка в блок не спускаемся — обрезаем перед ним (по
  /// границе блока, а не посреди абзаца).
  static const _minPart = 2048;

  /// Картинка data: в атрибуте или стиле (src, background, url(…)).
  static final _dataUri = RegExp(r'''data:[^,"'\s>)]{0,100},[^"'\s>)]*''', caseSensitive: false);

  /// Элементы, которые не режутся внутри.
  static const _atomic = {'svg', 'math', 'picture', 'video', 'audio', 'select', 'textarea', 'object', 'button'};

  /// Не текст письма: в «вес» не входит и при обрезке остаётся.
  static const _noWeight = {'style', 'script', 'meta', 'link', 'title', 'head'};

  /// Длина строки без картинок data:.
  static int lengthWithoutData(String s) {
    var n = s.length;
    for (final m in _dataUri.allMatches(s)) {
      n -= m.end - m.start;
    }
    return n;
  }

  /// Обрезать тело письма [body] до начала по границе блока, если письмо
  /// длиннее [limit]. [raw] — исходный HTML: короткое письмо отсекается по
  /// его длине, без подсчёта по дереву. true — обрезано.
  static bool clipDom(dom.Element body, {String? raw, int limit = htmlLimit, int keep = htmlKeep}) {
    if (raw != null && (raw.length <= limit || lengthWithoutData(raw) <= limit)) return false;
    final w = Map<dom.Node, int>.identity();
    final total = _weigh(body, w, 0);
    if (total <= limit) return false;
    _cut(body, keep, w, 0);
    return true;
  }

  /// Примерная длина узла в разметке без картинок data:, стилей и комментариев.
  static int _weigh(dom.Node n, Map<dom.Node, int> w, int depth) {
    var sum = 0;
    if (n is dom.Text) {
      sum = n.data.length;
    } else if (n is dom.Element) {
      final tag = n.localName ?? '';
      if (_noWeight.contains(tag)) {
        w[n] = 0;
        return 0;
      }
      if (depth > 256) {
        sum = lengthWithoutData(n.outerHtml);
      } else {
        sum = 2 * tag.length + 5;
        n.attributes.forEach((k, v) => sum += k.toString().length + lengthWithoutData(v) + 4);
        for (final c in n.nodes) {
          sum += _weigh(c, w, depth + 1);
        }
      }
    }
    w[n] = sum;
    return sum;
  }

  /// Оставить в [e] начало «весом» не больше [budget]; остальное — убрать.
  static void _cut(dom.Element e, int budget, Map<dom.Node, int> w, int depth) {
    final nodes = e.nodes;
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final nw = w[n] ?? 0;
      if (nw <= budget) {
        budget -= nw;
        continue;
      }
      var keepThis = false;
      if (budget >= _minPart) {
        if (n is dom.Element && depth < 256 && !_atomic.contains(n.localName) && n.nodes.isNotEmpty) {
          _cut(n, budget, w, depth + 1);
          keepThis = true;
        } else if (n is dom.Text) {
          n.data = cutText(n.data, budget);
          keepThis = n.data.isNotEmpty;
        }
      }
      // Всё после места обрезки — убрать; стили письма остаются.
      for (var j = nodes.length - 1; j >= (keepThis ? i + 1 : i); j--) {
        final x = nodes[j];
        if (x is dom.Element && x.localName == 'style') continue;
        x.remove();
      }
      return;
    }
  }

  /// Начало текста длиной около [keep]: по концу строки, иначе по пробелу
  /// (не дальше половины), иначе ровно [keep] — не посреди суррогатной пары.
  static String cutText(String s, int keep) {
    if (s.length <= keep) return s;
    var at = s.lastIndexOf('\n', keep);
    if (at < keep ~/ 2) at = s.lastIndexOf(' ', keep);
    if (at < keep ~/ 2) at = keep;
    if (at > 0 && at < s.length) {
      final c = s.codeUnitAt(at - 1);
      if (c >= 0xD800 && c <= 0xDBFF) at--;
    }
    return s.substring(0, at).trimRight();
  }

  /// Начало длинного текста (письмо без HTML); null — текст не длинный.
  static String? clipText(String s, {int limit = textLimit, int keep = textKeep}) =>
      s.length <= limit ? null : cutText(s, keep);
}
