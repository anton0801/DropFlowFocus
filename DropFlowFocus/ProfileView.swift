
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
                }

                Section("Privacy & Contact") {
                    Button {
                        UIApplication.shared.open(URL(string: "https://dropfllowfocus.com/privacy-policy.html")!)
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    Button {
                        UIApplication.shared.open(URL(string: "https://dropfllowfocus.com/support.html")!)
                    } label: {
                        HStack {
                            Text("Contact us")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
