import Flutter
import UIKit
import SwiftUI
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif
import UserNotifications
import flutter_local_notifications
import workmanager_apple

// Точка входа iOS.
//  · Плагины пакетов — GeneratedPluginRegistrant; свои каналы (календарь и
//    контакты устройства) — registerAppChannels, в основном и в фоновом движке.
//  · Фоновая проверка почты — BGTaskScheduler через workmanager: задача
//    «periodic_sync» (тот же идентификатор в Info.plist и в Dart,
//    lib/services/background/background_service.dart). Когда запускать, решает
//    iOS: обычно не чаще раза в 15–30 минут и реже при экономии заряда.
//    Плюс задача обработки «processing_sync» (BGProcessingTask) — ещё
//    пробуждения, чаще ночью и на зарядке.
//  · Уведомления — flutter_local_notifications; показываются и при открытом
//    приложении.
//  · Сигналы сервера (1.7.2): канал 'ogneliss/push' — токен уведомлений
//    Apple для «будильника» (server/push-relay) и пробуждение по его
//    сигналу: проверку почты делает Dart (PushWakeService). Нужны
//    Push Notifications у цели Runner в Xcode (docs/guides/IOS_PUSH_SETUP.md).
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppDelegate.firstLaunchCleanup()
    AppDelegate.excludeDataFromBackup()
    GeneratedPluginRegistrant.register(with: self)
    AppDelegate.registerAppChannels(self)
    if let r = self.registrar(forPlugin: "OgnelissPlatform") {
      AppDelegate.registerPlatformChannel(r.messenger())
    }
    // Виджеты iPhone: данные — в App Group, нажатия — сюда (WidgetBridgePlugin).
    if let r = self.registrar(forPlugin: "OgnelissWidget") {
      WidgetBridgePlugin.register(with: r.messenger(), main: true)
    }
    // Сигналы сервера «проверь почту» (1.7.2).
    if let r = self.registrar(forPlugin: "OgnelissPush") {
      AppDelegate.registerPushChannel(r.messenger())
    }
    // Перевод писем на устройстве (1.9.x, Apple Translation, iOS 18+).
    if let r = self.registrar(forPlugin: "OgnelissTranslate") {
      TranslationBridge.register(r.messenger())
    }
    // Холодный запуск нажатием на виджет.
    if let url = launchOptions?[.url] as? URL { _ = WidgetBridgePlugin.handle(url) }

    // Фоновый движок (workmanager, действия из уведомлений) — те же плагины
    // и каналы, иначе синхронизация в фоне не нашла бы, например, хранилище.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      AppDelegate.registerAppChannels(registry)
      // Фоновая синхронизация тоже обновляет виджеты.
      if let r = registry.registrar(forPlugin: "OgnelissWidget") {
        WidgetBridgePlugin.register(with: r.messenger(), main: false)
      }
    }
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "periodic_sync",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    // Дополнительные пробуждения (1.6.42): BGProcessingTask «processing_sync»
    // — разовая, заявку выставляет Dart (при запуске, сворачивании и после
    // выполнения). Обработчик регистрируется здесь, до конца запуска.
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "processing_sync")

    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Нажатие на виджет (com.ogneliss.mail://widget?t=…), когда приложение
  /// уже запущено. Остальные ссылки — плагинам (вход OAuth и т. п.).
  override func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if WidgetBridgePlugin.handle(url) { return true }
    return super.application(app, open: url, options: options)
  }

  // MARK: Сигналы сервера (1.7.2)

  static var pushChannel: FlutterMethodChannel?

  static func registerPushChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ogneliss/push", binaryMessenger: messenger)
    pushChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "register":
        UIApplication.shared.registerForRemoteNotifications()
        result(nil)
      case "unregister":
        UIApplication.shared.unregisterForRemoteNotifications()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Окружение APNs этой сборки: сборка из Xcode с профилем разработчика —
  /// sandbox (в профиле aps-environment = development); TestFlight и App
  /// Store — production (профиля в приложении нет).
  static let apnsEnvironment: String = {
    guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let text = String(data: data, encoding: .isoLatin1),
          let r = text.range(of: "<key>aps-environment</key>") else { return "production" }
    return text[r.upperBound...].prefix(80).contains("development") ? "sandbox" : "production"
  }()

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    AppDelegate.pushChannel?.invokeMethod("onToken", arguments: ["token": hex, "env": AppDelegate.apnsEnvironment])
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    AppDelegate.pushChannel?.invokeMethod("onError", arguments: error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// Сигнал «проверь почту» (в нём ключ "w"). Остальные уведомления —
  /// плагинам, как раньше.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard userInfo["w"] != nil else {
      super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
      return
    }
    AppDelegate.handleWake(completionHandler)
  }

  /// У iOS на сигнал ~30 с. Dart может быть ещё не готов (приложение
  /// запущено сигналом с нуля) — тогда повтор раз в секунду; через 27 с
  /// ответ iOS даётся в любом случае.
  static func handleWake(_ completion: @escaping (UIBackgroundFetchResult) -> Void) {
    var finished = false
    let deadline = Date().addingTimeInterval(26)
    func finish(_ r: UIBackgroundFetchResult) {
      if finished { return }
      finished = true
      completion(r)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 27) { finish(.noData) }
    func retry() {
      if Date() < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt() }
      } else {
        finish(.noData)
      }
    }
    func attempt() {
      if finished { return }
      guard let channel = pushChannel else { retry(); return }
      let left = Int(max(0, deadline.timeIntervalSinceNow) * 1000)
      channel.invokeMethod("onWake", arguments: ["deadlineMs": left]) { res in
        if let r = res as? String {
          finish(r == "newData" ? .newData : (r == "failed" ? .failed : .noData))
        } else {
          retry()
        }
      }
    }
    attempt()
  }

  /// Связка ключей iOS переживает удаление приложения: после переустановки
  /// в ней остались бы пароли, токены и ключ базы прежней установки (а сама
  /// база удалена). При первом запуске после установки — чистим.
  static func firstLaunchCleanup() {
    let flag = "ogneliss.installed.v1"
    if UserDefaults.standard.bool(forKey: flag) { return }
    for cls in [kSecClassGenericPassword, kSecClassInternetPassword, kSecClassKey, kSecClassCertificate] {
      SecItemDelete([kSecClass as String: cls] as CFDictionary)
    }
    UserDefaults.standard.set(true, forKey: flag)
  }

  /// Почта, вложения и журнал — не в резервные копии iCloud и компьютера
  /// (как на Android, где резервное копирование выключено): каталоги данных
  /// приложения помечаются «не копировать».
  static func excludeDataFromBackup() {
    let fm = FileManager.default
    for dir in [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory] {
      guard var url = fm.urls(for: dir, in: .userDomainMask).first else { continue }
      try? fm.createDirectory(at: url, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
  }

  /// Незавершённые «доделать после сворачивания» (beginBackgroundTask): одну
  /// задачу нельзя завершить дважды — и из Dart, и по истечении времени.
  /// Всё — на главном потоке (обработчик канала и истечения iOS вызывает там).
  static var backgroundTasks = Set<Int>()

  static func endBackground(_ task: UIBackgroundTaskIdentifier) {
    guard task != .invalid, backgroundTasks.remove(task.rawValue) != nil else { return }
    UIApplication.shared.endBackgroundTask(task)
  }

  /// MethodChannel 'ogneliss/platform': состояние фоновой работы для журнала
  /// и экрана разрешений (Обновление контента, режим энергосбережения,
  /// разрешение на уведомления, модель устройства).
  static func registerPlatformChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ogneliss/platform", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "beginBackgroundTask":
        // 1.6.44: свернули посреди синхронизации или отправки — iOS даёт
        // ~30 с доделать начатое (Dart отдаёт время, как только закончил,
        // и не позже чем через 25 с). Иначе запрос замерзал до открытия.
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "ogneliss.finish") {
          // Время вышло раньше, чем Dart отдал его, — завершить сразу,
          // иначе iOS завершит приложение.
          AppDelegate.endBackground(task)
        }
        if task == .invalid {
          result(-1)
          return
        }
        AppDelegate.backgroundTasks.insert(task.rawValue)
        result(task.rawValue)
      case "endBackgroundTask":
        if let raw = call.arguments as? Int {
          AppDelegate.endBackground(UIBackgroundTaskIdentifier(rawValue: raw))
        }
        result(nil)
      case "copyImage":
        // Картинка из письма — в буфер обмена (1.8.12).
        guard let data = (call.arguments as? FlutterStandardTypedData)?.data,
              let image = UIImage(data: data) else {
          result(false)
          return
        }
        UIPasteboard.general.image = image
        result(true)
      case "clearBadge":
        // Число на значке сбрасывается при открытии приложения (письма
        // остаются непрочитанными — значок говорит лишь «пришло новое»).
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
          UIApplication.shared.applicationIconBadgeNumber = 0
        }
        result(nil)
      case "diagnostics":
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
          $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let refresh: String
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: refresh = "available"
        case .denied: refresh = "denied"
        case .restricted: refresh = "restricted"
        @unknown default: refresh = "unknown"
        }
        // UIKit — только на главном потоке: читаем до асинхронного вызова.
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let system = "\(device.systemName) \(device.systemVersion)"
        let battery = device.batteryLevel < 0 ? -1 : Int(device.batteryLevel * 100)
        let charging = device.batteryState == .charging || device.batteryState == .full
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let auth: String
          switch settings.authorizationStatus {
          case .authorized: auth = "authorized"
          case .denied: auth = "denied"
          case .notDetermined: auth = "notDetermined"
          case .provisional: auth = "provisional"
          case .ephemeral: auth = "ephemeral"
          @unknown default: auth = "unknown"
          }
          let info: [String: Any] = [
            "model": model,
            "system": system,
            "backgroundRefresh": refresh,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "notifications": auth,
            "alerts": settings.alertSetting == .enabled,
            "lockScreen": settings.lockScreenSetting == .enabled,
            "batteryPct": battery,
            "charging": charging,
          ]
          DispatchQueue.main.async { result(info) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Каналы приложения (не пакеты): MethodChannel 'ogneliss/device_calendar'
  /// и 'ogneliss/device_contacts' — зеркала Android-плагинов.
  static func registerAppChannels(_ registry: FlutterPluginRegistry) {
    if let r = registry.registrar(forPlugin: "OgnelissDeviceCalendar") {
      DeviceCalendarPlugin.register(with: r.messenger())
    }
    if let r = registry.registrar(forPlugin: "OgnelissDeviceContacts") {
      DeviceContactsPlugin.register(with: r.messenger())
    }
    // Контакты и календарь ящиков в телефоне (группа и календарь «Ogneliss — ящик»).
    if let r = registry.registrar(forPlugin: "OgnelissPhoneMirror") {
      PhoneMirrorPlugin.register(with: r.messenger())
    }
  }
}

// MARK: Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026)

/// Канал 'ogneliss/translate' (Dart — lib/services/translation/translator.dart).
/// Перевод — Apple Translation (iOS 18+): бесплатно, на устройстве, языки
/// скачивает сама iOS (и сама спрашивает разрешение). Язык текста —
/// NaturalLanguage, названия языков — Locale (есть на любой iOS).
/// Сессия перевода у Apple выдаётся только виду SwiftUI (.translationTask),
/// поэтому перевод идёт через невидимый вид 1×1 (UIHostingController)
/// поверх экрана Flutter. Включать в Xcode ничего не нужно
/// (docs/guides/TRANSLATION_SETUP.md).
enum TranslationBridge {
  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ogneliss/translate", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "detect":
        result(detect(args["text"] as? String ?? ""))
      case "names":
        let display = Locale(identifier: args["display"] as? String ?? "en")
        var names: [String: String] = [:]
        for code in args["codes"] as? [String] ?? [] {
          if let n = display.localizedString(forLanguageCode: code == "no" ? "nb" : code) { names[code] = n }
        }
        result(names)
      case "downloaded":
        // Языками управляет iOS (Настройки → Приложения → Перевод).
        result(nil)
      default:
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
          TranslationHost.shared.handle(call.method, args, result)
          return
        }
        #endif
        if call.method == "available" { result(false) } else { result(FlutterMethodNotImplemented) }
      }
    }
  }

  /// Язык текста (код вида «en», «zh-Hans») или nil — не уверены.
  static func detect(_ text: String) -> String? {
    let r = NLLanguageRecognizer()
    r.processString(String(text.prefix(2000)))
    guard let best = r.languageHypotheses(withMaximum: 1).first, best.value >= 0.5 else { return nil }
    return best.key.rawValue
  }

  /// Код приложения → язык Apple: норвежский у Apple — «nb», китайский —
  /// упрощённый, португальский — бразильский (как в приложении).
  static func appleLanguage(_ code: String) -> String {
    switch code {
    case "no": return "nb"
    case "zh": return "zh-Hans"
    case "pt": return "pt-BR"
    default: return code
    }
  }
}

#if canImport(Translation)
@available(iOS 18.0, *)
final class TranslationHost {
  static let shared = TranslationHost()
  private let jobs = TranslationJobs()
  private var host: UIViewController?

  func handle(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) {
    let fromCode = args["from"] as? String ?? ""
    let toCode = args["to"] as? String ?? ""
    let from = TranslationBridge.appleLanguage(fromCode)
    let to = TranslationBridge.appleLanguage(toCode)
    switch method {
    case "available":
      result(true)
    case "languages":
      Task {
        let langs = await LanguageAvailability().supportedLanguages
        let codes = Array(Set(langs.compactMap { $0.languageCode?.identifier }))
        await MainActor.run { result(codes) }
      }
    case "missing":
      Task {
        let status = await LanguageAvailability().status(
          from: Locale.Language(identifier: from), to: Locale.Language(identifier: to))
        await MainActor.run {
          switch status {
          case .installed: result([String]())
          case .supported: result([fromCode, toCode])
          default: result(FlutterError(code: "unsupported", message: "\(from) → \(to)", details: nil))
          }
        }
      }
    case "download":
      // Окно iOS «Скачать языки?» — системное, со своим размером и сетью.
      run(from, to, result) { session in
        try await session.prepareTranslation()
        return nil
      }
    case "translate":
      let texts = args["texts"] as? [String] ?? []
      run(from, to, result) { session in
        let requests = texts.enumerated().map {
          TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        var out = texts
        for r in try await session.translations(from: requests) {
          if let id = r.clientIdentifier, let i = Int(id), i < out.count { out[i] = r.targetText }
        }
        return out
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Задание — виду SwiftUI: новая конфигурация (или invalidate той же
  /// пары) запускает .translationTask с сессией. Вызовы Dart идут по
  /// одному, заданий одновременно не бывает.
  private func run(_ from: String, _ to: String, _ result: @escaping FlutterResult,
                   _ work: @escaping (TranslationSession) async throws -> Any?) {
    DispatchQueue.main.async {
      guard self.attach() else {
        result(FlutterError(code: "translate", message: "no window", details: nil))
        return
      }
      self.jobs.job = { session in
        do {
          let r = try await work(session)
          await MainActor.run { result(r) }
        } catch {
          await MainActor.run {
            result(FlutterError(code: "translate", message: error.localizedDescription, details: nil))
          }
        }
      }
      let source = Locale.Language(identifier: from)
      let target = Locale.Language(identifier: to)
      if var c = self.jobs.configuration, c.source == source, c.target == target {
        c.invalidate()
        self.jobs.configuration = c
      } else {
        self.jobs.configuration = TranslationSession.Configuration(source: source, target: target)
      }
    }
  }

  /// Невидимый вид SwiftUI 1×1 поверх экрана Flutter (один на приложение).
  private func attach() -> Bool {
    if host != nil { return true }
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    guard let root = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else { return false }
    let vc = UIHostingController(rootView: TranslationHostView(jobs: jobs))
    vc.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    vc.view.backgroundColor = .clear
    vc.view.isUserInteractionEnabled = false
    root.addChild(vc)
    root.view.addSubview(vc.view)
    vc.didMove(toParent: root)
    host = vc
    return true
  }
}

@available(iOS 18.0, *)
final class TranslationJobs: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?
  var job: ((TranslationSession) async -> Void)?
}

@available(iOS 18.0, *)
struct TranslationHostView: View {
  @ObservedObject var jobs: TranslationJobs

  var body: some View {
    Color.clear
      .translationTask(jobs.configuration) { session in
        guard let job = jobs.job else { return }
        jobs.job = nil
        await job(session)
      }
  }
}
#endif
