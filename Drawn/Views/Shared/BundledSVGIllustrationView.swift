import SwiftUI
import WebKit

/// Renders a bundled **SVG** at a fixed logical size via `WKWebView`.
/// Add **`ringingtimer.svg`** (or your asset) to **Copy Bundle Resources**.
struct BundledSVGIllustrationView: UIViewRepresentable {
    var resourceName: String
    var svgExtension: String = "svg"
    var width: CGFloat = 160
    var height: CGFloat = 120

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        web.isOpaque = true
        web.backgroundColor = .white
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.backgroundColor = .white
        web.setContentCompressionResistancePriority(.required, for: .vertical)
        web.setContentCompressionResistancePriority(.required, for: .horizontal)
        web.setContentHuggingPriority(.required, for: .vertical)
        web.setContentHuggingPriority(.required, for: .horizontal)

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: svgExtension),
              let svg = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Add \(resourceName).\(svgExtension) to Copy Bundle Resources")
            return web
        }

        let wi = Int(width)
        let hi = Int(height)
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8">
        <meta name="viewport" content="width=\(wi), maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; padding: 0; width: \(wi)px; height: \(hi)px; overflow: hidden; background: #ffffff; }
          svg { display: block; width: \(wi)px !important; height: \(hi)px !important; margin: 0 auto; }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """

        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }
}
