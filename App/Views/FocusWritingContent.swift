import SwiftUI
import YunPatCore

struct FocusWritingContent: View {
    var onExit: () -> Void
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DocumentWorkspace(selectedFileURL: $appState.selectedDocumentURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        if reduceMotion {
                            onExit()
                        } else {
                            withAnimation(.spring(duration: AnimationDuration.spring)) {
                                onExit()
                            }
                        }
                    } label: {
                        Label("退出专注模式", systemImage: "xmark.circle.fill")
                            .font(FontStyle.body)
                    }
                    .buttonStyle(.borderless)
                    .padding(Spacing.sm)
                    .background(.ultraThinMaterial)
                    .cornerRadius(CornerRadius.lg)
                    .padding(Spacing.xs)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("退出专注写作模式 (ESC)")
                    .accessibilityLabel("退出专注写作模式")
                }
            }
        }
    }
}
