import AppKit
import UserNotifications

enum SystemSounds {
    private static var current: NSSound?

    /// The Finder sound for moving an item to the Trash.
    /// Honors the "Play user interface sound effects" setting.
    static func playMoveToTrash() {
        let d = UserDefaults.standard
        if d.object(forKey: "com.apple.sound.uiaudio.enabled") != nil,
           !d.bool(forKey: "com.apple.sound.uiaudio.enabled") { return }
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif"
        current = NSSound(contentsOfFile: path, byReference: true)
        current?.play()
    }
}

/// Dock badge and scan-finished notification.
@MainActor
enum ScanCompletionNotifier {
    private static var askedPermission = false

    /// Call when a scan starts, so the permission prompt shows up while the user
    /// is looking at the app, not when it goes to the background.
    static func prepare() {
        guard !askedPermission else { return }
        askedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func scanFinished(found: Int, duration: TimeInterval, cancelled: Bool) {
        guard !NSApp.isActive, !cancelled else { return }
        NSApp.dockTile.badgeLabel = found > 0 ? found.formatted() : nil
        // Only notify when the scan took long enough for the user to have switched to something else.
        guard duration >= 2 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Scan Complete")
        content.body = found == 0
            ? String(localized: "No empty folders found")
            : String(localized: "\(found) empty folders found")
        content.sound = .default
        let req = UNNotificationRequest(identifier: "scan-finished", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    static func clearBadge() {
        NSApp.dockTile.badgeLabel = nil
    }
}
