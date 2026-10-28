// lib/l10n/app_localizations.dart
// Локализация приложения Ogneliss Mail. Строки — файлами
// assets/l10n/<код>.xml (1.7.3, strings_store.dart), список языков —
// languages.g.dart (создаётся tool/l10n/l10n.py gen).

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'languages.g.dart';
import 'strings_store.dart';

export 'strings_store.dart' show AppLanguage;

/// Локализация приложения Ogneliss Mail
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)
        ?? AppLocalizations(const Locale('ru'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// Языки интерфейса — те, для которых есть файл assets/l10n/<код>.xml.
  static final List<Locale> supportedLocales = [for (final l in kAppLanguages) Locale(l.code)];

  static final Set<String> supportedCodes = {for (final l in kAppLanguages) l.code};

  /// Язык по коду (null — такого языка в приложении нет).
  static AppLanguage? languageOf(String code) => kAppLanguages.where((l) => l.code == code).firstOrNull;

  /// Строки языка [code] (и английские — подмена недостающих) загружены,
  /// даты на этом языке — тоже. Для фоновой работы и уведомлений, где нет
  /// дерева виджетов: `final l10n = await AppLocalizations.load(lang);`.
  static Future<AppLocalizations> load(String code) {
    final lang = supportedCodes.contains(code) ? code : 'en';
    // Уже загружено (запуск приложения, тесты) — сразу, без пустого кадра.
    if (StringsStore.isLoaded(lang) && StringsStore.isLoaded('en') && _dates.contains(lang)) {
      return SynchronousFuture(AppLocalizations(Locale(lang)));
    }
    return _load(lang);
  }

  static final Set<String> _dates = {};

  static Future<AppLocalizations> _load(String lang) async {
    await Future.wait([StringsStore.ensure(lang), StringsStore.ensure('en')]);
    try {
      await initializeDateFormatting(lang);
    } catch (_) {
      // Нет данных дат для языка — даты по-английски (localeCode).
    }
    _dates.add(lang);
    return AppLocalizations(Locale(lang));
  }

  bool get isRussian => locale.languageCode == 'ru';

  /// Код локали для intl (DateFormat / NumberFormat): язык приложения,
  /// иначе английский. Данные дат загружает [load].
  String get localeCode {
    final lang = locale.languageCode;
    return supportedCodes.contains(lang) ? lang : 'en';
  }

  /// Строка с числом и правильной формой множественного числа (<plurals>
  /// в файле языка; форма — по правилам CLDR языка). `{n}` заменяется
  /// числом.
  String plural(String key, int n) {
    final lang = locale.languageCode;
    final own = StringsStore.plurals(lang, key);
    final String form;
    if (own != null) {
      form = StringsStore.pick(lang, own, n);
    } else {
      final en = StringsStore.plurals('en', key);
      form = en != null ? StringsStore.pick('en', en, n) : tr(key);
    }
    return form.replaceAll('{n}', '$n');
  }

  /// Строка для текущего языка. Нет в языке — английская, нет и её —
  /// русская, иначе сам ключ.
  String tr(String key) {
    final lang = locale.languageCode;
    return StringsStore.get(lang, key) ??
        StringsStore.get('en', key) ??
        StringsStore.get('ru', key) ??
        key;
  }

  // ── Navigation ───────────────────────────────────────────────────────────
  String get inbox => tr('inbox');
  String get allMail => tr('allMailLbl');
  String get mail => tr('mail');
  String get compose => tr('compose');
  String get search => tr('searchLbl');
  String get dashboardLabel => tr('dashboardLabel');
  String get calendarLabel => tr('calendarLabel');
  String get contactsLabel => tr('contactsLabel');
  String get tasksLabel => tr('tasksLabel');
  String get settingsLabel => tr('settingsLabel');

  // ── Actions ──────────────────────────────────────────────────────────────
  String get save => tr('saveLbl');
  String get cancel => tr('cancelLbl');
  String get delete => tr('deleteLbl');
  String get reply => tr('replyLbl');
  String get replyAll => tr('replyAllLbl');
  String get forward => tr('forwardLbl');
  String get send => tr('sendLbl');
  String get archive => tr('archiveLbl');
  String get markRead => tr('markReadLbl');
  String get markUnread => tr('markUnreadLbl');
  String get moveToFolder => tr('moveToFolder');
  String get flag => tr('flagLbl');
  String get unflag => tr('unflag');
  String get dismiss => tr('dismiss');
  String get join => tr('join');
  String get confirm => tr('confirm');
  String get close => tr('closeLbl');
  String get refresh => tr('refreshLbl');
  String get retry => tr('retryLbl');
  String get edit => tr('editLbl');
  String get add => tr('addLbl');
  String get create => tr('create');
  String get done => tr('done');
  String get yes => tr('yes');
  String get no => tr('no');
  String get ok => tr('ok');
  String get loading => tr('loading');
  String get error => tr('errorLbl');
  String get success => tr('success');
  String get warning => tr('warning');
  String get noResults => tr('noResults');
  String get noEmails => tr('noEmailsLbl');
  String get noEvents => tr('noEventsLbl');
  String get noTasks => tr('noTasksLbl');
  String get noContacts => tr('noContactsLbl');

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get login => tr('loginLbl');
  String get logout => tr('logout');
  String get password => tr('passwordLbl');
  String get username => tr('usernameLbl');
  String get domain => tr('domainLbl');
  String get server => tr('serverLbl');
  String get connecting => tr('connectingLbl');
  String get authFailed => tr('authFailed');
  String get enterCredentials => tr('enterCredentials');

  // ── Mail compose ─────────────────────────────────────────────────────────
  String get to => tr('toLbl');
  String get cc => tr('ccLbl');
  String get bcc => tr('bccLbl');
  String get subject => tr('subjectLbl');
  String get body => tr('body');
  String get attachments => tr('attachmentsLbl');
  String get addAttachment => tr('addAttachment');
  String get discardDraft => tr('discardDraftLbl');
  String get saveDraft => tr('saveDraftLbl');
  String get sending => tr('sendingLbl');
  String get sent => tr('sentLbl');
  String get drafts => tr('draftsLbl');
  String get spam => tr('spam');
  String get trash => tr('trashLbl');
  String get starred => tr('starred');
  String get important => tr('important');

  // ── Calendar ─────────────────────────────────────────────────────────────
  String get newEvent => tr('newEvent');
  String get eventTitle => tr('eventTitle');
  String get startDate => tr('startDate');
  String get endDate => tr('endDate');
  String get allDay => tr('allDayLbl');
  String get location => tr('locationLbl');
  String get reminder => tr('reminderLbl');
  String get recurrence => tr('recurrence');
  String get attendees => tr('attendees');
  String get meetingReminder => tr('meetingReminder');
  String get joinMeeting => tr('joinMeeting');
  String get today => tr('todayLbl');
  String get tomorrow => tr('tomorrowLbl');

  // ── Contacts ─────────────────────────────────────────────────────────────
  String get newContact => tr('newContactLbl');
  String get firstName => tr('firstName');
  String get lastName => tr('lastName');
  String get email => tr('emailLbl');
  String get phone => tr('phoneLbl');
  String get company => tr('companyLbl');
  String get position => tr('position');

  // ── Tasks ────────────────────────────────────────────────────────────────
  String get newTask => tr('newTask');
  String get taskTitle => tr('taskTitle');
  String get dueDate => tr('dueDate');
  String get priority => tr('priorityLbl');
  String get completed => tr('completedLbl');
  String get pending => tr('pending');

  // ── Settings ─────────────────────────────────────────────────────────────
  String get accounts => tr('accountsLbl');
  String get notifications => tr('notificationsLbl');
  String get theme => tr('themeLbl');
  String get language => tr('languageLbl');
  String get security => tr('securityLbl');
  String get accessibility => tr('accessibilityLbl');
  String get about => tr('aboutLbl');
  String get syncSettings => tr('syncSettings');
  String get signatureLabel => tr('signatureLabel');
  String get autoReply => tr('autoReply');
  String get rules => tr('rulesLbl');
  String get addRule => tr('addRule');
  String get darkMode => tr('darkMode');
  String get fontSize => tr('fontSizeLbl');

  // ── AI / Smart ───────────────────────────────────────────────────────────
  String get aiAnalysis => tr('aiAnalysisLbl');
  String get smartCompose => tr('smartCompose');
  String get summary => tr('summary');
  String get category => tr('categoryLbl');
  String get tags => tr('tags');

  // ── Notifications ────────────────────────────────────────────────────────
  String get newEmailNotif => tr('newEmailNotif');
  String get permissionRequired => tr('permissionRequired');

  // ── Misc ─────────────────────────────────────────────────────────────────
  String get syncInProgress => tr('syncInProgress');
  String get lastSynced => tr('lastSynced');
  String get offline => tr('offlineLbl');
  String get pinCode => tr('pinCode');
  String get enterPin => tr('enterPinLbl');
  String get wrongPin => tr('wrongPinLbl');
  String get scanDocument => tr('scanDocumentLbl');
  String get ocrResult => tr('ocrResult');
  String get noAccount => tr('noAccount');
  String get addAccount => tr('addAccountLbl');
  String get connectionError => tr('connectionError');
  String get unknownError => tr('unknownError');
  String get recallMessage => tr('recallMessageLbl');
  String get unsubscribe => tr('unsubscribeLbl');
  String get printEmail => tr('printEmail');
  String get shareEmail => tr('shareEmail');
  String get reportSpam => tr('reportSpam');
  String get selectAll => tr('selectAllLbl');
  String get deselectAll => tr('deselectAll');
  String get noInternet => tr('noInternet');
  String get voiceInput => tr('voiceInput');
  String get listening => tr('listening');
  String get attachFile => tr('attachFileLbl');
  String get openFile => tr('openFile');
  String get downloadFile => tr('downloadFile');
  String get fileSize => tr('fileSize');
  String get from => tr('fromLbl');
  String get date => tr('dateLbl');
  String get time => tr('time');
  String get size => tr('sizeLbl');
  String get name => tr('nameLbl');
  String get type => tr('type');
  String get description => tr('descriptionLbl');
  String get notes => tr('notesLbl');

  // ── Поручения (Assignments) ────────────────────────────────────────────
  String get assignmentsNavLabel => tr('assignmentsNavLabel');
  String get assignmentCreateFromEmail => tr('assignmentCreateFromEmail');
  String get assignmentNewTitle => tr('assignmentNewTitle');
  String get assignmentTitleField => tr('assignmentTitleField');
  String get assignmentParticipants => tr('assignmentParticipants');
  String get assignmentAddParticipant => tr('assignmentAddParticipant');
  String get assignmentNoParticipants => tr('assignmentNoParticipants');
  String get assignmentRole => tr('assignmentRole');
  String get assignmentRoleOwner => tr('assignmentRoleOwner');
  String get assignmentRoleResponsible => tr('assignmentRoleResponsible');
  String get assignmentRoleParticipant => tr('assignmentRoleParticipant');
  String get assignmentRoleObserver => tr('assignmentRoleObserver');
  String get assignmentKind => tr('assignmentKind');
  String get assignmentKindOnce => tr('assignmentKindOnce');
  String get assignmentKindPermanent => tr('assignmentKindPermanent');
  String get assignmentKindCyclic => tr('assignmentKindCyclic');
  String get assignmentFreqLabel => tr('assignmentFreqLabel');
  String get assignmentFreqDaily => tr('assignmentFreqDaily');
  String get assignmentFreqWeekly => tr('assignmentFreqWeekly');
  String get assignmentFreqMonthly => tr('assignmentFreqMonthly');
  String get assignmentFreqYearly => tr('assignmentFreqYearly');
  String get assignmentFreqEvery => tr('assignmentFreqEvery');
  String get assignmentAutoDecide => tr('assignmentAutoDecide');
  String get assignmentStatusDraft => tr('assignmentStatusDraft');
  String get assignmentStatusOpen => tr('assignmentStatusOpen');
  String get assignmentStatusInProgress => tr('assignmentStatusInProgress');
  String get assignmentStatusReview => tr('assignmentStatusReview');
  String get assignmentStatusDone => tr('assignmentStatusDone');
  String get assignmentStatusClosed => tr('assignmentStatusClosed');
  String get assignmentStatusCancelled => tr('assignmentStatusCancelled');
  String get assignmentFeed => tr('assignmentFeed');
  String get assignmentFeedEmpty => tr('assignmentFeedEmpty');
  String get assignmentAddProposal => tr('assignmentAddProposal');
  String get assignmentProposalHint => tr('assignmentProposalHint');
  String get assignmentSupport => tr('assignmentSupport');
  String get assignmentReject => tr('assignmentReject');
  String get assignmentAbstain => tr('assignmentAbstain');
  String get assignmentDecisionAccepted => tr('assignmentDecisionAccepted');
  String get assignmentDecisionRejected => tr('assignmentDecisionRejected');
  String get assignmentDecideOwner => tr('assignmentDecideOwner');
  String get assignmentByMajority => tr('assignmentByMajority');
  String get assignmentByOwner => tr('assignmentByOwner');
  String get assignmentChangeStatus => tr('assignmentChangeStatus');
  String get assignmentMyAssignments => tr('assignmentMyAssignments');
  String get assignmentAsResponsible => tr('assignmentAsResponsible');
  String get assignmentOverdue => tr('assignmentOverdue');
  String get assignmentEmptyList => tr('assignmentEmptyList');
  String get assignmentDueDateLabel => tr('assignmentDueDateLabel');
  String get assignmentNoDueDate => tr('assignmentNoDueDate');
  String get assignmentCreated => tr('assignmentCreatedLbl');
  String get assignmentScheduleMeeting => tr('assignmentScheduleMeeting');
  String get assignmentMeetingType => tr('assignmentMeetingType');
  String get assignmentMeetingSelector => tr('assignmentMeetingSelector');
  String get assignmentMeetingMeeting => tr('assignmentMeetingMeeting');
  String get assignmentMeetingStandup => tr('assignmentMeetingStandup');
  String get assignmentMeetingCall => tr('assignmentMeetingCall');
  String get assignmentMeetingWhen => tr('assignmentMeetingWhen');
  String get assignmentMeetingDialIn => tr('assignmentMeetingDialIn');
  String get assignmentMeetingLink => tr('assignmentMeetingLink');
  String get assignmentMeetingCreated => tr('assignmentMeetingCreated');
  String get assignmentCompileReport => tr('assignmentCompileReport');
  String get assignmentReportReady => tr('assignmentReportReady');
  String get assignmentOpenReport => tr('assignmentOpenReport');
  String get assignmentSigInvalid => tr('assignmentSigInvalid');
  String get assignmentSigUnsigned => tr('assignmentSigUnsigned');

  // ── Вычистка хардкода: общие UI-строки ────────────────────────────────
  String get copied => tr('copied');
  String get enterEmail => tr('enterEmail');
  String get selectEmailPrompt => tr('selectEmailPrompt');
  String get readReceiptSent => tr('readReceiptSent');
  String get emptyTrashTitle => tr('emptyTrashTitle');
  String get emptyTrashBody => tr('emptyTrashBody');
  String get emptyAction => tr('emptyAction');
  String get certValidation => tr('certValidation');
  String get pinTrustStore => tr('pinTrustStore');
  String get pinStrict => tr('pinStrict');
  String get pinAcceptAll => tr('pinAcceptAll');
  String get taskDeadline => tr('taskDeadline');
  String get taskCreatedPrefix => tr('taskCreatedPrefix');
  String get createMeetingAction => tr('createMeetingAction');
  String get forwardForInfo => tr('forwardForInfo');
  String get quickReplyTitle => tr('quickReplyTitle');
  String get trackingCopied => tr('trackingCopied');
  String get codeCopied => tr('codeCopied');
  // ── Антифишинг / безопасность отправителя ─────────────────────────────
  String get safetyExternalSender => tr('safetyExternalSender');
  String get safetyFirstContact => tr('safetyFirstContact');
  String get safetyDisplayNameSpoof => tr('safetyDisplayNameSpoof');
  String get safetyLookalikeDomain => tr('safetyLookalikeDomain');
  String get safetyDangerousAttach => tr('safetyDangerousAttach');
  String get safetyLinkMismatch => tr('safetyLinkMismatch');
  String get safetyBannerCaution => tr('safetyBannerCaution');
  String get safetyBannerDanger => tr('safetyBannerDanger');
  String get safetyReportPhishing => tr('safetyReportPhishing');
  String get safetyAuthFail => tr('safetyAuthFail');
  String get actionToCalendar => tr('actionToCalendar');
  String get actionCopy => tr('actionCopy');
  String get actionCopyCode => tr('actionCopyCode');
  String get actionUnsubscribe => tr('actionUnsubscribe');

}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedCodes.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
