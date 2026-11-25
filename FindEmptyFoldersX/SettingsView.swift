import SwiftUI

/// Settings window (⌘,): the scan rules.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.options.ignoreInvisibleFiles) {
                    Text("Ignore invisible files")
                    Text("A folder that only contains .DS_Store, Icon or ._* counts as empty")
                }
                Toggle(isOn: $model.options.skipInvisibleFolders) {
                    Text("Don’t look inside invisible folders")
                    Text("The contents of .git, .cache and other invisible folders are skipped")
                }
                Toggle(isOn: $model.options.skipPackages) {
                    Text("Don’t look inside packages")
                    Text("Apps, Photos libraries… Their empty folders are often needed")
                }
            } header: {
                Text("Scan")
            } footer: {
                Text("Changing a rule starts a new scan")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
