import AppKit

/// Checks GitHub for a newer release and offers to open its page.
/// No automatic install: the app isn't notarized, so a new version is downloaded and installed by hand.
@MainActor
enum UpdateChecker {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/lehenandmartin/FindEmptyFoldersX/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/lehenandmartin/FindEmptyFoldersX/releases")!

    /// UserDefaults keys.
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedUpdateVersion"

    private static var isChecking = false

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
        /// "v0.2" → "0.2"
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    static var currentVersion: String {
        #if DEBUG
        // For testing: launch with -UpdateCheckerCurrentVersion 0.0.1
        if let v = UserDefaults.standard.string(forKey: "UpdateCheckerCurrentVersion") { return v }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// At launch: at most once a day, silent unless a new version is out and not skipped.
    static func checkAutomatically() async {
        let d = UserDefaults.standard
        if d.object(forKey: automaticKey) != nil, !d.bool(forKey: automaticKey) { return }
        if let last = d.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await check(userInitiated: false)
    }

    /// From the "Check for Updates…" menu: always answers, even when up to date or offline.
    static func checkNow() {
        Task { await check(userInitiated: true) }
    }

    private static func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let release: Release
        do {
            var request = URLRequest(url: latestReleaseAPI, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            if userInitiated { showError() }
            return
        }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        let latest = release.version
        guard isVersion(latest, newerThan: currentVersion) else {
            if userInitiated { showUpToDate() }
            return
        }
        // A skipped version is only shown again when the user asks.
        if !userInitiated, UserDefaults.standard.string(forKey: skippedKey) == latest { return }
        showUpdateAvailable(latest, page: release.htmlURL, allowSkip: !userInitiated)
    }

    /// Compares dotted versions numerically: 0.10 is newer than 0.9.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Alerts

    private static func showUpdateAvailable(_ version: String, page: URL, allowSkip: Bool) {
        let current = currentVersion
        let alert = NSAlert()
        alert.messageText = String(localized: "Find Empty Folders X \(version) is available")
        alert.informativeText = String(localized: "You have version \(current). Download the new version from GitHub, then install it like the first time.")
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))
        if allowSkip { alert.addButton(withTitle: String(localized: "Skip This Version")) }
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(page)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(version, forKey: skippedKey)
        default:
            break
        }
    }

    private static func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = String(localized: "You’re up to date")
        alert.informativeText = String(localized: "Find Empty Folders X \(currentVersion) is the latest version.")
        alert.runModal()
    }

    private static func showError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t check for updates")
        alert.informativeText = String(localized: "GitHub couldn’t be reached. Check your connection, or see the releases page.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Open Releases Page"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(releasesPage)
        }
    }
}
