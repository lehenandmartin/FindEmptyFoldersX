import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var roots: [URL] = []
    var results: [EmptyFolder] = []
    var selection: Set<URL> = []
    var sortOrder: [KeyPathComparator<EmptyFolder>] = [.init(\.path)]

    var isScanning = false
    var progress = ScanProgress()
    var lastSummary: String?
    /// Low-key detail shown after the summary (folders scanned, duration…).
    var lastDetail: String?
    var lastScanIncomplete = false
    var emptyRoots: [URL] = []
    var errorMessage: String?

    // UI state
    var sidebarSelection: SidebarItem? = .all
    var searchText = ""
    var showInspector = false
    /// Item shown in Quick Look (space bar).
    var quickLookURL: URL?
    var isDropTargeted = false
    var pendingTrash: [EmptyFolder] = []
    var showTrashConfirm = false

    /// Last batch moved to the Trash: (original location, location in the Trash).
    private(set) var lastTrashed: [(original: URL, trashed: URL)] = []

    var options: ScanOptions {
        didSet { saveOptions() }
    }

    private var scanTask: Task<Void, Never>?

    private init() {
        let d = UserDefaults.standard
        var o = ScanOptions()
        if d.object(forKey: "ignoreInvisibleFiles") != nil { o.ignoreInvisibleFiles = d.bool(forKey: "ignoreInvisibleFiles") }
        if d.object(forKey: "skipInvisibleFolders") != nil { o.skipInvisibleFolders = d.bool(forKey: "skipInvisibleFolders") }
        if d.object(forKey: "skipPackages") != nil { o.skipPackages = d.bool(forKey: "skipPackages") }
        if d.object(forKey: "groupNested") != nil { o.groupNested = d.bool(forKey: "groupNested") }
        options = o
    }

    private func saveOptions() {
        let d = UserDefaults.standard
        d.set(options.ignoreInvisibleFiles, forKey: "ignoreInvisibleFiles")
        d.set(options.skipInvisibleFolders, forKey: "skipInvisibleFolders")
        d.set(options.skipPackages, forKey: "skipPackages")
        d.set(options.groupNested, forKey: "groupNested")
    }

    /// Displayed results: filtered by the sidebar and the search field, then sorted.
    var displayedResults: [EmptyFolder] {
        var r = results
        if case .root(let root) = sidebarSelection { r = r.filter { $0.root == root } }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            r = r.filter { $0.name.localizedStandardContains(q) || $0.displayPath.localizedStandardContains(q) }
        }
        return r.sorted(using: sortOrder)
    }

    func count(in root: URL) -> Int { results.reduce(0) { $0 + ($1.root == root ? 1 : 0) } }

    var subtitle: String {
        if isScanning { return String(localized: "Scanning…") }
        if roots.isEmpty { return "" }
        let n = displayedResults.count
        return n == 0 ? String(localized: "No Empty Folders") : String(localized: "\(n) empty folders")
    }

    var selectedFolders: [EmptyFolder] { results.filter { selection.contains($0.url) } }

    // MARK: - Folders to scan

    /// Adds folders and starts a scan.
    func add(_ urls: [URL], scan: Bool = true) {
        var added = false
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let u = url.standardizedFileURL
            // Skip if already covered by an existing root.
            if roots.contains(where: { u.path == $0.path || u.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }) { continue }
            // Drop roots now covered by the new one.
            roots.removeAll { $0.path.hasPrefix(u.path.hasSuffix("/") ? u.path : u.path + "/") }
            roots.append(u)
            added = true
        }
        if added && scan { startScan() }
    }

    func remove(root: URL) {
        roots.removeAll { $0 == root }
        let gone = Set(results.filter { $0.root == root }.map(\.url))
        results.removeAll { $0.root == root }
        selection.subtract(gone)
        if sidebarSelection == .root(root) { sidebarSelection = .all }
        emptyRoots.removeAll { $0 == root }
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Scan")
        panel.message = String(localized: "Choose one or more folders to search for empty folders.")
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: - Scanning

    func startScan() {
        guard !roots.isEmpty else { return }
        cancelScan()
        let roots = self.roots
        let options = self.options
        isScanning = true
        ScanCompletionNotifier.prepare()
        ScanCompletionNotifier.clearBadge()
        results = []
        selection = []
        emptyRoots = []
        lastSummary = nil
        lastDetail = nil
        lastScanIncomplete = false
        progress = ScanProgress()
        let start = Date()

        scanTask = Task { [weak self] in
            let outputs: [(URL, ScanOutput)] = await Task.detached(priority: .userInitiated) {
                var all: [(URL, ScanOutput)] = []
                var base = ScanProgress()
                for root in roots {
                    if Task.isCancelled { break }
                    let offset = base
                    let scanner = FolderScanner(options: options) { p in
                        var merged = p
                        merged.foldersScanned += offset.foldersScanned
                        merged.found += offset.found
                        Task { @MainActor in AppModel.shared.progress = merged }
                    }
                    let out = scanner.scan(root: root)
                    base.foldersScanned += out.scanned
                    base.found += out.folders.count
                    all.append((root, out))
                }
                return all
            }.value

            guard let self else { return }
            let cancelled = Task.isCancelled
            self.results = outputs.flatMap { $0.1.folders }
            self.emptyRoots = outputs.filter { $0.1.rootIsEmpty }.map { $0.0 }
            let scanned = outputs.reduce(0) { $0 + $1.1.scanned }
            let unreadable = outputs.reduce(0) { $0 + $1.1.unreadable }
            let secs = Date().timeIntervalSince(start)
            self.lastSummary = nil
            let duration = secs.formatted(.number.precision(.fractionLength(1)))
            var detail = String(localized: "\(scanned) folders scanned in \(duration) s")
            if unreadable > 0 { detail += " · " + String(localized: "\(unreadable) unreadable") }
            if cancelled { detail += " · " + String(localized: "scan stopped, results incomplete") }
            self.lastDetail = detail
            self.lastScanIncomplete = cancelled
            self.isScanning = false
            ScanCompletionNotifier.scanFinished(found: self.results.count, duration: secs, cancelled: cancelled)
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: - Actions

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // If an item no longer exists, the Finder has nothing to show:
        // walk up to the closest existing parent.
        let fm = FileManager.default
        var missing = 0
        let targets = urls.map { url -> URL in
            var u = url
            while !fm.fileExists(atPath: u.path) && u.pathComponents.count > 1 {
                u = u.deletingLastPathComponent()
            }
            if u != url { missing += 1 }
            return u
        }
        if missing > 0 {
            lastSummary = missing == 1
                ? String(localized: "This folder no longer exists")
                : String(localized: "\(missing) folders no longer exist")
            lastDetail = String(localized: "showing the parent folder")
        }
        NSWorkspace.shared.activateFileViewerSelecting(Array(Set(targets)))
    }

    func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// Moves folders to the Trash, after checking again that they are still empty.
    func trash(_ folders: [EmptyFolder]) {
        guard !folders.isEmpty else { return }
        // If a parent and its child are both selected, only handle the parent.
        let paths = folders.map(\.path)
        let targets = folders.filter { f in !paths.contains { f.path.hasPrefix($0 + "/") } }

        let checker = FolderScanner(options: options)
        var done: [(URL, URL)] = []
        var changed: [String] = []
        var failed: [String] = []
        for f in targets {
            guard checker.isStillEmpty(f.url) else { changed.append(f.name); continue }
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: f.url, resultingItemURL: &resulting)
                if let r = resulting as URL? { done.append((f.url, r)) }
            } catch {
                failed.append("\(f.name): \(error.localizedDescription)")
            }
        }
        let removed = Set(done.map { $0.0.path })
        results.removeAll { r in removed.contains(r.path) || removed.contains { r.path.hasPrefix($0 + "/") } }
        selection = selection.filter { s in !removed.contains(s.path) }
        if !done.isEmpty {
            lastTrashed = done.map { (original: $0.0, trashed: $0.1) }
            SystemSounds.playMoveToTrash()
        }

        var msg: [String] = []
        if !changed.isEmpty {
            msg.append(String(localized: "These folders are no longer empty and were left in place:") + "\n" + changed.joined(separator: "\n"))
        }
        if !failed.isEmpty {
            msg.append(String(localized: "Couldn’t move to the Trash:") + "\n" + failed.joined(separator: "\n"))
        }
        if !msg.isEmpty { errorMessage = msg.joined(separator: "\n\n") }
        if !done.isEmpty {
            lastSummary = String(localized: "\(done.count) folders moved to the Trash")
            lastDetail = String(localized: "⌘Z to undo · their parents may now be empty, scan again with ⌘R")
        }
    }

    /// Quick Look: opens or closes the preview of the selection, like the space bar in the Finder.
    func toggleQuickLook() {
        if quickLookURL != nil { quickLookURL = nil; return }
        quickLookURL = displayedResults.first { selection.contains($0.url) }?.url
    }

    func askTrash(_ folders: [EmptyFolder]) {
        guard !folders.isEmpty, !isScanning else { return }
        pendingTrash = folders
        showTrashConfirm = true
    }

    var canUndoTrash: Bool { !lastTrashed.isEmpty }

    func undoTrash() {
        var failed: [String] = []
        for item in lastTrashed {
            do {
                if FileManager.default.fileExists(atPath: item.original.path) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: item.trashed, to: item.original)
            } catch {
                failed.append("\(item.original.lastPathComponent): \(error.localizedDescription)")
            }
        }
        let n = lastTrashed.count - failed.count
        lastTrashed = []
        if !failed.isEmpty { errorMessage = String(localized: "Some folders couldn’t be put back:") + "\n" + failed.joined(separator: "\n") }
        lastSummary = String(localized: "\(n) folders put back")
        lastDetail = nil
        if !roots.isEmpty { startScan() }
    }
}

enum SidebarItem: Hashable {
    case all
    case root(URL)
}
