import Flutter
import Foundation
#if canImport(WidgetKit)
import WidgetKit
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
