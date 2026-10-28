// Режим совместимости со шлюзом на iPhone (1.6.12).
//
// Анти-бот шлюз перед Exchange различает клиентов по отпечатку TLS. Запрос из
// Dart (BoringSSL Dart VM) с User-Agent почты iPhone для него — подделка:
// пользователи iPhone получали 403 «If you are not a bot…» на Provision.
// Здесь запрос идёт через NSURLSession — тем же сетевым стеком, что у
// штатной Почты iOS. Канал тот же, что у Android-части: ogneliss/native_http.
//
// Сертификат, не прошедший системную проверку, принимается, если это
// разрешено правилами приложения (отпечаток SHA-256 листового сертификата в
// base64, доверенный домен) или его цепочку подтверждают дополнительные ЦС
// приложения (ЦС Минцифры и др.). Отказ — ошибка CERT с данными сертификата:
// экран входа предложит доверять ему.

import CryptoKit
import Flutter
import Foundation
import Security

public class NativeHttpPlugin: NSObject, FlutterPlugin, URLSessionDelegate, URLSessionTaskDelegate {
  private struct Trust {
    let fingerprints: Set<String>
    let acceptAny: Bool
    let extraCas: [SecCertificate]
  }

  private let lock = NSLock()
  private var trust: [String: Trust] = [:]
  private var failed: [String: (der: Data, subject: String, leafFp: String, expected: String)] = [:]
  // Параметры соединения по задачам (1.6.17), см. didFinishCollecting.
  private var taskMetrics: [Int: String] = [:]

  private lazy var session: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 20 * 60
    cfg.timeoutIntervalForResource = 20 * 60
    // Куки (BackEnd сервера Exchange) приложение передаёт само.
    cfg.httpShouldSetCookies = false
    cfg.httpCookieAcceptPolicy = .never
    cfg.urlCache = nil
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
  }()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ogneliss/native_http", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativeHttpPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "send",
          let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString) else {
      result(FlutterMethodNotImplemented)
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = (args["method"] as? String) ?? "GET"
    if let headers = args["headers"] as? [String: String] {
      for (k, v) in headers {
        // Как в Android-части: сжатие система включает и снимает сама,
        // длину тела считает сама.
        let lk = k.lowercased()
        if lk == "accept-encoding" || lk == "content-length" { continue }
        request.setValue(v, forHTTPHeaderField: k)
      }
    }
    if let body = args["body"] as? FlutterStandardTypedData, !body.data.isEmpty {
      request.httpBody = body.data
    }
    if let ms = args["timeoutMs"] as? Int { request.timeoutInterval = Double(ms) / 1000.0 }

    let host = (url.host ?? "").lowercased()
    let cas: [SecCertificate] = ((args["extraCas"] as? [FlutterStandardTypedData]) ?? []).compactMap {
      SecCertificateCreateWithData(nil, $0.data as CFData)
    }
    lock.lock()
    trust[host] = Trust(
      fingerprints: Set((args["trustedSha256"] as? [String]) ?? []),
      acceptAny: (args["acceptAny"] as? Bool) ?? false,
      extraCas: cas)
    lock.unlock()

    // Номер задачи — через объект-ссылку, а не захваченную переменную
    // (замыкание NSURLSession может быть @Sendable).
    let ref = TaskRef()
    let task = session.dataTask(with: request) { [weak self] data, response, error in
      let certFailure: (der: Data, subject: String, leafFp: String, expected: String)? = {
        guard let self = self else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.failed.removeValue(forKey: host)
      }()
      // Небольшая задержка: метрики соединения (didFinishCollecting) приходят
      // примерно одновременно с ответом.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        if let error = error {
          if let cert = certFailure {
            result(FlutterError(code: "CERT",
                                message: "Сертификат сервера \(host) не подтверждён "
                                  + "(отпечаток листа \(cert.leafFp), ожидались: \(cert.expected))",
                                details: [
                                  "der": FlutterStandardTypedData(bytes: cert.der),
                                  "subject": cert.subject,
                                  "issuer": "",
                                  "notBefore": 0,
                                  "notAfter": 0,
                                ]))
          } else {
            let ns = error as NSError
            // Код ошибки — для журнала: -1200 TLS, -1001 таймаут, -1009 нет сети.
            result(FlutterError(code: "NET", message: "\(ns.localizedDescription) (\(ns.domain) \(ns.code))", details: nil))
          }
          return
        }
        guard let http = response as? HTTPURLResponse else {
          result(FlutterError(code: "NET", message: "нет ответа", details: nil))
          return
        }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
          let lk = String(describing: k).lowercased()
          // Тело уже распаковано системой — Content-Encoding и длину сжатого
          // тела не передаём, иначе Dart распакует ещё раз.
          if lk == "content-encoding" || lk == "content-length" { continue }
          headers[lk] = String(describing: v)
        }
        let net = self?.takeMetrics(ref.id) ?? ""
        result([
          "status": http.statusCode,
          "headers": headers,
          "body": FlutterStandardTypedData(bytes: data ?? Data()),
          "reason": HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
          "net": net,
        ])
      }
    }
    ref.id = task.taskIdentifier
    task.resume()
  }

  private final class TaskRef {
    var id = -1
  }

  private func takeMetrics(_ id: Int) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return taskMetrics.removeValue(forKey: id)
  }

  // Диагностика соединения (1.6.17): протокол (h2 или http/1.1), версия TLS,
  // шифр, новое или повторное соединение, через прокси или нет, адрес шлюза и
  // имена отправленных заголовков (без значений). Уходит в ответ («net») и в
  // журнал движка — чтобы сравнить запрос с Почтой iPhone.
  public func urlSession(_ session: URLSession, task: URLSessionTask,
                         didFinishCollecting metrics: URLSessionTaskMetrics) {
    guard let t = metrics.transactionMetrics.last else { return }
    var parts: [String] = [t.networkProtocolName ?? "протокол ?"]
    if let v = t.negotiatedTLSProtocolVersion {
      let raw = v.rawValue
      parts.append(raw == 0x0304 ? "TLS 1.3" : (raw == 0x0303 ? "TLS 1.2" : "TLS 0x" + String(raw, radix: 16)))
    }
    if let c = t.negotiatedTLSCipherSuite {
      parts.append("шифр 0x" + String(c.rawValue, radix: 16))
    }
    parts.append(t.isReusedConnection ? "повторное соединение" : "новое соединение")
    if t.isProxyConnection { parts.append("через прокси") }
    if let addr = t.remoteAddress { parts.append("адрес " + addr) }
    if let names = t.request.allHTTPHeaderFields?.keys.sorted() {
      parts.append("заголовки: " + names.joined(separator: " "))
    }
    lock.lock()
    if taskMetrics.count > 64 { taskMetrics.removeAll() }
    taskMetrics[task.taskIdentifier] = parts.joined(separator: ", ")
    lock.unlock()
  }

  public func urlSession(_ session: URLSession,
                         didReceive challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let serverTrust = challenge.protectionSpace.serverTrust else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    if SecTrustEvaluateWithError(serverTrust, nil) {
      completionHandler(.useCredential, URLCredential(trust: serverTrust))
      return
    }
    let host = challenge.protectionSpace.host.lowercased()
    lock.lock()
    let rule = trust[host]
    lock.unlock()
    if let rule = rule {
      if rule.acceptAny {
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
        return
      }
      // Дополнительные ЦС приложения — вместе с системными корнями.
      if !rule.extraCas.isEmpty {
        SecTrustSetAnchorCertificates(serverTrust, rule.extraCas as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, false)
        if SecTrustEvaluateWithError(serverTrust, nil) {
          completionHandler(.useCredential, URLCredential(trust: serverTrust))
          return
        }
      }
    }
    var leafDer = Data()
    var subject = host
    var leafFp = ""
    if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate], let leaf = chain.first {
      leafDer = SecCertificateCopyData(leaf) as Data
      subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? host
      leafFp = Data(SHA256.hash(data: leafDer)).base64EncodedString()
      if let rule = rule, rule.fingerprints.contains(leafFp) {
        NSLog("[native_http] %@: доверяем по отпечатку листа", host)
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
        return
      }
    }
    // Диагностика (1.6.13): почему системная проверка не прошла и отпечаток не
    // совпал — чтобы по журналу flutter run было видно, что передано плагину.
    let expected = rule?.fingerprints.joined(separator: ", ") ?? "(правила нет)"
    NSLog("[native_http] %@: сертификат не принят. acceptAny=%@, отпечаток листа=%@, ожидались: %@",
          host, (rule?.acceptAny ?? false) ? "да" : "нет", leafFp, expected)
    lock.lock()
    failed[host] = (leafDer, subject, leafFp, expected)
    lock.unlock()
    completionHandler(.cancelAuthenticationChallenge, nil)
  }

  // Перенаправления не выполняем (как setInstanceFollowRedirects(false) на
  // Android): 302/451 разбирает движок — он знает, куда и с чем повторять.
  public func urlSession(_ session: URLSession, task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest,
                         completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }

  // Сервер принимает только NTLM/Negotiate (Basic выключен на IIS): Почта iOS
  // в этом случае входит теми же логином и паролем — берём их из заголовка
  // Basic запроса. Один раз: неверный пароль — ответ 401 приложению.
  public func urlSession(_ session: URLSession, task: URLSessionTask,
                         didReceive challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    let method = challenge.protectionSpace.authenticationMethod
    if method == NSURLAuthenticationMethodServerTrust {
      urlSession(session, didReceive: challenge, completionHandler: completionHandler)
      return
    }
    guard (method == NSURLAuthenticationMethodNTLM || method == NSURLAuthenticationMethodNegotiate),
          challenge.previousFailureCount == 0,
          let header = task.originalRequest?.value(forHTTPHeaderField: "Authorization"),
          header.hasPrefix("Basic "),
          let raw = Data(base64Encoded: String(header.dropFirst(6))),
          let pair = String(data: raw, encoding: .utf8),
          let colon = pair.firstIndex(of: ":") else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    let user = String(pair[..<colon])
    let password = String(pair[pair.index(after: colon)...])
    completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .forSession))
  }
}
