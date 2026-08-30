import Foundation
import WebKit

/// Privileged HTTP for the Bridge host: can set Cookie header and read
/// Set-Cookie (WKWebView page `fetch` cannot). Mirrors `NativeHttp.kt`.
final class NativeHttp {
    private let queue = DispatchQueue(label: "art.mineradio.nativeHttp", qos: .userInitiated)

    static let shared = NativeHttp()

    /// Cookies injected into / read back from requests are stored in the
    /// shared `WKWebsiteDataStore` so the page tabs and Bridge stay in sync.
    private var cookieStore: WKHTTPCookieStore? { MR.dataStore.httpCookieStore }

    func start(requestId: String, specJson: String, bridge: WKWebView, deliver: @escaping (String) -> Void) {
        queue.async {
            let result = self.execute(specJson)
            DispatchQueue.main.async {
                let idLit = Self.quote(requestId)
                let rawLit = Self.quote(result)
                let js = "window.__nativeHttpResult && window.__nativeHttpResult(\(idLit), \(rawLit));"
                bridge.evaluateJavaScript(js)
                _ = deliver
            }
        }
    }

    private func execute(_ specJson: String) -> String {
        guard
            let data = specJson.data(using: .utf8),
            let spec = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Self.err("invalid spec")
        }
        guard let urlStr = spec["url"] as? String, let url = URL(string: urlStr) else {
            return Self.err("missing url")
        }
        let method = (spec["method"] as? String ?? "GET").uppercased()
        let followRedirects = spec["redirect"] as? Bool ?? true
        let headersIn = spec["headers"] as? [String: String] ?? [:]

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = [:]

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        var hasCookie = false
        for (k, v) in headersIn {
            if k.lowercased() == "content-length" { continue }
            if k.lowercased() == "cookie" { hasCookie = true }
            request.setValue(v, forHTTPHeaderField: k)
        }

        let semaphore = DispatchSemaphore(value: 0)
        if !hasCookie {
            cookieStore?.getAllCookies { cookies in
                let header = Self.cookieHeader(for: url, cookies: cookies)
                if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") }
                semaphore.signal()
            }
            // WKHTTPCookieStore.getAllCookies is async; if store missing, proceed.
            if cookieStore == nil { semaphore.signal() }
        } else {
            semaphore.signal()
        }
        semaphore.wait()

        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(MR.desktopUA, forHTTPHeaderField: "User-Agent")
        }

        let bodyBase64 = spec["bodyBase64"] as? String ?? ""
        let bodyText = spec["body"] as? String ?? ""
        if method != "GET", method != "HEAD", !(bodyBase64.isEmpty && bodyText.isEmpty) {
            if !bodyBase64.isEmpty, let bytes = Data(base64Encoded: bodyBase64) {
                request.httpBody = bytes
            } else {
                request.httpBody = bodyText.data(using: .utf8)
            }
        }

        let session = URLSession(configuration: config)
        let taskSemaphore = DispatchSemaphore(value: 0)
        var respData = Data()
        var response: URLResponse?
        var taskError: Error?
        var finalURL = url

        let delegate = RedirectStop(enabled: !followRedirects)
        let sessionDel = session.delegate as? URLSessionDataDelegate
        _ = sessionDel
        let task: URLSessionTask
        if !followRedirects {
            // Use a no-redirect delegate session to stop on redirect.
            let redirectSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            task = redirectSession.dataTask(with: request) { d, r, e in
                respData = d ?? Data()
                response = r
                taskError = e
                if let h = (r as? HTTPURLResponse)?.allHeaderFields {
                    _ = h
                }
                finalURL = r?.url ?? url
                taskSemaphore.signal()
            }
        } else {
            task = session.dataTask(with: request) { d, r, e in
                respData = d ?? Data()
                response = r
                taskError = e
                finalURL = r?.url ?? url
                taskSemaphore.signal()
            }
        }
        task.resume()
        taskSemaphore.wait()

        // Append Set-Cookie values into the shared cookie store (so subsequent
        // navigations see them), then expose the raw Set-Cookie list to JS.
        var setCookies: [String] = []
        if let http = response as? HTTPURLResponse {
            for (name, value) in http.allHeaderFields {
                let key = String(describing: name)
                if key.lowercased() == "set-cookie" {
                    let raw = String(describing: value)
                    // Multiple Set-Cookie may be joined; split on separators
                    // that delimit distinct cookie rows.
                    for cookieRow in Self.splitSetCookie(raw) {
                        if cookieRow.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                        setCookies.append(cookieRow)
                        if let httpCookie = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": cookieRow],
                                                               for: finalURL).first {
                            cookieStore?.setCookie(httpCookie)
                        }
                    }
                }
            }
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let _ = taskError, status == 0 {
            return Self.err(taskError?.localizedDescription ?? "http failed")
        }

        let outHeaders = collectHeaders(response as? HTTPURLResponse)
        let body = respData.base64EncodedString(options: [.endLineWithLineFeed]).replacingOccurrences(of: "\n", with: "")

        let res: [String: Any] = [
            "ok": true,
            "status": status,
            "url": finalURL.absoluteString,
            "headers": outHeaders,
            "setCookies": setCookies,
            "bodyBase64": body,
        ]
        guard let outData = try? JSONSerialization.data(withJSONObject: res),
              let outStr = String(data: outData, encoding: .utf8) else {
            return Self.err("encode failed")
        }
        return outStr
    }

    private func collectHeaders(_ http: HTTPURLResponse?) -> [String: String] {
        var out: [String: String] = [:]
        guard let http = http else { return out }
        for (k, v) in http.allHeaderFields {
            let key = String(describing: k)
            if key.lowercased() == "set-cookie" { continue }
            out[key] = String(describing: v)
        }
        return out
    }

    // MARK: Helpers

    static func cookieHeader(for url: URL, cookies: [HTTPCookie]) -> String {
        let host = (url.host ?? "").lowercased()
        let path = url.path.isEmpty ? "/" : url.path
        let secure = url.scheme == "https"
        let picked = cookies.filter { c in
            let cd = (c.domain).lowercased()
            let stripped = cd.hasPrefix(".") ? String(cd.dropFirst()) : cd
            let domainMatch = stripped.isEmpty || host == stripped || host.hasSuffix("." + stripped)
            let cp = c.path.isEmpty ? "/" : c.path
            let pathMatch = path.hasPrefix(cp) || cp == "/"
            let secureOk = !c.isSecure || secure
            return domainMatch && pathMatch && secureOk
        }
        return picked.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// A single Set-Cookie header field value may contain several cookies
    /// concatenated (URLSession flattens multi-header). Split into rows.
    static func splitSetCookie(_ raw: String) -> [String] {
        // Split before attributes that start a new cookie (Name= followed by
        // another Name=). Simpler: split on ", " only when followed by an
        // "=" pair AND the preceding segment contains "=" (heuristic).
        var rows: [String] = []
        var current = ""
        var depth = 0
        let scalars = Array(raw)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "=" { depth = 1 }
            if c == "," && depth == 1 {
                // peek: next non-space char should be part of attr=value pair
                let next = scalars[(i+1)..<min(scalars.count, i+4)]
                let joined = String(next)
                if joined.contains("=") || joined.contains(";") {
                    // belongs to same cookie value (e.g. Expires=...)
                    current.append(c)
                    i += 1
                    continue
                }
                rows.append(current)
                current = ""
                i += 1
                while i < scalars.count, scalars[i] == " " { i += 1 }
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty { rows.append(current) }
        // Fallback: if heuristic produced nothing meaningful, treat whole as one.
        if rows.isEmpty { rows = [raw] }
        return rows
    }

    static func quote(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let str = String(data: data, encoding: .utf8) {
            // JSONSerialization of [s] -> ["s"] -> strip brackets -> "s"
            let trimmed = str.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return trimmed
        }
        return "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    static func err(_ message: String) -> String {
        return "{\"ok\":false,\"error\":\"\(message.replacingOccurrences(of: "\"", with: "\\\""))\"}"
    }
}

/// URLSessionDataDelegate that stops following redirects when `enabled`,
/// returning the redirect response itself (like `redirect: false`).
private final class RedirectStop: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    let enabled: Bool
    init(enabled: Bool) { self.enabled = enabled }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if enabled {
            completionHandler(nil) // stop: surface the redirect response
        } else {
            completionHandler(request)
        }
    }
}
