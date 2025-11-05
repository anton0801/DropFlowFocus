import SwiftUI
import Foundation
import AVFoundation

@main
struct DropFlowFocusApp: App {
    @StateObject private var state = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Global Colors & Gradient
extension Color {
    static let bgTop      = Color(hex: "0D0D1A")
    static let bgMid      = Color(hex: "2B0D4F")
    static let bgBottom   = Color(hex: "39105E")
    static let neonPink   = Color(hex: "FF4FBF")
    static let neonPurple = Color(hex: "B84FFF")
    static let neonCyan   = Color(hex: "4FFFE0")
    static let glassBG    = Color.white.opacity(0.08)
}

// Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

// Global background
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [.bgTop, .bgMid, .bgBottom]),
            startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Glass Panel (Glassmorphism)
struct GlassPanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding()
            .background(Color.glassBG)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}


final class AppState: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var habits: [Habit] = []
    @Published var quotes: [Quote] = Quote.defaultQuotes
    @Published var sessions: [FocusSession] = []
    @Published var settings = Settings()

    private let defaults = UserDefaults.standard

    init() { loadAll() }

    func saveAll() {
        save(tasks, key: "tasks")
        save(habits, key: "habits")
        save(quotes, key: "quotes")
        save(sessions, key: "sessions")
        save(settings, key: "settings")
    }

    private func loadAll() {
        tasks = load(key: "tasks") ?? []
        habits = load(key: "habits") ?? []
        quotes = load(key: "quotes") ?? Quote.defaultQuotes
        sessions = load(key: "sessions") ?? []
        settings = load(key: "settings") ?? Settings()
    }

    private func save<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<T: Codable>(key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

struct Settings: Codable {
    var theme: Theme = .calmViolet
    var animationSpeed: Double = 1.0
    var defaultMusic: Music = .cosmicWaves
    var pushReminders = true

    enum Theme: String, CaseIterable, Codable { case calmViolet, cyberBlue }
    enum Music: String, CaseIterable, Codable { case whiteNoise, rain, forest, cosmicWaves }
}


class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?
    
    func play(_ name: String) {
//        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { return }
//        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
//        player = try? AVAudioPlayer(contentsOf: url)
//        player?.play()
    }
}

extension Quote {
    static let defaultQuotes: [Quote] = [
        Quote(text: "The best way to get started is to quit talking and begin doing.", category: .focus),
        Quote(text: "Don’t watch the clock; do what it does. Keep going.", category: .focus),
        Quote(text: "The secret of getting ahead is getting started.", category: .balance),
        Quote(text: "You don’t have to be great to start, but you have to start to be great.", category: .power),
        Quote(text: "Breathe. It’s just a bad day, not a bad life.", category: .calm),
        Quote(text: "Your speed doesn’t matter, forward is forward.", category: .balance),
        Quote(text: "Focus on being productive instead of busy.", category: .focus),
        Quote(text: "The only limit to our realization of tomorrow is today’s doubts.", category: .power)
    ]
}
