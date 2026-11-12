// lib/features/mail/screens/mail_detail_screen.dart
// Просмотр письма:
// - Lazy-загрузка вложений по клику (не при открытии)
// - Загрузка тела при fetchMode=headersOnly
// - ИИ-шторка по кнопке ✨
// - Conversation thread (цепочка писем)
// - Bottom sheet действий (19 действий как в референсе Nine)
// - Кнопка отзыва (recall) для отправленных
// - DLP-проверка при пересылке
// - Haptic feedback, Semantics, SafeAsync

import '../../../widgets/ui/banner_button.dart';
import '../../../core/platform/download_saver.dart';
import '../../../core/platform/file_opener.dart';
import '../../../widgets/ui/section_band.dart';
import '../../../widgets/common/peek_card.dart' show AppMenuEntry, PeekAction, PeekGroup;
import '../message_window.dart';
import '../../assignments/assign_sheet.dart' show showAssignSheet;
import '../../assignments/assignment_widgets.dart';
import '../../../services/assignments/assignment_codec.dart' show AssignmentCodec;
import '../../../services/assignments/assignment_service.dart';
import '../widgets/mail_peek_card.dart' show showMailPeek;
import '../widgets/unsubscribe_banner.dart';
import '../widgets/booking_card.dart';
import '../widgets/control_sheet.dart';
import '../../../services/mail/unsubscribe_service.dart' show encodeListUnsubscribe, ListUnsubscribe;
import '../../../services/mail/reply_drafts.dart' show conversationReplyDrafts, replyDraftsProvider;
import '../../../services/security/managed_config.dart' show ManagedPolicy, ManagedRule;
import '../../tasks/widgets/task_editor_sheet.dart' show showTaskEditorForEmail;
import '../../../core/utils/text_safe.dart';
import '../../../core/utils/symbol_fonts.dart';
import '../../../core/navigation/app_router.dart' show mailOpenPath;
import '../../../core/theme/app_icons.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../services/mail/transport_capabilities.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../../../widgets/ui/file_type_icon.dart';
import '../../../widgets/ui/action_sheet.dart';
import 'package:flutter/services.dart' hide UndoManager;
import '../../../core/theme/mail_page_color.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../services/export/email_pdf_service.dart';

import '../../../core/theme/tokens.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice, quietError, quietNotice;
import '../../../core/theme/app_theme.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/open_trace.dart';
import '../../../services/mail/ews/ews_service.dart' show ewsServiceProvider;
import '../../../core/security/mail_body_processor.dart';
import '../../../services/security/tracker_blocker.dart';
import '../../../core/utils/async_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/models/account_model.dart';
import '../../../widgets/common/keyboard_shortcuts.dart' show TypingAwareShortcuts;
import '../../../widgets/common/undo_manager.dart';
import '../providers/mail_providers.dart';
import '../widgets/sender_safety_banner.dart';
import '../widgets/meeting_invite_banner.dart';
import '../providers/mail_open_cache.dart';
import '../../../services/sync/offline_store_service.dart' show offlineStoreProvider;
import '../../contacts/widgets/person_card.dart';
import '../../../services/mail/control_service.dart';
import '../../../services/mail/later_service.dart';
import '../widgets/later_sheet.dart';
import '../widgets/sender_actions_sheet.dart';
import '../../settings/screens/device_rule_screen.dart' show openDeviceRule;
import '../../../services/mail/own_addresses.dart';
import '../../../services/security/mail_classification.dart';
import '../../../services/security/smime_service.dart' show smimeServiceProvider, CmsSignature;
import '../../settings/providers/categories_provider.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../features/settings/providers/feature_flags_provider.dart';
import '../../settings/widgets/feature_settings_sections.dart' show ExperimentalKeys, QuotePeopleMode, quotePeopleMode;
import '../widgets/linkified_text.dart';
import '../widgets/mail_clipped_bar.dart';
import '../widgets/mail_native_body.dart';
import '../widgets/mail_translation.dart';
import '../../../services/translation/translator.dart' show translationPlatformSupported;
import '../../../core/utils/mail_clip.dart';
import '../widgets/mail_header.dart';
import '../widgets/conversation_thread_view.dart';
import '../widgets/quick_reply_bar.dart';
import '../providers/drawer_prefs.dart'
    show quickReplyBarProvider, mailBarOrderProvider, MailBarAction, confirmMailDeleteProvider;
import '../../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../widgets/attachment_drag_out.dart';
import '../widgets/move_folder_picker.dart';
import '../widgets/mail_html_view.dart';
import '../widgets/mac_mail_web_view.dart';
import '../../../widgets/common/readable_width.dart';
import '../providers/conversation_mute.dart';
import '../widgets/read_receipt_banner.dart';
import '../widgets/delivery_status_banner.dart';
import '../widgets/mail_notice_bar.dart';
import '../../../services/security/sender_safety_service.dart' show senderSafetyServiceProvider, SafetyLevel, SenderSafetyReport;
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../archive/archive_sheets.dart' show ensureArchiveReady;
import '../../../services/archive/archive_runner.dart' show archiveRunnerProvider;
import '../../../services/archive/archive_settings.dart' show archiveSettingsProvider;
import '../../../services/mail/special_folders.dart';
import '../../../services/mail/imap/imap_service.dart';
import '../../../services/mail/email_actions_service.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/animated_appearance.dart';
import '../../../core/utils/quote_splitter.dart';
import '../../../services/mail/eml_builder.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/dom.dart' as dom;
import '../../../core/security/link_opener.dart';
import '../../../core/utils/date_links.dart';
import '../widgets/date_link_sheet.dart';
import 'attachment_preview_screen.dart';
import '../widgets/mail_find.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../services/mail/tnef/tnef_decoder.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../compose/providers/templates_provider.dart' show templatesProvider;
import '../../compose/screens/compose_screen.dart' show ComposeScreen;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../core/theme/ogneliss_look.dart';
import '../../../core/theme/appearance.dart' show AppearanceLook;
import '../../../widgets/common/mail_open_motion.dart' show MailHeroTags, MailOpenHandoff, MailSubjectHero;
import '../../../core/utils/quote_people.dart';
import '../../../widgets/common/person_photo.dart' show personPhotosProvider;
import '../../settings/providers/module_settings_provider.dart' show moduleSettingsProvider;
import '../../../services/contacts/mail_contacts_service.dart' show mailContactsServiceProvider;
import '../../../core/platform/app_share.dart';
import '../../../widgets/common/pane_navigator.dart';

class MailDetailScreen extends ConsumerStatefulWidget {
  final String emailId;
  final String accountId;
  final bool embedded;

  /// Письмо открыто из беседы: в шапке «2 / 8» и стрелки к соседним письмам,
  /// цепочка под письмом не показывается — беседа уже на предыдущем экране.
  final String? pagerLabel;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// Страница беседы остановилась на этом письме (false — его листают
  /// мимо): тело письма и отметка «прочитано» — только для остановленной
  /// страницы.
  final bool active;

  /// Поиск по беседе (2.2.0): письмо открывается с этим поиском.
  final String? findQuery;

  const MailDetailScreen({
    super.key,
    required this.emailId,
    required this.accountId,
    this.embedded = false,
    this.pagerLabel,
    this.onPrev,
    this.onNext,
    this.active = true,
    this.findQuery,
  });

  @override
  ConsumerState<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends ConsumerState<MailDetailScreen>
    with SafeAsyncState<MailDetailScreen> {
  EmailModel? _email;
  bool _isLoading = true;
  /// Перевод письма на устройстве (1.9.x, просьба владельца 31.10.2026):
  /// плашка «Перевести», перевод вместо текста, «Показать оригинал».
  /// Масштаб широкого письма — пилюлей в строке сведений (1.15.1): окно
  /// письма сообщает, что доступно, строка рисует.
  final MailScaleControl _scale = MailScaleControl();

  /// Проверка отправителя (антифишинг) для пилюли предупреждения (1.15.1):
  /// раньше её считала карточка над письмом. Ключ — то, от чего проверка
  /// зависит: тело (ссылки), вложения, заголовки подлинности.
  String _safetyKey = '';
  SenderSafetyReport? _safety;

  late final MailTranslationController _translation =
      MailTranslationController(ref)..addListener(() => safeSetState(() {}));
  bool _isLoadingBody = false;
  bool _readReceiptHandled = false;
  late bool _showQuote = (widget.findQuery ?? '').trim().isNotEmpty;

  /// Поиск в письме (2.2.0, план 08.11.2026): строка под заголовком;
  /// из поиска по беседе — сразу открыта, с тем же запросом.
  final MailFindController _find = MailFindController();
  late bool _findOpen = (widget.findQuery ?? '').trim().isNotEmpty;

  /// Открыть поиск: письмо — целиком и с перепиской, чтобы искалось всё.
  void _openFind() {
    if (_findOpen) return;
    safeSetState(() {
      _findOpen = true;
      _showQuote = true;
      _showWhole = true;
    });
  }

  void _closeFind() {
    _find.setQuery('');
    safeSetState(() => _findOpen = false);
  }
  /// Тело до очистки трекеров — чтобы по «Показать изображения» обработать
  /// его заново, не загружая письмо повторно.
  String? _rawBodyHtml;
  int _externalImagesBlocked = 0;
  List<BlockedImage> _blockedItems = const [];
  bool _imagesAllowed = false;
  String? _splitSource;
  QuoteSplit? _split;
  String? _error;

  /// Состояние загрузки каждого вложения
  final Map<String, _AttachmentState> _attachmentStates = {};
  bool _busyAll = false; // идёт групповая операция со вложениями

  /// Цепочка беседы
  List<EmailModel>? _conversationEmails;

  /// Быстрый ответ ↔ кнопки «Ответить» под письмом (1.7.3).
  final _quickReply = QuickReplyController();


  @override
  void initState() {
    super.initState();
    // Докачка «Писем на телефоне» ждёт несколько секунд: сеть и процессор —
    // открытому письму.
    ref.read(offlineStoreProvider).hold();
    // Шапка из строки ленты (1.9.x, «Анимация открытия письма»): портрет и
    // тема — уже в первом кадре, им есть куда лететь; тело — как обычно.
    final early = widget.embedded ? null : MailOpenHandoff.take(widget.accountId, widget.emailId);
    if (early != null) {
      _email = early;
      _isLoading = false;
      _isLoadingBody = true;
    }
    _loadEmailDetail();
    // Журнал открытых писем для «Продолжить» больше не ведётся (раздел
    // убран 10.10.2026); прежний журнал стирается (один раз, а не запись в
    // настройки при каждом открытии письма).
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.containsKey('opened_recent_v1')) unawaited(prefs.remove('opened_recent_v1'));
    _whenShown(() => unawaited(_clearReturned()));
  }

  // ── Переход на экран письма ──
  // Пока экран выезжает, делается только то, что нужно для показа. То, что
  // перестраивает ленту под экраном (отметка «прочитано»), читает базу и
  // сеть (цепочка, заголовки ActiveSync) или тяжело считает (проверка
  // отправителя, приглашение, подпись S/MIME), — после перехода: раньше всё
  // это шло прямо во время анимации, и она «дико тормозила» (11.10.2026).
  bool _routeDone = false;
  Animation<double>? _routeAnim;

  bool get _settled => _routeDone && widget.active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeDone) return;
    final anim = widget.embedded ? null : ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      _routeDone = true;
      _flushAfterSettle();
      return;
    }
    if (!identical(anim, _routeAnim)) {
      _routeAnim?.removeStatusListener(_onRouteStatus);
      _routeAnim = anim..addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus st) {
    if (st != AnimationStatus.completed) return;
    _routeAnim?.removeStatusListener(_onRouteStatus);
    _routeAnim = null;
    if (!mounted || _routeDone) return;
    setState(() => _routeDone = true);
    _flushAfterSettle();
  }

  @override
  void didUpdateWidget(MailDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      ref.read(offlineStoreProvider).hold();
      _flushAfterSettle();
    }
  }

  // ── После показа текста (1.5.9) ──
  // Работа, которая читает и пишет базу или перестраивает ленту под
  // экраном («прочитано», цепочка беседы, снятие «Вернулось», заголовки
  // ActiveSync), раньше запускалась ровно по концу перехода — в тот же кадр,
  // когда создавался WebView, — и отнимала главный поток у его загрузки и
  // замеров. Теперь — когда текст показан (MailHtmlView.onShown), но не
  // позже чем через [_shownFallback] после перехода (письмо без WebView,
  // ошибка загрузки).
  bool _bodyShown = false;
  Timer? _shownTimer;
  final List<VoidCallback> _afterShown = [];
  final Completer<void> _shown = Completer<void>();
  static const _shownFallback = Duration(milliseconds: 600);

  void _whenShown(VoidCallback f) {
    _afterShown.add(f);
    _flushAfterShown();
  }

  void _onBodyShown() {
    if (_bodyShown) return;
    _bodyShown = true;
    _shownTimer?.cancel();
    if (!_shown.isCompleted) _shown.complete();
    _flushAfterShown();
  }

  void _flushAfterShown() {
    if (!_settled) return;
    if (!_bodyShown) {
      _shownTimer ??= Timer(_shownFallback, () {
        if (mounted) _onBodyShown();
      });
      return;
    }
    if (_afterShown.isEmpty) return;
    final list = List<VoidCallback>.of(_afterShown);
    _afterShown.clear();
    // После кадра — не внутри построения экрана (кадр запрашивается: без
    // него обратный вызов ждал бы следующей перерисовки).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final f in list) {
        f();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Переход закончился (или страница беседы остановилась на письме):
  /// запустить отложенное, если текст уже показан.
  void _flushAfterSettle() => _flushAfterShown();

  @override
  void dispose() {
    _routeAnim?.removeStatusListener(_onRouteStatus);
    _inlineWait?.cancel();
    _shownTimer?.cancel();
    OpenTrace.cancel();
    _quickReply.dispose();
    _translation.dispose();
    _scale.dispose();
    _find.dispose();
    super.dispose();
  }

  /// Вернувшееся («Посмотреть позже») письмо открыто — отметка «Вернулось»
  /// снимается: дальше это обычное прочитанное письмо.
  Future<void> _clearReturned() async {
    try {
      final row = await ref.read(mailOpenCacheProvider).row(widget.accountId, widget.emailId);
      if (row == null || row.laterState != LaterState.returned || !mounted) return;
      final emails = ref.read(emailsProvider.notifier);
      final later = ref.read(laterRevisionProvider.notifier);
      await ref.read(emailActionsProvider).clearReturned(widget.emailId, widget.accountId);
      emails.applyLocalFlags(widget.emailId, laterState: LaterState.none);
      later.state++;
      if (_email != null) safeSetState(() => _email = _email!.copyWith(laterState: LaterState.none));
    } catch (e) {
      AppLogger.debug('Позже — снятие «Вернулось»: $e');
    }
  }

  Future<void> _loadEmailDetail() async {
    try {
      safeSetState(() {
        // Шапка из ленты уже на экране — без индикатора на весь экран.
        _isLoading = _email == null || _error != null;
        _error = null;
      });

      // Аккаунт мог быть удалён, пока экран открыт: firstWhere без orElse
      // бросал бы StateError и ронял операцию.
      var found = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
      if (found == null) {
        // Письмо открыто сразу после запуска (уведомление, ссылка), ящики
        // ещё грузятся — подождать их. Раньше экран здесь выходил и вечно
        // показывал индикатор загрузки (28.10.2026).
        await ref.read(accountsProvider.notifier).loaded.timeout(const Duration(seconds: 10), onTimeout: () {});
        if (!mounted) return;
        found = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
        if (found == null) {
          final notFound = AppLocalizations.of(context).tr('mailNotFound');
          safeSetState(() {
            _isLoading = false;
            _error = notFound;
          });
          return;
        }
      }
      final account = found;
      final cache = ref.read(mailOpenCacheProvider);

      if (account.usesEws || account.isExchange) {
        // Сначала — копия из базы, если тело уже есть: письмо открывается
        // сразу, а не через секунду ожидания сервера (раньше EWS-письмо
        // каждый раз запрашивалось заново, даже открытое минуту назад).
        final db = ref.read(databaseProvider);
        final cachedRow = await cache.row(widget.accountId, widget.emailId);
        String? shownHtml, shownPlain;
        if (cachedRow != null &&
            ((cachedRow.bodyHtml ?? '').isNotEmpty || (cachedRow.bodyPlain ?? '').isNotEmpty)) {
          // Шапка — сразу, как у IMAP и ActiveSync: раньше у EWS до конца
          // подготовки тела на экране был только индикатор (1.5.9).
          final header = emailModelFromRow(cachedRow);
          final rawHtml = header.bodyHtml ?? '';
          final o = cache.optionsFor(header);
          final ready = rawHtml.isEmpty ||
              cache.peekPrepared(rawHtml, options: o.options, allowImages: o.allowImages, dates: cache.datesFor(header)) !=
                  null;
          if (!ready) {
            safeSetState(() {
              _email = header;
              _isLoading = false;
              _isLoadingBody = true;
              for (final att in header.attachments) {
                _attachmentStates.putIfAbsent(att.id, () => const _AttachmentState());
              }
            });
          }
          final cached = await _secureBody(header);
          if (!mounted) return;
          shownHtml = cachedRow.bodyHtml;
          shownPlain = cachedRow.bodyPlain;
          safeSetState(() {
            _email = cached;
            _isLoading = false;
            _isLoadingBody = false;
            for (final att in cached.attachments) {
              _attachmentStates[att.id] = const _AttachmentState();
            }
          });
          _startInlineImages(cached);
        }
        final shownCached = shownHtml != null || shownPlain != null;

        // Загружаем в зависимости от fetchMode (через фасад движка)
        // Копия на экране — запрос к серверу ждёт показа текста (не дольше
        // 2 с): ответ сервера, запись в базу и пересборка не должны делить
        // главный поток с созданием WebView (1.5.9).
        if (shownCached) {
          await _shown.future.timeout(const Duration(seconds: 2), onTimeout: () {});
          if (!mounted) return;
        }
        final EmailModel? email;
        try {
          email = await safeAsync<EmailModel?>(() =>
              ref.read(mailEngineServiceProvider).fetchEmailDetailEws(account, widget.emailId));
        } catch (e) {
          // Нет сети — показана копия из базы, ошибку не выводим.
          if (shownCached) {
            AppLogger.warning('MailDetail: сервер недоступен, показана сохранённая копия: $e');
            final shown = _email;
            if (shown != null) _afterOpen(account, shown);
            return;
          }
          rethrow;
        }

        if (email == null) return; // Widget disposed

        // Копия совпала с сервером — экран не перерисовываем (раньше письмо
        // «догружало» текст и оформление уже после открытия).
        final sameBody = shownCached && shownHtml == email.bodyHtml && shownPlain == email.bodyPlain;

        // В базу — одной записью и только то, что изменилось (1.5.9). Раньше
        // при каждом открытии писались тело (с цепочкой страниц SQLCipher) и
        // до трёх заголовков отдельными записями — каждая заново будила все
        // подписки ленты, счётчиков и бесед.
        final attJson = email.attachments.isEmpty
            ? null
            : jsonEncode(email.attachments.map((a) => a.toMap()).toList());
        final bodyChanged = !sameBody && (email.bodyHtml != null || email.bodyPlain != null);
        final attChanged = attJson != null && attJson != cachedRow?.attachmentsJson;
        final authChanged = (email.authResults ?? '').isNotEmpty && email.authResults != cachedRow?.authResults;
        final sensChanged =
            MailLabel.decode(email.sensitivity).hasExtras && email.sensitivity != cachedRow?.sensitivity;
        final luChanged = email.listUnsubscribe != null && email.listUnsubscribe != cachedRow?.listUnsubscribe;
        // Получатели и Reply-To: EWS отдаёт их только здесь (GetItem). Без
        // записи в базу «Ответить всем» знало лишь отправителя, а ответ
        // уходил мимо Reply-To (1.5.12).
        String? addrJson(List<EmailAddress> l) => l.isEmpty ? null : jsonEncode(l.map((a) => a.toMap()).toList());
        final toJson = addrJson(email.to);
        final ccJson = addrJson(email.cc);
        final rtJson = addrJson(email.replyTo);
        final toChanged = toJson != null && toJson != cachedRow?.toRecipients;
        final ccChanged = ccJson != null && ccJson != cachedRow?.ccJson;
        final rtChanged = rtJson != null && rtJson != cachedRow?.replyToEmail;
        if (bodyChanged || attChanged || authChanged || sensChanged || luChanged || toChanged || ccChanged || rtChanged) {
          await (db.update(db.emails)
                ..where((e) => e.id.equals(widget.emailId) & e.accountId.equals(widget.accountId)))
              .write(EmailsCompanion(
                bodyHtml: bodyChanged && email.bodyHtml != null ? Value(email.bodyHtml) : const Value.absent(),
                bodyPlain: bodyChanged && email.bodyPlain != null ? Value(email.bodyPlain) : const Value.absent(),
                attachmentsJson: attChanged ? Value(attJson) : const Value.absent(),
                authResults: authChanged ? Value(email.authResults) : const Value.absent(),
                sensitivity: sensChanged ? Value(email.sensitivity) : const Value.absent(),
                listUnsubscribe: luChanged ? Value(email.listUnsubscribe) : const Value.absent(),
                toRecipients: toJson != null && toJson != cachedRow?.toRecipients ? Value(toJson) : const Value.absent(),
                ccJson: ccChanged ? Value(ccJson) : const Value.absent(),
                replyToEmail: rtChanged ? Value(rtJson) : const Value.absent(),
              ));
          cache.forgetRow(widget.accountId, widget.emailId);
        }

        // Санитизация HTML + блокировка трекеров. Локальные отметки
        // («Позже», «На контроле») сервер не знает — берём из базы.
        final sanitizedEmail = sameBody
            ? _email!
            : (await _secureBody(email)).copyWith(
                laterState: cachedRow?.laterState,
                remindAt: cachedRow?.remindAt,
                controlState: cachedRow?.controlState,
              );
        if (!mounted) return;

        // Authentication-Results, гриф в MIME и рассылка (EWS даёт заголовки
        // только при открытии письма) записаны выше одной записью; на уже
        // показанное письмо — только если что-то изменилось.
        if (sameBody && _email != null && (sensChanged || luChanged || authChanged || attChanged)) {
          final sens = email.sensitivity;
          final lu = email.listUnsubscribe;
          final ar = email.authResults;
          // Вложения: список с сервера мог стать полнее (12.11.2026: файл
          // «inline» без Content-ID прежде не попадал в список) — сразу, а
          // не при следующем открытии.
          final atts = email.attachments;
          safeSetState(() {
            _email = _email!.copyWith(
              sensitivity: sensChanged ? sens : null,
              listUnsubscribe: luChanged ? lu : null,
              authResults: authChanged ? ar : null,
              attachments: attChanged ? atts : null,
            );
            if (attChanged) {
              for (final att in atts) {
                _attachmentStates.putIfAbsent(att.id, () => const _AttachmentState());
              }
            }
          });
        }

        if (!sameBody) {
          safeSetState(() {
            _email = sanitizedEmail;
            _isLoading = false;
            _isLoadingBody = false;

            // Инициализируем состояния вложений (уже скачанные не сбрасываем)
            for (final att in sanitizedEmail.attachments) {
              _attachmentStates.putIfAbsent(att.id, () => const _AttachmentState());
            }
          });
          _startInlineImages(sanitizedEmail);
        }

        // «Прочитано» и цепочка — после перехода на экран.
        _afterOpen(account, sanitizedEmail);
      } else {
        // IMAP / ActiveSync: тело обычно уже в базе — «Письма на телефоне»
        // докачивают его заранее. Строка, прочитанная при касании строки
        // списка, берётся готовой.
        final row = await cache.row(widget.accountId, widget.emailId);
        if (row == null) {
          if (!mounted) return;
          final notFound = AppLocalizations.of(context).tr('mailNotFound');
          safeSetState(() { _isLoading = false; _error = notFound; });
          return;
        }
        var email = emailModelFromRow(row);
        final hasBody = (email.bodyHtml ?? '').isNotEmpty || (email.bodyPlain ?? '').isNotEmpty;
        // Откуда тело — в замер открытия (1.10.2: письмо открывалось ~10 с,
        // по журналу было не понять, ждали сервер или окно).
        OpenTrace.mark(hasBody ? 'тело в базе' : 'тело с сервера');

        // Шапка письма — сразу, тело — когда будет готово: раньше до конца
        // подготовки (а без текста в базе — до ответа сервера) на экране был
        // только индикатор загрузки.
        final o = cache.optionsFor(email);
        final ready = hasBody &&
            (email.bodyHtml ?? '').isNotEmpty &&
            cache.peekPrepared(email.bodyHtml!,
                    options: o.options, allowImages: o.allowImages, dates: cache.datesFor(email)) !=
                null;
        if (!ready) {
          if (!mounted) return;
          final header = email;
          safeSetState(() {
            _email = header;
            _isLoading = false;
            _isLoadingBody = true;
            for (final att in header.attachments) {
              _attachmentStates.putIfAbsent(att.id, () => const _AttachmentState());
            }
          });
        }
        if (hasBody) _startInlineImages(email);

        // Если тело не загружено — дотягиваем (EAS через движок, иначе IMAP)
        if (!hasBody) {
          final db = ref.read(databaseProvider);
          if (account.usesEas) {
            // ActiveSync: ItemOperations Fetch полного тела
            final engineSvc = ref.read(mailEngineServiceProvider);
            final full = await safeAsync(() => engineSvc.fetchFullBody(
                account, folderId: email.folderId, serverId: email.id));
            if (full != null &&
                ((full.bodyPlain?.isNotEmpty ?? false) || (full.bodyHtml?.isNotEmpty ?? false))) {
              email = email.copyWith(bodyPlain: full.bodyPlain, bodyHtml: full.bodyHtml);
              // Тихо: лента тел не показывает (см. storeBodiesQuietly).
              await db.storeBodiesQuietly(widget.accountId, {
                widget.emailId: {'body_plain': full.bodyPlain, 'body_html': full.bodyHtml},
              });
              cache.forgetRow(widget.accountId, widget.emailId);
            }
          } else {
            final uid = int.tryParse(email.id.split(':').last) ?? 0;
            if (uid > 0) {
              final imap = ref.read(imapServiceProvider);
              // Режим загрузки из настроек: по умолчанию письмо целиком, но без
              // вложений — они догружаются по нажатию (или предзагрузкой в full).
              final full = await safeAsync(() => imap.getEmailDetail(
                    account,
                    folderId: email.folderId,
                    uid: uid,
                    fetchMode: ref.read(settingsProvider).emailFetchMode,
                  ));
              if (full != null) {
                email = full;
                // Сохраняем тело и список вложений в БД для будущих открытий:
                // без списка при повторном открытии (тело уже есть, сервер не
                // спрашивается) вложения письма пропадали.
                await db.storeBodiesQuietly(widget.accountId, {
                  widget.emailId: {
                    'body_plain': full.bodyPlain,
                    'body_html': full.bodyHtml,
                    if (full.attachments.isNotEmpty)
                      'attachments_json': jsonEncode(full.attachments.map((a) => a.toMap()).toList()),
                  },
                });
                cache.forgetRow(widget.accountId, widget.emailId);
              }
            }
          }
          if (!mounted) return;
          OpenTrace.mark('тело получено');
          _startInlineImages(email);
        }

        final sanitized = await _secureBody(email);
        if (!mounted) return;
        OpenTrace.mark('тело готово');
        safeSetState(() {
          _email = sanitized;
          _isLoading = false;
          _isLoadingBody = false;
          for (final att in sanitized.attachments) {
            _attachmentStates.putIfAbsent(att.id, () => const _AttachmentState());
          }
        });
        _afterOpen(account, sanitized);
      }
    } catch (e, stack) {
      AppLogger.error('MailDetail: ошибка загрузки', e, stack);
      safeSetState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingBody = false;
      });
    }
  }

  /// Встроенные картинки письма — сразу, вместе с подготовкой текста (из
  /// памяти телефона — мгновенно; недостающие — с сервера, ActiveSync —
  /// одним запросом).
  void _startInlineImages(EmailModel e) {
    final html = e.bodyHtml;
    if (html == null || !html.toLowerCase().contains('cid:')) return;
    unawaited(ref
        .read(mailOpenCacheProvider)
        .inlineImages(widget.accountId, e, rawHtml: html)
        .then((_) {}, onError: (Object _) {}));
  }

  /// После показа текста: «прочитано» (с обновлением ленты), цепочка
  /// беседы, заголовки ActiveSync.
  void _afterOpen(AccountModel account, EmailModel e) {
    _whenShown(() {
      if (!mounted) return;
      final conv = e.conversationId;
      if (conv != null) unawaited(_loadConversation(conv));
      // ActiveSync не отдаёт заголовки рассылки и проверки отправителя —
      // при первом открытии они читаются из начала MIME (одним запросом).
      if (account.usesEas && e.listUnsubscribe == null && (e.authResults ?? '').isEmpty) {
        unawaited(_loadEasHeaders(account, e));
      }
      // Помечаем прочитанным локально и на сервере (не блокируя экран).
      if (!e.isRead) {
        ref.read(emailActionsProvider).setRead(account, e.id, e.folderId, true)
            .catchError((Object err) => AppLogger.warning('Mark read failed: $err'));
        ref.read(emailsProvider.notifier).applyLocalFlags(e.id, isRead: true);
        ref.read(mailOpenCacheProvider).forgetRow(widget.accountId, e.id);
        safeSetState(() => _email = _email?.copyWith(isRead: true));
      }
    });
  }

  /// Отправить уведомление о прочтении (read receipt)
  Future<void> _sendReadReceipt(EmailModel email) async {
    final l10n = AppLocalizations.of(context);
    try {
      // Ящик письма, а не выбранный в ленте (1.8.13): в «Всей почте», группе
      // и из уведомления другого ящика уведомление уходило от чужого адреса.
      final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
      if (account == null) return;
      await ref.read(mailEngineServiceProvider).sendReadReceipt(
        account,
        originalMessageId: email.internetMessageId ?? email.id,
        toEmail: email.from.email,
        subject: email.subject,
      );
      if (mounted) {
        showInlineNotice(l10n.readReceiptSent);
      }
    } catch (e) {
      AppLogger.warning('Read receipt send failed: $e');
    }
  }

  /// Загрузка цепочки беседы (фоново, не блокирует UI)
  Future<void> _loadConversation(String conversationId) async {
    if (!mounted) return; // экран успели закрыть до запуска загрузки
    try {
      final db = ref.read(databaseProvider);
      // Без тел писем: под письмом — только шапки и превью цепочки.
      final rows = await db.getConversationLight(
        conversationId: conversationId,
        accountId: widget.accountId,
      );

      if (!mounted) return;
      // ref после await — только пока экран открыт.
      // Конвертируем через публичный метод
      final notifier = ref.read(emailsProvider.notifier);
      final emails = rows.map((r) => notifier.rowToModel(r)).toList();
      // Черновики ответов этой беседы (1.10.5): на сервере у них своя
      // беседа — находятся по связи «письмо → черновик», как в ленте.
      final drafts = await db.watchDraftsLight(widget.accountId).first;
      if (!mounted) return;
      emails.addAll(conversationReplyDrafts(
        drafts: [for (final r in drafts) notifier.rowToModel(r)],
        conversation: emails,
        accountId: widget.accountId,
        conversationId: conversationId,
        replyDrafts: ref.read(replyDraftsProvider),
      ));
      if (emails.length <= 1) return;

      safeSetState(() => _conversationEmails = emails);
    } catch (e) {
      AppLogger.debug('Conversation load failed: $e');
    }
  }

  /// Санитизация HTML + блокировка трекеров (шпионские 1×1 пиксели, внешние
  /// изображения по настройке). `processHtml` ведёт статистику и делает _save,
  /// поэтому вызывается ОДИН раз при загрузке тела, НЕ в build — иначе счётчик
  /// заблокированного рос бы на каждой перерисовке. Раньше трекер-блокер к
  /// отрисовке письма не применялся вовсе (тумблер в настройках ничего не делал).
  ///
  /// Сама обработка — вне UI-изолята (MailBodyProcessor): крупное письмо
  /// больше не подвешивает экран при открытии.
  Future<EmailModel> _secureBody(EmailModel e, {bool allowImages = false}) async {
    if (e.bodyHtml == null || e.bodyHtml!.isEmpty) return e;
    _rawBodyHtml = e.bodyHtml;
    final cache = ref.read(mailOpenCacheProvider);
    final blocker = ref.read(trackerBlockerProvider.notifier);
    // «Показать изображения» для этого письма запоминается: при следующем
    // открытии разрешать заново не нужно (замечание 11.10.2026).
    final o = cache.optionsFor(e, allowImages: allowImages);
    final domain = o.domain;
    allowImages = o.allowImages;
    final opts = o.options;
    // Картинки разрешены (письмо, доверенный домен или блокировка внешних
    // картинок выключена) — WebView тоже должен их грузить. Раньше у
    // доверенного отправителя HTML картинки сохранял, а WebView сеть
    // блокировал: картинки не появлялись, и кнопки «Показать» не было.
    if (allowImages || !opts.blockExternal) _imagesAllowed = true;
    // Очистка (стили письма для WebView сохраняются очищенными), цитата и
    // документ WebView — одним заходом в изолят; подготовленное при касании
    // строки списка или при прошлом открытии — сразу.
    final p = await cache.prepare(e.bodyHtml!, options: opts, allowImages: allowImages, dates: cache.datesFor(e));
    _prepared = p;
    final r = p.secured;
    if (mounted) {
      blocker.countBlocked(r,
          countStats: !allowImages,
          messageKey: '${e.accountId}|${e.id}',
          sender: e.from.label,
          subject: e.subject,
          senderDomain: domain);
    }
    _externalImagesBlocked = r.externalBlocked;
    _blockedItems = r.items;
    // В журнал — что именно заблокировано (хост и причина, без адресов и
    // параметров ссылок): раньше было видно только «что-то скрыто».
    if (r.items.isNotEmpty && !allowImages) {
      AppLogger.info('Трекеры в письме от $domain: ${r.blockedCount}'
          '${r.externalBlocked > 0 ? ', внешних картинок скрыто: ${r.externalBlocked}' : ''}'
          ' — ${describeBlocked(r.items)}');
    }
    return e.copyWith(bodyHtml: r.html);
  }

  /// Что заблокировано в письме: хост, причина. Трекеры остаются
  /// заблокированными и после «Показать изображения».
  void _showBlocked(AppLocalizations l10n) {
    String reason(BlockReason r) => switch (r) {
          BlockReason.pixel => l10n.tr('blockReasonPixel'),
          BlockReason.hidden => l10n.tr('blockReasonHidden'),
          BlockReason.trackerService => l10n.tr('blockReasonService'),
          BlockReason.external => l10n.tr('blockReasonExternal'),
        };
    final items = [..._blockedItems]..sort((a, b) => a.reason.index.compareTo(b.reason.index));
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(l10n.tr('whatWasBlocked'), style: Theme.of(ctx).textTheme.titleMedium),
                subtitle: Text(_externalImagesBlocked > 0
                    ? '${l10n.tr('imagesBlocked')}. ${l10n.tr('whatWasBlockedHint')}'
                    : l10n.tr('whatWasBlockedHint')),
              ),
              for (final i in items)
                ListTile(
                  dense: true,
                  leading: Icon(i.reason == BlockReason.external
                      ? AppIcons.image_not_supported
                      : AppIcons.visibility_off),
                  title: Text(i.host),
                  subtitle: Text('${reason(i.reason)}${i.path.isNotEmpty && i.path != '/' ? ' · ${i.path}' : ''}'),
                  // Сервис отслеживания можно разблокировать прямо отсюда.
                  trailing: i.reason == BlockReason.trackerService && i.host != '—'
                      ? TextButton(
                          onPressed: () {
                            ref.read(trackerBlockerProvider.notifier).allowHost(i.host);
                            Navigator.pop(ctx);
                            _reapplyBlocking();
                          },
                          child: Text(l10n.tr('trackerAllowShort')),
                        )
                      : null,
                ),
              // Доверять отправителю — его картинки больше не скрываются.
              if (_email != null && _email!.from.email.contains('@'))
                ListTile(
                  leading: const Icon(AppIcons.verified_user),
                  title: Text(l10n.tr('trackerTrustSender')
                      .replaceAll('{domain}', _email!.from.email.split('@').last)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _allowImages(always: true);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Пересобрать тело письма с текущими правилами блокировки (после
  /// разблокировки сервиса — его картинки показываются сразу).
  void _reapplyBlocking() {
    final e = _email;
    final raw = _rawBodyHtml;
    if (e == null || raw == null) return;
    unawaited(() async {
      try {
        final secured = await _secureBody(e.copyWith(bodyHtml: raw), allowImages: _imagesAllowed);
        safeSetState(() => _email = secured);
      } catch (err) {
        AppLogger.warning('Пересборка письма: $err');
      }
    }());
  }

  /// «Показать изображения» для письма запоминается (MailOpenCache).
  void _rememberImages(EmailModel e) => ref.read(mailOpenCacheProvider).rememberImages(e);

  /// «Показать изображения» для этого письма (и, по желанию, всегда для домена).
  void _allowImages({bool always = false}) {
    final e = _email;
    final raw = _rawBodyHtml;
    if (e == null || raw == null) return;
    _rememberImages(e);
    if (always && e.from.email.contains('@')) {
      ref.read(trackerBlockerProvider.notifier).addWhitelist(e.from.email.split('@').last);
    }
    unawaited(() async {
      try {
        final secured = await _secureBody(e.copyWith(bodyHtml: raw), allowImages: true);
        safeSetState(() {
          _imagesAllowed = true;
          _email = secured;
        });
      } catch (err) {
        AppLogger.warning('Показ изображений: $err');
      }
    }());
  }

  /// Документы WebView: ответ / письмо целиком × изображения разрешены или
  /// нет. Строятся один раз на тело письма, а не на каждую перерисовку.
  /// [_baseDocs] — без встроенных картинок (собираются в изоляте),
  /// [_webDocs] — с картинками (строковая подстановка, мгновенно).
  final Map<String, MailHtmlDocument> _baseDocs = {};
  final Map<String, MailHtmlDocument> _webDocs = {};

  /// Подготовленное тело (MailOpenCache): очистка, цитата, первый документ.
  PreparedMailBody? _prepared;

  /// Документы, которые сейчас собираются в изоляте, и «поколение» тела
  /// письма: результат для прежнего тела (сменилось письмо, догрузились
  /// картинки) отбрасывается.
  final Set<String> _docBuilding = {};
  int _docGen = 0;
  bool _hasCid = false;

  /// Место тела письма, пока оно готовится: пусто, а индикатор — только
  /// если ждать дольше полсекунды (сеть). Мигание индикатора на долю
  /// секунды выглядело как «догрузка» письма.
  Widget _bodyPreparing() => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xxl),
        child: Center(child: _DelayedSpinner()),
      );

  /// Встроенные картинки письма (Content-ID → data URI) для `cid:`.
  Map<String, String> _inlineImages = const {};

  /// Те же картинки байтами — окно письма запрашивает их само (1.5.9,
  /// «Настройки → Почта → Открытие писем → Картинки письма отдельно»).
  Map<String, ({String mime, Uint8List data})> _inlineRaw = const {};

  bool get _inlineByRequest =>
      ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.inlineByRequest) ?? false;
  String? _inlineLoadedFor;

  /// Картинки письма готовы (или ждать их больше нельзя) — можно показывать
  /// тело. Раньше письмо показывалось сразу, а картинки подписи приходили
  /// следом и WebView создавался заново: текст «прыгал» на глазах.
  String? _inlineDoneFor;
  Timer? _inlineWait;

  /// Картинки ждём, только если все они уже на телефоне: тогда они приходят
  /// за несколько кадров, а это ожидание — подстраховка от медленного
  /// диска. Картинки, которые надо скачивать, текст больше не держат (было
  /// до 1,5 с пустого поля): они подставляются в то же окно, когда придут
  /// (1.5.9).
  static const _inlineMaxWait = Duration(milliseconds: 300);
  bool _inlineLocal = false;

  static const _inlineMaxEach = MailOpenCache.maxEach;

  /// Вложения, на которые ссылается тело письма как `cid:` — они показаны в
  /// тексте и в списке вложений не нужны.
  bool _isEmbedded(EmailAttachment a) {
    final html = _rawBodyHtml ?? _email?.bodyHtml;
    if (a.contentId == null) return false;
    // Текст письма ещё не готов: картинка с Content-ID, помеченная как
    // встроенная, — почти всегда подпись. Не показываем её в списке, чтобы
    // строка вложений не «мигала» (появилась и исчезла, когда текст готов).
    if (html == null || html.isEmpty) {
      return a.isInline && (a.isVmlPreview || a.mimeType.toLowerCase().startsWith('image/'));
    }
    // Нижний регистр — один раз на тело письма (раньше — на каждое вложение
    // при каждой перерисовке: сотни килобайт копий на кадр).
    if (!identical(_rawLowerOf, html)) {
      _rawLowerOf = html;
      _rawLower = html.toLowerCase();
    }
    return MailOpenCache.embeddedIn(a, _rawLower);
  }

  String? _rawLowerOf;
  String _rawLower = '';

  /// Встроенные картинки, которые показать в тексте не удалось (слишком
  /// большие — фото с телефона, ошибка загрузки, не картинка).
  final Set<String> _inlineFailed = {};

  /// Встроенная картинка скрывается из списка вложений, только если она
  /// действительно видна в тексте (или ещё грузится). Раньше скрывались все
  /// cid-вложения: фото с телефона больше 3 МБ не показывалось ни в тексте,
  /// ни в списке — его нельзя было открыть.
  ///
  /// Не показываются: запасные картинки Outlook (.wmz/.emz — дубли PNG
  /// подписи) и встроенные картинки, не загруженные из-за сети или сервера
  /// (замечание 11.10.2026: картинки подписи были и в тексте, и во вложениях).
  List<EmailAttachment> _visibleAttachments(EmailModel e) => e.attachments
      .where((a) =>
          !_isSmimeSignature(a) &&
          (!_isEmbedded(a) ||
              (!a.isVmlPreview && (_inlineFailed.contains(a.id) || a.size > _inlineMaxEach))))
      .toList();

  /// Встроенные картинки (подпись, картинки в тексте) — data URI для
  /// документа WebView. Из кэша вложений разом, недостающие — с сервера
  /// (MailOpenCache; загрузка могла начаться ещё при нажатии на строку).
  Future<void> _loadInlineImages(EmailModel email) async {
    try {
      await _loadInlineImagesImpl(email);
    } finally {
      _inlineWait?.cancel();
      if (_inlineDoneFor != email.id) safeSetState(() => _inlineDoneFor = email.id);
    }
  }

  Future<void> _loadInlineImagesImpl(EmailModel email) async {
    final r = await ref
        .read(mailOpenCacheProvider)
        .inlineImages(widget.accountId, email, rawHtml: _rawBodyHtml);
    if (!mounted) return;
    _inlineFailed.addAll(r.failed);
    if (r.map.isEmpty) {
      if (r.failed.isNotEmpty) safeSetState(() {});
      return;
    }
    safeSetState(() {
      _inlineImages = r.map;
      _inlineRaw = r.raw;
      // Картинки подставляются в уже собранный документ строкой — разбор
      // письма заново не нужен.
      _webDocs.clear();
    });
  }

  /// Вид получателей в шапке (1.5.9, «Настройки → Почта → Получатели в письме»).
  RecipientsLayout get _recipientsLayout {
    final v = ref.read(sharedPrefsProvider).getString(ExperimentalKeys.recipientsLayout);
    return RecipientsLayout.values.where((l) => l.name == v).firstOrNull ?? RecipientsLayout.overlap;
  }

  // ── Простые письма без WebView (1.5.9, этап 3) ──
  /// Модели для показа без WebView: «reply» — ответ без цитаты, «full» —
  /// письмо целиком; null — письмо сложное (WebView).
  final Map<String, NativeMail?> _natives = {};
  final Set<String> _nativeBuilding = {};

  /// Mac: встроенное окно браузера не показало это письмо — виджетами.
  String? _macWebFailedFor;
  String? _whyMarkedFor;

  /// Простое письмо — виджетами (MailNativeBody); null — показывать в WebView
  /// (письмо сложное, выключено в «Возможностях», цитата ещё не отделена).
  /// Кнопка «Как в браузере» убрана в 1.5.10 — показ виджетами точнее.
  Widget? _nativeBody(EmailModel email, String html, ThemeData theme, AppLocalizations l10n, AppSettings settings) {
    // Компьютер (1.8.14): окна браузера в письме нет — виджетами всегда.
    if (mailWebViewSupported && !(ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.nativeMail) ?? true)) {
      return null;
    }
    final split = _split;
    if (split == null) return null;
    final full = !split.hasQuote || _showQuote;
    final mode = full ? 'full' : 'reply';
    if (!_natives.containsKey(mode)) {
      final p = _prepared;
      if (p != null && identical(p.secured.html, html) && mode == (p.split.hasQuote ? 'reply' : 'full')) {
        _natives[mode] = p.native;
      } else {
        // Письмо целиком («Показать переписку») — модель строится в изоляте.
        if (_nativeBuilding.add(mode)) {
          final gen = _docGen;
          unawaited(_withQuotePeople(full ? html : split.reply, quoteShown: full && split.hasQuote)
              .then((src) => MailBodyProcessor.heavy(src, _nativeBuilder(_imagesAllowed, _datesFor(email))))
              .then(
            (n) {
              if (gen == _docGen) safeSetState(() => _natives[mode] = n);
            },
            onError: (Object _) {
              if (gen == _docGen) safeSetState(() => _natives[mode] = null);
            },
          ));
        }
        return _bodyPreparing();
      }
    }
    final whole = _natives[mode];
    if (whole == null) {
      // В замер открытия — почему письмо в браузере (1.5.10).
      final why = _prepared?.nativeWhy;
      if (why != null && _whyMarkedFor != email.id) {
        _whyMarkedFor = email.id;
        OpenTrace.mark('в браузере: $why');
      }
      return null;
    }
    // Очень длинное письмо — начало, целиком — по кнопке (1.9.x).
    final n = _showWhole ? whole : whole.shortened;
    // Встроенные картинки — подставляются, когда придут (перерисовка без
    // пересоздания окна, ждать их не нужно).
    if (_hasCid && _inlineLoadedFor != email.id) {
      _inlineLoadedFor = email.id;
      _inlineDoneFor = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadInlineImages(email));
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MailNativeBody(
          key: ValueKey('${email.id}_native_$mode'),
          mail: n,
          images: _inlineImages,
          textScale: MailHtmlView.textScaleOf(context),
          onShown: () {
            OpenTrace.mark('без WebView');
            OpenTrace.done();
            _onBodyShown();
          },
          onLink: (url, text) => _onBodyLink(email, url, text),
          onQuoteReply: (text) => _replyWithFragment(email, text),
          find: _findOpen ? _find : null,
          // «Обычный размер» после щипка — пилюлей в строке сведений.
          scaleControl: _scale,
        ),
        if (n.clipped) MailClippedBar(onShowWhole: _onShowWhole),
        if (split.hasQuote) _quoteToggle(theme, l10n, tailOnly: split.tailOnly),
      ],
    );
  }

  // ── Даты в тексте письма (1.9.x, просьба владельца 31.10.2026) ──
  // Даты нажимаются, как у iOS (DateLinks, «Настройки → Почта → Даты в
  // тексте письма»): «завтра» — от даты письма. Нажатие — карточка «Создать
  // встречу / Напоминание / Скопировать / Показать в календаре».
  DateContext? _datesFor(EmailModel email) => ref.read(mailOpenCacheProvider).datesFor(email);

  /// Фото людей в плашках цитаты для окна браузера (1.15.1): те же, что у
  /// плашек простого письма и в шапке (карта фото); у кого фото ещё нет —
  /// запрос в адресную книгу организации, как это делает портрет в ленте.
  /// Документ не перезагружается, когда фото придут позже: они будут при
  /// следующем открытии.
  MailHtmlDocument _withPeoplePhotos(MailHtmlDocument doc) {
    final emails = doc.peopleEmails;
    if (emails.isEmpty || !ref.read(moduleSettingsProvider).showContactPhotos) return doc;
    final photos = ref.read(personPhotosProvider).value;
    if (photos == null) return doc;
    final contacts = ref.read(mailContactsServiceProvider);
    for (final e in emails) {
      if (!photos.containsKey(e)) contacts.requestPhoto(e);
    }
    return doc.withPeoplePhotos(photos);
  }

  /// Разбор простого письма для изолята. Статический: замыкание внутри
  /// метода экрана захватило бы и сам экран, а его в изолят не передать.
  static NativeMail? Function(String) _nativeBuilder(bool remote, DateContext? dates) {
    final build = mailWebViewSupported
        ? (remote ? buildNativeMailRemote : buildNativeMail)
        : (remote ? buildNativeMailDesktopRemote : buildNativeMailDesktop);
    return (h) => build(h, dates: dates);
  }

  /// Люди в шапках цитат (1.10.3; с 1.10.5 включено, имена «Фамилия
  /// И.О.» или полностью — «Почта → Работа с письмами»): только когда
  /// цитата раскрыта — открытие письма не замедляется. Разбор — в изоляте,
  /// как подготовка документа; не вышло — письмо как есть. Подписи шапки
  /// («From / Sent / To / Cc / Subject») и дата — на языке приложения
  /// (1.11.x, замечание владельца 04.11.2026) — и при выключенных плашках.
  Future<String> _withQuotePeople(String html, {required bool quoteShown}) async {
    if (!quoteShown || !mounted) return html;
    final mode = quotePeopleMode(ref.read(sharedPrefsProvider));
    final l10n = AppLocalizations.of(context);
    final local = QuoteHeaderText(l10n.localeCode, {
      'from': l10n.tr('quoteFrom'),
      'sent': l10n.tr('quoteSent'),
      'to': l10n.tr('quoteTo'),
      'cc': l10n.tr('quoteCc'),
      'subject': l10n.tr('quoteSubject'),
    });
    final sw = Stopwatch()..start();
    try {
      final out = await MailBodyProcessor.heavy(html, _quoteHeaders(mode, local));
      AppLogger.debug('Шапки цитат: ${sw.elapsedMilliseconds} мс');
      return out;
    } catch (e) {
      AppLogger.warning('Шапки цитат: $e');
      return html;
    }
  }

  /// Обработка шапок для изолята. Статическая — как [_nativeBuilder]:
  /// замыкание внутри метода экрана захватило бы и сам экран.
  static String Function(String) _quoteHeaders(QuotePeopleMode mode, QuoteHeaderText local) =>
      (h) => QuotePeople.enrich(h,
          shortNames: mode == QuotePeopleMode.short, people: mode != QuotePeopleMode.off, local: local);

  void _onBodyLink(EmailModel email, String url, String? text) {
    // Плашка человека в шапке цитаты (1.10.3, экспериментально) — карточка;
    // у человека без адреса карточки нет.
    if (QuotePeople.isLink(url)) {
      final person = QuotePeople.fromLink(url);
      if (person != null) {
        unawaited(showPersonCard(context, email: person.email, name: person.name, accountId: email.accountId));
      }
      return;
    }
    if (DateLinks.isDateLink(url)) {
      final t = DateLinks.parse(url);
      if (t != null) unawaited(showDateLinkSheet(context, t, text: text, email: email));
      return;
    }
    LinkOpener.open(context, url, linkText: text, accountId: widget.accountId);
  }

  // ── Очень длинное письмо (1.9.x, просьба владельца 31.10.2026) ──
  // Огромные рассылки, цепочки с цитатами, журналы показываются началом
  // (пороги — MailClip), под ним — «Показать письмо целиком». Ответ,
  // пересылка, печать и PDF берут письмо целиком: обрезается только показ.
  late bool _showWhole = (widget.findQuery ?? '').trim().isNotEmpty;

  void _onShowWhole() => safeSetState(() => _showWhole = true);

  /// Письмо без HTML и его начало, если оно очень длинное (один раз на
  /// текст: экран перестраивается часто).
  String? _plainFor;
  String _plainText = '';
  String? _plainShort;

  /// Свежий текст письма без HTML и его начало, если он очень длинный;
  /// цитата «>» и длинная подпись «-- » свёрнуты (план 08.11.2026, п. 5).
  QuoteSplit _plainSplit = QuoteSplit('', '');
  String? _plainReplyShort;

  Widget _plainBody(EmailModel email, ThemeData theme) {
    final src = email.bodyPlain ?? email.bodyPreview ?? '';
    if (!identical(_plainFor, src)) {
      _plainFor = src;
      _plainText = SymbolFonts.fixPlain(src);
      _plainShort = MailClip.clipText(_plainText);
      _plainSplit = splitQuotedPlain(_plainText);
      _plainReplyShort = _plainSplit.hasQuote ? MailClip.clipText(_plainSplit.reply) : null;
    }
    final folded = _plainSplit.hasQuote && !_showQuote;
    final shownText = folded ? _plainSplit.reply : _plainText;
    final short = _showWhole ? null : (folded ? _plainReplyShort : _plainShort);
    // Письмо без HTML — того же размера, что и HTML-письма (1.8.12): 15 px ×
    // шрифт системы, без уменьшения масштабом интерфейса
    // (MailHtmlView.textScaleOf).
    final text = LinkifiedText(
      short ?? shownText,
      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15 * MailHtmlView.textScaleOf(context), height: 1.4),
      textScaler: TextScaler.noScaling,
      dates: _datesFor(email),
      onLink: (url, text) => _onBodyLink(email, url, text),
      find: _findOpen ? _find : null,
    );
    if (short == null && !_plainSplit.hasQuote) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        text,
        if (short != null) MailClippedBar(onShowWhole: _onShowWhole),
        if (_plainSplit.hasQuote) _quoteToggle(theme, AppLocalizations.of(context), tailOnly: _plainSplit.tailOnly),
      ],
    );
  }

  // ── «Исходные цвета» (1.9.x, просьба владельца 31.10.2026) ──
  // В тёмной теме письмо в окне браузера перекрашивается (своё тёмное
  // оформление письма или инверсия). «Исходные цвета» в «Ещё» показывают
  // его так, как задумал отправитель: светлым на белом, без перекраски.
  // Выбор — для этого письма на время работы приложения (MailOpenCache).
  bool _originalColors(EmailModel e) => ref.read(mailOpenCacheProvider).originalColors(e);

  void _toggleOriginalColors(EmailModel e) {
    ref.read(mailOpenCacheProvider).setOriginalColors(e, !_originalColors(e));
    safeSetState(() {});
  }

  /// Тело письма сейчас в окне браузера (простое письмо виджетами не
  /// перекрашивается — «Исходные цвета» ему не нужны).
  bool _inWebView(EmailModel e) {
    if (!mailWebViewSupported || (e.bodyHtml ?? '').isEmpty) return false;
    if (!(ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.nativeMail) ?? true)) return true;
    final split = _split;
    if (split == null) return false;
    final mode = !split.hasQuote || _showQuote ? 'full' : 'reply';
    return _natives.containsKey(mode) && _natives[mode] == null;
  }

  /// Тело письма на компьютере (Windows, macOS, Linux; 1.8.14). Окна браузера
  /// в письме нет, а прежний показ (flutter_html с расширением таблиц) на
  /// вёрстке таблицами рассылок падал при раскладке: вместо письма — пустые
  /// и серые места (замечание 29.10.2026 «сложные письма отображаются
  /// некорректно»). Теперь — виджетами, как простые письма на телефоне;
  /// сложная вёрстка — упрощённо, оформление целиком — «Открыть в браузере».
  Widget _buildDesktopBody(EmailModel email, ThemeData theme, AppLocalizations l10n, AppSettings settings) {
    final html = email.bodyHtml!;
    if (!identical(_splitSource, html)) {
      _splitSource = html;
      _hasCid = html.toLowerCase().contains('cid:');
      _natives.clear();
      _nativeBuilding.clear();
      _docGen++;
      final p = _prepared;
      _split = p != null && identical(p.secured.html, html) ? p.split : splitQuotedHtml(html);
    }
    // Mac: сложная вёрстка — во встроенном окне браузера (12.11.2026,
    // включается в «Открытии писем»); окно не показало письмо — как раньше.
    final macWeb = mailMacWebViewSupported &&
        _prepared?.nativeWhy != null &&
        _macWebFailedFor != email.id &&
        (ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.macWebMail) ?? false);
    final Widget body;
    if (macWeb) {
      final dark = theme.brightness == Brightness.dark;
      final original = dark && _originalColors(email);
      body = MacMailWebView(
        key: ValueKey('macweb_${email.id}'),
        html: html,
        allowRemoteImages: _imagesAllowed,
        inlineImages: _inlineImages,
        height: macMailWebHeight(MediaQuery.sizeOf(context).height),
        dark: dark && !original,
        pageColor: original ? Colors.white : mailPageColor(theme),
        textScale: MailHtmlView.textScaleOf(context),
        onLink: (url, text) => _onBodyLink(email, url, text),
        onFailed: () => safeSetState(() => _macWebFailedFor = email.id),
      );
    } else {
      body = _nativeBody(email, html, theme, l10n, settings) ?? _flutterHtmlBody(html, theme, l10n);
    }
    if (_prepared?.nativeWhy == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => unawaited(_openInBrowser(email)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(AppIcons.open_in_new, size: 18),
            label: Text(l10n.tr('mailOpenInBrowser')),
          ),
        ),
        body,
      ],
    );
  }

  /// Письмо целиком в браузере компьютера (1.8.14): тот же очищенный
  /// документ, что у окна письма на телефоне — без скриптов (CSP), картинки
  /// из интернета — только если они разрешены в письме.
  Future<void> _openInBrowser(EmailModel email) async {
    final html = email.bodyHtml;
    if (html == null || html.isEmpty) return;
    try {
      final doc = await MailHtmlDocument.buildAsync(html,
          allowRemoteImages: _imagesAllowed, inlineImages: _inlineImages);
      final subject = email.subject.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      // Поля у краёв окна браузера и тема письма — в заголовке вкладки.
      final page = MailHtmlView.composeHtml(doc,
              viewWidth: 0, fitWidth: null, dark: false, pageColor: Colors.white, textScale: 1)
          .replaceFirst('</head>', '<title>$subject</title><style>body{padding:16px !important;}</style></head>');
      final dir = await getTemporaryDirectory();
      // Один файл на все письма: прежнее письмо не копится во временной папке.
      final f = File('${dir.path}${Platform.pathSeparator}ogneliss-mail-view.html');
      await f.writeAsString(page, flush: true);
      final ok = await launchUrl(Uri.file(f.path), mode: LaunchMode.externalApplication);
      if (!ok && mounted) quietError(AppLocalizations.of(context).tr('mailOpenInBrowserFailed'));
    } catch (e) {
      AppLogger.warning('Письмо в браузере: $e');
      if (mounted) quietError(AppLocalizations.of(context).tr('mailOpenInBrowserFailed'));
    }
  }

  /// Запасной показ на компьютере, если разбор виджетами не удался.
  Widget _flutterHtmlBody(String html, ThemeData theme, AppLocalizations l10n) {
    // Блоки <style> письма flutter_html применил бы по-своему (без @media) —
    // без них, как раньше.
    final plain = html.replaceAll(_styleBlock, '');
    Map<String, Style> htmlStyle() => {
          'body': Style(fontSize: FontSize(15), lineHeight: const LineHeight(1.5)),
          'a': Style(color: AppColors.linkBlue),
        };
    return SelectionArea(
        child: Html(data: plain, style: htmlStyle(), onLinkTap: (url, _, el) => _onLinkTap(url, el)));
  }

  static final _styleBlock = RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false);

  /// Тело письма в WebView (Android, iOS): вложенные таблицы Outlook, стили,
  /// широкая вёрстка. Цитата свёрнута; «Показать переписку» загружает письмо
  /// целиком в тот же WebView — так вёрстка цитаты не режется.
  Widget _buildWebBody(EmailModel email, ThemeData theme, AppLocalizations l10n, AppSettings settings) {
    final html = email.bodyHtml!;
    // Отделение цитаты и сборка документа — разбор DOM всего письма. Обычно
    // всё уже готово (MailOpenCache: при касании строки или прошлом
    // открытии); иначе — вне UI-изолята, а на месте тела пока пусто.
    if (!identical(_splitSource, html)) {
      _splitSource = html;
      _hasCid = html.toLowerCase().contains('cid:');
      _split = null;
      _baseDocs.clear();
      _webDocs.clear();
      _docBuilding.clear();
      _natives.clear();
      _nativeBuilding.clear();
      _docGen++;
      final p = _prepared;
      if (p != null && identical(p.secured.html, html)) {
        _split = p.split;
        _baseDocs['${p.split.hasQuote ? 'reply' : 'full'}_${p.remoteImages ? 'img' : 'noimg'}'] = p.firstDoc;
      } else {
        // Результат сверяется с телом, а не со счётчиком: догрузка встроенных
        // картинок меняет счётчик, но цитата от неё не зависит.
        unawaited(MailBodyProcessor.heavy(html, splitQuotedHtml)
            .catchError((Object e) {
          AppLogger.debug('Отделение цитаты: $e');
          return QuoteSplit(html, '');
        }).then((s) {
          if (!identical(_splitSource, html)) return;
          OpenTrace.mark('цитата');
          safeSetState(() => _split = s);
        }));
      }
    }
    // Простое письмо — без WebView (1.5.9): виджетами, в том же кадре, что и
    // шапка.
    final native = _nativeBody(email, html, theme, l10n, settings);
    if (native != null) return native;
    // Встроенные картинки — один раз на письмо. Тело показывается, когда
    // они готовы (из памяти телефона — мгновенно), но не дольше 1,5 с: без
    // этого WebView создавался дважды и письмо дёргалось после открытия.
    if (_hasCid) {
      if (_inlineLoadedFor != email.id) {
        _inlineLoadedFor = email.id;
        _inlineDoneFor = null;
        // Картинки по запросу окна — ждать их незачем: окно запросит их,
        // когда они придут (перезагрузка документа в том же окне).
        _inlineLocal = !_inlineByRequest &&
            ref.read(mailOpenCacheProvider).inlineImagesLocal(widget.accountId, email, _rawBodyHtml ?? html);
        final id = email.id;
        _inlineWait?.cancel();
        if (_inlineLocal) {
          _inlineWait = Timer(_inlineMaxWait, () {
            if (_inlineDoneFor != id) safeSetState(() => _inlineDoneFor = id);
          });
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadInlineImages(email));
        });
      }
      if (_inlineLocal && _inlineDoneFor != email.id) return _bodyPreparing();
    }
    final split = _split;
    if (split == null) return _bodyPreparing();
    final full = !split.hasQuote || _showQuote;
    final baseKey = '${full ? 'full' : 'reply'}_${_imagesAllowed ? 'img' : 'noimg'}';
    // Письмо целиком (1.9.x) — свой документ, без обрезки; документ, который
    // и так не обрезан, годится и для него.
    final cut = _baseDocs[baseKey];
    final docKey = _showWhole && (cut == null || cut.clipped) ? '${baseKey}_whole' : baseKey;
    final byRequest = _hasCid && _inlineByRequest;
    // Картинки — строкой в готовый документ (без разбора HTML).
    MailHtmlDocument withImages(String k, MailHtmlDocument base) =>
        _webDocs['${k}_${byRequest ? 'req' : _inlineImages.length}'] ??=
            _withPeoplePhotos(_hasCid && !byRequest ? base.withInlineImages(_inlineImages) : base);
    var doc = _webDocs['${docKey}_${byRequest ? 'req' : _inlineImages.length}'];
    if (doc == null) {
      final base = _baseDocs[docKey];
      if (base != null) {
        doc = withImages(docKey, base);
      } else {
        // Ключ сборки — с «поколением»: сборка для прежнего тела не
        // блокирует новую с тем же ключом.
        final gen = _docGen;
        final buildKey = '$gen|$docKey';
        if (_docBuilding.add(buildKey)) {
          unawaited(_withQuotePeople(full ? html : split.reply, quoteShown: full && split.hasQuote)
              .then((src) => MailHtmlDocument.buildAsync(
            src,
            allowRemoteImages: _imagesAllowed,
            keepCid: true,
            clip: docKey == baseKey,
            dates: _datesFor(email),
          )).catchError((Object e) {
            AppLogger.warning('Подготовка письма к показу: $e');
            return const MailHtmlDocument('<!DOCTYPE html><html><body></body></html>', {});
          }).then((d) {
            _docBuilding.remove(buildKey);
            if (gen != _docGen) return;
            OpenTrace.mark('документ');
            safeSetState(() => _baseDocs[docKey] = d);
          }));
        }
        // Письмо целиком ещё собирается — пока показано начало: целиком оно
        // загрузится в то же окно (MailHtmlView.didUpdateWidget), высота
        // только вырастет.
        if (docKey == baseKey || cut == null) return _bodyPreparing();
        doc = withImages(baseKey, cut);
      }
    }
    final dark = theme.brightness == Brightness.dark;
    final original = dark && _originalColors(email);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Во всю ширину и без скругления: письмо — часть страницы, а не
        // карточка на ней.
        MailHtmlView(
          // Без числа встроенных картинок: пришедшие картинки загружаются в
          // то же окно (MailHtmlView.didUpdateWidget), а не пересоздают
          // WebView (1.5.9). Письмо целиком (1.9.x) — тоже в то же окно.
          key: ValueKey('${email.id}_${baseKey}_${original ? 'original' : theme.brightness.name}'),
          document: doc,
          active: widget.active,
          allowRemoteImages: _imagesAllowed,
          textScale: MailHtmlView.textScaleOf(context),
          // «Исходные цвета» (1.9.x) — светлое письмо на белом, как в
          // светлой теме.
          pageColor: original ? Colors.white : mailPageColor(theme),
          dark: dark && !original,
          onShown: _onBodyShown,
          inlineRaw: byRequest ? _inlineRaw : null,
          scaleControl: _scale,
          onLink: (url, text) => _onBodyLink(email, url, text),
          find: _findOpen ? _find : null,
        ),
        if (doc.clipped) MailClippedBar(onShowWhole: _onShowWhole, busy: _showWhole),
        if (split.hasQuote) _quoteToggle(theme, l10n, tailOnly: split.tailOnly),
      ],
    );
  }

  /// Кнопка «Показать / скрыть переписку»; [tailOnly] — свёрнута только
  /// подпись или юридическое уведомление (2.0.0).
  Widget _quoteToggle(ThemeData theme, AppLocalizations l10n, {bool tailOnly = false}) => Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => safeSetState(() => _showQuote = !_showQuote),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_showQuote ? AppIcons.unfold_less : AppIcons.more_horiz,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Space.xs),
                Text(
                  tailOnly
                      ? l10n.tr(_showQuote ? 'hideSignatureTail' : 'showSignatureTail')
                      : (_showQuote ? l10n.tr('hideQuoted') : l10n.tr('showQuoted')),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );

  void _onLinkTap(String? url, dom.Element? element) {
    LinkOpener.open(context, url, linkText: element?.text, accountId: widget.accountId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);

    if (_isLoading) {
      return Scaffold(
        appBar: TextScaleCapBar(child: AppBar()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _email == null) {
      return Scaffold(
        appBar: TextScaleCapBar(child: AppBar()),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.error, size: 48, color: AppColors.errorRed),
              const SizedBox(height: Space.l),
              Text(_error ?? l10n.tr('noData')),
              const SizedBox(height: Space.l),
              FilledButton(onPressed: _loadEmailDetail, child: Text(l10n.tr('retry'))),
            ],
          ),
        ),
      );
    }

    final email = _email!;

    // Горячие клавиши письма (Windows/macOS/Linux, клавиатура на планшете):
    // Ctrl+R — ответить, Ctrl+Shift+R — всем, Ctrl+F — переслать (как в
    // Outlook), Delete — удалить, Esc — закрыть. Раньше эти сочетания были
    // объявлены, но обработчиков не было.
    // Шапка письма закреплена, пока шрифт не очень крупный.
    final pinHeader = context.textScale <= 1.3;
    // Планшет и компьютер (1.10.5, как в Outlook): панель команд с
    // подписями — сверху, отправитель и дата — под темой, телефонной
    // нижней панели нет.
    final wide = _wideLayout(context);
    return TypingAwareShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            _compose({'replyToId': email.id, 'accountId': email.accountId}),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true): () =>
            _compose({'replyToId': email.id, 'accountId': email.accountId, 'replyAll': 'true'}),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _forward(email),
        if (!widget.embedded)
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        // Ещё сочетания Outlook (1.10.x, просьба владельца 02.11.2026):
        // Ctrl+Q — прочитано, Ctrl+U — не прочитано, Ctrl+P — печать.
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () => _setReadKey(email, true),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _setReadKey(email, false),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () => unawaited(_exportPdf(email, l10n)),
        // Поиск в письме (2.2.0) — F4, как в Outlook (Ctrl+F — переслать).
        const SingleActivator(LogicalKeyboardKey.f4): _openFind,
      },
      // Клавиши без Ctrl — не пока набирают ответ (1.10.1): Delete —
      // удалить, Backspace — в архив, Insert — флажок.
      plain: {
        const SingleActivator(LogicalKeyboardKey.delete): () => _deleteEmail(email, l10n),
        const SingleActivator(LogicalKeyboardKey.backspace): () => unawaited(_archiveEmail(email, l10n)),
        const SingleActivator(LogicalKeyboardKey.insert): () => _toggleFlag(email),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      // Под шторкой или окном с полем ввода письмо (WebView) не подстраивается
      // под клавиатуру — не перестраивается в каждом кадре её появления (1.6.19).
      resizeToAvoidBottomInset: widget.embedded || (ModalRoute.of(context)?.isCurrent ?? true),
      appBar: TextScaleCapBar(child: AppBar(
        leading: widget.embedded
            ? null
            : IconButton(
              tooltip: l10n.tr('back'),
                icon: const Icon(AppIcons.arrow_back),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/mail');
                  }
                },
              ),
        // Отправитель — в верхней панели (1.5.9): она была пустой, а
        // отправитель занимал отдельную строку шапки под темой. Портрет —
        // того же размера, что у адресатов; ниже имени — дата (и номер
        // письма в беседе). На широком экране — панель команд (1.10.5).
        titleSpacing: widget.embedded || wide ? (wide ? Space.s : null) : 0,
        title: wide
            ? _commandBar(email, settings, l10n)
            : MailSenderTitle(email: email, hero: !widget.embedded, pagerLabel: widget.pagerLabel),
        backgroundColor: mailPageColor(theme),
        actions: [
          // Флаг «К исполнению» — на виду: в меню «…» его не находили.
          // На широком экране он в панели команд.
          if (!wide) IconButton(
            tooltip: l10n.tr('flag'),
            icon: Icon(
              AppIcons.flag,
              fill: email.isFlagged ? 1 : 0,
              color: email.isFlagged ? AppColors.errorRed : null,
            ),
            onPressed: () => _toggleFlag(email),
          ),
          if (widget.pagerLabel != null) ...[
            IconButton(
              tooltip: l10n.tr('convNewer'),
              icon: const Icon(AppIcons.keyboard_arrow_up),
              onPressed: widget.onPrev,
            ),
            IconButton(
              tooltip: l10n.tr('convOlder'),
              icon: const Icon(AppIcons.keyboard_arrow_down),
              onPressed: widget.onNext,
            ),
          ],
        ],
        // Поиск в письме (2.2.0) — строкой под заголовком.
        bottom: _findOpen ? MailFindBar(controller: _find, onClose: _closeFind, initial: widget.findQuery) : null,
      )),
      backgroundColor: mailPageColor(theme),
      // Ответ — кнопками нижней панели. Плавающая кнопка быстрого ответа
      // (подсказки ИИ, диктовка) убрана вместе с модулями ИИ и голоса.
      // Шапка (тема, отправитель, адресаты, вложения) закреплена, письмо
      // прокручивается под ней (замечание 07.10.2026). При очень крупном
      // шрифте закреплённая шапка заняла бы экран — тогда всё прокручивается.
      // Переход экрана уже плавный — второе затухание содержимого не нужно.
      // Слева и справа — вырез камеры и панели в альбомной ориентации
      // (1.5.10): приложение рисует под системными панелями (edge-to-edge),
      // а прокрутка письма их не учитывала — начало строк уходило под вырез.
      body: SafeArea(top: false, bottom: false, child: AnimatedAppearance(offsetY: 0, play: false, child: Builder(builder: (context) {
        final headerChildren = <Widget>[
            // ── Тема ──
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
              child: Semantics(
                header: true,
                // Тема летит из строки ленты (1.9.x, «Анимация открытия письма»).
                child: Builder(builder: (context) {
                  // С переводом (1.10.5) — тема переведена; «оставить оба» —
                  // вторая тема мелко под первой.
                  final subj = _translation.subjectFor(email);
                  final main = MailSubjectHero(
                    tag: MailHeroTags.subject(email.accountId, email.id),
                    enabled: !widget.embedded && AppearanceLook.of(context).openAnimation,
                    child: Text(
                      subj.main.isEmpty ? l10n.tr('noSubject') : subj.main,
                      // В закреплённой шапке длинная тема не занимает пол-экрана.
                      maxLines: pinHeader ? 3 : null,
                      overflow: pinHeader ? TextOverflow.ellipsis : null,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  );
                  final second = subj.second;
                  if (second == null || second.isEmpty) return main;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    main,
                    const SizedBox(height: Space.xs),
                    Text(
                      second,
                      maxLines: pinHeader ? 2 : null,
                      overflow: pinHeader ? TextOverflow.ellipsis : null,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ]);
                }),
              ),
            ),

            // Отправитель и дата — под темой (широкий экран, как в Outlook).
            if (wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
                child: MailSenderTitle(email: email, hero: false, pagerLabel: widget.pagerLabel),
              ),

            // ── Адресаты ── (1.5.9): «Кому» и «Копия» — значками, каждый
            // список своей строкой; портреты и имена крупнее, чем были
            // (24 px и мелкий шрифт под отправителем).
            // Вид — на выбор в «Настройки → Почта → Получатели в письме» (1.5.9).
            MailRecipientsPanel(
              email: email,
              layout: _recipientsLayout,
              onShowAll: () => _showRecipients(context, email, l10n),
              isMine: (addr) {
                final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
                return acc != null && OwnAddresses.isMine(acc, addr);
              },
            ),

            const Divider(height: 24),
            if (pinHeader && _visibleAttachments(email).isNotEmpty)
              _attachmentStrip(email, theme, l10n),
        ];
        // Плашки, которые считают (проверка отправителя, приглашение,
        // бронирование), читают базу или сеть (папка письма, подпись
        // S/MIME), — после перехода на экран: тело письма появляется тогда
        // же, поэтому они не сдвигают уже видимый текст.
        final settled = _settled && !_isLoadingBody;
        // Язык письма — когда тело готово; показ — с переводом, если он включён.
        if (settled) _translation.detect(email);
        if (settled) _checkSafety(email);
        final shown = _translation.apply(email);
        final bodyChildren = <Widget>[
            // ── Строка сведений (1.12.x, просьба владельца 04.11.2026) ──
            // Перевод, «Отписаться», скрытые изображения, уведомление о
            // прочтении, «На контроле», «Позже», доставка, S/MIME, важность,
            // «Спам»/«Корзина», теги и категории — одной строкой чипов под
            // шапкой, а не стопкой плашек во всю ширину («съедают место»).
            // Нажатие на чип раскрывает прежнюю плашку с её кнопками. Свой
            // Consumer: отчёты о доставке перестраивают только строку.
            // Масштаб широкого письма и предупреждение об отправителе — тоже
            // чипами этой строки (1.15.1, замечание владельца 07.11.2026:
            // строками над письмом они увеличивали его длину).
            Consumer(
              key: ValueKey('notices|${email.accountId}|${email.id}'),
              builder: (_, r, __) => ListenableBuilder(
                listenable: _scale,
                builder: (_, __) => MailNoticeBar(
                  notices: _notices(r, email, settled: settled, mailControl: settings.mailControl),
                  // Планшет и компьютер — перенос строк, телефон — прокрутка вбок.
                  wrap: wide || widget.embedded,
                  note: settled ? MailTranslateNotice.note(context, _translation) : null,
                ),
              ),
            ),

            // ── Приглашение на встречу ── (карточка с кнопками ответа)
            if (settled)
              Builder(builder: (_) {
                final matches = ref.read(accountsProvider).where((a) => a.id == email.accountId);
                if (matches.isEmpty) return const SizedBox.shrink();
                return MeetingInviteBanner(account: matches.first, email: email);
              }),

            // ── Бронирование (билет, отель…): разметка schema.org в письме ──
            if (settled && (_rawBodyHtml ?? '').contains('ld+json'))
              Builder(builder: (_) {
                final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
                return acc == null
                    ? const SizedBox.shrink()
                    : BookingCards(account: acc, email: email, rawHtml: _rawBodyHtml);
              }),

            // Плашки выше — каждая с отступом Space.s сверху и без нижнего;
            // здесь один общий отступ до вложений и текста: плашка «На
            // контроле» стояла вплотную к письму (замечание 10.10.2026).
            const SizedBox(height: Space.s),

            if (!pinHeader && _visibleAttachments(email).isNotEmpty)
              _attachmentStrip(email, theme, l10n),

            // ── Тело письма ──
            if (_isLoadingBody)
              _bodyPreparing()
            else
              Padding(
                // Поля 16 dp у любого тела письма — левый край текста на одной
                // линии с шапкой, плашками и «Показать переписку» (раньше
                // WebView шёл во всю ширину с отступом внутри документа).
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: shown.bodyHtml != null && shown.bodyHtml!.isNotEmpty && mailWebViewSupported
                    ? _buildWebBody(shown, theme, l10n, settings)
                    : shown.bodyHtml != null && shown.bodyHtml!.isNotEmpty
                    ? _buildDesktopBody(shown, theme, l10n, settings)
                    // Письмо без HTML (очень длинное — началом, 1.9.x).
                    : _plainBody(shown, theme),
              ),

            // ── Цепочка беседы ──
            if (widget.pagerLabel == null &&
                _conversationEmails != null &&
                _conversationEmails!.length > 1) ...[
              const Divider(height: 24),
              ConversationThreadView(
                emails: _conversationEmails!,
                currentEmailId: email.id,
                onEmailTap: (e) {
                  // Черновик — в редактор, как из «Черновиков».
                  if (e.isDraft) {
                    context.push('/compose?draftId=${Uri.encodeQueryComponent(e.id)}'
                        '&accountId=${Uri.encodeQueryComponent(e.accountId)}');
                    return;
                  }
                  context.push(mailOpenPath(context, e.id, accountId: e.accountId));
                },
              ),
            ],

            const SizedBox(height: 100), // Отступ для bottom bar
        ];
        if (!pinHeader) {
          return SingleChildScrollView(
            child: ReadableWidth(
              fill: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [...headerChildren, ...bodyChildren],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReadableWidth(
              fill: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: headerChildren),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ReadableWidth(
                  fill: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: bodyChildren),
                ),
              ),
            ),
          ],
        );
      }))),

      // ── Нижняя панель ──
      // Над клавиатурой, пока пишется быстрый ответ (1.6.49): нижняя панель
      // Scaffold сама не поднимается.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: wide
            ? _wideReplyBar(theme, email)
            : _buildBottomBar(context, theme, l10n, email, settings),
      ),
    ),
      ),
    );
  }

  // ════════════════════════ СТРОКА СВЕДЕНИЙ ════════════════════════

  /// Чипы строки сведений (1.12.x, просьба владельца 04.11.2026: плашки
  /// «съедают место»). Порядок: что можно сделать (перевод, отписка,
  /// изображения, уведомление о прочтении), состояние (контроль, «Позже»,
  /// доставка, S/MIME, важность, «Спам»), теги и категории. Условия показа —
  /// те же, что у прежних плашек; раскрытый чип — та же плашка с кнопками.
  /// [r] — ref строки (Consumer): отчёты о доставке перестраивают только её.
  /// Плашка поручения: у исполнителя — «Поручение · до …» с кнопками
  /// «Принять в работу», «Готово», «Вопрос»; у поручившего — статус.
  MailNotice? _assignmentNotice(WidgetRef r, EmailModel email, AppLocalizations l10n) {
    final id = AssignmentCodec.idFromBody(email.bodyHtml) ?? AssignmentCodec.idFromBody(email.bodyPlain);
    if (id == null) return null;
    final v = (r.watch(assignmentsProvider).value ?? const <AssignmentView>[]).where((x) => x.id == id).firstOrNull;
    if (v == null) return null;
    final label = [
      l10n.tr('assignTitle'),
      assignmentStatusLabel(v.status, l10n),
      if (v.due != null && v.active) l10n.tr('assignDueShort').replaceAll('{due}', assignmentDueText(v.due!, l10n)),
    ].join(' · ');
    return MailNotice(
      id: 'assignment',
      icon: AppIcons.assignment_ind,
      color: assignmentStatusColor(v.status, context),
      label: label,
      detail: '${l10n.tr(v.outgoing ? 'assignTo' : 'assignFrom')} ${v.otherName}',
      expanded: (_) => AssignmentMailCard(v: v),
    );
  }

  List<MailNotice> _notices(WidgetRef r, EmailModel email, {required bool settled, required bool mailControl}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;

    // Рассылка: «Отписаться» (по заголовку List-Unsubscribe) — после
    // проверки отправителя: при подозрении на подделку чипа нет.
    final unsub = settled && acc != null ? ListUnsubscribe.parse(email.listUnsubscribe) : null;
    final unsubOk = unsub != null && acc != null && _unsubscribeAllowed(acc, email);

    // Внешние изображения скрыты: «Показать изображения» — сразу; «Всегда от
    // этого домена» и «Что заблокировано» — в меню чипа.
    final trackers = _blockedItems.where((i) => i.reason != BlockReason.external).length;
    // Картинки разрешены, но часть адресов отнесена к службам отслеживания —
    // чип «Трекеры» остаётся: оттуда сервис можно разблокировать (12.11.2026:
    // без него было не понять, куда делись картинки и как их вернуть).
    final services = _blockedItems.any((i) => i.reason == BlockReason.trackerService);
    final imagesHidden = !_isLoadingBody &&
        ((!_imagesAllowed && (_externalImagesBlocked > 0 || _blockedItems.isNotEmpty)) || services);

    final p7m = settled ? _smimeP7m(email) : null;
    final sig = settled && p7m == null && _smimeP7s(email) != null ? _sigView(email, l10n) : null;
    final folder = settled ? _folderTypeNow(email) : null;
    final junk = folder == FolderType.junk;
    final showCats = acc != null && acc.isMsExchange && email.categories.isNotEmpty;
    final laterAt = email.remindAt?.toLocal();
    final control = email.controlState != 0 && mailControl ? _controlParts(email, l10n) : null;

    // Предупреждение об отправителе (антифишинг): первым — его видно сразу;
    // карточка с причинами и «Пожаловаться» — по нажатию.
    final safety = settled ? _safety : null;
    final safetyLevel = SenderSafetyBanner.pillLevel(safety, r.watch(featureFlagsProvider));
    final scale = _scale.action;

    return [
      if (safety != null && safetyLevel != null && acc != null)
        MailNotice(
          id: 'safety',
          icon: SenderSafetyBanner.iconOf(safetyLevel),
          color: SenderSafetyBanner.colorOf(safetyLevel),
          iconFilled: safetyLevel == SafetyLevel.danger,
          label: SenderSafetyBanner.pillLabel(safetyLevel, l10n),
          detail: SenderSafetyBanner.summary(safety, l10n),
          expanded: (_) => SenderSafetyBanner(account: acc, email: email, report: safety),
        ),

      // ── Поручение (2.2.0): письмо с тегом OGN-… в теле ──
      ?_assignmentNotice(r, email, l10n),

      // ── Перевод: «Перевести · английский» ↔ «Оригинал» ──
      if (settled) ?MailTranslateNotice.of(context, _translation, email),

      // ── Масштаб широкого письма (было кнопкой строкой над письмом) ──
      if (scale != MailScaleAction.none)
        MailNotice(
          id: 'scale',
          icon: scale == MailScaleAction.actualSize ? AppIcons.zoom_in : AppIcons.fit_screen,
          label: l10n.tr(switch (scale) {
            MailScaleAction.actualSize => 'mailActualSize',
            MailScaleAction.fitToWidth => 'mailFitToWidth',
            _ => 'mailZoomReset',
          }),
          onTap: _scale.run,
        ),

      if (unsubOk)
        MailNotice(
          id: 'unsubscribe',
          icon: AppIcons.unsubscribe,
          label: l10n.tr(isUnsubscribed(ref, email.from.email) ? 'noticeUnsubscribed' : 'unsubscribe'),
          detail: l10n.tr('mailingList').replaceAll('{name}', unsub.listName ?? email.from.label),
          expanded: (_) => UnsubscribeBanner(account: acc, email: email, onDone: () => safeSetState(() {})),
        ),

      if (imagesHidden && !_imagesAllowed && _externalImagesBlocked > 0)
        MailNotice(
          id: 'images',
          icon: AppIcons.image_not_supported,
          label: l10n.tr('noticeShowImages'),
          detail: l10n.tr('imagesBlocked'),
          onTap: _allowImages,
          menu: [
            AppMenuEntry(value: 'always', icon: AppIcons.image, label: l10n.tr('alwaysFromSender')),
            AppMenuEntry(value: 'what', icon: AppIcons.info, label: l10n.tr('whatWasBlocked')),
          ],
          onMenu: (v) {
            if (v == 'always') _allowImages(always: true);
            if (v == 'what') _showBlocked(l10n);
          },
        )
      else if (imagesHidden)
        // Только трекеры (картинок показать нечего) — нажатие: что заблокировано.
        MailNotice(
          id: 'images',
          icon: AppIcons.visibility_off,
          label: l10n.tr('trackersBlockedN').replaceAll('{n}', '$trackers'),
          detail: '${l10n.tr('trackersBlockedN').replaceAll('{n}', '$trackers')}. ${l10n.tr('whatWasBlocked')}',
          onTap: () => _showBlocked(l10n),
        ),

      if (email.readReceiptRequested && !_readReceiptHandled)
        MailNotice(
          id: 'readReceipt',
          icon: AppIcons.mark_email_read,
          label: l10n.tr('noticeReadReceipt'),
          detail: l10n.tr('readReceiptRequested').replaceAll('{name}', email.from.label),
          expanded: (_) => ReadReceiptBanner(
            senderName: email.from.label,
            onSend: () {
              _sendReadReceipt(email);
              setState(() => _readReceiptHandled = true);
            },
            onDismiss: () => setState(() => _readReceiptHandled = true),
          ),
        ),

      // ── «На контроле»: «Нужно ответить · срок завтра» ──
      if (control != null)
        MailNotice(
          id: 'control',
          icon: AppIcons.task_alt,
          iconColor: email.controlState == ControlState.done
              ? AppColors.successText(context)
              : theme.colorScheme.primary,
          iconFilled: email.controlState == ControlState.done,
          label: [
            control.first,
            if (email.controlState != ControlState.done && email.followUpAt != null) control.last,
          ].join(' · '),
          detail: control.join(' · '),
          expanded: (_) => _controlBanner(email, theme, l10n),
        ),

      // ── «Позже: завтра, 09:00» (письмо открыто из списка «Позже») ──
      if (email.laterState == LaterState.waiting)
        MailNotice(
          id: 'later',
          icon: AppIcons.watch_later,
          iconColor: _laterColor,
          iconFilled: true,
          label: laterAt == null
              ? l10n.tr('later')
              : l10n.tr('noticeLaterUntil').replaceAll('{when}', laterWhenLabel(laterAt, l10n)),
          detail: _laterText(email, l10n),
          expanded: (_) => _laterBanner(email, theme, l10n),
        ),

      // ── Доставка своего письма; на письме-отчёте — «Отчёт о доставке» ──
      ?DeliveryStatusBanner.noticeOf(context, r, email),

      // ── S/MIME: зашифрованное письмо (тело в smime.p7m) или подпись ──
      if (p7m != null)
        MailNotice(
          id: 'smime',
          icon: AppIcons.lock,
          iconColor: theme.colorScheme.primary,
          label: l10n.tr('noticeEncrypted'),
          detail: l10n.tr('smimeEncryptedMail'),
          busy: _attachmentStates[p7m.id]?.isDownloading ?? false,
          expanded: (_) => _smimeEncryptedBanner(email, theme, l10n),
        )
      else if (sig != null)
        MailNotice(
          id: 'smime',
          icon: sig.icon,
          iconColor: sig.tone == MailNoticeTone.warning ? null : sig.color,
          label: sig.chip,
          detail: '${sig.title}. ${sig.sub}',
          tone: sig.tone,
          busy: sig.busy,
          expanded: (_) => _smimeSignatureBanner(email, theme, l10n),
        ),

      // ── Высокая важность: нажатие — выбор важности (как в меню письма) ──
      if (email.isHighPriority)
        MailNotice(
          id: 'importance',
          icon: AppIcons.priority_high,
          iconColor: AppColors.errorText(context),
          label: l10n.tr('highImportanceLabel'),
          detail: '${l10n.tr('highImportanceLabel')} · ${l10n.tr('importance')}',
          onTap: () => unawaited(_pickImportance(email, l10n)),
        ),

      // ── Спам / Корзина: «Не спам», «Восстановить» — в раскрытой плашке ──
      if (folder == FolderType.junk || folder == FolderType.trash)
        MailNotice(
          id: 'folder',
          icon: junk ? AppIcons.report : AppIcons.delete,
          label: l10n.tr(junk ? 'spam' : 'trash'),
          detail: l10n.tr(junk ? 'inJunkFolder' : 'inTrashFolder'),
          expanded: (_) => _restoreBanner(email, junk, theme, l10n),
        ),

      // ── Теги и категории Outlook ── (раньше — своей строкой чипов, 05.10):
      // нажатие открывает тот же выбор, добавить — «Ещё» в нижней панели.
      for (final tag in email.tags)
        MailNotice(
          id: 'tag:$tag',
          label: tag,
          color: AppTheme.getTagColor(tag),
          detail: '$tag · ${l10n.tr('editTags')}',
          onTap: () => _editTags(context, email, l10n),
        ),
      if (showCats)
        for (final c in email.categories)
          MailNotice(
            id: 'cat:$c',
            icon: AppIcons.label,
            iconColor: AppColors.accentOrangeText(context),
            label: c,
            detail: '$c · ${l10n.tr('outlookCategories')}',
            onTap: () => _editCategories(context, acc, email, l10n),
          ),
    ];
  }

  /// Проверка отправителя для пилюли предупреждения — один раз на письмо
  /// и заново, только когда пришло то, от чего она зависит (как считала
  /// прежняя карточка).
  void _checkSafety(EmailModel e) {
    final acc = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    if (acc == null) return;
    final key = '${acc.id}|${e.id}|${e.from.email}|${e.bodyHtml?.length ?? e.bodyPlain?.length ?? 0}'
        '|${e.attachments.length}|${e.authResults?.length ?? 0}';
    if (key == _safetyKey) return;
    _safetyKey = key;
    ref.read(senderSafetyServiceProvider).analyze(acc, e).then((r) {
      if (!mounted || _safetyKey != key) return;
      safeSetState(() => _safety = r);
    }, onError: (Object err) => AppLogger.debug('Проверка отправителя: $err'));
  }

  /// Проверка отправителя для «Отписаться» — один раз на письмо (результат
  /// проверки сервис помнит): при подозрении на подделку не было плашки, нет
  /// и чипа. Не удалась проверка — чип есть, как была плашка.
  String? _unsubCheckFor;
  bool _unsubSafe = false;

  bool _unsubscribeAllowed(AccountModel acc, EmailModel email) {
    final key = '${acc.id}|${email.id}';
    if (_unsubCheckFor != key) {
      _unsubCheckFor = key;
      _unsubSafe = false;
      ref.read(senderSafetyServiceProvider).analyze(acc, email).then((report) {
        if (_unsubCheckFor == key) safeSetState(() => _unsubSafe = report.level != SafetyLevel.danger);
      }, onError: (Object e) {
        if (_unsubCheckFor == key) safeSetState(() => _unsubSafe = true);
      });
    }
    return _unsubSafe;
  }

  // ════════════════════════ ВЛОЖЕНИЯ ════════════════════════

  /// Вложения компактной лентой: значок, имя, размер, состояние. Нажатие —
  /// как раньше (скачать/открыть), «скачать все» и «сохранить все» — в конце.
  Widget _attachmentStrip(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    final list = _visibleAttachments(email);
    final scheme = theme.colorScheme;
    // Над лентой — разделитель шапки (12 dp до линии), под лентой столько же
    // до своей линии: раньше снизу было 4 dp, и плашки «съезжали» вниз.
    // Высота — по содержимому (Row в прокрутке), а не фиксированные 56 dp:
    // при крупном шрифте плашки обрезались.
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Плашки прокручиваются, кнопка — на месте справа (раньше «скачать
          // все» и «сохранить все» стояли после плашек и уезжали за край).
          // Одна кнопка: пока не всё скачано — «Скачать», затем — «Сохранить».
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.s, Space.m),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final att in list)
                        Padding(
                          padding: const EdgeInsets.only(right: Space.s),
                          child: _attachmentChip(att, theme, l10n),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.s, bottom: Space.m),
                child: _attachmentsAction(email, list, l10n),
              ),
            ],
          ),
          // Место под полоску всегда занято — список не сдвигается.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: SizedBox(height: 2, child: _busyAll ? const LinearProgressIndicator(minHeight: 2) : null),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  /// Кнопка ленты вложений: «Скачать все» → после скачивания «Сохранить».
  Widget _attachmentsAction(EmailModel email, List<EmailAttachment> list, AppLocalizations l10n) {
    if (_busyAll) {
      return const SizedBox(
        width: Sizes.tapTarget,
        height: Sizes.tapTarget,
        child: Center(child: SizedBox(width: Sizes.iconRow, height: Sizes.iconRow, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final allLocal = list.isNotEmpty && list.every((a) => _attachmentStates[a.id]?.localPath != null);
    final many = list.length > 1;
    return allLocal
        ? IconButton.filledTonal(
            tooltip: l10n.tr(DownloadSaver.supported
                ? (many ? 'saveAllToDownloads' : 'saveToDownloads')
                : (many ? 'saveAll' : 'attachShareSave')),
            icon: const Icon(AppIcons.save_alt),
            onPressed: () => _saveAll(email),
          )
        : IconButton.filledTonal(
            tooltip: l10n.tr(many ? 'downloadAll' : 'downloadAttachment'),
            icon: const Icon(AppIcons.download),
            onPressed: () => _downloadAll(email),
          );
  }

  Widget _attachmentChip(EmailAttachment att, ThemeData theme, AppLocalizations l10n) {
    final state = _attachmentStates[att.id] ?? const _AttachmentState();
    final scheme = theme.colorScheme;
    // Перетаскивание наружу (1.15.0): на сенсорном экране его начинает
    // удержание — лист действий тогда, когда вложение удержали и отпустили
    // на месте (AttachmentDragSource.onHoldWithoutMove).
    final drag = AttachmentDragOut.available(context);
    final touchDrag = drag && AttachmentDragOut.touchDrag(defaultTargetPlatform);
    return AttachmentDragSource(
      attachment: att,
      localPath: () => _attachmentStates[att.id]?.localPath,
      fetch: () => _ensureLocal(att),
      onHoldWithoutMove: () => unawaited(_onAttachmentLongPress(att, l10n)),
      child: Semantics(
      label: '${l10n.tr('downloadAttachment')}: ${att.name}, ${att.sizeFormatted}',
      button: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.chipAll,
        child: InkWell(
          borderRadius: Radii.chipAll,
          onTap: () => _onAttachmentTap(att, l10n),
          // Долгое нажатие — шторка: просмотр, открыть в другом приложении,
          // поделиться/сохранить (раньше одиночное вложение можно было только
          // открыть; «сохранить» было лишь для всех сразу).
          onLongPress: touchDrag ? null : () => _onAttachmentLongPress(att, l10n),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.m, Space.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: Space.xxl, height: 32, child: FittedBox(child: _attachmentIcon(att))),
                const SizedBox(width: Space.s),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(att.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                      Text(
                        state.error != null ? l10n.tr('error') : att.sizeFormatted,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: state.error != null ? AppColors.errorText(context) : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                if (state.isDownloading)
                  const SizedBox(width: Space.l, height: Space.l, child: CircularProgressIndicator(strokeWidth: 2))
                else if (state.localPath != null)
                  Icon(AppIcons.check_circle, color: AppColors.successText(context), size: Space.l),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _onAttachmentTap(EmailAttachment att, AppLocalizations l10n) async {
    // Организация запретила вложения на устройстве (MDM block_attachment_download).
    if (ManagedPolicy.deny(ManagedRule.attachments)) return;
    final state = _attachmentStates[att.id];
    if (state == null) return;

    // Если уже скачано — открыть предпросмотр ВНУТРИ приложения (картинки, PDF,
    // текст). Раньше сразу уходили во внешнее приложение: это уводит из почты и
    // требует установленной программы под формат. Кнопка «Открыть во внешнем»
    // осталась на экране предпросмотра.
    if (state.localPath != null) {
      unawaited(HapticFeedback.selectionClick());
      await _openPreview(state.localPath!, att);
      return;
    }

    // Если скачивается — ждём
    if (state.isDownloading) return;

    // Уже в кэше? Тогда открываем сразу — сеть не нужна. Раньше эта проверка
    // отсутствовала: одно и то же вложение качалось при КАЖДОМ открытии,
    // хотя кэш-сервис в проекте был.
    final cacheKey = MailEngineService.attachmentCacheKey(
        widget.accountId, widget.emailId, att.id);
    final cached = await ref.read(attachmentCacheProvider).get(cacheKey);
    if (cached != null) {
      safeSetState(() {
        _attachmentStates[att.id] = _AttachmentState(localPath: cached);
      });
      unawaited(HapticFeedback.selectionClick());
      await _openPreview(cached, att);
      return;
    }

    // Скачиваем
    safeSetState(() {
      _attachmentStates[att.id] = const _AttachmentState(isDownloading: true);
    });

    try {
      final accounts = ref.read(accountsProvider);
      // Аккаунт мог быть удалён, пока экран открыт: firstWhere без orElse
      // бросал бы StateError и ронял операцию.
      final account = accounts.where((a) => a.id == widget.accountId).firstOrNull;
      if (account == null) return;

      // Скачиваем байты через фасад движка: он сам выбирает протокол
      // (EAS — ItemOperations, EWS — GetAttachment, IMAP — часть MIME).
      // Раньше ветка выбиралась по account.isExchange, и у ActiveSync-ящиков
      // запрос уходил в IMAP-ветку — вложение не открывалось.
      final bytes = await safeAsync(() => ref
          .read(mailEngineServiceProvider)
          .getAttachmentBytes(account, att.id, emailId: widget.emailId));
      if (bytes == null) return; // disposed

      // В КЭШ, а не в Documents: один файл на содержимое (MD5), LRU +
      // очистка по давности. Ключ включает письмо — в IMAP id вложения
      // («2», «3») повторяется в разных письмах.
      final filePath = await ref
          .read(attachmentCacheProvider)
          .put(cacheKey, att.name, bytes);

      safeSetState(() {
        _attachmentStates[att.id] = _AttachmentState(localPath: filePath);
      });

      unawaited(HapticFeedback.mediumImpact());

      // Открываем во внешнем приложении (письмо — в почте), см. _openPreview.
      await _openPreview(filePath, att);
    } catch (e) {
      safeSetState(() {
        _attachmentStates[att.id] = _AttachmentState(error: e.toString());
      });

      // Письма уже нет на сервере (ActiveSync ItemOperations Status 6 —
      // «объект не найден», 15 — неверный id): понятной строкой, а не
      // «Bad state: EAS: ItemOperations Fetch Status=6» (журнал владельца
      // 08.11.2026; синхронизация следом удаляет письмо и у нас).
      final gone = RegExp(r'ItemOperations Fetch Status=(6|15)\b').hasMatch('$e');
      if (mounted) quietError(gone ? l10n.tr('attachmentGoneOnServer') : '${l10n.tr('error')}: $e');
    }
  }

  Future<void> _onAttachmentLongPress(EmailAttachment att, AppLocalizations l10n) async {
    unawaited(HapticFeedback.selectionClick());
    final action = await showActionSheet<String>(
      context,
      title: att.name,
      subtitle: att.sizeFormatted,
      leading: _attachmentIcon(att),
      items: [
        // Просмотра в приложении нет (1.5.10): «Открыть» — то же, что
        // нажатие (внешнее приложение, письмо — в почте).
        ActionSheetItem(icon: AppIcons.open_in_new, label: l10n.tr('openExternallyApp'), value: 'open'),
        // «Сохранить в Загрузки» — отдельным пунктом (1.6.33): в листе
        // «Поделиться» Android такого пункта нет.
        if (DownloadSaver.supported)
          ActionSheetItem(icon: AppIcons.save_alt, label: l10n.tr('saveToDownloads'), value: 'save'),
        ActionSheetItem(
            icon: AppIcons.ios_share,
            label: l10n.tr(DownloadSaver.supported ? 'share' : 'attachShareSave'),
            value: 'share'),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'open') {
      await _onAttachmentTap(att, l10n);
      return;
    }
    final path = await _ensureLocal(att);
    if (path == null || !mounted) return;
    if (action == 'save') {
      await DownloadSaver.saveWithFeedback(context, [(path: path, name: att.name)]);
      return;
    }
    // Системный лист «Поделиться» умеет и «Сохранить в Файлы» (iOS),
    // и «Загрузки»/Диск (Android).
    // Копия с именем из письма: в кэше файл лежит под служебным именем (1.6.5).
    await appShare(ShareParams(files: [XFile(await FileOpener.namedCopy(path, att.name), name: att.name)]));
  }

  /// Локальный путь вложения: из состояния, из кэша или скачав.
  Future<String?> _ensureLocal(EmailAttachment att) async {
    final known = _attachmentStates[att.id]?.localPath;
    if (known != null && File(known).existsSync()) return known;
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null) return null;
    safeSetState(() => _attachmentStates[att.id] = const _AttachmentState(isDownloading: true));
    try {
      final path = await _fetchToCache(att, account);
      safeSetState(() => _attachmentStates[att.id] = _AttachmentState(localPath: path));
      return path;
    } catch (e) {
      safeSetState(() => _attachmentStates[att.id] = _AttachmentState(error: e.toString()));
      return null;
    }
  }

  Widget _attachmentIcon(EmailAttachment att) =>
      FileTypeIcon(category: FileTypeStyle.categoryOf(att.mimeType, att.name));


  // ════════════════════════ НИЖНЯЯ ПАНЕЛЬ ════════════════════════

  /// Широкий экран — окно планшета или компьютера (обе стороны от 600,
  /// ширина от 840). Узкая панель письма в нём — та же раскладка: кнопки
  /// панели команд сами переходят на значки.
  static bool _wideLayout(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return s.shortestSide >= 600 && s.width >= 840;
  }

  /// Строка «Ответить…» на широком экране (1.10.5): своя кнопка отправки
  /// и «Ответить всем» — нижней панели с кнопками нет.
  Widget? _wideReplyBar(ThemeData theme, EmailModel email) {
    final draft = email.isDraft || email.folderId == 'drafts';
    if (draft || !ref.watch(quickReplyBarProvider)) return null;
    return ColoredBox(
      color: mailPageColor(theme),
      child: SafeArea(
        top: false,
        // Column: без неё ReadableWidth (Align) занял бы всю высоту, которую
        // Scaffold даёт bottomNavigationBar, — весь экран.
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ReadableWidth(
            fill: true,
            child: QuickReplyBar(key: ValueKey('qrw_${email.accountId}_${email.id}'), email: email),
          ),
        ]),
      ),
    );
  }

  /// Панель команд над письмом (1.10.5, широкий экран, по образцу Outlook):
  /// ответ, пересылка, удалить, в архив, переместить, флажок, прочитано,
  /// позже и «Ещё» (все действия). Подписи — пока помещаются; иначе
  /// значки с подсказками (узкая панель письма рядом с лентой).
  Widget _commandBar(EmailModel email, AppSettings settings, AppLocalizations l10n) {
    final draft = email.isDraft || email.folderId == 'drafts';
    final scheme = Theme.of(context).colorScheme;
    void compose(Map<String, String> q) => _compose({...q, 'accountId': email.accountId});
    final id = email.id;
    final groups = <List<_Cmd>>[
      [
        if (draft)
          _Cmd(AppIcons.edit, l10n.tr('edit'), () => compose({'draftId': id}))
        else ...[
          _Cmd(AppIcons.reply, l10n.tr('reply'), () => compose({'replyToId': id}),
              onLongPress: () => _showQuickReplies(email, l10n)),
          _Cmd(AppIcons.reply_all, l10n.tr('replyAll'), () => compose({'replyToId': id, 'replyAll': 'true'})),
          _Cmd(AppIcons.forward, l10n.tr('forward'), () => _forward(email)),
        ],
      ],
      [
        _Cmd(AppIcons.delete, l10n.delete, () => unawaited(_deleteFromBar(email, l10n))),
        if (!draft) _Cmd(AppIcons.archive, l10n.tr('archive'), () => unawaited(_archiveEmail(email, l10n))),
        if (!draft) _Cmd(AppIcons.drive_file_move, l10n.tr('moveTo'), () => unawaited(_moveEmail(email, l10n))),
      ],
      [
        _Cmd(AppIcons.flag, l10n.tr('flag'), () => _toggleFlag(email),
            selected: email.isFlagged, color: email.isFlagged ? AppColors.errorRed : null),
        _Cmd(email.isRead ? AppIcons.mark_email_unread : AppIcons.mark_email_read,
            l10n.tr(email.isRead ? 'markUnread' : 'markRead'), () => _setReadKey(email, !email.isRead)),
        if (!draft)
          _Cmd(AppIcons.watch_later, l10n.tr('later'), () => unawaited(_later(context, email)),
              selected: email.laterState != 0),
      ],
    ];
    final more = IconButton(
      tooltip: l10n.tr('more'),
      icon: const Icon(AppIcons.more_horiz),
      onPressed: () => _showFullActionsSheet(context, l10n, email, settings),
    );
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return LayoutBuilder(builder: (context, c) {
      double textW(String t) {
        final tp = TextPainter(
          text: TextSpan(text: t, style: labelStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final w = tp.width;
        tp.dispose();
        return w;
      }

      const iconW = 44.0, gap = 13.0, moreW = 48.0;
      // Подписи — по важности (как в Outlook): ответ, пересылка, удалить,
      // архив… пока помещаются; остальные — значками с подсказкой.
      final cmds = [for (final g in groups) ...g];
      final extra = [for (final c in cmds) 20 + 8 + 24 + textW(c.label) - iconW];
      var used = moreW + gap * (groups.length - 1) + iconW * cmds.length;
      final withLabel = <_Cmd>{};
      for (var i = 0; i < cmds.length; i++) {
        if (used + extra[i] > c.maxWidth) break;
        used += extra[i];
        withLabel.add(cmds[i]);
      }
      bool labeled(_Cmd cmd) => withLabel.contains(cmd);
      final row = <Widget>[];
      for (var gi = 0; gi < groups.length; gi++) {
        if (gi > 0) {
          row.add(Container(
              width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: scheme.outlineVariant));
        }
        for (final cmd in groups[gi]) {
          row.add(_commandButton(cmd, labeled(cmd), scheme));
        }
      }
      row.add(more);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: row),
      );
    });
  }

  Widget _commandButton(_Cmd cmd, bool labeled, ColorScheme scheme) {
    final color = cmd.color ?? (cmd.selected ? scheme.primary : scheme.onSurface);
    final icon = Icon(cmd.icon, size: 20, fill: cmd.selected ? 1 : 0, color: color);
    void tap() {
      HapticFeedback.selectionClick();
      cmd.onTap();
    }

    final Widget button = labeled
        ? TextButton.icon(
            onPressed: tap,
            onLongPress: cmd.onLongPress,
            icon: icon,
            label: Text(cmd.label),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
          )
        : IconButton(onPressed: tap, icon: icon, tooltip: cmd.label);
    final withLong = (!labeled && cmd.onLongPress != null)
        ? GestureDetector(onLongPress: cmd.onLongPress, child: button)
        : button;
    return labeled ? Tooltip(message: cmd.label, child: withLong) : withLong;
  }

  /// «Переместить» (панель команд, 1.10.5; «Ещё» на телефоне, 1.15.0):
  /// папки ящика этого письма.
  Future<void> _moveEmail(EmailModel email, AppLocalizations l10n) async {
    final targetId = await pickMoveFolder(context, ref, email);
    if (targetId == null || !mounted) return;
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    final notifier = ref.read(emailsProvider.notifier);
    final actions = ref.read(emailActionsProvider);
    notifier.hideLocally(email);
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('emailMoved'),
        execute: () => actions.moveTo(account, email.id, email.folderId, targetId),
        undo: () async {},
        onUndo: () => notifier.unhideLocally(email),
        onSettled: () => notifier.unhideLocally(email),
      ),
    );
    _closeAfterAction();
  }

  Widget _buildBottomBar(
    BuildContext context, ThemeData theme, AppLocalizations l10n,
    EmailModel email, AppSettings settings,
  ) {
    final draft = email.isDraft || email.folderId == 'drafts';
    // Строка «Ответить…» (1.6.49) — не у черновиков; выключается в
    // «Настройки → Почта». С 1.7.3 — плавающей карточкой над кнопками.
    final quick = !draft && ref.watch(quickReplyBarProvider);
    final order = ref.watch(mailBarOrderProvider);
    final outlined = OgnelissLook.of(context).outlined;
    final bar = Container(
      decoration: BoxDecoration(
        // Цвет страницы письма: в AMOLED панель была серой полосой под чёрным.
        color: mailPageColor(theme),
        // Плоская панель с тонкой линией сверху (1.8.0, «воздушный» вид);
        // тень — в высококонтрастной теме.
        border: outlined ? null : Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        boxShadow: outlined
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, -1))]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
      child: SafeArea(
        top: false,
        // Кнопки «Ответить» меняются, когда в быстром ответе появился текст.
        // Широкое окно (планшет, компьютер, 1.8.13): кнопки — по центру
        // колонкой шириной с телефон, а не через весь экран, где до «Ответить»
        // от «Удалить» было полметра.
        child: ListenableBuilder(
          listenable: _quickReply,
          // heightFactor: 1 — панель высотой по кнопкам. Без неё Align
          // ReadableWidth занимал всю высоту, которую Scaffold даёт
          // bottomNavigationBar (весь экран), когда строки «Ответить…» нет
          // (с ней панель — в Column, где высота не ограничена).
          builder: (context, _) => ReadableWidth(
            maxWidth: 600,
            fill: true,
            heightFactor: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _barButtons(email, settings, l10n, order: order, draft: draft),
            ),
          ),
        ),
      ),
    );
    if (!quick) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Строка ответа — шириной с колонку письма (как шапка и текст).
        ColoredBox(
          color: mailPageColor(theme),
          child: ReadableWidth(
            fill: true,
            child: QuickReplyBar(
              key: ValueKey('qr_${email.accountId}_${email.id}'),
              email: email,
              controller: _quickReply,
            ),
          ),
        ),
        bar,
      ],
    );
  }

  /// Кнопки под письмом в порядке из настройки (1.7.3; по умолчанию — под
  /// правую руку: «Ответить» справа, «Удалить» — подальше от системной
  /// «Назад»). Черновику — «Изменить» рядом с «Ответить», со стороны края.
  List<Widget> _barButtons(EmailModel email, AppSettings settings, AppLocalizations l10n,
      {required List<MailBarAction> order, required bool draft}) {
    final quick = _quickReply.hasText;
    final sending = _quickReply.sending;
    final replyAt = order.indexOf(MailBarAction.reply);
    final editAfter = replyAt >= order.length / 2;
    Widget edit() => _bottomAction(AppIcons.edit, l10n.tr('edit'), () {
          context.push('/compose?draftId=${Uri.encodeQueryComponent(email.id)}'
              '&accountId=${Uri.encodeQueryComponent(email.accountId)}');
        });
    final out = <Widget>[];
    for (final a in order) {
      if (draft && a == MailBarAction.reply && !editAfter) out.add(edit());
      out.add(switch (a) {
        MailBarAction.reply => _replyButton(email, l10n, all: false, quick: quick, sending: sending),
        MailBarAction.replyAll => _replyButton(email, l10n, all: true, quick: quick, sending: sending),
        MailBarAction.forward => _bottomAction(AppIcons.forward, l10n.tr('forward'), () => _forward(email)),
        // «Посмотреть позже» — сейчас не до этого.
        MailBarAction.later => _bottomAction(AppIcons.watch_later, l10n.tr('later'), () {
            unawaited(_later(context, email));
          }, filled: email.laterState != 0),
        MailBarAction.delete => _bottomAction(AppIcons.delete, l10n.delete, () {
            unawaited(_deleteFromBar(email, l10n));
          }),
        // Подпись — для TalkBack и VoiceOver (раньше пустая: «кнопка» без имени).
        MailBarAction.more => _bottomAction(AppIcons.more_horiz, l10n.tr('more'), () {
            _showFullActionsSheet(context, l10n, email, settings);
          }),
      });
      if (draft && a == MailBarAction.reply && editAfter) out.add(edit());
    }
    return out;
  }

  /// «Ответить» / «Ответить всем» (1.7.3): в быстром ответе набран текст —
  /// кнопка залита цветом и отправляет его (быстрым ответом: приветствие,
  /// текст, подпись); поле пусто — полный редактор. Долгое нажатие на
  /// «Ответить» — готовые формулировки и шаблоны.
  Widget _replyButton(EmailModel email, AppLocalizations l10n,
      {required bool all, required bool quick, required bool sending}) {
    final icon = all ? AppIcons.reply_all : AppIcons.reply;
    if (quick) {
      final tip = l10n.tr(all ? 'quickReplySendAll' : 'quickReplySend');
      final VoidCallback? onTap = sending
          ? null
          : () {
              HapticFeedback.selectionClick();
              unawaited(_quickReply.send(all: all));
            };
      const box = BoxConstraints(minWidth: 48, minHeight: 48);
      return Semantics(
        label: tip,
        button: true,
        child: all
            ? IconButton.filledTonal(tooltip: tip, onPressed: onTap, icon: Icon(icon), constraints: box)
            : IconButton.filled(tooltip: tip, onPressed: onTap, icon: Icon(icon), constraints: box),
      );
    }
    return _bottomAction(icon, l10n.tr(all ? 'replyAll' : 'reply'), () {
      context.push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}'
          '&accountId=${Uri.encodeQueryComponent(email.accountId)}${all ? '&replyAll=true' : ''}');
    }, onLongPress: all ? null : () => _showQuickReplies(email, l10n));
  }

  /// «Переслать»: набранный в быстром ответе текст — в начало пересылки.
  void _forward(EmailModel email) {
    final text = _quickReply.hasText ? _quickReply.take() : '';
    _compose({
      'forwardFromId': email.id,
      'accountId': email.accountId,
      if (text.isNotEmpty) 'quick': text,
    });
  }

  /// Ответ, пересылка, черновик (1.11.0): на планшете и компьютере в панели
  /// рядом с лентой — прямо в панели (как в Outlook), иначе — отдельным
  /// экраном, как раньше.
  void _compose(Map<String, String> q) {
    if (PaneNavigator.isInside(context) && _wideLayout(context)) {
      unawaited(PaneNavigator.push<void>(
        context,
        ComposeScreen(
          replyToId: q['replyToId'],
          forwardFromId: q['forwardFromId'],
          draftId: q['draftId'],
          accountId: q['accountId'],
          replyAll: q['replyAll'] == 'true',
          quoteFragment: q['fragment'],
          quickText: q['quick'],
        ),
      ));
      return;
    }
    context.push(Uri(path: '/compose', queryParameters: q).toString());
  }

  /// «Ответить с цитатой» из меню выделенного текста письма (2.0.0): ответ
  /// отправителю, в цитате — только выделенное.
  void _replyWithFragment(EmailModel email, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _compose({
      'replyToId': email.id,
      'accountId': email.accountId,
      'fragment': t.length > 4000 ? t.substring(0, 4000) : t,
    });
  }

  /// «Удалить» под письмом (1.7.3): по умолчанию — с вопросом (письма
  /// удаляли случайно, промахнувшись мимо системной «Назад»); вопрос
  /// выключается в «Настройки → Почта».
  Future<void> _deleteFromBar(EmailModel email, AppLocalizations l10n) async {
    if (ref.read(confirmMailDeleteProvider)) {
      final subject = email.subject.trim();
      final ok = await confirmDestructive(
        context,
        title: l10n.tr('deleteMailAskTitle'),
        message: subject.isEmpty ? null : cutSafe(subject, 120),
      );
      if (!ok || !mounted) return;
    }
    _deleteEmail(email, l10n);
  }

  /// [onTap] = null — кнопка неактивна (подсказка объясняет почему).
  Widget _bottomAction(IconData icon, String tooltip, VoidCallback? onTap,
      {VoidCallback? onLongPress, bool filled = false}) {
    final button = IconButton(
      icon: Icon(icon, fill: filled ? 1.0 : 0.0, color: filled ? Theme.of(context).colorScheme.primary : null),
      tooltip: onLongPress == null ? tooltip : null,
      onPressed: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
            },
      constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
    );
    // Подпись под значком (оценка интерфейса 12.11.2026: «Позже» и «Ответить
    // всем» без подписи не узнавались). Длинная — мельче, не обрезается.
    final labeled = Column(mainAxisSize: MainAxisSize.min, children: [
      button,
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 64),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(tooltip,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ),
      ),
    ]);
    return Semantics(
      label: tooltip,
      button: true,
      excludeSemantics: true,
      child: onLongPress == null
          ? labeled
          : GestureDetector(
              onLongPress: () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
              child: labeled,
            ),
    );
  }

  /// Быстрые ответы: короткие рабочие формулировки и шаблоны пользователя.
  /// Выбранный текст подставляется в ответ между приветствием и подписью —
  /// остаётся проверить и нажать «Отправить».
  ///
  /// 1.8.12 (замечание 30.10.2026: «быстрые ответы отличаются от остального
  /// UI») — карточкой, как остальные выборы; «ответить всем» — переключатель
  /// в шапке карточки (было скрытое долгое нажатие на строку).
  Future<void> _showQuickReplies(EmailModel email, AppLocalizations l10n) async {
    final templates = [for (final t in ref.read(templatesProvider)) t.resolve(l10n.tr)];
    const builtIn = ['quickReply1', 'quickReply2', 'quickReply3', 'quickReply4', 'quickReply5'];
    final texts = [for (final k in builtIn) l10n.tr(k), for (final t in templates) t.body];
    const manage = -1;
    final all = ValueNotifier<bool>(false);
    final picked = await showChoiceSheet<int>(
      context,
      title: l10n.tr('quickReplies'),
      subtitle: l10n.tr('quickRepliesCardHint'),
      headerTrailing: ValueListenableBuilder<bool>(
        valueListenable: all,
        builder: (ctx, on, _) => IconButton(
          tooltip: l10n.tr(on ? 'quickReplyToSender' : 'replyAll'),
          isSelected: on,
          icon: const Icon(AppIcons.reply),
          selectedIcon: Icon(AppIcons.reply_all, color: Theme.of(ctx).colorScheme.primary),
          onPressed: () => all.value = !on,
        ),
      ),
      entries: [
        for (var i = 0; i < builtIn.length; i++)
          AppMenuEntry(value: i, icon: AppIcons.quickreply, label: texts[i]),
        for (var j = 0; j < templates.length; j++)
          AppMenuEntry(
            value: builtIn.length + j,
            icon: AppIcons.description,
            label: templates[j].title.isEmpty ? templates[j].body : templates[j].title,
            subtitle: templates[j].title.isEmpty ? null : templates[j].body,
          ),
        AppMenuEntry(value: manage, icon: AppIcons.edit_note, label: l10n.tr('quickRepliesManage')),
      ],
    );
    final toAll = all.value;
    all.dispose();
    if (picked == null || !mounted) return;
    if (picked == manage) {
      unawaited(context.push('/settings/templates'));
      return;
    }
    unawaited(context.push(Uri(path: '/compose', queryParameters: {
      'replyToId': email.id,
      'accountId': email.accountId,
      if (toAll) 'replyAll': 'true',
      'quick': texts[picked],
    }).toString()));
  }

  // ════════════════════════ ПОЛНЫЙ BOTTOM SHEET ════════════════════════

  void _showFullActionsSheet(
    BuildContext context, AppLocalizations l10n, EmailModel email, AppSettings settings,
  ) {
    // Действия сгруппированы по смыслу (раньше — сплошная сетка из 20+
    // значков, где «Экспорт», «Сохранить PDF» и «Печать» делали одно и то же).
    final isExchange = ref.read(accountsProvider).any((a) => a.id == email.accountId && a.isMsExchange);
    final convMuted = ref.read(mutedConversationsProvider.notifier).isMuted(email.accountId, email.conversationId);
    // Та же карточка, что по удержанию письма в ленте (1.8.8, замечание
    // владельца 29.10.2026): шапка с письмом и все действия по группам —
    // круглыми кнопками, сразу развёрнуты.
    unawaited(showMailPeek(
      context,
      email: email,
      anchor: null,
      previewLines: 2,
      moreOpen: true,
      actions: const [],
      more: [
        PeekGroup(title: l10n.tr('actionsRespond'), items: [
          _peekAction(AppIcons.reply, l10n.tr('reply'), () => context.push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}')),
          _peekAction(AppIcons.reply_all, l10n.tr('replyAll'), () => context
              .push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}&replyAll=true')),
          _peekAction(AppIcons.quickreply, l10n.tr('quickReplies'),
              () => _showQuickReplies(email, l10n)),
          _peekAction(AppIcons.attach_email, l10n.tr('asEml'),
                () => unawaited(_forwardAsEml(email))),
        ]),
        PeekGroup(title: l10n.tr('actionsOrganize'), items: [
          _peekAction(AppIcons.archive, l10n.tr('archive'), () => _archiveEmail(email, l10n)),
          // «Переместить» (1.15.0, замечание владельца 07.11.2026: в письме
          // на телефоне его не было — только на панели команд компьютера).
          if (!(email.isDraft || email.folderId == 'drafts'))
            _peekAction(AppIcons.drive_file_move, l10n.tr('moveTo'), () => unawaited(_moveEmail(email, l10n))),
          _peekAction(email.isRead ? AppIcons.mark_email_unread : AppIcons.mark_email_read,
              email.isRead ? l10n.tr('markUnread') : l10n.tr('markRead'), () {
            final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
            if (acc != null) {
              final newRead = !email.isRead;
              ref.read(emailActionsProvider).setRead(acc, email.id, email.folderId, newRead);
              ref.read(emailsProvider.notifier).applyLocalFlags(email.id, isRead: newRead);
              safeSetState(() => _email = email.copyWith(isRead: newRead));
            }
          }),
          _peekAction(AppIcons.flag, l10n.tr('flag'), fill: email.isFlagged,
              () => _toggleFlag(email)),
          // Важность (замечание 07.10.2026: поставить было нельзя)
          _peekAction(AppIcons.priority_high, l10n.tr('importance'),
              () => unawaited(_pickImportance(email, l10n))),
          // «На контроль» (вместе с бывшим «Напомнить, если нет
          // ответа»): меню со сроком; снять — там же.
          if (ref.read(settingsProvider).mailControl)
            _peekAction(AppIcons.task_alt,
                l10n.tr(email.controlState == 0 ? 'controlSet' : 'controlFilter'),
                () => unawaited(_controlMenu(email)),
                fill: email.controlState != 0),
          _peekAction(AppIcons.label, l10n.tr('addTag'), () => _editTags(context, email, l10n)),
          // Категории Outlook — только у Exchange
          if (isExchange)
            _peekAction(AppIcons.new_label, l10n.tr('outlookCategories'), () {
              final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
              if (acc != null) _editCategories(context, acc, email, l10n);
            }),
          _peekAction(AppIcons.report, l10n.tr('moveToJunk'), () => _moveToJunk(email, l10n)),
          // Заблокировать отправителя и «Чистка» (1.10.x).
          _peekAction(AppIcons.block,
              l10n.tr(isSenderBlocked(ref, email.from.email, email.accountId) ? 'unblockSender' : 'blockSender'),
              () => unawaited(_blockSender(email))),
          _peekAction(AppIcons.cleaning_services, l10n.tr('sweepShort'), () => unawaited(_sweepSender(email))),
        ]),
        PeekGroup(title: l10n.tr('actionsCreate'), items: [
          // Встреча по письму: тема, участники и текст — из письма.
          _peekAction(AppIcons.event, l10n.tr('createEvent'), () => _planMeeting(email)),
          _peekAction(AppIcons.check_box, l10n.tr('createTask'), () => _createTask(email, l10n)),
          // Поручение по письму (2.2.0, решение владельца 09.11.2026).
          _peekAction(AppIcons.assignment_ind, l10n.tr('assignSheetTitle'), () => unawaited(
              showAssignSheet(context, sourceEmailId: email.id, accountId: email.accountId))),
          _peekAction(AppIcons.watch_later, l10n.tr('later'), fill: email.laterState != 0,
              () => unawaited(_later(context, email))),
          // Правило на телефоне для этого отправителя (09.10.2026).
          _peekAction(AppIcons.rule, l10n.tr('ruleShort'), () => unawaited(
              openDeviceRule(context, sender: email.from.email, accountId: email.accountId))),
        ]),
        PeekGroup(title: l10n.tr('actionsSave'), items: [
          // Письмо целиком — в архив Ogneliss (1.7.3); архива нет —
          // сначала создать (29.10.2026: пункт был скрыт до создания).
          _peekAction(AppIcons.inventory_2, l10n.tr('toOgnaArchive'),
              () => unawaited(_toOgnaArchive(email, l10n))),
          _peekAction(AppIcons.picture_as_pdf, l10n.tr('saveAsPdf'),
              () => unawaited(_exportPdf(email, l10n))),
          // Печать — через PDF: системный просмотрщик/«Поделиться»
          // отправляет его на принтер на любой платформе.
          _peekAction(AppIcons.print, l10n.tr('print'), () => unawaited(_exportPdf(email, l10n))),
          _peekAction(AppIcons.share, l10n.tr('share'), () => appShare(
              ShareParams(text: '${email.subject}\n\n${email.bodyPlain ?? email.bodyPreview ?? ""}'))),
        ]),
        PeekGroup(title: l10n.tr('actionsMore'), items: [
          // Поиск в письме (2.2.0, план 08.11.2026).
          _peekAction(AppIcons.search, l10n.tr('findInMail'), _openFind),
          // Письмо в отдельном окне — компьютер (1.9.x, просьба владельца
          // 31.10.2026).
          if (MessageWindow.supported)
            _peekAction(AppIcons.open_in_new, l10n.tr('openInNewWindow'), () => unawaited(_openInWindow(email))),
          // Перевод на устройстве (1.9.x): то же, что чип строки сведений.
          // Движка перевода нет (iOS до 18, Mac до 15, ML Kit не запустился)
          // — пункта нет (1.12.x).
          if (translationPlatformSupported && _translation.engineAvailable != false)
            _peekAction(AppIcons.translate, l10n.tr(_translation.showing ? 'translateShowOriginal' : 'translate'),
                () => _translation.showing
                    ? _translation.showOriginal()
                    : unawaited(_translation.translate(context, email))),
          _peekAction(AppIcons.info, l10n.tr('messageDetails'),
              () => _showMessageDetails(email, l10n)),
          // «Исходные цвета» (1.9.x): в тёмной теме — письмо как задумано,
          // светлым, без перекраски; отмечено — включено для этого письма.
          if (Theme.of(context).brightness == Brightness.dark && _inWebView(email))
            _peekAction(AppIcons.palette, l10n.tr('mailOriginalColors'), fill: _originalColors(email),
                () => _toggleOriginalColors(email)),
          // «Найти документ»: все файлы этого отправителя из всех писем.
          if (email.from.email.contains('@') && ref.read(featureFlagsProvider).showFileHub)
            _peekAction(AppIcons.attach_file, l10n.tr('senderFiles'), () => unawaited(
                context.push('/attachment-hub?from=${Uri.encodeQueryComponent(email.from.email)}'))),
          _peekAction(AppIcons.sync, l10n.tr('redownload'), _loadEmailDetail),
          // Беседа без уведомлений (1.8.13, как «Без звука» в Telegram).
          if ((email.conversationId ?? '').isNotEmpty)
            _peekAction(convMuted ? AppIcons.notifications_active : AppIcons.notifications_off,
                l10n.tr(convMuted ? 'convUnmute' : 'convMute'), () => unawaited(_toggleMute(email, l10n))),
          // Отзыв письма (нативно — Exchange ActiveSync 16.1).
          if (_canRecall(ref, email))
            _peekAction(AppIcons.undo, l10n.tr('recallMessage'),
                () => _confirmRecall(context, ref, email, l10n)),
        ]),
      ],
    ));
  }

  /// Беседа письма без уведомлений или снова с ними (1.8.13).
  Future<void> _toggleMute(EmailModel email, AppLocalizations l10n) async {
    final conv = email.conversationId;
    if (conv == null || conv.isEmpty) return;
    final muted = await ref.read(mutedConversationsProvider.notifier).toggle(email.accountId, conv);
    if (mounted) showInlineNotice(l10n.tr(muted ? 'convMutedNotice' : 'convUnmutedNotice'));
  }

  /// Поставить или снять «На контроле».
  static final _easHeadersTried = <String>{};

  Future<void> _loadEasHeaders(AccountModel account, EmailModel email) async {
    if (!_easHeadersTried.add('${email.accountId}|${email.id}')) return;
    // База — заранее: экран могут закрыть, пока идёт запрос (ref после
    // закрытия бросал ошибку — журнал 09.10.2026).
    final db = ref.read(databaseProvider);
    final h = await ref
        .read(mailEngineServiceProvider)
        .fetchEasHeaders(account, folderId: email.folderId, serverId: email.id);
    if (h == null) return;
    final unsub = encodeListUnsubscribe(
        unsubscribe: h['list-unsubscribe'], post: h['list-unsubscribe-post'], listId: h['list-id']);
    // «none» — заголовка нет, но письмо уже проверено (не запрашивать снова).
    final auth = (h['authentication-results'] ?? '').trim().isEmpty ? 'none' : h['authentication-results']!;
    // Гриф в MIME: ActiveSync отдаёт заголовки только из начала MIME.
    final label = MailLabel.fromHeaders(
      sensitivity: h['sensitivity'],
      classification: h['x-ogneliss-classification'],
      handling: h['x-ogneliss-handling'],
    );
    final hasLabel = MailLabel.decode(label).hasExtras;
    await (db.update(db.emails)..where((e) => e.id.equals(email.id) & e.accountId.equals(email.accountId)))
        .write(EmailsCompanion(
          listUnsubscribe: unsub == null ? const Value.absent() : Value(unsub),
          authResults: Value(auth),
          sensitivity: hasLabel ? Value(label) : const Value.absent(),
        ));
    if (!mounted || _email?.id != email.id) return;
    safeSetState(() => _email = _email!.copyWith(
        listUnsubscribe: unsub, authResults: auth, sensitivity: hasLabel ? label : null));
  }

  /// Меню «На контроль»: срок или без срока, снять.
  Future<void> _controlMenu(EmailModel email) async {
    final c = await showControlSheet(context, ref, email);
    if (c == null || !mounted) return;
    unawaited(HapticFeedback.selectionClick());
    final next = await applyControl(ref, email, c);
    final deadline = c.clear ? null : c.deadline;
    safeSetState(() => _email = (_email ?? email).copyWith(
          controlState: next,
          clearControl: c.clear || c.deadline == null,
          followUpAt: deadline,
          controlReplied: (_email ?? email).controlReplied,
        ));
  }

  Future<void> _setControl(EmailModel email, bool on) async {
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    final next = on
        ? ControlService.initialFor(fromEmail: email.from.email, myEmail: acc == null ? '' : OwnAddresses.of(acc).join(','), to: [for (final a in email.to) a.email])
        : ControlState.none;
    unawaited(HapticFeedback.selectionClick());
    await ref.read(databaseProvider).setControlState(email.id, email.accountId, next);
    ref.read(emailsProvider.notifier).applyLocalFlags(email.id, controlState: next);
    ref.read(controlRevisionProvider.notifier).state++;
    safeSetState(() => _email = (_email ?? email).copyWith(controlState: next));
  }

  /// Текст «На контроле»: состояние, кто ответил, кого ждём, срок. Первая
  /// часть и срок — надпись чипа строки сведений (1.12.x), всё — плашка.
  List<String> _controlParts(EmailModel email, AppLocalizations l10n) {
    final done = email.controlState == ControlState.done;
    final base = l10n.tr(done
        ? 'controlDone'
        : (email.controlState == ControlState.awaitingReply ? 'controlAwaiting' : 'controlMustReply'));
    // Моё письмо нескольким адресатам: кто ответил, кого ждём.
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    final me = (acc?.email ?? '').toLowerCase();
    final to = [for (final a in email.to) if (a.email.toLowerCase() != me) a];
    final replied = ControlService.repliedSet(email.controlReplied);
    final parts = <String>[base];
    if (email.controlState == ControlState.awaitingReply && to.length > 1) {
      final n = to.where((a) => replied.contains(a.email.toLowerCase())).length;
      parts.add(l10n.tr('controlRepliedOf').replaceAll('{n}', '$n').replaceAll('{total}', '${to.length}'));
      final waiting = [for (final a in to) if (!replied.contains(a.email.toLowerCase())) a.label.split(' ').first];
      if (waiting.isNotEmpty && waiting.length <= 3) {
        parts.add(l10n.tr('controlWaitingFor').replaceAll('{names}', waiting.join(', ')));
      }
    }
    if (!done && email.followUpAt != null) {
      parts.add(l10n.tr('controlUntil').replaceAll('{when}', controlDeadlineLabel(email.followUpAt!.toLocal(), l10n)));
    }
    return parts;
  }

  Widget _controlBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    final done = email.controlState == ControlState.done;
    final color = done ? AppColors.successText(context) : theme.colorScheme.primary;
    final parts = _controlParts(email, l10n);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: bannerPadding,
      constraints: const BoxConstraints(minHeight: bannerMinHeight),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: Radii.chipAll,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(AppIcons.task_alt, size: Sizes.iconInline, color: color, fill: done ? 1 : 0),
        const SizedBox(width: Space.s),
        Expanded(
            child: Text(parts.join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: color))),
        BannerButton(
          onPressed: done ? () => _setControl(email, false) : () => unawaited(_controlMenu(email)),
          label: l10n.tr(done ? 'controlClear' : 'laterChange'),
        ),
      ]),
    );
  }

  static const _laterColor = Color(0xFF7B61B8);

  /// Текст плашки «Позже»: «Отложено до …» или «Без даты».
  String _laterText(EmailModel email, AppLocalizations l10n) {
    final at = email.remindAt?.toLocal();
    return at == null ? l10n.tr('laterNoDate') : l10n.tr('laterUntil').replaceAll('{when}', laterWhenLabel(at, l10n));
  }

  Widget _laterBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    const color = _laterColor;
    final text = _laterText(email, l10n);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: bannerPadding,
      constraints: const BoxConstraints(minHeight: bannerMinHeight),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: Radii.chipAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Icon(AppIcons.watch_later, size: Sizes.iconInline, color: color, fill: 1),
        const SizedBox(width: Space.s),
        Expanded(child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: color))),
        BannerButton(
          onPressed: () => unawaited(_later(context, email)),
          label: l10n.tr('laterChange'),
        ),
      ]),
    );
  }

  /// Отзыв доступен для отправленного письма, если транспорт аккаунта его
  /// поддерживает (нативно — EWS/Exchange; в EAS отзыва нет).
  bool _canRecall(WidgetRef ref, EmailModel email) {
    // Папка «Отправленные» определяется по типу: её id у сервера свой
    // (раньше сравнивалось с 'sent', и пункт не появлялся никогда).
    final folders = ref.read(foldersProvider).value ?? const <FolderModel>[];
    final isSent = email.folderId == 'sent' ||
        folders.any((f) => f.id == email.folderId && f.type == FolderType.sent);
    if (!isSent) return false;
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (acc == null) return false;
    return TransportCapabilities.forAccount(acc).recall;
  }

  Future<void> _confirmRecall(BuildContext context, WidgetRef ref, EmailModel email, AppLocalizations l10n) async {
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (acc == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('recallMessageQ')),
        content: Text(l10n.tr('recallAttemptDesc')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('recall'))),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final ok = await ref.read(mailEngineServiceProvider).recall(acc, email.id);
      if (ok) {
        showInlineNotice(l10n.tr('recallSent'));
      } else {
        quietError(l10n.tr('recallUnavailable'));
      }
    } catch (e) {
      showInlineError('${l10n.error}: $e');
    }
  }

  /// «Посмотреть позже»: меню срока. Отложенное письмо уходит с экрана —
  /// вернётся в срок непрочитанным, с уведомлением.
  Future<void> _later(BuildContext context, EmailModel email) async {
    final choice = await postponeEmails(context, ref, [email]);
    if (choice == null || !mounted) return;
    safeSetState(() => _email = _email!.copyWith(
          laterState: choice.clear ? LaterState.none : LaterState.waiting,
          remindAt: choice.clear ? null : choice.at,
          clearReminder: choice.clear || choice.at == null,
        ));
    if (!choice.clear) _closeAfterAction();
  }

  /// Редактор серверных категорий Outlook: как теги, но пишет и на сервер (EWS).
  Future<void> _editCategories(BuildContext context, AccountModel account, EmailModel email, AppLocalizations l10n) async {
    final selected = email.categories.toSet();
    final customController = TextEditingController();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(l10n.tr('outlookCategories')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tr('outlookCategoriesSynced'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in {...ref.read(categoriesProvider), ...selected})
                      FilterChip(
                        label: Text(c, style: Theme.of(context).textTheme.labelMedium),
                        selected: selected.contains(c),
                        onSelected: (v) => setSt(() => v ? selected.add(c) : selected.remove(c)),
                      ),
                  ],
                ),
                const SizedBox(height: Space.m),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: customController,
                        decoration: InputDecoration(isDense: true, hintText: l10n.tr('customCategory')),
                        onSubmitted: (v) {
                          final t = v.trim();
                          if (t.isNotEmpty) setSt(() { selected.add(t); customController.clear(); });
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.tr('add'),
                      icon: const Icon(AppIcons.add),
                      onPressed: () {
                        final t = customController.text.trim();
                        if (t.isNotEmpty) setSt(() { selected.add(t); customController.clear(); });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(selected), child: Text(l10n.save)),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final cats = result.toList();
    final ok = await ref.read(emailActionsProvider).setCategories(account, email.id, cats);
    safeSetState(() => _email = _email!.copyWith(categories: cats));
    await ref.read(emailsProvider.notifier).refresh();
    if (!mounted) return;
    // На сервер не ушло — сказать, что категории только на телефоне.
    if (ok) {
      AppLogger.info(l10n.tr('categoriesSavedSynced'));
    } else {
      showInlineNotice(l10n.tr('categoriesSavedLocal'));
    }
  }

  /// Редактор тегов письма (локально): переключаемые предустановленные + свой тег.
  Future<void> _editTags(BuildContext context, EmailModel email, AppLocalizations l10n) async {
    final selected = email.tags.toSet();
    final customController = TextEditingController();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(l10n.tr('emailTags')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in {...ref.read(categoriesProvider), ...selected})
                      FilterChip(
                        label: Text(tag, style: Theme.of(context).textTheme.labelMedium),
                        selected: selected.contains(tag),
                        onSelected: (v) => setSt(() => v ? selected.add(tag) : selected.remove(tag)),
                      ),
                  ],
                ),
                const SizedBox(height: Space.m),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: customController,
                        decoration: InputDecoration(isDense: true, hintText: l10n.tr('customTag')),
                        onSubmitted: (v) {
                          final t = v.trim();
                          if (t.isNotEmpty) setSt(() { selected.add(t); customController.clear(); });
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.tr('add'),
                      icon: const Icon(AppIcons.add),
                      onPressed: () {
                        final t = customController.text.trim();
                        if (t.isNotEmpty) setSt(() { selected.add(t); customController.clear(); });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(selected), child: Text(l10n.save)),
          ],
        ),
      ),
    );
    if (result == null) return;
    final tags = result.toList();
    await ref.read(emailActionsProvider).setTags(email.id, tags, accountId: email.accountId);
    safeSetState(() => _email = _email!.copyWith(tags: tags));
    await ref.read(emailsProvider.notifier).refresh();
  }

  /// Флаг «К исполнению»: сервер, список писем и этот экран — сразу.
  void _toggleFlag(EmailModel email) {
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (acc == null) return;
    final flagged = !email.isFlagged;
    HapticFeedback.selectionClick();
    ref.read(emailActionsProvider).setFlag(acc, email.id, email.folderId, flagged);
    ref.read(emailsProvider.notifier).applyLocalFlags(email.id, isFlagged: flagged);
    safeSetState(() => _email = email.copyWith(isFlagged: flagged));
  }

  /// Кнопка «Ещё» письма (1.8.8) — круглая, как в карточке по удержанию.
  PeekAction _peekAction(IconData icon, String label, VoidCallback onTap, {bool fill = false}) => PeekAction(
        icon: icon,
        label: label,
        filled: fill,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      );

  // ════════════════════════ ДЕЙСТВИЯ ════════════════════════

  /// Важность письма: в приложении — всегда; на сервере — для ящиков EWS
  /// (у ActiveSync и IMAP важность полученного письма не меняется).
  Future<void> _pickImportance(EmailModel email, AppLocalizations l10n) async {
    // Карточкой (1.8.8), как меню «⋮»; текущая — с галочкой.
    final picked = await showChoiceSheet<EmailPriority>(
      context,
      title: l10n.tr('importance'),
      selected: email.priority,
      entries: [
        for (final (p, icon, key) in const [
          (EmailPriority.high, AppIcons.priority_high, 'importanceHigh'),
          (EmailPriority.normal, AppIcons.remove, 'importanceNormal'),
          (EmailPriority.low, AppIcons.arrow_downward, 'importanceLow'),
        ])
          AppMenuEntry(value: p, label: l10n.tr(key), icon: icon),
      ],
    );
    if (picked == null || picked == email.priority) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.emails)
          ..where((e) => e.id.equals(email.id) & e.accountId.equals(email.accountId)))
        .write(EmailsCompanion(priority: Value(picked.index)));
    safeSetState(() => _email = _email!.copyWith(priority: picked));
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account != null && account.usesEws) {
      try {
        await ref.read(ewsServiceProvider).setImportance(account,
            emailId: email.id,
            importance: switch (picked) {
              EmailPriority.high => 'High',
              EmailPriority.low => 'Low',
              EmailPriority.normal => 'Normal',
            });
      } catch (e) {
        AppLogger.warning('Важность на сервере: $e');
      }
    }
  }

  void _deleteEmail(EmailModel email, AppLocalizations l10n) {
    // Всё из ref — до показа отмены: действие выполняется через несколько
    // секунд, когда карточка уже закрыта (или в split-view выбрано другое
    // письмо), и ref к этому моменту недействителен («Using ref when a widget
    // is unmounted»), письмо не удалялось.
    final notifier = ref.read(emailsProvider.notifier);
    final actions = ref.read(emailActionsProvider);
    // Аккаунт мог быть удалён, пока экран открыт.
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    notifier.hideLocally(email);
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('emailDeleted'),
        onUndo: () => notifier.unhideLocally(email),
        onSettled: () => notifier.unhideLocally(email),
        // Через единый слой действий: EAS→движок, EWS→ews_service, IMAP→imap.
        execute: () => actions.delete(account, email.id, email.folderId),
        undo: () async {
          // Восстановление из Корзины во Входящие (best-effort: id мог смениться).
          try {
            await actions.moveTo(account, email.id, 'trash', 'inbox');
          } catch (_) {/* синхронизация вернёт актуальное состояние */}
        },
      ),
    );
    _closeAfterAction();
  }

  void _closeAfterAction() {
    if (widget.embedded) return; // в split-view закрывать нечего
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Напоминание «нет ответа»: если на письмо не ответят к выбранному сроку,
  /// придёт уведомление. Проверка идёт при синхронизации и стоит один запрос
  /// по индексу — постоянного фонового опроса нет.
  /// Экспорт письма в PDF и системный диалог «Поделиться» (сохранить в файлы,
  /// отправить в мессенджер и т.д.). Генерация идёт в сервисе; здесь только UI.
  Future<void> _exportPdf(EmailModel email, AppLocalizations l10n) async {
    // Политика организации (MDM, 1.10.5): PDF и печать — данные из
    // приложения; запрещено — сразу, без подготовки файла.
    if (ManagedPolicy.deny(ManagedRule.share)) return;

    // Если письмо в цепочке — спрашиваем, что сохранять. Для делопроизводства
    // обычно нужна вся переписка по вопросу, но иногда достаточно одного
    // письма, поэтому решает пользователь.
    var exportWholeThread = false;
    final convId = email.conversationId;
    if (convId != null && convId.isNotEmpty) {
      try {
        final thread = await ref.read(conversationProvider((conversationId: convId, accountId: email.accountId)).future);
        if (thread.length > 1 && mounted) {
          final choice = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(AppIcons.picture_as_pdf),
              title: Text(l10n.tr('saveAsPdf')),
              content: Text(l10n.tr('exportScopeQuestion')
                  .replaceAll('{n}', '${thread.length}')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'one'),
                  child: Text(l10n.tr('exportThisMessage')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'thread'),
                  child: Text(l10n.tr('exportWholeThread')),
                ),
              ],
            ),
          );
          if (choice == null) return;
          exportWholeThread = choice == 'thread';
        }
      } catch (e) {
        AppLogger.warning('Не удалось получить цепочку для экспорта: $e');
      }
    }

    quietNotice(l10n.tr('preparingPdf'));
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    final labelsMap = {
      'from': l10n.tr('from'),
      'to': l10n.tr('to'),
      'cc': l10n.tr('cc'),
      'date': l10n.tr('date'),
      'account': l10n.tr('account'),
      'attachments': l10n.tr('attachments'),
      'noSubject': l10n.tr('noSubject'),
      'messages': l10n.tr('messagesLabel'),
    };

    if (exportWholeThread) {
      final thread = await ref.read(conversationProvider((conversationId: email.conversationId!, accountId: email.accountId)).future);
      final p = await EmailPdfService.exportThread(thread,
          labels: labelsMap, accountName: email.accountId);
      if (!mounted) return;
      if (p == null) {
        showInlineError(l10n.tr('pdfExportFailed'));
        return;
      }
      await appShare(ShareParams(files: [XFile(p)], subject: email.subject));
      return;
    }

    final path = await EmailPdfService.exportEmail(
      email,
      accountName: account?.email,
      labels: labelsMap,
    );
    if (!mounted) return;
    if (path == null) {
      showInlineError(l10n.tr('pdfExportFailed'));
      return;
    }
    await appShare(ShareParams(files: [XFile(path)], subject: email.subject));
  }

  Future<void> _forwardAsEml(EmailModel email) async {
    try {
      // Вложения ДОКАЧИВАЕМ: раньше .eml собирался только из тела, и файлы
      // терялись — получатель видел «письмо во вложении» без самих вложений.
      // Берём из кэша, если письмо открывали; иначе один раз качаем.
      // Аккаунт мог быть удалён, пока экран открыт: firstWhere без orElse
      // бросал бы StateError и ронял пересылку.
      final account =
          ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
      if (account == null) return;
      final atts = <EmlAttachment>[];
      for (final a in email.attachments) {
        try {
          final path = await _fetchToCache(a, account);
          if (path != null) {
            atts.add((name: a.name, mimeType: a.mimeType, path: path));
          }
        } catch (_) {}
      }

      // Тело — исходное, а не подготовленное к показу: в показанном картинки
      // и счётчики заменены заглушками (12.11.2026: в пересланном .eml
      // рассылки остались только две картинки из двадцати).
      final raw = _rawBodyHtml;
      final source = raw != null && raw.isNotEmpty && email.id == _email?.id ? email.copyWith(bodyHtml: raw) : email;
      final eml = await buildEmlFromEmail(source, attachments: atts);
      // Отдельная папка: копии писем (с вложениями) не копятся во временных
      // файлах — всё старше суток удаляется при следующей пересылке.
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/eml_out');
      await dir.create(recursive: true);
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final f in dir.list()) {
        try {
          if (f is File && (await f.lastModified()).isBefore(cutoff)) await f.delete();
        } catch (_) {}
      }
      final file = File('${dir.path}/${emlFileName(email)}');
      await file.writeAsString(eml);
      if (!mounted) return;
      unawaited(context.push(
          '/compose?accountId=${Uri.encodeQueryComponent(email.accountId)}&attachments=${Uri.encodeComponent(file.path)}'));
    } catch (e) {
      if (mounted) {
        quietError('$e');
      }
    }
  }

  /// Скачать вложение и вернуть путь (без открытия предпросмотра).
  /// Общая часть для группового скачивания.
  Future<String?> _fetchToCache(EmailAttachment att, AccountModel account) async {
    // Организация запретила вложения на устройстве (MDM block_attachment_download).
    if (ManagedPolicy.deny(ManagedRule.attachments)) return null;
    final cache = ref.read(attachmentCacheProvider);
    final key = MailEngineService.attachmentCacheKey(account.id, widget.emailId, att.id);
    final cached = await cache.get(key);
    if (cached != null) return cached; // уже есть — сеть не трогаем

    final bytes = await ref
        .read(mailEngineServiceProvider)
        .getAttachmentBytes(account, att.id, emailId: widget.emailId);
    return cache.put(key, att.name, bytes);
  }

  /// Скачать все вложения письма. Последовательно — параллельные запросы к
  /// одному ящику всё равно выстроятся в очередь (см. мьютекс в imap_service),
  /// а так виден прогресс и не рвётся соединение.
  Future<void> _downloadAll(EmailModel email) async {
    final l10n = AppLocalizations.of(context);
    // Аккаунт мог быть удалён, пока экран открыт: firstWhere без orElse
    // бросал бы StateError и ронял операцию.
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null) return;

    setState(() => _busyAll = true);
    var done = 0, failed = 0;
    for (final att in email.attachments) {
      try {
        final path = await _fetchToCache(att, account);
        if (path != null) {
          done++;
          if (mounted) {
            setState(() => _attachmentStates[att.id] = _AttachmentState(localPath: path));
          }
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _busyAll = false);
    if (failed == 0) {
      showInlineNotice(l10n.tr('downloadedN').replaceAll('{done}', '$done'));
    } else {
      quietError(l10n.tr('downloadedNFailed').replaceAll('{done}', '$done').replaceAll('{failed}', '$failed'));
    }
  }

  /// Сохранить все вложения: сначала докачиваем недостающие, затем отдаём
  /// системному листу «Поделиться» — он умеет «Сохранить в Файлы»/«Загрузки».
  Future<void> _saveAll(EmailModel email) async {
    // Аккаунт мог быть удалён, пока экран открыт: firstWhere без orElse
    // бросал бы StateError и ронял операцию.
    final l10n = AppLocalizations.of(context);
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null) return;

    setState(() => _busyAll = true);
    final items = <({String path, String name})>[];
    for (final att in email.attachments) {
      try {
        final path = await _fetchToCache(att, account);
        if (path == null) continue;
        // winmail.dat — контейнер Outlook: сохраняем/делимся тем, что ВНУТРИ,
        // а не нечитаемым контейнером (тот же декодер, что и в предпросмотре).
        final unpacked = await _unpackWinmail(path, att);
        if (unpacked != null && unpacked.isNotEmpty) {
          for (final it in unpacked) {
            items.add((path: it.filePath, name: it.fileName));
          }
        } else {
          items.add((path: path, name: att.name));
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _busyAll = false);

    if (items.isEmpty) {
      showInlineError(l10n.tr('attachDownloadFailed'));
      return;
    }
    // Android и компьютер — сразу в «Загрузки» (1.6.33); iPhone — лист
    // «Поделиться» («Сохранить в Файлы»).
    if (DownloadSaver.supported) {
      await DownloadSaver.saveWithFeedback(context, items);
      return;
    }
    final files = [
      for (final it in items) XFile(await FileOpener.namedCopy(it.path, it.name), name: it.name),
    ];
    await appShare(ShareParams(files: files, subject: email.subject));
  }

  /// winmail.dat (TNEF) — контейнер Outlook: настоящие файлы лежат ВНУТРИ.
  ///
  /// Декодер `TnefDecoder` был написан (сигнатура, эвристика имени/типа, разбор),
  /// но не вызывался — пользователь видел нечитаемый `winmail.dat` вместо
  /// вложений. Классическая жалоба на почту от Outlook.
  ///
  /// Возвращает вкладки с распакованными файлами либо null, если это не TNEF.
  Future<List<PreviewItem>?> _unpackWinmail(String path, EmailAttachment att) async {
    if (!TnefDecoder.looksLikeWinmail(att.name, att.mimeType)) return null;
    try {
      final bytes = await File(path).readAsBytes();
      if (!TnefDecoder.isTnef(bytes)) return null; // имя обмануло — не TNEF

      final inner = TnefDecoder.decode(bytes);
      if (inner.isEmpty) return null; // не распарсилось — покажем как есть

      // Кладём распакованное в кэш: тот же файл из другого письма не будет
      // распаковываться заново (адресация по MD5 содержимого).
      final cache = ref.read(attachmentCacheProvider);
      final items = <PreviewItem>[];
      for (var i = 0; i < inner.length; i++) {
        final f = inner[i];
        if (f.data == null || f.data!.isEmpty) continue;
        final name = f.filename.isEmpty ? 'attachment_${i + 1}' : f.filename;
        final p = await cache.put(
            MailEngineService.attachmentCacheKey(widget.accountId, widget.emailId, '${att.id}#tnef$i'), name, f.data!);
        items.add(PreviewItem(filePath: p, fileName: name, sizeBytes: f.size));
      }
      if (items.isEmpty) return null;
      AppLogger.info('TNEF: распаковано вложений — ${items.length}');
      return items;
    } catch (e) {
      AppLogger.warning('TNEF: распаковать не удалось — $e');
      return null; // покажем winmail.dat как обычный файл
    }
  }

  /// Открыть вложение (1.5.10): во внешнем приложении; в почте — только
  /// вложенные письма и S/MIME (см. openAttachment). Раньше — экран
  /// предпросмотра со всеми вложениями вкладками.
  Future<void> _openPreview(String path, EmailAttachment att) async {
    if (!mounted) return;

    // winmail.dat — то, что внутри, а не контейнер: один файл — сразу,
    // несколько — выбор.
    final unpacked = await _unpackWinmail(path, att);
    if (unpacked != null) {
      if (!mounted) return;
      var pick = unpacked.first;
      if (unpacked.length > 1) {
        final i = await showActionSheet<int>(
          context,
          title: att.name,
          items: [
            for (var k = 0; k < unpacked.length; k++)
              ActionSheetItem(icon: AppIcons.attach_file, label: unpacked[k].fileName, value: k),
          ],
        );
        if (i == null || !mounted) return;
        pick = unpacked[i];
      }
      await openAttachment(context, pick,
          emailSubject: _email?.subject,
          accountId: widget.accountId,
          emailFrom: _email?.from.label,
          emailDate: _email?.receivedAt);
      return;
    }
    if (!mounted) return;
    await openAttachment(
      context,
      PreviewItem(filePath: path, fileName: att.name, sizeBytes: att.size, mimeType: att.mimeType),
      emailSubject: _email?.subject,
      accountId: widget.accountId,
      emailFrom: _email?.from.label,
      emailDate: _email?.receivedAt,
    );
  }

  /// Переместить письмо в папку «Спам» (Junk).
  /// Папка ищется по типу среди папок аккаунта: её идентификатор у разных
  /// серверов различается (EWS `junkemail`, IMAP «Спам»/«Junk»/«Bulk Mail»),
  /// поэтому хардкодить ID нельзя.
  /// Тип папки письма (для «Не спам» и «Восстановить»), запоминается на письмо.
  String? _folderTypeFor;
  Future<FolderType?>? _folderType;

  Future<FolderType?> _folderTypeOf(EmailModel email) {
    final key = '${email.accountId}|${email.folderId}';
    if (_folderTypeFor != key || _folderType == null) {
      _folderTypeFor = key;
      final db = ref.read(databaseProvider);
      _folderType = (db.select(db.folders)
            ..where((f) => f.id.equals(email.folderId) & f.accountId.equals(email.accountId)))
          .getSingleOrNull()
          .then((r) => r == null ? null : FolderType.values.elementAtOrNull(r.type));
    }
    return _folderType!;
  }

  /// Тип папки письма, когда он прочитан из базы ([_folderTypeOf]): по нему
  /// чип «Спам» / «Корзина» строки сведений (1.12.x). Пока не прочитан — null.
  String? _folderTypeReadFor;
  FolderType? _folderTypeRead;

  FolderType? _folderTypeNow(EmailModel email) {
    final key = '${email.accountId}|${email.folderId}';
    if (_folderTypeReadFor != key) {
      _folderTypeReadFor = key;
      _folderTypeRead = null;
      _folderTypeOf(email).then((t) {
        if (_folderTypeReadFor == key && t != _folderTypeRead) safeSetState(() => _folderTypeRead = t);
      }, onError: (Object e) => AppLogger.debug('Папка письма: $e'));
    }
    return _folderTypeRead;
  }

  /// Письмо попало в спам или корзину по ошибке — вернуть во «Входящие».
  /// Плашка раскрывается из чипа «Спам» / «Корзина» (1.12.x).
  Widget _restoreBanner(EmailModel email, bool junk, ThemeData theme, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: bannerPadding,
      constraints: const BoxConstraints(minHeight: bannerMinHeight),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: Radii.cardAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(junk ? AppIcons.report : AppIcons.delete, size: Sizes.iconRow, color: AppColors.mutedText(context)),
        const SizedBox(width: Space.s),
        Expanded(child: Text(l10n.tr(junk ? 'inJunkFolder' : 'inTrashFolder'), style: theme.textTheme.bodyMedium)),
        BannerButton(
          onPressed: () => unawaited(_restoreToInbox(email, l10n)),
          label: l10n.tr(junk ? 'notSpam' : 'restoreToInbox'),
        ),
      ]),
    );
  }

  Future<void> _restoreToInbox(EmailModel email, AppLocalizations l10n) async {
    final inboxId = await ref.read(databaseProvider).folderIdOfType(email.accountId, FolderType.inbox.index);
    if (!mounted) return;
    if (inboxId == null) {
      showInlineError(l10n.tr('inboxFolderNotFound'));
      return;
    }
    final actions = ref.read(emailActionsProvider);
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('restoredToInbox'),
        execute: () => actions.moveTo(account, email.id, email.folderId, inboxId),
        undo: () async {},
      ),
    );
    _closeAfterAction();
  }

  /// Ctrl+Q / Ctrl+U (как в Outlook): прочитано или не прочитано.
  void _setReadKey(EmailModel email, bool read) {
    if (email.isRead == read) return;
    final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (acc == null) return;
    unawaited(ref.read(emailActionsProvider).setRead(acc, email.id, email.folderId, read));
    ref.read(emailsProvider.notifier).applyLocalFlags(email.id, isRead: read);
    safeSetState(() => _email = email.copyWith(isRead: read));
  }

  /// Заблокировать (или разблокировать) отправителя письма (1.10.x).
  Future<void> _blockSender(EmailModel email) async {
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    final wasBlocked = isSenderBlocked(ref, email.from.email, email.accountId);
    final msg = await blockSender(context, ref, account: account, email: email);
    if (!mounted || msg == null) return;
    showSenderActionResult(context, msg);
    // Письмо заблокированного отправителя уже в «Спаме» — закрыть его.
    if (!wasBlocked) _closeAfterAction();
  }

  /// «Чистка» по отправителю письма (1.10.x).
  Future<void> _sweepSender(EmailModel email) async {
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    final msg = await sweepSender(context, ref, account: account, email: email);
    if (!mounted || msg == null) return;
    showSenderActionResult(context, msg);
  }

  Future<void> _moveToJunk(EmailModel email, AppLocalizations l10n) async {
    // По типу, с распознаванием «Нежелательной почты» по названию
    // (SpecialFolders, 1.7.2+106); нет папки — строкой с подсказкой.
    final junkId = await SpecialFolders.resolve(
        ref.read(databaseProvider), ref.read(sharedPrefsProvider), email.accountId, SpecialKind.junk);
    if (!mounted) return;
    if (junkId == null) {
      showInlineError(l10n.tr('junkFolderNotFound'));
      return;
    }
    if (junkId == email.folderId) return;
    final actions = ref.read(emailActionsProvider);
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('movedToJunk'),
        execute: () => actions.moveTo(account, email.id, email.folderId, junkId),
        undo: () async {},
      ),
    );
    _closeAfterAction();
  }

  Future<void> _archiveEmail(EmailModel email, AppLocalizations l10n) async {
    // Папка «Архив» аккаунта письма по типу. Раньше подставлялся
    // 'archivemsgfolderroot' — это корень ОНЛАЙН-АРХИВА Exchange (отдельный
    // ящик, которого у большинства нет), у IMAP и EAS такого id нет вовсе.
    // «Архив» Exchange приходит обычной папкой — SpecialFolders (1.7.2+106).
    final archiveId = await SpecialFolders.resolve(
        ref.read(databaseProvider), ref.read(sharedPrefsProvider), email.accountId, SpecialKind.archive);
    if (!mounted) return;
    if (archiveId == null) {
      showInlineError(l10n.tr('archiveFolderNotFound'));
      return;
    }
    if (archiveId == email.folderId) return;
    final notifier = ref.read(emailsProvider.notifier);
    final actions = ref.read(emailActionsProvider);
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    notifier.hideLocally(email);
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('emailMoved'),
        execute: () => actions.moveTo(account, email.id, email.folderId, archiveId),
        undo: () async {},
        onUndo: () => notifier.unhideLocally(email),
        onSettled: () => notifier.unhideLocally(email),
      ),
    );
    _closeAfterAction();
  }

  /// Письмо — в архив Ogneliss (1.7.3): целиком, с вложениями, в папку с
  /// тем же путём. Исходное — в «Удалённые» на сервере, если так настроено
  /// (тогда экран закрывается сразу, письмо скрыто в ленте; не удалось —
  /// возвращается в ленту и строка ошибки).
  Future<void> _toOgnaArchive(EmailModel email, AppLocalizations l10n) async {
    if (!await ensureArchiveReady(context, ref) || !mounted) return;
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    final db = ref.read(databaseProvider);
    final row = await (db.select(db.emails)..where((e) => e.id.equals(email.id) & e.accountId.equals(email.accountId)))
        .getSingleOrNull();
    if (row == null || !mounted) return;
    final runner = ref.read(archiveRunnerProvider.notifier);
    final notifier = ref.read(emailsProvider.notifier);
    final deleting = ref.read(archiveSettingsProvider).deleteFromServer;
    if (deleting) {
      notifier.hideLocally(email);
      _closeAfterAction();
    }
    final r = await runner.archiveEmails(account, [row]);
    if (deleting) notifier.unhideLocally(email);
    if (r.archived == 0) showInlineError(l10n.tr('archiveOneFailed'));
  }

  /// Письмо — в отдельное окно (компьютер): окно получает письмо готовым —
  /// очищенный текст, картинки в тексте, адресаты, вложения (message_window.dart).
  Future<void> _openInWindow(EmailModel email) async {
    final html = (email.bodyHtml ?? '').trim().isNotEmpty
        ? email.bodyHtml!
        : '<div>${const HtmlEscape().convert(email.bodyPlain ?? email.bodyPreview ?? '').replaceAll('\n', '<br>')}</div>';
    MessageWindowPerson p(EmailAddress a) => (name: a.displayName ?? '', email: a.email);
    try {
      await MessageWindow.open(MessageWindowPayload(
        accountId: email.accountId,
        emailId: email.id,
        folderId: email.folderId,
        subject: email.subject,
        from: p(email.from),
        to: [for (final a in email.to) p(a)],
        cc: [for (final a in email.cc) p(a)],
        date: email.receivedAt,
        html: html,
        images: _inlineImages,
        attachments: [
          for (final a in email.attachments)
            if (!a.isInline) (id: a.id, name: a.name, size: a.size),
        ],
        dark: Theme.of(context).brightness == Brightness.dark,
        locale: Localizations.localeOf(context).languageCode,
      ));
    } catch (e) {
      AppLogger.warning('Окно письма не открылось: $e');
      if (mounted) quietError('${AppLocalizations.of(context).tr('error')}: $e');
    }
  }

  /// Задача по письму (как свайп «Создать задачу» в списке).
  /// Задача из письма — карточка задачи с названием из темы, сроком из темы
  /// («обновить до 17:00 10.10.2026» → 10.10, 17:00) и ссылкой на письмо.
  /// Раньше задача молча создавалась только в телефоне, а сообщение
  /// «Задача создана» было скрыто — казалось, что кнопка не работает.
  Future<void> _createTask(EmailModel email, AppLocalizations l10n) => showTaskEditorForEmail(context, email);

  /// Вложение smime.p7m (зашифрованное или «непрозрачно» подписанное письмо).
  EmailAttachment? _smimeP7m(EmailModel email) => email.attachments
      .where((a) => a.name.toLowerCase().endsWith('.p7m') || a.mimeType.toLowerCase().contains('pkcs7-mime'))
      .firstOrNull;

  /// Подпись обычного подписанного письма (multipart/signed): вложение
  /// smime.p7s. В списке вложений не показывается — вместо него строка
  /// проверки подписи.
  static bool _isSmimeSignature(EmailAttachment a) =>
      a.name.toLowerCase().endsWith('.p7s') || a.mimeType.toLowerCase().contains('pkcs7-signature');
  EmailAttachment? _smimeP7s(EmailModel email) => email.attachments.where(_isSmimeSignature).firstOrNull;

  /// Проверка подписи: письмо целиком (исходный MIME) с сервера — подпись
  /// считается по исходным байтам. Результат на время открытия письма.
  String? _sigFor;
  bool _sigChecking = false;
  CmsSignature? _sig;
  String? _sigError;

  Future<void> _verifySignature(EmailModel email) async {
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null) return;
    safeSetState(() {
      _sigFor = email.id;
      _sigChecking = true;
      _sigError = null;
    });
    try {
      final raw = await ref
          .read(mailEngineServiceProvider)
          .fetchRawMime(account, folderId: email.folderId, emailId: email.id);
      if (raw == null) throw StateError('no MIME');
      final r = await ref.read(smimeServiceProvider).open(widget.accountId, raw);
      if (!mounted || _sigFor != email.id) return;
      safeSetState(() {
        _sig = r.signature;
        _sigError = r.signature == null ? (r.error ?? 'format') : null;
        _sigChecking = false;
      });
    } catch (e) {
      AppLogger.debug('Проверка подписи S/MIME: $e');
      if (!mounted || _sigFor != email.id) return;
      safeSetState(() {
        _sigChecking = false;
        _sigError = 'network';
      });
    }
  }

  /// Подпись S/MIME — значок, цвет, текст плашки и надпись чипа строки
  /// сведений (1.12.x). Проверка — один раз на письмо, после первого кадра
  /// (письмо уже видно): её запускает чип, плашка раскрывается по нажатию.
  ({IconData icon, Color color, String title, String sub, String chip, MailNoticeTone tone, bool busy})
      _sigView(EmailModel email, AppLocalizations l10n) {
    if (_sigFor != email.id && !_sigChecking) {
      _sigFor = email.id;
      _sig = null;
      _sigError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_verifySignature(email));
      });
    }
    final s = _sig;
    final ok = s != null && s.valid;
    final IconData icon;
    final Color color;
    final String title;
    final String sub;
    var chip = l10n.tr('noticeSigOk');
    var tone = MailNoticeTone.neutral;
    var busy = false;
    if (_sigChecking || (s == null && _sigError == null)) {
      icon = AppIcons.verified_user;
      color = AppColors.mutedText(context);
      title = l10n.tr('smimeSignedMail');
      sub = l10n.tr('smimeSigChecking');
      chip = sub;
      busy = true;
    } else if (s == null) {
      icon = AppIcons.verified_user;
      color = AppColors.mutedText(context);
      title = l10n.tr('smimeSignedMail');
      sub = _sigError == 'network' ? l10n.tr('smimeSigFailed') : l10n.tr('smimeSigUnknown').replaceAll('{reason}', _sigError ?? '');
      chip = l10n.tr('noticeSigUnchecked');
    } else {
      final name = s.signer?.commonName ?? s.signer?.emails.firstOrNull ?? '';
      icon = ok ? AppIcons.verified_user : AppIcons.warning;
      color = ok ? AppColors.successText(context) : AppColors.warningText(context);
      title = name.isEmpty ? l10n.tr('smimeSignedMail') : l10n.tr('smimeSignedBy').replaceAll('{name}', name);
      final signerMail = s.signer?.emails ?? const <String>[];
      final notSelf = ok && signerMail.isNotEmpty &&
          !signerMail.any((m) => m.toLowerCase() == email.from.email.toLowerCase());
      sub = !ok
          ? l10n.tr('smimeSigBad')
          : notSelf
              ? l10n.tr('smimeSigNotSelf').replaceAll('{email}', signerMail.join(', '))
              : l10n.tr('smimeSigOk');
      // Подпись не сходится — цветом ошибки; подписал другой адрес — с
      // предупреждающим значком.
      chip = l10n.tr(!ok ? 'noticeSigBad' : (notSelf ? 'noticeSigOther' : 'noticeSigOk'));
      if (!ok) tone = MailNoticeTone.warning;
    }
    return (icon: icon, color: color, title: title, sub: sub, chip: chip, tone: tone, busy: busy);
  }

  Widget _smimeSignatureBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    final v = _sigView(email, l10n);
    final icon = v.icon, color = v.color, title = v.title, sub = v.sub;
    final retry = !_sigChecking && _sig == null && _sigError == 'network';
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Radii.cardAll,
      ),
      child: Row(children: [
        Icon(icon, size: Sizes.iconRow, color: color),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.bodyMedium),
            Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
          ]),
        ),
        if (_sigChecking)
          const Padding(
            padding: EdgeInsets.all(Space.m),
            child: SizedBox.square(dimension: Sizes.iconInline, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (retry)
          TextButton(onPressed: () => unawaited(_verifySignature(email)), child: Text(l10n.tr('smimeVerify'))),
      ]),
    );
  }

  Widget _smimeEncryptedBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    final att = _smimeP7m(email)!;
    final busy = _attachmentStates[att.id]?.isDownloading ?? false;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Radii.cardAll,
      ),
      child: Row(children: [
        Icon(AppIcons.lock, size: Sizes.iconRow, color: theme.colorScheme.primary),
        const SizedBox(width: Space.s),
        Expanded(child: Text(l10n.tr('smimeEncryptedMail'), style: theme.textTheme.bodyMedium)),
        busy
            ? const Padding(
                padding: EdgeInsets.all(Space.m),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : TextButton(onPressed: () => _onAttachmentTap(att, l10n), child: Text(l10n.tr('smimeOpen'))),
      ]),
    );
  }

  /// Встреча по письму: тема, участники и текст — из письма (редактор
  /// встречи). Время — выбирает пользователь: подсказки дат из текста
  /// («Быстро запланировать») убраны в 1.5.6.
  void _planMeeting(EmailModel email) {
    unawaited(context.push('/create-event', extra: {'email': email}));
  }

  /// Свойства письма: адреса, дата, размер, идентификатор, проверка подлинности.
  void _showMessageDetails(EmailModel email, AppLocalizations l10n) {
    String list(List<EmailAddress> a) => a.map((x) => x.displayName != null && x.displayName!.isNotEmpty
        ? '${x.displayName} <${x.email}>'
        : x.email).join(', ');
    final rows = <(String, String)>[
      (l10n.tr('from'), email.from.displayName != null && email.from.displayName!.isNotEmpty
          ? '${email.from.displayName} <${email.from.email}>'
          : email.from.email),
      if (email.to.isNotEmpty) (l10n.tr('to'), list(email.to)),
      if (email.cc.isNotEmpty) (l10n.tr('cc'), list(email.cc)),
      (l10n.tr('date'), DateFormat('d MMMM yyyy, HH:mm:ss', l10n.localeCode)
          .format(email.receivedAt.toLocal())),
      if ((email.size ?? 0) > 0) (l10n.tr('size'), '${((email.size ?? 0) / 1024).toStringAsFixed(1)} KB'),
      if ((email.internetMessageId ?? '').isNotEmpty) ('Message-ID', email.internetMessageId!),
      if ((email.authResults ?? '').isNotEmpty) ('Authentication-Results', email.authResults!),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('messageDetails')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText.rich(TextSpan(children: [
              for (final r in rows) ...[
                TextSpan(text: '${r.$1}\n', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: '${r.$2}\n\n'),
              ],
            ])),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('close')))],
      ),
    );
  }

  /// До трёх маленьких аватарок адресатов внахлёст (кому, затем копия).
  void _showRecipients(BuildContext context, EmailModel email, AppLocalizations l10n) {
    // Получатели — с фото из контактов (10.10.2026), разделы — полосой-
    // заголовком в стиле бокового меню.
    Widget person(EmailAddress r) => ListTile(
          leading: HeroEmailAvatar(
            emailId: 'rcpt_${email.id}_${r.email}',
            hero: false,
            radius: 18,
            email: r.email,
            initial: r.label.isEmpty ? '?' : initialOf(r.label),
            color: HeroEmailAvatar.colorForEmail(r.email),
          ),
          title: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: r.label == r.email ? null : Text(r.email, maxLines: 1, overflow: TextOverflow.ellipsis),
          dense: true,
          trailing: const Icon(AppIcons.chevron_right),
          onTap: () => showPersonCard(context, email: r.email, name: r.displayName, accountId: email.accountId),
        );
    showAppSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Space.l),
        children: [
          SectionBand(title: l10n.tr('to'), count: email.to.length > 1 ? email.to.length : null),
          ...email.to.map(person),
          if (email.cc.isNotEmpty) ...[
            SectionBand(title: l10n.tr('cc'), count: email.cc.length > 1 ? email.cc.length : null),
            ...email.cc.map(person),
          ],
        ],
      ),
    );
  }

  // ════════════════════════ УТИЛИТЫ ════════════════════════


}

class _AttachmentState {
  final bool isDownloading;
  final String? localPath;
  final String? error;

  const _AttachmentState({this.isDownloading = false, this.localPath, this.error});
}

/// Индикатор, который появляется, только если ждать дольше полсекунды:
/// подготовка письма из памяти телефона занимает доли секунды, и мигание
/// индикатора выглядело как «догрузка».
class _DelayedSpinner extends StatefulWidget {
  const _DelayedSpinner();

  @override
  State<_DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<_DelayedSpinner> {
  bool _show = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: _show ? const CircularProgressIndicator(strokeWidth: 2) : null,
      );
}

/// Команда панели над письмом (широкий экран, 1.10.5).
class _Cmd {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final Color? color;
  const _Cmd(this.icon, this.label, this.onTap, {this.onLongPress, this.selected = false, this.color});
}
