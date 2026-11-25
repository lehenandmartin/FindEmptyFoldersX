import SwiftUI

/// Inspector panel: details of the selected folder.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    let folders: [EmptyFolder]

    var body: some View {
        switch folders.count {
        case 0:
            ContentUnavailableView("No Selection", systemImage: "info.circle",
                                   description: Text("Select a folder to see what it contains"))
        case 1:
            FolderDetailView(folder: folders[0])
        default:
            Form {
                Section("\(folders.count) folders selected") {
                    ForEach(folders.prefix(200)) { f in
                        Label(f.name, systemImage: "folder")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct FolderDetailView: View {
    @Environment(AppModel.self) private var model
    let folder: EmptyFolder

    var body: some View {
        let d = FolderDetails(url: folder.url)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label(folder.name, systemImage: "folder")
                        .font(.headline)
                    Text(folder.displayPath)
                        .foregroundStyle(.secondary)
                }
                Text(folder.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Dates") {
                LabeledContent("Created", value: d.created.map(format) ?? "—")
                LabeledContent("Modified", value: d.modified.map(format) ?? "—")
            }

            Section("Empty Subfolders") {
                if d.subfolders.isEmpty {
                    Text("None").foregroundStyle(.tertiary)
                } else {
                    ForEach(d.subfolders, id: \.self) { rel in
                        Label(rel, systemImage: "folder")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Invisible Files") {
                if d.invisibleFiles.isEmpty {
                    Text("None").foregroundStyle(.tertiary)
                } else {
                    ForEach(d.invisibleFiles, id: \.self) { rel in
                        Text(rel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if d.truncated {
                Text("List limited to the first 200 items")
                    .foregroundStyle(.tertiary)
            }

            Section {
                Button("Show in Finder") { model.reveal([folder.url]) }
                Button("Move to Trash…", role: .destructive) { model.askTrash([folder]) }
                    .disabled(model.isScanning)
            }
        }
        .formStyle(.grouped)
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Actual contents of a folder, read on demand (these folders are almost empty, so it's fast).
private struct FolderDetails {
    var created: Date?
    var modified: Date?
    var subfolders: [String] = []
    var invisibleFiles: [String] = []
    var truncated = false

    init(url: URL) {
        let v = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        created = v?.creationDate
        modified = v?.contentModificationDate
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let base = url.standardizedFileURL.pathComponents.count
        var n = 0
        // Depth-first walk with directoryEntries(of:), which also sees ._* files.
        var pending = [url]
        while let dir = pending.popLast() {
            let children = ((try? directoryEntries(of: dir)) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            var subdirs: [URL] = []
            for item in children {
                n += 1
                if n > 200 { truncated = true; return }
                let rel = item.standardizedFileURL.pathComponents.dropFirst(base).joined(separator: "/")
                    .replacingOccurrences(of: "\r", with: "")
                let rv = try? item.resourceValues(forKeys: keys)
                if (rv?.isDirectory ?? false) && !(rv?.isSymbolicLink ?? false) {
                    subfolders.append(rel)
                    subdirs.append(item)
                } else {
                    invisibleFiles.append(rel)
                }
            }
            pending.append(contentsOf: subdirs.reversed())
        }
    }
}
