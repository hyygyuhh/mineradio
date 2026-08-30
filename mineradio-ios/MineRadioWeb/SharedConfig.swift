import UIKit
import WebKit

/// Shared constants, theme colors, and the shared WebKit data store.
/// All tabs and the hidden Bridge host share one `WKWebsiteDataStore`
/// so that cookies captured on music.163.com / y.qq.com / kugou.com
/// flow into the Bridge's privileged HTTP path.
enum MR {
    static let homeURL = URL(string: "https://mineradio.art/")!
    static let bridgeVersion = "1.4.2"
    static let extId = "mineradio-ios"
    static let bridgeScheme = "mineradio-bridge"

    /// Desktop UA so mineradio.art exposes the full Bridge login / QR UI.
    static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    static let storageDefaultsKey = "bridge_storage"

    /// Single shared process pool + persistent data store for every WebView.
    static let processPool = WKProcessPool()
    static let dataStore = WKWebsiteDataStore.default()

    // MARK: Theme (mirrors Android colors.xml)

    static let bg          = UIColor(hex: 0x0A0E14)
    static let bgElevated  = UIColor(hex: 0x121821)
    static let border      = UIColor(hex: 0x243041)
    static let text        = UIColor(hex: 0xE8EEF6)
    static let textDim     = UIColor(hex: 0x8B9BB0)
    static let accent      = UIColor(hex: 0x00F5D4)
    static let danger      = UIColor(hex: 0xFF6B7A)

    /// Persisted chrome (top bar) visibility.
    static let chromeVisibleKey = "chrome_visible"
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
