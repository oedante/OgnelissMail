// lib/features/auth/screens/login_screen.dart
// Экран входа (1.8.0, п. 6 плана — «вход удобнее: адрес почты первым,
// почта узнаётся по адресу»). Два шага:
//  1. Адрес. Человек вводит только адрес и нажимает «Далее»; способ входа
//     приложение выбирает само (MailProviderDetect): Google, Microsoft и
//     Яндекс — страница входа службы с уже подставленным адресом
//     (login_hint), Mail.ru и iCloud — пароль приложения, известные службы —
//     IMAP с готовыми серверами, рабочая почта — Exchange (сервер находит
//     автообнаружение).
//  2. Вход выбранным способом: пароль (и «Расширенные настройки» — логин,
//     домен, сервер или серверы IMAP/SMTP) либо кнопка входа через службу.
//     «Другой способ входа» — выбор вручную. Ошибка — строкой на экране с
//     кнопкой: «Проверить пароль», «Создать пароль приложения», «Открыть
//     настройки почты», «Повторить».
// «Войти снова» (`/login?reauth=<id>`) — сразу шаг 2, заполненный данными
// ящика: адрес не меняется, способ не выбирается.
//
// 1.8.8 (замечание владельца 29.10.2026: «адрес на ogneliss.ru — сразу
// Exchange; раньше можно было просто нажать Google или Яндекс»): под полем
// адреса — плитки способов входа. Google, Яндекс и Microsoft открывают
// страницу входа службы сразу, адрес не нужен; остальные — шаг 2 с полем
// адреса. На шаге 2 у рабочей почты — переключатель «Exchange | IMAP»:
// протокол, который узнали по адресу, видно и можно сменить.

import '../../../widgets/ui/confirm_dialog.dart';
import '../../../core/constants/exchange_feature.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/mail_domains.dart' show isPublicMailDomain;
import '../../../core/security/certificate_pinning_service.dart';
import '../../../core/security/trusted_ca_store.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/async_guard.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/ews/ews_service.dart';
import '../../../services/mail/mail_provider_detect.dart';
import '../../../services/mail/oauth/cross_platform_oauth.dart' show crossPlatformOAuthProvider;
import '../../../services/mail/oauth/direct_oauth.dart' show DirectOAuth;
import '../../../widgets/common/app_logo.dart';
import '../../../widgets/common/eas_compat_switch.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/app_menu_button.dart';
import '../../../widgets/ui/help_hint.dart' show TitleWithHelp;
import '../../mail/providers/mail_providers.dart';
import '../providers/auth_provider.dart';
import '../../../core/security/secure_storage_service.dart' show secureStorageProvider;
import '../widgets/certificate_trust_dialog.dart';
import '../../settings/widgets/account_label_dialog.dart';
import '../../../services/security/managed_config.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool isAddMode;

  /// «Войти снова» (1.5.12): тот же экран, заполненный данными ящика —
  /// адрес не меняется, тип не выбирается, логин, домен, сервер (или
  /// серверы IMAP/SMTP) — в «Расширенных настройках». Успех — экран
  /// закрывается с обновлённым ящиком (`context.pop(account)`).
  final String? reauthAccountId;
  const LoginScreen({super.key, this.isAddMode = false, this.reauthAccountId});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

/// Шаг входа: адрес или способ входа.
enum _Step { address, method }

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SafeAsyncState<LoginScreen>, SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  /// Логин IMAP, если он не совпадает с адресом (рабочая почта, 2.6.0):
  /// «ivanov», «CORP\\ivanov». Пусто — логин = адрес.
  final _imapLoginController = TextEditingController();
  final _domainController = TextEditingController(text: AppConstants.defaultDomain);
  final _serverController = TextEditingController(text: AppConstants.defaultExchangeServer);
  final _imapServerController = TextEditingController();
  final _imapPortController = TextEditingController(text: AppConstants.defaultImapPort.toString());
  final _smtpServerController = TextEditingController();
  final _smtpPortController = TextEditingController(text: AppConstants.defaultSmtpPort.toString());
  final _passwordFocus = FocusNode();

  bool _showPassword = false;

  /// «Войти снова» (18.11.2026: «перезайти с сохранёнными данными нельзя —
  /// пароль не заполняется»): в поле — сохранённый пароль (точками). Пока
  /// он не изменён, показать его нельзя — подсмотреть с чужого телефона
  /// тоже.
  bool _savedPassword = false;
  bool _showAdvanced = false;

  /// Порты или шифрование IMAP/SMTP изменены вручную — их не подбираем.
  bool _portsEdited = false;
  EncryptionType _imapEncryption = EncryptionType.ssl;
  EncryptionType _smtpEncryption = EncryptionType.starttls;

  /// Стандартные порты по типу шифрования. При смене шифрования порт должен
  /// меняться вместе с ним, иначе подключение не установится (например,
  /// STARTTLS на порту 993 не работает).
  static const Map<EncryptionType, int> _imapStandardPorts = {
    EncryptionType.ssl: 993,
    EncryptionType.starttls: 143,
    EncryptionType.none: 143,
  };
  static const Map<EncryptionType, int> _smtpStandardPorts = {
    EncryptionType.ssl: 465,
    EncryptionType.starttls: 587,
    EncryptionType.none: 25,
  };

  /// Подключение без шифрования: пароль и письма — открытым текстом.
  Future<bool> _confirmPlaintext() {
    final l10n = AppLocalizations.of(context);
    return confirmDestructive(context,
        title: l10n.tr('plaintextTitle'), message: l10n.tr('plaintextBody'), action: l10n.tr('plaintextAction'));
  }

  /// Подставляет стандартный порт для выбранного шифрования, НО только если
  /// текущее значение — тоже стандартное (т.е. пользователь не вписал свой порт
  /// вручную). Так мы не затираем нестандартный порт корпоративного сервера.
  void _applyStandardPort(
      TextEditingController controller, Map<EncryptionType, int> table, EncryptionType next) {
    final current = int.tryParse(controller.text.trim());
    final isStandard = current == null || table.values.contains(current);
    if (!isStandard) return;
    final port = table[next];
    if (port != null) controller.text = port.toString();
  }

  PinningMode _pinningMode = PinningMode.trustStore;
  AccountType _selectedType = kExchangeEnabled ? AccountType.exchange : AccountType.imap;

  /// Почта iCloud (1.6.12): ящик IMAP с серверами Apple и паролем приложения.
  bool _icloud = false;

  /// IMAP организации (2.6.0): плитка «Рабочая почта», политика MDM или
  /// домен организации без известных серверов — подсказка, что спросить у
  /// администратора.
  bool _corporate = false;
  final _formKey = GlobalKey<FormState>();

  /// Шаг входа (1.8.0).
  _Step _step = _Step.address;

  /// Идёт проверка адреса («Ищем настройки почты…»).
  bool _detecting = false;

  /// Что узнали по адресу (null — способ выбран вручную или «Войти снова»).
  MailGuess? _guess;

  /// Шаг 2 открыт без адреса (плитка или «Другой способ входа» до ввода
  /// адреса) — поле адреса на шаге 2. Флаг, а не «адрес неверный»: иначе
  /// поле пропадало бы посреди ввода, как только адрес становился похож на
  /// настоящий.
  bool _askEmail = false;

  /// Домен, для которого узнан [_guess].
  String? _guessFor;

  /// Способ выбран вручную («Другой способ входа»).
  bool _manual = false;

  /// Вход паролем приложения вместо входа через службу ('google' |
  /// 'yandex'): Google не пустил по OAuth (лимит пользователей
  /// непроверенного приложения, 2.5.4) или входа через службу на этой
  /// платформе нет (2.5.5: сервера входа нет — Яндекс на Windows и Linux,
  /// сборка без клиента Google).
  String? _appPwFor;

  /// Страница паролей приложений службы (Google — и для адресов Google
  /// Workspace на своём домене: MailProviderDetect знает только gmail.com).
  static String _appPwUrlFor(String provider) => provider == 'yandex'
      ? 'https://id.yandex.ru/security/app-passwords'
      : 'https://myaccount.google.com/apppasswords';

  /// Серверы Яндекс Почты для входа паролем приложения.
  static const _yandexImap = ImapPreset(
    imapHost: 'imap.yandex.ru',
    imapPort: 993,
    imapEncryption: EncryptionType.ssl,
    smtpHost: 'smtp.yandex.ru',
    smtpPort: 465,
    smtpEncryption: EncryptionType.ssl,
  );

  /// Серверы Gmail для входа паролем приложения (и для адресов Google
  /// Workspace на своём домене).
  static const _gmailImap = ImapPreset(
    imapHost: 'imap.gmail.com',
    imapPort: 993,
    imapEncryption: EncryptionType.ssl,
    smtpHost: 'smtp.gmail.com',
    smtpPort: 587,
    smtpEncryption: EncryptionType.starttls,
  );

  /// Ошибка поля адреса на первом шаге.
  String? _addressError;

  /// Домен, для которого заполнены серверы: адрес сменили — серверы
  /// прежнего домена не переносятся на новый.
  String? _filledFor;

  /// Ящик для «Войти снова»; null — обычный вход.
  AccountModel? _reauth;
  bool _reauthBusy = false;
  String? _reauthError;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  /// Ящики до входа: после успешного входа новый ящик — тот, которого здесь
  /// не было (ему предлагается название, 2.6.1).
  Set<String> _idsBefore = const {};
  bool _successHandled = false;

  @override
  void initState() {
    super.initState();
    _idsBefore = {for (final a in ref.read(accountsProvider)) a.id};
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
    final rid = widget.reauthAccountId;
    if (rid != null) {
      final a = ref.read(accountsProvider).where((x) => x.id == rid).firstOrNull;
      if (a != null) {
        _fillFrom(a);
        if (!a.usesOAuthTokens) unawaited(_fillSavedPassword(a.id));
      }
    } else {
      // Ящик, заданный организацией (MDM, 1.10.5), — адрес уже вписан,
      // остаётся пароль; ещё не добавлен — иначе пустой вход.
      final m = ref.read(managedPolicyProvider);
      final email = m.accountEmail;
      if (m.hasAccount && !ref.read(accountsProvider).any((a) => a.email.toLowerCase() == email)) {
        _emailController.text = email!;
      }
    }
    _emailController.addListener(_onEmailChanged);
    // Ошибка прошлой попытки входа не должна встречать на новом экране входа
    // (замечание 09.10.2026: «Не удалось подключиться…» висело при входе
    // в другой ящик).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authProvider).errorMessage != null) ref.read(authProvider.notifier).clearError();
    });
  }

  /// Адрес сервера без пробелов (автозамена iPhone: «cloud mail.…») и без «/» в конце.
  static String _cleanServer(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  @override
  void dispose() {
    // Доверие ЦС Минцифры «на время настройки» не переживает экран входа
    // (ящик за это время уже получил флаг — TrustedCaStore.syncAccounts).
    TrustedCaStore.instance?.setupTrust = false;
    _emailController.removeListener(_onEmailChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _imapLoginController.dispose();
    _domainController.dispose();
    _serverController.dispose();
    _imapServerController.dispose();
    _imapPortController.dispose();
    _smtpServerController.dispose();
    _smtpPortController.dispose();
    _passwordFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Сохранённый пароль ящика — в поле «Войти снова».
  Future<void> _fillSavedPassword(String accountId) async {
    String? pw;
    try {
      pw = await ref.read(secureStorageProvider).getAccountPassword(accountId);
    } catch (_) {}
    if (!mounted || pw == null || pw.isEmpty || _passwordController.text.isNotEmpty) return;
    setState(() {
      _passwordController.text = pw!;
      _savedPassword = true;
      _savedPasswordText = pw;
      _showPassword = false;
    });
    _passwordController.addListener(_onPasswordEdited);
  }

  String? _savedPasswordText;

  /// Пароль изменили (а не только курсор или фокус) — это уже новый пароль.
  void _onPasswordEdited() {
    if (!_savedPassword || _passwordController.text == _savedPasswordText) return;
    _passwordController.removeListener(_onPasswordEdited);
    setState(() => _savedPassword = false);
  }

  /// Поля — из ящика («Войти снова»).
  void _fillFrom(AccountModel a) {
    _reauth = a;
    _step = _Step.method;
    final exchange = a.isMsExchange || a.usesEas || a.usesEws;
    _selectedType = exchange ? AccountType.exchange : AccountType.imap;
    _emailController.text = a.email;
    _usernameController.text = a.username;
    final own = a.username.trim().isNotEmpty && a.username.trim().toLowerCase() != a.email.trim().toLowerCase();
    _imapLoginController.text = !exchange && own ? a.username : '';
    _domainController.text = a.domain ?? '';
    _serverController.text = a.exchangeServer ?? '';
    _imapServerController.text = a.imapServer ?? '';
    _imapPortController.text = '${a.imapPort ?? AppConstants.defaultImapPort}';
    _smtpServerController.text = a.smtpServer ?? '';
    _smtpPortController.text = '${a.smtpPort ?? AppConstants.defaultSmtpPort}';
    _imapEncryption = a.imapEncryption ?? _imapEncryption;
    _smtpEncryption = a.smtpEncryption ?? _smtpEncryption;
    _filledFor = MailProviderDetect.domainOf(a.email);
    // Ящик Google (2.6.7): «Войти снова» — пароль приложения Gmail
    // (серверы Gmail, если у ящика их не было).
    if (a.type == AccountType.google) {
      _appPwFor = 'google';
      if (_imapServerController.text.trim().isEmpty) {
        _imapServerController.text = _gmailImap.imapHost;
        _imapPortController.text = '${_gmailImap.imapPort}';
        _imapEncryption = _gmailImap.imapEncryption;
        _smtpServerController.text = _gmailImap.smtpHost;
        _smtpPortController.text = '${_gmailImap.smtpPort}';
        _smtpEncryption = _gmailImap.smtpEncryption;
      }
    }
  }

  /// Пароль из поля. Пароль приложения Google показывается группами через
  /// пробел («abcd efgh ijkl mnop») — пробелы не часть пароля.
  String get _passwordText =>
      _appPwFor == 'google' ? _passwordController.text.replaceAll(RegExp(r'\s'), '') : _passwordController.text;

  /// Логин Exchange — часть адреса до «@».
  void _onEmailChanged() {
    if (_reauth != null) return; // адрес ящика не меняется
    final t = _emailController.text;
    if (t.contains('@')) _usernameController.text = t.split('@').first.trim();
    if (_addressError != null) setState(() => _addressError = null);
  }

  // ════════════════════════ СПОСОБ ВХОДА ════════════════════════

  /// Способ входа по выбранному типу ящика.
  MailKind get _kind {
    if (_icloud) return MailKind.icloud;
    return switch (_selectedType) {
      AccountType.google => MailKind.google,
      AccountType.outlook => MailKind.microsoft,
      AccountType.yandex => MailKind.yandex,
      AccountType.mailru => MailKind.mailru,
      AccountType.imap || AccountType.yahoo => MailKind.imap,
      _ => MailKind.exchange,
    };
  }

  bool get _isOAuthKind => _kind == MailKind.google || _kind == MailKind.microsoft || _kind == MailKind.yandex;

  String get _email => _emailController.text.trim();

  /// Домен адреса — не общедоступная почта и не известная служба: скорее
  /// всего, почта организации.
  bool get _orgDomain {
    final d = MailProviderDetect.domainOf(_email);
    return d != null && !isPublicMailDomain(d) && MailProviderDetect.byDomain(_email) == null;
  }

  /// Поле «Логин (если отличается от адреса)» у IMAP: рабочая почта,
  /// домен организации, логин уже задан (MDM, «Войти снова»).
  bool get _showImapLogin =>
      _kind == MailKind.imap &&
      !_icloud &&
      _appPwFor == null &&
      (_corporate || _orgDomain || _imapLoginController.text.trim().isNotEmpty || _reauth != null);

  /// Адрес похож на настоящий (на шаге 2 тогда не нужно поле адреса).
  bool get _emailValid => MailProviderDetect.domainOf(_email) != null && !_email.startsWith('@');

  /// Выбрать способ входа (и серверы IMAP, если они известны).
  /// [guessed] — серверы IMAP додуманы по домену (imap./smtp.): их стоит
  /// проверить.
  void _applyKind(MailKind k, {ImapPreset? preset, bool guessed = false}) {
    _icloud = k == MailKind.icloud;
    if (k != MailKind.imap) _corporate = false;
    _appPwFor = null;
    // Входа через службу на этой платформе нет (2.5.5) — пароль приложения
    // по IMAP с серверами службы. Microsoft паролей не принимает — остаётся
    // вход через службу (он объяснит, что не настроен).
    final provider = switch (k) { MailKind.google => 'google', MailKind.yandex => 'yandex', _ => null };
    // Google (2.6.7) — всегда пароль приложения: доступ к почте Gmail через
    // вход Google приложение больше не запрашивает.
    if (provider != null &&
        _reauth == null &&
        (provider == 'google' || !ref.read(crossPlatformOAuthProvider).available(provider))) {
      k = MailKind.imap;
      preset = provider == 'google' ? _gmailImap : _yandexImap;
      guessed = false;
      _appPwFor = provider;
    }
    _selectedType = switch (k) {
      MailKind.google => AccountType.google,
      MailKind.microsoft => AccountType.outlook,
      MailKind.yandex => AccountType.yandex,
      MailKind.mailru => AccountType.mailru,
      MailKind.icloud || MailKind.imap => AccountType.imap,
      MailKind.exchange => AccountType.exchange,
    };
    if (preset != null) {
      _portsEdited = false;
      _imapServerController.text = preset.imapHost;
      _imapPortController.text = '${preset.imapPort}';
      _imapEncryption = preset.imapEncryption;
      _smtpServerController.text = preset.smtpHost;
      _smtpPortController.text = '${preset.smtpPort}';
      _smtpEncryption = preset.smtpEncryption;
    }
    // Серверы IMAP неизвестны или это догадка — «Расширенные настройки»
    // открыты сразу: их стоит проверить.
    _showAdvanced = k == MailKind.imap && (preset == null || guessed || !(_guess?.sure ?? true));
    ref.read(authProvider.notifier).reset();
  }

  /// Адрес сменили — серверы, логин и домен прежнего домена сбрасываются.
  void _resetForDomain() {
    final d = MailProviderDetect.domainOf(_email);
    if (d == _filledFor) return;
    _filledFor = d;
    _imapServerController.clear();
    _imapPortController.text = AppConstants.defaultImapPort.toString();
    _imapEncryption = EncryptionType.ssl;
    _smtpServerController.clear();
    _smtpPortController.text = AppConstants.defaultSmtpPort.toString();
    _smtpEncryption = EncryptionType.starttls;
    _serverController.text = AppConstants.defaultExchangeServer;
    _domainController.text = AppConstants.defaultDomain;
  }

  /// Серверы, логин и домен из политики организации (MDM, 1.10.5) — для
  /// ящика, который она задала (адрес совпадает).
  void _applyManaged() {
    final m = ref.read(managedPolicyProvider);
    if (!m.hasAccount || _email.trim().toLowerCase() != m.accountEmail) return;
    final proto = m.accountProtocol ?? 'auto';
    if (proto == 'imap' || (proto == 'auto' && m.imapServer != null)) {
      final smtpPort = m.smtpPort ?? 587;
      _applyKind(MailKind.imap,
          preset: ImapPreset(
            imapHost: m.imapServer ?? _imapServerController.text,
            imapPort: m.imapPort ?? 993,
            imapEncryption: EncryptionType.ssl,
            smtpHost: m.smtpServer ?? _smtpServerController.text,
            smtpPort: smtpPort,
            smtpEncryption: smtpPort == 465 ? EncryptionType.ssl : EncryptionType.starttls,
          ));
    } else if (kExchangeEnabled && (proto == 'exchange' || m.accountServer != null)) {
      _applyKind(MailKind.exchange);
    }
    final server = m.accountServer;
    if (server != null) _serverController.text = _cleanServer(server);
    final user = m.accountUsername;
    if (user != null) _usernameController.text = user;
    // IMAP организации: логин из политики — в поле логина IMAP.
    if (_kind == MailKind.imap) {
      _corporate = true;
      if (user != null) _imapLoginController.text = user;
    }
    final domain = m.accountDomain;
    if (domain != null) _domainController.text = domain;
  }

  /// «Далее»: узнать почту по адресу и перейти ко входу.
  Future<void> _onNext() async {
    final l10n = AppLocalizations.of(context);
    if (!_emailValid) {
      setState(() => _addressError = l10n.tr('invalidEmail'));
      return;
    }
    // Политика организации (MDM, 1.10.5): только разрешённые домены.
    final mdm = ref.read(managedPolicyProvider);
    if (!mdm.allowsAccount(_email)) {
      setState(() => _addressError =
          l10n.tr('mdmDomainNotAllowed').replaceAll('{domains}', mdm.allowedDomains.join(', ')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _addressError = null;
      _detecting = true;
    });
    var guess = await MailProviderDetect.detect(_email);
    if (!mounted) return;
    // Сборка без Exchange (1.8.5): «похоже на Exchange» — IMAP с серверами
    // домена (их можно поправить в «Дополнительно»).
    if (!kExchangeEnabled && guess.kind == MailKind.exchange) {
      final d = MailProviderDetect.domainOf(_email) ?? '';
      // Серверы IMAP, которые опубликовал администратор (SRV), — уверенно.
      guess = MailGuess(MailKind.imap,
          sure: guess.imap != null,
          imap: guess.imap ?? ImapPreset(
            imapHost: 'imap.$d',
            imapPort: 993,
            imapEncryption: EncryptionType.ssl,
            smtpHost: 'smtp.$d',
            smtpPort: 587,
            smtpEncryption: EncryptionType.starttls,
          ));
    }
    setState(() {
      _detecting = false;
      _resetForDomain();
      _guess = guess;
      _guessFor = MailProviderDetect.domainOf(_email);
      _manual = false;
      _askEmail = false;
      _applyKind(guess.kind, preset: guess.imap);
      // Домен организации (не общедоступная почта и не известная служба) —
      // подсказка «что спросить у администратора» и поле логина.
      _corporate = guess.kind == MailKind.imap && _orgDomain;
      _applyManaged();
      _step = _Step.method;
    });
    unawaited(HapticFeedback.selectionClick());
    _focusPasswordSoon();
  }

  /// Поле пароля — в фокус после перехода (вход по паролю).
  void _focusPasswordSoon() {
    if (_isOAuthKind) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == _Step.method) _passwordFocus.requestFocus();
    });
  }

  /// К первому шагу (адрес).
  void _backToAddress() {
    if (_reauth != null) return;
    setState(() {
      _step = _Step.address;
      _passwordController.clear();
    });
    ref.read(authProvider.notifier).reset();
  }

  /// «Другой способ входа» — выбор вручную.
  Future<void> _chooseMethod() async {
    final l10n = AppLocalizations.of(context);
    // (IMAP, true) — «IMAP организации»: тот же IMAP с подсказкой и логином.
    final k = await showActionSheet<(MailKind, bool)>(
      context,
      title: l10n.tr('loginChooseMethod'),
      items: [
        if (kExchangeEnabled)
          ActionSheetItem(
              icon: AppIcons.business,
              label: l10n.tr('exchange'),
              subtitle: l10n.tr('loginKindExchangeDesc'),
              value: (MailKind.exchange, false)),
        ActionSheetItem(
            icon: AppIcons.g_mobiledata, label: 'Google', subtitle: l10n.tr('loginKindGoogleDesc'), value: (MailKind.google, false)),
        ActionSheetItem(
            icon: AppIcons.window,
            label: 'Microsoft',
            subtitle: l10n.tr('loginKindMicrosoftDesc'),
            value: (MailKind.microsoft, false)),
        ActionSheetItem(
            icon: AppIcons.signal_cellular_alt,
            label: l10n.tr('yandex'),
            subtitle: l10n.tr('loginKindYandexDesc'),
            value: (MailKind.yandex, false)),
        ActionSheetItem(
            icon: AppIcons.alternate_email, label: 'Mail.ru', subtitle: l10n.tr('loginKindMailruDesc'), value: (MailKind.mailru, false)),
        ActionSheetItem(
            icon: AppIcons.cloud, label: 'iCloud', subtitle: l10n.tr('loginKindIcloudDesc'), value: (MailKind.icloud, false)),
        ActionSheetItem(
            icon: AppIcons.settings_ethernet,
            label: l10n.tr('loginKindImap'),
            subtitle: l10n.tr('loginKindImapDesc'),
            value: (MailKind.imap, false)),
        ActionSheetItem(
            icon: AppIcons.dns,
            label: l10n.tr('loginKindWorkImap'),
            subtitle: l10n.tr('loginKindWorkImapDesc'),
            value: (MailKind.imap, true)),
      ],
    );
    if (k == null || !mounted) return;
    _pickMethod(k.$1, corporate: k.$2);
  }

  /// Способ входа выбран вручную (плитка, «Другой способ входа»): шаг 2.
  /// Google, Яндекс и Microsoft — сразу страница входа службы: адрес для
  /// неё не нужен (если введён — подставляется).
  void _pickMethod(MailKind k, {bool corporate = false}) {
    setState(() {
      _resetForDomain();
      // Адрес не проверяли (плитка до «Далее») — подсказки прежнего адреса
      // («догадка», пароль приложения) не к месту.
      if (_guess != null && MailProviderDetect.domainOf(_email) != _guessFor) _guess = null;
      _manual = true;
      _askEmail = !_emailValid;
      final p = _imapPreset();
      _applyKind(k, preset: k == MailKind.imap ? p.preset : null, guessed: p.guessed);
      _corporate = k == MailKind.imap && (corporate || (_emailValid && _orgDomain));
      // IMAP организации — серверы и логин сразу на виду.
      if (corporate) _showAdvanced = true;
      _step = _Step.method;
    });
    unawaited(HapticFeedback.selectionClick());
    if (_isOAuthKind) {
      _onOAuth();
    } else {
      _focusPasswordSoon();
    }
  }

  /// Серверы IMAP для адреса: что узнали по нему, таблица известных служб
  /// или imap./smtp. домена (их можно поправить в «Расширенных настройках»).
  ({ImapPreset? preset, bool guessed}) _imapPreset() {
    final known = _guess?.imap ?? ImapPreset.fromTable(AppConstants.serverConfigForEmail(_email));
    if (known != null) return (preset: known, guessed: false);
    final d = MailProviderDetect.domainOf(_email);
    if (d == null) return (preset: null, guessed: false);
    return (preset: ImapPreset(
      imapHost: 'imap.$d',
      imapPort: 993,
      imapEncryption: EncryptionType.ssl,
      smtpHost: 'smtp.$d',
      smtpPort: 587,
      smtpEncryption: EncryptionType.starttls,
    ), guessed: true);
  }

  /// Вход удался: новому ящику — предложить название (2.6.1, просьба
  /// владельца 16.11.2026; можно пропустить), затем — в почту или обратно в
  /// настройки.
  Future<void> _afterSuccess() async {
    if (_reauth == null && widget.reauthAccountId == null) {
      final added = [for (final a in ref.read(accountsProvider)) if (!_idsBefore.contains(a.id)) a];
      if (added.isNotEmpty && mounted) {
        await showAccountLabelDialog(context, ref, added.last, ask: true);
      }
    }
    if (!mounted) return;
    if (widget.isAddMode && context.canPop()) {
      context.pop(); // возврат в настройки после добавления аккаунта
    } else {
      context.go('/mail');
    }
  }

  /// Переключатель «Exchange | IMAP» на шаге 2 (1.8.8).
  void _switchProtocol(MailKind k) {
    if (k == _kind) return;
    setState(() {
      _manual = true;
      final p = _imapPreset();
      _applyKind(k, preset: k == MailKind.imap ? p.preset : null, guessed: p.guessed);
    });
    unawaited(HapticFeedback.selectionClick());
  }

  // ════════════════════════ ЭКРАН ════════════════════════

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider);

    // Переход при успехе
    ref.listen<AuthState>(authProvider, (prev, next) {
      // Сертификат сервера не прошёл проверку — предложить сверить отпечаток.
      final cert = next.untrustedCert;
      if (cert != null && !identical(cert, prev?.untrustedCert)) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          if (await showCertificateTrustDialog(context, cert)) {
            await ref.read(certPinningProvider).trustCertificate(cert);
            if (mounted) _onLogin();
          }
        });
      }
      if (next.status == AuthStatus.success && !_successHandled) {
        _successHandled = true;
        HapticFeedback.mediumImpact();
        unawaited(_afterSuccess());
      }
    });

    final onMethod = _step == _Step.method;
    final busy = _reauth != null ? _reauthBusy : authState.status == AuthStatus.connecting;
    return PopScope(
      // Шаг 2 — «Назад» возвращает к адресу, а не закрывает экран (пока
      // идёт вход — ничего не делает).
      canPop: !onMethod || _reauth != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && onMethod && !busy) _backToAddress();
      },
      child: Scaffold(
        // «Войти снова», добавление ящика и шаг 2 — с кнопкой «Назад»
        // (системная — не у всех на виду).
        appBar: ((_reauth != null || widget.isAddMode) && context.canPop()) || (onMethod && _reauth == null)
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: onMethod && _reauth == null
                    ? IconButton(
                        icon: const BackButtonIcon(),
                        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: busy ? null : _backToAddress,
                      )
                    : null,
              )
            : null,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: onMethod
                        ? _buildMethodStep(theme, l10n, authState, busy)
                        : _buildAddressStep(theme, l10n, accounts.isNotEmpty),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════ ШАГ 1: АДРЕС ════════════════════════

  Widget _buildAddressStep(ThemeData theme, AppLocalizations l10n, bool hasAccounts) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.xl),
        _buildLogo(theme),
        const SizedBox(height: Space.s),
        Text(l10n.tr('loginTitle'), style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.s),
        Text(l10n.tr('loginAddressHint'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: Space.xl),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: l10n.tr('email'),
            hintText: 'name@example.com',
            prefixIcon: const Icon(AppIcons.mail),
            errorText: _addressError,
            suffixIcon: _emailController.text.isNotEmpty && !_detecting
                ? IconButton(
                    tooltip: l10n.tr('clear'),
                    icon: const Icon(AppIcons.clear, size: 20),
                    onPressed: () {
                      _emailController.clear();
                      _usernameController.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          enableSuggestions: false,
          autofocus: hasAccounts,
          textInputAction: TextInputAction.next,
          enabled: !_detecting,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _onNext(),
        ),
        const SizedBox(height: Space.l),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _detecting ? null : _onNext,
            child: _detecting
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: Space.m),
                    Flexible(child: Text(l10n.tr('loginDetecting'), overflow: TextOverflow.ellipsis)),
                  ])
                : Text(l10n.tr('next')),
          ),
        ),
        // Способы входа (1.8.8; 2.6.0 — два раздела, замечание владельца
        // 15.11.2026): личная почта — плитками (Google, Яндекс и Microsoft —
        // сразу страница входа службы), рабочая — строками с пояснением.
        const SizedBox(height: Space.xl),
        _buildOrDivider(theme, l10n.tr('loginOrChoose')),
        const SizedBox(height: Space.l),
        _buildSectionLabel(theme, l10n.tr('loginPersonalMail')),
        const SizedBox(height: Space.s),
        _buildMethodTiles(theme, l10n),
        const SizedBox(height: Space.l),
        _buildSectionLabel(theme, l10n.tr('loginWorkMail')),
        const SizedBox(height: Space.s),
        _buildWorkRows(theme, l10n),

        // Новый телефон: ящики и настройки — из резервной копии.
        if (!hasAccounts) ...[
          const SizedBox(height: Space.m),
          TextButton.icon(
            icon: const Icon(AppIcons.settings_backup_restore, size: 18),
            label: Text(l10n.tr('backupFromLogin')),
            onPressed: () => context.push('/settings/backup'),
          ),
          // Копия архива Ogneliss (1.7.3): ящики и настройки
          // восстанавливаются из архива.
          TextButton.icon(
            icon: const Icon(AppIcons.inventory_2, size: 18),
            label: Text(l10n.tr('archiveFromLogin')),
            onPressed: () => context.push('/settings/archive'),
          ),
        ],

        // Уже есть ящики — кнопка «Пропустить»
        if (hasAccounts && !(widget.isAddMode && context.canPop())) ...[
          const SizedBox(height: Space.m),
          TextButton(
            onPressed: () => context.go('/mail'),
            child: Text(l10n.tr('skipAccountsExist')),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildLogo(ThemeData theme) {
    return Column(
      children: [
        const AppLogo(size: 80),
        const SizedBox(height: Space.m),
        Text(AppConstants.appName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Черта с подписью посередине: «или выберите почту».
  Widget _buildOrDivider(ThemeData theme, String text) {
    final color = theme.colorScheme.outlineVariant;
    return Row(children: [
      Expanded(child: Divider(color: color)),
      // Длинная подпись (крупный шрифт, другой язык) переносится, а не
      // вылезает за край.
      Flexible(
        flex: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ),
      Expanded(child: Divider(color: color)),
    ]);
  }

  /// Подпись раздела: «Личная почта», «Рабочая почта».
  Widget _buildSectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsetsDirectional.only(start: Space.xs),
        child: Text(text,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );

  /// Рабочая почта: Exchange, Microsoft 365, IMAP организации и вход через
  /// систему организации (форк или консультация) — строками с пояснением.
  Widget _buildWorkRows(ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    Widget row(IconData icon, Color color, String title, String desc, VoidCallback onTap, {Key? key}) => Material(
          key: key,
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.chipAll,
          child: InkWell(
            borderRadius: Radii.chipAll,
            onTap: _detecting ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.m, horizontal: Space.m),
              child: Row(children: [
                CircleAvatar(radius: 18, backgroundColor: color, child: Icon(icon, size: 20, color: Colors.white)),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                Icon(AppIcons.chevron_right, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (kExchangeEnabled) ...[
        row(_kindIcon(MailKind.exchange), _kindColor(MailKind.exchange), l10n.tr('exchange'),
            l10n.tr('loginKindExchangeServerDesc'), () => _pickMethod(MailKind.exchange)),
        const SizedBox(height: Space.s),
      ],
      row(_kindIcon(MailKind.microsoft), _kindColor(MailKind.microsoft), 'Microsoft 365', l10n.tr('loginKindM365Desc'),
          () => _pickMethod(MailKind.microsoft)),
      const SizedBox(height: Space.s),
      row(AppIcons.dns, _kindColor(MailKind.imap), l10n.tr('loginKindWorkImap'), l10n.tr('loginKindWorkImapDesc'),
          () => _pickMethod(MailKind.imap, corporate: true),
          key: const ValueKey('login_work_imap')),
      const SizedBox(height: Space.s),
      row(AppIcons.verified_user, const Color(0xFF6B4FA0), l10n.tr('loginKindSso'), l10n.tr('loginKindSsoDesc'),
          () => unawaited(_showOrgSso()),
          key: const ValueKey('login_sso')),
    ]);
  }

  /// Вход через систему организации (SSO, OAuth организации): в приложении
  /// его нет — он у каждой организации свой. Решение владельца 15.11.2026:
  /// не обещать сделать его каждому, а предложить форк открытого кода или
  /// консультацию.
  Future<void> _showOrgSso() async {
    final l10n = AppLocalizations.of(context);
    final go = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(AppIcons.verified_user),
        title: Text(l10n.tr('loginSsoTitle')),
        content: SingleChildScrollView(child: Text(l10n.tr('loginSsoBody'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('close'))),
          TextButton(
              key: const ValueKey('login_sso_source'),
              onPressed: () => Navigator.pop(ctx, 'source'),
              child: Text(l10n.tr('sourceCode'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'contact'), child: Text(l10n.tr('loginSsoContact'))),
        ],
      ),
    );
    if (go == 'source') {
      await _open(AppConstants.sourceUrl);
    } else if (go == 'contact') {
      final mail = AppConstants.supportEmail.trim();
      await _open(mail.isNotEmpty
          ? Uri(scheme: 'mailto', path: mail, queryParameters: {'subject': 'Ogneliss Mail: SSO'}).toString()
          : AppConstants.corporateContactUrl(l10n.localeCode));
    }
  }

  /// Плитки личной почты: по три в ряд.
  Widget _buildMethodTiles(ThemeData theme, AppLocalizations l10n) {
    final kinds = [
      MailKind.google,
      MailKind.yandex,
      MailKind.microsoft,
      MailKind.mailru,
      MailKind.icloud,
      MailKind.imap,
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = Space.s;
      final w = ((c.maxWidth - gap * 2) / 3).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        alignment: WrapAlignment.center,
        children: [for (final k in kinds) SizedBox(width: w, child: _buildMethodTile(theme, l10n, k))],
      );
    });
  }

  Widget _buildMethodTile(ThemeData theme, AppLocalizations l10n, MailKind k) {
    final scheme = theme.colorScheme;
    final color = _kindColor(k);
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: Radii.chipAll,
      child: InkWell(
        borderRadius: Radii.chipAll,
        onTap: _detecting ? null : () => _pickMethod(k),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.m, horizontal: Space.xs),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color,
              child: Icon(_kindIcon(k), size: 22, color: Colors.white),
            ),
            const SizedBox(height: Space.s),
            Text(
              _kindTitle(l10n, k, short: true),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ]),
        ),
      ),
    );
  }

  Color _kindColor(MailKind k) => switch (k) {
        MailKind.google => _providerColor(AccountType.google),
        MailKind.yandex => _providerColor(AccountType.yandex),
        MailKind.microsoft => _providerColor(AccountType.outlook),
        MailKind.mailru => _providerColor(AccountType.mailru),
        MailKind.icloud => const Color(0xFF3693F3),
        MailKind.exchange => const Color(0xFF0F5BA7),
        MailKind.imap => const Color(0xFF5A6472),
      };

  /// Переключатель «Exchange | IMAP» — у рабочей почты на шаге 2.
  Widget _buildProtocolSwitch(AppLocalizations l10n, bool busy) {
    return SegmentedButton<MailKind>(
      segments: [
        ButtonSegment(value: MailKind.exchange, icon: const Icon(AppIcons.business), label: Text(l10n.tr('exchange'))),
        const ButtonSegment(value: MailKind.imap, icon: Icon(AppIcons.settings_ethernet), label: Text('IMAP')),
      ],
      selected: {_kind},
      showSelectedIcon: false,
      onSelectionChanged: busy ? null : (v) => _switchProtocol(v.first),
    );
  }

  // ════════════════════════ ШАГ 2: ВХОД ════════════════════════

  Widget _buildMethodStep(ThemeData theme, AppLocalizations l10n, AuthState authState, bool busy) {
    final reauth = _reauth != null;
    final error = reauth ? _reauthError : authState.errorMessage;
    final kind = _kind;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reauth) ...[
          Text(l10n.tr('signInAgain'), style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: Space.l),
        ],
        _buildProviderHeader(theme, l10n, busy),
        if (!reauth && kExchangeEnabled && (kind == MailKind.exchange || kind == MailKind.imap)) ...[
          const SizedBox(height: Space.l),
          Center(child: _buildProtocolSwitch(l10n, busy)),
        ],
        if (!reauth && !_manual && _guess != null && !_guess!.sure) ...[
          const SizedBox(height: Space.m),
          _buildNote(theme, kind == MailKind.imap ? l10n.tr('loginGuessImap') : l10n.tr('loginGuessUnsure')),
        ],
        const SizedBox(height: Space.xl),
        // Exchange Online (Microsoft 365): вход в браузере Microsoft (1.6.2)
        // — если в сборке задан клиент Microsoft.
        if (!reauth && kind == MailKind.exchange && !kIsWeb && DirectOAuth.clientFor('exchange') != null) ...[
          _buildExchangeOnlineButton(theme, l10n, busy),
          const SizedBox(height: Space.l),
        ],
        if (_isOAuthKind && !reauth)
          _buildOAuthStep(theme, l10n, busy)
        else
          _buildPasswordStep(theme, l10n, busy),

        // Ошибка — строкой с кнопкой: что сделать дальше.
        if (error != null) ...[
          const SizedBox(height: Space.l),
          _buildError(theme, l10n, error, reauth ? _reauthErrorKind : authState.errorKind),
          // Вход не удался — журнал нужен именно сейчас, а в настройки без
          // ящика не попасть.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(AppIcons.article, size: 18),
              label: Text(l10n.tr('logsForSupport')),
              onPressed: () => context.push('/settings/logs'),
            ),
          ),
        ],

        // Российские сертификаты (НУЦ Минцифры) — частая причина
        // «сертификат не прошёл проверку» у российских серверов. Тот же
        // переключатель — в Настройки → Защита. Только на русском языке
        // интерфейса (1.7.3, решение владельца 25.10.2026) и только для
        // своих серверов (Exchange, IMAP).
        if (TrustedCaStore.instance case final store?
            when !reauth &&
                store.userTrustAllowed &&
                l10n.isRussian &&
                (kind == MailKind.exchange || kind == MailKind.imap)) ...[
          const SizedBox(height: Space.s),
          StatefulBuilder(
            builder: (context, setLocal) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(AppIcons.verified_user),
              // Пояснение — под «?» (10.10.2026).
              title: TitleWithHelp(l10n.tr('caMincifry'), hint: l10n.tr('caMincifrySetupDesc')),
              // Только для подключаемого ящика: созданный ящик получит флаг
              // (TrustedCaStore.syncAccounts), для остальных серверов ЦС не
              // действует.
              value: store.bundledEnabled || store.setupTrust,
              onChanged: store.bundledEnabled ? null : (v) => setLocal(() => store.setupTrust = v),
            ),
          ),
        ],

        if (!reauth) ...[
          const SizedBox(height: Space.s),
          Center(
            child: TextButton(
              onPressed: busy ? null : _chooseMethod,
              child: Text(l10n.tr('loginOtherMethod')),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  /// Название способа входа.
  String _kindTitle(AppLocalizations l10n, MailKind k, {bool short = false}) => switch (k) {
        MailKind.exchange => l10n.tr('exchange'),
        MailKind.google => 'Google',
        MailKind.microsoft => (_guess?.microsoft365 ?? false) ? 'Microsoft 365' : 'Microsoft',
        MailKind.yandex => l10n.tr('yandex'),
        MailKind.mailru => 'Mail.ru',
        MailKind.icloud => 'iCloud',
        MailKind.imap => short ? 'IMAP' : l10n.tr('loginKindImap'),
      };

  IconData _kindIcon(MailKind k) => switch (k) {
        MailKind.exchange => AppIcons.business,
        MailKind.google => AppIcons.g_mobiledata,
        MailKind.microsoft => AppIcons.window,
        MailKind.yandex => AppIcons.signal_cellular_alt,
        MailKind.mailru => AppIcons.alternate_email,
        MailKind.icloud => AppIcons.cloud,
        MailKind.imap => AppIcons.settings_ethernet,
      };

  /// Шапка шага 2: способ входа и адрес («Изменить» — к первому шагу).
  Widget _buildProviderHeader(ThemeData theme, AppLocalizations l10n, bool busy) {
    final scheme = theme.colorScheme;
    final kind = _kind;
    return Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: scheme.primaryContainer,
          child: Icon(kind == MailKind.imap && _corporate ? AppIcons.dns : _kindIcon(kind),
              size: 32, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: Space.m),
        Text(kind == MailKind.imap && _corporate ? l10n.tr('loginKindWorkImap') : _kindTitle(l10n, kind),
            style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        if (_emailValid && !_askEmail) ...[
          const SizedBox(height: Space.xs),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.xs,
            children: [
              Text(_email, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (_reauth == null)
                TextButton(
                  onPressed: busy ? null : _backToAddress,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(l10n.tr('loginChangeAddress')),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Спокойная строка-пояснение.
  Widget _buildNote(ThemeData theme, String text) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: Radii.chipAll),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        ],
      ),
    );
  }

  /// Google, Microsoft, Яндекс: вход на странице службы, адрес подставлен.
  Widget _buildOAuthStep(ThemeData theme, AppLocalizations l10n, bool busy) {
    final name = _providerName(_selectedType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.tr('loginOAuthHint').replaceAll('{provider}', name),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: Space.l),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: busy ? null : _onOAuth,
            icon: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_providerIcon(_selectedType)),
            label: Text(busy ? l10n.tr('connecting') : l10n.tr('loginWithProvider').replaceAll('{provider}', name)),
            style: FilledButton.styleFrom(backgroundColor: _providerColor(_selectedType), foregroundColor: Colors.white),
          ),
        ),
      ],
    );
  }

  /// Вход по паролю: Exchange, IMAP, Mail.ru и iCloud (пароль приложения).
  Widget _buildPasswordStep(ThemeData theme, AppLocalizations l10n, bool busy) {
    final reauth = _reauth != null;
    final kind = _kind;
    final scheme = theme.colorScheme;
    final gmail = _appPwFor == 'google';
    final appPwKind = kind == MailKind.mailru || kind == MailKind.icloud || gmail;
    final appPwHint = !appPwKind && (_appPwFor != null || (_guess?.appPassword ?? false));
    final appPwUrl = switch (kind) {
      MailKind.mailru => 'https://account.mail.ru/user/2-step-auth/passwords/',
      MailKind.icloud => 'https://account.apple.com/account/manage',
      _ when _appPwFor != null => _appPwUrlFor(_appPwFor!),
      _ => MailProviderDetect.appPasswordUrl(_email),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mail.ru и iCloud: обычный пароль не подходит — объяснение и
        // ссылка на страницу, где создают пароль приложения. Mail.ru — только
        // так: OAuth Mail с июля 2025 не выдаёт доступ к почте новым
        // приложениям, а VK ID доступа к IMAP не даёт (09.10.2026).
        if (appPwKind) ...[
          Text(l10n.tr(gmail ? 'gmailAppPwTitle' : kind == MailKind.mailru ? 'mailruAppPwTitle' : 'icloudAppPwTitle'),
              style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(l10n.tr(gmail ? 'gmailAppPwHint' : kind == MailKind.mailru ? 'mailruAppPwHint' : 'icloudAppPwHint'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(AppIcons.open_in_new, size: 18),
              label: Text(l10n.tr(kind == MailKind.mailru && !gmail ? 'mailruAppPwCreate' : 'icloudAppPwCreate')),
              onPressed: () => _open(appPwUrl!),
            ),
          ),
          const SizedBox(height: Space.s),
        ],

        // IMAP организации (2.6.0): что понадобится и что спросить у
        // администратора; вход через систему организации — форк или консультация.
        if (kind == MailKind.imap && _corporate && !reauth) ...[
          _buildNote(theme, l10n.tr('loginWorkImapNote')),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(AppIcons.verified_user, size: 18),
              label: Text(l10n.tr('loginKindSso')),
              onPressed: busy ? null : () => unawaited(_showOrgSso()),
            ),
          ),
          const SizedBox(height: Space.s),
        ],

        // Адрес — если его нет в шапке (способ выбрали до ввода адреса).
        if (_askEmail && !reauth) ...[
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: l10n.tr('email'),
              hintText: 'name@example.com',
              prefixIcon: const Icon(AppIcons.mail),
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            readOnly: reauth,
            enabled: !busy,
            onChanged: (_) => setState(() {}),
            validator: (v) => MailProviderDetect.domainOf(v ?? '') == null ? l10n.tr('invalidEmail') : null,
          ),
          const SizedBox(height: Space.m),
        ],

        // Логин IMAP, если он не совпадает с адресом (рабочая почта: «ivanov»,
        // «CORP\\ivanov»). Пусто — входим по адресу.
        if (_showImapLogin) ...[
          TextFormField(
            key: const ValueKey('imap_login'),
            controller: _imapLoginController,
            decoration: InputDecoration(
              labelText: l10n.tr('imapLoginLabel'),
              hintText: l10n.tr('imapLoginHint'),
              prefixIcon: const Icon(AppIcons.person),
            ),
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.username],
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.next,
            enabled: !busy,
          ),
          const SizedBox(height: Space.m),
        ],

        // Пароль (у Mail.ru и iCloud — пароль приложения).
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          decoration: InputDecoration(
            labelText: switch (kind) {
              MailKind.mailru => l10n.tr('mailruAppPwLabel'),
              MailKind.icloud => l10n.tr('icloudAppPwLabel'),
              _ when gmail => l10n.tr('icloudAppPwLabel'),
              _ => l10n.tr('password'),
            },
            hintText: kind == MailKind.icloud
                ? 'xxxx-xxxx-xxxx-xxxx'
                : gmail
                    ? 'xxxx xxxx xxxx xxxx'
                    : null,
            prefixIcon: Icon(appPwKind ? AppIcons.key : AppIcons.lock),
            // Сохранённый пароль не показывается — только новый.
            helperText: _savedPassword ? l10n.tr('reauthSavedPassword') : null,
            suffixIcon: _savedPassword
                ? null
                : IconButton(
                    tooltip: l10n.tr(_showPassword ? 'hidePassword' : 'showPassword'),
                    icon: Icon(_showPassword ? AppIcons.visibility_off : AppIcons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
          ),
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          autofocus: reauth,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _onLogin(),
          enabled: !busy,
          validator: (v) => (v == null || v.isEmpty) ? l10n.tr('invalidPassword') : null,
        ),

        // Служба пускает почтовые программы только по паролю приложения.
        if (appPwHint) ...[
          const SizedBox(height: Space.s),
          _buildNote(theme, l10n.tr(_appPwFor == 'google' ? 'gmailAppPwNote' : 'loginAppPasswordNote')),
          if (appPwUrl != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(AppIcons.open_in_new, size: 18),
                label: Text(l10n.tr('loginErrAppPassword')),
                onPressed: () => _open(appPwUrl),
              ),
            ),
        ],

        // Расширенные настройки — у Exchange и IMAP.
        if (kind == MailKind.exchange || kind == MailKind.imap) ...[
          const SizedBox(height: Space.s),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              borderRadius: Radii.chipAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_showAdvanced ? AppIcons.keyboard_arrow_up : AppIcons.keyboard_arrow_down,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(l10n.tr('advancedSettings'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: Space.m),
            if (kind == MailKind.exchange) _buildExchangeAdvanced(l10n) else _buildImapAdvanced(l10n),
          ],
        ],

        const SizedBox(height: Space.xl),

        // Кнопка «Войти»
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: busy ? null : _onLogin,
            child: busy
                ? const SizedBox(width: Space.xl, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(AppIcons.login),
                    const SizedBox(width: Space.s),
                    Text(l10n.tr(reauth ? 'signInAgain' : 'login')),
                  ]),
          ),
        ),
      ],
    );
  }

  Widget _buildExchangeAdvanced(AppLocalizations l10n) {
    return Column(
      children: [
        TextFormField(controller: _usernameController, autocorrect: false, enableSuggestions: false, textCapitalization: TextCapitalization.none, decoration: InputDecoration(labelText: l10n.tr('username'), hintText: 'user', prefixIcon: const Icon(AppIcons.person))),
        const SizedBox(height: Space.m),
        TextFormField(controller: _domainController, autocorrect: false, enableSuggestions: false, textCapitalization: TextCapitalization.none, decoration: InputDecoration(labelText: l10n.tr('domain'), hintText: 'CORP', prefixIcon: const Icon(AppIcons.domain))),
        const SizedBox(height: Space.m),
        TextFormField(controller: _serverController, keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false, textCapitalization: TextCapitalization.none, decoration: InputDecoration(labelText: l10n.tr('server'), hintText: 'mail.example.com', prefixIcon: const Icon(AppIcons.dns))),
        const SizedBox(height: Space.xs),
        // «Войти снова» — переключатель этого ящика.
        EasCompatSwitch(contentPadding: EdgeInsets.zero, accountId: _reauth?.id),
        // Режим проверки сертификата — только в отладочной сборке: в
        // выпускаемой «строгий» не отличался от стандартного (1.6.2).
        if (!kReleaseMode) ...[
          const SizedBox(height: Space.m),
          AppSelectField<PinningMode>(
            value: _pinningMode,
            decoration: InputDecoration(labelText: l10n.certValidation, prefixIcon: const Icon(AppIcons.verified_user)),
            entries: [
              AppMenuEntry(value: PinningMode.trustStore, label: l10n.pinTrustStore),
              AppMenuEntry(value: PinningMode.pinned, label: l10n.pinStrict),
              AppMenuEntry(value: PinningMode.off, label: l10n.pinAcceptAll),
            ],
            onChanged: (v) {
              setState(() => _pinningMode = v);
              ref.read(certPinningProvider).setMode(v);
            },
          ),
        ],
        // «Дочернее общество» убрано (замечание 09.10.2026): не нужно.
      ],
    );
  }

  Widget _buildImapAdvanced(AppLocalizations l10n) {
    return Column(
      children: [
        TextFormField(controller: _imapServerController, keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'IMAP ${l10n.tr('server')}', prefixIcon: const Icon(AppIcons.dns))),
        const SizedBox(height: Space.m),
        Row(
          children: [
            Expanded(flex: 2, child: TextFormField(controller: _imapPortController, decoration: InputDecoration(labelText: 'IMAP ${l10n.tr('port')}'), keyboardType: TextInputType.number, onChanged: (_) => _portsEdited = true)),
            const SizedBox(width: Space.m),
            Expanded(flex: 3, child: AppSelectField<EncryptionType>(
              value: _imapEncryption,
              decoration: InputDecoration(labelText: l10n.tr('encryption')),
              entries: const [
                AppMenuEntry(value: EncryptionType.ssl, label: 'SSL/TLS'),
                AppMenuEntry(value: EncryptionType.starttls, label: 'STARTTLS'),
                AppMenuEntry(value: EncryptionType.none, label: 'None'),
              ],
              onChanged: (v) async {
                // Без шифрования пароль уходит открытым текстом (08.11.2026,
                // аудит безопасности) — только после явного согласия.
                if (v == EncryptionType.none && !await _confirmPlaintext()) return;
                if (!mounted) return;
                setState(() {
                  _portsEdited = true;
                  _imapEncryption = v;
                  _applyStandardPort(_imapPortController, _imapStandardPorts, v);
                });
              },
            )),
          ],
        ),
        const SizedBox(height: Space.m),
        TextFormField(controller: _smtpServerController, keyboardType: TextInputType.url, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'SMTP ${l10n.tr('server')}', prefixIcon: const Icon(AppIcons.send))),
        const SizedBox(height: Space.m),
        Row(
          children: [
            Expanded(flex: 2, child: TextFormField(controller: _smtpPortController, decoration: InputDecoration(labelText: 'SMTP ${l10n.tr('port')}'), keyboardType: TextInputType.number, onChanged: (_) => _portsEdited = true)),
            const SizedBox(width: Space.m),
            Expanded(flex: 3, child: AppSelectField<EncryptionType>(
              value: _smtpEncryption,
              decoration: InputDecoration(labelText: l10n.tr('encryption')),
              entries: const [
                AppMenuEntry(value: EncryptionType.ssl, label: 'SSL/TLS'),
                AppMenuEntry(value: EncryptionType.starttls, label: 'STARTTLS'),
                AppMenuEntry(value: EncryptionType.none, label: 'None'),
              ],
              onChanged: (v) async {
                // Без шифрования пароль уходит открытым текстом (08.11.2026,
                // аудит безопасности) — только после явного согласия.
                if (v == EncryptionType.none && !await _confirmPlaintext()) return;
                if (!mounted) return;
                setState(() {
                  _portsEdited = true;
                  _smtpEncryption = v;
                  _applyStandardPort(_smtpPortController, _smtpStandardPorts, v);
                });
              },
            )),
          ],
        ),
      ],
    );
  }

  /// Exchange Online: вход в браузере Microsoft (пароль, второй фактор и
  /// условный доступ организации — у Microsoft).
  Widget _buildExchangeOnlineButton(ThemeData theme, AppLocalizations l10n, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: busy
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    ref.read(authProvider.notifier).loginExchangeOnline();
                  },
            icon: const Icon(AppIcons.window),
            label: Text(l10n.tr('loginExchangeOnline')),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(l10n.tr('loginExchangeOnlineHint'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  /// Ошибка входа и кнопка «что сделать».
  Widget _buildError(ThemeData theme, AppLocalizations l10n, String message, AuthErrorKind? kind) {
    final appPwUrl = switch (_kind) {
      MailKind.mailru => 'https://account.mail.ru/user/2-step-auth/passwords/',
      MailKind.icloud => 'https://account.apple.com/account/manage',
      _ when _appPwFor != null => _appPwUrlFor(_appPwFor!),
      _ => MailProviderDetect.appPasswordUrl(_email),
    };
    final imapUrl = MailProviderDetect.imapSettingsUrl(_email);
    final (String? label, IconData? icon, VoidCallback? action) = switch (kind) {
      AuthErrorKind.password => (l10n.tr('loginErrCheckPassword'), AppIcons.lock_reset, _checkPassword),
      AuthErrorKind.appPassword when appPwUrl != null =>
        (l10n.tr('loginErrAppPassword'), AppIcons.open_in_new, () => _open(appPwUrl)),
      AuthErrorKind.appPassword => (l10n.tr('loginErrCheckPassword'), AppIcons.lock_reset, _checkPassword),
      AuthErrorKind.imapDisabled when imapUrl != null =>
        (l10n.tr('loginErrImapSettings'), AppIcons.open_in_new, () => _open(imapUrl)),
      AuthErrorKind.network => (l10n.tr('retry'), AppIcons.refresh, _isOAuthKind ? _onOAuth : _onLogin),
      // Google не пускает новых пользователей — почта Gmail паролем
      // приложения (вход по паролю, IMAP).
      AuthErrorKind.googleUserCap when _reauth == null =>
        (l10n.tr('oauthGoogleUserCapAction'), AppIcons.key, _gmailAppPassword),
      _ => (null, null, null),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: Radii.chipAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.error, color: theme.colorScheme.onErrorContainer, size: 20),
              const SizedBox(width: Space.s),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer)),
                ),
              ),
            ],
          ),
          if (kind == AuthErrorKind.appPassword) ...[
            const SizedBox(height: Space.xs),
            Text(l10n.tr('loginErrAppPasswordHint'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer)),
          ],
          if (label != null && action != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onErrorContainer),
                icon: Icon(icon, size: 18),
                label: Text(label),
                onPressed: action,
              ),
            )
          else
            const SizedBox(height: Space.xs),
        ],
      ),
    );
  }

  /// Gmail паролем приложения вместо входа через Google (2.5.4): вход по
  /// паролю IMAP с серверами Gmail, подсказка и ссылка на страницу паролей
  /// приложений Google.
  void _gmailAppPassword() {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _resetForDomain();
      _manual = true;
      _askEmail = !_emailValid;
      _applyKind(MailKind.imap, preset: _gmailImap);
      _appPwFor = 'google';
      _showAdvanced = false;
      _step = _Step.method;
    });
    _focusPasswordSoon();
  }

  /// «Проверить пароль»: показать пароль и выделить его.
  void _checkPassword() {
    // Сохранённый пароль не раскрывается: сначала его нужно изменить.
    if (_savedPassword) {
      _passwordFocus.requestFocus();
      _passwordController.selection = TextSelection(baseOffset: 0, extentOffset: _passwordController.text.length);
      return;
    }
    setState(() => _showPassword = true);
    _passwordFocus.requestFocus();
    _passwordController.selection = TextSelection(baseOffset: 0, extentOffset: _passwordController.text.length);
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ════════════════════════ ОБРАБОТЧИКИ ════════════════════════

  /// Вид ошибки «Войти снова».
  AuthErrorKind? _reauthErrorKind;

  void _onOAuth() {
    HapticFeedback.mediumImpact();
    ref.read(authProvider.notifier).loginOAuth(_selectedType, loginHint: _emailValid ? _email : null);
  }

  void _onLogin() {
    if (_isOAuthKind && _reauth == null) {
      _onOAuth();
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    HapticFeedback.mediumImpact();
    if (_reauth != null) {
      unawaited(_onReauth());
      return;
    }

    final auth = ref.read(authProvider.notifier);
    final email = _email;
    switch (_kind) {
      case MailKind.exchange:
        auth.loginExchange(
          email: email,
          password: _passwordController.text,
          username: _usernameController.text.trim().isNotEmpty ? _usernameController.text.trim() : null,
          domain: _domainController.text.trim().isNotEmpty ? _domainController.text.trim() : null,
          server: _cleanServer(_serverController.text).isNotEmpty ? _cleanServer(_serverController.text) : null,
        );
      case MailKind.imap:
        // Адрес ввели уже на шаге 2 (плитка «IMAP») — серверы по нему.
        if (_imapServerController.text.trim().isEmpty) {
          final p = _imapPreset().preset;
          if (p != null) {
            _imapServerController.text = p.imapHost;
            _imapPortController.text = '${p.imapPort}';
            _imapEncryption = p.imapEncryption;
            if (_smtpServerController.text.trim().isEmpty) {
              _smtpServerController.text = p.smtpHost;
              _smtpPortController.text = '${p.smtpPort}';
              _smtpEncryption = p.smtpEncryption;
            }
          }
        }
        auth.loginImap(
          email: email,
          password: _passwordText,
          imapServer: _cleanServer(_imapServerController.text),
          imapPort: int.tryParse(_imapPortController.text) ?? AppConstants.defaultImapPort,
          smtpServer: _cleanServer(_smtpServerController.text),
          smtpPort: int.tryParse(_smtpPortController.text) ?? AppConstants.defaultSmtpPort,
          imapEncryption: _imapEncryption,
          smtpEncryption: _smtpEncryption,
          appPassword: _appPwFor != null || (_guess?.appPassword ?? false),
          username: _showImapLogin ? _imapLoginController.text.trim() : null,
          // Серверы додуманы (imap./smtp. домена, догадка) — порты и
          // шифрование подбираются, если указанные не отвечают.
          probePorts: !_portsEdited,
        );
      case MailKind.mailru:
        // Серверы Mail.ru (все домены: mail.ru, bk.ru, inbox.ru, list.ru,
        // internet.ru) — IMAP 993 и SMTP 465 по SSL.
        auth.loginImap(
          email: email,
          password: _passwordController.text,
          imapServer: 'imap.mail.ru',
          imapPort: 993,
          smtpServer: 'smtp.mail.ru',
          smtpPort: 465,
          imapEncryption: EncryptionType.ssl,
          smtpEncryption: EncryptionType.ssl,
          appPassword: true,
        );
      case MailKind.icloud:
        // Серверы Apple: IMAP 993 по SSL, SMTP 587 со STARTTLS; календарь
        // и контакты — по CalDAV/CardDAV тем же паролем.
        auth.loginImap(
          email: email,
          password: _passwordController.text.trim(),
          imapServer: 'imap.mail.me.com',
          imapPort: 993,
          smtpServer: 'smtp.mail.me.com',
          smtpPort: 587,
          imapEncryption: EncryptionType.ssl,
          smtpEncryption: EncryptionType.starttls,
          appPassword: true,
        );
      case MailKind.google || MailKind.microsoft || MailKind.yandex:
        _onOAuth();
    }
  }

  /// «Войти снова»: изменённые логин, домен и серверы — в ящик, пароль — в
  /// защищённое хранилище, подключение — заново. Ошибка — на экране, успех —
  /// экран закрывается с обновлённым ящиком.
  Future<void> _onReauth() async {
    final a = _reauth!;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _reauthBusy = true;
      _reauthError = null;
      _reauthErrorKind = null;
    });
    var account = a;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    if (_selectedType == AccountType.exchange) {
      final login = opt(_usernameController) ?? a.username;
      final domain = opt(_domainController);
      final server = _cleanServer(opt(_serverController) ?? (a.exchangeServer ?? ''));
      final serverChanged = server.isNotEmpty && server != (a.exchangeServer ?? '');
      if (login != a.username || domain != a.domain || serverChanged) {
        account = a.copyWith(
          username: login,
          domain: domain,
          exchangeServer: serverChanged ? server : a.exchangeServer,
          // EWS-ящик: адрес веб-служб — от нового сервера.
          ewsUrl: serverChanged && a.usesEws ? EwsService.ewsUrlFromServer(server) : a.ewsUrl,
        );
        await ref.read(accountsProvider.notifier).updateAccount(account);
        if (serverChanged) ref.read(ewsServiceProvider).clearClientCache(a.id);
      }
    } else {
      final imap = opt(_imapServerController) ?? a.imapServer;
      final smtp = opt(_smtpServerController) ?? a.smtpServer;
      final imapPort = int.tryParse(_imapPortController.text.trim()) ?? a.imapPort;
      final smtpPort = int.tryParse(_smtpPortController.text.trim()) ?? a.smtpPort;
      // Логин IMAP (2.6.0): пусто — адрес ящика.
      final login = _showImapLogin ? (opt(_imapLoginController) ?? a.email) : a.username;
      if (login != a.username ||
          imap != a.imapServer ||
          smtp != a.smtpServer ||
          imapPort != a.imapPort ||
          smtpPort != a.smtpPort ||
          _imapEncryption != a.imapEncryption ||
          _smtpEncryption != a.smtpEncryption) {
        account = a.copyWith(
          username: login,
          imapServer: imap,
          smtpServer: smtp,
          imapPort: imapPort,
          smtpPort: smtpPort,
          imapEncryption: _imapEncryption,
          smtpEncryption: _smtpEncryption,
        );
        await ref.read(accountsProvider.notifier).updateAccount(account);
      }
    }
    // Новые данные входа и режим совместимости — только с новым подключением.
    ref.read(mailEngineServiceProvider).disconnect(a.id);
    final err = await ref.read(authProvider.notifier).reauthenticate(account, password: _passwordText);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _reauthBusy = false;
        _reauthError = err == 'password' ? l10n.tr('invalidPassword') : err;
        _reauthErrorKind = err == 'password'
            ? AuthErrorKind.password
            : authErrorKindOf(err, appPassword: MailProviderDetect.byDomain(a.email)?.appPassword ?? false);
      });
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    context.pop(account);
  }

  String _providerName(AccountType t) {
    switch (t) {
      case AccountType.google:
        return 'Google';
      case AccountType.yandex:
        return AppLocalizations.of(context).tr('yandex');
      case AccountType.yahoo:
        return 'Yahoo';
      case AccountType.mailru:
        return 'Mail.ru';
      case AccountType.outlook:
        return 'Microsoft';
      default:
        return '';
    }
  }

  Color _providerColor(AccountType t) {
    switch (t) {
      case AccountType.google:
        return const Color(0xFF4285F4);
      case AccountType.yandex:
        return const Color(0xFFFC3F1D);
      case AccountType.yahoo:
        return const Color(0xFF720E9E);
      case AccountType.mailru:
        return const Color(0xFF005FF9);
      case AccountType.outlook:
        return const Color(0xFF0078D4);
      default:
        return AppColors.primaryBlue;
    }
  }

  IconData _providerIcon(AccountType t) {
    switch (t) {
      case AccountType.google:
        return AppIcons.g_mobiledata;
      case AccountType.yandex:
        return AppIcons.signal_cellular_alt;
      case AccountType.yahoo:
        return AppIcons.mail;
      case AccountType.mailru:
        return AppIcons.alternate_email;
      case AccountType.outlook:
        return AppIcons.window;
      default:
        return AppIcons.login;
    }
  }
}
