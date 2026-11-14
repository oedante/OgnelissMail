// tool/desktop/macos/MainFlutterWindow.swift
//
// Окно Mac. Папку macos/ создаёт `flutter create` при сборке (в git её нет),
// сборка кладёт этот файл поверх macos/Runner/MainFlutterWindow.swift
// (.github/workflows/ci.yml, scripts/build_macos.sh) — файл в проекте Xcode
// уже есть, менять проект не нужно.
//
// Перевод писем на устройстве (1.11.0, просьба владельца 03.11.2026: «перевод
// на macOS сделать аналогично iOS»): канал 'ogneliss/translate' — тот же, что
// на iPhone (ios/Runner/AppDelegate.swift), Apple Translation, macOS 15+.
// Сессия перевода у Apple выдаётся только виду SwiftUI (.translationTask) —
// перевод идёт через невидимый вид 1×1 поверх экрана Flutter. Языки
// скачивает сама macOS (Системные настройки → Основные → Язык и регион →
// Языки перевода).

import Cocoa
import FlutterMacOS
import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Движок рисования выбирается при создании Flutter — до него.
    GraphicsBridge.install()
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    TranslationBridge.register(flutterViewController.engine.binaryMessenger, view: flutterViewController.view)
    GraphicsBridge.register(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Движок рисования на Mac (14.11.2026, снимки владельца: Flutter 3.47.7,
/// Mac с Intel — Impeller рассыпал буквы в шум, интерфейс дёргался; на Apple
/// Silicon Impeller работает и он плавнее). Flutter решает по ключу
/// FLTEnableImpeller из Info.plist — `[[NSBundle mainBundle]
/// objectForInfoDictionaryKey:]` (FlutterDartProject.mm). Info.plist
/// подписанного приложения не изменить, поэтому ответ на этот ключ
/// подменяется в процессе до создания движка. Выбор хранится в UserDefaults
/// и применяется со следующего запуска; канал 'ogneliss/graphics' — тот же,
/// что на Android (lib/core/platform/graphics_mode.dart).
enum GraphicsBridge {
  private static let modeKey = "ogneliss.graphics.mode"

  /// Чем рисует этот процесс: skia | impeller.
  private(set) static var active = "impeller"

  /// Mac с Intel (и приложение под Rosetta).
  static var intel: Bool {
    #if arch(x86_64)
    return true
    #else
    return false
    #endif
  }

  /// Выбор: auto | skia | impeller.
  static var mode: String {
    let m = UserDefaults.standard.string(forKey: modeKey) ?? "auto"
    return ["skia", "impeller"].contains(m) ? m : "auto"
  }

  static func engine(_ mode: String) -> String {
    switch mode {
    case "skia", "impeller": return mode
    default: return intel ? "skia" : "impeller"
    }
  }

  static func install() {
    let want = engine(mode)
    if Bundle.ognOverrideImpeller(want == "impeller") {
      active = want
    } else {
      // Подмена не удалась — как записано в Info.plist (сборка пишет false).
      let on = (Bundle.main.object(forInfoDictionaryKey: "FLTEnableImpeller") as? NSNumber)?.boolValue ?? true
      active = on ? "impeller" : "skia"
    }
  }

  static func state() -> [String: Any] {
    var s: [String: Any] = ["mode": mode, "active": active, "next": engine(mode), "cpu": intel ? "intel" : "arm"]
    if let gpu = MTLCreateSystemDefaultDevice()?.name {
      s["gpu"] = "\(gpu), \(intel ? "Intel" : "Apple Silicon")"
    }
    return s
  }

  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ogneliss/graphics", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "state":
        result(state())
      case "setMode":
        let m = call.arguments as? String ?? "auto"
        UserDefaults.standard.set(["skia", "impeller"].contains(m) ? m : "auto", forKey: modeKey)
        result(state())
      case "restart":
        result(nil)
        restart()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Новый процесс приложения и выход из этого: движок выбирается при запуске.
  static func restart() {
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, error in
      DispatchQueue.main.async {
        if error == nil { NSApp.terminate(nil) }
      }
    }
  }
}

extension Bundle {
  private static var ognImpeller: Bool?
  private static var ognSwizzled = false

  /// Ответ главного бандла на FLTEnableImpeller — [on]. false — подменить
  /// не удалось.
  static func ognOverrideImpeller(_ on: Bool) -> Bool {
    ognImpeller = on
    if ognSwizzled { return true }
    guard let original = class_getInstanceMethod(Bundle.self, #selector(Bundle.object(forInfoDictionaryKey:))),
          let replacement = class_getInstanceMethod(Bundle.self, #selector(Bundle.ogn_object(forInfoDictionaryKey:)))
    else { return false }
    method_exchangeImplementations(original, replacement)
    ognSwizzled = true
    return true
  }

  /// После обмена реализаций вызов ogn_object(…) внутри — исходный метод.
  @objc private func ogn_object(forInfoDictionaryKey key: String) -> Any? {
    if key == "FLTEnableImpeller", self == Bundle.main, let on = Bundle.ognImpeller {
      return NSNumber(value: on)
    }
    return ogn_object(forInfoDictionaryKey: key)
  }
}

enum TranslationBridge {
  static func register(_ messenger: FlutterBinaryMessenger, view: NSView) {
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
        // Языками управляет macOS.
        result(nil)
      default:
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
          TranslationHost.shared.handle(call.method, args, view, result)
          return
        }
        #endif
        if call.method == "available" { result(false) } else { result(FlutterMethodNotImplemented) }
      }
    }
  }

  /// Язык текста: ["lang": код, "confident": уверены ли] или nil (как на
  /// iPhone, 1.12.x): от 0,5 — уверены, от 0,2 — догадка (только для
  /// «Перевести» из меню письма, без плашки-предложения).
  static func detect(_ text: String) -> [String: Any]? {
    let r = NLLanguageRecognizer()
    r.processString(String(text.prefix(2000)))
    guard let best = r.languageHypotheses(withMaximum: 1).first, best.value >= 0.2 else { return nil }
    return ["lang": best.key.rawValue, "confident": best.value >= 0.5]
  }

  /// Код приложения → язык Apple (как на iPhone).
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
@available(macOS 15.0, *)
final class TranslationHost {
  static let shared = TranslationHost()
  private let jobs = TranslationJobs()
  private var host: NSView?

  func handle(_ method: String, _ args: [String: Any], _ view: NSView, _ result: @escaping FlutterResult) {
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
      run(from, to, view, result) { session in
        try await session.prepareTranslation()
        return nil
      }
    case "translate":
      let texts = args["texts"] as? [String] ?? []
      run(from, to, view, result) { session in
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
  /// пары) запускает .translationTask с сессией. Вызовы Dart идут по одному.
  private func run(_ from: String, _ to: String, _ view: NSView, _ result: @escaping FlutterResult,
                   _ work: @escaping (TranslationSession) async throws -> Any?) {
    DispatchQueue.main.async {
      self.attach(to: view)
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
  private func attach(to view: NSView) {
    if host != nil { return }
    let v = NSHostingView(rootView: TranslationHostView(jobs: jobs))
    v.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
    view.addSubview(v)
    host = v
  }
}

@available(macOS 15.0, *)
final class TranslationJobs: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?
  var job: ((TranslationSession) async -> Void)?
}

@available(macOS 15.0, *)
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
