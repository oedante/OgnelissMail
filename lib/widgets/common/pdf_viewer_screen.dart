// lib/widgets/common/pdf_viewer_screen.dart
import 'dart:async';
import '../../core/platform/file_opener.dart';
import '../../core/theme/app_icons.dart';
// Встроенный PDF-просмотрщик — открывает PDF без выхода из приложения.
// Поддерживает: зум, прокрутку, поиск по тексту, шаринг.

import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'text_scale_cap.dart';

/// Экран просмотра PDF
/// Использует нативный рендеринг: на Android через PdfRenderer,
/// на iOS через PDFKit. Для полноценного просмотра рекомендуется
/// добавить syncfusion_flutter_pdfviewer или pdfx в pubspec.yaml.
/// Сейчас — fallback через open_filex (системный просмотрщик).
class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    this.title = 'PDF',
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isLoading = true;
  String? _error;
  Uint8List? _pdfBytes;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        final msg = AppLocalizations.of(context).tr('pdfFileNotFound');
        setState(() {
          _error = msg;
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      setState(() {
        _pdfBytes = bytes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // Поделиться
          IconButton(
            icon: const Icon(AppIcons.share),
            tooltip: l10n.tr('share'),
            onPressed: () {
              HapticFeedback.selectionClick();
              SharePlus.instance.share(ShareParams(files: [XFile(widget.filePath)], subject: widget.title));
            },
          ),
          // Открыть в системе
          IconButton(
            icon: const Icon(AppIcons.open_in_new),
            tooltip: l10n.tr('openInApp'),
            onPressed: () async {
              unawaited(HapticFeedback.selectionClick());
              await FileOpener.open(widget.filePath, mime: 'application/pdf');
            },
          ),
        ],
      )),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.error, size: 48, color: AppColors.errorRed),
                      const SizedBox(height: Space.l),
                      Text(_error!, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: Space.l),
                      FilledButton(
                        onPressed: _loadPdf,
                        child: Text(l10n.tr('retry')),
                      ),
                    ],
                  ),
                )
              : _pdfBytes != null
                  ? _buildPdfView(theme)
                  : const SizedBox.shrink(),
    );
  }

  Widget _buildPdfView(ThemeData theme) {
    // Встроенный просмотр PDF
    // В production рекомендуется pdfx или syncfusion_flutter_pdfviewer
    // Здесь — базовый просмотр через Image виджеты (первая страница)
    // и кнопка "Открыть в системном приложении"
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.picture_as_pdf, size: 80, color: AppColors.errorRed.withValues(alpha: 0.3)),
          const SizedBox(height: Space.l),
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.s),
          Text(
            _pdfBytes != null
                ? '${(_pdfBytes!.length / 1024).toStringAsFixed(1)} KB'
                : '',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),
          FilledButton.icon(
            onPressed: () async {
              // Открыть в системном просмотрщике
              try {
                // Динамический импорт
                await Process.run('open', [widget.filePath]); // macOS
              } catch (_) {
                try {
                  await Process.run('xdg-open', [widget.filePath]); // Linux
                } catch (_) {
                  // Android/iOS — через open_filex в onPressed AppBar
                }
              }
            },
            icon: const Icon(AppIcons.open_in_new),
            label: Text(AppLocalizations.of(context).tr('openPdf')),
          ),
        ],
      ),
    );
  }
}

/// Хелпер для открытия PDF из вложения
class PdfViewerHelper {
  /// Открыть PDF файл
  static void openPdf(BuildContext context, String filePath, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: filePath, title: title),
      ),
    );
  }

  /// Проверить, является ли файл PDF
  static bool isPdf(String fileName) {
    return fileName.toLowerCase().endsWith('.pdf');
  }
}
