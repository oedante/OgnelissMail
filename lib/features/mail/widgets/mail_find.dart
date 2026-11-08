// lib/features/mail/widgets/mail_find.dart
// Поиск в открытом письме (2.2.0, план 08.11.2026 «из мессенджеров»: поиск
// внутри письма и беседы). «⋮ → Найти в письме» (на компьютере — F4, как в
// Outlook): строка под заголовком — поле, «3 из 12», ↑ ↓ и крестик.
//
// Совпадения подсвечиваются там, где показан текст: в простом показе
// (MailNativeBody) и в письме без HTML (LinkifiedText) — фоном текста,
// текущее — ярче, экран прокручивается к нему; в окне браузера
// (MailHtmlView) — поиском самого WebView (JavaScript письма для этого не
// нужен), прокрутка — к примерному месту по доле текста до совпадения.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';

/// Состояние поиска в письме: что ищем, сколько нашлось и какое текущее.
class MailFindController extends ChangeNotifier {
  String _query = '';
  int _current = 0;
  int _total = 0;

  /// Последний шаг человека: 1 — «Следующее», −1 — «Предыдущее», 0 — новый
  /// поиск или ответ показа (окно браузера само ведёт текущее совпадение).
  int step = 0;

  String get query => _query;

  /// Текущее совпадение (с нуля).
  int get current => _current;
  int get total => _total;
  bool get active => _query.trim().isNotEmpty;

  void setQuery(String q) {
    if (q == _query) return;
    _query = q;
    _current = 0;
    _total = 0;
    step = 0;
    notifyListeners();
  }

  void next() {
    if (_total == 0) return;
    _current = (_current + 1) % _total;
    step = 1;
    notifyListeners();
  }

  void prev() {
    if (_total == 0) return;
    _current = (_current - 1 + _total) % _total;
    step = -1;
    notifyListeners();
  }

  /// Показ письма сообщает, сколько нашлось (и какое текущее — окно
  /// браузера). Вызывать после кадра, не во время построения.
  void report(int total, {int? current}) {
    final cur = (current ?? _current).clamp(0, total == 0 ? 0 : total - 1);
    if (total == _total && cur == _current) return;
    _total = total;
    _current = cur;
    step = 0;
    notifyListeners();
  }
}

/// Места [query] в [text] без учёта регистра: (начало, конец).
List<(int, int)> findRanges(String text, String query) {
  final q = query.trim();
  if (q.isEmpty || text.isEmpty) return const [];
  var hay = text.toLowerCase();
  var needle = q.toLowerCase();
  // Редкие буквы меняют длину при смене регистра — тогда как есть.
  if (hay.length != text.length || needle.length != q.length) {
    hay = text;
    needle = q;
  }
  final out = <(int, int)>[];
  var at = hay.indexOf(needle);
  while (at >= 0) {
    out.add((at, at + needle.length));
    at = hay.indexOf(needle, at + needle.length);
  }
  return out;
}

/// Отрезок текста после разметки совпадениями: [match] — номер совпадения
/// в тексте (с нуля) или null.
typedef FindPiece = ({int run, String text, int? match});

/// Тексты [runs] подряд, разрезанные по совпадениям [ranges] (места — в
/// общем тексте `runs.join()`): куски каждого текста по порядку.
List<FindPiece> splitByMatches(List<String> runs, List<(int, int)> ranges) {
  final out = <FindPiece>[];
  var base = 0;
  var r = 0;
  for (var i = 0; i < runs.length; i++) {
    final t = runs[i];
    final end = base + t.length;
    var at = base;
    while (at < end) {
      while (r < ranges.length && ranges[r].$2 <= at) {
        r++;
      }
      if (r < ranges.length && ranges[r].$1 <= at) {
        final stop = ranges[r].$2 < end ? ranges[r].$2 : end;
        out.add((run: i, text: t.substring(at - base, stop - base), match: r));
        at = stop;
      } else {
        final next = r < ranges.length && ranges[r].$1 < end ? ranges[r].$1 : end;
        out.add((run: i, text: t.substring(at - base, next - base), match: null));
        at = next;
      }
    }
    base = end;
  }
  return out;
}

/// Фон совпадения: текущее — оранжевый, остальные — жёлтый (как в
/// браузерах); текст на нём — чёрный в обеих темах.
Color findMarkColor({required bool current}) => current ? const Color(0xFFFF9632) : const Color(0xFFFFE066);

/// Показать совпадение [start]…[end] абзаца [key] на экране (прокрутка
/// всех предков), с запасом вокруг. Абзац — Text (RenderParagraph) или
/// SelectableText (RenderEditable внутри).
void revealMatch(GlobalKey key, int start, int end) {
  final ro = key.currentContext?.findRenderObject();
  if (ro == null || !ro.attached) return;
  final sel = TextSelection(baseOffset: start, extentOffset: end);
  var target = ro;
  var boxes = const <TextBox>[];
  if (ro is RenderParagraph) {
    boxes = ro.getBoxesForSelection(sel);
  } else {
    RenderEditable? editable;
    void visit(RenderObject o) {
      if (editable != null) return;
      if (o is RenderEditable) {
        editable = o;
        return;
      }
      o.visitChildren(visit);
    }

    visit(ro);
    final e = editable;
    if (e != null) {
      boxes = e.getBoxesForSelection(sel);
      target = e;
    }
  }
  const duration = Duration(milliseconds: 200);
  if (boxes.isEmpty) {
    ro.showOnScreen(duration: duration);
    return;
  }
  var rect = boxes.first.toRect();
  for (final b in boxes.skip(1)) {
    rect = rect.expandToInclude(b.toRect());
  }
  target.showOnScreen(rect: rect.inflate(48), duration: duration);
}

/// Строка поиска под заголовком письма.
class MailFindBar extends StatefulWidget implements PreferredSizeWidget {
  static const double height = 52;
  final MailFindController controller;
  final VoidCallback onClose;
  final String? initial;

  /// Подсказка в пустом поле; null — «Текст в письме».
  final String? hint;
  const MailFindBar({super.key, required this.controller, required this.onClose, this.initial, this.hint});

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<MailFindBar> createState() => _MailFindBarState();
}

class _MailFindBarState extends State<MailFindBar> {
  late final TextEditingController _text = TextEditingController(text: widget.initial ?? widget.controller.query);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    if (_text.text.isNotEmpty) widget.controller.setQuery(_text.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _typed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => widget.controller.setQuery(v));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = widget.controller;
    final count = !c.active
        ? ''
        : c.total == 0
            ? l10n.tr('findNone')
            : l10n.tr('findCount').replaceAll('{n}', '${c.current + 1}').replaceAll('{m}', '${c.total}');
    return SizedBox(
      height: MailFindBar.height,
      child: Row(children: [
        const SizedBox(width: Space.m),
        Expanded(
          child: TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _typed,
            onSubmitted: (_) {
              _debounce?.cancel();
              if (c.query != _text.text) {
                c.setQuery(_text.text);
              } else {
                c.next();
              }
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint ?? l10n.tr('findInMailHint'),
              prefixIcon: const Icon(AppIcons.search, size: Sizes.iconRow),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
        if (count.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Text(count, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        IconButton(
          tooltip: l10n.tr('findPrev'),
          icon: const Icon(AppIcons.keyboard_arrow_up),
          onPressed: c.total > 1 ? c.prev : null,
        ),
        IconButton(
          tooltip: l10n.tr('findNext'),
          icon: const Icon(AppIcons.keyboard_arrow_down),
          onPressed: c.total > 1 ? c.next : null,
        ),
        IconButton(tooltip: l10n.tr('close'), icon: const Icon(AppIcons.close), onPressed: widget.onClose),
        const SizedBox(width: Space.xs),
      ]),
    );
  }
}
