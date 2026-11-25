import SwiftUI
import QuickLook

// UI state lives in AppModel rather than in @State: the app was first built without Xcode, where the @State macro is unavailable.

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            detail
                .navigationTitle("Find Empty Folders X")
                .navigationSubtitle(model.subtitle)
                .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search")
                .inspector(isPresented: $model.showInspector) {
                    InspectorView(folders: model.selectedFolders)
                        .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
                }
                .toolbar { toolbar }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: { model.isDropTargeted = $0 }
        .onChange(of: model.options) { model.startScan() }
        .confirmationDialog(trashTitle, isPresented: $model.showTrashConfirm) {
            Button("Move to Trash", role: .destructive) {
                model.trash(model.pendingTrash)
                model.pendingTrash = []
            }
            Button("Cancel", role: .cancel) { model.pendingTrash = [] }
        } message: {
            Text("Each folder is checked again right before it is moved. You can undo with ⌘Z.")
        }
        .dialogIcon(Image(nsImage: NSImage(named: NSImage.trashFullName) ?? NSImage()))
        .alert("Warning", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var trashTitle: String {
        let n = model.pendingTrash.count
        return n == 1
            ? String(localized: "Move “\(model.pendingTrash[0].name)” to the Trash?")
            : String(localized: "Move \(n) folders to the Trash?")
    }

    // MARK: - Main content

    private var detail: some View {
        VStack(spacing: 0) {
            ZStack {
                if model.roots.isEmpty {
                    dropHint
                } else if model.displayedResults.isEmpty && !model.isScanning {
                    noResults
                } else {
                    table
                }
                if model.isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
    }

    private var table: some View {
        @Bindable var model = model
        return Table(model.displayedResults, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { f in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(f.isHidden ? .tertiary : .secondary)
                        .frame(width: 16)
                    Text(f.name)
                        .foregroundStyle(f.isHidden ? .secondary : .primary)
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("Contents", value: \.nestedCount) { f in
                ContentCell(folder: f)
            }
            .width(min: 140, ideal: 220)

            TableColumn("Modified", value: \.modified) { f in
                Text(f.modified == .distantPast ? "—" : f.modified.formatted(date: .numeric, time: .shortened))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 130)

            TableColumn("Location", value: \.path) { f in
                Text(f.displayPath)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                    .help(f.path)
            }
            .width(min: 120, ideal: 200)
        }
        .contextMenu(forSelectionType: URL.self) { ids in
            let folders = model.results.filter { ids.contains($0.url) }
            Button("Show in Finder") { model.reveal(Array(ids)) }
            Button("Quick Look") {
                model.quickLookURL = model.displayedResults.first { ids.contains($0.url) }?.url
            }
            Button("Copy Path") { model.copyPaths(Array(ids)) }
            Divider()
            Button("Move to Trash…") { model.askTrash(folders) }
        } primaryAction: { ids in
            model.reveal(Array(ids))
        }
        .onDeleteCommand { model.askTrash(model.selectedFolders) }
        .onKeyPress(.space) {
            model.toggleQuickLook()
            return .handled
        }
        .quickLookPreview($model.quickLookURL, in: model.displayedResults.map(\.url))
        .overlay {
            if model.isScanning && model.results.isEmpty {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private var dropHint: some View {
        ContentUnavailableView {
            Label("Drop a Folder Here", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Find Empty Folders X finds folders that contain nothing, or only invisible files such as .DS_Store")
        } actions: {
            Button("Choose a Folder…") { model.chooseFolders() }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var noResults: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ContentUnavailableView {
                Label("No Empty Folders", systemImage: "checkmark.circle")
            } description: {
                if !model.emptyRoots.isEmpty {
                    Text("The scanned folder is itself empty")
                } else if model.lastDetail == nil {
                    Text("Start a scan with ⌘R")
                } else {
                    Text("Nothing to clean up here")
                }
            }
        }
    }

    // MARK: - Status bar

    @ViewBuilder
    private var statusBar: some View {
        let hasMessage = model.lastSummary != nil || model.lastDetail != nil
        if model.isScanning || hasMessage {
            HStack(spacing: 8) {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Text("\(model.progress.foldersScanned) folders scanned")
                        .foregroundStyle(.secondary)
                    Text(model.progress.currentPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.tertiary)
                } else {
                    if let s = model.lastSummary {
                        Text(s).foregroundStyle(.primary).layoutPriority(1)
                    }
                    if let d = model.lastDetail {
                        Text(d)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.isScanning {
                Button {
                    model.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop the scan (⌘.)")
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label("Scan Again", systemImage: "arrow.clockwise")
                }
                .disabled(model.roots.isEmpty)
                .help("Scan again (⌘R)")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.reveal(Array(model.selection))
            } label: {
                Label("Show in Finder", systemImage: "finder")
            }
            .disabled(model.selection.isEmpty)
            .help("Show in Finder (⇧⌘R)")

            Button {
                model.askTrash(model.selectedFolders)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(model.selection.isEmpty || model.isScanning)
            .help("Move to Trash (⌘⌫)")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "info.circle")
            }
            .help("Show or hide the inspector (⌥⌘I)")
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Label("All Folders", systemImage: "tray.full")
                .badge(model.results.count)
                .tag(SidebarItem.all)

            Section("Scanned Folders") {
                ForEach(model.roots, id: \.self) { root in
                    Label(root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent, systemImage: "folder")
                        .badge(model.count(in: root))
                        .tag(SidebarItem.root(root))
                        .help((root.path as NSString).abbreviatingWithTildeInPath)
                        .contextMenu {
                            Button("Show in Finder") { model.reveal([root]) }
                            Divider()
                            Button("Remove from List") { model.remove(root: root) }
                                .disabled(model.isScanning)
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    model.chooseFolders()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .help("Add a folder (⌘O)")

                Button {
                    if case .root(let root) = model.sidebarSelection { model.remove(root: root) }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .disabled(selectedRoot == nil || model.isScanning)
                .help("Remove the selected folder")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var selectedRoot: URL? {
        if case .root(let r) = model.sidebarSelection { return r }
        return nil
    }
}

// MARK: - Contents column

/// Empty subfolders in secondary text, invisible files in faded monospace
/// (the app's signature look), a discreet "Empty" otherwise.
private struct ContentCell: View {
    let folder: EmptyFolder

    var body: some View {
        HStack(spacing: 8) {
            if let nested = folder.nestedLabel {
                Text(nested)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
            if folder.invisibleCount > 0 {
                Text(folder.invisibleNames)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if folder.nestedLabel == nil && folder.invisibleCount == 0 {
                Text("Empty")
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}
