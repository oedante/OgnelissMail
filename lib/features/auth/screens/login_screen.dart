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

import '../../../core/constants/exchange_feature.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
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
import '../../../services/mail/oauth/direct_oauth.dart' show DirectOAuth;
import '../../../widgets/common/app_logo.dart';
import '../../../widgets/common/eas_compat_switch.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/help_hint.dart' show TitleWithHelp;
import '../../mail/providers/mail_providers.dart';
import '../providers/auth_provider.dart';
import '../widgets/certificate_trust_dialog.dart';

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
  final _domainController = TextEditingController(text: AppConstants.defaultDomain);
  final _serverController = TextEditingController(text: AppConstants.defaultExchangeServer);
  final _imapServerController = TextEditingController();
  final _imapPortController = TextEditingController(text: AppConstants.defaultImapPort.toString());
  final _smtpServerController = TextEditingController();
  final _smtpPortController = TextEditingController(text: AppConstants.defaultSmtpPort.toString());
  final _passwordFocus = FocusNode();

  bool _showPassword = false;
  bool _showAdvanced = false;
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
  final _formKey = GlobalKey<FormState>();

  /// Шаг входа (1.8.0).
  _Step _step = _Step.address;

  /// Идёт проверка адреса («Ищем настройки почты…»).
  bool _detecting = false;

  /// Что узнали по адресу (null — способ выбран вручную или «Войти снова»).
  MailGuess? _guess;

  /// Способ выбран вручную («Другой способ входа»).
  bool _manual = false;

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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();
    final rid = widget.reauthAccountId;
    if (rid != null) {
      final a = ref.read(accountsProvider).where((x) => x.id == rid).firstOrNull;
      if (a != null) _fillFrom(a);
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

  /// Поля — из ящика («Войти снова»).
  void _fillFrom(AccountModel a) {
    _reauth = a;
    _step = _Step.method;
    final exchange = a.isMsExchange || a.usesEas || a.usesEws;
    _selectedType = exchange ? AccountType.exchange : AccountType.imap;
    _emailController.text = a.email;
    _usernameController.text = a.username;
    _domainController.text = a.domain ?? '';
    _serverController.text = a.exchangeServer ?? '';
    _imapServerController.text = a.imapServer ?? '';
    _imapPortController.text = '${a.imapPort ?? AppConstants.defaultImapPort}';
    _smtpServerController.text = a.smtpServer ?? '';
    _smtpPortController.text = '${a.smtpPort ?? AppConstants.defaultSmtpPort}';
    _imapEncryption = a.imapEncryption ?? _imapEncryption;
    _smtpEncryption = a.smtpEncryption ?? _smtpEncryption;
    _filledFor = MailProviderDetect.domainOf(a.email);
  }

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

  /// Адрес похож на настоящий (на шаге 2 тогда не нужно поле адреса).
  bool get _emailValid => MailProviderDetect.domainOf(_email) != null && !_email.startsWith('@');

  /// Выбрать способ входа (и серверы IMAP, если они известны).
  void _applyKind(MailKind k, {ImapPreset? preset}) {
    _icloud = k == MailKind.icloud;
    _selectedType = switch (k) {
      MailKind.google => AccountType.google,
      MailKind.microsoft => AccountType.outlook,
      MailKind.yandex => AccountType.yandex,
      MailKind.mailru => AccountType.mailru,
      MailKind.icloud || MailKind.imap => AccountType.imap,
      MailKind.exchange => AccountType.exchange,
    };
    if (preset != null) {
      _imapServerController.text = preset.imapHost;
      _imapPortController.text = '${preset.imapPort}';
      _imapEncryption = preset.imapEncryption;
      _smtpServerController.text = preset.smtpHost;
      _smtpPortController.text = '${preset.smtpPort}';
      _smtpEncryption = preset.smtpEncryption;
    }
    // Серверы IMAP неизвестны или это догадка — «Расширенные настройки»
    // открыты сразу: их стоит проверить.
    _showAdvanced = k == MailKind.imap && (preset == null || !(_guess?.sure ?? true));
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

  /// «Далее»: узнать почту по адресу и перейти ко входу.
  Future<void> _onNext() async {
    final l10n = AppLocalizations.of(context);
    if (!_emailValid) {
      setState(() => _addressError = l10n.tr('invalidEmail'));
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
      guess = MailGuess(MailKind.imap,
          sure: false,
          imap: ImapPreset(
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
      _manual = false;
      _applyKind(guess.kind, preset: guess.imap);
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
    final k = await showActionSheet<MailKind>(
      context,
      title: l10n.tr('loginChooseMethod'),
      items: [
        if (kExchangeEnabled)
          ActionSheetItem(
              icon: AppIcons.business, label: l10n.tr('exchange'), subtitle: l10n.tr('loginKindExchangeDesc'), value: MailKind.exchange),
        ActionSheetItem(icon: AppIcons.g_mobiledata, label: 'Google', subtitle: l10n.tr('loginKindGoogleDesc'), value: MailKind.google),
        ActionSheetItem(icon: AppIcons.window, label: 'Microsoft', subtitle: l10n.tr('loginKindMicrosoftDesc'), value: MailKind.microsoft),
        ActionSheetItem(
            icon: AppIcons.signal_cellular_alt, label: l10n.tr('yandex'), subtitle: l10n.tr('loginKindYandexDesc'), value: MailKind.yandex),
        ActionSheetItem(icon: AppIcons.alternate_email, label: 'Mail.ru', subtitle: l10n.tr('loginKindMailruDesc'), value: MailKind.mailru),
        ActionSheetItem(icon: AppIcons.cloud, label: 'iCloud', subtitle: l10n.tr('loginKindIcloudDesc'), value: MailKind.icloud),
        ActionSheetItem(
            icon: AppIcons.settings_ethernet, label: l10n.tr('loginKindImap'), subtitle: l10n.tr('loginKindImapDesc'), value: MailKind.imap),
      ],
    );
    if (k == null || !mounted) return;
    setState(() {
      _resetForDomain();
      // IMAP вручную: серверы — из того, что узнали, или из таблицы служб.
      final preset = k == MailKind.imap
          ? (_guess?.imap ?? ImapPreset.fromTable(AppConstants.serverConfigForEmail(_email)))
          : null;
      _manual = true;
      _applyKind(k, preset: preset);
      _step = _Step.method;
    });
    unawaited(HapticFeedback.selectionClick());
    _focusPasswordSoon();
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
      if (next.status == AuthStatus.success) {
        HapticFeedback.mediumImpact();
        if (widget.isAddMode && context.canPop()) {
          context.pop(); // возврат в настройки после добавления аккаунта
        } else {
          context.go('/mail');
        }
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
        const SizedBox(height: Space.s),
        Center(
          child: TextButton(
            onPressed: _detecting ? null : _chooseMethod,
            child: Text(l10n.tr('loginOtherMethod')),
          ),
        ),

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
            when !reauth && l10n.isRussian && (kind == MailKind.exchange || kind == MailKind.imap)) ...[
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
  String _kindTitle(AppLocalizations l10n, MailKind k) => switch (k) {
        MailKind.exchange => l10n.tr('exchange'),
        MailKind.google => 'Google',
        MailKind.microsoft => (_guess?.microsoft365 ?? false) ? 'Microsoft 365' : 'Microsoft',
        MailKind.yandex => l10n.tr('yandex'),
        MailKind.mailru => 'Mail.ru',
        MailKind.icloud => 'iCloud',
        MailKind.imap => l10n.tr('loginKindImap'),
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
          child: Icon(_kindIcon(kind), size: 32, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: Space.m),
        Text(_kindTitle(l10n, kind), style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        if (_emailValid) ...[
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
    final appPwKind = kind == MailKind.mailru || kind == MailKind.icloud;
    final appPwHint = !appPwKind && (_guess?.appPassword ?? false);
    final appPwUrl = switch (kind) {
      MailKind.mailru => 'https://account.mail.ru/user/2-step-auth/passwords/',
      MailKind.icloud => 'https://account.apple.com/account/manage',
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
          Text(l10n.tr(kind == MailKind.mailru ? 'mailruAppPwTitle' : 'icloudAppPwTitle'), style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(l10n.tr(kind == MailKind.mailru ? 'mailruAppPwHint' : 'icloudAppPwHint'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(AppIcons.open_in_new, size: 18),
              label: Text(l10n.tr(kind == MailKind.mailru ? 'mailruAppPwCreate' : 'icloudAppPwCreate')),
              onPressed: () => _open(appPwUrl!),
            ),
          ),
          const SizedBox(height: Space.s),
        ],

        // Адрес — если его нет в шапке (способ выбрали до ввода адреса).
        if (!_emailValid) ...[
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

        // Пароль (у Mail.ru и iCloud — пароль приложения).
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          decoration: InputDecoration(
            labelText: switch (kind) {
              MailKind.mailru => l10n.tr('mailruAppPwLabel'),
              MailKind.icloud => l10n.tr('icloudAppPwLabel'),
              _ => l10n.tr('password'),
            },
            hintText: kind == MailKind.icloud ? 'xxxx-xxxx-xxxx-xxxx' : null,
            prefixIcon: Icon(appPwKind ? AppIcons.key : AppIcons.lock),
            suffixIcon: IconButton(
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
          _buildNote(theme, l10n.tr('loginAppPasswordNote')),
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
                    Text(l10n.tr('advancedSettings'), style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary)),
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
          DropdownButtonFormField<PinningMode>(
            initialValue: _pinningMode,
            decoration: InputDecoration(labelText: l10n.certValidation, prefixIcon: const Icon(AppIcons.verified_user)),
            isExpanded: true,
            items: [
              DropdownMenuItem(value: PinningMode.trustStore, child: Text(l10n.pinTrustStore)),
              DropdownMenuItem(value: PinningMode.pinned, child: Text(l10n.pinStrict)),
              DropdownMenuItem(value: PinningMode.off, child: Text(l10n.pinAcceptAll)),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _pinningMode = v);
                ref.read(certPinningProvider).setMode(v);
              }
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
            Expanded(flex: 2, child: TextFormField(controller: _imapPortController, decoration: InputDecoration(labelText: 'IMAP ${l10n.tr('port')}'), keyboardType: TextInputType.number)),
            const SizedBox(width: Space.m),
            Expanded(flex: 3, child: DropdownButtonFormField<EncryptionType>(
              // Шифрование подставляется и по адресу — ключ пересоздаёт
              // поле, чтобы показать новое значение.
              key: ValueKey(_imapEncryption),
              initialValue: _imapEncryption,
              decoration: InputDecoration(labelText: l10n.tr('encryption')),
              items: const [
                DropdownMenuItem(value: EncryptionType.ssl, child: Text('SSL/TLS')),
                DropdownMenuItem(value: EncryptionType.starttls, child: Text('STARTTLS')),
                DropdownMenuItem(value: EncryptionType.none, child: Text('None')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
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
            Expanded(flex: 2, child: TextFormField(controller: _smtpPortController, decoration: InputDecoration(labelText: 'SMTP ${l10n.tr('port')}'), keyboardType: TextInputType.number)),
            const SizedBox(width: Space.m),
            Expanded(flex: 3, child: DropdownButtonFormField<EncryptionType>(
              key: ValueKey(_smtpEncryption),
              initialValue: _smtpEncryption,
              decoration: InputDecoration(labelText: l10n.tr('encryption')),
              items: const [
                DropdownMenuItem(value: EncryptionType.ssl, child: Text('SSL/TLS')),
                DropdownMenuItem(value: EncryptionType.starttls, child: Text('STARTTLS')),
                DropdownMenuItem(value: EncryptionType.none, child: Text('None')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
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

  /// «Проверить пароль»: показать пароль и выделить его.
  void _checkPassword() {
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
        auth.loginImap(
          email: email,
          password: _passwordController.text,
          imapServer: _cleanServer(_imapServerController.text),
          imapPort: int.tryParse(_imapPortController.text) ?? AppConstants.defaultImapPort,
          smtpServer: _cleanServer(_smtpServerController.text),
          smtpPort: int.tryParse(_smtpPortController.text) ?? AppConstants.defaultSmtpPort,
          imapEncryption: _imapEncryption,
          smtpEncryption: _smtpEncryption,
          appPassword: _guess?.appPassword ?? false,
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
      if (imap != a.imapServer ||
          smtp != a.smtpServer ||
          imapPort != a.imapPort ||
          smtpPort != a.smtpPort ||
          _imapEncryption != a.imapEncryption ||
          _smtpEncryption != a.smtpEncryption) {
        account = a.copyWith(
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
    final err = await ref.read(authProvider.notifier).reauthenticate(account, password: _passwordController.text);
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
