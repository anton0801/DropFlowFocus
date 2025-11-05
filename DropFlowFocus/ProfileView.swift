
import Foundation
import SwiftUI

struct ProfileView: View {
    
    @EnvironmentObject var state: AppState
    
    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $state.settings.theme) {
                        ForEach(Settings.Theme.allCases, id: \.self) { t in Text(t.rawValue.capitalized).tag(t) }
                    }
//                    Slider(value: $state.settings.animationSpeed, in: 0.5...2.0, step: 0.1) {
//                        Text("Animation Speed")
//                    }
                }
                Section("Sync") {
                    Button("Backup to iCloud") { /* implement */ }
                    Button("Restore") { /* implement */ }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
