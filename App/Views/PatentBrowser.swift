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
                                .font(FontStyle.caption2)
                            Text(preset.name)
                                .font(FontStyle.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selectedPreset == index ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("跳转至 \(preset.name)")
                    .accessibilityHint("切换到 \(preset.name) 网站")
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
                .accessibilityLabel("后退")
                .accessibilityHint("浏览历史中上一页")
                Button(action: {}, label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                })
                .buttonStyle(.plain)
                .accessibilityLabel("前进")
                .accessibilityHint("浏览历史中下一页")

                TextField("网址", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(FontStyle.caption)
                    .accessibilityLabel("网址输入")
                    .accessibilityHint("输入或粘贴专利检索网址")

                Button(action: {}, label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                })
                .buttonStyle(.plain)
                .accessibilityLabel("刷新")
                .accessibilityHint("重新加载当前页面")
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
