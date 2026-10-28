// lib/core/constants/exchange_feature.dart
// Exchange (ActiveSync и EWS) — выключатель сборки (1.8.5, решение владельца
// 28.10.2026): протокол Exchange ActiveSync лицензирует Microsoft; пока нет
// ответа Microsoft о лицензии, приложение выходит без Exchange. Включить:
// --dart-define=OGNELISS_EXCHANGE=true (код Exchange остаётся в проекте).
//
// Без Exchange: способа входа «Exchange» нет, адрес, похожий на Exchange,
// подключается по IMAP; уже добавленные ящики Exchange скрыты (не
// синхронизируются, данные на устройстве не удаляются) — вернутся в сборке
// с Exchange.

import '../../data/models/account_model.dart' show AccountType;

const bool kExchangeEnabled = bool.fromEnvironment('OGNELISS_EXCHANGE', defaultValue: true);

/// Ящик этого типа скрыт в сборке без Exchange.
bool exchangeHidden(AccountType t) =>
    !kExchangeEnabled && (t == AccountType.exchange || t == AccountType.activesync || t == AccountType.corporate);
