import SwiftUI
import Foundation
import AVFoundation
import UIKit
import Firebase
import UserNotifications
import AppsFlyerLib
import AppTrackingTransparency

final class DropFlowFocusDelegate: UIResponder, UIApplicationDelegate, AppsFlyerLibDelegate, MessagingDelegate, UNUserNotificationCenterDelegate, DeepLinkDelegate {
    
    private let trackingActivationKey = UIApplication.didBecomeActiveNotification
    private var deepLinkClickEvent: [String: Any] = [:]
    private var attrData: [AnyHashable: Any] = [:]
    private var timerMerge: Timer?
    private let keySented = "hasSentAttributionData"
    private let keyTImer = "deepLinkMergeTimer"
    private var keySdf = "deepReceived"
    private var keyDeepexhaud = "keyDeepexhaud"
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
        
        AppsFlyerLib.shared().appsFlyerDevKey = AppConstants.appsFlyerDevKey
        AppsFlyerLib.shared().appleAppID = AppConstants.appsFlyerAppID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().deepLinkDelegate = self
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(startATT),
            name: trackingActivationKey,
            object: nil
        )
        
        if let remotePayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            getDeepLinkFromPushData(from: remotePayload)
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        getDeepLinkFromPushData(from: userInfo)
        completionHandler(.newData)
    }
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = notification.request.content.userInfo
        getDeepLinkFromPushData(from: payload)
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        getDeepLinkFromPushData(from: response.notification.request.content.userInfo)
        completionHandler()
    }
    
    private func scheduleMergeTimer() {
        timerMerge?.invalidate()
        timerMerge = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.sendToSplashMergedDataAttrWithDeeps()
        }
    }
    
    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status,
              let deepLinkObj = result.deepLink else { return }
        guard !UserDefaults.standard.bool(forKey: keySented) else { return }
        deepLinkClickEvent = deepLinkObj.clickEvent
        NotificationCenter.default.post(name: Notification.Name("deeplink_values"), object: nil, userInfo: ["deeplinksData": deepLinkClickEvent])
        timerMerge?.invalidate()
        sendToSplashMergedDataAttrWithDeeps()
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { [weak self] token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: "fcm_token")
            UserDefaults.standard.set(token, forKey: "push_token")
        }
    }
    
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        attrData = data
        scheduleMergeTimer()
        sendToSplashMergedDataAttrWithDeeps()
    }
    
    func onConversionDataFail(_ error: Error) {
        NotificationCenter.default.post(
                    name: Notification.Name("ConversionDataReceived"),
                    object: nil,
                    userInfo: ["conversionData": [:]]
                )
    }
    
    @objc private func startATT() {
        if #available(iOS 14.0, *) {
            AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
            ATTrackingManager.requestTrackingAuthorization { _ in
                DispatchQueue.main.async {
                    AppsFlyerLib.shared().start()
                }
            }
        }
    }
    
    private func getDeepLinkFromPushData(from payload: [AnyHashable: Any]) {
        var retrivedDeepleenk: String?
        
        if let url = payload["url"] as? String {
            retrivedDeepleenk = url
        } else if let data = payload["data"] as? [String: Any],
                  let url = data["url"] as? String {
            retrivedDeepleenk = url
        }
        
        if let deeped = retrivedDeepleenk {
            UserDefaults.standard.set(deeped, forKey: "temp_url")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoadTempURL"),
                    object: nil,
                    userInfo: ["temp_url": deeped]
                )
            }
        }
    }

    private func sendToSplashMergedDataAttrWithDeeps() {
        var merged = attrData
        
        // Добавляем deep link только если он есть и ключей нет
        for (key, value) in deepLinkClickEvent {
            if merged[key] == nil {
                merged[key] = value
            }
        }
        
        NotificationCenter.default.post(
                    name: Notification.Name("ConversionDataReceived"),
                    object: nil,
                    userInfo: ["conversionData": merged]
                )
        UserDefaults.standard.set(true, forKey: keySented)
        timerMerge?.invalidate()
    }
    
}

@main
struct DropFlowFocusApp: App {
    
    @UIApplicationDelegateAdaptor(DropFlowFocusDelegate.self) var delegateDropFlowFocus
    
    var body: some Scene {
        WindowGroup {
            SplashScreen()
        }
    }
}

extension Color {
    static let bgTop      = Color(hex: "0D0D1A")
    static let bgMid      = Color(hex: "2B0D4F")
    static let bgBottom   = Color(hex: "39105E")
    static let neonPink   = Color(hex: "FF4FBF")
    static let neonPurple = Color(hex: "B84FFF")
    static let neonCyan   = Color(hex: "4FFFE0")
    static let glassBG    = Color.white.opacity(0.08)
}

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
    @Published var tasks: [TaskItem] = []
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
