import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Folders dropped on the Dock icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppModel.shared.add(urls) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in ScanCompletionNotifier.clearBadge() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Let the window appear first, so a possible update alert doesn't come before the app.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            await UpdateChecker.checkAutomatically()
        }
    }
}

/// Standard About panel, with credits for the original app and a link to the source code.
/// The copyright line comes from NSHumanReadableCopyright in Info.plist (translated in InfoPlist.xcstrings).
@MainActor
private func showAboutPanel() {
    let inspiration = String(localized: "A modernized rewrite inspired by Find Empty Folders by Thomas Tempelmann.")
    let sourceCode = String(localized: "Source code on GitHub")
    let text = inspiration + "\n\n" + sourceCode
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let credits = NSMutableAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: style,
    ])
    // The original app's name links to its page, the last line to this app's repository.
    let original = (inspiration as NSString).range(of: "Find Empty Folders")
    if original.location != NSNotFound {
        credits.addAttribute(.link, value: URL(string: "https://www.tempel.org/FindEmptyFolders")!, range: original)
    }
    let repository = NSRange(location: (text as NSString).length - (sourceCode as NSString).length,
                             length: (sourceCode as NSString).length)
    credits.addAttribute(.link, value: URL(string: "https://github.com/lehenandmartin/FindEmptyFoldersX")!, range: repository)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

@main
struct FindEmptyFoldersXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Find Empty Folders X", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 440)
        }
        .defaultSize(width: 1100, height: 640)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Find Empty Folders X") { showAboutPanel() }
                Button("Check for Updates…") { UpdateChecker.checkNow() }
            }
            SidebarCommands()
            InspectorCommands()
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { model.chooseFolders() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Scan Again") { model.startScan() }
                    .keyboardShortcut("r")
                    .disabled(model.roots.isEmpty || model.isScanning)
                Button("Stop") { model.cancelScan() }
                    .keyboardShortcut(".")
                    .disabled(!model.isScanning)
                Divider()
                Button("Show in Finder") { model.reveal(Array(model.selection)) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.selection.isEmpty)
                Button("Quick Look") { model.toggleQuickLook() }
                    .keyboardShortcut("y")
                    .disabled(model.selection.isEmpty)
                Button("Move to Trash…") { model.askTrash(model.selectedFolders) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selection.isEmpty || model.isScanning)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Move to Trash") { model.undoTrash() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndoTrash)
            }
            CommandGroup(before: .toolbar) {
                Toggle("Group Nested Folders", isOn: Binding(
                    get: { model.options.groupNested },
                    set: { model.options.groupNested = $0 }
                ))
                .disabled(model.isScanning)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
