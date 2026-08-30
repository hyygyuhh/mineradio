import UIKit
import WebKit

/// One browser tab: a visible WKWebView plus its strip entry.
final class BrowserTab {
    let id: String
    let webView: WKWebView
    let stripView: UIView
    let titleLabel: UILabel
    let faviconView: UIImageView
    let closeButton: UIButton
    var url: String

    init(id: String, webView: WKWebView, stripView: UIView, titleLabel: UILabel,
         faviconView: UIImageView, closeButton: UIButton, url: String) {
        self.id = id
        self.webView = webView
        self.stripView = stripView
        self.titleLabel = titleLabel
        self.faviconView = faviconView
        self.closeButton = closeButton
        self.url = url
    }

    /// Creates a strip entry (favicon + title + close) mirroring item_tab.xml.
    static func makeStripView() -> (UIView, UILabel, UIImageView, UIButton) {
        let container = UIView()
        container.backgroundColor = MR.bg
        container.layer.cornerRadius = 8
        container.layer.borderWidth = 1
        container.layer.borderColor = MR.border.cgColor

        let favicon = UIImageView()
        favicon.contentMode = .scaleAspectFit
        favicon.tintColor = MR.textDim
        favicon.isHidden = true

        let title = UILabel()
        title.font = .systemFont(ofSize: 12)
        title.textColor = MR.textDim
        title.numberOfLines = 1
        title.lineBreakMode = .byTruncatingTail
        title.text = "加载中…"

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = MR.textDim
        close.contentMode = .scaleAspectFit

        let stack = UIStackView(arrangedSubviews: [favicon, title, close])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            favicon.widthAnchor.constraint(equalToConstant: 16),
            favicon.heightAnchor.constraint(equalToConstant: 16),
            close.widthAnchor.constraint(equalToConstant: 26),
            close.heightAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 110),
        ])

        container.setContentHuggingPriority(.required, for: .horizontal)
        return (container, title, favicon, close)
    }
}
