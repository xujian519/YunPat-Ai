import SwiftUI
import WebKit

/// 内嵌专利浏览器 — Google Patents / CNIPA / Espacenet 直达
struct PatentBrowser: View {
    @State private var urlString: String = "https://patents.google.com/"
    @State private var selectedPreset: Int = 0

    struct Preset: Identifiable {
        let id = UUID()
        let name: String
        let url: String
        let icon: String
    }

    static let presets: [Preset] = [
        Preset(name: "Google Patents", url: "https://patents.google.com/", icon: "magnifyingglass"),
        Preset(name: "CNIPA 公布公告", url: "http://epub.cnipa.gov.cn/", icon: "building.columns"),
        Preset(name: "Espacenet", url: "https://worldwide.espacenet.com/", icon: "globe.europe.africa"),
        Preset(name: "WIPO Patentscope", url: "https://patentscope.wipo.int/", icon: "globe"),
        Preset(name: "USPTO", url: "https://portal.uspto.gov/pair/PublicPair", icon: "flag")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 预设按钮栏
            HStack(spacing: 4) {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { index, preset in
                    Button(action: {
                        selectedPreset = index
                        urlString = preset.url
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 9))
                            Text(preset.name)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selectedPreset == index ? Color.accentColor.opacity(0.15) : Color.clear)
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
                Button(action: {}, label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                })
                .buttonStyle(.plain)
                Button(action: {}, label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                })
                .buttonStyle(.plain)

                TextField("URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Button(action: {}, label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                })
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
