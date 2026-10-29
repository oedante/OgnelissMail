// lib/features/compose/screens/compose_screen.dart
import '../widgets/mail_tips_strip.dart';
import '../../../core/platform/file_pick.dart' show ChosenFile, FilePick;
import '../../../core/utils/app_date_format.dart';
import '../../../core/utils/send_later_presets.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../../widgets/common/peek_card.dart' show PeekAction, peekAnchorOf, showHoldMenu, showPeekCard;
import '../../../widgets/common/quick_long_press.dart' show HoldPointer, QuickLongPress;
import '../../contacts/person_names.dart' show personNamesProvider, normalizePersonName, bestPersonName;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/wheel_pickers.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle;
import '../../../core/utils/text_safe.dart';
import '../../../core/utils/subject_prefix.dart';
import '../../../core/utils/address_input.dart';
import '../../../core/utils/mail_domains.dart' show sameOrgDomain;
import '../../../widgets/common/person_photo.dart';
import '../../../services/mail/alias_service.dart' show aliasServiceProvider;
import '../../../core/theme/app_icons.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../mail/providers/account_look.dart' show onAccountColor;
import '../../../core/security/html_sanitizer.dart';
import '../../../core/security/mail_body_processor.dart';
import '../widgets/mail_editor.dart';
import '../../mail/widgets/mail_html_view.dart';
import '../../../core/security/link_opener.dart';
import 'dart:io';
import '../../../services/security/smime_service.dart';
import '../../../services/security/mail_classification.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../services/mail/reply_builder.dart';
import '../../../core/utils/person_names.dart';
import '../../../services/contacts/person_name_directory.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
// Создание/ответ/пересылка письма:
// - DLP-проверка перед отправкой (в Isolate)
// - Автодополнение контактов из GAL (debounce)
// - Приветствие по времени суток с именем/отчеством
// - Автовставка подписи (из настроек аккаунта)
// - Шаблоны быстрых ответов (локализованные)
// - Прикрепление файлов + OCR-сканирование
// - SafeAsync для всех операций

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/mail/control_service.dart';
import '../../../core/theme/mail_page_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/greeting_helper.dart';
import '../../../services/mail/greeting_mode.dart';
import '../../../services/mail/greeting_history.dart';
import '../../../l10n/strings_store.dart' show StringsStore;
import '../../../core/utils/async_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/contact_model.dart';
import '../../../services/mail/offline_send_service.dart';
import '../../../services/mail/smart_compose_service.dart';
import '../../settings/providers/feature_flags_provider.dart';
import '../../../services/security/dlp_service.dart';
import '../../settings/screens/dlp_settings_screen.dart' show dlpSettingsProvider;
import '../../../services/mail/attachment_hint_service.dart';
import '../../../services/mail/paste_cleaner.dart';
import '../../../widgets/common/shared_mailbox_badge.dart';
import '../../../widgets/common/dlp_warning_dialog.dart';
import '../../mail/providers/mail_providers.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/attachment_limit_provider.dart';
import '../providers/templates_provider.dart';
import 'package:flutter/foundation.dart';
import '../providers/distribution_groups_provider.dart';
import '../../../services/mail/signature_service.dart';
import '../../../services/mail/draft_sync_service.dart';
import '../../../services/mail/reply_drafts.dart';
import '../../../services/mail/compose_style_service.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../data/database/app_database.dart' show Email, EmailsCompanion;
import '../../../data/models/folder_model.dart' show FolderType;
import '../../../data/providers/database_provider.dart';
import 'package:drift/drift.dart' show Variable, Value;
import 'dart:convert';
import '../../../services/mail/draft_autosave_service.dart';
import '../../../services/mail/draft_files.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/mail/email_actions_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../widgets/people_picker_sheet.dart';
import '../widgets/image_size_sheet.dart';
import '../../../core/utils/format_bytes.dart';
import '../../../widgets/ui/help_hint.dart' show HelpButton;
import '../../../widgets/ui/app_menu_button.dart';
import '../../../services/mail/image_shrink.dart';
import '../../../services/mail/image_edit.dart' show ImageEdit;
import '../../mail/screens/attachment_preview_screen.dart' show PreviewItem, openAttachment;
import 'image_edit_screen.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/ogneliss_look.dart';


class ComposeScreen extends ConsumerStatefulWidget {
  final String? replyToId;
  final String? forwardFromId;
  final String? draftId;
  final String? accountId;
  final bool replyAll;
  final String? sharedBody;
  /// Быстрый ответ: текст между приветствием и подписью (вместо пустой
  /// средней строки), курсор — после него.
  final String? quickText;

  /// Предзаполненный адресат (например, «Написать» из карточки контакта).
  final String? to;

  /// Копия и скрытая копия (ссылка mailto из другого приложения).
  final String? cc;
  final String? bcc;

  final List<String> sharedAttachments;

  /// Предзаполненная тема (например, «Журнал → Отправить в поддержку»).
  final String? sharedSubject;

  const ComposeScreen({
    super.key,
    this.replyToId,
    this.forwardFromId,
    this.draftId,
    this.accountId,
    this.replyAll = false,
    this.sharedBody,
    this.quickText,
    this.to,
    this.cc,
    this.bcc,
    this.sharedAttachments = const [],
    this.sharedSubject,
  });

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen>
    with SafeAsyncState<ComposeScreen> {
  /// Message-ID письма, на которое отвечаем: уходит в In-Reply-To/References,
  /// чтобы ответ встал в ту же цепочку у получателя (Outlook, Gmail,
  /// Thunderbird). Раньше заголовки не передавались, и каждый ответ из
  /// приложения начинал у адресата новую переписку.
  String? _inReplyTo;

  final _toController = TextEditingController();
  String? _toError;
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final TextEditingController _plainController = TextEditingController(); // фолбэк (Linux/без WebView)
  final FocusNode _bodyFocusNode = FocusNode();
  // HTML-редактор (HugeRTE во встроенном браузере): таблицы, списки, вставка
  // с оформлением. Вызовы до загрузки копятся в контроллере.
  final MailEditorController _editor = MailEditorController();
  String _lastHtml = '';
  /// Редактор не загрузился — работаем в простом текстовом поле.
  bool _editorFailed = false;

  // ── Цитата исходного письма (ответ/пересылка) ──
  // Как в Outlook Mobile: в редакторе — только новый текст, исходное письмо —
  // под ним, только для чтения (тот же безопасный просмотр, что при чтении).
  // При отправке цитата добавляется к тексту; у ActiveSync ответ и пересылку
  // собирает сам сервер (SmartReply/SmartForward) — вёрстка оригинала
  // не искажается, вложения не скачиваются.
  /// Шапка Outlook и исходное письмо для отправки. null — цитаты нет, она убрана или
  /// перенесена в редактор.
  String? _quoteHtml;
  /// Шапка цитаты («От / Отправлено / Кому / Тема» под линией) — отдельно:
  /// ответ и пересылка ActiveSync силами сервера получают её в конце текста,
  /// исходное письмо сервер допишет сам (27.10.2026).
  String? _quoteHeader;
  MailHtmlDocument? _quoteDoc;
  bool _quoteExpanded = false;
  /// Пользователь правил или убрал цитату — серверный ответ/пересылка
  /// (которые всегда добавляют оригинал) не используются.
  bool _quoteChanged = false;

  /// Получатели ответа, как их предложили при открытии («кому|копия»).
  /// Exchange (EWS) при серверном ответе выбирает получателей сам —
  /// серверный ответ возможен, только пока их не меняли.
  String? _replyRecipientsAtStart;
  /// У исходного письма есть Reply-To или оно — своё (из «Отправленных»):
  /// тут Exchange выбрал бы получателей иначе, чем экран.
  bool _replySpecialCase = false;

  String _recipientsKey() {
    String k(List<EmailAddress> l) => (l.map((a) => a.email.trim().toLowerCase()).toList()..sort()).join(',');
    return '${k(_toRecipients)}|${k(_ccRecipients)}|${k(_bccRecipients)}';
  }

  /// Тело для отправки: новый текст и цитата.
  String _withQuote(String editorHtml) {
    // Служебные метки приветствия и подписи получателю не нужны. Текст — в
    // стиле аккаунта (шрифт и размер), как его видел автор при наборе.
    final stripped = editorHtml.replaceAll(RegExp(r'\s+id="ogn-(greeting|signature)"'), '');
    final body = '<div style="${_style.css.replaceAll('"', "'")}">$stripped</div>';
    // Пустая строка между подписью и линией цитаты, как в Outlook: с одним
    // <br> исходное письмо начиналось вплотную под подписью (27.10.2026).
    return _quoteHtml == null ? body : '$body<div><br></div>${_quoteHtml!}';
  }

  /// «Изменить цитату»: перенести её в редактор.
  void _editQuote() {
    final q = _quoteHtml;
    if (q == null) return;
    _appendBodyHtml('<br>$q');
    setState(() {
      _quoteHtml = null;
      _quoteDoc = null;
      _quoteChanged = true;
    });
    _markDraftChanged();
  }

  void _removeQuote() {
    setState(() {
      _quoteHtml = null;
      _quoteDoc = null;
      _quoteChanged = true;
    });
    _markDraftChanged();
  }
  /// Подсказки Smart Compose для текущего ввода (показываются чипами над вложениями).
  List<SmartComposeSuggestion> _composeSuggestions = const [];
  // HTML-редактор — на Android, iOS, macOS и Windows (WebView2). На Linux,
  // в вебе и при сбое загрузки — простое текстовое поле.
  bool get _useHtmlEditor => mailEditorSupported && !_editorFailed;

  // Тело как обычный текст и как HTML.
  String get _bodyPlain => _useHtmlEditor ? _htmlToPlain(_lastHtml) : _plainController.text.trimRight();

  /// Только то, что человек написал сам: без приветствия и подписи. По нему
  /// работают подсказки Smart Compose и их обучение. Раньше бралось всё тело:
  /// «последней строкой» оказывалась строка подписи («E-mail: …»), обучение
  /// запоминало подпись, и чип «✦ E-mail: …» висел в каждом новом письме.
  String get _authoredPlain {
    if (_useHtmlEditor) {
      var html = _lastHtml;
      final sig = html.indexOf('id="ogn-signature"');
      if (sig >= 0) {
        final open = html.lastIndexOf('<div', sig);
        html = html.substring(0, open >= 0 ? open : sig);
      }
      html = html.replaceFirst(RegExp(r'<div id="ogn-greeting">[\s\S]*?</div>'), '');
      return html
          .replaceAll(RegExp(r'<br\s*/?>|</(div|p)>'), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&nbsp;', ' ')
          .trim();
    }
    var text = _plainController.text;
    final sigPlain = _signatureFor(_fromAccount)?.plain.trim();
    if (sigPlain != null && sigPlain.isNotEmpty) {
      final i = text.lastIndexOf(sigPlain);
      if (i >= 0) text = text.substring(0, i);
    }
    final g = _autoGreeting;
    if (g != null && g.isNotEmpty && text.trimLeft().startsWith(g)) {
      text = text.trimLeft().substring(g.length);
    }
    return text.trim();
  }

  /// HTML тела (для отправки). Для html-редактора — асинхронно из редактора.
  /// Тело письма в HTML — с очисткой разметки Office.
  ///
  /// Вставка таблицы из Excel или текста из Word приносит служебную разметку
  /// (`mso-*`, `MsoNormal`, условные комментарии). Без очистки письмо весит
  /// в разы больше и по-разному выглядит у получателей.
  Future<String> _getBodyHtmlAsync() async {
    if (_useHtmlEditor) {
      try {
        final raw = await _editor.getHtml();
        if (raw != null && raw.trim().isNotEmpty) {
          // Чистим здесь, а не при вставке: редактор работает в WebView, и
          // перехват буфера обмена там ведёт себя по-разному на Android, iOS
          // и десктопе. Обработка готового HTML одинакова везде.
          final h = PasteCleaner.clean(_fromEditor(raw));
          _lastHtml = h;
          return h;
        }
      } catch (_) {}
      return _lastHtml;
    }
    return _bodyToHtml();
  }
  String _bodyToHtml() {
    // Фолбэк-редактор — простой текст; оборачиваем в HTML (переводы строк → <br>).
    final esc = _plainController.text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    return '<div>$esc</div>';
  }
  /// Всё, что попадает в HTML-редактор, проходит здесь. Строки в редактор
  /// передаются как JSON (MailEditorController), ручное экранирование не нужно.
  ///
  /// Внешние картинки (`src="https://…"`) переименовываются в
  /// `data-ogn-src`: редактор — WebView с JavaScript и сетью, и при нажатии
  /// «Ответить» он загрузил бы трекеры исходного письма, даже если
  /// пользователь не разрешал показ изображений. Обратно — [_fromEditor].
  static String _toEditor(String html) =>
      html.replaceAllMapped(_imgTag, (m) =>
          m.group(0)!.replaceAllMapped(_remoteSrc, (a) => ' data-ogn-src=${a.group(1)}'));

  /// Вернуть адреса внешних картинок перед сохранением и отправкой.
  static String _fromEditor(String html) =>
      html.replaceAll(RegExp(r'\sdata-ogn-src\s*=', caseSensitive: false), ' src=');

  static final _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final _remoteSrc = RegExp(
      r'''\ssrc\s*=\s*("https?:[^"]*"|'https?:[^']*'|https?:[^\s>]+)''',
      caseSensitive: false);

  /// HTML → текст для простого редактора и подписи: строки — по <br> и
  /// концам блоков (абзац, строка таблицы, пункт списка, цитата), сущности —
  /// в символы.
  static String _htmlToPlain(String html) {
    final t = html
        .replaceAll(RegExp(r'<br\s*/?>|<hr[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|tr|li|h[1-6]|blockquote|table|pre)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
          final v = m[1]!;
          final code = v.startsWith('x') || v.startsWith('X') ? int.tryParse(v.substring(1), radix: 16) : int.tryParse(v);
          return code == null || code <= 0 || code > 0x10FFFF ? '' : String.fromCharCode(code);
        })
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  static String _escText(String t) => t
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');

  void _setBodyPlain(String text) {
    if (_useHtmlEditor) {
      final html = '<div>${_escText(text)}</div>';
      _editor.setHtml(_toEditor(html));
      _lastHtml = html;
      return;
    }
    _plainController.text = text;
  }
  void _appendBodyPlain(String text) {
    if (_useHtmlEditor) {
      final html = _escText(text);
      _editor.appendHtml(_toEditor(html));
      _lastHtml += html;
      return;
    }
    _plainController.text += text;
  }
  /// Вставить HTML в тело (для html-редактора). В фолбэке — как текст.
  void _appendBodyHtml(String html) {
    if (_useHtmlEditor) {
      _editor.appendHtml(_toEditor(html));
      _lastHtml += html;
      return;
    }
    // Раньше здесь были свои замены: в цитате оставались «&lt;адрес&gt;»,
    // а «Тема: …» слипалась с первой строкой письма (28.10.2026).
    // Между текстом и цитатой — две пустые строки, сколько бы <br> ни было.
    final add = _htmlToPlain(html);
    final cur = _plainController.text;
    _plainController.text = cur.trim().isEmpty ? add : '${cur.trimRight()}\n\n\n$add';
  }

  /// Вставляет [text] в позицию курсора (или заменяет выделение).
  /// Если курсор не установлен — добавляет в начало тела (перед цитатой/подписью).
  void _insertBodyPlainAtCursor(String text) {
    if (_useHtmlEditor) { _editor.insertHtml(_escText(text)); return; }
    final sel = _plainController.selection;
    final base = _plainController.text;
    if (sel.isValid && sel.start >= 0 && sel.end <= base.length) {
      _plainController.text = base.replaceRange(sel.start, sel.end, text);
      _plainController.selection = TextSelection.collapsed(offset: sel.start + text.length);
    } else {
      _plainController.text = base + text;
    }
  }

  /// Строки «Копия» и «Скрытая» показываются по кнопке или когда в них есть
  /// адресаты. Скрытая копия нужна редко — по умолчанию свёрнута.
  bool _showCc = false;
  bool _showBcc = false;
  /// Строка, из которой несут плашку адресата: остальные строки «Кому»,
  /// «Копия», «Скрытая» подсвечиваются как место, куда её можно опустить.
  List<EmailAddress>? _dragFrom;

  /// Поле адресатов в режиме правки (плашки и ввод). Остальные — одной
  /// строкой («Кузнецов М. Г., Соколов М. В. и ещё 2»): раньше плашки
  /// всех получателей занимали пол-экрана.
  TextEditingController? _editingField;

  /// Курсор в тексте письма (окно редактора): курсор полей шапки скрыт —
  /// фокус Flutter у них остаётся (иначе система спрятала бы клавиатуру
  /// редактора), но мигающих курсоров два не бывает (замечание 13.10.2026).
  bool _caretInBody = false;

  /// Нажатие в текст письма: набранный адрес — плашкой, поле — строкой,
  /// курсор шапки гаснет.
  void _onEditorFocus() {
    if (!mounted) return;
    _watchEditorPosition();
    // Касания текста приходят и тогда, когда курсор уже в нём (27.10.2026):
    // повторно ничего не пересобираем.
    if (_caretInBody &&
        _editingField == null &&
        _toController.text.trim().isEmpty &&
        _ccController.text.trim().isEmpty &&
        _bccController.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _caretInBody = true;
      for (final (c, target) in [
        (_toController, _toRecipients),
        (_ccController, _ccRecipients),
        (_bccController, _bccRecipients),
      ]) {
        _commitPendingRecipient(c, target);
      }
      _editingField = null;
      _contactSuggestions.clear();
      _lastQuery = '';
    });
    _updateGreeting();
    unawaited(_fillNamesFromContacts());
  }

  void _caretToHeader() {
    _editorWatch?.cancel();
    _editorWatch = null;
    if (!_caretInBody) return;
    setState(() => _caretInBody = false);
    // Фокус Flutter у поля темы или адресатов мог и не уходить (касание
    // текста его не снимает): без этого курсор оставался и в тексте письма —
    // курсоров было два (замечание 27.10.2026).
    if (_useHtmlEditor) unawaited(_editor.blur());
  }

  /// Положение окна редактора на экране, пока курсор в тексте: окно
  /// сдвинулось (лист прокрутили, над редактором появилась строка подсказок
  /// Exchange, панель форматирования) — «капля» выделения Android осталась
  /// бы на прежнем месте, и печатать приходилось «не там» (27.10.2026).
  final _editorKey = GlobalKey();
  Timer? _editorWatch;
  Offset? _editorAt;

  void _watchEditorPosition() {
    if (!_useHtmlEditor || _editorWatch != null) return;
    _editorAt = null;
    _editorWatch = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted || !_caretInBody) {
        _editorWatch?.cancel();
        _editorWatch = null;
        return;
      }
      final box = _editorKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final at = box.localToGlobal(Offset.zero);
      final was = _editorAt;
      _editorAt = at;
      if (was != null && (was - at).distance > 1.5) unawaited(_editor.refreshSelection());
    });
  }
  final _subjectFocus = FocusNode();
  final _toFocus = FocusNode();
  final _ccFocus = FocusNode();
  final _bccFocus = FocusNode();

  /// Последнее автоматическое приветствие: обновляется вслед за адресатами,
  /// пока пользователь его не исправил. null — приветствия нет (черновик);
  /// '' — выбрано «Без приветствия».
  String? _autoGreeting;

  /// Приветствие стоит в письме (новое письмо или ответ, у ящика оно
  /// включено): над текстом — кнопка «Приветствие» со всеми вариантами.
  bool _greetingPlaced = false;

  /// Вариант, выбранный кнопкой «Приветствие»; null — по настройке ящика
  /// (в ответе в переписке, где вы уже писали, — короткое).
  GreetingVariant? _greetPick;

  /// Ответ в переписке, где вы уже писали: приветствие короткое — «Имя
  /// Отчество,» / «Коллеги,» (просьба владельца 25.10.2026).
  bool _wroteInThread = false;

  /// Полные имена адресатов (адрес → «Фамилия Имя Отчество»): в карточках
  /// Exchange имя часто «Фамилия, Имя», без отчества. Отчество берём из
  /// других записей того же адреса или из адресной книги организации.
  final Map<String, String> _fullNames = {};
  final Set<String> _fullNameLookups = {};

  /// Состояние письма сразу после заполнения (адресаты ответа, тема,
  /// приветствие, подпись). Совпадает — пользователь ничего не делал:
  /// закрытие не оставляет черновик ни на устройстве, ни на сервере.
  String? _pristineSig;
  String _sig(String rawBody) => [
        for (final a in _toRecipients) a.email,
        '|',
        for (final a in _ccRecipients) a.email,
        '|',
        for (final a in _bccRecipients) a.email,
        '|',
        _subjectController.text.trim(),
        '|',
        _plainText(rawBody),
        '|',
        // Файлы — по именам (1.7.2+111): добавили или убрали файл — письмо
        // изменено. Докачка файла пересылки (плашка → файл) — нет.
        ...([for (final f in _attachments) f.name, for (final p in _pendingOriginal) p.name]..sort()),
        '#$_fileEdits',
      ].join(',');
  void _markPristine() => _pristineSig = _sig(_useHtmlEditor ? _lastHtml : _plainController.text);
  bool get _isPristine =>
      _pristineSig != null && _sig(_useHtmlEditor ? _lastHtml : _plainController.text) == _pristineSig;
  static String _plainText(String body) =>
      _htmlToPlain(body).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Панель форматирования: на телефоне скрыта (стиль — в настройках
  /// аккаунта), на планшете и компьютере видна. null — ещё не определено.
  bool? _showFormatting;

  /// Стиль текста ящика «От» (шрифт, размер).
  ComposeStyle get _style =>
      ComposeStylesNotifier.styleFor(ref.read(composeStylesProvider), _fromAccount?.id);

  /// Подпись вставлена автоматически: при смене ящика «От» меняется на его.
  bool _autoSignature = false;
  bool get _isReplyOrForward => widget.replyToId != null || widget.forwardFromId != null;
  bool _isSending = false;

  /// Размер фото для этой отправки (1.7.2+109): доля ширины и высоты, 1 —
  /// как есть. Выбирается шторкой «Размер фото» или настройкой.
  double _imageScale = 1;

  /// Фото уменьшаются перед отправкой — кнопка «Отправить» крутится.
  bool _shrinking = false;

  /// Длина текста письма при последнем показе строки размера: вставили
  /// картинку в текст — строка «Письмо: … из …» обновляется (1.7.2+110).
  int _sizeShownBody = 0;

  final List<EmailAddress> _toRecipients = [];
  final List<EmailAddress> _ccRecipients = [];
  final List<EmailAddress> _bccRecipients = [];
  final List<ChosenFile> _attachments = [];

  /// Фото, уменьшенные вручную («Сжать» в карточке фото, 1.7.2+113): при
  /// отправке их не уменьшаем ещё раз.
  final Set<String> _shrunkPaths = {};

  /// Фото, которые сейчас уменьшаются или сохраняются после правки.
  final Set<ChosenFile> _editingFiles = {};

  /// Сколько раз правили файлы письма (обрезка, поворот, сжатие): имя файла
  /// при этом может не меняться, а письмо изменено.
  int _fileEdits = 0;

  bool _isShrunk(ChosenFile f) => f.path != null && _shrunkPaths.contains(f.path);

  /// Вложения пересылаемого письма, которых нет на телефоне (1.6.18). Видны
  /// плашками сразу и докачиваются в фоне, пока человек пишет текст. Пока
  /// они не скачаны, пересылку делает сервер (Exchange) — там файлы есть;
  /// иначе они качаются перед отправкой, а без связи письмо ждёт их в
  /// очереди отправки. Раньше такие файлы не показывались вовсе.
  final List<_PendingFile> _pendingOriginal = [];
  String? _pendingAccountId;
  String? _pendingEmailId;
  int get _notDownloadedCount => _pendingOriginal.length;

  String _importance = 'Normal'; // Low / Normal / High — важность письма
  /// Строка «sensitivity» для отправки: теперь только отметки S/MIME
  /// (очередь, отложенная отправка и все три протокола передают её без
  /// изменений). Гриф письма убран в 1.5.9 по решению владельца —
  /// пользователям он мешал; пометка Outlook — обычная.
  String get _sensitivity => MailLabel(
        // S/MIME едет той же строкой, что раньше гриф.
        smimeSign: _smimeAvailable && _smimeSign,
        smimeEncrypt: _smimeAvailable && _smimeEncrypt,
      ).encode();

  /// S/MIME: у ящика «От» загружен сертификат — можно подписать и
  /// зашифровать письмо (Настройки ящика → «Подпись и шифрование»).
  bool _smimeAvailable = false;
  bool _smimeSign = false;
  bool _smimeEncrypt = false;
  /// Отметки S/MIME выбраны в этом письме (черновик, переключатели) — при
  /// смене ящика не сбрасываются на значения по умолчанию.
  bool _smimeTouched = false;
  bool get _smimeActive => _smimeAvailable && (_smimeSign || _smimeEncrypt);

  /// Есть ли сертификат у ящика «От»; значения по умолчанию — из настроек
  /// ящика.
  Future<void> _loadSmime() async {
    final acc = _fromAccount;
    if (acc == null) return;
    final svc = ref.read(smimeServiceProvider);
    final cert = await svc.certificate(acc.id);
    if (!mounted || _fromAccount?.id != acc.id) return;
    setState(() {
      _smimeAvailable = cert != null && cert.isValidAt(DateTime.now());
      if (!_smimeTouched) {
        _smimeSign = svc.signByDefault(acc.id);
        _smimeEncrypt = svc.encryptByDefault(acc.id);
      }
    });
  }


  List<ContactModel> _contactSuggestions = [];

  /// Поле, в котором сейчас набирают адрес: подсказки показываются прямо
  /// под ним и добавляют получателя именно туда (раньше — внизу экрана,
  /// под редактором, и всегда в «Кому»).
  TextEditingController? _suggestFor;
  List<EmailAddress>? _suggestTarget;
  int _searchSeq = 0;
  AccountModel? _fromAccount;

  /// Адрес отправки «от имени» — адрес из «Адресов отправки» ящика (общий
  /// ящик отдела, ящик руководителя у секретаря, диспетчерская), 1.6.27.
  /// null — от адреса самого ящика.
  String? _fromAlias;
  EmailAddress? get _fromOverride => _fromAlias == null ? null : EmailAddress(email: _fromAlias!);

  // Автосохранение черновика: сервис, признак «письмо отправлено/черновик
  // удалён» (после него сохранять нечего) и id черновика — тот же, что у
  // открытого на правку черновика, иначе новый.
  DraftAutosaveService? _autosave;
  bool _sentOrDiscarded = false;
  /// Свой черновик (сохранён этим экраном, id «draft-…») продолжаем под тем
  /// же id. Черновик с сервера (папка «Черновики» Exchange/IMAP) сохраняем
  /// локально под новым id, а серверную копию удаляем после отправки —
  /// иначе автосохранение перезаписало бы письмо сервера.
  ///
  /// Не final с 1.7.0: «Ответить» на письмо, у которого уже есть начатый
  /// ответ, продолжает тот черновик — под его id (см. [_resumeReplyDraft]).
  String _draftId = 'draft-';
  ({String id, String folderId})? _serverDraft;
  late final DraftSyncService _draftSync;
  late final ReplyDraftsNotifier _replyDrafts;

  /// Исходное письмо ответа или пересылки (1.7.0): из параметров экрана, а у
  /// открытого черновика — из его записи (parent_id) или по теме из
  /// [replyDraftsProvider]. Нужен для In-Reply-To, отметки «Отвечено» и
  /// строки «Черновик: …» у исходного письма в ленте.
  String? _parentId;
  String? _parentAccountId;
  String? _parentConversationId;
  bool _parentForward = false;

  /// Открытый черновик, как он был загружен: не меняли — закрытие без
  /// вопросов и без повторной выгрузки на сервер.
  bool _openedDraft = false;

  @override
  void initState() {
    super.initState();
    _draftSync = ref.read(draftSyncServiceProvider);
    _replyDrafts = ref.read(replyDraftsProvider.notifier);
    _draftId = (widget.draftId != null && widget.draftId!.startsWith('draft-'))
        ? widget.draftId!
        : 'draft-${const Uuid().v4()}';
    _draftSync.beginEdit(_draftId);
    _parentId = widget.replyToId ?? widget.forwardFromId;
    _parentForward = widget.replyToId == null && widget.forwardFromId != null;
    _parentAccountId = widget.accountId;
    _initFromAccount();
    // Ящики ещё не загружены («Написать» из виджета, уведомления, «Поделиться»
    // или ссылки mailto сразу после запуска): «От» — когда они появятся.
    // Раньше строка так и оставалась пустой, с «?» вместо ящика (28.10.2026).
    if (_fromAccount == null) {
      ref.listenManual(accountsProvider, (_, next) {
        if (_fromAccount != null || next.isEmpty || !mounted) return;
        _initFromAccount();
        final acc = _fromAccount;
        if (acc == null) return;
        _fromAccount = null; // _onFromChanged сравнивает с прежним ящиком
        _onFromChanged(acc);
      });
    }
    // Поле темы или адресатов получило фокус — редактор письма отпускает
    // свой курсор (1.5.10: курсор и «капля» выделения оставались в тексте
    // письма, и курсоров было два).
    for (final f in [_subjectFocus, _toFocus, _ccFocus, _bccFocus]) {
      f.addListener(() {
        if (f.hasFocus && _useHtmlEditor) unawaited(_editor.blur());
      });
    }
    unawaited(_loadSmime());
    _initContent();
    _initSharedContent();
    _initPrefilledRecipient();
    if (widget.draftId == null && !_isReplyOrForward &&
        (widget.sharedBody ?? '').isEmpty && widget.sharedAttachments.isEmpty) {
      _markPristine();
    }
    _startAutosave();
    for (final (f, c) in [
      (_toFocus, _toController),
      (_ccFocus, _ccController),
      (_bccFocus, _bccController),
    ]) {
      f.addListener(() => _onFieldFocus(f, c));
    }
  }

  /// Поле адресатов потеряло фокус — набранный адрес становится плашкой,
  /// поле сворачивается в строку.
  void _onFieldFocus(FocusNode f, TextEditingController c) {
    if (!mounted) return;
    if (f.hasFocus) {
      _caretInBody = false;
      if (_editingField != c) setState(() => _editingField = c);
      return;
    }
    // Нажатие на подсказку снимает фокус раньше, чем срабатывает выбор, —
    // сворачиваем после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || f.hasFocus || _editingField != c) return;
      final target = c == _toController
          ? _toRecipients
          : (c == _ccController ? _ccRecipients : _bccRecipients);
      setState(() {
        _commitPendingRecipient(c, target);
        _editingField = null;
        if (_suggestFor == c) _contactSuggestions.clear();
        _lastQuery = '';
      });
      if (c == _toController) _updateGreeting();
      unawaited(_fillNamesFromContacts());
    });
  }

  /// Предзаполнить адресата, если экран открыт с параметром `to`
  /// (кнопка «Написать» в карточке контакта).
  void _initPrefilledRecipient() {
    void fill(String? value, List<EmailAddress> target) {
      final addr = value?.trim();
      if (addr == null || addr.isEmpty) return;
      // Несколько адресов через запятую или «;» — «Написать участникам» встречи.
      for (final a in addr.split(RegExp(r'[,;]'))) {
        var e = a.trim();
        if (e.isEmpty || !e.contains('@')) continue;
        // «Имя <адрес>» (ссылки mailto на сайтах) — имя отдельно (1.6.33).
        String? name;
        final m = RegExp(r'^(.*?)<([^<>\s]+@[^<>\s]+)>$').firstMatch(e);
        if (m != null) {
          name = m.group(1)!.trim().replaceAll(RegExp(r'^"|"$'), '').trim();
          e = m.group(2)!.trim();
          if (name.isEmpty || name.contains('\uFFFD')) name = null;
        }
        if (target.any((r) => r.email.toLowerCase() == e.toLowerCase())) continue;
        target.add(EmailAddress(email: e, displayName: name));
      }
    }

    fill(widget.cc, _ccRecipients);
    fill(widget.bcc, _bccRecipients);
    if (_ccRecipients.isNotEmpty) _showCc = true;
    if (_bccRecipients.isNotEmpty) _showBcc = true;
    if ((widget.to ?? '').trim().isNotEmpty) {
      fill(widget.to, _toRecipients);
      _updateGreeting();
    }
    unawaited(_fillNamesFromContacts());
  }

  /// Адреса без имени («Написать» в контакте и во встрече, ссылка mailto,
  /// набранный вручную адрес) — именем из контактов и писем, как при выборе
  /// из подсказок (замечание 13.10.2026: оставался голый адрес).
  /// Дополняет [_resolveRecipientNames] (1.5.9, полное ФИО из адресной книги
  /// организации — только когда выбран ящик «От»): здесь имя из уже
  /// известных контактов и писем, сразу и без сети.
  Future<void> _fillNamesFromContacts() async {
    final Map<String, String> names;
    try {
      names = await ref.read(personNamesProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    var changed = false;
    for (final list in [_toRecipients, _ccRecipients, _bccRecipients]) {
      for (var i = 0; i < list.length; i++) {
        final r = list[i];
        if ((r.displayName ?? '').trim().isNotEmpty) continue;
        final n = names[r.email.toLowerCase()];
        if (n == null) continue;
        list[i] = EmailAddress(email: r.email, displayName: n);
        changed = true;
      }
    }
    if (!changed) return;
    setState(() {});
    _updateGreeting();
  }

  /// Автосохранение черновика. Сервис был написан (таймер 30 с, флаг изменений,
  /// принудительное сохранение), но его никто не вызывал: черновик сохранялся
  /// только по кнопке. Свернул приложение на полуслове — текст терялся.
  void _startAutosave() {
    _autosave = ref.read(draftAutosaveProvider);
    _autosave!.startAutosave(_snapshot());
    _autosave!.savedAt.addListener(_onDraftSaved);
    // Правки в полях помечают черновик изменённым — таймер сохранит их сам.
    _subjectController.addListener(_markDraftChanged);
    _plainController.addListener(_markDraftChanged);
  }

  void _markDraftChanged() {
    if (_sentOrDiscarded) return;
    _autosave?.updateDraft(_snapshot());
    _recomputeSuggestions();
  }

  /// Черновик записан (таймер или кнопка «Сохранить»): подпись «Сохранено ·
  /// чч:мм» под заголовком и строка «Черновик: …» у исходного письма.
  void _onDraftSaved() {
    if (!mounted || _sentOrDiscarded) return;
    final at = _autosave?.savedAt.value;
    if (at == null) return;
    _localSaved = true;
    setState(() => _savedAt = at);
    _rememberReplyDraft();
  }

  DateTime? _savedAt;

  /// Это окно уже записывало черновик в базу (таймер или «Сохранить»).
  bool _localSaved = false;

  /// Точка «не меняли» — сохранённая кнопкой «Сохранить» версия (а не
  /// черновик, как его открыли).
  bool _pristineSaved = false;

  /// Начатый ответ — у исходного письма в ленте «Черновик: …» (1.7.0).
  void _rememberReplyDraft() {
    final pid = _parentId;
    final acc = _parentAccountId ?? _fromAccount?.id;
    if (pid == null || acc == null || _isPristine) return;
    unawaited(_replyDrafts.put(ReplyDraft(
      accountId: acc,
      emailId: pid,
      conversationId: _parentConversationId,
      subject: _subjectController.text,
      text: ReplyDraft.snippet(_authoredPlain),
      forward: _parentForward,
      at: DateTime.now(),
    )));
  }

  /// Ответ отправлен или черновик удалён — строка «Черновик: …» не нужна.
  void _forgetReplyDraft() {
    final pid = _parentId;
    final acc = _parentAccountId ?? _fromAccount?.id;
    if (pid != null && acc != null) {
      unawaited(_replyDrafts.removeFor(acc, pid));
      return;
    }
    // Черновик из «Черновиков», связь с исходным письмом не нашлась, — по теме.
    final from = _fromAccount?.id;
    if (widget.draftId != null && from != null) {
      unawaited(_replyDrafts.removeBySubject(from, _subjectController.text));
    }
  }

  /// Пересчитать подсказки Smart Compose по текущему тексту тела. Вызывается на
  /// каждое изменение тела (единая точка _markDraftChanged — работает и для
  /// html-редактора через onChangeContent, и для TextField-фолбэка).
  void _recomputeSuggestions() {
    final list = ref.read(smartComposeProvider).getSuggestions(_authoredPlain);
    if (!mounted) return;
    // Не дёргаем setState, если набор не изменился (снижаем перерисовки при наборе).
    if (list.length == _composeSuggestions.length &&
        List.generate(list.length, (i) => list[i].text == _composeSuggestions[i].text)
            .every((x) => x)) {
      return;
    }
    setState(() => _composeSuggestions = list);
  }

  /// Применить подсказку: вставляем ОСТАТОК фразы за уже набранным префиксом
  /// (ghost-completion) — читается верно в обоих редакторах. Если фраза не
  /// продолжает набранное — вставляем целиком.
  void _applySuggestion(SmartComposeSuggestion s) {
    final typed = _authoredPlain.split('\n').last.trimLeft();
    final phrase = s.text;
    final insert = (typed.isNotEmpty && phrase.toLowerCase().startsWith(typed.toLowerCase()))
        ? phrase.substring(typed.length)
        : phrase;
    _insertBodyPlainAtCursor(insert);
    setState(() => _composeSuggestions = const []);
  }

  /// Текущее состояние письма для черновика.
  /// Тело берём из ПЛОШКИ-фолбэка либо из кэша html-редактора (_lastHtml):
  /// getText() у него асинхронный, а снимок нужен синхронно — по таймеру.
  DraftData _snapshot({bool force = false}) {
    Map<String, String> addr(EmailAddress a) =>
        {'email': a.email, if (a.displayName != null) 'name': a.displayName!};
    final rawBody = _useHtmlEditor ? _lastHtml : _plainController.text;
    // Письмо не тронуто (только автоматическое содержимое) — пустой снимок:
    // сервис автосохранения пустое не сохраняет.
    final untouched = !force && _isPristine;
    if (untouched) {
      return DraftData(
        id: _draftId,
        accountId: _fromAccount?.id ?? widget.accountId ?? '',
        to: const [],
        cc: const [],
        bcc: const [],
        subject: '',
        body: '',
        replyToId: _parentForward ? null : _parentId,
        forwardFromId: _parentForward ? _parentId : null,
        parentAccountId: _parentAccountId,
        savedAt: DateTime.now(),
      );
    }
    return DraftData(
      id: _draftId,
      accountId: _fromAccount?.id ?? widget.accountId ?? '',
      to: _toRecipients.map(addr).toList(),
      cc: _ccRecipients.map(addr).toList(),
      bcc: _bccRecipients.map(addr).toList(),
      subject: _subjectController.text,
      // Цитата — в черновик тоже: иначе ответ, открытый из «Черновиков»
      // (здесь или в Outlook), был бы без исходного письма.
      body: _quoteHtml == null ? rawBody : '$rawBody<div><br></div>${_quoteHtml!}',
      replyToId: _parentForward ? null : _parentId,
      forwardFromId: _parentForward ? _parentId : null,
      parentAccountId: _parentAccountId,
      sensitivity: _sensitivity,
      savedAt: DateTime.now(),
      // Файлы письма (1.7.2+111): свои — копией в папку черновика, не
      // скачанные файлы пересылки — ссылкой.
      files: [
        for (final f in _attachments)
          DraftFile.local(name: f.name, size: f.size, mimeType: _mimeForName(f.name), path: f.path, bytes: f.bytes),
        if (_pendingAccountId != null && _pendingEmailId != null)
          for (final p in _pendingOriginal)
            DraftFile.remote(
              name: p.name,
              size: p.size,
              mimeType: p.mimeType,
              accountId: _pendingAccountId!,
              emailId: _pendingEmailId!,
              attachmentId: p.id,
            ),
      ],
    );
  }

  /// Контент, пришедший через системное "Поделиться".
  void _initSharedContent() {
    final subj = widget.sharedSubject;
    if (subj != null && subj.isNotEmpty && _subjectController.text.isEmpty) {
      _subjectController.text = subj;
    }
    if (widget.sharedBody != null && widget.sharedBody!.isNotEmpty) {
      _setBodyPlain('${widget.sharedBody}\n\n');
    }
    if (widget.sharedAttachments.isNotEmpty) {
      for (final path in widget.sharedAttachments) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            final bytes = file.lengthSync();
            _attachments.add(ChosenFile(
              name: path.split(Platform.pathSeparator).last,
              size: bytes,
              path: path,
            ));
          }
        } catch (_) {}
      }
      if (mounted) setState(() {});
    }
  }

  void _initFromAccount() {
    final accounts = ref.read(accountsProvider);
    // Список аккаунтов может быть пуст (все удалены) — тогда `.first` в orElse
    // бросил бы StateError прямо при открытии экрана.
    if (accounts.isEmpty) return;
    if (widget.accountId != null) {
      _fromAccount = accounts.firstWhere(
        (a) => a.id == widget.accountId,
        orElse: () => accounts.first,
      );
    } else {
      _fromAccount = ref.read(activeAccountProvider);
    }
  }

  /// Загрузить исходное письмо для ОТВЕТА или ПЕРЕСЫЛКИ.
  ///
  /// Раньше `replyToId`/`forwardFromId` доходили до экрана и использовались лишь
  /// в проверке `== null` (вставлять приветствие или нет). Само письмо не
  /// загружалось: не было ни получателя, ни «Re:»/«Fwd:», ни цитаты, ни вложений.
  Future<void> _initReplyOrForward() async {
    final id = widget.replyToId ?? widget.forwardFromId;
    if (id == null) return;
    final isReply = widget.replyToId != null;

    try {
      final db = ref.read(databaseProvider);
      final row = await db.getEmailById(id, accountId: widget.accountId);
      if (row == null || !mounted) return;
      _parentConversationId = row.conversationId;

      final l10n = AppLocalizations.of(context);
      final me = _fromAccount?.email.toLowerCase();

      if (isReply) {
        final mid = row.internetMessageId?.trim();
        // У ActiveSync поле могло хранить ServerId («5:12») — это не
        // Message-ID, такой заголовок только запутает почтовый сервер.
        if (mid != null && mid.contains('@')) {
          // Вся цепочка: References родителя + его Message-ID.
          final refs = row.referencesStr?.trim() ?? '';
          _inReplyTo = refs.isEmpty ? mid : '$refs $mid';
        }
      }

      // ── Получатели ──
      final from = EmailAddress(
        email: row.fromEmail,
        displayName: row.fromName,
      );
      var origTo = _parseAddrs(row.toRecipients);
      var origCc = _parseAddrs(row.ccJson);
      var replyTo = _parseAddrs(row.replyToEmail);
      // EWS отдаёт получателей и Reply-To только с полным письмом. Письмо,
      // которое ещё не открывали (ответ из уведомления, из списка), знало бы
      // одного отправителя: «Ответить всем» теряло адресатов, а в шапке
      // пересылки не было «Кому». Дозапрашиваем, недолго.
      final acc0 = _fromAccount;
      if (origTo.isEmpty && acc0 != null && (acc0.usesEws || acc0.isExchange)) {
        try {
          final full = await ref
              .read(mailEngineServiceProvider)
              .fetchEmailDetailEws(acc0, row.id)
              .timeout(const Duration(seconds: 4));
          if (full != null) {
            origTo = full.to;
            if (full.cc.isNotEmpty) origCc = full.cc;
            if (full.replyTo.isNotEmpty) replyTo = full.replyTo;
          }
        } catch (e) {
          AppLogger.warning('Compose: получатели оригинала не дозагружены: $e');
        }
        if (!mounted) return;
      }
      if (isReply) {
        // «Я» — любой адрес ящика (адрес входа, основной с сервера, алиасы):
        // раньше при входе под другим адресом себя не исключали, и
        // «Ответить всем» уходило в копию самому себе.
        final acc = _fromAccount;
        bool mine(String email) =>
            acc == null ? email.toLowerCase() == me : OwnAddresses.isMine(acc, email);
        // Как в Outlook (1.5.12): Reply-To учитывается, при «Ответить всем»
        // «Кому» оригинала остаются в «Кому», «Копия» — в копии.
        final r = ReplyBuilder.recipients(
          from: from,
          replyTo: replyTo,
          to: origTo,
          cc: origCc,
          all: widget.replyAll,
          mine: mine,
        );
        _toRecipients.addAll(r.to);
        _ccRecipients.addAll(r.cc);
        // Письмо пришло на «адрес отправки» ящика (общий адрес отдела,
        // диспетчерская, ящик руководителя) — отвечаем от него же (1.6.27).
        if (acc != null) {
          final aliases = {
            for (final x in ref.read(aliasServiceProvider)[acc.id] ?? const <String>[]) x.toLowerCase(): x,
          };
          final hit = [...origTo, ...origCc]
              .map((a) => a.email.toLowerCase())
              .where((e) => e != acc.email.toLowerCase() && aliases.containsKey(e))
              .firstOrNull;
          if (hit != null) _fromAlias = aliases[hit];
        }
        if (_ccRecipients.isNotEmpty) _showCc = true;
        _replyRecipientsAtStart = _recipientsKey();
        _replySpecialCase = replyTo.isNotEmpty || mine(from.email);
      }

      // Вы уже писали в этой переписке — приветствие короткое («Максим
      // Геннадьевич,»): полное во втором и третьем ответе звучит странно.
      final acc1 = _fromAccount;
      if (isReply && acc1 != null) {
        _wroteInThread = await GreetingHistory.wroteBefore(db, acc1, row);
        if (!mounted) return;
      }

      // Приветствие — по адресату ответа («Добрый день, Максим Геннадьевич,»).
      _updateGreeting();

      // ── Тема ──
      // Один префикс, как в Outlook: «RE: » / «FW: », прежние убираются
      // (1.5.12: было «Fwd: RE: …», и префиксы росли с каждым кругом).
      final subj = row.subject;
      _subjectController.text = isReply ? SubjectPrefix.reply(subj) : SubjectPrefix.forward(subj);

      // ── Цитата ──
      // Шапка как у Outlook — «От / Отправлено / Кому / Копия / Тема» под
      // линией, одна и та же для ответа и пересылки (1.5.12; была шапка
      // Gmail «…, Иван пишет:» и отступ-цитата).
      // ── Вложения: только при пересылке (1.6.12 — до цитаты) ──
      // При ОТВЕТЕ вложения не переносятся: это лишний трафик, и получатель их
      // уже видел. При ПЕРЕСЫЛКЕ они нужны — берём из кэша, если уже скачаны.
      // Раньше они прикладывались после цитаты: ошибка при её подготовке
      // (огромное письмо, сбой очистки) обрывала загрузку, и письмо уходило
      // без вложений (замечание 15.10.2026).
      if (!isReply) {
        try {
          await _attachOriginal(row);
        } catch (e) {
          AppLogger.warning('Пересылка: вложения оригинала не приложены: $e');
        }
      }

      final header = ReplyBuilder.header(
        labels: {
          'from': l10n.tr('quoteFrom'),
          'sent': l10n.tr('quoteSent'),
          'to': l10n.tr('quoteTo'),
          'cc': l10n.tr('quoteCc'),
          'subject': l10n.tr('quoteSubject'),
        },
        from: from,
        sent: ReplyBuilder.sentDate(row.sentAt ?? row.receivedAt, l10n.localeCode),
        to: origTo,
        cc: origCc,
        subject: row.subject,
      );

      // Цитата — только после очистки по белому списку (письма ActiveSync и
      // IMAP хранятся без очистки). Стили оригинала сохраняются: без них
      // вёрстка Outlook (таблицы, отступы) у получателя разваливается.
      final quotedBody = row.bodyHtml != null
          ? await MailBodyProcessor.heavy(row.bodyHtml!, HtmlSanitizer.sanitizeKeepingStyles)
          : (row.bodyPlain != null ? '<pre>${_esc(row.bodyPlain!)}</pre>' : '');
      if (!mounted) return;
      final quote = ReplyBuilder.quote(header, quotedBody);
      _quoteHeader = header;

      if (_useHtmlEditor) {
        // Цитата — под редактором, только для чтения (см. _quoteHtml).
        _quoteHtml = quote;
        if (mailWebViewSupported) {
          _quoteDoc = MailHtmlDocument.build(quote, allowRemoteImages: false);
        }
      } else {
        _appendBodyHtml('<br><br>$quote');
      }


      // Вложения пересылки — уже приложены выше, до цитаты (1.6.12).

      // Ответ, который просто открыли и закрыли, черновиком не становится.
      _markPristine();
      if (mounted) setState(() {});
    } catch (e) {
      AppLogger.error('Compose: не удалось загрузить исходное письмо', e);
    }
  }

  /// Прикрепить вложения исходного письма при пересылке.
  ///
  /// Про «не качать заново»: файл берётся ИЗ КЭША, если он там уже есть (письмо
  /// открывали — вложение осело в кэше). Если нет — докачиваем один раз и кладём
  /// в кэш. Совсем без скачивания обойтись нельзя: SMTP требует, чтобы клиент
  /// собрал MIME целиком. Исключение — Exchange: у EWS есть серверная пересылка
  /// (ForwardItem), при которой вложения не покидают сервер, — вынесено в карту.
  Future<void> _attachOriginal(Email row) async {
    final raw = row.attachmentsJson;
    if (raw == null || raw.isEmpty) return;

    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List;
    } catch (_) {
      return;
    }
    if (list.isEmpty) return;
    _pendingAccountId = row.accountId;
    _pendingEmailId = row.id;

    final cache = ref.read(attachmentCacheProvider);
    var skippedInline = 0;
    for (final item in list) {
      try {
        final m = item as Map<String, dynamic>;
        // Встроенные картинки уже в теле цитаты — вторым файлом не нужны.
        if (_isInlineImage(m)) {
          skippedInline++;
          continue;
        }
        final id = m['id']?.toString();
        // Имя может храниться в MIME-кодировке («=?utf-8?B?…?=»).
        final meta = EmailAttachment.fromMap(m);
        final name = meta.name;
        if (id == null) continue;
        final pending = _PendingFile(id: id, name: name, size: meta.size,
            mimeType: meta.mimeType.isEmpty ? null : meta.mimeType);

        // Ключ кэша тот же, что у экрана письма и фоновой предзагрузки.
        final path = await cache.get(MailEngineService.attachmentCacheKey(
            row.accountId, row.id, id)); // уже скачано — сеть не трогаем
        if (path == null) {
          // Вложение не скачано локально. Само по себе это не беда: серверная
          // пересылка сохранит его без участия клиента. Но её нужно РАЗРЕШИТЬ —
          // раньше несовпадение числа вложений её отключало, и письмо уходило
          // без файла.
          _pendingOriginal.add(pending);
          continue;
        }
        final f = File(path);
        if (!await f.exists()) {
          _pendingOriginal.add(pending);
          continue;
        }
        _attachments.add(ChosenFile(
          name: name,
          size: await f.length(),
          path: path,
        ));
      } catch (_) {}
    }
    if (skippedInline > 0) {
      AppLogger.debug('Пересылка: пропущено встроенных вложений — $skippedInline');
    }
    // Не скачанные файлы — в фоне, по одному (1.6.18).
    if (_pendingOriginal.isNotEmpty) unawaited(_prefetchPending());
  }

  /// Докачать файлы пересылаемого письма, пока человек пишет текст.
  Future<void> _prefetchPending() async {
    for (final p in List<_PendingFile>.of(_pendingOriginal)) {
      if (!mounted) return;
      if (!_pendingOriginal.contains(p)) continue; // плашку убрали
      await _fetchPending(p);
    }
  }

  /// Одно скачивание на файл: фоновая докачка и отправка ждут одну и ту же
  /// загрузку, а не качают файл дважды (и не прикладывают его дважды).
  Future<bool> _fetchPending(_PendingFile p) =>
      p.task ??= _downloadPending(p).whenComplete(() => p.task = null);

  Future<bool> _downloadPending(_PendingFile p) async {
    final accId = _pendingAccountId;
    final emailId = _pendingEmailId;
    if (accId == null || emailId == null) return false;
    final account = ref.read(accountsProvider).where((a) => a.id == accId).firstOrNull;
    if (account == null) return false;
    if (mounted) {
      setState(() {
        p.loading = true;
        p.failed = false;
      });
    }
    try {
      // Качаем от имени ящика, где лежит ИСХОДНОЕ письмо (общий ящик).
      final bytes = await ref.read(mailEngineServiceProvider).getAttachmentBytes(account, p.id, emailId: emailId);
      if (bytes.isEmpty) throw StateError('сервер вернул пустое вложение');
      String? path;
      try {
        // Ключ кэша — как у экрана письма: файл не придётся качать снова.
        path = await ref.read(attachmentCacheProvider).put(
            MailEngineService.attachmentCacheKey(accId, emailId, p.id), p.name, bytes);
      } catch (_) {}
      if (!_pendingOriginal.contains(p)) return true; // плашку убрали, пока качали
      final file = path != null
          ? ChosenFile(name: p.name, size: bytes.length, path: path)
          : ChosenFile(name: p.name, size: bytes.length, bytes: bytes);
      if (mounted) {
        setState(() {
          _pendingOriginal.remove(p);
          _attachments.add(file);
        });
      } else {
        _pendingOriginal.remove(p);
        _attachments.add(file);
      }
      return true;
    } catch (e) {
      AppLogger.warning('Пересылка: вложение «${p.name}» не скачано: $e');
      if (mounted) {
        setState(() {
          p.loading = false;
          p.failed = true;
        });
      }
      return false;
    }
  }

  /// Ссылки на недостающие файлы — для очереди отправки.
  List<RemoteAttachment> _pendingRefs() => [
        if (_pendingAccountId != null && _pendingEmailId != null)
          for (final p in _pendingOriginal)
            (
              accountId: _pendingAccountId!,
              emailId: _pendingEmailId!,
              attachmentId: p.id,
              name: p.name,
              contentType: p.mimeType,
            ),
      ];

  /// Получатели из строки БД: JSON-список [{email, displayName}] (так их
  /// пишут синхронизация и черновики); старый формат — адреса через «;».
  List<EmailAddress> _parseAddrs(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final t = raw.trimLeft();
    if (t.startsWith('[')) {
      try {
        return (jsonDecode(t) as List)
            .whereType<Map>()
            .map((m) => EmailAddress.fromMap(Map<String, dynamic>.from(m)))
            .where((a) => a.email.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    return raw
        .split(';')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => EmailAddress(email: s.trim()))
        .toList();
  }

  String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Подставить переменные подписи. Неизвестные значения убираются вместе
  /// со строкой-подписью («Тел.: » без номера не остаётся).
  /// Шрифт, размер и цвет подписи — как у текста письма. Подписи из Outlook
  /// и шаблоны несли свои (Calibri 10pt, серый 12px): подпись выглядела
  /// чужой вставкой, а в тёмной теме серый текст терялся. Жирный, курсив и
  /// ссылки сохраняются.
  static String _normalizeSignatureFont(String html) {
    var out = html.replaceAllMapped(
        RegExp(r'''style\s*=\s*(["'])(.*?)\1''', caseSensitive: false, dotAll: true), (m) {
      final kept = m
          .group(2)!
          .split(';')
          .map((d) => d.trim())
          .where((d) {
            final prop = d.split(':').first.trim().toLowerCase();
            return d.isNotEmpty &&
                !const {'font-family', 'font-size', 'color', 'line-height', 'font', 'mso-bidi-font-family', 'mso-fareast-font-family', 'mso-ansi-language'}
                    .contains(prop) &&
                !prop.startsWith('mso-');
          })
          .join(';');
      return kept.isEmpty ? '' : 'style="$kept"';
    });
    // <font face="…" size="…" color="…"> → без атрибутов оформления.
    out = out.replaceAllMapped(RegExp(r'<font\b[^>]*>', caseSensitive: false), (_) => '<span>');
    out = out.replaceAll(RegExp(r'</font\s*>', caseSensitive: false), '</span>');
    return out;
  }

  String _renderSignature(String template, {required bool html, AccountModel? account}) {
    final acc = account ?? _fromAccount!;
    final card = ref.read(mailEngineServiceProvider).cachedSelfCard(acc.id);
    // Имя отправителя из настроек аккаунта главнее адресной книги: там
    // бывает «Фамилия Имя», а человек хочет «Имя Отчество Фамилия» или
    // иное. Логин и адрес именем не считаются — тогда берём карточку.
    final own = acc.displayName.trim();
    final ownIsReal = own.isNotEmpty &&
        own.toLowerCase() != acc.email.toLowerCase() &&
        own.toLowerCase() != acc.email.split('@').first.toLowerCase();
    final values = <String, String>{
      'name': ownIsReal ? own : (card['name'] ?? own),
      'title': card['title'] ?? '',
      'department': card['office'] ?? '',
      'company': card['company'] ?? '',
      'phone': card['phone'] ?? card['mobile'] ?? '',
      'email': acc.email,
    };
    var out = template;
    values.forEach((k, v) => out = out.replaceAll('{$k}', v));
    out = out.replaceAll(RegExp(r'\{[a-zA-Zа-яА-Я_]+\}'), '');
    if (html) {
      // Абзацы подписи — строками (div) без верхнего отступа: в редакторе
      // строки идут без отступов, и подпись с <p> и margin-top стояла
      // отдельным островом с большими промежутками.
      out = out
          .replaceAllMapped(RegExp(r'<p(\s[^>]*)?>', caseSensitive: false), (m) => '<div${m.group(1) ?? ''}>')
          .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '</div>')
          .replaceAll(RegExp(r'margin-top\s*:\s*\d+px;?', caseSensitive: false), '');
      out = _normalizeSignatureFont(out);
      // «Тел.: <br>», двойные <br> и пустые абзацы после пустых полей.
      out = out
          .replaceAllMapped(RegExp(r'[^<>\n]{0,20}:\s*(<br\s*/?>)', caseSensitive: false),
              (m) => m.group(1)!)
          .replaceAll(RegExp(r'(<br\s*/?>\s*){2,}', caseSensitive: false), '<br>')
          .replaceAll(RegExp(r'<p>\s*(<br\s*/?>)?\s*</p>', caseSensitive: false), '');
      return out;
    }
    return out
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !RegExp(r':\s*$').hasMatch(l.trim()))
        .join('\n');
  }

  void _initContent() {
    // Открыт сохранённый черновик — продолжаем его, без приветствия и подписи.
    if (widget.draftId != null) {
      unawaited(_initFromDraft(widget.draftId!));
      return;
    }
    // «Ответить» на письмо, у которого уже начат ответ («Черновик: …» в
    // ленте), — продолжить тот черновик, а не заводить второй (1.7.0, как
    // Gmail и Telegram). Текст из быстрого ответа или «Поделиться» — новое
    // письмо, как раньше.
    final pid = _parentId;
    final pacc = _parentAccountId ?? widget.accountId;
    if (pid != null && pacc != null &&
        (widget.quickText ?? '').trim().isEmpty && (widget.sharedBody ?? '').isEmpty) {
      final started = ref.read(replyDraftsProvider)['$pacc|$pid'];
      if (started != null && started.forward == _parentForward) {
        unawaited(_resumeReplyDraft(started));
        return;
      }
    }
    _initNewContent();
  }

  /// Найти черновик начатого ответа: свой (на телефоне, по parent_id) или
  /// уже выгруженный в «Черновики» (по теме). Нашёлся — открыть его; нет
  /// (удалён в Outlook, отправлен с компьютера) — обычный новый ответ.
  Future<void> _resumeReplyDraft(ReplyDraft started) async {
    String? foundId;
    var foundAcc = started.accountId;
    try {
      final db = ref.read(databaseProvider);
      final ref0 = '${started.forward ? 'f' : 'r'}|${started.accountId}|${started.emailId}';
      final local = await db.customSelect(
        "SELECT id, account_id FROM emails WHERE folder_id = 'drafts' AND parent_id = ? "
        'ORDER BY received_at DESC LIMIT 1',
        variables: [Variable.withString(ref0)],
        readsFrom: {db.emails},
      ).getSingleOrNull();
      foundId = local?.read<String>('id');
      if (local != null) foundAcc = local.read<String>('account_id');
      if (foundId == null) {
        final bare = ReplyDraft.bareSubject(started.subject);
        final rows = await db.customSelect(
          'SELECT e.id AS id, e.subject AS subject FROM emails e '
          'WHERE e.account_id = ? AND e.folder_id IN '
          '(SELECT f.id FROM folders f WHERE f.account_id = e.account_id AND f.type = ?) '
          'ORDER BY e.received_at DESC LIMIT 50',
          variables: [Variable.withString(started.accountId), Variable.withInt(FolderType.drafts.index)],
          readsFrom: {db.emails, db.folders},
        ).get();
        for (final r in rows) {
          if (bare.isNotEmpty && ReplyDraft.bareSubject(r.read<String>('subject')) == bare) {
            foundId = r.read<String>('id');
            break;
          }
        }
      }
    } catch (e) {
      AppLogger.debug('Начатый ответ не найден: $e');
    }
    if (!mounted) return;
    if (foundId == null) {
      unawaited(_replyDrafts.removeFor(started.accountId, started.emailId));
      _initNewContent();
      return;
    }
    if (foundId.startsWith('draft-') && foundId != _draftId) {
      // Свой черновик — дальше сохраняем под его id.
      _draftSync.endEdit(_draftId);
      _draftId = foundId;
      _draftSync.beginEdit(_draftId);
    }
    await _initFromDraft(foundId, accountId: foundAcc);
  }

  void _initNewContent() {
    // Ответ/пересылка — асинхронно: письмо читаем из БД, экран не ждёт.
    unawaited(_initReplyOrForward());
    // Текст из «Поделиться» заменяет тело целиком (см. _initSharedContent).
    if (widget.sharedBody != null && widget.sharedBody!.isNotEmpty) return;

    // Приветствие и подпись — и в новом письме, и в ответе, и в пересылке.
    // Раньше в ответах тело было пустым, а приветствие с именем-отчеством
    // в редакторе с оформлением не обновлялось вовсе.
    final greeting = _greetingText();
    // Приветствие выключено для ящика — пустое письмо с подписью.
    _autoGreeting = greeting.isEmpty ? null : greeting;
    _greetingPlaced = greeting.isNotEmpty;
    final settings = ref.read(settingsProvider);
    final sig = settings.autoInsertSignature ? _signatureFor(_fromAccount) : null;
    _autoSignature = sig != null;
    if (_useHtmlEditor) {
      // Между приветствием и подписью — три пустые строки, курсор — на
      // средней (замечание 07.10.2026).
      final quick = widget.quickText?.trim() ?? '';
      final blank3 = quick.isEmpty
          ? '<div><br></div><div><br></div><div><br></div>'
          : '<div><br></div>${quick.split('\n').map((l) => '<div>${l.isEmpty ? '<br>' : _escText(l)}</div>').join()}<div><br></div>';
      final html = (greeting.isEmpty ? blank3 : '<div id="ogn-greeting">${_escText(greeting)}</div>$blank3')
          + (sig != null ? '<div id="ogn-signature">${sig.html}</div>' : '');
      _editor.setHtml(_toEditor(html));
      _lastHtml = html;
      // В ответе сразу пишут текст; в новом письме сначала выбирают адресата.
      if (_isReplyOrForward) _editor.focusText();
    } else {
      final quick = widget.quickText?.trim() ?? '';
      _plainController.text = greeting.isEmpty
          ? '\n$quick\n\n${sig != null ? sig.plain : ''}'
          : '$greeting\n\n$quick\n\n${sig != null ? sig.plain : ''}';
      _plainController.selection = TextSelection.collapsed(
          offset: (greeting.isEmpty ? 1 : greeting.length + 2) + quick.length);
    }
    // Подписи читаются из базы асинхронно: при первом открытии после запуска
    // список ещё пуст — подпись вставляется, как только он загрузится
    // (раньше в этом случае письмо оставалось без подписи).
    if (sig == null && settings.autoInsertSignature && ref.read(signaturesProvider).isEmpty) {
      ref.listenManual<List<SignatureModel>>(signaturesProvider, (prev, next) {
        if (_autoSignature || next.isEmpty || !mounted) return;
        final s2 = _signatureFor(_fromAccount);
        if (s2 == null) return;
        _autoSignature = true;
        final wasPristine = _isPristine;
        if (_useHtmlEditor) {
          _editor.setSignature(s2.html);
          _lastHtml += '<div><br></div><div id="ogn-signature">${s2.html}</div>';
        } else {
          _plainController.text = '${_plainController.text.trimRight()}\n\n\n${s2.plain}';
        }
        if (wasPristine) _markPristine();
      });
    }
  }

  /// Приветствие по адресатам «Кому»: вариант, выбранный кнопкой
  /// «Приветствие», иначе по настройке ящика — нет, «Добрый день!» или
  /// «Добрый день, Имя Отчество,» (в переписке, где вы уже писали, —
  /// «Имя Отчество,»). '' — без приветствия.
  String _greetingText() {
    final v = _greetingVariantNow;
    if (v == GreetingVariant.none) return '';
    if (v != GreetingVariant.hello) {
      for (final r in _toRecipients) {
        _lookupFullName(r);
      }
    }
    return _greetingSet().text(v);
  }

  /// Тексты всех вариантов приветствия для нынешних адресатов «Кому» — на
  /// языке приложения или адресата (кириллица — русский). Строк этого
  /// языка ещё нет в памяти — пока английские, после загрузки приветствие
  /// обновится само.
  GreetingSet _greetingSet() {
    final acc = _fromAccount;
    final set = GreetingHelper.variants(
      names: [
        for (final r in _toRecipients) _fullNames[r.email.toLowerCase()] ?? r.displayName ?? '',
      ],
      emails: [for (final r in _toRecipients) r.email],
      appLang: ref.read(settingsProvider).locale.languageCode,
      ownDomains: acc == null ? const {} : OwnAddresses.domains(acc),
    );
    if (!StringsStore.isLoaded(set.lang)) {
      unawaited(StringsStore.ensure(set.lang).then((_) {
        if (mounted) _updateGreeting();
      }));
    }
    return set;
  }

  /// Вариант, который сейчас в письме.
  GreetingVariant get _greetingVariantNow {
    if (_greetPick != null) return _greetPick!;
    final mode = ref.read(greetingModeProvider.notifier).of(_fromAccount?.id);
    return switch (mode) {
      GreetingMode.off => GreetingVariant.none,
      GreetingMode.hello => GreetingVariant.hello,
      GreetingMode.helloName => _wroteInThread ? GreetingVariant.short : GreetingVariant.full,
    };
  }

  /// Кнопка «Приветствие» над текстом письма: все варианты для нынешних
  /// адресатов — полное, короткое, без имени, без приветствия (просьба
  /// владельца 25.10.2026: «рядом с приветствием — кнопка переключения
  /// вариантов»). Выбор заменяет первую строку письма, даже если её правили.
  Widget _greetingChip(ThemeData theme, AppLocalizations l10n) {
    final set = _greetingSet();
    final now = _greetingVariantNow;
    final nowText = set.text(now);
    final scheme = theme.colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppMenuButton<GreetingVariant>(
        tooltip: l10n.tr('greetingChipHint'),
        onSelected: (v) {
          setState(() => _greetPick = v);
          _updateGreeting(force: true);
          _markDraftChanged();
        },
        itemBuilder: (_) => [
          for (final (v, text) in set.choices)
            AppMenuEntry(
              value: v,
              label: v == GreetingVariant.none ? l10n.tr('greetingOff') : text,
              checked: v == now || (text.isNotEmpty && text == nowText),
            ),
        ],
        child: ConstrainedBox(
          // Палец попадает и в узкую строку: высота не меньше 40.
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(AppIcons.waving_hand, size: 16, color: scheme.primary),
            const SizedBox(width: Space.xs),
            Text(l10n.tr('greetingChip'),
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
            Icon(AppIcons.expand_more, size: 18, color: scheme.primary),
          ]),
        ),
      ),
    );
  }

  static bool _hasPatronymic(String name) =>
      RegExp(r'(ович|евич|ьич|овна|евна|ична|инична)(?=[\s,]|$)', caseSensitive: false)
          .hasMatch(GreetingHelper.cleanName(name).toLowerCase());

  /// Найти ФИО адресата с отчеством: другие записи того же адреса в базе
  /// (карточка Exchange, адресная книга, CardDAV), затем адресная книга
  /// организации. Нашли — обновляем приветствие.
  void _lookupFullName(EmailAddress r) {
    final key = r.email.trim().toLowerCase();
    if (key.isEmpty || _fullNames.containsKey(key) || !_fullNameLookups.add(key)) return;
    if (_hasPatronymic(r.displayName ?? '')) return;
    final acc = _fromAccount;
    unawaited(() async {
      String? found;
      try {
        final db = ref.read(databaseProvider);
        final rows = await db.customSelect(
          'SELECT display_name, first_name, middle_name, last_name FROM contacts '
          'WHERE lower(email) = ? LIMIT 10',
          variables: [Variable.withString(key)],
        ).get();
        for (final row in rows) {
          final first = row.readNullable<String>('first_name')?.trim() ?? '';
          final middle = row.readNullable<String>('middle_name')?.trim() ?? '';
          final last = row.readNullable<String>('last_name')?.trim() ?? '';
          if (first.isNotEmpty && middle.isNotEmpty) {
            found = '$last $first $middle'.trim();
            break;
          }
          final dn = row.read<String>('display_name');
          if (_hasPatronymic(dn)) {
            found = dn;
            break;
          }
        }
        if (found == null && acc != null && acc.isMsExchange) {
          final gal = await ref
              .read(mailEngineServiceProvider)
              .resolveNames(acc, key)
              .timeout(const Duration(seconds: 10));
          for (final c in gal) {
            if (c.email.toLowerCase() != key) continue;
            if ((c.firstName ?? '').isNotEmpty && (c.middleName ?? '').isNotEmpty) {
              found = '${c.lastName ?? ''} ${c.firstName} ${c.middleName}'.trim();
              break;
            }
            if (_hasPatronymic(c.displayName)) {
              found = c.displayName;
              break;
            }
          }
        }
      } catch (_) {}
      if (found == null || !mounted) return;
      _fullNames[key] = found;
      _updateGreeting();
    }());
  }

  /// Подпись ящика для этого письма (новое — или ответ/пересылка): выбор на
  /// экране «Подписи» аккаунта. null — без подписи.
  ({String html, String plain})? _signatureFor(AccountModel? acc) {
    if (acc == null) return null;
    final def = SignatureChoicesNotifier.resolve(
        ref.read(signaturesProvider), ref.read(signatureChoicesProvider), acc.id,
        reply: _isReplyOrForward);
    if (def == null || (def.htmlContent.trim().isEmpty && def.plainContent.trim().isEmpty)) {
      return null;
    }
    // Переменные подписи ({name}, {title}, {phone}…) — из карточки
    // владельца в адресной книге организации.
    return (
      // Подписи по умолчанию раньше были серыми и мельче (color:#666;
      // font-size:12px) — шрифт и размер не совпадали с текстом письма.
      // Сохранённые с тем оформлением подписи выравниваем при вставке.
      html: _renderSignature(
          (def.htmlContent.isNotEmpty ? def.htmlContent : def.plainContent.replaceAll('\n', '<br>'))
              .replaceAll(RegExp(r'color:\s*#666;?\s*font-size:\s*12px;?\s*'), ''),
          html: true, account: acc),
      plain: _renderSignature(
          def.plainContent.isNotEmpty ? def.plainContent : _htmlToPlain(def.htmlContent),
          html: false, account: acc),
    );
  }

  /// Сменился ящик «От»: автоматическая подпись — на подпись этого ящика.
  void _onFromChanged(AccountModel acc) {
    final changed = _fromAccount?.id != acc.id;
    setState(() {
      _fromAccount = acc;
      if (changed) _fromAlias = null;
    });
    if (changed) {
      _smimeAvailable = false;
      unawaited(_loadSmime());
    }
    if (changed && _useHtmlEditor) _editor.setBodyStyle(_style.css);
    if (!changed || !_autoSignature || !_useHtmlEditor) return;
    final sig = ref.read(settingsProvider).autoInsertSignature ? _signatureFor(acc) : null;
    _editor.setSignature(sig?.html ?? '');
  }

  /// Загрузить черновик в форму: адресаты, тема, текст, файлы.
  Future<void> _initFromDraft(String id, {String? accountId}) async {
    try {
      final row = await ref.read(databaseProvider).getEmailById(id, accountId: accountId ?? widget.accountId);
      if (row == null || !mounted) return;
      final local = row.folderId == 'drafts';
      if (local && id != _draftId) {
        // Свой черновик под другим id (письмо, отправку которого отменили, —
        // «undosend_…»): продолжаем под его id. Раньше правка сохранялась
        // новым черновиком, а прежний оставался второй копией.
        _draftSync.endEdit(_draftId);
        _draftId = id;
        _draftSync.beginEdit(_draftId);
      }
      if (!local) _serverDraft = (id: row.id, folderId: row.folderId);
      await _fillFromDraft(row, local: local);
      if (!mounted) return;
      // Черновик как загружен: закрыли, ничего не меняя, — он остаётся как
      // был (раньше каждое открытие пересохраняло и заново выгружало его).
      _markPristine();
      _openedDraft = true;
      _pristineSaved = false;
      _markDraftChanged();
      if (!local) unawaited(_completeServerDraft(row));
      await _restoreParent(row);
    } catch (e) {
      AppLogger.warning('Черновик не открылся: $e');
    }
  }

  /// Поля письма из строки черновика. Свой черновик хранит в bodyPlain то,
  /// что было в редакторе (HTML, если редактор с оформлением), и свои файлы
  /// (1.7.2+111); у серверного — обычные поля и вложения сервера.
  Future<void> _fillFromDraft(Email row, {required bool local}) async {
    List<EmailAddress> parse(String? json) {
      if (json == null || json.isEmpty) return const [];
      try {
        return [
          for (final m in (jsonDecode(json) as List).cast<Map>())
            if ((m['email'] ?? '').toString().isNotEmpty)
              EmailAddress(
                email: m['email'].toString(),
                displayName: (m['displayName'] ?? m['name'])?.toString(),
              ),
        ];
      } catch (_) {
        return const [];
      }
    }

    final body = local ? (row.bodyPlain ?? '') : (row.bodyHtml ?? row.bodyPlain ?? '');
    final looksHtml = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(body);
    final files = local ? await DraftFiles.load(row.attachmentsJson) : null;
    if (!mounted) return;
    setState(() {
      _toRecipients
        ..clear()
        ..addAll(parse(row.toRecipients));
      _ccRecipients
        ..clear()
        ..addAll(parse(row.ccJson));
      _bccRecipients
        ..clear()
        ..addAll(parse(row.bccJson));
      _showCc = _ccRecipients.isNotEmpty;
      _showBcc = _bccRecipients.isNotEmpty;
      _subjectController.text = row.subject;
      // Отметки S/MIME черновика.
      final label = MailLabel.decode(row.sensitivity);
      if (label.smime) {
        _smimeTouched = true;
        _smimeSign = label.smimeSign;
        _smimeEncrypt = label.smimeEncrypt;
      }
      _attachments.clear();
      _pendingOriginal.clear();
      // Файлы своего черновика: с телефона — сразу, не скачанные — плашками
      // (докачиваются в фоне).
      for (final f in files ?? const <DraftFile>[]) {
        if (!f.isRemote) {
          _attachments.add(ChosenFile(name: f.name, size: f.size, path: f.path));
          continue;
        }
        _pendingAccountId ??= f.remoteAccountId;
        _pendingEmailId ??= f.remoteEmailId;
        if (f.remoteEmailId != _pendingEmailId) continue; // одно исходное письмо
        _pendingOriginal.add(_PendingFile(id: f.remoteId!, name: f.name, size: f.size, mimeType: f.mimeType));
      }
    });
    if (looksHtml && _useHtmlEditor) {
      unawaited(_editor.setHtml(_toEditor(body)));
      _lastHtml = body;
    } else {
      _setBodyPlain(looksHtml ? _htmlToPlain(body) : body);
    }
    if (_pendingOriginal.isNotEmpty) unawaited(_prefetchPending());
    // Вложения черновика из серверной папки (начат в Outlook или
    // веб-почте) — плашками, как у пересылки: раньше при отправке такого
    // черновика файлы терялись.
    if (!local && (row.attachmentsJson ?? '').isNotEmpty) {
      await _attachOriginal(row);
      if (mounted) setState(() {});
    }
  }

  /// Черновик из серверной папки: недостающее (у Exchange список писем не
  /// несёт адресатов, текста и файлов) — с сервера (1.7.2+111). Раньше такой
  /// черновик открывался пустым, а после правки пустая версия заменяла
  /// настоящую. Пока письмо не трогали — поля заполняются заново; начали
  /// править раньше, чем пришёл ответ, или догрузить не удалось — прежняя
  /// копия на сервере не удаляется (в ней может быть то, чего нет на экране).
  Future<void> _completeServerDraft(Email row) async {
    final acc = ref.read(accountsProvider).where((a) => a.id == row.accountId).firstOrNull;
    final sd = _serverDraft;
    if (acc == null || sd == null) return;
    final done = await _draftSync.completeServerDraft(acc, row);
    if (!mounted || _sentOrDiscarded || _serverDraft != sd) return;
    var complete = done.complete;
    if (!identical(done.row, row)) {
      if (_isPristine) {
        await _fillFromDraft(done.row, local: false);
        if (!mounted) return;
        _markPristine();
        _markDraftChanged();
      } else {
        complete = false;
      }
    }
    if (complete) {
      // Новая версия заменит эту копию при выгрузке.
      unawaited(_draftSync.rememberReplace(_draftId, sd));
    } else {
      AppLogger.warning('Черновик с сервера открыт не целиком — прежняя копия на сервере сохранится');
    }
  }

  /// На что отвечает открытый черновик: своя запись (parent_id) или начатый
  /// ответ с той же темой. Нашлось исходное письмо — ответ снова встаёт в
  /// его цепочку (In-Reply-To), а после отправки письмо получит отметку
  /// «Отвечено» (раньше ответ из «Черновиков» уходил новой перепиской).
  Future<void> _restoreParent(Email row) async {
    if (_parentId == null) {
      final p = DraftData.parseParentRef(row.parentId);
      if (p != null) {
        _parentId = p.emailId;
        _parentAccountId = p.accountId;
        _parentForward = p.forward;
      } else {
        final r = _replyDrafts.byDraftSubject(row.accountId, row.subject);
        if (r != null) {
          _parentId = r.emailId;
          _parentAccountId = r.accountId;
          _parentForward = r.forward;
          _parentConversationId = r.conversationId;
        }
      }
    }
    final pid = _parentId;
    if (pid == null) return;
    try {
      final orig = await ref.read(databaseProvider).getEmailById(pid, accountId: _parentAccountId);
      if (orig == null || !mounted) return;
      _parentConversationId ??= orig.conversationId;
      final mid = orig.internetMessageId?.trim();
      if (!_parentForward && _inReplyTo == null && mid != null && mid.contains('@')) {
        final refs = orig.referencesStr?.trim() ?? '';
        _inReplyTo = refs.isEmpty ? mid : '$refs $mid';
      }
      // Пересылка, продолженная из «Черновиков»: черновик прежних версий
      // файлов не хранил — файлы исходного письма снова плашками. Черновик
      // 1.7.2+111 хранит их сам (в том числе «все убрали»).
      if (_parentForward && _attachments.isEmpty && _pendingOriginal.isEmpty &&
          row.attachmentsJson == null && !row.hasAttachments) {
        final was = _isPristine;
        await _attachOriginal(orig);
        if (was) _markPristine();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _editorWatch?.cancel();
    // Дослать черновик ДО освобождения контроллеров: снимок уже сделан в
    // _markDraftChanged, forceSave лишь пишет его в БД. Пустой черновик сервис
    // не сохраняет (проверка isEmpty внутри).
    // forceSave берёт снимок синхронно, до первого await, поэтому вызывается
    // раньше stopAutosave (тот обнуляет снимок — сохранять было бы нечего).
    _noneTimer?.cancel();
    _draftSync.endEdit(_draftId);
    _autosave?.savedAt.removeListener(_onDraftSaved);
    if (!_sentOrDiscarded) {
      // Сохранить локально, затем выгрузить в серверные «Черновики» (видно
      // в Outlook и веб-почте). Без сети — выгрузка при синхронизации.
      final accId = _fromAccount?.id;
      final sync = _draftSync;
      final id = _draftId;
      final autosave = _autosave;
      if (_openedDraft && _isPristine) {
        if (_pristineSaved) {
          // Как сохранили кнопкой «Сохранить» — эту версию и выгружаем
          // (записав заново: таймер мог сохранить промежуточную правку).
          autosave?.updateDraft(_snapshot(force: true));
          unawaited((autosave?.forceSave() ?? Future.value(false)).then((_) async {
            if (accId != null) await sync.upload(id, accId);
          }));
        } else if (_serverDraft != null) {
          // Открытый из серверной папки черновик не меняли (или вернули как
          // было): серверная копия и есть он; промежуточная локальная — не нужна.
          unawaited(sync.forget(id));
          if (accId != null) unawaited(autosave?.deleteDraft(id, accId));
        } else if (_localSaved) {
          // Свой черновик правили и вернули как было — записать как есть.
          autosave?.updateDraft(_snapshot(force: true));
          unawaited((autosave?.forceSave() ?? Future.value(false)).then((_) async {
            if (accId != null) await sync.upload(id, accId);
          }));
        } else if (accId != null) {
          // Свой, ещё не выгруженный (например, без сети), — выгружается.
          unawaited(sync.upload(id, accId));
        }
      } else if (_snapshot().isEmpty) {
        // Всё стёрли: черновика нет — и прежней автосохранённой копии тоже.
        if (accId != null) unawaited(autosave?.deleteDraft(id, accId));
        unawaited(sync.forget(id));
      } else {
        _rememberReplyDraft();
        // Свежий снимок: адресатов (плашки) правка полей не отмечала — без
        // него в черновик попадало состояние до последнего добавленного
        // получателя.
        autosave?.updateDraft(_snapshot());
        unawaited((autosave?.forceSave() ?? Future.value(false)).then((_) async {
          if (accId != null) await sync.upload(id, accId);
        }));
      }
    }
    _autosave?.stopAutosave();

    _subjectController.removeListener(_markDraftChanged);
    _plainController.removeListener(_markDraftChanged);
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _plainController.dispose();
    _bodyFocusNode.dispose();
    _subjectFocus.dispose();
    _toFocus.dispose();
    _ccFocus.dispose();
    _bccFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    _resolveRecipientNames();

    // Системное «Назад» и жест — как крестик (1.7.0): несохранённое письмо не
    // закрывается молча, а спрашивает, сохранить ли черновик.
    // Клавиатура компьютера и планшета (1.8.13), как в Outlook и Почте Mac:
    // Ctrl+Enter (⌘+Enter) — отправить, Ctrl+S (⌘+S) — сохранить черновик,
    // Esc — закрыть (с вопросом о черновике). В тексте письма — через
    // редактор (MailEditor.onKey).
    void send() {
      if (!_isSending) unawaited(_onSend(l10n, settings));
    }
    void save() {
      if (!_isSending) unawaited(_saveDraftNow(l10n));
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): send,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): send,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): save,
        const SingleActivator(LogicalKeyboardKey.escape): () => _onDiscard(l10n),
      },
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onDiscard(l10n);
      },
      child: Scaffold(
      // Под шторкой (подбор адресатов) или окном экран письма не подстраивается
      // под клавиатуру (1.6.19): иначе он вместе с редактором в WebView
      // перестраивался в каждом кадре её появления, и шторка ехала рывками.
      resizeToAvoidBottomInset: ModalRoute.of(context)?.isCurrent ?? true,
      // Белый (светлая тема) или фон темы — как у открытого письма.
      backgroundColor: mailPageColor(Theme.of(context)),
      appBar: TextScaleCapBar(child: AppBar(
        backgroundColor: mailPageColor(Theme.of(context)),
        leading: IconButton(
          tooltip: l10n.tr('cancel'),
          icon: const Icon(AppIcons.close),
          onPressed: () => _onDiscard(l10n),
        ),
        titleSpacing: 0,
        // Шесть значков в заголовке обрезали название («Ново…»): редкие
        // действия — в меню «⋮», на виду только отправка и метки письма.
        title: _titleWithSaved(l10n),
        actions: [
          // «Сохранить черновик» — на виду (1.7.0): сохраняет на телефоне
          // сразу; в серверные «Черновики» письмо уходит при закрытии окна.
          IconButton(
            tooltip: l10n.tr('saveDraft'),
            icon: const Icon(AppIcons.save),
            onPressed: _isSending ? null : () => unawaited(_saveDraftNow(l10n)),
          ),
          if (_importance != 'Normal')
            IconButton(
              tooltip: l10n.tr('importance'),
              icon: Icon(_importance == 'High' ? AppIcons.priority_high : AppIcons.low_priority,
                  color: _importance == 'High' ? AppColors.errorRed : null),
              onPressed: () => _pickImportance(l10n),
            ),
          // Подпись / шифрование S/MIME включены — значок; нажатие —
          // переключатели S/MIME (раньше — в шторке грифа, гриф убран в 1.5.9).
          if (_smimeActive)
            IconButton(
              tooltip: l10n.tr(_smimeEncrypt ? 'smimeEncrypt' : 'smimeSign'),
              icon: Icon(_smimeEncrypt ? AppIcons.shield : AppIcons.verified_user,
                  color: Theme.of(context).colorScheme.primary),
              onPressed: () => unawaited(_pickSmime(l10n)),
            ),
          // «Отправить» — внизу, под большим пальцем (решение владельца
          // 08.10.2026, по образцу Ogneliss Dialer).
          AppMenuButton<String>(
            tooltip: l10n.tr('more'),
            onSelected: (v) {
              switch (v) {
                case 'later':
                  if (!_isSending) _onScheduleSend(l10n, settings);
                case 'importance':
                  _pickImportance(l10n);
                case 'smime':
                  unawaited(_pickSmime(l10n));
                case 'groups':
                  _showGroupsSheet(l10n);
                case 'signature':
                  _showSignaturePicker(l10n);
                case 'bcc':
                  _openField(_bccController);
                case 'control':
                  setState(() => _control = !_control);
              }
            },
            itemBuilder: (_) => [
              _menuItem('later', AppIcons.schedule_send, l10n.tr('scheduleSend')),
              _menuItem('importance', AppIcons.flag, l10n.tr('importance')),
              _menuItem('groups', AppIcons.groups, l10n.tr('distributionGroups')),
              _menuItem('signature', AppIcons.draw, l10n.tr('insertSignature')),
              // S/MIME — раньше в шторке грифа (гриф убран в 1.5.9).
              if (_smimeAvailable) _menuItem('smime', AppIcons.verified_user, l10n.tr('smimeSection')),
              if (!_showBcc && _bccRecipients.isEmpty)
                _menuItem('bcc', AppIcons.visibility_off, l10n.tr('bcc')),
              if (ref.read(settingsProvider).mailControl)
                AppMenuEntry(
                  value: 'control',
                  icon: AppIcons.task_alt,
                  label: l10n.tr('controlOnSend'),
                  checked: _control,
                ),
            ],
          ),
        ],
      )),

      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // From
                  _buildFromField(theme, l10n),
                  _sharedMailboxNotice(theme, l10n),
                  const Divider(height: 1),

                  // Кому / Копия / Скрытая
                  _buildRecipientField(
                    controller: _toController,
                    focusNode: _toFocus,
                    label: l10n.tr('to'), icon: AppIcons.person,
                    recipients: _toRecipients,
                    theme: theme,
                    l10n: l10n,
                    trailing: (!_showCc && _ccRecipients.isEmpty)
                        ? _fieldToggle(theme, l10n.tr('cc'), () => _openField(_ccController))
                        : null,
                  ),
                  if (_toError != null && _toRecipients.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xxl + Space.s, bottom: Space.xs),
                      child: Text(_toError!,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                    ),
                  if (_suggestFor == _toController) _buildSuggestions(theme),
                  if (_badAddress != null)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xxl + Space.s, bottom: Space.xs, right: Space.s),
                      child: Text(l10n.tr('composeBadAddress').replaceAll('{addr}', _badAddress!),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                    ),
                  const Divider(height: 1),
                  if (_showCc || _ccRecipients.isNotEmpty) ...[
                    _buildRecipientField(
                      controller: _ccController,
                      focusNode: _ccFocus,
                      label: l10n.tr('cc'), icon: AppIcons.group,
                      recipients: _ccRecipients,
                      theme: theme,
                      l10n: l10n,
                      trailing: (!_showBcc && _bccRecipients.isEmpty)
                          ? _fieldToggle(theme, l10n.tr('bcc'), () => _openField(_bccController))
                          : null,
                    ),
                    if (_suggestFor == _ccController) _buildSuggestions(theme),
                    const Divider(height: 1),
                  ],
                  if (_showBcc || _bccRecipients.isNotEmpty) ...[
                    _buildRecipientField(
                      controller: _bccController,
                      focusNode: _bccFocus,
                      label: l10n.tr('bcc'), icon: AppIcons.visibility_off,
                      recipients: _bccRecipients,
                      theme: theme,
                      l10n: l10n,
                    ),
                    if (_suggestFor == _bccController) _buildSuggestions(theme),
                    const Divider(height: 1),
                  ],

                  // Подсказки Exchange об адресатах (автоответ, переполненный
                  // ящик, большая рассылка) — 1.6.49.
                  MailTipsStrip(
                    account: _fromAccount,
                    emails: [
                      for (final l in [_toRecipients, _ccRecipients, _bccRecipients])
                        for (final a in l) a.email,
                    ],
                  ),

                  // Subject
                  TextField(
                    controller: _subjectController,
                    focusNode: _subjectFocus,
                    showCursor: !_caretInBody,
                    onTap: _caretToHeader,
                    decoration: InputDecoration(
                      hintText: l10n.tr('subject'),
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: theme.textTheme.titleMedium,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const Divider(height: 1),

                  // Вложения — под темой, компактными плашками: раньше они
                  // стояли строками списка под редактором и цитатой, и без
                  // прокрутки их было не видно.
                  // Строка размера — и без вложений, если текст с картинками
                  // и цитата тяжелее 1 МБ.
                  if (_attachments.isNotEmpty || _pendingOriginal.isNotEmpty || _messageBytes >= 1024 * 1024)
                    _buildAttachments(theme, l10n),

                  // «Приветствие ▾» — варианты приветствия первой строки.
                  if (_greetingPlaced) _greetingChip(theme, l10n),

                  // Редактор тела: HugeRTE (таблицы, списки, вставка с
                  // оформлением); простое поле — на Linux и при сбое загрузки.
                  if (_useHtmlEditor)
                    MailEditor(
                      key: _editorKey,
                      controller: _editor,
                      placeholder: l10n.tr('messageBodyHint'),
                      // Половина экрана (не меньше 260): на большом телефоне
                      // поле не обрывается посередине, на маленьком влезает.
                      height: (MediaQuery.sizeOf(context).height * 0.5).clamp(260.0, 640.0),
                      bodyStyle: _style.css,
                      toolbarHidden: !(_showFormatting ??= MediaQuery.sizeOf(context).width >= 700),
                      onChanged: (html) {
                        _lastHtml = _fromEditor(html);
                        // Без этого правки тела не попадали бы в автосохранение:
                        // слушатели висят только на текстовых полях.
                        _markDraftChanged();
                        // Картинка вставлена в текст или убрана — пересчитать
                        // строку размера письма (обычный набор её не трогает).
                        if ((_lastHtml.length - _sizeShownBody).abs() >= 256 * 1024 && mounted) {
                          setState(() => _sizeShownBody = _lastHtml.length);
                        }
                      },
                      onFailed: () {
                        if (!mounted) return;
                        // Текст, набранный до сбоя, переносится в простое поле.
                        _plainController.text = _htmlToPlain(_lastHtml);
                        setState(() => _editorFailed = true);
                      },
                      onPickImage: pickInlineImageDataUri,
                      onFocus: _onEditorFocus,
                      onKey: (k) {
                        if (_isSending) return;
                        if (k == 'send') unawaited(_onSend(l10n, settings));
                        if (k == 'save') unawaited(_saveDraftNow(l10n));
                      },
                    )
                  else
                    // Фолбэк (Linux / без WebView): простой текстовый редактор.
                    // Отправляется как HTML (переводы строк → <br>). Упрощённо, как договорено.
                    // Как поле темы — без серой подложки и своих полей: на
                    // компьютере текст письма был серым прямоугольником с
                    // отступами, не похожим на остальной экран (28.10.2026).
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 220),
                      child: TextField(
                        controller: _plainController,
                        focusNode: _bodyFocusNode,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(vertical: Space.m),
                          hintText: l10n.tr('messageBodyHint'),
                        ),
                        maxLines: null,
                        minLines: 10,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),

                  // Исходное письмо — под редактором, только для чтения.
                  if (_quoteHtml != null) ...[
                    const Divider(height: 1),
                    // Одна строка: «Исходное письмо ▾» и меню «⋮» (изменить,
                    // убрать) — раньше две кнопки и значок раздували строку.
                    InkWell(
                      onTap: () => setState(() => _quoteExpanded = !_quoteExpanded),
                      child: Row(
                        children: [
                          Icon(AppIcons.originalMessage, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Text(l10n.tr('quoteOriginal'),
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ),
                          Icon(_quoteExpanded ? AppIcons.expand_less : AppIcons.expand_more,
                              size: 20, color: theme.colorScheme.onSurfaceVariant),
                          AppMenuButton<String>(
                            tooltip: l10n.tr('more'),
                            icon: const Icon(AppIcons.more_vert, size: 20),
                            onSelected: (v) => v == 'edit' ? _editQuote() : _removeQuote(),
                            itemBuilder: (_) => [
                              AppMenuEntry(value: 'edit', icon: AppIcons.edit, label: l10n.tr('quoteEdit')),
                              AppMenuEntry(value: 'remove', icon: AppIcons.format_clear, label: l10n.tr('quoteRemove')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_quoteExpanded)
                      Padding(
                        padding: EdgeInsets.zero,
                        child: _quoteDoc != null
                            ? MailHtmlView(
                                document: _quoteDoc!,
                                allowRemoteImages: false,
                                onLink: (url, text) => LinkOpener.open(context, url,
                                    linkText: text, accountId: _fromAccount?.id),
                              )
                            : Text(_htmlToPlain(_quoteHtml!), style: theme.textTheme.bodySmall),
                      ),
                  ],


                ],
              ),
            ),
          ),

          // Smart Compose — над нижней панелью: под редактором и цитатой
          // подсказки уходили за край экрана.
          // Подсказки вставки фраз: с подписью «Вставить:» и кнопкой «закрыть»
          // (раньше одинокая кнопка «✦ E-mail: …» внизу была непонятна).
          if (_composeSuggestions.isNotEmpty)
            SizedBox(
              height: 24 + 16 * context.textScale.clamp(1.0, TextScaleLimits.app),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(left: Space.m),
                  child: Text(l10n.tr('composeSuggestInsert'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                Expanded(child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
                itemCount: _composeSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.s),
                itemBuilder: (context, i) {
                  final s = _composeSuggestions[i];
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(AppIcons.auto_awesome, size: 16, color: AppColors.accent(context)),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(s.text, overflow: TextOverflow.ellipsis),
                    ),
                    onPressed: () => _applySuggestion(s),
                  );
                },
              )),
                IconButton(
                  tooltip: l10n.tr('close'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(AppIcons.close, size: 18),
                  onPressed: () => setState(() => _composeSuggestions = const []),
                ),
              ]),
            ),

          // Нижняя панель
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              // Плоская панель с тонкой линией сверху (1.8.0, «воздушный»
              // вид); тень — в высококонтрастной теме.
              border: OgnelissLook.of(context).outlined
                  ? null
                  : Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
              boxShadow: OgnelissLook.of(context).outlined
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -1))]
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.s, Space.xs),
            child: Row(
              children: [
                // Инструменты прокручиваются, если не помещаются (узкий
                // экран, крупный шрифт), — «Отправить» всегда на месте справа.
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                IconButton(icon: const Icon(AppIcons.attach_file), onPressed: _pickAttachments, tooltip: l10n.tr('attachFile')),
                IconButton(
                  icon: const Icon(AppIcons.article),
                  onPressed: _insertTemplate,
                  tooltip: l10n.tr('templates'),
                ),
                // Свой значок (облачко с молнией): рядом с «Шаблонами» два
                // похожих листка путались.
                IconButton(
                  icon: const Icon(AppIcons.quickreply),
                  onPressed: () => _showTemplates(l10n),
                  tooltip: l10n.tr('quickPhrases'),
                ),
                IconButton(
                  icon: const Icon(AppIcons.draw),
                  onPressed: () => _showSignaturePicker(l10n),
                  tooltip: l10n.tr('insertSignature'),
                ),
                // «Отправить позже» — под рукой внизу (Ф5, docs/plan/UI_REDESIGN.md);
                // раньше только в меню «⋮» вверху.
                // 1.6.49: те же быстрые варианты, что и по удержанию
                // «Отправить» (через час, завтра в 9…), и «Выбрать время».
                Builder(
                  builder: (button) => IconButton(
                    icon: const Icon(AppIcons.schedule_send),
                    onPressed: _isSending ? null : () => _sendLaterMenu(button, l10n, settings),
                    tooltip: l10n.tr('scheduleSend'),
                  ),
                ),
                // «Aa» — панель форматирования (жирный, списки, цвет…).
                if (_useHtmlEditor)
                  IconButton(
                    tooltip: l10n.tr('formatting'),
                    isSelected: _showFormatting ?? false,
                    icon: const Icon(AppIcons.text_format),
                    selectedIcon: Icon(AppIcons.text_format, color: theme.colorScheme.primary),
                    onPressed: () {
                      final v = !(_showFormatting ?? false);
                      setState(() => _showFormatting = v);
                      _editor.showToolbar(v);
                    },
                  ),
                    ]),
                  ),
                ),
                const SizedBox(width: Space.s),
                _sendButton(l10n, settings),
              ],
            ),
          ),
        ],
      ),
    )));
  }

  /// «Отправить»: на широком экране — с подписью, на узком — значок.
  /// Удержание (1.6.49, как в Telegram) — меню над кнопкой: через час,
  /// сегодня вечером, завтра в 9, в понедельник, «Выбрать дату и время»;
  /// палец можно довести до пункта и отпустить. Раньше удержание сразу
  /// открывало барабаны.
  Widget _sendButton(AppLocalizations l10n, AppSettings settings) {
    final busy = _isSending || _shrinking;
    final icon = busy
        ? SizedBox(
            width: Sizes.iconRow,
            height: Sizes.iconRow,
            child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
          )
        : const Icon(AppIcons.send);
    void send() => _onSend(l10n, settings);
    final wide = MediaQuery.sizeOf(context).width >= 400;
    // Без всплывающей подсказки: она тоже открывается долгим нажатием и
    // перехватывала бы меню.
    return Semantics(
      onLongPressHint: l10n.tr('scheduleSend'),
      child: Builder(
        builder: (button) => QuickLongPress(
          onLongPress: busy
              ? null
              : () {
                  unawaited(HapticFeedback.mediumImpact());
                  _sendLaterMenu(button, l10n, settings);
                },
          tracker: HoldPointer.instance,
          child: wide
              ? FilledButton.icon(
                  onPressed: busy ? null : send,
                  icon: icon,
                  label: Text(l10n.tr('send')),
                )
              : IconButton.filled(
                  onPressed: busy ? null : send,
                  icon: Semantics(label: l10n.tr('send'), child: icon),
                ),
        ),
      ),
    );
  }

  /// Меню «Отправить позже» над кнопкой [button].
  void _sendLaterMenu(BuildContext button, AppLocalizations l10n, AppSettings settings) {
    if (_isSending) return;
    final anchor = peekAnchorOf(button);
    final presets = SendLaterPresets.of(DateTime.now());
    final items = <PeekAction>[
      for (final p in presets)
        PeekAction(
          icon: p.key == 'inHour' ? AppIcons.schedule : AppIcons.schedule_send,
          label: l10n.tr(SendLaterPresets.labelKey(p)).replaceAll('{time}', AppDateFormat.time(context, p.at)),
          onTap: () => unawaited(_onScheduleSend(l10n, settings, at: p.at)),
        ),
      PeekAction(
        icon: AppIcons.calendar_month,
        label: l10n.tr('schedPick'),
        onTap: () => unawaited(_onScheduleSend(l10n, settings)),
      ),
    ];
    if (anchor == null) {
      unawaited(_onScheduleSend(l10n, settings));
      return;
    }
    unawaited(showHoldMenu(context, anchor: anchor, items: items));
  }

  // ════════════════════════ ПОЛЯ ════════════════════════

  /// Вложения плашками: значок типа, имя, размер, «×». Под ними — строка
  /// размера письма: «Письмо: 4,2 МБ из 25 МБ · можно добавить ещё 20,8 МБ»
  /// и полоска (1.7.2+110; раньше полоска появлялась только от 70 % лимита,
  /// и владелец её не находил).
  Widget _buildAttachments(ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    IconData iconFor(String name) {
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      return switch (ext) {
        'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' => AppIcons.image,
        'pdf' => AppIcons.picture_as_pdf,
        'doc' || 'docx' || 'rtf' || 'odt' || 'txt' => AppIcons.description,
        'xls' || 'xlsx' || 'csv' || 'ods' => AppIcons.table_chart,
        'ppt' || 'pptx' || 'odp' => AppIcons.slideshow,
        'zip' || 'rar' || '7z' => AppIcons.folder_zip,
        _ => AppIcons.insert_drive_file,
      };
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              for (final f in _attachments) _fileChip(f, theme, l10n, iconFor(f.name)),
              // Файлы пересылаемого письма, ещё не скачанные (1.6.18).
              for (final p in _pendingOriginal)
                Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, 0, Space.xs),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: Radii.chipAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(p.failed ? AppIcons.warning : AppIcons.download,
                            size: 18, color: p.failed ? AppColors.errorRed : scheme.primary),
                      const SizedBox(width: Space.xs + 2),
                      Flexible(
                        child: InkWell(
                          // Не скачался — повторить касанием.
                          onTap: p.failed && !p.loading ? () => unawaited(_fetchPending(p)) : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                              Text(
                                  p.loading
                                      ? l10n.tr('attPendingLoading')
                                      : p.failed
                                          ? l10n.tr('attPendingFailed')
                                          : l10n.tr('attPendingWaiting'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: p.failed ? AppColors.errorRed : scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tr('delete'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        icon: const Icon(AppIcons.close),
                        onPressed: () {
                          setState(() => _pendingOriginal.remove(p));
                          _markDraftChanged();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
          _sizeLine(theme, l10n),
        ],
      ),
    );
  }

  // ───────────── Фото во вложениях: открыть, сжать, обрезать и повернуть ─────────────
  // 1.7.2+113, просьба владельца 25.10.2026: касание фото — карточка с
  // размытым фоном, как карточка письма по удержанию: «Открыть», «Сжать»,
  // «Обрезать и повернуть». Касание другого файла — открыть его.

  /// Плашка приложенного файла: у фото — миниатюра; пока фото уменьшается
  /// или сохраняется после правки — крутилка.
  Widget _fileChip(ChosenFile f, ThemeData theme, AppLocalizations l10n, IconData icon) {
    final scheme = theme.colorScheme;
    final busy = _editingFiles.contains(f);
    final size = formatBytes(f.size, l10n);
    return Builder(
      builder: (chipCtx) => Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.chipAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => unawaited(_onFileTap(f, peekAnchorOf(chipCtx))),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, 0, Space.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  _fileThumb(f, Icon(icon, size: 18, color: scheme.primary)),
                const SizedBox(width: Space.xs + 2),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                      Text(_isShrunk(f) ? '$size · ${l10n.tr('imageShrunkMark')}' : size,
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.tr('delete'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(AppIcons.close),
                  onPressed: busy
                      ? null
                      : () {
                          setState(() => _attachments.remove(f));
                          _markDraftChanged();
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Картинка файла для показа (с телефона или из памяти); null — не фото.
  ImageProvider<Object>? _imageOf(ChosenFile f) {
    if (!ImageEdit.isEditable(f.name)) return null;
    final path = f.path;
    if (path != null) return FileImage(File(path));
    final bytes = f.bytes;
    return bytes == null ? null : MemoryImage(bytes);
  }

  /// Миниатюра фото на плашке; не фото или не открылось — значок типа.
  Widget _fileThumb(ChosenFile f, Widget fallback) {
    final provider = _imageOf(f);
    if (provider == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: ResizeImage(provider, width: 72),
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Future<void> _onFileTap(ChosenFile f, Rect? anchor) async {
    FocusScope.of(context).unfocus();
    if (_useHtmlEditor) unawaited(_editor.blur());
    if (!ImageEdit.isEditable(f.name)) {
      await _openFile(f);
      return;
    }
    final l10n = AppLocalizations.of(context);
    await showPeekCard(
      context,
      anchor: anchor,
      card: _imagePeek(f, Theme.of(context), l10n),
      // Касание карточки — открыть фото.
      onOpen: () => unawaited(_openFile(f)),
      actions: [
        PeekAction(icon: AppIcons.open_in_new, label: l10n.tr('attOpen'), onTap: () => unawaited(_openFile(f))),
        PeekAction(
            icon: AppIcons.photo_size_select_small,
            label: l10n.tr('attCompress'),
            onTap: () => unawaited(_compressFile(f))),
        PeekAction(icon: AppIcons.crop_rotate, label: l10n.tr('attCropRotate'), onTap: () => unawaited(_editFile(f))),
      ],
    );
  }

  /// Карточка фото: само фото (до 45 % высоты экрана), имя и размер.
  Widget _imagePeek(ChosenFile f, ThemeData theme, AppLocalizations l10n) {
    final provider = _imageOf(f);
    final maxH = MediaQuery.sizeOf(context).height * 0.45;
    final placeholder = SizedBox(
      height: 120,
      child: Center(child: Icon(AppIcons.image, size: 48, color: AppColors.mutedText(context))),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: provider == null
              ? placeholder
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: Image(
                    image: ResizeImage(provider, width: 1080),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => placeholder,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                _isShrunk(f)
                    ? '${formatBytes(f.size, l10n)} · ${l10n.tr('imageShrunkMark')}'
                    : formatBytes(f.size, l10n),
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Временный файл (фото после правки, файл без пути для просмотра).
  Future<String> _writeTemp(String name, Uint8List bytes) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/compose_files');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final file = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Открыть файл — как вложение письма: во внешней программе.
  Future<void> _openFile(ChosenFile f) async {
    final l10n = AppLocalizations.of(context);
    try {
      final path = f.path ?? await _writeTemp(f.name, await f.readBytes());
      if (!mounted) return;
      await openAttachment(
        context,
        PreviewItem(filePath: path, fileName: f.name, sizeBytes: f.size, mimeType: _mimeForName(f.name)),
      );
    } catch (e) {
      AppLogger.warning('Вложение «${f.name}» не открылось: $e');
      showInlineError(l10n.tr('attachFileMissing').replaceAll('{file}', f.name));
    }
  }

  /// «Сжать»: шторка «Размер фото» для одного фото (размеры — всего
  /// письма), фото уменьшается сразу; при отправке его уже не уменьшаем.
  Future<void> _compressFile(ChosenFile f) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final rest = _messageBytes - f.size;
    final scale = await showImageSizeSheet(context, [(name: f.name, size: f.size)],
        other: rest < 0 ? 0 : rest, limit: _sizeLimit().limit);
    if (scale == null || scale >= 1 || !mounted) return;
    setState(() => _editingFiles.add(f));
    try {
      final bytes = await f.readBytes();
      AppLogger.info('Фото: уменьшение вручную до ${(scale * 100).round()}%, '
          '${(bytes.length / 1048576).toStringAsFixed(1)} МБ');
      final r = await ImageShrink.shrink(f.name, bytes, scale);
      if (identical(r.bytes, bytes)) {
        showInlineError(l10n.tr('imageCompressNoGain'));
        return;
      }
      final path = await _writeTemp(r.name, r.bytes);
      _replaceFile(f, ChosenFile(name: r.name, size: r.bytes.length, path: path), shrunk: true);
      AppLogger.info('Фото уменьшено вручную до ${(scale * 100).round()}%: '
          '${(bytes.length / 1048576).toStringAsFixed(1)} → ${(r.bytes.length / 1048576).toStringAsFixed(1)} МБ');
    } catch (e) {
      AppLogger.warning('Фото не уменьшено: $e');
      showInlineError(l10n.tr('imageEditFailed'));
    } finally {
      if (mounted) setState(() => _editingFiles.remove(f));
    }
  }

  /// «Обрезать и повернуть» — редактор; результат заменяет фото в письме.
  Future<void> _editFile(ChosenFile f) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final Uint8List bytes;
    try {
      bytes = await f.readBytes();
    } catch (_) {
      showInlineError(l10n.tr('attachFileMissing').replaceAll('{file}', f.name));
      return;
    }
    if (!mounted) return;
    final r = await ImageEditScreen.open(context, bytes: bytes, name: f.name);
    if (r == null || !mounted) return;
    setState(() => _editingFiles.add(f));
    try {
      final path = await _writeTemp(r.name, r.bytes);
      _replaceFile(f, ChosenFile(name: r.name, size: r.bytes.length, path: path));
    } catch (e) {
      AppLogger.warning('Правка фото не сохранена: $e');
      showInlineError(l10n.tr('imageEditFailed'));
    } finally {
      if (mounted) setState(() => _editingFiles.remove(f));
    }
  }

  /// Заменить файл письма новым (после сжатия или правки) на том же месте.
  /// Уменьшенное фото и после правки остаётся уменьшенным.
  void _replaceFile(ChosenFile old, ChosenFile now, {bool shrunk = false}) {
    if (!mounted) return;
    final i = _attachments.indexOf(old);
    if (i < 0) return; // файл убрали, пока шла правка
    final keepShrunk = shrunk || _isShrunk(old);
    setState(() {
      _attachments[i] = now;
      if (keepShrunk && now.path != null) _shrunkPaths.add(now.path!);
      _fileEdits++;
    });
    _markDraftChanged();
  }

  /// Примерный размер письма: вложения (и ещё не скачанные файлы
  /// пересылаемого письма), текст с вставленными картинками и цитата.
  int get _messageBytes {
    final files = _attachments.fold<int>(0, (s, f) => s + f.size) +
        _pendingOriginal.fold<int>(0, (s, p) => s + p.size);
    final body = _useHtmlEditor ? _lastHtml.length : _plainController.text.length;
    return files + body + (_quoteHtml?.length ?? 0);
  }

  /// Лимит размера письма у ящика «От» и известен ли он от сервера.
  ({int limit, bool known}) _sizeLimit() {
    final id = _fromAccount?.id;
    if (id == null) return (limit: AppConstants.maxAttachmentSize, known: false);
    final store = ref.read(attachmentLimitProvider);
    return (limit: store.limitFor(id), known: store.isKnown(id));
  }

  /// «Письмо: 4,2 МБ из 25 МБ · можно добавить ещё 20,8 МБ» и полоска; от
  /// 80 % — цветом предупреждения, больше лимита — красным, с подсказкой
  /// (с фото — уменьшить их при отправке). «?» — откуда лимит.
  Widget _sizeLine(ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    final (:limit, :known) = _sizeLimit();
    final total = _messageBytes;
    final share = limit > 0 ? total / limit : 0.0;
    final over = total > limit;
    final warn = !over && share >= 0.8;
    final hasPhotos = _attachments.any((f) => ImageShrink.isShrinkable(f.name));
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final color = over
        ? AppColors.errorTextOn(theme)
        : warn
            ? AppColors.warningText(context)
            : scheme.onSurfaceVariant;
    final size = formatBytes(total, l10n), lim = formatBytes(limit, l10n);
    final text = over
        ? l10n.tr('msgSizeOver').replaceAll('{size}', size).replaceAll('{limit}', lim)
            .replaceAll('{over}', formatBytes(total - limit, l10n))
        : l10n.tr('msgSizeLine').replaceAll('{size}', size).replaceAll('{limit}', lim)
            .replaceAll('{left}', formatBytes(limit - total, l10n));
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(text, style: muted?.copyWith(color: color))),
              HelpButton(
                compact: true,
                title: l10n.tr('msgSizeTitle'),
                text: l10n.tr(known ? 'msgSizeHelpServer' : 'msgSizeHelpDefault').replaceAll('{limit}', lim),
              ),
            ],
          ),
          LinearProgressIndicator(
            value: share.clamp(0.0, 1.0),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
            color: over ? AppColors.errorRed : (warn ? AppColors.warningText(context) : null),
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(l10n.tr(hasPhotos ? 'msgSizeOverPhotos' : 'msgSizeOverFiles'), style: muted),
            ),
        ],
      ),
    );
  }

  /// Выбор отправителя списком (по нажатию на подпись «От»).
  Future<void> _pickFromSheet(List<AccountModel> accounts, ThemeData theme) async {
    // Карточкой (1.8.8), как меню «⋮».
    final id = await showChoiceSheet<String>(
      context,
      title: AppLocalizations.of(context).tr('from'),
      selected: _fromAccount?.id,
      entries: [
        for (final a in accounts)
          AppMenuEntry(
            value: a.id,
            label: a.displayName,
            subtitle: a.email,
            icon: a.isSharedMailbox ? AppIcons.supervisor_account : AppIcons.alternate_email,
            iconColor: a.isSharedMailbox ? kSharedMailboxColor : null,
          ),
      ],
    );
    final picked = accounts.where((a) => a.id == id).firstOrNull;
    if (picked != null) _onFromChanged(picked);
  }

  /// Имя ящика для показа: имя владельца, если оно известно, иначе адрес.
  static String _accountName(AccountModel a) {
    final n = a.displayName.trim();
    final login = a.email.split('@').first.toLowerCase();
    return (n.isEmpty || n.toLowerCase() == login || n.toLowerCase() == a.email.toLowerCase())
        ? a.email
        : n;
  }

  /// Значок слева от строки («От» — фото ящика, «Кому», «Копия», «Скрытая» —
  /// пиктограммы). Раньше слева стояли подписи разной ширины, и адреса в
  /// строках начинались с разных мест (замечание 07.10.2026). Подпись поля —
  /// подсказкой в пустом поле и всплывающей подсказкой у значка.
  Widget _fieldLead({required String label, required Widget child, VoidCallback? onTap}) => Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: onTap != null,
          child: InkResponse(
            onTap: onTap,
            radius: 20,
            child: SizedBox(width: 36, height: 40, child: Center(child: child)),
          ),
        ),
      );

  static const _aliasSep = '\u0001';

  Widget _buildFromField(ThemeData theme, AppLocalizations l10n) {
    final acc = _fromAccount;
    // Архив Exchange (1.6.49) — не адрес отправки: в списке «От» его нет
    // (кроме случая, когда письмо уже пишется из него — ответ из архива).
    final accounts = [
      for (final a in ref.watch(accountsProvider))
        if (!a.isOnlineArchive || a.id == acc?.id) a,
    ];
    final aliases = ref.watch(aliasServiceProvider);
    // Ящики и их адреса отправки «от имени» — одним списком.
    final entries = <({String key, AccountModel account, String? alias})>[
      for (final a in accounts) ...[
        (key: a.id, account: a, alias: null),
        for (final x in aliases[a.id] ?? const <String>[])
          if (x.toLowerCase() != a.email.toLowerCase()) (key: '${a.id}$_aliasSep$x', account: a, alias: x),
      ],
    ];
    final wanted = acc == null ? null : (_fromAlias == null ? acc.id : '${acc.id}$_aliasSep$_fromAlias');
    final selKey = entries.any((e) => e.key == wanted) ? wanted : acc?.id;
    final color = acc == null ? theme.colorScheme.primary : Color(acc.colorValue);
    return Row(
      children: [
        _fieldLead(
          label: l10n.tr('from'),
          onTap: accounts.length > 1 ? () => _pickFromSheet(accounts, theme) : null,
          child: PhotoRing(child: CircleAvatar(
            radius: 14,
            backgroundColor: color,
            foregroundImage: photoImage(acc?.avatarUrl),
            child: Text(
              acc == null ? '?' : initialOf(_accountName(acc)),
              style: TextStyle(fontSize: 12, color: onAccountColor(color)),
            ),
          )),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          // Меню-карточка (1.8.8) вместо списка Material. В строке — имя
          // ящика (раньше — адрес); в меню — имя и адрес. Адреса отправки «от
          // имени» (1.6.27) — под своим ящиком, с пометкой: отправить от
          // чужого имени по невнимательности — дорогая ошибка, особенно когда
          // секретарь ведёт ящик руководителя.
          child: AppSelectField<String>(
            value: selKey,
            entries: [
              for (final e in entries)
                AppMenuEntry(
                  value: e.key,
                  label: e.alias ?? _accountName(e.account),
                  icon: (e.account.isSharedMailbox || e.alias != null) ? AppIcons.supervisor_account : AppIcons.mail,
                  iconColor:
                      (e.account.isSharedMailbox || e.alias != null) ? kSharedMailboxColor : Color(e.account.colorValue),
                  subtitle: e.alias != null
                      ? l10n.tr('fromOnBehalfVia').replaceAll('{account}', e.account.email)
                      : (_accountName(e.account) != e.account.email ? e.account.email : null),
                ),
            ],
            selectedBuilder: (_, sel) {
              final e = entries.where((x) => x.key == sel?.value).firstOrNull;
              if (e == null) return const SizedBox.shrink();
              final marked = e.account.isSharedMailbox || e.alias != null;
              return Text(
                e.alias ?? _accountName(e.account),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: marked ? kSharedMailboxColor : null,
                  fontWeight: marked ? FontWeight.w600 : null,
                ),
              );
            },
            onChanged: (key) {
              final e = entries.where((x) => x.key == key).firstOrNull;
              if (e == null) return;
              _onFromChanged(e.account);
              setState(() => _fromAlias = e.alias);
            },
          ),
        ),
      ],
    );
  }

  /// Предупреждение под полем «От кого», когда выбран общий ящик.
  ///
  /// Мягкое, не блокирующее: работа с делегированным ящиком штатная. Но
  /// человек должен видеть, что письмо уйдёт не от его имени — особенно если
  /// он переключил ящик в начале работы, а отправляет через полчаса.
  Widget _sharedMailboxNotice(ThemeData theme, AppLocalizations l10n) {
    final acc = _fromAccount;
    if (acc == null || !acc.isSharedMailbox) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(50, Space.xs, Space.s, Space.xs),
      child: Row(
        children: [
          const Icon(AppIcons.info, size: 14, color: kSharedMailboxColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.tr('sendingFromShared').replaceAll('{mailbox}', acc.email),
              style: theme.textTheme.bodySmall?.copyWith(color: kSharedMailboxColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required List<EmailAddress> recipients,
    required ThemeData theme,
    required AppLocalizations l10n,
    required IconData icon,
    Widget? trailing,
  }) {
    final scheme = theme.colorScheme;
    void add(String v) {
      if (!v.contains('@')) return;
      setState(() {
        _commitPendingRecipient(controller, recipients);
        _contactSuggestions.clear();
        _lastQuery = '';
      });
      if (recipients == _toRecipients) _updateGreeting();
      focusNode.requestFocus(); // следующий адрес — сразу
    }

    // Имена — «Фамилия Имя», полное ФИО, если оно известно по контактам и
    // письмам (замечание 27.10.2026: в редакторе оставалось «Ситников, Дмитрий»).
    final names = ref.watch(personNamesProvider).value ?? const <String, String>{};

    Widget pill(EmailAddress r) {
      final group = _groupEmails.contains(r.email.toLowerCase());
      return _RecipientPill(
        text: _nameOf(r, names),
        tooltip: r.email,
        email: r.email,
        isGroup: group,
        // Нажатие — перенести в «Кому», «Копию» или «Скрытую», скопировать,
        // убрать (27.10.2026); у группы рассылки — её действия.
        onTap: group ? () => _showGroupActions(r, recipients) : () => _showRecipientActions(r, recipients),
        onRemove: () {
          setState(() => recipients.remove(r));
          if (recipients == _toRecipients) _updateGreeting();
          _markDraftChanged();
        },
      );
    }

    // Правка — плашки и поле ввода; иначе одна строка с именами.
    final editing = _editingField == controller || recipients.isEmpty;
    final Widget content = editing
        ? Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in recipients)
                // Удержать плашку и вести в другую строку — перенос адресата
                // (из «Кому» в «Копию», в «Скрытую» и обратно).
                LongPressDraggable<_DragRecipient>(
                  data: _DragRecipient(r, recipients),
                  onDragStarted: () => setState(() => _dragFrom = recipients),
                  onDragEnd: (_) {
                    if (mounted) setState(() => _dragFrom = null);
                  },
                  feedback: Material(
                    type: MaterialType.transparency,
                    child: Opacity(opacity: 0.9, child: pill(r)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: pill(r)),
                  child: pill(r),
                ),
              SizedBox(
                width: 180,
                child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    showCursor: !_caretInBody,
                    onTap: () {
                      _caretToHeader();
                      if (_editingField != controller) setState(() => _editingField = controller);
                    },
                    decoration: InputDecoration(
                      // Подпись поля — подсказкой, пока адресатов нет.
                      hintText: recipients.isEmpty ? label : null,
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: Space.s),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onChanged: (v) {
                      // Запятая или точка с запятой завершают адрес.
                      if (v.endsWith(',') || v.endsWith(';')) {
                        add(v.substring(0, v.length - 1));
                        return;
                      }
                      _onRecipientSearch(v, controller, recipients);
                    },
                    onSubmitted: add,
                ),
              ),
            ],
          )
        : InkWell(
            onTap: () => _openField(controller),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Row(
                children: [
                  // Фото первых адресатов перед строкой имён.
                  for (final r in recipients.take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: Space.xs),
                      child: HeroEmailAvatar(
                        emailId: 'sum/${r.email}',
                        initial: initialOf(_nameOf(r, names)),
                        color: HeroEmailAvatar.colorForEmail(r.email),
                        email: r.email,
                        radius: 11,
                        hero: false,
                      ),
                    ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      _recipientsSummary(recipients, l10n, names),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Значок строки — окно подбора адресатов: выбранные (убрать),
          // поиск по контактам и адресной книге, группы, «Моё подразделение».
          // Набор адреса прямо в строке работает как раньше.
          _fieldLead(
            label: label,
            onTap: () => _editRecipients(label, recipients),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: Space.s),
          // Нажатие в любом месте строки — к вводу адреса: раньше ввод
          // открывался только по узкому полю справа от плашек (11.10.2026).
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editing ? () => focusNode.requestFocus() : () => _openField(controller),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Align(alignment: Alignment.centerLeft, child: content),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
    return DragTarget<_DragRecipient>(
      onWillAcceptWithDetails: (d) => !identical(d.data.from, recipients),
      onAcceptWithDetails: (d) => _moveRecipient(d.data.address, d.data.from, recipients),
      builder: (context, candidates, _) {
        final over = candidates.isNotEmpty;
        final target = _dragFrom != null && !identical(_dragFrom, recipients) && !over;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: over
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : target
                    ? scheme.primaryContainer.withValues(alpha: 0.18)
                    : Colors.transparent,
            borderRadius: Radii.chipAll,
          ),
          child: row,
        );
      },
    );
  }

  /// Имя адресата для плашки, строки и шторки: «Фамилия, Имя» → «Фамилия
  /// Имя»; полное ФИО из контактов и писем, если оно известно; без имени —
  /// адрес.
  String _nameOf(EmailAddress r, Map<String, String> names) {
    final given = (r.displayName ?? '').trim();
    final norm = given.isEmpty ? null : normalizePersonName(given);
    return bestPersonName(norm, [names[r.email.toLowerCase()]]) ?? r.email;
  }

  /// Перенести адресата в другую строку (перетаскиванием или из шторки).
  void _moveRecipient(EmailAddress r, List<EmailAddress> from, List<EmailAddress> to) {
    if (identical(from, to)) return;
    final key = r.email.toLowerCase();
    setState(() {
      from.removeWhere((x) => x.email.toLowerCase() == key);
      if (!to.any((x) => x.email.toLowerCase() == key)) to.add(r);
      if (identical(to, _ccRecipients)) _showCc = true;
      if (identical(to, _bccRecipients)) _showBcc = true;
      _dragFrom = null;
    });
    HapticFeedback.selectionClick();
    if (identical(from, _toRecipients) || identical(to, _toRecipients)) _updateGreeting();
    _markDraftChanged();
  }

  /// Нажатие на плашку адресата: перенести в «Кому», «Копию» или «Скрытую»
  /// (строка откроется, если была скрыта), скопировать адрес, убрать.
  Future<void> _showRecipientActions(EmailAddress r, List<EmailAddress> from) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final names = ref.read(personNamesProvider).value ?? const <String, String>{};
    final name = _nameOf(r, names);
    final targets = <(String, List<EmailAddress>, IconData)>[
      if (!identical(from, _toRecipients)) (l10n.tr('recipientMoveTo'), _toRecipients, AppIcons.person),
      if (!identical(from, _ccRecipients)) (l10n.tr('recipientMoveCc'), _ccRecipients, AppIcons.group),
      if (!identical(from, _bccRecipients)) (l10n.tr('recipientMoveBcc'), _bccRecipients, AppIcons.visibility_off),
    ];
    final v = await showActionSheet<String>(
      context,
      title: name,
      subtitle: name == r.email ? null : r.email,
      leading: HeroEmailAvatar(
        emailId: 'act/${r.email}',
        initial: initialOf(name),
        color: HeroEmailAvatar.colorForEmail(r.email),
        email: r.email,
        radius: 20,
        hero: false,
      ),
      items: [
        for (var i = 0; i < targets.length; i++)
          ActionSheetItem(icon: targets[i].$3, label: targets[i].$1, value: 'move$i'),
        ActionSheetItem(icon: AppIcons.content_copy, label: l10n.tr('copyEmail'), value: 'copy'),
        ActionSheetItem(icon: AppIcons.close, label: l10n.tr('recipientRemove'), value: 'remove', destructive: true),
      ],
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
        child: Text(l10n.tr('recipientDragHint'),
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
      ),
    );
    if (v == null || !mounted) return;
    if (v.startsWith('move')) {
      final t = targets[int.parse(v.substring(4))];
      _moveRecipient(r, from, t.$2);
    } else if (v == 'copy') {
      await Clipboard.setData(ClipboardData(text: r.email));
      if (mounted) showInlineNotice(l10n.tr('copied'));
    } else if (v == 'remove') {
      setState(() => from.remove(r));
      if (identical(from, _toRecipients)) _updateGreeting();
      _markDraftChanged();
    }
  }

  /// Окно подбора адресатов строки; результат заменяет её содержимое.
  Future<void> _editRecipients(String title, List<EmailAddress> recipients) async {
    final current = [
      for (final r in recipients)
        ContactModel(
          id: 'r:${r.email}',
          email: r.email,
          displayName: r.displayName ?? r.email,
          isGroup: _groupEmails.contains(r.email.toLowerCase()),
        ),
    ];
    final picked = await editRecipientsSheet(context, account: _fromAccount, title: title, current: current);
    if (picked == null || !mounted) return;
    setState(() {
      final old = {for (final r in recipients) r.email.toLowerCase(): r};
      recipients
        ..clear()
        ..addAll([
          for (final c in picked)
            old[c.email.toLowerCase()] ??
                EmailAddress(
                    email: c.email,
                    displayName: c.displayName.isNotEmpty && c.displayName != c.email ? c.displayName : null),
        ]);
      for (final c in picked) {
        if (c.isGroup) _groupEmails.add(c.email.toLowerCase());
      }
      if (recipients == _ccRecipients && recipients.isNotEmpty) _showCc = true;
      if (recipients == _bccRecipients && recipients.isNotEmpty) _showBcc = true;
    });
    if (recipients == _toRecipients) _updateGreeting();
  }

  /// Небольшая кнопка-ссылка справа в строке адресатов («Копия», «Скрытая»).
  Widget _fieldToggle(ThemeData theme, String text, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: Space.s),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
      );

  /// Показать строку адресатов и перевести её в правку.
  void _openField(TextEditingController c) {
    setState(() {
      if (c == _ccController) _showCc = true;
      if (c == _bccController) _showBcc = true;
      _editingField = c;
    });
    final f = c == _toController ? _toFocus : (c == _ccController ? _ccFocus : _bccFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) f.requestFocus();
    });
  }

  // ── Полные ФИО получателей (1.5.9) ──
  // Получатель показывался так, как его записал Exchange: «Смирнов, Андрей».
  // Полное ФИО — из контактов, писем этого человека или адресной книги
  // организации (PersonNameDirectory); найденное заменяет имя в плашке и в
  // заголовке отправляемого письма. Один раз на адрес.
  final Set<String> _nameAsked = {};

  void _resolveRecipientNames() {
    final acc = _fromAccount;
    // Ящик «От» ещё не выбран — искать рано (письма и адресная книга — его).
    if (acc == null) return;
    for (final list in [_toRecipients, _ccRecipients, _bccRecipients]) {
      for (final r in List<EmailAddress>.of(list)) {
        final key = r.email.trim().toLowerCase();
        if (key.isEmpty || _nameAsked.contains(key) || _groupEmails.contains(key)) continue;
        final dn = r.displayName ?? '';
        // ФИО уже полное.
        if (PersonNames.words(dn) >= 3 && !dn.contains(',')) continue;
        _nameAsked.add(key);
        unawaited(ref.read(personNameDirectoryProvider).fullName(r.email, account: acc).then((full) {
          if (!mounted || full == null) return;
          final wasPristine = _isPristine;
          var changedTo = false;
          var changed = false;
          for (final l in [_toRecipients, _ccRecipients, _bccRecipients]) {
            for (var i = 0; i < l.length; i++) {
              if (l[i].email.trim().toLowerCase() != key || !PersonNames.better(l[i].displayName, full)) continue;
              l[i] = EmailAddress(email: l[i].email, displayName: full);
              changed = true;
              if (identical(l, _toRecipients)) changedTo = true;
            }
          }
          if (!changed) return;
          setState(() {});
          // Обращение по полному имени («Андрей Сергеевич»), а не по
          // «Смирнов, Андрей»; нетронутое письмо таким и остаётся.
          if (changedTo) {
            _updateGreeting();
            if (wasPristine) _markPristine();
          }
        }, onError: (Object _) {}));
      }
    }
  }

  /// «Кузнецов М. Г., Соколов М. В. и ещё 2» — адресаты одной строкой.
  String _recipientsSummary(List<EmailAddress> rs, AppLocalizations l10n, Map<String, String> names) {
    if (rs.isEmpty) return '';
    if (rs.length == 1) return _nameOf(rs.first, names);
    final shown = [for (final r in rs.take(2)) _shortName(r, names)].join(', ');
    final rest = rs.length - 2;
    return rest > 0 ? '$shown ${l10n.tr('andNMore').replaceAll('{n}', '$rest')}' : shown;
  }

  /// «Кузнецов Максим Геннадьевич» → «Кузнецов М. Г.»; без имени — адрес.
  String _shortName(EmailAddress a, Map<String, String> names) {
    final n = _nameOf(a, names);
    return PersonNames.short(n == a.email ? null : n, email: a.email);
  }

  /// «На контроле» для отправляемого письма (меню «⋮»).
  bool _control = false;

  Future<void> _applyControlOnSend() async {
    final account = _fromAccount;
    if (account == null || !ref.read(settingsProvider).mailControl) return;
    try {
      if (_control && _toRecipients.isNotEmpty) {
        await ControlService.addPending(
          accountId: account.id,
          subject: _subjectController.text.trim(),
          firstTo: _toRecipients.first.email,
        );
      }
      // Ответ на письмо «должен ответить» — сразу «Исполнено».
      final src = widget.replyToId;
      if (src != null) {
        final db = ref.read(databaseProvider);
        final row = await db.getEmailById(src, accountId: widget.accountId ?? account.id);
        if (row != null && row.controlState == ControlState.mustReply) {
          await db.setControlState(row.id, row.accountId, ControlState.done);
          ref.read(controlRevisionProvider.notifier).state++;
        }
      }
    } catch (_) {}
  }

  AppMenuEntry<String> _menuItem(String value, IconData icon, String text) =>
      AppMenuEntry(value: value, icon: icon, label: text);

  /// Заголовок экрана по виду письма.
  /// Заголовок и под ним — «Сохранено · 06:41», когда черновик записан.
  Widget _titleWithSaved(AppLocalizations l10n) {
    final title = Text(_screenTitle(l10n), maxLines: 1, overflow: TextOverflow.ellipsis);
    final at = _savedAt;
    if (at == null || _sentOrDiscarded) return title;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        Text(
          l10n.tr('draftSavedAt').replaceAll('{time}', AppDateFormat.time(context, at)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Кнопка «Сохранить»: записать черновик сейчас. Пустое письмо сохранять
  /// нечего — строка-подсказка вместо плашки.
  Future<void> _saveDraftNow(AppLocalizations l10n) async {
    _markDraftChanged();
    final snap = _snapshot();
    if (snap.isEmpty) {
      showInlineError(l10n.tr('draftNothingToSave'));
      return;
    }
    final ok = await (_autosave?.forceSave() ?? Future.value(false));
    if (!mounted) return;
    if (ok) {
      unawaited(HapticFeedback.selectionClick());
      // Сохранённая версия — новая точка отсчёта: закрыть, ничего больше не
      // меняя, можно без вопроса.
      _markPristine();
      _openedDraft = true;
      _pristineSaved = true;
    } else {
      showInlineError(l10n.tr('draftSaveFailed'));
    }
  }

  String _screenTitle(AppLocalizations l10n) {
    if (widget.draftId != null) return l10n.tr('draft');
    if (widget.replyToId != null) return l10n.tr(widget.replyAll ? 'replyAllTitle' : 'replyTitle');
    if (widget.forwardFromId != null) return l10n.tr('forwardTitle');
    return l10n.tr('newMessage');
  }

  void _pickImportance(AppLocalizations l10n) => _pickOption(
        l10n.tr('importance'),
        {
          'High': l10n.tr('importanceHigh'),
          'Normal': l10n.tr('importanceNormal'),
          'Low': l10n.tr('importanceLow'),
        },
        _importance,
        (v) => setState(() => _importance = v),
      );

  /// Гриф письма: метка в начале темы («[ДСП] …») — видна в любом клиенте,
  /// у получателя с Ogneliss письмо защищено. Пометка Outlook
  /// (чувствительность) выводится из грифа при отправке — см. [_sensitivity].
  /// Шифрование: у каждого получателя должен быть сертификат (он
  /// запоминается из его подписанного письма). Нет — предложить отправить без
  /// шифрования (подпись остаётся) или вернуться.
  Future<bool> _smimeAllowsSend(AppLocalizations l10n) async {
    if (!_smimeAvailable || !_smimeEncrypt) return true;
    final missing = ref.read(smimeServiceProvider).missingPeers([
      for (final r in [..._toRecipients, ..._ccRecipients, ..._bccRecipients]) r.email,
    ]);
    if (missing.isEmpty) return true;
    // Шифрование включено настройкой ящика («если возможно») — письмо уходит
    // подписанным без шифрования, без вопросов. Включено в этом письме —
    // спросить.
    if (!_smimeTouched) {
      setState(() => _smimeEncrypt = false);
      return true;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(AppIcons.no_encryption),
        title: Text(l10n.tr('smimeNoPeerTitle')),
        content: Text(l10n.tr('smimeNoPeer').replaceAll('{list}', missing.join(', '))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'plain'), child: Text(l10n.tr('smimeSendUnencrypted'))),
        ],
      ),
    );
    if (choice != 'plain' || !mounted) return false;
    setState(() {
      _smimeTouched = true;
      _smimeEncrypt = false;
    });
    return true;
  }

  /// Подпись и шифрование S/MIME этого письма (у ящика есть сертификат).
  Future<void> _pickSmime(AppLocalizations l10n) async {
    if (!_smimeAvailable) return;
    await showAppSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              void toggle(void Function() change) {
                setState(change);
                setSheet(() {});
              }

              return Column(mainAxisSize: MainAxisSize.min, children: [
                SettingsSectionTitle(l10n.tr('smimeSection')),
                SwitchListTile(
                  value: _smimeSign,
                  onChanged: (v) => toggle(() {
                    _smimeTouched = true;
                    _smimeSign = v;
                  }),
                  title: Text(l10n.tr('smimeSign')),
                  subtitle: Text(l10n.tr('smimeSignHint')),
                ),
                SwitchListTile(
                  value: _smimeEncrypt,
                  onChanged: (v) => toggle(() {
                    _smimeTouched = true;
                    _smimeEncrypt = v;
                  }),
                  title: Text(l10n.tr('smimeEncrypt')),
                  subtitle: Text(l10n.tr('smimeEncryptHint')),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  void _pickOption(String title, Map<String, String> options, String current,
      ValueChanged<String> onPick) {
    // Карточкой (1.8.8), как меню «⋮»; выбранное — с галочкой.
    unawaited(showChoiceSheet<String>(
      context,
      title: title,
      selected: current,
      entries: [for (final e in options.entries) AppMenuEntry(value: e.key, label: e.value)],
    ).then((v) {
      if (v != null) onPick(v);
    }));
  }

  // ════════════════════════ АВТОДОПОЛНЕНИЕ ════════════════════════

  void _onRecipientSearch(String query, TextEditingController field, List<EmailAddress> target) {
    _suggestFor = field;
    _suggestTarget = target;
    debounce(const Duration(milliseconds: AppConstants.searchDebounceMs), () {
      if (query.trim().length >= 2) {
        _searchContacts(query.trim());
      } else {
        _searchSeq++;
        _lastQuery = '';
        if (mounted) {
          setState(() {
            _contactSuggestions.clear();
        _lastQuery = '';
            _galSearching = false;
          });
        }
      }
    });
  }

  /// Подсказки адресов: сначала свои — контакты всех аккаунтов (Google,
  /// Exchange, телефон) и те, с кем шла переписка; для Exchange затем
  /// добавляется адресная книга организации. Раньше искалась только она, и
  /// у Gmail подсказок не было вовсе.
  /// Идёт запрос к адресной книге организации (для индикатора).
  bool _galSearching = false;
  /// Последний искомый текст (для «ничего не найдено»).
  String _lastQuery = '';
  /// Поиск по [_lastQuery] завершён (локальный и адресная книга).
  bool _searchDone = false;

  Future<void> _searchContacts(String query) async {
    final seq = ++_searchSeq;
    _lastQuery = query;
    _searchDone = false;
    final seen = <String>{
      for (final r in [..._toRecipients, ..._ccRecipients, ..._bccRecipients]) r.email.toLowerCase(),
    };
    final out = <ContactModel>[];
    void addAll(Iterable<ContactModel> list) {
      for (final c in list) {
        final key = c.email.trim().toLowerCase();
        if (key.isEmpty) continue;
        if (!seen.add(key)) {
          // Тот же адрес уже есть из локальных контактов, а адресная книга
          // говорит, что это группа рассылки, — помечаем найденную запись.
          if (c.isGroup) {
            final i = out.indexWhere((x) => x.email.trim().toLowerCase() == key);
            if (i >= 0 && !out[i].isGroup) out[i] = c;
          }
          continue;
        }
        out.add(c);
      }
    }

    try {
      final db = ref.read(databaseProvider);
      // SQLite lower() и LIKE без учёта регистра работают только для
      // латиницы: «ив» не находил «Иванов». Ищем по трём написаниям запроса
      // (как набрано, строчными, с заглавной), а адрес — строчными.
      final q = query.trim();
      final lower = q.toLowerCase();
      final cap = lower.isEmpty ? lower : lower[0].toUpperCase() + lower.substring(1);
      final variants = {q, lower, cap, q.toUpperCase()}.toList();
      final nameCond = List.filled(variants.length, 'display_name LIKE ?').join(' OR ');
      final prefixCond = List.filled(variants.length, 'display_name LIKE ? OR display_name LIKE ?').join(' OR ');
      final contacts = await db.customSelect(
        'SELECT id, email, display_name, job_title, department, company, avatar_url FROM contacts '
        'WHERE lower(email) LIKE ? OR $nameCond '
        // Сначала — совпадение с началом адреса, имени или фамилии.
        'ORDER BY (lower(email) LIKE ? OR $prefixCond) DESC, '
        'is_favorite DESC, interaction_count DESC, last_interaction DESC, display_name LIMIT 12',
        variables: [
          Variable.withString('%$lower%'),
          for (final v in variants) Variable.withString('%$v%'),
          Variable.withString('$lower%'),
          for (final v in variants) ...[Variable.withString('$v%'), Variable.withString('% $v%')],
        ],
      ).get();
      addAll(contacts.map((r) => ContactModel(
            id: r.data['id'] as String,
            email: r.data['email'] as String,
            displayName: (r.data['display_name'] as String?) ?? '',
            jobTitle: r.data['job_title'] as String?,
            department: r.data['department'] as String?,
            company: r.data['company'] as String?,
            avatarUrl: r.data['avatar_url'] as String?,
          )));
      final senderNameCond = List.filled(variants.length, 'from_name LIKE ?').join(' OR ');
      final senders = await db.customSelect(
        'SELECT lower(from_email) AS e, MAX(from_name) AS n, COUNT(*) AS c FROM emails '
        'WHERE lower(from_email) LIKE ? OR $senderNameCond '
        'GROUP BY lower(from_email) ORDER BY c DESC LIMIT 6',
        variables: [Variable.withString('%$lower%'), for (final v in variants) Variable.withString('%$v%')],
      ).get();
      addAll(senders.map((r) => ContactModel(
            id: 'sender:${r.data['e']}',
            email: r.data['e'] as String,
            displayName: (r.data['n'] as String?) ?? '',
            source: ContactSource.device,
          )));
    } catch (_) {}
    if (!mounted || seq != _searchSeq) return;
    final acc = _fromAccount;
    final withGal = acc != null && acc.isMsExchange;
    setState(() {
      _contactSuggestions = _stableMerge(query, out);
      _searchDone = !withGal;
    });

    // Адресная книга организации — дольше (запрос к серверу), дописываем.
    if (!withGal) return;
    setState(() => _galSearching = true);
    try {
      // Потолок 15 с: при плохой связи индикатор не крутится бесконечно.
      final gal = await safeAsync(() => ref
          .read(mailEngineServiceProvider)
          .resolveNames(acc, query)
          .timeout(const Duration(seconds: 15)));
      if (gal == null || !mounted || seq != _searchSeq) return;
      addAll(gal);
      setState(() => _contactSuggestions = _stableMerge(query, out));
    } catch (_) {
    } finally {
      if (mounted && seq == _searchSeq) {
        setState(() {
          _galSearching = false;
          _searchDone = true;
        });
      }
    }
  }

  /// Запрос, для которого показан текущий список подсказок.
  String _shownQuery = '';
  Timer? _noneTimer;

  /// Тот же запрос — уже показанные строки остаются на местах, новые
  /// дописываются ниже: раньше список перестраивался по мере ответа адресной
  /// книги, и под пальцем оказывался другой адресат (замечание 11.10.2026).
  /// Новый запрос — список заново.
  List<ContactModel> _stableMerge(String query, List<ContactModel> found) {
    if (query != _shownQuery || _contactSuggestions.isEmpty) {
      _shownQuery = query;
      return List.of(found);
    }
    final byKey = {for (final c in found) c.email.trim().toLowerCase(): c};
    final out = <ContactModel>[
      for (final c in _contactSuggestions)
        if (byKey.containsKey(c.email.trim().toLowerCase())) byKey.remove(c.email.trim().toLowerCase())!,
    ];
    out.addAll(byKey.values);
    return out;
  }

  /// Подсказки под полем ввода: компактные строки, не больше шести.
  Widget _buildSuggestions(ThemeData theme) {
    final scheme = theme.colorScheme;
    // Состояние поиска: при плохой связи было непонятно, ищет ли приложение
    // или ничего не нашло.
    final status = _galSearching
        ? Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Expanded(child: Text(AppLocalizations.of(context).tr('recipientSearchGal'),
                style: theme.textTheme.bodySmall)),
          ])
        // «Ничего не найдено» — только когда поиск по ЭТОМУ тексту завершён
        // и пуст. Раньше надпись оставалась после выбора адресата (запрос
        // не сбрасывался) и мелькала, пока шёл поиск.
        : (_contactSuggestions.isEmpty &&
                _searchDone &&
                _lastQuery.length >= 2 &&
                (_suggestFor?.text.trim() ?? '') == _lastQuery)
            ? Text(AppLocalizations.of(context).tr('recipientSearchNone'), style: theme.textTheme.bodySmall)
            : null;
    if (_contactSuggestions.isEmpty && status == null) return const SizedBox.shrink();
    // «Ничего не найдено» — ненадолго: через 3 с строка убирается.
    if (_contactSuggestions.isEmpty && !_galSearching) {
      final q = _lastQuery;
      _noneTimer?.cancel();
      _noneTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _lastQuery == q && _contactSuggestions.isEmpty) setState(() => _lastQuery = '');
      });
    }
    if (_contactSuggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 44, bottom: Space.s, top: Space.xs),
        child: status,
      );
    }
    return Container(
      margin: const EdgeInsets.only(left: 44, bottom: Space.s),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.cardAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final c in _contactSuggestions.take(6))
            InkWell(
              onTap: () => _addRecipient(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: Row(
                  children: [
                    PhotoRing(child: CircleAvatar(
                      radius: 14,
                      backgroundColor: avatarTones(context, Color(c.avatarColor)).fill,
                      // Фото — из контакта или по адресу (адресная книга, переписка).
                      foregroundImage: photoImage(c.avatarUrl ??
                          ref.watch(personPhotosProvider).value?[c.email.toLowerCase()]),
                      onForegroundImageError: photoImage(c.avatarUrl ??
                                  ref.watch(personPhotosProvider).value?[c.email.toLowerCase()]) ==
                              null
                          ? null
                          : (_, __) {},
                      child: c.isGroup
                          ? Icon(AppIcons.groups, size: 16, color: avatarTones(context, Color(c.avatarColor)).letter)
                          : Text(
                              initialOf((c.displayName.isNotEmpty ? c.displayName : c.email)),
                              style: TextStyle(color: avatarTones(context, Color(c.avatarColor)).letter, fontSize: 12),
                            ),
                    )),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.displayName.isNotEmpty ? normalizePersonName(c.displayName) : c.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (c.displayName.isNotEmpty)
                            Text(
                              c.isGroup
                                  ? '${AppLocalizations.of(context).tr('groupMailingList')} · ${c.email}'
                                  : c.subtitle.isNotEmpty ? '${c.email} · ${c.subtitle}' : c.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Состояние поиска — снизу: строка сверху сдвигала подсказки, когда
          // появлялась и исчезала.
          if (status != null)
            Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s), child: status),
        ],
      ),
    );
  }

  /// Лист выбора подписи для вставки (из сохранённых подписей аккаунта).
  void _showSignaturePicker(AppLocalizations l10n) {
    final all = ref.read(signaturesProvider);
    final acc = _fromAccount;
    final sigs = all
        .where((s) => acc == null || s.accountId == null || s.accountId == acc.id)
        .toList();
    if (sigs.isEmpty) {
      showInlineNotice(l10n.tr('noSignaturesCompose'));
      return;
    }
    // Карточкой (1.8.8), как меню «⋮».
    unawaited(showChoiceSheet<int>(
      context,
      title: l10n.tr('insertSignature'),
      entries: [
        for (final (i, s) in sigs.indexed)
          AppMenuEntry(
            value: i,
            label: s.name,
            icon: AppIcons.draw,
            subtitle: () {
              final t = s.plainContent.replaceAll('\n', ' ').trim();
              return t.length > 60 ? '${t.substring(0, 60)}…' : t;
            }(),
          ),
      ],
    ).then((i) {
      if (i == null || !mounted || _fromAccount == null) return;
      final s = sigs[i];
      if (_useHtmlEditor) {
        // Заменяет текущую подпись (или добавляется в конец).
        _autoSignature = false;
        _editor.setSignature(_renderSignature(
            s.htmlContent.isNotEmpty ? s.htmlContent : s.plainContent.replaceAll('\n', '<br>'),
            html: true));
      } else {
        _appendBodyPlain(
            '\n\n${_renderSignature(s.plainContent.isNotEmpty ? s.plainContent : s.htmlContent, html: false)}');
      }
    }));
  }

  /// Лист управления группами рассылки.
  void _showGroupsSheet(AppLocalizations l10n) {
    showAppSheet(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref2, _) {
        final groups = ref2.watch(distributionGroupsProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.s, Space.s),
                child: Row(
                  children: [
                    Text(l10n.tr('distributionGroups'),
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    if (_toRecipients.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(AppIcons.save, size: 18),
                        label: Text(l10n.tr('saveCurrent')),
                        onPressed: () => _saveCurrentAsGroup(ctx, ref2, l10n),
                      ),
                  ],
                ),
              ),
              // Подразделение из адресной книги организации (Exchange).
              if (_fromAccount?.isMsExchange ?? false)
                ListTile(
                  leading: const Icon(AppIcons.apartment),
                  title: Text(l10n.tr('myDepartment')),
                  subtitle: Text(l10n.tr('myDepartmentHint')),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_pickDepartment(l10n));
                  },
                ),
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xl),
                  child: Text(
                    l10n.tr('noGroups'),
                    style: TextStyle(color: AppColors.mutedText(context)),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: groups
                        .map((g) => ListTile(
                              leading: const Icon(AppIcons.group),
                              title: Text(g.name),
                              subtitle: Text(l10n.tr('nRecipients').replaceAll('{n}', '${g.members.length}')),
                              onTap: () {
                                _addGroupToRecipients(g);
                                Navigator.pop(ctx);
                              },
                              trailing: IconButton(
                                tooltip: l10n.tr('delete'),
                                icon: const Icon(AppIcons.delete, size: 20),
                                onPressed: () =>
                                    ref2.read(distributionGroupsProvider.notifier).deleteGroup(g.name),
                              ),
                            ))
                        .toList(),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  void _addGroupToRecipients(DistributionGroup g) {
    setState(() {
      for (final m in g.members) {
        if (!_toRecipients.any((r) => r.email.toLowerCase() == m.email.toLowerCase())) {
          _toRecipients.add(EmailAddress(email: m.email, displayName: m.name));
        }
      }
    });
    _updateGreeting();
  }

  Future<void> _saveCurrentAsGroup(BuildContext ctx, WidgetRef ref2, AppLocalizations l10n) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.tr('groupName')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(l10n.tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: Text(l10n.tr('save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      if (!mounted) return;
      final members =
          _toRecipients.map((r) => GroupMember(email: r.email, name: r.displayName)).toList();
      await ref2.read(distributionGroupsProvider.notifier).saveGroup(name, members);
      if (ctx.mounted) {
        Navigator.pop(ctx);
        showInlineNotice(l10n.tr('groupSaved').replaceAll('{name}', name));
      }
    }
  }

  /// Адреса получателей, которые являются группами рассылки организации.
  final Set<String> _groupEmails = {};

  /// Действия с группой-получателем: объяснение и «Раскрыть».
  Future<void> _showGroupActions(EmailAddress group, List<EmailAddress> recipients) async {
    final l10n = AppLocalizations.of(context);
    // Карточкой (1.8.8), как меню «⋮».
    final expand = await showActionSheet<bool>(
      context,
      title: group.label,
      subtitle: '${l10n.tr('groupMailingList')} · ${group.email}',
      leading: const Icon(AppIcons.groups),
      items: [ActionSheetItem(icon: AppIcons.unfold_more, label: l10n.tr('groupExpand'), value: true)],
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
        child: Text(l10n.tr('groupExpandHint'), style: Theme.of(context).textTheme.bodySmall),
      ),
    );
    if (expand != true || !mounted) return;
    final acc = _fromAccount;
    if (acc == null) return;
    try {
      final members = await ref.read(mailEngineServiceProvider).expandGroup(acc, group.email);
      if (!mounted) return;
      if (members == null) {
        showInlineError(l10n.tr('groupExpandUnavailable'));
        return;
      }
      if (members.isEmpty) {
        showInlineNotice(l10n.tr('groupExpandEmpty'));
        return;
      }
      var added = 0;
      setState(() {
        final at = recipients.indexOf(group);
        recipients.remove(group);
        _groupEmails.remove(group.email.toLowerCase());
        final insert = <EmailAddress>[];
        for (final m in members) {
          final e = m.email.toLowerCase();
          if (recipients.any((r) => r.email.toLowerCase() == e) ||
              insert.any((r) => r.email.toLowerCase() == e)) {
            continue;
          }
          insert.add(EmailAddress(email: m.email, displayName: m.displayName));
          if (m.isGroup) _groupEmails.add(e); // вложенная группа
          added++;
        }
        recipients.insertAll(at < 0 ? recipients.length : at, insert);
      });
      if (recipients == _toRecipients) _updateGreeting();
      showInlineNotice(l10n.tr('groupExpanded').replaceAll('{n}', '$added'));
    } catch (e) {
      if (mounted) showInlineError('${l10n.error}: $e');
    }
  }

  /// «Моё подразделение»: коллеги с тем же подразделением из адресной книги
  /// организации — выбрать, кого добавить в «Кому».
  Future<void> _pickDepartment(AppLocalizations l10n) async {
    final acc = _fromAccount;
    if (acc == null) return;
    final future = ref.read(mailEngineServiceProvider).departmentColleagues(acc);
    final picked = await showAppSheet<List<ContactModel>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FutureBuilder<({String unit, String wider, Set<String> near, List<ContactModel> people})>(
        future: future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return snap.hasError
                ? Padding(padding: const EdgeInsets.all(Space.xl), child: Text('${l10n.error}: ${snap.error}'))
                : const Padding(padding: EdgeInsets.all(Space.xxl), child: Center(child: CircularProgressIndicator()));
          }
          final r = snap.data!;
          if (r.people.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(l10n.tr('myDepartmentNone')),
            );
          }
          // Отмечены сразу — тот же «Офис», что у вас; остальные из того же
          // здания/подразделения — без отметки (1.6.26).
          final selected = {...r.near};
          return StatefulBuilder(
            builder: (ctx, setLocal) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (ctx, controller) => Column(
                children: [
                  ListTile(
                    title: Text(r.wider.isEmpty ? r.unit : '${r.wider} · ${r.unit}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(l10n.tr('myDepartmentHint')),
                    trailing: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(ctx,
                              r.people.where((p) => selected.contains(p.email.toLowerCase())).toList()),
                      child: Text(l10n.tr('addSelectedN').replaceAll('{n}', '${selected.length}')),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      children: [
                        for (final p in r.people)
                          CheckboxListTile(
                            value: selected.contains(p.email.toLowerCase()),
                            onChanged: (v) => setLocal(() => v == true
                                ? selected.add(p.email.toLowerCase())
                                : selected.remove(p.email.toLowerCase())),
                            title: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [p.jobTitle, p.email, p.office].where((x) => x != null && x.isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final p in picked) {
        if (!_toRecipients.any((r) => r.email.toLowerCase() == p.email.toLowerCase())) {
          _toRecipients.add(EmailAddress(email: p.email, displayName: p.displayName));
        }
      }
    });
    _updateGreeting();
    showInlineNotice(l10n.tr('groupExpanded').replaceAll('{n}', '${picked.length}'));
  }

  void _addRecipient(ContactModel contact) {
    final target = _suggestTarget ?? _toRecipients;
    final field = _suggestFor ?? _toController;
    _searchSeq++; // запоздавший ответ поиска не вернёт подсказки
    setState(() {
      if (!target.any((r) => r.email.toLowerCase() == contact.email.toLowerCase())) {
        target.add(EmailAddress(
            email: contact.email,
            // «Ситников, Дмитрий» из адресной книги → «Ситников Дмитрий».
            displayName: contact.displayName.isNotEmpty ? normalizePersonName(contact.displayName) : null));
      }
      if (contact.isGroup) _groupEmails.add(contact.email.toLowerCase());
      field.clear();
      _contactSuggestions.clear();
        _lastQuery = '';
    });
    _updateGreeting();
    HapticFeedback.selectionClick();
  }

  /// Приветствие следует за адресатами «Кому» («Добрый день, Максим
  /// Геннадьевич,» → «Добрый день, коллеги,»), пока пользователь его не правил.
  /// [force] — вариант выбран кнопкой «Приветствие»: первая строка
  /// заменяется, даже если её правили (её не было — вставляется).
  void _updateGreeting({bool force = false}) {
    if (!_greetingPlaced) return;
    final prev = _autoGreeting ?? '';
    final greeting = _greetingText();
    if (greeting == prev && !force) return;
    _autoGreeting = greeting;
    if (_useHtmlEditor) {
      _editor.setGreeting(greeting, force ? null : prev);
      _lastHtml = _withGreetingHtml(_lastHtml, greeting);
      return;
    }
    final lines = _plainController.text.split('\n');
    final first = lines.isEmpty ? '' : lines.first.trim();
    final known = {prev, for (final (_, t) in _greetingSet().choices) t}..remove('');
    if (first.isNotEmpty && (first == prev.trim() || (force && known.contains(first)))) {
      if (greeting.isEmpty) {
        lines.removeAt(0);
        if (lines.isNotEmpty && lines.first.trim().isEmpty) lines.removeAt(0);
      } else {
        lines[0] = greeting;
      }
      _plainController.text = lines.join('\n');
    } else if (force && greeting.isNotEmpty) {
      _plainController.text = '$greeting\n\n${_plainController.text}';
    }
  }

  /// [html] с приветствием [greeting] в первой строке (блок #ogn-greeting;
  /// '' — без блока).
  String _withGreetingHtml(String html, String greeting) {
    final re = RegExp(r'<div id="ogn-greeting">[\s\S]*?</div>');
    final div = '<div id="ogn-greeting">${_escText(greeting)}</div>';
    if (re.hasMatch(html)) return html.replaceFirst(re, greeting.isEmpty ? '' : div);
    return greeting.isEmpty ? html : '$div$html';
  }

  // ════════════════════════ ОТПРАВКА с DLP ════════════════════════

  /// Добавляет email из поля ввода в список получателей, если он ещё не добавлен
  /// (на случай, если пользователь не нажал Enter перед отправкой).
  void _commitPendingRecipient(TextEditingController controller, List<EmailAddress> recipients) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    // Несколько адресов через запятую, точку с запятой или пробел, «Имя
    // <адрес>» и «mailto:» (1.8.13, AddressInput). Раньше адресатом
    // становился любой кусок с «@» — «<ivan@corp.ru>» со скобками, «ivan@».
    final parsed = AddressInput.parse(text);
    for (final a in parsed.addresses) {
      if (!recipients.any((r) => r.email.toLowerCase() == a.email.toLowerCase())) recipients.add(a);
    }
    // Неверный адрес остаётся в поле — его исправят; текст без «@» (поиск
    // по имени) убирается, как раньше.
    final bad = parsed.rest.contains('@') ? parsed.rest : '';
    if (controller.text != bad) controller.text = bad;
    if (bad.isNotEmpty) {
      _badAddress = bad;
    } else if (_badAddress == text) {
      _badAddress = null;
    }
  }

  /// Неверный адрес в поле адресатов — строкой под полями (1.8.13).
  String? _badAddress;

  /// Перед отправкой: в полях адресатов не осталось неверных адресов.
  bool _addressesOk(AppLocalizations l10n) {
    for (final (c, f) in [(_toController, _toFocus), (_ccController, _ccFocus), (_bccController, _bccFocus)]) {
      final t = c.text.trim();
      if (t.contains('@')) {
        setState(() {
          _badAddress = t;
          _editingField = c;
        });
        f.requestFocus();
        unawaited(HapticFeedback.heavyImpact());
        return false;
      }
    }
    if (_badAddress != null) setState(() => _badAddress = null);
    return true;
  }


  /// Отложенная отправка. [at] — время из быстрого варианта (меню по
  /// удержанию «Отправить», 1.6.49); без него — шторка выбора времени.
  Future<void> _onScheduleSend(AppLocalizations l10n, AppSettings settings, {DateTime? at}) async {
    if (_sendInFlight) return;
    _sendInFlight = true;
    try {
      await _onScheduleSendGuarded(l10n, settings, at: at);
    } finally {
      _sendInFlight = false;
    }
  }

  Future<void> _onScheduleSendGuarded(AppLocalizations l10n, AppSettings settings, {DateTime? at}) async {
    _commitPendingRecipient(_toController, _toRecipients);
    _commitPendingRecipient(_ccController, _ccRecipients);
    _commitPendingRecipient(_bccController, _bccRecipients);
    if (!_addressesOk(l10n)) return;

    if (_toRecipients.isEmpty) {
      // Подсказка у поля «Кому» (всплывающие сообщения отключены — раньше
      // нажатие «Отправить» без адресата выглядело так, будто ничего не
      // произошло).
      setState(() => _toError = l10n.tr('specifyRecipient'));
      _toFocus.requestFocus();
      unawaited(HapticFeedback.heavyImpact());
      return;
    }
    if (!await _smimeAllowsSend(l10n)) return;
    if (!mounted) return;

    // Выбор даты
    final now = DateTime.now();
    List<(String, DateTime)> presets() => [
          for (final p in SendLaterPresets.of(DateTime.now()))
            (l10n.tr(SendLaterPresets.labelKey(p)).replaceAll('{time}', AppDateFormat.time(context, p.at)), p.at),
        ];
    // Дата и время — одной шторкой с барабанами (10.10.2026); сверху —
    // быстрые варианты, как в меню «Отправить» (1.6.49).
    final picked = (at != null && at.isAfter(now))
        ? at
        : await showWheelDateTimePicker(context,
            initial: now.add(const Duration(hours: 1)),
            first: now.add(const Duration(minutes: 5)),
            last: now.add(const Duration(days: 365)),
            title: l10n.tr('scheduleSend'),
            presets: presets());
    if (picked == null || !mounted) return;
    var scheduledAt = picked;
    // Время уже прошло (шторку держали открытой долго) — выбор снова.
    while (!scheduledAt.isAfter(DateTime.now())) {
      final again = await showWheelDateTimePicker(context,
          initial: DateTime.now().add(const Duration(hours: 1)),
          first: DateTime.now().add(const Duration(minutes: 5)),
          last: DateTime.now().add(const Duration(days: 365)),
          title: l10n.tr('timeInPast'),
          presets: presets());
      if (again == null || !mounted) return;
      scheduledAt = again;
    }
    if (!await _chooseImageSize() || !mounted) return;

    setState(() => _isSending = true);
    try {
      final account = _fromAccount!;
      // Отложенная отправка уходит обычным путём — с цитатой.
      final bodyHtml = _withQuote(await _getBodyHtmlAsync());
      ref.read(smartComposeProvider).learnFromSentEmail(_authoredPlain);
      await _awaitRunningDownloads();
      await ref.read(offlineSendProvider).scheduleSend(
            accountId: account.id,
            importance: _importance,
            sensitivity: _sensitivity,
            attachments: await _collectAttachments(l10n),
            // Не скачанные файлы пересылаемого письма — скачаются к отправке.
            remoteAttachments: _pendingRefs(),
            to: _toRecipients,
            cc: _ccRecipients,
            bcc: _bccRecipients,
            subject: _subjectController.text.trim(),
            bodyHtml: bodyHtml,
            inReplyTo: _inReplyTo,
            scheduledAt: scheduledAt,
            from: _fromOverride,
          );
      unawaited(HapticFeedback.mediumImpact());
      AppLogger.info('Письмо отложено до $scheduledAt');
      // Письмо видно в ленте строкой «Отправка запланирована» (её можно
      // отменить или изменить там же).
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Плашки скрыты (решение владельца 19.10): ошибка — строкой на экране
      // (о пропавшем файле строка уже есть).
      if (e is! _MissingFile) {
        showInlineError(e.toString().contains('offline_queue_full')
            ? l10n.tr('offlineQueueFull')
            : '${l10n.tr('error')}: $e');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Отправка уже идёт (проверки, окна вопросов, сборка письма) — второе
  /// нажатие «Отправить» ничего не делает (1.8.13). Раньше двойное касание,
  /// пока письмо собиралось (крупные вложения), ставило его в очередь
  /// дважды — адресаты получали два одинаковых письма.
  bool _sendInFlight = false;

  Future<void> _onSend(AppLocalizations l10n, AppSettings settings) async {
    if (_sendInFlight) return;
    _sendInFlight = true;
    try {
      await _onSendGuarded(l10n, settings);
    } finally {
      _sendInFlight = false;
    }
  }

  Future<void> _onSendGuarded(AppLocalizations l10n, AppSettings settings) async {
    // Захватываем незакоммиченный текст из полей (если пользователь не нажал Enter)
    _commitPendingRecipient(_toController, _toRecipients);
    _commitPendingRecipient(_ccController, _ccRecipients);
    _commitPendingRecipient(_bccController, _bccRecipients);
    if (!_addressesOk(l10n)) return;

    if (_toRecipients.isEmpty) {
      // Подсказка у поля «Кому» (всплывающие сообщения отключены — раньше
      // нажатие «Отправить» без адресата выглядело так, будто ничего не
      // произошло).
      setState(() => _toError = l10n.tr('specifyRecipient'));
      _toFocus.requestFocus();
      unawaited(HapticFeedback.heavyImpact());
      return;
    }

    if (!await _smimeAllowsSend(l10n)) return;
    if (!mounted) return;

    // Группы рассылки среди получателей: письмо уйдёт всем их участникам —
    // одна строка в «Кому» может означать сотни человек. Подтверждение один
    // раз перед отправкой (раскрыть группу можно нажатием на неё).
    final groups = [..._toRecipients, ..._ccRecipients]
        .where((r) => _groupEmails.contains(r.email.toLowerCase()))
        .toList();
    if (groups.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(AppIcons.groups),
          title: Text(l10n.tr('groupSendTitle')),
          content: Text(l10n.tr('groupSendBody').replaceAll('{groups}', groups.map((g) => g.label).join(', '))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('send'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    // DLP-проверка (если включена)
    // Правила защиты от утечек — политика организации, для рабочих ящиков.
    if (settings.dlpEnabled && (_fromAccount?.isMsExchange ?? false)) {
      final dlpService = ref.read(dlpServiceProvider);
      final policy = ref.read(dlpSettingsProvider);
      final dlpResult = dlpService.checkOutgoingEmail(
        senderEmail: _fromAccount?.email ?? '',
        recipients: [..._toRecipients, ..._ccRecipients, ..._bccRecipients],
        subject: _subjectController.text.trim(),
        body: _authoredPlain,
        attachmentNames: _attachments.map((f) => f.name).toList(),
        checkPersonalData: policy.blockPersonalData,
        checkBankData: policy.blockBankData,
        checkClassified: policy.blockClassified,
        checkMassSend: policy.warnMassSend,
        massSendThreshold: policy.massSendThreshold,
        extraInternalDomains: policy.internalDomains,
      );

      if (dlpResult.hasViolations) {
        ref.read(dlpSettingsProvider.notifier).logViolations(dlpResult.violations);
        if (!mounted) return;
        final confirmed = await showDlpWarningDialog(context, dlpResult);
        if (!confirmed) return;
      }
    }

    // Подтверждение получателей: внешние адресаты и/или большой список (reply-all).
    // Защита от случайной отправки за пределы организации и reply-all-штормов.
    if (!await _confirmRecipients(l10n)) return;

    // Часть вложений оригинала не скачана: их докачивает фон, а что не
    // успело — отправка (сразу или из очереди, когда будет связь) либо
    // приложит сервер при пересылке Exchange (1.6.18). Окна «скачиваю…»
    // перед отправкой больше нет.

    // Встроенные картинки (скриншот вставили прямо в письмо) раздувают тело:
    // base64 длиннее оригинала на треть, а серверы режут письма по общему
    // размеру. Предупреждаем один раз, решение оставляем за человеком.
    final bodyForCheck = await _getBodyHtmlAsync();
    final inline = PasteCleaner.inlineImages(bodyForCheck);
    if (PasteCleaner.bodyBytes(bodyForCheck) > PasteCleaner.warnBodyBytes) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(AppIcons.photo_size_select_large),
          title: Text(l10n.tr('largeBodyTitle')),
          content: Text(l10n.tr('largeBodyBody')
              .replaceAll('{mb}', (PasteCleaner.bodyBytes(bodyForCheck) / 1048576).toStringAsFixed(1))
              .replaceAll('{n}', '${inline.count}')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.tr('sendAnyway')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // «Вы упомянули вложение, но не прикрепили файл» — типовая ошибка деловой
    // переписки. Цитируемая часть исключается, иначе предупреждение
    // срабатывало бы почти на каждый ответ.
    if (AttachmentHintService.shouldWarn(
      bodyText: _bodyPlain,
      hasAttachments: _attachments.isNotEmpty,
    )) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(AppIcons.attach_file),
          title: Text(l10n.tr('attachmentMissingTitle')),
          content: Text(l10n.tr('attachmentMissingBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('addAttachment')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.tr('sendAnyway')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Фото во вложениях: как есть или уменьшить (1.7.2+109). Шторку смахнули —
    // письмо не уходит.
    if (!await _chooseImageSize() || !mounted) return;

    // Smart Compose учится на отправленных фразах (частые формулировки станут
    // подсказками). Вызов здесь — единая точка для обычной отправки и Undo Send.
    ref.read(smartComposeProvider).learnFromSentEmail(_authoredPlain);

    // «На контроле»: отправленное письмо получит отметку «жду ответа», когда
    // появится в «Отправленных»; ответ на письмо «должен ответить» — исполнено.
    unawaited(_applyControlOnSend());

    // Отмена отправки (Undo Send): короткое окно, в течение которого можно
    // передумать. Окно живёт ВНУТРИ compose (поля блокируются) — при отмене
    // ничего не отправлено и письмо не потеряно. Ноль секунд = сразу.
    final undoSeconds = ref.read(featureFlagsProvider).undoSendSeconds;
    if (undoSeconds > 0) {
      // Письмо собирается (тело, файлы, уменьшение фото) — кнопка крутится.
      if (mounted) setState(() => _isSending = true);
      try {
        await _sendWithUndo(l10n, Duration(seconds: undoSeconds));
      } on _MissingFile {
        // Строка о файле уже вверху экрана, письмо не ушло.
      } finally {
        if (mounted) setState(() => _isSending = false);
      }
    } else {
      await _performSend(l10n);
    }
  }

  /// Перед отправкой: дождаться уже идущих фоновых загрузок вложений
  /// пересылаемого письма — их файлы уйдут обычными вложениями, а не будут
  /// качаться второй раз очередью отправки (1.6.18).
  Future<void> _awaitRunningDownloads() async {
    final running = [for (final p in _pendingOriginal) if (p.task != null) p.task!];
    if (running.isNotEmpty) await Future.wait(running);
  }

  /// Размер фото для отправки (1.7.2+109): «Размер фото при отправке» в
  /// настройках или шторка «Как есть / 75% / 50% / 25%». Фото нет или их
  /// мало (меньше [ImageShrink.askFromBytes] вместе) — как есть, без
  /// вопроса. false — шторку смахнули, письмо не отправлять.
  Future<bool> _chooseImageSize() async {
    _imageScale = 1;
    final images = [
      for (final f in _attachments)
        if (ImageShrink.isShrinkable(f.name) && !_isShrunk(f)) (name: f.name, size: f.size),
    ];
    final total = images.fold<int>(0, (s, f) => s + f.size);
    if (images.isEmpty || total < ImageShrink.askFromBytes) return true;
    final fixed = ref.read(featureFlagsProvider).photoSize;
    if (fixed != 0) {
      _imageScale = fixed / 100;
      return true;
    }
    final limit = _sizeLimit().limit;
    final picked = await showImageSizeSheet(context, images, other: _messageBytes - total, limit: limit);
    if (picked == null) return false;
    _imageScale = picked;
    return true;
  }

  /// Прочитать байты выбранных файлов для отправки (из bytes или по пути).
  /// Фото — уменьшенные до [_imageScale], если так выбрано (1.7.2+109; раньше
  /// фото больше 1,5 МБ молча ужимались до 1600 точек).
  /// Файла нет на телефоне (кэш вложений очистила система, файл удалили) —
  /// строка вверху экрана и [_MissingFile]: письмо без него не уходит
  /// (1.7.2+111; раньше файл молча пропадал из письма).
  Future<List<({String name, String? contentType, Uint8List bytes})>> _collectAttachments(AppLocalizations l10n) async {
    final result = <({String name, String? contentType, Uint8List bytes})>[];
    final scale = _imageScale;
    final shrink = scale < 1 && _attachments.any((f) => ImageShrink.isShrinkable(f.name));
    if (shrink && mounted) setState(() => _shrinking = true);
    var before = 0, after = 0, count = 0;
    try {
      for (final f in _attachments) {
        Uint8List? data;
        try {
          data = await f.readBytes();
        } catch (_) {}
        if (data == null) {
          showInlineError(l10n.tr('attachFileMissing').replaceAll('{file}', f.name));
          throw _MissingFile(f.name);
        }
        var name = f.name;
        var bytes = data;
        if (shrink && ImageShrink.isShrinkable(name) && !_isShrunk(f)) {
          final r = await ImageShrink.shrink(name, bytes, scale);
          before += bytes.length;
          after += r.bytes.length;
          count++;
          name = r.name;
          bytes = r.bytes;
        }
        result.add((name: name, contentType: _mimeForName(name), bytes: bytes));
      }
    } finally {
      if (shrink && mounted) setState(() => _shrinking = false);
    }
    if (count > 0) {
      AppLogger.info('Фото уменьшены до ${(scale * 100).round()}%: $count шт., '
          '${(before / 1048576).toStringAsFixed(1)} → ${(after / 1048576).toStringAsFixed(1)} МБ');
    }
    return result;
  }

  String? _mimeForName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    // Без типа файл уходит как application/octet-stream: фото HEIC и WebP,
    // видео и приглашения у получателя не открывались просмотром (1.8.13 —
    // добавлены частые типы).
    const m = {
      'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'gif': 'image/gif', 'txt': 'text/plain', 'zip': 'application/zip', 'csv': 'text/csv',
      'doc': 'application/msword', 'xls': 'application/vnd.ms-excel',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'ppt': 'application/vnd.ms-powerpoint', 'rtf': 'application/rtf',
      'odt': 'application/vnd.oasis.opendocument.text',
      'ods': 'application/vnd.oasis.opendocument.spreadsheet',
      'odp': 'application/vnd.oasis.opendocument.presentation',
      'heic': 'image/heic', 'heif': 'image/heif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'tif': 'image/tiff', 'tiff': 'image/tiff', 'svg': 'image/svg+xml',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mp3': 'audio/mpeg', 'm4a': 'audio/mp4',
      'wav': 'audio/wav', 'ogg': 'audio/ogg',
      // .eml — без message/rfc822: такую часть нельзя кодировать base64
      // (RFC 2046), и часть серверов отклоняет письмо.
      'ics': 'text/calendar', 'vcf': 'text/vcard',
      'html': 'text/html', 'htm': 'text/html', 'xml': 'application/xml', 'json': 'application/json',
      '7z': 'application/x-7z-compressed', 'rar': 'application/vnd.rar', 'gz': 'application/gzip',
    };
    return m[ext];
  }

  /// Отправка с окном отмены: письмо кладётся в Исходящие и уходит по истечении
  /// окна; экран закрывается сразу (как ждут пользователи), а отменить/
  /// отредактировать можно из тоста или прямо из папки Исходящие.
  /// Не скачанные вложения пересылаемого письма уходят ссылками: очередь
  /// скачает их перед отправкой (1.6.18; раньше письмо уходило без них).
  Future<void> _sendWithUndo(AppLocalizations l10n, Duration window) async {
    final account = _fromAccount!;
    final subject = _subjectController.text.trim();
    final bodyPlain = _bodyPlain;
    // Прежде здесь уходил текст без оформления (`<br>` вместо HTML редактора):
    // таблицы, списки и выделение терялись при «отправке с отменой».
    final bodyHtml = _withQuote(await _getBodyHtmlAsync());
    final offlineSend = ref.read(offlineSendProvider);

    await _awaitRunningDownloads();
    final outboxId = await offlineSend.scheduleUndoSend(
      accountId: account.id,
            importance: _importance,
            sensitivity: _sensitivity,
            attachments: await _collectAttachments(l10n),
            remoteAttachments: _pendingRefs(),
      fromEmail: _fromAlias ?? account.email,
      from: _fromOverride,
      to: List.of(_toRecipients),
      cc: List.of(_ccRecipients),
      bcc: List.of(_bccRecipients),
      subject: subject,
      bodyHtml: bodyHtml,
      bodyPlain: bodyPlain,
      inReplyTo: _inReplyTo,
      window: window,
    );
    await _finishDraft();
    await _markOriginalAnswered();
    unawaited(HapticFeedback.mediumImpact());
    if (!mounted) return;
    Navigator.of(context).pop(); // сразу к списку

    // «Отправка через N с · Отменить» — строкой над нижней панелью ленты
    // (PendingSendStrip); отдельная плашка не нужна (1.8.0).
    AppLogger.info('${l10n.tr('sendingInOutbox').replaceAll('{secs}', '${window.inSeconds}')} ($outboxId)');
  }

  /// Порог «большого списка» для предупреждения о reply-all.
  static const int _manyRecipientsThreshold = 8;

  /// Подтверждение получателей: если есть внешние адресаты (домен вне
  /// организации) и/или получателей слишком много — показать предупреждение.
  /// Возвращает true, если можно отправлять. Управляется флагом (по умолчанию вкл).
  Future<bool> _confirmRecipients(AppLocalizations l10n) async {
    final flags = ref.read(featureFlagsProvider);
    if (!flags.confirmRecipients) return true;

    final all = [..._toRecipients, ..._ccRecipients, ..._bccRecipients];
    if (all.isEmpty) return true;

    // Внешние адресаты имеют смысл только для рабочего ящика: с личной почты
    // (Gmail, Яндекс) все получатели «внешние», и предупреждение было бы на
    // каждом письме. Для личной почты остаётся только проверка «много
    // получателей».
    // Домены организации — по всем адресам ящика (адрес входа, основной с
    // сервера, алиасы) и с поддоменами («msk.corp.ru» — свой для «corp.ru»):
    // раньше «внешними» считались коллеги на втором домене организации.
    final acc = _fromAccount;
    final corporate = acc?.isMsExchange ?? false;
    final orgDomains = corporate && acc != null ? OwnAddresses.domains(acc) : const <String>{};
    final externalDomains = <String>{};
    for (final r in all) {
      final d = _domainOf(r.email);
      if (d.isNotEmpty && orgDomains.isNotEmpty && !orgDomains.any((o) => sameOrgDomain(d, o))) {
        externalDomains.add(d);
      }
    }
    final many = all.length >= _manyRecipientsThreshold;

    if (externalDomains.isEmpty && !many) return true; // всё в порядке

    final lines = <String>[];
    if (many) {
      lines.add(l10n.tr('goesToNRecipients').replaceAll('{n}', '${all.length}'));
    }
    if (externalDomains.isNotEmpty) {
      final shown = externalDomains.take(5).join(', ');
      lines.add(l10n.tr('externalRecipientsWarn')
          .replaceAll('{domains}', shown)
          .replaceAll('{ellipsis}', externalDomains.length > 5 ? '…' : ''));
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(AppIcons.warning, color: AppColors.accentOrangeText(context)),
        title: Text(l10n.tr('checkRecipients')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t),
              )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('send'))),
        ],
      ),
    );
    return confirmed == true;
  }

  String _domainOf(String email) {
    final at = email.lastIndexOf('@');
    return at >= 0 ? email.substring(at + 1).toLowerCase().trim() : '';
  }

  /// Настоящая отправка: sendOrQueue → уведомление → закрыть экран.
  /// Письмо ушло (отправлено/запланировано/переслано сервером) — черновик
  /// больше не нужен: снимаем автосохранение и убираем запись, иначе в
  /// «Черновиках» осталась бы копия уже отправленного письма.
  /// Отметить исходное письмо «Отвечено» / «Переслано» — значок в списке,
  /// как в Outlook (1.5.12). Сервер отмечает сам только при серверных
  /// ответе и пересылке; при обычной отправке отметки не было вовсе.
  Future<void> _markOriginalAnswered() async {
    // Исходное письмо — и у ответа, продолженного из «Черновиков» (1.7.0).
    final id = _parentId;
    final acc = _fromAccount;
    if (id == null || acc == null) return;
    try {
      final db = ref.read(databaseProvider);
      await (db.update(db.emails)
            ..where((e) => e.id.equals(id))
            ..where((e) => e.accountId.equals(_parentAccountId ?? widget.accountId ?? acc.id)))
          .write(!_parentForward
              ? const EmailsCompanion(isReplied: Value(true))
              : const EmailsCompanion(isForwarded: Value(true)));
    } catch (e) {
      AppLogger.debug('Отметка «Отвечено» не записана: $e');
    }
  }

  Future<void> _finishDraft({bool deleteServerCopy = true}) async {
    _sentOrDiscarded = true;
    // Серверная копия, которую должен был заменить этот черновик (его
    // открывали из «Черновиков», а новая версия ещё не выгружена — не было
    // связи): после отправки она тоже не нужна (1.7.2+111; раньше
    // оставалась на сервере).
    final replaced = _draftSync.replacesFor(_draftId);
    _forgetReplyDraft();
    _autosave?.savedAt.removeListener(_onDraftSaved);
    _autosave?.stopAutosave();
    unawaited(_draftSync.forget(_draftId));
    try {
      await _autosave?.deleteDraft(_draftId, _fromAccount?.id ?? '');
    } catch (_) {
      // Черновика могло и не быть (успели отправить до первого сохранения).
    }
    // Письмо из серверных «Черновиков» отправлено — убираем и его.
    final sd = _serverDraft;
    final acc = _fromAccount;
    // Файлы серверного черновика, которые ещё не скачаны, отправка берёт
    // из него самого — такой черновик пока не удаляем.
    final filesFromDraft = sd != null && _pendingRefs().any((r) => r.emailId == sd.id);
    if (deleteServerCopy && sd != null && acc != null && !filesFromDraft) {
      try {
        await ref.read(emailActionsProvider).delete(acc, sd.id, sd.folderId, hard: true);
      } catch (e) {
        AppLogger.warning('Серверный черновик не удалён: $e');
      }
    }
    if (deleteServerCopy &&
        replaced != null &&
        replaced.id != sd?.id &&
        acc != null &&
        !_pendingRefs().any((r) => r.emailId == replaced.id)) {
      try {
        await ref.read(emailActionsProvider).delete(acc, replaced.id, replaced.folderId, hard: true);
      } catch (e) {
        AppLogger.warning('Прежняя копия черновика не удалена: $e');
      }
    }
  }

  /// Попытка переслать силами сервера. true — письмо ушло, обычная отправка
  /// не нужна.
  ///
  /// С 1.5.12 — и для писем без вложений: как в Outlook, исходное письмо
  /// со шапкой и встроенными картинками добавляет сервер, вёрстка оригинала
  /// не пересобирается на телефоне.
  ///
  /// Не применяем, если:
  ///  · это не пересылка;
  ///  · протокол не умеет (IMAP/SMTP — там пересылки на сервере не существует);
  ///  · в тексте вставлены картинки — сервер берёт только текст;
  ///  · пользователь изменил набор вложений (убрал или добавил) — сервер
  ///    приложит ОРИГИНАЛЬНЫЕ, и результат разошёлся бы с тем, что на экране.
  Future<bool> _tryServerForward(
      AccountModel account, String subject, String bodyHtml) async {
    final srcId = widget.forwardFromId;
    if (srcId == null) return false;
    // Подписанное или зашифрованное письмо сервер дополнить не может (подпись
    // сломалась бы, шифр — тем более): отправляется целиком с устройства.
    if (_smimeActive) return false;
    // Сервер всегда добавляет оригинал целиком: если цитату правили или
    // убрали, отправляем то, что на экране.
    if (_quoteChanged) return false;
    if (_hasInlineImages(bodyHtml)) return false;

    final engine = ref.read(mailEngineServiceProvider);
    if (!engine.supportsServerForward(account)) return false;

    try {
      final db = ref.read(databaseProvider);
      final row = await db.getEmailById(srcId, accountId: widget.accountId ?? account.id);
      if (row == null) return false;

      final origCount = _originalAttachmentCount(row.attachmentsJson);
      // Простой редактор: цитата уже в тексте — сервер добавил бы оригинал
      // второй раз. Ради вложений это терпимо (как и до 1.5.12), без них —
      // обычная отправка.
      if (_quoteHtml == null && origCount == 0) return false;

      // Ключевая проверка. Часть вложений могла не скачаться локально — тогда
      // серверная пересылка ОБЯЗАТЕЛЬНА: только сервер приложит эти файлы.
      // Раньше их отсутствие делало число вложений «изменённым», серверная
      // пересылка отключалась, и письмо уходило без них.
      // Набор — по именам (1.7.2+111): раньше сравнивалось только число, и
      // замена одного файла другим уходила с исходным файлом вместо нового.
      final now = [for (final f in _attachments) f.name, for (final p in _pendingOriginal) p.name]..sort();
      if (!listEquals(now, _originalAttachmentNames(row.attachmentsJson))) {
        AppLogger.info('Серверная пересылка пропущена: набор вложений изменён '
            '(локально ${_attachments.length}, не скачано $_notDownloadedCount, было $origCount)');
        return false;
      }
      if (_notDownloadedCount > 0) {
        AppLogger.info('Пересылка через сервер: $_notDownloadedCount вложений '
            'нет локально, их приложит Exchange');
      }

      final ok = await engine.forwardOnServer(
        account,
        itemId: srcId,
        folderId: row.folderId,
        to: _toRecipients,
        cc: _ccRecipients,
        subject: subject,
        bodyHtml: bodyHtml,
        clientId: 'f$_draftId',
        sensitivity: _sensitivity,
        easQuoteHeader: _quoteChanged ? null : _quoteHeader,
      );
      if (ok) {
        AppLogger.info('Пересылка выполнена сервером: вложения не скачивались');
      }
      return ok;
    } catch (e) {
      AppLogger.warning('Серверная пересылка не удалась, отправляем обычным путём: $e');
      return false; // откат на обычную отправку
    }
  }

  /// Ответ силами сервера: ActiveSync SmartReply, Exchange (EWS) ReplyToItem
  /// (1.5.12) — исходное письмо, шапку и встроенные картинки добавляет сервер,
  /// как у ответа из Outlook. Только когда результат совпадает с тем, что на
  /// экране: цитата не менялась, нет своих вложений, скрытой копии и картинок
  /// в тексте (серверный ответ их не передаёт), у Exchange — и получатели
  /// те же, что были предложены.
  /// Иначе — обычная отправка с цитатой.
  Future<bool> _tryServerReply(AccountModel account, String subject, String bodyHtml) async {
    final srcId = widget.replyToId;
    if (srcId == null || _quoteChanged || _quoteHtml == null) return false;
    final ews = account.usesEws || account.isExchange;
    if (!ews && !account.usesEas) return false;
    if (_attachments.isNotEmpty || _bccRecipients.isNotEmpty) return false;
    // Exchange выбирает получателей сам: только если на экране — те же.
    if (ews && (_replySpecialCase || _replyRecipientsAtStart != _recipientsKey())) return false;
    if (_hasInlineImages(bodyHtml)) return false;
    if (_smimeActive) return false; // сервер не может дополнить подписанное письмо
    try {
      final db = ref.read(databaseProvider);
      final row = await db.getEmailById(srcId, accountId: widget.accountId ?? account.id);
      if (row == null) return false;
      final ok = await ref.read(mailEngineServiceProvider).replyOnServer(
            account,
            itemId: srcId,
            folderId: row.folderId,
            to: _toRecipients,
            cc: _ccRecipients,
            subject: subject,
            bodyHtml: bodyHtml,
            clientId: 'r$_draftId',
            sensitivity: _sensitivity,
            replyAll: widget.replyAll,
            easQuoteHeader: _quoteHeader,
          );
      if (ok) AppLogger.info('Ответ собран сервером (${ews ? 'ReplyToItem' : 'SmartReply'})');
      return ok;
    } catch (e) {
      AppLogger.warning('Серверный ответ не удался, отправляем обычным путём: $e');
      return false;
    }
  }

  /// Картинки, вставленные в текст (data:/cid:). Серверные ответ и
  /// пересылка берут только текст: такие картинки до адресата не дошли бы.
  static bool _hasInlineImages(String html) =>
      RegExp(r'''<img[^>]+src\s*=\s*["']?\s*(?:data:|cid:)''', caseSensitive: false).hasMatch(html);

  /// Встроенная картинка (уже в тексте цитаты), а не вложение. Outlook
  /// помечает «встроенными» и обычные файлы (PDF, документы с Content-ID) —
  /// такие при пересылке терялись (1.6.12): встроенной считаем только
  /// картинку.
  static bool _isInlineImage(Map m) {
    if (m['isInline'] != true) return false;
    final mime = (m['mimeType'] ?? m['contentType'] ?? '').toString().toLowerCase();
    if (mime.startsWith('image/')) return true;
    if (mime.isNotEmpty) return false;
    final name = (m['name'] ?? '').toString().toLowerCase();
    return RegExp(r'\.(png|jpe?g|gif|bmp|webp|tiff?)$').hasMatch(name);
  }

  /// Имена вложений исходного письма (без встроенных картинок), по порядку.
  static List<String> _originalAttachmentNames(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(raw) as List).whereType<Map>())
          if (!_isInlineImage(m)) EmailAttachment.fromMap(Map<String, dynamic>.from(m)).name,
      ]..sort();
    } catch (_) {
      return const [];
    }
  }

  int _originalAttachmentCount(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final list = jsonDecode(raw) as List;
      return list.where((m) => !_isInlineImage(m as Map)).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _performSend(AppLocalizations l10n) async {
    if (!mounted) return;
    setState(() => _isSending = true);
    try {
      final account = _fromAccount!;
      final subject = _subjectController.text.trim();
      // Только новый текст: серверные ответ и пересылка добавляют оригинал сами.
      final bodyHtml = await _getBodyHtmlAsync();

      // ── ОТВЕТ СИЛАМИ СЕРВЕРА (ActiveSync SmartReply) ──
      // Exchange сам добавляет исходное письмо: вёрстка Outlook, встроенные
      // картинки и шапка — как в Outlook, без пересборки на телефоне.
      if (await _tryServerReply(account, subject, bodyHtml)) {
        await _finishDraft();
        await _markOriginalAnswered();
        unawaited(HapticFeedback.mediumImpact());
        if (mounted) {
          AppLogger.info(l10n.tr('emailSent'));
          Navigator.of(context).pop();
        }
        return;
      }

      // ── ПЕРЕСЫЛКА СИЛАМИ СЕРВЕРА ──
      // Exchange умеет переслать письмо сам (EWS ForwardItem / EAS SmartForward):
      // оригинальные вложения он берёт из исходного сообщения, и они НЕ
      // скачиваются на устройство и не отправляются обратно. Для письма с
      // тяжёлыми файлами это разница между «мгновенно» и «выкачать и залить
      // десятки мегабайт по мобильной сети».
      // Условия: это пересылка, вложения пользователь не менял.
      if (await _tryServerForward(account, subject, bodyHtml)) {
        await _finishDraft();
        await _markOriginalAnswered();
        unawaited(HapticFeedback.mediumImpact());
        if (mounted) {
          AppLogger.info(l10n.tr('forwardedServer'));
          Navigator.of(context).pop();
        }
        return;
      }

      // Серверная пересылка не состоялась (нет связи, сервер отказал, набор
      // вложений менялся), а часть вложений не скачана. Обычная отправка ушла
      // бы без этих файлов — молча. Теперь их докачивает отправка: сразу, а
      // без связи — очередь, письмо уйдёт вместе с ними (1.6.18).
      await _awaitRunningDownloads();
      final remote = _pendingRefs();

      // sendOrQueue: при ошибке/офлайне письмо ставится в очередь (Outbox),
      // не теряется, дошлётся автоматически при восстановлении связи.
      final sent = await ref.read(offlineSendProvider).sendOrQueue(
            accountId: account.id,
            importance: _importance,
            sensitivity: _sensitivity,
            attachments: await _collectAttachments(l10n),
            to: _toRecipients,
            cc: _ccRecipients,
            bcc: _bccRecipients,
            subject: subject,
            bodyHtml: _withQuote(bodyHtml),
            inReplyTo: _inReplyTo,
            remoteAttachments: remote,
            from: _fromOverride,
            // Не принято по размеру — письмо остаётся здесь (ниже).
            keepTooLarge: true,
          );

      // И при отправке, и при постановке в очередь черновик не нужен: письмо
      // уже в Исходящих и уйдёт само.
      await _finishDraft();
      await _markOriginalAnswered();
      unawaited(HapticFeedback.mediumImpact());

      if (mounted) {
        // Отправлено — видно по ленте; в очереди — сказать, что письмо ещё
        // не ушло и уйдёт само.
        if (sent) {
          AppLogger.info(l10n.tr('emailSent'));
        } else {
          showInlineNotice(remote.isNotEmpty ? l10n.tr('attPendingQueued') : l10n.tr('queuedOutbox'));
        }
        Navigator.of(context).pop();
      }
    } on MessageTooLargeException catch (e) {
      // Сервер или шлюз организации не принял письмо по размеру (1.7.2+114):
      // письмо остаётся открытым — уменьшить фото («Сжать») или убрать файлы
      // и отправить снова. Раньше редактор закрывался, а письмо пропадало.
      if (mounted) showInlineError(OfflineSendService.tooLargeText(l10n, e));
    } catch (e) {
      if (mounted && e is! _MissingFile) {
        showInlineError(e.toString().contains('offline_queue_full')
              ? l10n.tr('offlineQueueFull')
              : '${l10n.tr('sendError')}: $e');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Закрыть письмо (крестик, системное «Назад», жест): пустое (только
  /// приветствие и подпись) и открытый черновик, который не меняли, —
  /// сразу; иначе шторка: «Сохранить черновик», «Удалить», «Продолжить».
  /// Раньше системное «Назад» закрывало письмо молча, а окно с вопросом
  /// называлось «Отменить» и спрашивало «Удалить черновик?» с тремя
  /// одинаковыми на вид кнопками.
  void _onDiscard(AppLocalizations l10n) {
    if (_sentOrDiscarded || _snapshot().isEmpty || (_openedDraft && _isPristine)) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(_askClose(l10n));
  }

  Future<void> _askClose(AppLocalizations l10n) async {
    FocusScope.of(context).unfocus();
    if (_useHtmlEditor) unawaited(_editor.blur());
    // Есть что сохранить — текст, адресаты, тема или файлы (1.7.2+111:
    // черновик хранит и файлы).
    final canSave = !_snapshot().isEmpty;
    final choice = await showAppSheet<_CloseChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _CloseDraftSheet(
        canSave: canSave,
        openedDraft: widget.draftId != null || _openedDraft,
      ),
    );
    if (!mounted || choice == null || choice == _CloseChoice.keepWriting) return;
    if (choice == _CloseChoice.delete) {
      await _deleteDraftCompletely();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    // «Сохранить»: при закрытии окна (dispose) — на телефон и в серверные
    // «Черновики».
    Navigator.of(context).pop();
  }

  /// «Удалить»: черновик убирается и с устройства, и из серверной папки
  /// (в корзину), если письмо было открыто оттуда.
  Future<void> _deleteDraftCompletely() async {
    // И копия, которую должен был заменить невыгруженный черновик.
    final sd = _serverDraft ?? _draftSync.replacesFor(_draftId);
    await _finishDraft(deleteServerCopy: false);
    final acc = _fromAccount;
    if (sd != null && acc != null) {
      try {
        await ref.read(emailActionsProvider).delete(acc, sd.id, sd.folderId);
      } catch (_) {}
    }
  }

  /// Вставить шаблон ответа (с подстановкой полей) в позицию курсора.
  Future<void> _insertTemplate() async {
    final l10n = AppLocalizations.of(context);
    final templates = [for (final t in ref.read(templatesProvider)) t.resolve(l10n.tr)];
    if (templates.isEmpty) {
      showInlineNotice(l10n.tr('noTemplates'));
      return;
    }
    // Карточкой (1.8.8), как меню «⋮».
    final i = await showChoiceSheet<int>(
      context,
      title: l10n.tr('insertTemplate'),
      entries: [
        for (final (i, t) in templates.indexed)
          AppMenuEntry(
            value: i,
            label: t.title,
            icon: AppIcons.article,
            subtitle: t.body.length > 80 ? '${t.body.substring(0, 80).trim()}…' : t.body,
          ),
      ],
    );
    if (i == null) return;
    final chosen = templates[i];
    final text = applyPlaceholders(chosen.body,
        name: _fromAccount?.displayName,
        email: _fromAccount?.email,
        phone: ref.read(signatureProvider).phone);
    _insertBodyPlainAtCursor(text);
  }

  Future<void> _pickAttachments() async {
    final l10n = AppLocalizations.of(context);
    final limit = _fromAccount != null
        ? ref.read(attachmentLimitProvider).limitFor(_fromAccount!.id)
        : AppConstants.maxAttachmentSize;
    try {
      final picked = await FilePick.files();
      var total = _attachments.fold<int>(0, (s, f) => s + f.size);
      for (final chosen in picked) {
        // Блокируем по СУММАРНОМУ объёму (лимит сервера), а не только по
        // одному файлу. Строкой вверху экрана: чёрные плашки в приложении
        // выключены, и раньше превышение лимита молча ничего не делало.
        // Фото добавляются и сверх лимита (1.7.2+110): при отправке их можно
        // уменьшить — строка размера покажет, на сколько письмо тяжелее.
        if (total + chosen.size > limit && !ImageShrink.isShrinkable(chosen.name)) {
          final mb = (limit / (1024 * 1024)).toStringAsFixed(0);
          showInlineError(l10n.tr('attachLimitExceeded').replaceAll('{mb}', mb).replaceAll('{file}', chosen.name));
          continue;
        }
        final file = await chosen.keepable();
        total += file.size;
        if (!mounted) return;
        setState(() => _attachments.add(file));
      }
      // Файлы — в черновик (1.7.2+111).
      if (picked.isNotEmpty) _markDraftChanged();
    } catch (e) {
      AppLogger.warning('Вложения: выбор файлов не удался — $e');
      showInlineError('${l10n.tr('error')}: $e');
    }
  }

  void _showTemplates(AppLocalizations l10n) {
    // Карточкой (1.8.8), как меню «⋮».
    final texts = [
      for (final k in const [
        'templateAccepted', 'templateApproved', 'templateInProgress', 'templateClarify',
        'templateThankYou', 'templateWillDo', 'templateMeetingOk', 'templateCannotAttend',
      ])
        l10n.tr(k),
    ];
    unawaited(showChoiceSheet<String>(
      context,
      title: l10n.tr('templates'),
      entries: [for (final t in texts) AppMenuEntry(value: t, label: t, icon: AppIcons.quickreply)],
    ).then((text) {
      if (text == null || !mounted) return;
      _insertBodyPlainAtCursor(text);
      HapticFeedback.selectionClick();
    }));
  }

}

/// Получатель в поле «Кому/Копия»: плашка 28 dp, имя и крестик.
/// Плашка адресата, которую несут в другую строку.
class _DragRecipient {
  final EmailAddress address;
  final List<EmailAddress> from;
  const _DragRecipient(this.address, this.from);
}

class _RecipientPill extends StatelessWidget {
  final String text;
  final String tooltip;
  final VoidCallback onRemove;
  /// Адрес — для фото адресата на плашке.
  final String email;

  /// Группа рассылки: значок группы, нажатие — действия (раскрыть).
  final bool isGroup;
  final VoidCallback? onTap;

  const _RecipientPill({
    required this.text,
    required this.tooltip,
    required this.onRemove,
    required this.email,
    this.isGroup = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      // Удержание пальцем — перетаскивание плашки, адрес — по наведению мыши.
      triggerMode: TooltipTriggerMode.manual,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Фото адресата (раньше на плашке было только имя).
            if (isGroup)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: Space.xs),
                child: Icon(AppIcons.groups, size: 16, color: scheme.onSecondaryContainer),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: HeroEmailAvatar(
                  emailId: 'pill/$email',
                  initial: text.isNotEmpty ? initialOf(text) : '?',
                  color: HeroEmailAvatar.colorForEmail(email),
                  email: email,
                  radius: 12,
                  hero: false,
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: GestureDetector(
               onTap: onTap,
               child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSecondaryContainer),
              ),
              ),
            ),
            InkResponse(
              onTap: onRemove,
              radius: 14,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(AppIcons.close, size: 16, color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Вложение пересылаемого письма, ещё не скачанное на телефон (1.6.18).
enum _CloseChoice { save, delete, keepWriting }

/// Шторка при закрытии несохранённого письма (1.7.0, как в почте iPhone):
/// сохранить черновик, удалить или вернуться к письму.
class _CloseDraftSheet extends StatelessWidget {
  final bool canSave;
  final bool openedDraft;
  const _CloseDraftSheet({required this.canSave, required this.openedDraft});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(left: Space.xl, right: Space.xl, bottom: Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.tr(canSave ? 'draftCloseTitle' : 'draftCloseEmptyTitle'), style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.s),
          if (canSave) Text(l10n.tr('draftCloseHint'), style: muted),
          const SizedBox(height: Space.l),
          if (canSave) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Sizes.tapTarget)),
              onPressed: () => Navigator.of(context).pop(_CloseChoice.save),
              icon: const Icon(AppIcons.save),
              label: Text(l10n.tr('saveDraft')),
            ),
            const SizedBox(height: Space.s),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.tapTarget),
              foregroundColor: AppColors.errorText(context),
            ),
            onPressed: () => Navigator.of(context).pop(_CloseChoice.delete),
            icon: const Icon(AppIcons.delete),
            label: Text(l10n.tr(!canSave
                ? 'draftCloseDiscard'
                : (openedDraft ? 'draftDelete' : 'draftDiscardNew'))),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Sizes.tapTarget)),
            onPressed: () => Navigator.of(context).pop(_CloseChoice.keepWriting),
            child: Text(l10n.tr('draftKeepWriting')),
          ),
        ],
      ),
    );
  }
}

/// Файла письма нет на телефоне — отправка остановлена (см. _collectAttachments).
class _MissingFile implements Exception {
  final String name;
  const _MissingFile(this.name);

  @override
  String toString() => 'нет файла «$name»';
}

class _PendingFile {
  final String id;
  final String name;
  final int size;
  final String? mimeType;
  bool loading = false;
  bool failed = false;
  Future<bool>? task;

  _PendingFile({required this.id, required this.name, required this.size, this.mimeType});
}
