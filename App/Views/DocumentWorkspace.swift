import SwiftUI

struct DocumentWorkspace: View {
    @State private var documentText = ""
    @State private var annotations: [DocumentAnnotation] = []
    private let parser = AnnotationParser()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("文档工作区").font(.headline)
                Spacer()
                if !annotations.isEmpty {
                    Text("\(annotations.count) 处标注").font(.caption).foregroundStyle(.orange)
                }
            }.padding(.horizontal).padding(.top, 8)
            Divider()
            TextEditor(text: $documentText)
                .font(.system(.body, design: .monospaced))
                .onChange(of: documentText) { _, newValue in
                    let result = parser.parse(newValue)
                    annotations = result.annotations
                }
            if !annotations.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(annotations, id: \.line) { ann in
                            HStack(spacing: 4) {
                                Image(systemName: ann.type == .deletion ? "trash" : ann.type == .insertion ? "plus.circle" : ann.type == .question ? "questionmark.circle" : "text.bubble")
                                Text("L\(ann.line)").font(.caption2)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(ann.type == .deletion ? Color.red.opacity(0.15) : ann.type == .insertion ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .cornerRadius(12)
                        }
                    }.padding(8)
                }.frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }
}
