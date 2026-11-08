import Flutter
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif

/// Виджеты iPhone (цель OgnelissWidgets, WidgetKit): канал 'ogneliss/widget'
/// — тот же, что на Android.
///  · «save» {key, json} — данные виджета в общий контейнер App Group
///    (UserDefaults group.com.ogneliss.mail): расширение виджетов читает их
///    оттуда, своих данных у него нет;
///  · «refresh» — перерисовать виджеты (WidgetCenter);
///  · «take» — какой экран открыть по нажатию на виджет.
/// Нажатие на виджет открывает ссылку com.ogneliss.mail://widget?t=<экран>;
/// AppDelegate передаёт её сюда ([handle]), Dart получает «open» и забирает
/// экран тем же «take». Без цели виджетов и App Group всё это безвредно:
/// данные просто никто не читает.
enum WidgetBridgePlugin {
  static let appGroup = "group.com.ogneliss.mail"
  private static var mainChannel: FlutterMethodChannel?
  private static var pending: String?

  /// [main] — основной движок (нажатия на виджет идут только в него);
  /// фоновый движок (синхронизация) только сохраняет данные.
  static func register(with messenger: FlutterBinaryMessenger, main: Bool) {
    let channel = FlutterMethodChannel(name: "ogneliss/widget", binaryMessenger: messenger)
    if main { mainChannel = channel }
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "save":
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String,
           let json = args["json"] as? String {
          UserDefaults(suiteName: appGroup)?.set(json, forKey: key)
        }
        result(nil)
      case "refresh":
        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        #endif
        result(nil)
      case "take":
        let t = pending
        pending = nil
        result(t)
      case "takeMailQueue":
        // «Прочитано» и «В архив», нажатые в виджете «Почта» (08.11.2026):
        // очередь кладёт MailActionIntent расширения в общую группу.
        let d = UserDefaults(suiteName: appGroup)
        let q = d?.string(forKey: "widget_mail_queue")
        d?.removeObject(forKey: "widget_mail_queue")
        result(q)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Siri и «Команды» (1.9.x): открыть экран тем же путём, что нажатие на
  /// виджет. Dart ещё не запущен — экран ждёт, пока его заберут «take».
  static func open(_ type: String) {
    pending = type
    mainChannel?.invokeMethod("open", arguments: nil)
  }

  /// Экран с параметрами: «compose?to=…&subject=…». Пустые не передаются;
  /// «&», «=», «+» в значениях кодируются (Dart читает «+» как пробел).
  static func screen(_ path: String, _ params: [(String, String?)]) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+?#")
    let query = params.compactMap { item -> String? in
      guard let v = item.1?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty,
            let e = v.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
      return "\(item.0)=\(e)"
    }.joined(separator: "&")
    return query.isEmpty ? path : "\(path)?\(query)"
  }

  /// Ссылка из виджета. true — ссылка наша (обработана).
  static func handle(_ url: URL) -> Bool {
    guard url.scheme == "com.ogneliss.mail", url.host == "widget" else { return false }
    let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "t" })?.value
    guard let type = t, !type.isEmpty else { return true }
    pending = type
    mainChannel?.invokeMethod("open", arguments: nil)
    return true
  }
}

#if canImport(AppIntents)
// MARK: Siri и «Команды» (1.9.x, просьба владельца 31.10.2026)
//
// App Intents — действия в приложении «Команды», в Spotlight и в Siri по
// фразам ниже (AppShortcutsProvider). Возможности (entitlements) и
// настройки Xcode не нужны: метаданные действий Xcode собирает сам при
// сборке цели Runner. Каждое действие открывает приложение
// (openAppWhenRun) и передаёт экран в Dart — как нажатие на виджет
// (lib/core/platform/assistant_actions.dart). Названия и вопросы — из
// таблицы InfoPlist (ключи ios_siri* в assets/l10n, все языки
// приложения); фразы Siri — здесь, по-английски и по-русски
// (docs/guides/IOS_SHORTCUTS.md). Код — в уже существующем файле цели:
// новые файлы потребовали бы правки project.pbxproj.

@available(iOS 16.0, *)
struct OgnelissComposeIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriCompose", defaultValue: "New email", table: "InfoPlist")
  static var openAppWhenRun = true

  @Parameter(title: LocalizedStringResource("siriTo", defaultValue: "To", table: "InfoPlist"))
  var recipient: String?

  @Parameter(title: LocalizedStringResource("siriSubject", defaultValue: "Subject", table: "InfoPlist"))
  var subject: String?

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open(WidgetBridgePlugin.screen("compose", [("to", recipient), ("subject", subject)]))
    return .result()
  }
}

/// «Созвон с Анной завтра в 15» — разбирает QuickEventParser, редактор
/// встречи открывается заполненным.
@available(iOS 16.0, *)
struct OgnelissEventIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriEvent", defaultValue: "New meeting", table: "InfoPlist")
  static var openAppWhenRun = true

  @Parameter(
    title: LocalizedStringResource("siriPhrase", defaultValue: "What and when", table: "InfoPlist"),
    requestValueDialog: IntentDialog(LocalizedStringResource("siriEventAsk", defaultValue: "What is the meeting, and when?", table: "InfoPlist")))
  var phrase: String

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open(WidgetBridgePlugin.screen("event", [("phrase", phrase)]))
    return .result()
  }
}

/// «Позвонить маме завтра в 10» — разбирает TaskQuickParser.
@available(iOS 16.0, *)
struct OgnelissReminderIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriReminder", defaultValue: "New reminder", table: "InfoPlist")
  static var openAppWhenRun = true

  @Parameter(
    title: LocalizedStringResource("siriPhrase", defaultValue: "What and when", table: "InfoPlist"),
    requestValueDialog: IntentDialog(LocalizedStringResource("siriReminderAsk", defaultValue: "What should I remind you of, and when?", table: "InfoPlist")))
  var phrase: String

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open(WidgetBridgePlugin.screen("reminder", [("phrase", phrase)]))
    return .result()
  }
}

@available(iOS 16.0, *)
struct OgnelissSearchIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriSearch", defaultValue: "Search mail", table: "InfoPlist")
  static var openAppWhenRun = true

  @Parameter(
    title: LocalizedStringResource("siriQuery", defaultValue: "Search for", table: "InfoPlist"),
    requestValueDialog: IntentDialog(LocalizedStringResource("siriSearchAsk", defaultValue: "What should I search for?", table: "InfoPlist")))
  var query: String

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open(WidgetBridgePlugin.screen("search", [("q", query)]))
    return .result()
  }
}

@available(iOS 16.0, *)
struct OgnelissMyDayIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriMyDay", defaultValue: "My day", table: "InfoPlist")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open("myday")
    return .result()
  }
}

@available(iOS 16.0, *)
struct OgnelissUnreadIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriUnread", defaultValue: "Unread", table: "InfoPlist")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open("unread")
    return .result()
  }
}

@available(iOS 16.0, *)
struct OgnelissVipIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("siriVip", defaultValue: "Mail from VIPs", table: "InfoPlist")
  static var openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    WidgetBridgePlugin.open("vip")
    return .result()
  }
}

/// Фразы Siri. В каждой — название приложения (так требует iOS); параметры
/// (фраза встречи, запрос) Siri спрашивает следом.
@available(iOS 16.0, *)
struct OgnelissAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OgnelissComposeIntent(),
      phrases: [
        "New email in \(.applicationName)",
        "Write an email in \(.applicationName)",
        "\(.applicationName) new email",
        "Новое письмо в \(.applicationName)",
        "Написать письмо в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriCompose", defaultValue: "New email", table: "InfoPlist"),
      systemImageName: "square.and.pencil")
    AppShortcut(
      intent: OgnelissEventIntent(),
      phrases: [
        "New meeting in \(.applicationName)",
        "Create a meeting in \(.applicationName)",
        "Новая встреча в \(.applicationName)",
        "Создать встречу в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriEvent", defaultValue: "New meeting", table: "InfoPlist"),
      systemImageName: "calendar.badge.plus")
    AppShortcut(
      intent: OgnelissReminderIntent(),
      phrases: [
        "New reminder in \(.applicationName)",
        "Remind me with \(.applicationName)",
        "Новое напоминание в \(.applicationName)",
        "Напомни в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriReminder", defaultValue: "New reminder", table: "InfoPlist"),
      systemImageName: "checklist")
    AppShortcut(
      intent: OgnelissMyDayIntent(),
      phrases: [
        "My day in \(.applicationName)",
        "Мой день в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriMyDay", defaultValue: "My day", table: "InfoPlist"),
      systemImageName: "sun.max")
    AppShortcut(
      intent: OgnelissUnreadIntent(),
      phrases: [
        "Unread mail in \(.applicationName)",
        "Show unread in \(.applicationName)",
        "Непрочитанные в \(.applicationName)",
        "Непрочитанные письма в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriUnread", defaultValue: "Unread", table: "InfoPlist"),
      systemImageName: "envelope.badge")
    AppShortcut(
      intent: OgnelissVipIntent(),
      phrases: [
        "Mail from VIPs in \(.applicationName)",
        "VIP mail in \(.applicationName)",
        "Письма от VIP в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriVip", defaultValue: "Mail from VIPs", table: "InfoPlist"),
      systemImageName: "star")
    AppShortcut(
      intent: OgnelissSearchIntent(),
      phrases: [
        "Search mail in \(.applicationName)",
        "Search \(.applicationName)",
        "Найти в почте \(.applicationName)",
        "Поиск в \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("siriSearch", defaultValue: "Search mail", table: "InfoPlist"),
      systemImageName: "magnifyingglass")
  }
}
#endif
