import UIKit
import WebKit

/// Serves Bridge host assets (`runner.html`, `inject.js`, `bridge/api/*.js`,
/// vendor modules, icons) from the app bundle under a custom URL scheme so
/// that ES module imports (`import ... from '../bridge/api/router.js'`)
/// resolve same-origin. iOS WKWebView cannot expose `@JavascriptInterface`
/// like Android, so the Bridge host runs inside this scheme.
final class BridgeSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let url = urlSchemeTask.request.url
        // `mineradio-bridge://app/host/runner.html` -> bundle "Resources/host/runner.html"
        // The "app" host is virtual; only the path is used.
        guard let path = url?.path else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let bundlePath = "Resources/" + cleanPath
        let nsPath = bundlePath as NSString
        let dir = nsPath.deletingLastPathComponent
        let file = nsPath.lastPathComponent
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension

        guard
            let resourceURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir)
        else {
            // Fall back: some Xcode layouts flatten the "Resources" prefix.
            if let alt = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: file == dir ? "" : String(dir.dropFirst("Resources/".count))) {
                respond(urlSchemeTask: urlSchemeTask, url: alt)
                return
            }
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        respond(urlSchemeTask: urlSchemeTask, url: resourceURL)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel — we synchronously load from disk.
    }

    private func respond(urlSchemeTask: WKURLSchemeTask, url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            urlSchemeTask.didFailWithError(URLError(.cannotReadFile))
            return
        }
        let mime = Self.mime(forExtension: url.pathExtension)
        var headers = ["Content-Type": mime, "Content-Length": "\(data.count)"]
        if url.pathExtension == "js" || url.pathExtension == "mjs" || url.pathExtension == "html" {
            headers["Content-Type"] = mime + "; charset=utf-8"
        }
        let response = HTTPURLResponse(
            url: urlSchemeTask.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    static func mime(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "js": return "text/javascript"
        case "mjs": return "text/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "css": return "text/css"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}
