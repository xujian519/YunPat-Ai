import SwiftUI

/// 文件夹树 / 工作目录浏览器
struct FolderTreeView: View {
    let rootPath: URL?
    @State private var expandedPaths: Set<String> = []
    @State private var entries: [FileEntry] = []

    struct FileEntry: Identifiable {
        let id: String  // path
        let name: String
        let isDirectory: Bool
        let children: [FileEntry]?
    }

    init(rootPath: URL? = nil) {
        self.rootPath =
            rootPath
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("YunPat/workspaces")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.blue)
                Text("工作目录")
                    .font(FontStyle.headline)
                Spacer()
                    Button { refreshEntries() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新目录")
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)

            if let path = rootPath {
                HStack {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(path.lastPathComponent)
                        .font(FontStyle.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(path.path)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.05))
            }

            Divider()

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("点击刷新加载目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            FileEntryRow(
                                entry: entry,
                                depth: 0,
                                expanded: expandedPaths,
                                onToggle: { toggleExpand($0) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 200, idealWidth: 260)
        .background(Color.windowBackgroundColor)
    }

    private func refreshEntries() {
        guard let path = rootPath else { return }
        entries = scanDirectory(path)
    }

    private func scanDirectory(_ url: URL) -> [FileEntry] {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { itemURL in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { return nil }
            return FileEntry(
                id: itemURL.path,
                name: itemURL.lastPathComponent,
                isDirectory: isDir.boolValue,
                children: isDir.boolValue ? [] : nil
            )
        }
    }

    private func toggleExpand(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }
}

/// 递归文件目录行
struct FileEntryRow: View {
    let entry: FolderTreeView.FileEntry
    let depth: Int
    let expanded: Set<String>
    let onToggle: (String) -> Void

    @State private var children: [FolderTreeView.FileEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 1)
                        .padding(.leading, 8)
                }

                if entry.isDirectory {
                    Button {
                        onToggle(entry.id)
                        if children.isEmpty {
                            children = scanDir(URL(fileURLWithPath: entry.id))
                        }
                    } label: {
                        Image(systemName: expanded.contains(entry.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.caption, weight: .bold))
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

                Image(
                    systemName: entry.isDirectory
                        ? (expanded.contains(entry.id) ? "folder" : "folder")
                        : fileIcon(entry.name)
                )
                .font(.system(size: IconSize.caption))
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)

                Text(entry.name)
                    .font(FontStyle.caption)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                if entry.isDirectory {
                    onToggle(entry.id)
                    if children.isEmpty {
                        children = scanDir(URL(fileURLWithPath: entry.id))
                    }
                }
            }

            if entry.isDirectory && expanded.contains(entry.id) {
                ForEach(children) { child in
                    FileEntryRow(entry: child, depth: depth + 1, expanded: expanded, onToggle: onToggle)
                }
            }
        }
    }

    private func scanDir(_ url: URL) -> [FolderTreeView.FileEntry] {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { itemURL in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { return nil }
            return FolderTreeView.FileEntry(
                id: itemURL.path,
                name: itemURL.lastPathComponent,
                isDirectory: isDir.boolValue,
                children: isDir.boolValue ? [] : nil
            )
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "md": return "doc.richtext"
        case "pdf": return "doc"
        case "py": return "terminal"
        case "sh": return "terminal"
        case "json": return "curlybraces"
        default: return "doc"
        }
    }
}
