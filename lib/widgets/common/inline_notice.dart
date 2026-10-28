// lib/widgets/common/inline_notice.dart
// Сообщение — строкой вверху экрана, в разметке, а не плашкой поверх
// содержимого.
//
// Чёрные плашки (SnackBar) в приложении выключены (QuietScaffoldMessenger),
// и вместе с «Удалено»/«Сохранено» пропадали и сообщения об ошибках: «Не
// удалось отправить», «Превышен размер вложений», «Ошибка: …» — нажал, и
// ничего не произошло (09.10.2026). Теперь ошибки показываются здесь:
// спокойная строка цвета ошибки под строкой состояния, сдвигает экран вниз,
// ничего не закрывает; убирается крестиком, нажатием или сама через 12 с.
//
// 1.8.0 (п. 12 плана: «всплывающие сообщения внизу экрана заменить строкой
// вверху»): все вызовы SnackBar переведены сюда. Правило:
//  · ошибка или «почему ничего не произошло» — [showInlineError];
//  · сведения, которых иначе не видно («Сохранено в Загрузки: файл»,
//    «Добавлено адресатов: 5», «Отправлено в очередь») — [showInlineNotice],
//    спокойная строка цвета поверхности, сама уходит через 5 с, может нести
//    кнопку («Открыть», «Отменить»);
//  · подтверждение того, что и так видно на экране («Сохранено» в закрытой
//    форме, «Удалено» из списка) — только в журнал (решение владельца
//    07.10.2026: такие плашки мешают).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

/// Вид строки: ошибка или сведения.
enum AppNoticeKind { error, info }

class AppNotice {
  final String text;
  final int id;
  final AppNoticeKind kind;

  /// Кнопка в строке (null — без кнопки).
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppNotice(this.text, this.id, {this.kind = AppNoticeKind.error, this.actionLabel, this.onAction});
}

/// Текущее сообщение (null — нет). Доступно откуда угодно, без контекста.
final ValueNotifier<AppNotice?> appNotice = ValueNotifier<AppNotice?>(null);
int _seq = 0;
Timer? _hideTimer;

void _show(AppNotice n, Duration duration) {
  appNotice.value = n;
  _hideTimer?.cancel();
  _hideTimer = Timer(duration, () {
    if (appNotice.value?.id == n.id) appNotice.value = null;
  });
}

String _clip(String t) => t.length > 300 ? '${t.substring(0, 300)}…' : t;

/// Показать ошибку строкой вверху экрана.
void showInlineError(String text) {
  final t = text.trim();
  if (t.isEmpty) return;
  // И в журнал (1.7.2+106): по присланному журналу видно, что человек
  // увидел на экране.
  AppLogger.warning('Строка ошибки: $t');
  _show(AppNotice(_clip(t), ++_seq), const Duration(seconds: 12));
}

/// Показать сведения строкой вверху экрана (1.8.0): спокойный цвет, сама
/// уходит через [duration]. [actionLabel] и [onAction] — кнопка в строке.
/// Ошибку строкой сведений не заменяет: ошибка — [showInlineError].
void showInlineNotice(String text, {String? actionLabel, VoidCallback? onAction, Duration? duration}) {
  final t = text.trim();
  if (t.isEmpty) return;
  AppLogger.info('Строка сведений: $t');
  final hasAction = actionLabel != null && onAction != null;
  _show(
    AppNotice(_clip(t), ++_seq,
        kind: AppNoticeKind.info, actionLabel: hasAction ? actionLabel : null, onAction: hasAction ? onAction : null),
    duration ?? Duration(seconds: hasAction ? 8 : 5),
  );
}

void hideInlineError() {
  _hideTimer?.cancel();
  appNotice.value = null;
}

/// Убрать строку (любого вида).
void hideInlineNotice() => hideInlineError();

/// Слой над навигатором: строка сверху, под ней — приложение.
class InlineNoticeLayer extends StatelessWidget {
  final Widget child;
  const InlineNoticeLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppNotice?>(
      valueListenable: appNotice,
      // child передаётся как есть: навигатор не пересоздаётся при показе.
      child: child,
      builder: (context, notice, app) {
        final scheme = Theme.of(context).colorScheme;
        final error = notice?.kind != AppNoticeKind.info;
        final bg = error ? scheme.errorContainer : scheme.surfaceContainerHighest;
        final fg = error ? scheme.onErrorContainer : scheme.onSurface;
        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: notice == null
                  ? const SizedBox(width: double.infinity)
                  : Material(
                      color: bg,
                      child: SafeArea(
                        bottom: false,
                        child: InkWell(
                          onTap: hideInlineError,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
                            child: Row(
                              children: [
                                Icon(error ? AppIcons.error : AppIcons.info, size: 20,
                                    color: error ? fg : scheme.primary),
                                const SizedBox(width: Space.m),
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      notice.text,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                                    ),
                                  ),
                                ),
                                if (notice.actionLabel != null)
                                  TextButton(
                                    onPressed: () {
                                      final act = notice.onAction;
                                      hideInlineError();
                                      act?.call();
                                    },
                                    child: Text(notice.actionLabel!),
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(AppIcons.close, size: 20, color: fg),
                                  onPressed: hideInlineError,
                                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            // Строка заняла место строки состояния — экранам верхний отступ
            // больше не нужен (иначе шапка опустилась бы ещё раз).
            // Обёртка есть всегда — меняется только флаг: иначе при показе
            // строки навигатор пересоздавался бы со всеми открытыми экранами.
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: notice != null, child: app!),
            ),
          ],
        );
      },
    );
  }
}
