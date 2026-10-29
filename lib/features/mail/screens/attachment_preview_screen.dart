// lib/features/mail/screens/attachment_preview_screen.dart
// Просмотр вложения ВНУТРИ приложения.
//
// Раньше вложение открывалось только внешним приложением (OpenFilex): это уводит
// из почты, требует установленной программы под формат и на корпоративных
// устройствах часто просто не срабатывает. Здесь — быстрый просмотр самых частых
// форматов, а «Открыть во внешнем» остаётся кнопкой.
//
// Поддержка по форматам:
//   изображения — нативно (Image.file + масштабирование щипком);
//   PDF         — Android: системный PdfRenderer (1.8.14, pdf_view.dart);
//                 iPhone и iPad — «Просмотр» iOS, компьютер — своя программа;
//   архивы      — zip (и с паролем), tar, tgz, gz, bz2, xz (1.8.14, zip_view.dart);
//   текст       — чтение файла (с ограничением размера, чтобы не съесть память);
//   письмо .eml — как письмо: заголовки, тело в том же защищённом WebView,
//                 свои вложения (тоже открываются здесь же);
//   остальное   — предложение открыть во внешнем приложении.

import '../../../core/platform/download_saver.dart';
import '../../../core/platform/file_opener.dart';
import '../../../core/utils/text_safe.dart';
import 'dart:convert';
import '../../../core/theme/app_icons.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/tokens.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/security/attachment_safety.dart';
import '../../../core/security/link_opener.dart';
import '../widgets/mail_html_view.dart';
import '../widgets/desktop_mail_body.dart';
import '../widgets/pdf_view.dart';
import '../widgets/zip_view.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../services/mail/pkpass_parser.dart';
import '../../../services/mail/eml_reader.dart';
import '../../../core/security/html_sanitizer.dart';
import '../../../core/security/mail_body_processor.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/ui/section_band.dart';
import '../../../core/theme/mail_page_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import '../../../services/security/smime_service.dart';
import '../../../services/security/smime_mime.dart';
import '../../settings/providers/settings_provider.dart';

enum _Kind { image, pdf, text, pass, mail, zip, other }

/// Одна вкладка предпросмотра: файл + подпись.
class PreviewItem {
  final String filePath;
  final String fileName;
  final int? sizeBytes;

  /// MIME-тип из письма, если известен: вложенное письмо Exchange может
  /// прийти без расширения .eml, но с типом message/rfc822.
  final String? mimeType;
  const PreviewItem({required this.filePath, required this.fileName, this.sizeBytes, this.mimeType});
}

/// Открыть вложение (1.5.10, решение владельца 12.10.2026): во внешнем
/// приложении — с проверкой опасных файлов (AttachmentSafety). Просмотр
/// внутри почты убран: показывал только PDF и картинки, PDF — в плохом
/// качестве, и добавлял лишний экран и лишнее нажатие. В приложении
/// остались только вложенные письма (.eml, message/rfc822, письмо без
/// расширения) и зашифрованные S/MIME (.p7m): сторонние приложения на
/// телефоне их обычно не открывают, а расшифровать может только почта.
Future<void> openAttachment(
  BuildContext context,
  PreviewItem item, {
  String? emailSubject,
  String? accountId,
  String? emailFrom,
  DateTime? emailDate,
}) async {
  if (await AttachmentPreviewScreen.opensInApp(item)) {
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AttachmentPreviewScreen(
        items: [item],
        emailSubject: emailSubject,
        accountId: accountId,
        emailFrom: emailFrom,
        emailDate: emailDate,
      ),
    ));
    return;
  }
  if (!context.mounted) return;
  await AttachmentSafety.openExternally(context, item.filePath, item.fileName);
}

class AttachmentPreviewScreen extends StatefulWidget {
  /// Письмо или S/MIME — открывается в приложении (см. [openAttachment]).
  static Future<bool> opensInApp(PreviewItem item) async {
    final name = item.fileName.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    final ct = item.mimeType?.toLowerCase() ?? '';
    if (ext == 'eml' || ext == 'p7m' || ct.contains('pkcs7-mime') || ct == 'message/rfc822') return true;
    // 1.8.14 (просьба пользователей через владельца 29.10.2026): архивы — в
    // приложении везде; PDF — на Android (системный PdfRenderer); картинки,
    // текст и билеты — на Android и компьютере. iPhone и iPad показывают
    // PDF, картинки, текст и документы Office «Просмотром» iOS — он и так
    // внутри приложения, а билет .pkpass добавляет в Wallet.
    if (PackedArchive.kindOf(name) != null) return true;
    final ios = !kIsWeb && Platform.isIOS;
    if (ext == 'pdf') return NativePdf.supported;
    if (!ios && (_imageExt.contains(ext) || _textExt.contains(ext) || ext == 'pkpass')) return true;
    // Exchange отдаёт вложенное письмо и без расширения — по началу файла.
    if (ext.isEmpty || ext == 'dat' || ext == 'bin') {
      try {
        final head = <int>[];
        await for (final chunk in File(item.filePath).openRead(0, 4096)) {
          head.addAll(chunk);
        }
        return EmlReader.looksLikeEml(Uint8List.fromList(head));
      } catch (_) {
        return false;
      }
    }
    return false;
  }


  static const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _textExt = {'txt', 'log', 'csv', 'json', 'xml', 'md', 'yaml', 'yml', 'ini'};

  /// Все вложения письма — чтобы листать между ними, не возвращаясь назад.
  final List<PreviewItem> items;

  /// С какого начать (тапнутое вложение).
  final int initialIndex;

  /// Тема письма — подпись первой вкладки.
  final String? emailSubject;

  /// HTML письма. Если задан — первой вкладкой идёт само письмо: читать и
  /// листать документы можно в одном месте, не выходя назад.
  final String? emailHtml;

  /// Ящик письма — чтобы расшифровать smime.p7m своим сертификатом.
  final String? accountId;

  /// Отправитель и дата письма — для шапки расшифрованного письма (Outlook
  /// шифрует только тело: тема и адреса остаются снаружи).
  final String? emailFrom;
  final DateTime? emailDate;

  const AttachmentPreviewScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.emailSubject,
    this.emailHtml,
    this.accountId,
    this.emailFrom,
    this.emailDate,
  });

  @override
  State<AttachmentPreviewScreen> createState() => _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final PageController _pages;

  /// Ресурсы на вкладку — грузим лениво, только когда вкладку открыли.
  final Map<int, String> _texts = {};
  final Map<int, PkPass> _passes = {};
  final Map<int, EmlMessage> _mails = {};

  /// Итог S/MIME (подпись, расшифровка) для вкладки письма.
  final Map<int, SmimeOpenResult> _smime = {};
  final Map<int, MailHtmlDocument> _mailDocs = {};

  /// Документ вкладки «Письмо» — один раз (1.5.9): раньше собирался в
  /// каждой перестройке экрана (разбор всего HTML на главном изоляте) и
  /// каждый раз был новым объектом.
  MailHtmlDocument? _emailDoc;
  final Map<int, String> _mailHtml = {};

  /// Вложения без расширения, которые по содержимому оказались письмами.
  final Set<int> _sniffedMail = {};
  final Map<int, String> _errors = {};

  /// Ошибки, которые показываются как есть (понятная причина).
  final Set<int> _plainErrors = {};
  final Set<int> _loaded = {};

  /// Вкладки, которые ещё загружаются (в том числе проверка «не письмо ли»).
  final Set<int> _pending = {};

  static const _maxTextBytes = 512 * 1024;

  /// Есть ли вкладка письма и на сколько из-за неё смещены вложения.
  bool get _hasEmailTab => widget.emailHtml != null;
  int get _offset => _hasEmailTab ? 1 : 0;
  int get _tabCount => widget.items.length + _offset;

  /// Индекс вложения по индексу вкладки (для вкладки письма — null).
  int? _attIndex(int tab) {
    final i = tab - _offset;
    return (i >= 0 && i < widget.items.length) ? i : null;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: (widget.initialIndex + _offset).clamp(0, _tabCount - 1),
    );
    _pages = PageController(initialPage: _tabs.index);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      if (_pages.hasClients && _pages.page?.round() != _tabs.index) {
        _pages.animateToPage(_tabs.index,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
      final i = _attIndex(_tabs.index);
      if (i != null) _ensureLoaded(i);
      setState(() {});
    });
    final start = _attIndex(_tabs.index);
    if (start != null) _ensureLoaded(start);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _pages.dispose();
    super.dispose();
  }

  _Kind _kindOf(int i) {
    final name = widget.items[i].fileName;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (AttachmentPreviewScreen._imageExt.contains(ext)) return _Kind.image;
    if (ext == 'pdf') return _Kind.pdf;
    if (PackedArchive.kindOf(name) != null) return _Kind.zip;
    if (ext == 'pkpass') return _Kind.pass;
    // Письмо — письмом, а не текстом MIME (раньше .eml показывался сырым:
    // заголовки Received, «=?koi8-r?…», quoted-printable).
    if (ext == 'eml' ||
        ext == 'p7m' ||
        (widget.items[i].mimeType?.toLowerCase().contains('pkcs7-mime') ?? false) ||
        widget.items[i].mimeType?.toLowerCase() == 'message/rfc822' ||
        _sniffedMail.contains(i)) {
      return _Kind.mail;
    }
    if (AttachmentPreviewScreen._textExt.contains(ext)) return _Kind.text;
    return _Kind.other;
  }

  Future<void> _ensureLoaded(int i) async {
    if (_loaded.contains(i)) return;
    _loaded.add(i);
    _pending.add(i);
    final item = widget.items[i];
    try {
      switch (_kindOf(i)) {
        case _Kind.pdf:
        case _Kind.zip:
          break;
        case _Kind.text:
          final f = File(item.filePath);
          final len = await f.length();
          final raw = len > _maxTextBytes
              ? await f
                  .openRead(0, _maxTextBytes)
                  .transform(const Utf8Decoder(allowMalformed: true))
                  .join()
              : await f.readAsString();
          _texts[i] = len > _maxTextBytes ? '$raw\n\n…' : raw;
          break;
        case _Kind.pass:
          final bytes = await File(item.filePath).readAsBytes();
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          final pass = PkPassParser.parse(bytes, lang: l10n.localeCode);
          if (pass == null) {
            _errors[i] = l10n.tr('fileDamaged');
          } else {
            _passes[i] = pass;
          }
          break;
        case _Kind.mail:
          await _loadMail(i);
          break;
        case _Kind.other:
          // Вложенное письмо без расширения (так его отдаёт Exchange) —
          // узнаём по заголовкам в начале файла.
          final file = File(item.filePath);
          final head = await file.openRead(0, 4096).fold<List<int>>(<int>[], (a, b) => a..addAll(b));
          if (EmlReader.looksLikeEml(Uint8List.fromList(head))) {
            _sniffedMail.add(i);
            await _loadMail(i);
          }
          break;
        case _Kind.image:
          break;
      }
    } catch (e) {
      _errors[i] = e.toString();
    }
    _pending.remove(i);
    if (mounted) setState(() {});
  }

  /// Разобрать письмо и подготовить тело к показу — вне UI-изолята, если
  /// письмо крупное.
  Future<void> _loadMail(int i) async {
    var bytes = await File(widget.items[i].filePath).readAsBytes();
    // S/MIME: зашифрованное (smime.p7m) или подписанное письмо — расшифровать
    // своим сертификатом и проверить подпись, показать то, что внутри.
    final item = widget.items[i];
    final isP7m = item.fileName.toLowerCase().endsWith('.p7m') ||
        (item.mimeType?.toLowerCase().contains('pkcs7-mime') ?? false);
    final head = latin1.decode(bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes, allowInvalid: true).toLowerCase();
    if (isP7m || head.contains('application/pkcs7') || head.contains('application/x-pkcs7')) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final svc = ProviderScope.containerOf(context, listen: false).read(smimeServiceProvider);
      final r = await svc.open(widget.accountId ?? '', bytes, p7m: isP7m);
      if (r.error == 'needKey' || r.error == 'notForMe' || (r.error != null && !r.decrypted && r.signature == null)) {
        _errors[i] = switch (r.error) {
          'needKey' => l10n.tr('smimeNeedKey'),
          'notForMe' => l10n.tr('smimeNotForMe'),
          _ => l10n.tr('smimeOpenFailed').replaceAll('{e}', '${r.error}'),
        };
        return;
      }
      _smime[i] = r;
      bytes = SmimeMime.asMessage(r.entity,
          subject: widget.emailSubject, from: widget.emailFrom, date: widget.emailDate);
    }
    final m = await EmlReader.parseAsync(bytes);
    String? html;
    if ((m.html ?? '').trim().isNotEmpty) {
      // Стили письма — и на компьютере (1.8.14): по ним показ виджетами
      // решает, что скрыто и простое ли письмо.
      html = await MailBodyProcessor.heavy(m.html!, HtmlSanitizer.sanitizeKeepingStyles);
    } else if ((m.plain ?? '').trim().isNotEmpty) {
      html = '<pre style="white-space:pre-wrap;word-wrap:break-word;font-family:inherit;margin:0">'
          '${const HtmlEscape(HtmlEscapeMode.element).convert(m.plain!)}</pre>';
    }
    if (html != null) {
      _mailHtml[i] = html;
      if (mailWebViewSupported) {
        _mailDocs[i] = await MailHtmlDocument.buildAsync(html,
            allowRemoteImages: false, inlineImages: m.inlineImages);
      }
    }
    _mails[i] = m;
  }

  IconData _iconOf(int i) {
    switch (_kindOf(i)) {
      case _Kind.image:
        return AppIcons.image;
      case _Kind.pdf:
        return AppIcons.picture_as_pdf;
      case _Kind.zip:
        return AppIcons.folder_zip;
      case _Kind.text:
        return AppIcons.description;
      case _Kind.pass:
        return AppIcons.confirmation_number;
      case _Kind.mail:
        return AppIcons.mail;
      case _Kind.other:
        return AppIcons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final attIdx = _attIndex(_tabs.index);
    final current = attIdx != null ? widget.items[attIdx] : null;

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        // Вкладки сверху: письмо и его вложения — один уровень навигации.
        // Так не путаешь «назад к письму» и «закрыть просмотр»: назад — всегда
        // выход из просмотра, а переход к письму — вкладка.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(current?.fileName ?? (widget.emailSubject ?? (l10n.tr('emailWord'))),
                overflow: TextOverflow.ellipsis),
            if (current?.sizeBytes != null)
              Text(AppDateFormat.bytes(context, current!.sizeBytes!),
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          // На вкладке письма файловых действий нет.
          if (current != null) ...[
            IconButton(
              icon: const Icon(AppIcons.save_alt),
              tooltip: l10n.tr('save'),
              onPressed: () => _saveOne(current),
            ),
            IconButton(
              icon: const Icon(AppIcons.open_in_new),
              tooltip: l10n.tr('openExternally'),
              onPressed: () => AttachmentSafety.openExternally(context, current.filePath, current.fileName),
            ),
          ],
        ],
        bottom: _tabCount < 2
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  if (_hasEmailTab)
                    Tab(
                      icon: const Icon(AppIcons.mail, size: 18),
                      text: l10n.tr('emailWord'),
                    ),
                  for (var i = 0; i < widget.items.length; i++)
                    Tab(
                      icon: Icon(_iconOf(i), size: 18),
                      text: widget.items[i].fileName.length > 18
                          ? '${cutSafe(widget.items[i].fileName, 16)}…'
                          : widget.items[i].fileName,
                    ),
                ],
              ),
      )),
      // Вырез камеры сбоку в альбомной ориентации (1.5.10).
      body: SafeArea(top: false, bottom: false, child: PageView.builder(
        controller: _pages,
        itemCount: _tabCount,
        onPageChanged: (tab) {
          _tabs.animateTo(tab);
          final i = _attIndex(tab);
          if (i != null) _ensureLoaded(i);
          setState(() {});
        },
        itemBuilder: (_, tab) {
          final i = _attIndex(tab);
          if (i == null) return _emailPage();
          return _page(i, ru);
        },
      )),
    );
  }

  /// Размер шрифта письма из настроек (как на экране письма) — раньше письмо
  /// во вложении всегда было 100 % (1.5.10).
  double get _fontScale {
    try {
      return ProviderScope.containerOf(context, listen: false).read(settingsProvider).fontScale;
    } catch (_) {
      return 1.0;
    }
  }

  /// Вкладка письма: тот же HTML, что и в карточке — в том же защищённом
  /// WebView (без JavaScript, без сети, ссылки через проверку домена).
  Widget _emailPage() {
    final html = widget.emailHtml!;
    if (mailWebViewSupported) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(Space.l),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: MailHtmlView(
            key: ValueKey('mail_${Theme.of(context).brightness.name}'),
            document: _emailDoc ??= MailHtmlDocument.build(html, allowRemoteImages: false),
            allowRemoteImages: false,
            textScale: _fontScale,
            pageColor: mailPageColor(Theme.of(context)),
            dark: Theme.of(context).brightness == Brightness.dark,
            onLink: (url, text) => LinkOpener.open(context, url, linkText: text),
          ),
        ),
      );
    }
    // Компьютер (1.8.14): виджетами, как в экране письма.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.l),
      child: DesktopMailBody(
        html: html,
        textScale: _fontScale,
        onLink: (url, text) => LinkOpener.open(context, url, linkText: text),
      ),
    );
  }

  /// Сохранить файл. Через системный лист «Поделиться»: он даёт «Сохранить в
  /// Файлы»/«Загрузки» на всех платформах и не требует прав на запись в чужие
  /// каталоги — в отличие от самостоятельного выбора папки.
  Future<void> _saveOne(PreviewItem item) async {
    // Android и компьютер — сразу в «Загрузки» (1.6.33).
    if (DownloadSaver.supported) {
      await DownloadSaver.saveWithFeedback(context, [(path: item.filePath, name: item.fileName)]);
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(
          files: [XFile(await FileOpener.namedCopy(item.filePath, item.fileName), name: item.fileName)],
          subject: item.fileName));
    } catch (e) {
      if (!mounted) return;
      showInlineError(AppLocalizations.of(context).tr('cannotOpenFile').replaceAll('{e}', '$e'));
    }
  }

  Widget _page(int i, bool ru) {
    final l10n = AppLocalizations.of(context);
    if (_errors.containsKey(i)) {
      // Понятная причина (PDF с паролем, архив не читается) — как есть.
      return _fallback(
          i, ru, _plainErrors.contains(i) ? '${_errors[i]}' : l10n.tr('cannotOpenFile').replaceAll('{e}', '${_errors[i]}'));
    }
    switch (_kindOf(i)) {
      case _Kind.image:
        return InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.file(
              File(widget.items[i].filePath),
              errorBuilder: (_, e, __) =>
                  _fallback(i, ru, l10n.tr('fileDamaged')),
            ),
          ),
        );

      case _Kind.pdf:
        // 12.10.2026 PDF ушёл во внешнее приложение: встроенный просмотр
        // (pdfx) был хуже системного. С 1.8.14 на Android — свой, на
        // системном PdfRenderer (pdf_view.dart): резкость при увеличении,
        // номер страницы; другое приложение — кнопкой вверху.
        if (!NativePdf.supported) return _fallback(i, ru, l10n.tr('previewUnsupported'));
        return PdfView(
          path: widget.items[i].filePath,
          onUnsupported: (protected, e) => setState(() {
            _errors[i] = protected ? l10n.tr('pdfProtected') : l10n.tr('fileDamaged');
            _plainErrors.add(i);
          }),
        );

      case _Kind.zip:
        return ZipView(
          path: widget.items[i].filePath,
          fileName: widget.items[i].fileName,
          onOpen: (path, name) => openAttachment(context, PreviewItem(filePath: path, fileName: name),
              emailSubject: widget.emailSubject, accountId: widget.accountId),
          onFailed: (e) => setState(() {
            _errors[i] = l10n.tr('zipCannotRead');
            _plainErrors.add(i);
          }),
        );

      case _Kind.text:
        final t = _texts[i];
        if (t == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Space.l),
          child: SelectableText(t,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        );

      case _Kind.pass:
        final pass = _passes[i];
        if (pass == null) return const Center(child: CircularProgressIndicator());
        return _passView(pass, l10n);

      case _Kind.mail:
        final m = _mails[i];
        if (m == null) return const Center(child: CircularProgressIndicator());
        return _mailView(i, m, l10n);

      case _Kind.other:
        // Пока проверяем, не письмо ли это, — индикатор, а не «не умею».
        if (!_loaded.contains(i) || _pending.contains(i)) {
          return const Center(child: CircularProgressIndicator());
        }
        return _fallback(
            i,
            ru,
            l10n.tr('previewUnsupported'));
    }
  }

  /// Билет .pkpass карточкой: цвета билета, организация, лицевые поля
  /// сеткой, код (текстом — для сверки с кассой), обратная сторона ниже.
  Widget _passView(PkPass p, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final bg = p.background != null ? Color(p.background!) : theme.colorScheme.surfaceContainerHigh;
    final fg = p.foreground != null ? Color(p.foreground!) : theme.colorScheme.onSurface;
    final lc = p.labelColor != null ? Color(p.labelColor!) : fg.withValues(alpha: 0.7);
    Widget field(PkPassField f, {bool big = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (f.label.isNotEmpty)
              Text(f.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: lc, letterSpacing: 0.6)),
            Text(f.value,
                style: (big ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)
                    ?.copyWith(color: fg, fontWeight: big ? FontWeight.w700 : FontWeight.w600)),
          ],
        );
    Widget row(List<PkPassField> fs, {bool big = false}) => fs.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Wrap(spacing: Space.xl, runSpacing: Space.s, children: [for (final f in fs) field(f, big: big)]),
          );
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(color: bg, borderRadius: Radii.cardAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (p.logo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(Space.xs),
                  child: Image.memory(p.logo!, height: 32, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
                const SizedBox(width: Space.m),
              ],
              Expanded(
                child: Text(p.logoText.isNotEmpty ? p.logoText : p.organization,
                    style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
              ),
              for (final f in p.header) Padding(padding: const EdgeInsets.only(left: Space.m), child: field(f)),
            ]),
            row(p.primary, big: true),
            row(p.secondary),
            row(p.auxiliary),
            if ((p.barcodeMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: Space.l),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Space.s)),
                child: Column(children: [
                  SelectableText(p.barcodeAltText?.isNotEmpty == true ? p.barcodeAltText! : p.barcodeMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.black, fontFamily: 'monospace')),
                  if ((p.barcodeFormat ?? '').isNotEmpty)
                    Text(p.barcodeFormat!, style: theme.textTheme.labelSmall?.copyWith(color: Colors.black54)),
                ]),
              ),
            ],
          ]),
        ),
        if (p.description.isNotEmpty || p.relevantDate != null) ...[
          const SizedBox(height: Space.m),
          Text(
            [
              if (p.description.isNotEmpty) p.description,
              if (p.relevantDate != null) AppDateFormat.dateTime(context, p.relevantDate!),
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context)),
          ),
        ],
        for (final f in p.back) ...[
          const SizedBox(height: Space.m),
          if (f.label.isNotEmpty) Text(f.label, style: theme.textTheme.labelLarge),
          SelectableText(f.value, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Space.l),
        Text(l10n.tr('passNote'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
      ],
    );
  }

  /// Вложенное письмо: заголовки карточкой, тело — как в обычном письме,
  /// ниже — его собственные вложения.
  /// Строка S/MIME над письмом: расшифровано, кем подписано, верна ли подпись.
  Widget _smimeBanner(SmimeOpenResult r, EmlMessage m, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final s = r.signature;
    final lines = <String>[];
    var bad = false;
    if (r.decrypted) lines.add(l10n.tr('smimeEncrypted'));
    if (s != null) {
      final who = s.signer == null
          ? '?'
          : [s.signer!.commonName, if (s.signer!.email != null) '<${s.signer!.email}>'].join(' ');
      lines.add(l10n.tr('smimeSignedBy').replaceAll('{name}', who));
      if (s.valid) {
        lines.add(l10n.tr('smimeSigOk'));
        final at = s.signingTime ?? m.date ?? DateTime.now();
        if (s.signer != null && !s.signer!.isValidAt(at)) {
          bad = true;
          lines.add(l10n.tr('smimeSigExpired'));
        }
        final from = m.from.isNotEmpty ? m.from.first.email : (widget.emailFrom ?? '');
        final fromEmail = RegExp(r'[^<\s]+@[^>\s]+').firstMatch(from)?.group(0);
        if (s.signer != null && fromEmail != null && s.signer!.emails.isNotEmpty && !s.signer!.hasEmail(fromEmail)) {
          bad = true;
          lines.add(l10n.tr('smimeSigNotSelf').replaceAll('{email}', s.signer!.emails.join(', ')));
        }
        if (s.signer != null && s.signer!.issuerName.isNotEmpty) {
          lines.add(l10n.tr('smimeSigIssuerNote').replaceAll('{issuer}', s.signer!.issuerName));
        }
      } else {
        bad = s.error == 'content changed' || s.error == 'bad signature';
        lines.add(bad ? l10n.tr('smimeSigBad') : l10n.tr('smimeSigUnknown').replaceAll('{reason}', s.error ?? '?'));
      }
    }
    final c = bad ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: Radii.cardAll,
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(bad ? AppIcons.gpp_bad : AppIcons.verified_user, size: Sizes.iconRow, color: c),
        const SizedBox(width: Space.s),
        Expanded(child: Text(lines.join('\n'), style: theme.textTheme.bodySmall)),
      ]),
    );
  }

  Widget _mailView(int i, EmlMessage m, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    // От, кому, копия, дата — значками, как в шапке письма (1.5.9).
    Widget field(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: label,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: Space.s),
                  child: Icon(icon, size: 18, color: muted, semanticLabel: label),
                ),
              ),
              Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    final html = _mailHtml[i];
    final doc = _mailDocs[i];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Space.m),
      children: [
        if (_smime[i] != null) _smimeBanner(_smime[i]!, m, l10n),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l),
          child: Container(
            padding: const EdgeInsets.all(Space.m),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: Radii.cardAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.subject.isEmpty ? l10n.tr('noSubject') : m.subject,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Space.xs),
                if (m.from.isNotEmpty) field(AppIcons.person, l10n.tr('from'), m.from.map((a) => a.label).join(', ')),
                if (m.to.isNotEmpty) field(AppIcons.mailTo, l10n.tr('to'), m.to.map((a) => a.label).join(', ')),
                if (m.cc.isNotEmpty) field(AppIcons.mailCc, l10n.tr('cc'), m.cc.map((a) => a.label).join(', ')),
                if (m.date != null) field(AppIcons.schedule, l10n.tr('date'), AppDateFormat.dateTime(context, m.date!)),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        if (html == null)
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(l10n.tr('emlNoText'), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          )
        else if (doc != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MailHtmlView(
                key: ValueKey('eml_${i}_${theme.brightness.name}'),
                document: doc,
                allowRemoteImages: false,
                textScale: _fontScale,
                pageColor: mailPageColor(theme),
                dark: theme.brightness == Brightness.dark,
                onLink: (url, text) => LinkOpener.open(context, url, linkText: text),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: DesktopMailBody(
              html: html,
              images: m.inlineImages,
              textScale: _fontScale,
              onLink: (url, text) => LinkOpener.open(context, url, linkText: text),
            ),
          ),
        if (m.attachments.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          SectionBand(title: l10n.tr('attachments'), count: m.attachments.length),
          for (var k = 0; k < m.attachments.length; k++)
            ListTile(
              leading: Icon(_iconForName(m.attachments[k].name, m.attachments[k].contentType)),
              title: Text(m.attachments[k].name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(AppDateFormat.bytes(context, m.attachments[k].bytes.length)),
              onTap: () => _openInner(i, m, k),
            ),
        ],
      ],
    );
  }

  IconData _iconForName(String name, String contentType) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final ct = contentType.toLowerCase();
    if (ext == 'eml' || ct == 'message/rfc822') return AppIcons.mail;
    if (ext == 'pdf') return AppIcons.picture_as_pdf;
    if (ct.startsWith('image/')) return AppIcons.image;
    return AppIcons.insert_drive_file;
  }

  /// Открыть вложение вложенного письма тем же просмотром: файлы пишутся во
  /// временный каталог (их можно сохранить или открыть внешним приложением,
  /// как любое вложение), письмо внутри письма тоже открывается письмом.
  Future<void> _openInner(int i, EmlMessage m, int index) async {
    final l10n = AppLocalizations.of(context);
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/eml_view/${widget.items[i].filePath.hashCode.toUnsigned(32)}');
      await dir.create(recursive: true);
      final items = <PreviewItem>[];
      for (var k = 0; k < m.attachments.length; k++) {
        final a = m.attachments[k];
        final f = File('${dir.path}/${k}_${a.name}');
        if (!await f.exists() || await f.length() != a.bytes.length) {
          await f.writeAsBytes(a.bytes, flush: true);
        }
        items.add(PreviewItem(
          filePath: f.path,
          fileName: a.name,
          sizeBytes: a.bytes.length,
          mimeType: a.contentType,
        ));
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AttachmentPreviewScreen(
          items: items,
          initialIndex: index,
          emailSubject: m.subject.isEmpty ? l10n.tr('emlAttachedMessage') : m.subject,
        ),
      ));
    } catch (e) {
      showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', '$e'));
    }
  }

  Widget _fallback(int i, bool ru, String message) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.insert_drive_file,
                size: 72,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: Space.l),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(AppIcons.open_in_new),
              label: Text(l10n.tr('openExternallyApp')),
              onPressed: () => AttachmentSafety.openExternally(
                  context, widget.items[i].filePath, widget.items[i].fileName),
            ),
            const SizedBox(height: Space.s),
            Text(
              l10n.tr('fileAlreadyDownloaded'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
}
