import SwiftUI

struct DocumentWorkspace: View {
    @Binding var selectedFileURL: URL?
    @State private var documentText: String = ""
    @State private var annotations: [DocumentAnnotation] = []
    @State private var editCount: Int = 0
    @State private var lastSavedText: String = ""
    @State private var syncMode: DocumentSyncMode = .explicit
    private let parser = AnnotationParser()
    private let changeDetector = DocumentChangeDetector()

    enum DocumentSyncMode: String, CaseIterable {
        case explicit = "手动同步"
        case realtime = "实时同步"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedFileURL?.lastPathComponent ?? "文档工作区")
                    .font(FontStyle.headline)
                Spacer()
                if !annotations.isEmpty {
                    Text("\(annotations.count) 处标注")
                        .font(FontStyle.caption)
                        .foregroundStyle(Color.statusWarning)
                }
                if editCount > 0 {
                    Text("变更: +\(editCount)")
                        .font(FontStyle.caption)
                        .foregroundStyle(Color.statusSuccess)
                        .padding(.leading, Spacing.xs)
                }
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)

            HStack(spacing: Spacing.xs) {
                Picker("", selection: $syncMode) {
                    ForEach(DocumentSyncMode.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                Button(action: saveDocument) {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(FontStyle.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存文档")

                Button(action: syncToAgent) {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(FontStyle.caption)
                }
                .buttonStyle(.plain)
                .disabled(editCount == 0)
                .accessibilityLabel("同步至 Agent")
            }
            .padding(.horizontal)
            .padding(.vertical, Spacing.xxs)

            Divider()

            if selectedFileURL == nil {
                EmptyStateView(
                    icon: "doc.text",
                    title: "文档工作区",
                    subtitle: "在资源管理器中选择一个文件打开",
                    action: nil
                )
                .background(Color.windowBackgroundColor)
            } else {
                TextEditor(text: $documentText)
                    .font(FontStyle.bodyMonospaced)
                    .onChange(of: documentText) { _, newValue in
                        let result = parser.parse(newValue)
                        annotations = result.annotations
                        if !lastSavedText.isEmpty && newValue != lastSavedText {
                            editCount = abs(newValue.count - lastSavedText.count) / 10
                        }
                        if syncMode == .realtime && !lastSavedText.isEmpty && newValue != lastSavedText {
                            notifyAgentOfChanges(newValue)
                        }
                    }
                    .accessibilityLabel("文档编辑器")
                    .onChange(of: selectedFileURL) { _, newURL in
                        loadFile(newURL)
                    }
                    .onAppear {
                        loadFile(selectedFileURL)
                    }
            }

            if !annotations.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(annotations, id: \.line) { ann in
                            HStack(spacing: Spacing.xxs) {
                                Image(
                                    systemName: ann.type == .deletion
                                        ? "trash"
                                        : ann.type == .insertion
                                            ? "plus.circle"
                                            : ann.type == .question ? "questionmark.circle" : "text.bubble")
                                Text("L\(ann.line)").font(FontStyle.caption2)
                            }
                            .padding(.horizontal, Spacing.xs).padding(.vertical, Spacing.xxs)
                            .background(
                                ann.type == .deletion
                                    ? Color.annotationDeletion.opacity(0.15)
                                    : ann.type == .insertion
                                        ? Color.annotationInsertion.opacity(0.15)
                                        : Color.annotationQuestion.opacity(0.15)
                            )
                            .cornerRadius(CornerRadius.xl)
                        }
                    }.padding(Spacing.xs)
                }.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
        .onDisappear {
            Task { await changeDetector.stopWatching() }
        }
    }

    private func loadFile(_ url: URL?) {
        guard let url else {
            documentText = ""
            lastSavedText = ""
            annotations = []
            editCount = 0
            return
        }
        if let data = try? String(contentsOf: url, encoding: .utf8) {
            documentText = data
            lastSavedText = data
            editCount = 0
        }
    }

    private func saveDocument() {
        lastSavedText = documentText
        editCount = 0
        if let url = selectedFileURL {
            try? documentText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func syncToAgent() {
        lastSavedText = documentText
        editCount = 0
        notifyAgentOfChanges(documentText)
    }

    private func notifyAgentOfChanges(_ newText: String) {
        let changeEvent = DocumentChangeNotification(
            text: newText,
            annotations: annotations,
            timestamp: Date(),
            documentURL: selectedFileURL
        )
        NotificationCenter.default.post(
            name: .documentChangedNotification,
            object: changeEvent
        )
    }
}

struct DocumentChangeNotification {
    let text: String
    let annotations: [DocumentAnnotation]
    let timestamp: Date
    let documentURL: URL?
    init(text: String, annotations: [DocumentAnnotation], timestamp: Date, documentURL: URL? = nil) {
        self.text = text
        self.annotations = annotations
        self.timestamp = timestamp
        self.documentURL = documentURL
    }
}

extension Notification.Name {
    static let documentChangedNotification = Notification.Name("YunPatDocumentChanged")
}
