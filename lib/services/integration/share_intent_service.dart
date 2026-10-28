// lib/services/integration/share_intent_service.dart
// Интеграция с системной функцией "Поделиться" (Windows/Android/iOS/Linux).
// Принимает файлы/текст/ссылки из других приложений и открывает окно
// создания письма с вложением/текстом.
//
// Использует receive_sharing_intent (Android/iOS). На desktop (Windows/Linux)
// шаринг приходит через аргументы запуска/протокол — обрабатывается отдельно.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/logging/app_logger.dart';

/// Данные, пришедшие через "Поделиться".
class SharedPayload {
  final List<String> filePaths;
  final String? text;
  const SharedPayload({this.filePaths = const [], this.text});

  bool get isEmpty => filePaths.isEmpty && (text == null || text!.isEmpty);
}

final shareIntentProvider = Provider<ShareIntentService>((ref) => ShareIntentService());

class ShareIntentService {
  StreamSubscription? _mediaSub;
  final _controller = StreamController<SharedPayload>.broadcast();

  /// Поток входящих "Поделиться". UI подписывается и открывает compose.
  Stream<SharedPayload> get stream => _controller.stream;

  /// Инициализация слушателей. Вызывать при старте приложения.
  Future<void> init() async {
    // Только мобильные платформы поддерживают receive_sharing_intent
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    try {
      // Шаринг, когда приложение уже запущено
      _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (items) => _emit(items),
        onError: (e) => AppLogger.warning('Share stream error: $e'),
      );

      // Шаринг, который запустил приложение (cold start)
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        _emit(initial);
        unawaited(ReceiveSharingIntent.instance.reset());
      }
    } catch (e) {
      AppLogger.warning('ShareIntent init: $e');
    }
  }

  void _emit(List<SharedMediaFile> items) {
    if (items.isEmpty) return;
    final files = <String>[];
    String? text;
    for (final it in items) {
      switch (it.type) {
        case SharedMediaType.text:
        case SharedMediaType.url:
          text = (text == null) ? it.path : '$text\n${it.path}';
          break;
        default:
          // Android: файл должен быть копией, сделанной ShareIntentSanitizer
          // (MainActivity) в cache/shared_in. Всё остальное — путь, который
          // прислал отправитель, в том числе к личным файлам приложения.
          if (Platform.isAndroid && !it.path.contains('/shared_in/')) {
            AppLogger.warning('Поделиться: отклонён файл вне безопасного каталога');
            break;
          }
          files.add(it.path);
      }
    }
    final payload = SharedPayload(filePaths: files, text: text);
    if (!payload.isEmpty) {
      AppLogger.info('Получено через "Поделиться": ${files.length} файлов, текст=${text != null}');
      _controller.add(payload);
    }
  }

  /// Обработка шаринга на desktop через аргументы командной строки
  /// (Windows/Linux передают путь к файлу при "Открыть с помощью").
  void handleDesktopArgs(List<String> args) {
    if (kIsWeb) return;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    final files = args.where((a) => File(a).existsSync()).toList();
    if (files.isNotEmpty) {
      _controller.add(SharedPayload(filePaths: files));
    }
  }

  void dispose() {
    _mediaSub?.cancel();
    _controller.close();
  }
}
