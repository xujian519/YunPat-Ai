import SwiftUI
import WebKit

/// 内嵌专利浏览器 — Google Patents / CNIPA / Espacenet 直达
struct PatentBrowser: View {
    @State private var urlString = "https://patents.google.com/"
    @State private var selectedPreset = 0

    static let presets: [(String, String, String)] = [
        ("Google Patents", "https://patents.google.com/", "magnifyingglass"),
        ("CNIPA 公布公告", "http://epub.cnipa.gov.cn/", "building.columns"),
        ("Espacenet", "https://worldwide.espacenet.com/", "globe.europe.africa"),
        ("WIPO Patentscope", "https://patentscope.wipo.int/", "globe"),
        ("USPTO", "https://portal.uspto.gov/pair/PublicPair", "flag"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 预设按钮栏
            HStack(spacing: 4) {
                ForEach(Array(Self.presets.enumerated()), id: \.0) { i, preset in
                    Button(action: {
                        selectedPreset = i
                        urlString = preset.1
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: preset.2)
                                .font(.system(size: 9))
                            Text(preset.0)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selectedPreset == i ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // URL 导航栏
            HStack(spacing: 4) {
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Button(action: {}) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                TextField("URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Button(action: {}) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            Divider()

            // WebView
            WebViewRepresentable(urlString: urlString)
        }
    }
}

/// WKWebView NSViewRepresentable
struct WebViewRepresentable: NSViewRepresentable {
    let urlString: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let url = URL(string: urlString),
           nsView.url?.absoluteString != urlString {
            nsView.load(URLRequest(url: url))
        }
    }
}
