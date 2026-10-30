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
import '../../../widgets/common/peek_card.dart' show PeekAction, PeekGroup;
import '../widgets/mail_peek_card.dart' show showMailPeek;
import '../widgets/unsubscribe_banner.dart';
import '../widgets/booking_card.dart';
import '../widgets/control_sheet.dart';
import '../../../services/mail/unsubscribe_service.dart' show encodeListUnsubscribe;
import '../../tasks/widgets/task_editor_sheet.dart' show showTaskEditorForEmail;
import '../../../core/utils/text_safe.dart';
import '../../../core/utils/symbol_fonts.dart';
import '../../../core/navigation/app_router.dart' show pushMailDetail;
import '../../../core/theme/app_icons.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../services/mail/transport_capabilities.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
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
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
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
import '../../settings/screens/device_rule_screen.dart' show openDeviceRule;
import '../../../services/mail/own_addresses.dart';
import '../../../services/security/mail_classification.dart';
import '../../../services/security/smime_service.dart' show smimeServiceProvider, CmsSignature;
import '../../settings/providers/categories_provider.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../features/settings/providers/feature_flags_provider.dart';
import '../../settings/widgets/feature_settings_sections.dart' show ExperimentalKeys;
import '../widgets/linkified_text.dart';
import '../widgets/mail_native_body.dart';
import '../widgets/mail_header.dart';
import '../widgets/conversation_thread_view.dart';
import '../widgets/quick_reply_bar.dart';
import '../providers/drawer_prefs.dart'
    show quickReplyBarProvider, mailBarOrderProvider, MailBarAction, confirmMailDeleteProvider;
import '../../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../widgets/mail_html_view.dart';
import '../../../widgets/common/readable_width.dart';
import '../widgets/read_receipt_banner.dart';
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
import 'package:flutter_html_table/flutter_html_table.dart';
import 'package:html/dom.dart' as dom;
import '../../../core/security/link_opener.dart';
import 'attachment_preview_screen.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../services/mail/tnef/tnef_decoder.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../compose/providers/templates_provider.dart' show templatesProvider;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/app_menu_button.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../core/theme/ogneliss_look.dart';

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

  const MailDetailScreen({
    super.key,
    required this.emailId,
    required this.accountId,
    this.embedded = false,
    this.pagerLabel,
    this.onPrev,
    this.onNext,
    this.active = true,
  });

  @override
  ConsumerState<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends ConsumerState<MailDetailScreen>
    with SafeAsyncState<MailDetailScreen> {
  EmailModel? _email;
  bool _isLoading = true;
  bool _isLoadingBody = false;
  bool _readReceiptHandled = false;
  bool _showQuote = false;
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
        _isLoading = true;
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
              cache.peekPrepared(rawHtml, options: o.options, allowImages: o.allowImages) != null;
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
        if (sameBody && _email != null && (sensChanged || luChanged || authChanged)) {
          final sens = email.sensitivity;
          final lu = email.listUnsubscribe;
          final ar = email.authResults;
          safeSetState(() => _email = _email!.copyWith(
                sensitivity: sensChanged ? sens : null,
                listUnsubscribe: luChanged ? lu : null,
                authResults: authChanged ? ar : null,
              ));
        }

        if (!sameBody) {
          safeSetState(() {
            _email = sanitizedEmail;
            _isLoading = false;

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

        // Шапка письма — сразу, тело — когда будет готово: раньше до конца
        // подготовки (а без текста в базе — до ответа сервера) на экране был
        // только индикатор загрузки.
        final o = cache.optionsFor(email);
        final ready = hasBody &&
            (email.bodyHtml ?? '').isNotEmpty &&
            cache.peekPrepared(email.bodyHtml!, options: o.options, allowImages: o.allowImages) != null;
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
          _startInlineImages(email);
        }

        final sanitized = await _secureBody(email);
        if (!mounted) return;
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
      final account = ref.read(activeAccountProvider);
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

      if (!mounted || rows.length <= 1) return;
      // ref после await — только пока экран открыт.
      // Конвертируем через публичный метод
      final notifier = ref.read(emailsProvider.notifier);
      final emails = rows.map((r) => notifier.rowToModel(r)).toList();

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
    final p = await cache.prepare(e.bodyHtml!, options: opts, allowImages: allowImages);
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
  String? _whyMarkedFor;

  /// Простое письмо — виджетами (MailNativeBody); null — показывать в WebView
  /// (письмо сложное, выключено в «Возможностях», цитата ещё не отделена).
  /// Кнопка «Как в браузере» убрана в 1.5.10 — показ виджетами точнее.
  Widget? _nativeBody(EmailModel email, String html, ThemeData theme, AppLocalizations l10n, AppSettings settings) {
    if (!(ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.nativeMail) ?? true)) return null;
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
          unawaited(MailBodyProcessor.heavy(full ? html : split.reply, _imagesAllowed ? buildNativeMailRemote : buildNativeMail).then(
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
    final n = _natives[mode];
    if (n == null) {
      // В замер открытия — почему письмо в браузере (1.5.10).
      final why = _prepared?.nativeWhy;
      if (why != null && _whyMarkedFor != email.id) {
        _whyMarkedFor = email.id;
        OpenTrace.mark('в браузере: $why');
      }
      return null;
    }
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
          textScale: settings.fontScale,
          onShown: () {
            OpenTrace.mark('без WebView');
            OpenTrace.done();
            _onBodyShown();
          },
          onLink: (url, text) => LinkOpener.open(context, url, linkText: text, accountId: widget.accountId),
        ),
        if (split.hasQuote) _quoteToggle(theme, l10n),
      ],
    );
  }

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
    final byRequest = _hasCid && _inlineByRequest;
    final key = '${baseKey}_${byRequest ? 'req' : _inlineImages.length}';
    var doc = _webDocs[key];
    if (doc == null) {
      final base = _baseDocs[baseKey];
      if (base != null) {
        // Картинки — строкой в готовый документ (без разбора HTML).
        doc = _webDocs[key] = _hasCid && !byRequest ? base.withInlineImages(_inlineImages) : base;
      } else {
        // Ключ сборки — с «поколением»: сборка для прежнего тела не
        // блокирует новую с тем же ключом.
        final gen = _docGen;
        final buildKey = '$gen|$baseKey';
        if (_docBuilding.add(buildKey)) {
          unawaited(MailHtmlDocument.buildAsync(
            full ? html : split.reply,
            allowRemoteImages: _imagesAllowed,
            keepCid: true,
          ).catchError((Object e) {
            AppLogger.warning('Подготовка письма к показу: $e');
            return const MailHtmlDocument('<!DOCTYPE html><html><body></body></html>', {});
          }).then((d) {
            _docBuilding.remove(buildKey);
            if (gen != _docGen) return;
            safeSetState(() => _baseDocs[baseKey] = d);
          }));
        }
        return _bodyPreparing();
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Во всю ширину и без скругления: письмо — часть страницы, а не
        // карточка на ней.
        MailHtmlView(
          // Без числа встроенных картинок: пришедшие картинки загружаются в
          // то же окно (MailHtmlView.didUpdateWidget), а не пересоздают
          // WebView (1.5.9).
          key: ValueKey('${email.id}_${baseKey}_${theme.brightness.name}'),
          document: doc,
          active: widget.active,
          allowRemoteImages: _imagesAllowed,
          textScale: settings.fontScale,
          pageColor: mailPageColor(theme),
          dark: theme.brightness == Brightness.dark,
          onShown: _onBodyShown,
          inlineRaw: byRequest ? _inlineRaw : null,
          onLink: (url, text) =>
              LinkOpener.open(context, url, linkText: text, accountId: widget.accountId),
        ),
        if (split.hasQuote) _quoteToggle(theme, l10n),
      ],
    );
  }

  /// Кнопка «Показать / скрыть переписку».
  Widget _quoteToggle(ThemeData theme, AppLocalizations l10n) => Align(
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
                  _showQuote ? l10n.tr('hideQuoted') : l10n.tr('showQuoted'),
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            context.push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}'),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true): () =>
            context.push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}&replyAll=true'),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              context.push('/compose?forwardFromId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}'),
        const SingleActivator(LogicalKeyboardKey.delete): () => _deleteEmail(email, l10n),
        if (!widget.embedded)
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
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
        // письма в беседе).
        titleSpacing: widget.embedded ? null : 0,
        title: MailSenderTitle(email: email, hero: !widget.embedded, pagerLabel: widget.pagerLabel),
        backgroundColor: mailPageColor(theme),
        actions: [
          // Флаг «К исполнению» — на виду: в меню «…» его не находили.
          IconButton(
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
                child: Text(
                  email.subject.isEmpty ? l10n.tr('noSubject') : email.subject,
                  // В закреплённой шапке длинная тема не занимает пол-экрана.
                  maxLines: pinHeader ? 3 : null,
                  overflow: pinHeader ? TextOverflow.ellipsis : null,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
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
        final bodyChildren = <Widget>[
            // ── Антифишинг: баннер безопасности отправителя (сверху письма) ──
            if (settled)
              Builder(builder: (_) {
                final matches = ref.read(accountsProvider).where((a) => a.id == email.accountId);
                if (matches.isEmpty) return const SizedBox.shrink();
                return SenderSafetyBanner(account: matches.first, email: email);
              }),

            // ── Приглашение на встречу ──
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

            // ── Спам / Корзина: «Не спам», «Восстановить» ──
            if (settled) _restoreBanner(email, theme, l10n),

            // ── S/MIME: зашифрованное письмо — тело в smime.p7m ──
            if (settled && _smimeP7m(email) != null) _smimeEncryptedBanner(email, theme, l10n),
            // ── S/MIME: обычное подписанное письмо (подпись — smime.p7s) ──
            if (settled && _smimeP7m(email) == null && _smimeP7s(email) != null)
              _smimeSignatureBanner(email, theme, l10n),

            // ── «На контроле» ──
            if (email.controlState != 0 && ref.watch(settingsProvider).mailControl)
              _controlBanner(email, theme, l10n),

            // ── «Позже»: отложено до … (письмо открыто из списка «Позже») ──
            if (email.laterState == LaterState.waiting) _laterBanner(email, theme, l10n),

            // ── Рассылка: «Отписаться» (по заголовку List-Unsubscribe) ──
            if (email.listUnsubscribe != null)
              Builder(builder: (context) {
                final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
                return acc == null ? const SizedBox.shrink() : UnsubscribeBanner(account: acc, email: email);
              }),

            // ── Баннер высокой важности ──
            if (email.isHighPriority)
              Container(
                margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.priority_high, size: 16, color: AppColors.errorRed),
                    const SizedBox(width: 6),
                    Text(l10n.tr('highImportanceLabel'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.errorText(context))),
                  ],
                ),
              ),

            // ── Теги и категории Outlook ──
            // Одна строка чипов и только когда есть что показать: пустые
            // строки «Без тегов» / «Без категорий» занимали треть экрана
            // (замечание 05.10). Добавить — «Ещё» в нижней панели; нажатие на
            // чип открывает тот же выбор.
            Builder(builder: (_) {
              final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
              final showCats = account != null && account.isMsExchange && email.categories.isNotEmpty;
              if (email.tags.isEmpty && !showCats) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                child: Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: [
                    for (final tag in email.tags)
                      ActionChip(
                        label: Text(tag, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.getTagColor(tag))),
                        backgroundColor: AppTheme.getTagColor(tag).withValues(alpha: 0.1),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        tooltip: l10n.tr('editTags'),
                        onPressed: () => _editTags(context, email, l10n),
                      ),
                    if (showCats)
                      for (final c in email.categories)
                        ActionChip(
                          avatar: Icon(AppIcons.label, size: 14, color: AppColors.accentOrangeText(context)),
                          label: Text(c, style: Theme.of(context).textTheme.labelMedium),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          tooltip: l10n.tr('outlookCategories'),
                          onPressed: () => _editCategories(context, account, email, l10n),
                        ),
                  ],
                ),
              );
            }),
            if (email.readReceiptRequested && !_readReceiptHandled)
              ReadReceiptBanner(
                senderName: email.from.label,
                onSend: () {
                  _sendReadReceipt(email);
                  setState(() => _readReceiptHandled = true);
                },
                onDismiss: () => setState(() => _readReceiptHandled = true),
              ),


            // ── Внешние изображения скрыты ──
            // Одна строка: что скрыто, «Показать» и меню с остальным
            // («Всегда от этого домена», «Что заблокировано» — там же
            // подробности). Раньше плашка в три строки с тремя кнопками
            // занимала пол-экрана (замечание 09.10.2026).
            if (!_isLoadingBody && !_imagesAllowed && (_externalImagesBlocked > 0 || _blockedItems.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.only(left: Space.m),
                      child: Row(
                        children: [
                          Icon(AppIcons.image_not_supported, size: 18,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Text(
                              _externalImagesBlocked > 0
                                  ? l10n.tr('imagesBlockedShort')
                                  : l10n.tr('trackersBlockedN').replaceAll(
                                      '{n}', '${_blockedItems.where((i) => i.reason != BlockReason.external).length}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          if (_externalImagesBlocked > 0)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: _allowImages,
                              child: Text(l10n.tr('showImages')),
                            ),
                          AppMenuButton<String>(
                            tooltip: l10n.tr('more'),
                            icon: Icon(AppIcons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
                            onSelected: (v) {
                              if (v == 'always') _allowImages(always: true);
                              if (v == 'what') _showBlocked(l10n);
                            },
                            itemBuilder: (_) => [
                              if (_externalImagesBlocked > 0)
                                AppMenuEntry(value: 'always', icon: AppIcons.image, label: l10n.tr('alwaysFromSender')),
                              AppMenuEntry(value: 'what', icon: AppIcons.info, label: l10n.tr('whatWasBlocked')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

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
                child: email.bodyHtml != null && email.bodyHtml!.isNotEmpty && mailWebViewSupported
                    ? _buildWebBody(email, theme, l10n, settings)
                    : email.bodyHtml != null && email.bodyHtml!.isNotEmpty
                    ? Builder(builder: (context) {
                        // Разбор цитаты — один раз на тело письма, а не на
                        // каждую перерисовку (прокрутка, открытие панелей).
                        if (!identical(_splitSource, email.bodyHtml)) {
                          _splitSource = email.bodyHtml;
                          _split = splitQuotedHtml(email.bodyHtml!);
                        }
                        final split = _split!;
                        Map<String, Style> htmlStyle() => {
                              'body': Style(fontSize: FontSize(15), lineHeight: const LineHeight(1.5)),
                              'a': Style(color: AppColors.linkBlue),
                            };
                        if (!split.hasQuote) {
                          return SelectionArea(child: Html(data: email.bodyHtml!, extensions: const [TableHtmlExtension()], style: htmlStyle(), onLinkTap: (url, _, el) => _onLinkTap(url, el)));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Свежий ответ — показываем сразу.
                            SelectionArea(child: Html(data: split.reply, extensions: const [TableHtmlExtension()], style: htmlStyle(), onLinkTap: (url, _, el) => _onLinkTap(url, el))),
                            // Переключатель «показать/скрыть» процитированную переписку.
                            _quoteToggle(theme, l10n),
                            if (_showQuote)
                              Opacity(
                                opacity: 0.75,
                                child: SelectionArea(child: Html(data: split.quoted, extensions: const [TableHtmlExtension()], style: htmlStyle(), onLinkTap: (url, _, el) => _onLinkTap(url, el))),
                              ),
                          ],
                        );
                      })
                    : LinkifiedText(
                        SymbolFonts.fixPlain(email.bodyPlain ?? email.bodyPreview ?? ''),
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                        onLink: (url, text) => LinkOpener.open(context, url, linkText: text, accountId: widget.accountId),
                      ),
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
                  pushMailDetail(GoRouter.of(context), e.id, accountId: e.accountId);
                },
              ),
            ],

            const SizedBox(height: 100), // Отступ для bottom bar
        ];
        if (!pinHeader) {
          return SingleChildScrollView(
            child: ReadableWidth(
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: headerChildren),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: ReadableWidth(
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
        child: _buildBottomBar(context, theme, l10n, email, settings),
      ),
    ),
      ),
    );
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
    return Semantics(
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
          onLongPress: () => _onAttachmentLongPress(att, l10n),
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
    );
  }

  Future<void> _onAttachmentTap(EmailAttachment att, AppLocalizations l10n) async {
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

      if (mounted) showInlineError('${l10n.tr('error')}: $e');
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
    await SharePlus.instance.share(ShareParams(files: [XFile(await FileOpener.namedCopy(path, att.name), name: att.name)]));
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
        child: ListenableBuilder(
          listenable: _quickReply,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _barButtons(email, settings, l10n, order: order, draft: draft),
          ),
        ),
      ),
    );
    if (!quick) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: mailPageColor(theme),
          child: QuickReplyBar(
            key: ValueKey('qr_${email.accountId}_${email.id}'),
            email: email,
            controller: _quickReply,
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
    context.push(Uri(path: '/compose', queryParameters: {
      'forwardFromId': email.id,
      'accountId': email.accountId,
      if (text.isNotEmpty) 'quick': text,
    }).toString());
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
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
    return Semantics(
      label: tooltip,
      button: true,
      child: onLongPress == null
          ? button
          : GestureDetector(
              onLongPress: () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
              child: button,
            ),
    );
  }

  /// Быстрые ответы: короткие рабочие формулировки и шаблоны пользователя.
  /// Выбранный текст подставляется в ответ между приветствием и подписью —
  /// остаётся проверить и нажать «Отправить».
  void _showQuickReplies(EmailModel email, AppLocalizations l10n) {
    final templates = [for (final t in ref.read(templatesProvider)) t.resolve(l10n.tr)];
    const builtIn = ['quickReply1', 'quickReply2', 'quickReply3', 'quickReply4', 'quickReply5'];
    void open(String text, {bool all = false}) {
      Navigator.of(context, rootNavigator: true).pop();
      context.push(Uri(path: '/compose', queryParameters: {
        'replyToId': email.id,
        'accountId': email.accountId,
        if (all) 'replyAll': 'true',
        'quick': text,
      }).toString());
    }

    showAppSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l10n.tr('quickReplies'), style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(l10n.tr('quickRepliesHint')),
            ),
            for (final k in builtIn)
              ListTile(
                leading: const Icon(AppIcons.quickreply),
                title: Text(l10n.tr(k)),
                onTap: () => open(l10n.tr(k)),
                onLongPress: () => open(l10n.tr(k), all: true),
              ),
            for (final t in templates)
              ListTile(
                leading: const Icon(AppIcons.description),
                title: Text(t.title.isEmpty ? t.body : t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: t.title.isEmpty
                    ? null
                    : Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => open(t.body),
                onLongPress: () => open(t.body, all: true),
              ),
            ListTile(
              leading: const Icon(AppIcons.edit_note),
              title: Text(l10n.tr('quickRepliesManage')),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/settings/templates');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════ ПОЛНЫЙ BOTTOM SHEET ════════════════════════

  void _showFullActionsSheet(
    BuildContext context, AppLocalizations l10n, EmailModel email, AppSettings settings,
  ) {
    // Действия сгруппированы по смыслу (раньше — сплошная сетка из 20+
    // значков, где «Экспорт», «Сохранить PDF» и «Печать» делали одно и то же).
    final isExchange = ref.read(accountsProvider).any((a) => a.id == email.accountId && a.isMsExchange);
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
        ]),
        PeekGroup(title: l10n.tr('actionsCreate'), items: [
          // Встреча по письму: тема, участники и текст — из письма.
          _peekAction(AppIcons.event, l10n.tr('createEvent'), () => _planMeeting(email)),
          _peekAction(AppIcons.check_box, l10n.tr('createTask'), () => _createTask(email, l10n)),
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
          _peekAction(AppIcons.share, l10n.tr('share'), () => SharePlus.instance.share(
              ShareParams(text: '${email.subject}\n\n${email.bodyPlain ?? email.bodyPreview ?? ""}'))),
        ]),
        PeekGroup(title: l10n.tr('actionsMore'), items: [
          _peekAction(AppIcons.info, l10n.tr('messageDetails'),
              () => _showMessageDetails(email, l10n)),
          // «Найти документ»: все файлы этого отправителя из всех писем.
          if (email.from.email.contains('@') && ref.read(featureFlagsProvider).showFileHub)
            _peekAction(AppIcons.attach_file, l10n.tr('senderFiles'), () => unawaited(
                context.push('/attachment-hub?from=${Uri.encodeQueryComponent(email.from.email)}'))),
          _peekAction(AppIcons.sync, l10n.tr('redownload'), _loadEmailDetail),
          // Отзыв письма (нативно — Exchange ActiveSync 16.1).
          if (_canRecall(ref, email))
            _peekAction(AppIcons.undo, l10n.tr('recallMessage'),
                () => _confirmRecall(context, ref, email, l10n)),
        ]),
      ],
    ));
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

  Widget _controlBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    final done = email.controlState == ControlState.done;
    final color = done ? AppColors.successText(context) : theme.colorScheme.primary;
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

  Widget _laterBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    const color = Color(0xFF7B61B8);
    final at = email.remindAt?.toLocal();
    final text = at == null ? l10n.tr('laterNoDate') : l10n.tr('laterUntil').replaceAll('{when}', laterWhenLabel(at, l10n));
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
        showInlineError(l10n.tr('recallUnavailable'));
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

    showInlineNotice(l10n.tr('preparingPdf'));
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
      await SharePlus.instance.share(ShareParams(files: [XFile(p)], subject: email.subject));
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
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], subject: email.subject));
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

      final eml = await buildEmlFromEmail(email, attachments: atts);
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
        showInlineError('$e');
      }
    }
  }

  /// Скачать вложение и вернуть путь (без открытия предпросмотра).
  /// Общая часть для группового скачивания.
  Future<String?> _fetchToCache(EmailAttachment att, AccountModel account) async {
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
      showInlineError(l10n.tr('downloadedNFailed').replaceAll('{done}', '$done').replaceAll('{failed}', '$failed'));
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
    await SharePlus.instance.share(ShareParams(files: files, subject: email.subject));
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

  /// Письмо попало в спам или корзину по ошибке — вернуть во «Входящие».
  Widget _restoreBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    return FutureBuilder<FolderType?>(
      future: _folderTypeOf(email),
      builder: (context, snap) {
        final t = snap.data;
        if (t != FolderType.junk && t != FolderType.trash) return const SizedBox.shrink();
        final junk = t == FolderType.junk;
        return Container(
          margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
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
      },
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

  Widget _smimeSignatureBanner(EmailModel email, ThemeData theme, AppLocalizations l10n) {
    // Проверка — один раз на письмо, после первого кадра (письмо уже видно).
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
    if (_sigChecking || (s == null && _sigError == null)) {
      icon = AppIcons.verified_user;
      color = AppColors.mutedText(context);
      title = l10n.tr('smimeSignedMail');
      sub = l10n.tr('smimeSigChecking');
    } else if (s == null) {
      icon = AppIcons.verified_user;
      color = AppColors.mutedText(context);
      title = l10n.tr('smimeSignedMail');
      sub = _sigError == 'network' ? l10n.tr('smimeSigFailed') : l10n.tr('smimeSigUnknown').replaceAll('{reason}', _sigError ?? '');
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
    }
    final retry = !_sigChecking && s == null && _sigError == 'network';
    return Container(
      margin: const EdgeInsets.only(left: Space.l, right: Space.l, bottom: Space.s),
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
      margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
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
