// Плагин ogneliss_native_http на Mac (2.6.5): только прокси системы для
// почтовых серверов (метод proxyFor); запросы через сетевой стек системы —
// у iPhone и Android (на Mac — свой TLS Dart, как и раньше).

import FlutterMacOS
import Foundation

public class NativeHttpPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ogneliss/native_http", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(NativeHttpPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "proxyFor" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    let s = args?["url"] as? String ?? ""
    let pac = args?["pac"] as? String
    DispatchQueue.global(qos: .utility).async {
      let out = SystemProxyResolver.proxies(for: s, pac: pac)
      DispatchQueue.main.async { result(out) }
    }
  }
}
