// lib/services/export/email_pdf_service.dart
//
// Экспорт письма в PDF.
//
// Почему именно так:
// · Используется только пакет `pdf` (чистый Dart). Пакет `printing` не берём —
//   он требует платформенной настройки, а делиться файлом умеет share_plus,
//   который в проекте уже есть.
// · ОБЯЗАТЕЛЬНО подключается TTF с кириллицей (Roboto): встроенные шрифты PDF
//   (Helvetica/Times/Courier) содержат только латиницу, и русский текст в них
//   не отрисовывается вовсе. Шрифт лежит в assets/fonts/pdf/.
// · HTML-тело приводится к тексту: пакет `pdf` не рендерит HTML. Это осознанный
//   компромисс — верстка теряется, содержание сохраняется.

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/logging/app_logger.dart';
import '../../data/models/email_model.dart';

class EmailPdfService {
  EmailPdfService._();

  /// Кэш загруженных шрифтов: чтение из assets и разбор TTF не бесплатны,
  /// а экспорт может вызываться несколько раз подряд.
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) return;
    final reg = await rootBundle.load('assets/fonts/pdf/Roboto-Regular.ttf');
    final bld = await rootBundle.load('assets/fonts/pdf/Roboto-Bold.ttf');
    _regular = pw.Font.ttf(reg);
    _bold = pw.Font.ttf(bld);
  }

  /// Преобразует HTML в читаемый текст: скрипты/стили выбрасываем целиком,
  /// переводы строк сохраняем, сущности раскрываем, лишние пустые строки сжимаем.
  static String htmlToPlainText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|tr|li|h[1-6])>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–');
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  /// Собирает PDF письма и сохраняет во временный каталог.
  /// Возвращает путь к файлу; при ошибке — null (ошибка уходит в лог).
  ///
  /// [labels] — подписи полей на языке интерфейса: from, to, cc, date,
  /// attachments, noSubject.
  static Future<String?> exportEmail(
    EmailModel email, {
    required Map<String, String> labels,
    String? accountName,
  }) async {
    try {
      await _ensureFonts();

      final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
      final doc = pw.Document(theme: theme);

      final subject = email.subject.trim().isEmpty
          ? (labels['noSubject'] ?? '(no subject)')
          : email.subject.trim();

      final body = (email.bodyPlain?.trim().isNotEmpty ?? false)
          ? email.bodyPlain!.trim()
          : htmlToPlainText(email.bodyHtml ?? '');

      String addr(EmailAddress a) =>
          (a.displayName != null && a.displayName!.isNotEmpty) ? '${a.displayName} <${a.email}>' : a.email;
      String addrs(List<EmailAddress> list) => list.map(addr).join(', ');

      final d = email.receivedAt.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      final dateStr =
          '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
          footer: (ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
          build: (ctx) => [
            pw.Text(subject, style: pw.TextStyle(font: _bold, fontSize: 16)),
            pw.SizedBox(height: 10),
            _meta(labels['from'] ?? 'From', addr(email.from)),
            if (email.to.isNotEmpty) _meta(labels['to'] ?? 'To', addrs(email.to)),
            if (email.cc.isNotEmpty) _meta(labels['cc'] ?? 'Cc', addrs(email.cc)),
            _meta(labels['date'] ?? 'Date', dateStr),
            if (accountName != null && accountName.isNotEmpty)
              _meta(labels['account'] ?? 'Account', accountName),
            if (email.attachments.isNotEmpty)
              _meta(
                labels['attachments'] ?? 'Attachments',
                email.attachments.map((a) => a.name).join(', '),
              ),
            pw.SizedBox(height: 12),
            pw.Divider(color: PdfColors.grey400, height: 1),
            pw.SizedBox(height: 12),
            pw.Text(body, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final safe = _safeFileName(subject);
      final file = File('${dir.path}/$safe.pdf');
      await file.writeAsBytes(await doc.save());
      AppLogger.info('Email exported to PDF: ${file.path}');
      return file.path;
    } catch (e, st) {
      AppLogger.error('Не удалось экспортировать письмо в PDF', e, st);
      return null;
    }
  }

  /// Экспорт ЦЕПОЧКИ переписки в один PDF.
  ///
  /// Для делопроизводства нужна вся переписка по вопросу, а не отдельное
  /// письмо: сохранять их по одному и потом склеивать — лишняя работа.
  ///
  /// Письма идут в хронологическом порядке (от старых к новым), каждое со
  /// своей шапкой и разделителем. Нумерация страниц сквозная.
  static Future<String?> exportThread(
    List<EmailModel> thread, {
    required Map<String, String> labels,
    String? accountName,
  }) async {
    if (thread.isEmpty) return null;
    try {
      await _ensureFonts();
      final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);
      final doc = pw.Document(theme: theme);

      final sorted = [...thread]
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      final subject = sorted.first.subject.trim().isEmpty
          ? (labels['noSubject'] ?? '(no subject)')
          : sorted.first.subject.trim();

      String addr(EmailAddress a) =>
          (a.displayName != null && a.displayName!.isNotEmpty)
              ? '${a.displayName} <${a.email}>'
              : a.email;
      String two(int v) => v.toString().padLeft(2, '0');
      String fmt(DateTime d) {
        final l = d.toLocal();
        return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
          footer: (ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ),
          build: (ctx) => [
            // Шапка всей цепочки: тема и период переписки — по ним документ
            // потом и ищут в деле.
            pw.Text(subject, style: pw.TextStyle(font: _bold, fontSize: 16)),
            pw.SizedBox(height: 4),
            pw.Text(
              '${labels['messages'] ?? 'Messages'}: ${sorted.length} · '
              '${fmt(sorted.first.receivedAt)} — ${fmt(sorted.last.receivedAt)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(color: PdfColors.grey400, height: 1),

            for (var i = 0; i < sorted.length; i++) ...[
              pw.SizedBox(height: 14),
              // Порядковый номер помогает ссылаться на конкретное письмо
              // («см. сообщение 3») при обсуждении бумажной копии.
              pw.Text('#${i + 1} · ${fmt(sorted[i].receivedAt)}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.SizedBox(height: 2),
              _meta(labels['from'] ?? 'From', addr(sorted[i].from)),
              if (sorted[i].to.isNotEmpty)
                _meta(labels['to'] ?? 'To', sorted[i].to.map(addr).join(', ')),
              if (sorted[i].attachments.isNotEmpty)
                _meta(labels['attachments'] ?? 'Attachments',
                    sorted[i].attachments.map((a) => a.name).join(', ')),
              pw.SizedBox(height: 6),
              pw.Text(
                (sorted[i].bodyPlain?.trim().isNotEmpty ?? false)
                    ? sorted[i].bodyPlain!.trim()
                    : htmlToPlainText(sorted[i].bodyHtml ?? ''),
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.grey300, height: 1),
            ],
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_safeFileName(subject)}_thread.pdf');
      await file.writeAsBytes(await doc.save());
      AppLogger.info('Цепочка (${sorted.length}) экспортирована: ${file.path}');
      return file.path;
    } catch (e, st) {
      AppLogger.error('Не удалось экспортировать цепочку в PDF', e, st);
      return null;
    }
  }

  static pw.Widget _meta(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text('$label:',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );

  /// Имя файла из темы письма: убираем недопустимые в ФС символы и ограничиваем
  /// длину (в некоторых ФС лимит 255 байт, кириллица занимает по 2 байта).
  static String _safeFileName(String subject) {
    var s = subject.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    if (s.length > 60) s = s.substring(0, 60);
    if (s.isEmpty) s = 'email';
    return s;
  }
}
