// lib/widgets/common/inline_notice.dart
// Сообщение вверху экрана. С 1.10.2 — плашкой поверх окна (раньше строкой
// в разметке: она сдвигала экран вниз и обратно).
//
// Чёрные плашки (SnackBar) в приложении выключены (QuietScaffoldMessenger),
// и вместе с «Удалено»/«Сохранено» пропадали и сообщения об ошибках: «Не
// удалось отправить», «Превышен размер вложений», «Ошибка: …» — нажал, и
// ничего не произошло (09.10.2026). Теперь ошибки показываются здесь:
// спокойная плашка цвета ошибки под строкой состояния (до 1.10.2 — строка,
// сдвигавшая экран); убирается крестиком, нажатием или сама через 12 с.
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

/// Правило владельца 08.11.2026: пользователю показываются только
/// критические ошибки — когда нужны его действия или есть риск потерять
/// данные (письмо не ушло, черновик не сохранён, нужно войти снова, нет
/// папки «Архив», файл, которого человек ждёт, не открылся). Остальное
/// приложение выполняет повторно или пропускает молча — [quietError] и
/// [quietNotice], только в журнал (docs/guides/ERRORS.md).

/// Некритичная ошибка: не показывается, только в журнал.
void quietError(String text) {
  final t = text.trim();
  if (t.isEmpty) return;
  AppLogger.info('Не показано (некритично): $t');
}

/// Пояснение, без которого можно обойтись: не показывается, только в журнал.
void quietNotice(String text) {
  final t = text.trim();
  if (t.isEmpty) return;
  AppLogger.info('Не показано (пояснение): $t');
}

/// Показать КРИТИЧЕСКУЮ ошибку строкой вверху экрана (см. правило выше).
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

/// Слой над навигатором: сообщение — плашкой поверх окна сверху (1.10.2,
/// замечание владельца 02.11.2026: строка в разметке сдвигала письмо вниз,
/// а исчезая — поднимала обратно). Приложение под плашкой не двигается;
/// плашка выезжает сверху и уходит так же, без резких движений.
class InlineNoticeLayer extends StatelessWidget {
  final Widget child;
  const InlineNoticeLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Приложение — всегда на месте и не пересоздаётся при показе.
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<AppNotice?>(
            valueListenable: appNotice,
            builder: (context, notice, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              reverseDuration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (w, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(a),
                  child: w,
                ),
              ),
              child: notice == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : _NoticeCard(key: ValueKey(notice.id), notice: notice),
            ),
          ),
        ),
      ],
    );
  }
}

/// Плашка сообщения: под строкой состояния, с полями и тенью — поверх
/// содержимого, а не вместо него.
class _NoticeCard extends StatelessWidget {
  final AppNotice notice;
  const _NoticeCard({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = notice.kind != AppNoticeKind.info;
    final bg = error ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = error ? scheme.onErrorContainer : scheme.onSurface;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, 0),
        child: Center(
          child: ConstrainedBox(
            // На планшете и компьютере — не во всю ширину окна.
            constraints: const BoxConstraints(maxWidth: 640),
            child: Material(
              color: bg,
              elevation: 3,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: hideInlineError,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
                  child: Row(
                    children: [
                      Icon(error ? AppIcons.error : AppIcons.info, size: 20, color: error ? fg : scheme.primary),
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
      ),
    );
  }
}
