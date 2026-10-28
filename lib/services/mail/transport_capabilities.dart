// lib/services/mail/transport_capabilities.dart
// Этап 7П — паритет действий по транспортам.
// Сводная матрица возможностей EWS / EAS / IMAP+SMTP. UI и сервисы опираются
// на флаги, чтобы недоступные действия скрывались/пропускались явно, а не
// падали «тихо».

import '../../data/models/account_model.dart';

class TransportCapabilities {
  final bool serverMove;       // перемещение между папками на сервере
  final bool serverFlag;       // флаг на сервере
  final bool serverDelete;     // удаление на сервере
  final bool serverMarkRead;   // отметка прочитанным на сервере
  final bool serverSearch;     // серверный поиск
  final bool serverFolders;    // создание/переименование/удаление папок на сервере
  final bool serverRules;      // серверные правила обработки (inbox rules)
  final bool recall;           // отзыв отправленного письма
  final bool freeBusy;         // занятость календаря (free/busy)
  final bool gal;              // глобальная адресная книга
  final bool push;             // push/IDLE/Ping
  final bool meetingResponse;  // ответ на приглашения-встречи

  const TransportCapabilities({
    required this.serverMove,
    required this.serverFlag,
    required this.serverDelete,
    required this.serverMarkRead,
    required this.serverSearch,
    required this.serverFolders,
    required this.serverRules,
    required this.recall,
    required this.freeBusy,
    required this.gal,
    required this.push,
    this.meetingResponse = false,
  });

  /// EWS / Exchange — наиболее полный набор.
  ///
  /// Отзыва нет: в EWS нет операции отзыва письма. Прежняя кнопка создавала
  /// служебное письмо IPM.Outlook.Recall без получателей и ссылки на
  /// исходное — сервер его принимал, приложение сообщало «Письмо отозвано»,
  /// а у получателей ничего не менялось. Отзыв работает только из Outlook
  /// (облачный отзыв Exchange Online), честнее не показывать кнопку.
  static const ews = TransportCapabilities(
    serverMove: true, serverFlag: true, serverDelete: true, serverMarkRead: true,
    serverSearch: true, serverFolders: true, serverRules: true,
    recall: false, freeBusy: true, gal: true, push: true, meetingResponse: true,
  );

  /// EAS / ActiveSync — почти всё, кроме отзыва и серверных правил
  /// (в протоколе ActiveSync таких команд нет).
  static const eas = TransportCapabilities(
    serverMove: true, serverFlag: true, serverDelete: true, serverMarkRead: true,
    serverSearch: true, serverFolders: true, serverRules: false,
    recall: false, freeBusy: true, gal: true, push: true, meetingResponse: true,
  );

  /// IMAP + SMTP — стандартные почтовые операции, без Exchange-специфики.
  static const imap = TransportCapabilities(
    serverMove: true, serverFlag: true, serverDelete: true, serverMarkRead: true,
    serverSearch: true, serverFolders: true, serverRules: false,
    recall: false, freeBusy: false, gal: false, push: true, // push ~ IMAP IDLE
  );

  static TransportCapabilities forAccount(AccountModel account) {
    if (account.usesEws) return ews;
    if (account.usesEas) return eas;
    return imap; // IMAP/SMTP (включая google/yandex/yahoo/mailru через IMAP)
  }
}
