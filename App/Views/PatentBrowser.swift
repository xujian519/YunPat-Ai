import SwiftUI
import WebKit
import PatentClient

/// 内嵌专利浏览器 — Google Patents / CNIPA / Espacenet / WIPO / USPTO 直达
struct PatentBrowser: View {
    @State private var urlString: String = "https://patents.google.com/"
    @State private var selectedPreset: Int = 0
    @State private var isLoading: Bool = false
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var downloading: Bool = false
    @State private var downloadError: String?

    private let patentClient: GooglePatentsClient = GooglePatentsClient()

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
            presetBar
            navigationBar
            Divider()
            WebViewRepresentable(
                urlString: $urlString,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
        }
        .overlay(alignment: .bottomTrailing) {
            if downloading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("下载中…").font(FontStyle.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial).cornerRadius(8)
                .padding()
            }
        }
        .alert("下载失败", isPresented: .init(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("确定") { downloadError = nil }
        } message: {
            Text(downloadError ?? "")
        }
    }

    private var presetBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.presets.enumerated()), id: \.offset) { index, preset in
                Button(action: {
                    selectedPreset = index
                    urlString = preset.url
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: preset.icon).font(FontStyle.caption2)
                        Text(preset.name).font(FontStyle.caption)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(selectedPreset == index ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("跳转至 \(preset.name)")
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            Button(action: { postNavigationAction(.goBack) }) {
                Image(systemName: "chevron.left").font(.caption)
            }
            .buttonStyle(.plain).disabled(!canGoBack)
            .accessibilityLabel("后退")

            Button(action: { postNavigationAction(.goForward) }) {
                Image(systemName: "chevron.right").font(.caption)
            }
            .buttonStyle(.plain).disabled(!canGoForward)
            .accessibilityLabel("前进")

            TextField("网址", text: $urlString)
                .textFieldStyle(.roundedBorder).font(FontStyle.caption)
                .onSubmit { postNavigationAction(.navigate) }
                .accessibilityLabel("网址输入")

            Button(action: { postNavigationAction(.refresh) }) {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.plain).disabled(isLoading)
            .accessibilityLabel("刷新")

            Button(action: downloadCurrentPDF) {
                Label("PDF", systemImage: "arrow.down.doc")
                    .font(FontStyle.caption)
            }
            .buttonStyle(.plain).disabled(downloading)
            .accessibilityLabel("下载 PDF")
        }
        .padding(.horizontal, 8)
    }

    enum NavAction {
        case goBack, goForward, refresh, navigate
    }

    private func postNavigationAction(_ action: NavAction) {
        NotificationCenter.default.post(name: .webViewNavigationAction, object: action)
    }

    private func downloadCurrentPDF() {
        guard let patentNumber = extractPatentNumber(from: urlString) else {
            downloadError = "无法从当前 URL 识别专利号"
            return
        }
        downloading = true
        Task {
            defer { Task { @MainActor in downloading = false } }
            do {
                let panel = NSSavePanel()
                panel.title = "下载专利 PDF"
                panel.nameFieldStringValue = "\(patentNumber).pdf"
                panel.allowedContentTypes = [.pdf]
                guard panel.runModal() == .OK, let destURL = panel.url else { return }
                try await patentClient.downloadPDF(patentNumber, to: destURL)
            } catch {
                await MainActor.run { downloadError = error.localizedDescription }
            }
        }
    }

    private func extractPatentNumber(from url: String) -> String? {
        let patterns: [(pattern: String, group: Int, transform: (String) -> String)] = [
            ( #"patents\.google\.com/patent/([^/?]+)"#, 1, { $0 }),
            ( #"patents\.google\.com/patent/([^/?]+)/"#, 1, { $0 }),
            ( #"patentscope\.wipo\.int/search/.*WO=([^&]+)"#, 1, { $0 }),
            ( #"patentscope\.wipo\.int/search/.*number=([^&]+)"#, 1, { $0 }),
            ( #"worldwide\.espacenet\.com/.*publication=([^&]+)"#, 1, { $0 }),
        ]
        for (pattern, group, transform) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: url, options: [], range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range(at: group), in: url) {
                return transform(String(url[range]))
            }
        }
        return nil
    }
}

// MARK: - WKWebView Representable

struct WebViewRepresentable: NSViewRepresentable {
    @Binding var urlString: String
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        context.coordinator.webView = webView
        context.coordinator.observeNavigation()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let url = URL(string: urlString),
           nsView.url?.absoluteString != urlString {
            nsView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        weak var webView: WKWebView?
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        init(parent: WebViewRepresentable) {
            self.parent = parent
            super.init()
            observer = NotificationCenter.default.addObserver(
                forName: .webViewNavigationAction, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let action = note.object as? PatentBrowser.NavAction else { return }
                Task { @MainActor in self.handleNavigation(action) }
            }
        }

        deinit {
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
        }

        func observeNavigation() {
            webView?.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)
            webView?.addObserver(self, forKeyPath: #keyPath(WKWebView.isLoading), options: .new, context: nil)
            webView?.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
            webView?.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                    change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            Task { @MainActor in
                guard let webView = self.webView else { return }
                switch keyPath {
                case #keyPath(WKWebView.url):
                    if let currentURL = webView.url?.absoluteString, currentURL != parent.urlString {
                        parent.urlString = currentURL
                    }
                case #keyPath(WKWebView.isLoading):
                    parent.isLoading = webView.isLoading
                case #keyPath(WKWebView.canGoBack):
                    parent.canGoBack = webView.canGoBack
                case #keyPath(WKWebView.canGoForward):
                    parent.canGoForward = webView.canGoForward
                default:
                    break
                }
            }
        }

        private func handleNavigation(_ action: PatentBrowser.NavAction) {
            guard let webView else { return }
            switch action {
            case .goBack: webView.goBack()
            case .goForward: webView.goForward()
            case .refresh: webView.reload()
            case .navigate:
                if let url = URL(string: parent.urlString) {
                    webView.load(URLRequest(url: url))
                }
            }
        }
    }
}

extension Notification.Name {
    static let webViewNavigationAction = Notification.Name("webViewNavigationAction")
}
