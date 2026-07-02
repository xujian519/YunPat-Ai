import SwiftUI

struct DocumentWorkspace: View {
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
            // 工具栏
            HStack {
                Text("文档工作区").font(.headline)
                Spacer()
                if !annotations.isEmpty {
                    Text("\(annotations.count) 处标注")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if editCount > 0 {
                    Text("变更: +\(editCount)")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.leading, 8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // 同步模式
            HStack(spacing: 8) {
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
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button(action: syncToAgent) {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(editCount == 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()

            // 编辑器
            TextEditor(text: $documentText)
                .font(.system(.body, design: .monospaced))
                .onChange(of: documentText) { _, newValue in
                    let result = parser.parse(newValue)
                    annotations = result.annotations
                    if !lastSavedText.isEmpty && newValue != lastSavedText {
                        editCount = abs(newValue.count - lastSavedText.count) / 10
                    }
                    // 实时同步模式
                    if syncMode == .realtime && !lastSavedText.isEmpty && newValue != lastSavedText {
                        notifyAgentOfChanges(newValue)
                    }
                }

            // 标注摘要
            if !annotations.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(annotations, id: \.line) { ann in
                            HStack(spacing: 4) {
                                Image(
                                    systemName: ann.type == .deletion
                                        ? "trash"
                                        : ann.type == .insertion
                                            ? "plus.circle"
                                            : ann.type == .question ? "questionmark.circle" : "text.bubble")
                                Text("L\(ann.line)").font(.caption2)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                ann.type == .deletion
                                    ? Color.red.opacity(0.15)
                                    : ann.type == .insertion ? Color.green.opacity(0.15) : Color.orange.opacity(0.15)
                            )
                            .cornerRadius(12)
                        }
                    }.padding(8)
                }.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }

    private func saveDocument() {
        lastSavedText = documentText
        editCount = 0
    }

    private func syncToAgent() {
        lastSavedText = documentText
        editCount = 0
        notifyAgentOfChanges(documentText)
    }

    private func notifyAgentOfChanges(_ newText: String) {
        // 通过 NotificationCenter 通知 ChatManager 文档已变更
        let changeEvent = DocumentChangeNotification(
            text: newText,
            annotations: annotations,
            timestamp: Date()
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
}

extension Notification.Name {
    static let documentChangedNotification = Notification.Name("YunPatDocumentChanged")
}
