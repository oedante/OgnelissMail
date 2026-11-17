// Прокси для почтовых серверов (2.6.5, план 08.11.2026 п. 1): настройки
// сети устройства — ручной прокси, сценарий PAC, глобальный прокси профиля
// MDM. PAC выполняет сама система (CFNetwork), сценарий загружается здесь.
// Тот же файл — в macos/Classes (плагин для Mac).

import CFNetwork
import Foundation

enum SystemProxyResolver {
  /// Прокси для адреса [urlString] по порядку: {type: DIRECT|HTTP, host, port}.
  /// [pac] — сценарий PAC организации (MDM pac_url) вместо настроек сети.
  static func proxies(for urlString: String, pac: String? = nil) -> [[String: Any]] {
    guard let url = URL(string: urlString) else { return [] }
    if let pac = pac, !pac.isEmpty {
      guard let pacUrl = URL(string: pac), let script = fetch(pacUrl) else { return [] }
      return fromScript(script, url)
    }
    guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else { return [] }
    let array = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue()
    let list = (array as NSArray) as? [[String: Any]] ?? []
    var out: [[String: Any]] = []
    for p in list {
      let type = p[kCFProxyTypeKey as String] as? String ?? ""
      if type == (kCFProxyTypeAutoConfigurationURL as String) {
        if let pac = p[kCFProxyAutoConfigurationURLKey as String] as? URL, let script = fetch(pac) {
          out.append(contentsOf: fromScript(script, url))
        }
      } else if type == (kCFProxyTypeAutoConfigurationJavaScript as String) {
        if let script = p[kCFProxyAutoConfigurationJavaScriptKey as String] as? String {
          out.append(contentsOf: fromScript(script, url))
        }
      } else {
        if let e = entry(p) { out.append(e) }
      }
    }
    return out
  }

  private static func entry(_ p: [String: Any]) -> [String: Any]? {
    let type = p[kCFProxyTypeKey as String] as? String ?? ""
    if type == (kCFProxyTypeNone as String) { return ["type": "DIRECT"] }
    if type == (kCFProxyTypeHTTP as String) || type == (kCFProxyTypeHTTPS as String),
       let host = p[kCFProxyHostNameKey as String] as? String,
       let port = (p[kCFProxyPortNumberKey as String] as? NSNumber)?.intValue {
      return ["type": "HTTP", "host": host, "port": port]
    }
    return nil
  }

  private static func fromScript(_ script: String, _ url: URL) -> [[String: Any]] {
    var error: Unmanaged<CFError>?
    guard let array = CFNetworkCopyProxiesForAutoConfigurationScript(script as CFString, url as CFURL, &error)?
      .takeRetainedValue() else { return [] }
    let res = (array as NSArray) as? [[String: Any]] ?? []
    return res.compactMap { entry($0) }
  }

  /// Сценарий PAC — не дольше 5 секунд.
  private static func fetch(_ url: URL) -> String? {
    if url.isFileURL { return try? String(contentsOf: url, encoding: .utf8) }
    var text: String?
    let done = DispatchSemaphore(value: 0)
    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
    req.httpMethod = "GET"
    let cfg = URLSessionConfiguration.ephemeral
    cfg.connectionProxyDictionary = [:] // сам сценарий — без прокси
    let session = URLSession(configuration: cfg)
    let task = session.dataTask(with: req) { data, _, _ in
      if let data = data { text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) }
      done.signal()
    }
    task.resume()
    _ = done.wait(timeout: .now() + 6)
    session.finishTasksAndInvalidate()
    return text
  }
}
