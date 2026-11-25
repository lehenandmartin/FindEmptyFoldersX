import Foundation

/// Scan options.
struct ScanOptions: Equatable, Sendable {
    /// A folder that only contains invisible files (.DS_Store, Icon\r, ._*, .localized…) counts as empty.
    var ignoreInvisibleFiles = true
    /// Don't look inside invisible folders (.git, .cache…).
    var skipInvisibleFolders = true
    /// Don't look inside packages (.app, .photoslibrary, .bundle…).
    var skipPackages = true
    /// If a folder only contains empty folders, only list the parent.
    var groupNested = true
}

/// An empty folder that was found.
struct EmptyFolder: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isHidden: Bool
    /// A few of the invisible files it contains (relative paths), for display.
    let invisibleSample: [String]
    let invisibleCount: Int
    /// Number of empty subfolders inside this folder.
    let nestedCount: Int
    let modified: Date
    let depth: Int
    /// Scanned folder it comes from.
    let root: URL

    var id: URL { url }
    var path: String { url.path }
    /// Location relative to the scanned folder: "tree › mixed".
    var displayPath: String {
        // Rely on depth rather than on path strings (/tmp vs /private/tmp…).
        let parents = url.deletingLastPathComponent().pathComponents
        let rootName = root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent
        return ([rootName] + parents.suffix(max(0, depth - 1))).joined(separator: " › ")
    }

    var nestedLabel: String? {
        nestedCount == 0 ? nil : String(localized: "\(nestedCount) empty subfolders")
    }

    /// Distinct names of the invisible files it contains (without path), for the Contents column.
    var invisibleNames: String {
        var seen: [String] = []
        for f in invisibleSample {
            let n = (f as NSString).lastPathComponent.replacingOccurrences(of: "\r", with: "")
            if !seen.contains(n) { seen.append(n) }
        }
        var s = seen.joined(separator: ", ")
        if invisibleCount > invisibleSample.count { s += ", …" }
        return s
    }
}

struct ScanProgress: Sendable {
    var foldersScanned = 0
    var found = 0
    var currentPath = ""
}

struct ScanOutput: Sendable {
    var folders: [EmptyFolder]
    var rootIsEmpty: Bool
    var unreadable: Int
    var scanned: Int
}

/// Recursive walk of a folder tree, looking for empty folders.
/// Meant to run off the main thread; checks `Task.isCancelled`.
final class FolderScanner {
    private let options: ScanOptions
    private let onProgress: (@Sendable (ScanProgress) -> Void)?
    private let fm = FileManager()
    private var progress = ScanProgress()
    private var lastReport = Date.distantPast
    private var unreadable = 0
    private var rootVolume: AnyHashable?
    private var rootURL = URL(fileURLWithPath: "/")

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey,
        .contentModificationDateKey, .volumeIdentifierKey,
    ]
    private static let keySet = Set(keys)

    /// System folders that are never visited.
    private static let alwaysSkipped: Set<String> = [
        ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        ".TemporaryItems", ".MobileBackups", ".PKInstallSandboxManager", ".vol",
    ]

    private static let sampleLimit = 12

    init(options: ScanOptions, onProgress: (@Sendable (ScanProgress) -> Void)? = nil) {
        self.options = options
        self.onProgress = onProgress
    }

    private struct Node {
        var isEmpty: Bool
        var found: [EmptyFolder] = []
        var invisible: [String] = []
        var invisibleCount = 0
        var nested = 0
        static let notEmpty = Node(isEmpty: false)
    }

    func scan(root: URL) -> ScanOutput {
        rootVolume = (try? root.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? AnyHashable
        rootURL = root.standardizedFileURL
        let node = visit(rootURL, depth: 0)
        onProgress?(progress)
        return ScanOutput(folders: node.found, rootIsEmpty: node.isEmpty, unreadable: unreadable, scanned: progress.foldersScanned)
    }

    /// Checks that a folder is (still) empty with these options. Used right before moving to the Trash.
    func isStillEmpty(_ url: URL) -> Bool {
        rootVolume = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? AnyHashable
        return visit(url.standardizedFileURL, depth: 0).isEmpty
    }

    private func report(_ dir: URL) {
        let now = Date()
        guard let onProgress, now.timeIntervalSince(lastReport) > 0.08 else { return }
        lastReport = now
        progress.currentPath = dir.path
        onProgress(progress)
    }

    private func visit(_ dir: URL, depth: Int) -> Node {
        if Task.isCancelled { return .notEmpty }
        progress.foldersScanned += 1
        report(dir)

        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            unreadable += 1
            return .notEmpty // Unreadable: take no risk.
        }

        var node = Node(isEmpty: true)
        var foundHere: [EmptyFolder] = []

        for child in children {
            let name = child.lastPathComponent
            guard let v = try? child.resourceValues(forKeys: Self.keySet) else {
                node.isEmpty = false
                continue
            }
            let hidden = name.hasPrefix(".") || name == "Icon\r" || (v.isHidden ?? false)
            let isDir = (v.isDirectory ?? false) && !(v.isSymbolicLink ?? false)

            if !isDir {
                if hidden && options.ignoreInvisibleFiles {
                    node.invisibleCount += 1
                    if node.invisible.count < Self.sampleLimit { node.invisible.append(name) }
                } else {
                    node.isEmpty = false
                }
                continue
            }

            let isPackage = v.isPackage ?? false
            let otherVolume = rootVolume != nil && (v.volumeIdentifier as? AnyHashable) != rootVolume
            if Self.alwaysSkipped.contains(name)
                || otherVolume
                || (hidden && options.skipInvisibleFolders)
                || (isPackage && options.skipPackages) {
                node.isEmpty = false
                continue
            }

            let sub = visit(child, depth: depth + 1)
            if Task.isCancelled { return .notEmpty }

            if sub.isEmpty {
                let entry = EmptyFolder(
                    url: child,
                    name: name,
                    isHidden: hidden,
                    invisibleSample: sub.invisible,
                    invisibleCount: sub.invisibleCount,
                    nestedCount: sub.nested,
                    modified: v.contentModificationDate ?? .distantPast,
                    depth: depth + 1,
                    root: rootURL
                )
                foundHere.append(entry)
                if !options.groupNested { foundHere.append(contentsOf: sub.found) }
                node.nested += 1 + sub.nested
                node.invisibleCount += sub.invisibleCount
                for f in sub.invisible where node.invisible.count < Self.sampleLimit {
                    node.invisible.append(name + "/" + f)
                }
            } else {
                node.isEmpty = false
                node.found.append(contentsOf: sub.found)
            }
        }

        // If this folder is itself empty and nested folders are grouped, the caller lists it
        // and its empty subfolders are not shown separately.
        // The root folder itself is never listed: always keep its children.
        if !(node.isEmpty && options.groupNested) || depth == 0 {
            node.found.append(contentsOf: foundHere)
        }
        progress.found += foundHere.count
        return node
    }
}
