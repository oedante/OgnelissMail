// lib/features/mail/screens/mail_list_pager.dart
// Листать письма ленты свайпом влево-вправо (1.6.49+95, как в Gmail и
// мессенджерах): письмо из ленты открывается страницей, соседние страницы —
// соседние письма ленты в том же порядке. Порядок фиксируется при открытии:
// новое письмо или отметка «прочитано» страницу не сдвигают. Выключается в
// «Настройки → Почта».
//
// Тело письма (встроенное окно браузера) и отметка «прочитано» — только у
// страницы, на которой листание остановилось (как в беседе): окно соседней
// страницы, созданное на ходу, давало рывок.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/mail_open_cache.dart';
import 'mail_detail_screen.dart';

/// Письма ленты для листания: ящик и id, по порядку ленты.
class MailPagerArgs {
  final List<(String accountId, String emailId)> items;
  final int index;
  const MailPagerArgs(this.items, this.index);
}

class MailListPagerScreen extends ConsumerStatefulWidget {
  final MailPagerArgs args;
  const MailListPagerScreen({super.key, required this.args});

  @override
  ConsumerState<MailListPagerScreen> createState() => _MailListPagerScreenState();
}

class _MailListPagerScreenState extends ConsumerState<MailListPagerScreen> {
  late final PageController _controller = PageController(initialPage: widget.args.index);
  late int _settled = widget.args.index;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchAround(_settled);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _prefetchAround(int p) {
    final items = widget.args.items;
    final cache = ref.read(mailOpenCacheProvider);
    for (final i in [p - 1, p + 1]) {
      if (i >= 0 && i < items.length) cache.prefetch(items[i].$1, items[i].$2);
    }
  }

  void _onScrollEnd() {
    if (!_controller.hasClients) return;
    final n = widget.args.items.length;
    var p = (_controller.page ?? _settled.toDouble()).round();
    if (p < 0) p = 0;
    if (p > n - 1) p = n - 1;
    if (p != _settled) setState(() => _settled = p);
    _prefetchAround(p);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.args.items;
    return NotificationListener<ScrollEndNotification>(
      // Только листание страниц (прокрутка письма внутри — глубже).
      onNotification: (note) {
        if (note.depth == 0) _onScrollEnd();
        return false;
      },
      child: PageView.builder(
        controller: _controller,
        itemCount: items.length,
        itemBuilder: (context, i) => MailDetailScreen(
          key: ValueKey('${items[i].$1}|${items[i].$2}'),
          emailId: items[i].$2,
          accountId: items[i].$1,
          active: i == _settled,
        ),
      ),
    );
  }
}
