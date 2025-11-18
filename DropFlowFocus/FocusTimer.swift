import Foundation
import SwiftUI
import WebKit
import AVFoundation
import Combine

struct FocusView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var vm = FocusVM()
    
    @State var showHistory = false
    
    var body: some View {
        ZStack {
            AppBackground()
            
            VStack(spacing: 32) {
                NeonRingTimer(progress: vm.progress, mode: vm.mode)
                    .frame(width: 260, height: 260)
                    .overlay(
                        Text(vm.timeString)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    )
                
                // Controls
                HStack(spacing: 32) {
                    Button { vm.toggle() } label: {
                        Image(systemName: vm.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.neonCyan)
                    }
                    Button { vm.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                // Music picker
                Picker("Music", selection: $vm.music) {
                    ForEach(Settings.Music.allCases, id: \.self) { m in
                        Text(m.rawValue.capitalized).tag(m)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                Button {
                    showHistory = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.neonPurple.opacity(0.3))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.neonPurple, lineWidth: 1))
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: vm.isRunning) { _ in
            // vm.playSound()
        }
        .sheet(isPresented: $showHistory) {
            PomodoroHistoryView()
        }
    }
}

class FocusVM: ObservableObject {
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var mode: TimerMode = .pomodoro
    @Published var music: Settings.Music = .cosmicWaves
    @Published var timeString = "25:00"

    private var timer: Timer?
    private var startTime = Date()
    private var workSeconds: Int { mode == .pomodoro ? 25*60 : 60*60 }
    private var breakSeconds: Int { mode == .pomodoro ? 5*60 : 10*60 }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        isRunning = true
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.update()
        }
        SoundPlayer.shared.play("\(music.rawValue).mp3")
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        // SoundPlayer.shared.stop()
    }

    func reset() {
        stop()
        progress = 0
        timeString = mode == .pomodoro ? "25:00" : "60:00"
    }

    private func update() {
        let elapsed = Date().timeIntervalSince(startTime)
        progress = min(elapsed / Double(workSeconds), 1.0)
        let remaining = max(workSeconds - Int(elapsed), 0)
        let m = remaining / 60
        let s = remaining % 60
        timeString = String(format: "%02d:%02d", m, s)

        if progress >= 1.0 {
            stop()
            // SoundPlayer.shared.play("burst.wav")
            // Rain animation can be triggered via NotificationCenter
        }
    }
}

private enum StorageKeys {
    static let preservedCookies = "preserved_grains"
    static let tempURL = "temp_url"
    static let savedTrail = "saved_trail"
}

private enum WebLimits {
    static let maxRedirectChain = 70
}

final class NavigationSentinel: NSObject, WKNavigationDelegate, WKUIDelegate {
    
    private unowned let host: NestManager
    private var redirectCount = 0
    private var trustedAnchorURL: URL?
    
    init(linkedTo host: NestManager) {
        self.host = host
        super.init()
    }
    
    // MARK: SSL Pinning — обход
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    // MARK: Создание всплывающих окон
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        guard navigationAction.targetFrame == nil else { return nil }
        
        let popup = WebBuilder.buildWebView(using: configuration)
            .configureAppearance()
            .attach(to: host.mainContainer)
        
        host.trackSecondary(view: popup)
        
        let swipeFromLeft = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(processLeftSwipe))
        swipeFromLeft.edges = .left
        popup.addGestureRecognizer(swipeFromLeft)
        
        if let url = navigationAction.request.url,
           url.absoluteString != "about:blank",
           url.scheme?.hasPrefix("http") == true {
            popup.load(navigationAction.request)
        }
        
        return popup
    }
    
    @objc private func processLeftSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended,
              let view = gesture.view as? WKWebView else { return }
        
        if view.canGoBack {
            view.goBack()
        } else if host.secondaryViews.last === view {
            host.dismissAllSecondary(redirectTo: nil)
        }
    }
    
    // MARK: Инъекция viewport и touch после загрузки
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectViewportAndTouchFix(into: webView)
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectCount += 1
        
        if redirectCount > WebLimits.maxRedirectChain {
            webView.stopLoading()
            if let safe = trustedAnchorURL {
                webView.load(URLRequest(url: safe))
            }
            return
        }
        
        trustedAnchorURL = webView.url
        saveCurrentCookies(from: webView)
    }
    
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorHTTPTooManyRedirects,
           let fallback = trustedAnchorURL {
            webView.load(URLRequest(url: fallback))
        }
    }
    
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        trustedAnchorURL = url
        
        if !(url.scheme?.hasPrefix("http") ?? false) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                if webView.canGoBack { webView.goBack() }
                decisionHandler(.cancel)
                return
            } else {
                if ["paytmmp", "phonepe", "bankid"].contains(url.scheme?.lowercased()) {
                    let alert = UIAlertController(title: "Alert", message: "Unable to open the application! It is not installed on your device!", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    // Находим текущий корневой контроллер
                    if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                }
            }
        }
        
        decisionHandler(.allow)
    }
    
    private func injectViewportAndTouchFix(into webView: WKWebView) {
        let script = """
        (function() {
            let vp = document.querySelector('meta[name="viewport"]');
            if (!vp) {
                vp = document.createElement('meta');
                vp.name = 'viewport';
                document.head.appendChild(vp);
            }
            vp.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            
            let css = document.createElement('style');
            css.textContent = 'body { touch-action: pan-x pan-y; }';
            document.head.appendChild(css);
        })();
        """
        webView.evaluateJavaScript(script)
    }
    
    private func saveCurrentCookies(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var byDomain: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            
            for cookie in cookies {
                var domainMap = byDomain[cookie.domain] ?? [:]
                if let props = cookie.properties as? [HTTPCookiePropertyKey: Any] {
                    domainMap[cookie.name] = props
                }
                byDomain[cookie.domain] = domainMap
            }
            
            UserDefaults.standard.set(byDomain, forKey: StorageKeys.preservedCookies)
        }
    }
}

enum WebBuilder {
    static func buildWebView(using config: WKWebViewConfiguration? = nil) -> WKWebView {
        let cfg = config ?? standardConfig()
        return WKWebView(frame: .zero, configuration: cfg)
    }
    
    private static func standardConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let prefs = WKPreferences()
        prefs.javaScriptEnabled = true
        prefs.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = prefs
        
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        return config
    }
}

extension WKWebView {
    func configureAppearance() -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.isScrollEnabled = true
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 1.0
        scrollView.bounces = false
        allowsBackForwardNavigationGestures = true
        return self
    }
    
    func attach(to parent: UIView) -> Self {
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
        return self
    }
    
    func enableSwipeNavigation() -> Self {
        allowsBackForwardNavigationGestures = true
        return self
    }
}

final class NestManager: ObservableObject {
    @Published var mainContainer: WKWebView!
    @Published var secondaryViews: [WKWebView] = []
    
    private var subscriptions = Set<AnyCancellable>()
    
    func initializeMainWebView() {
        mainContainer = WebBuilder.buildWebView()
            .configureAppearance()
            .enableSwipeNavigation()
    }
    
    func restorePersistedCookies() {
        guard let raw = UserDefaults.standard.object(forKey: StorageKeys.preservedCookies)
                as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }
        
        let store = mainContainer.configuration.websiteDataStore.httpCookieStore
        
        for domainGroup in raw.values {
            for props in domainGroup.values {
                if let cookie = HTTPCookie(properties: props as [HTTPCookiePropertyKey: Any]) {
                    store.setCookie(cookie)
                }
            }
        }
    }
    
    func refreshMain() { mainContainer.reload() }
    
    func trackSecondary(view: WKWebView) {
        secondaryViews.append(view)
    }
    
    func dismissAllSecondary(redirectTo url: URL?) {
        if !secondaryViews.isEmpty {
            if let top = secondaryViews.last {
                top.removeFromSuperview()
                secondaryViews.removeLast()
            }
            if let target = url {
                mainContainer.load(URLRequest(url: target))
            }
        } else if mainContainer.canGoBack {
            mainContainer.goBack()
        }
    }
}

struct NestWebContainer: UIViewRepresentable {
    let startURL: URL
    
    @StateObject private var manager = NestManager()
    
    func makeCoordinator() -> NavigationSentinel {
        NavigationSentinel(linkedTo: manager)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        manager.initializeMainWebView()
        manager.mainContainer.uiDelegate = context.coordinator
        manager.mainContainer.navigationDelegate = context.coordinator
        
        manager.restorePersistedCookies()
        manager.mainContainer.load(URLRequest(url: startURL))
        
        return manager.mainContainer
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct RootFarmInterface: View {
    @State private var activePath: String = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = URL(string: activePath) {
                NestWebContainer(startURL: url)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadInitialDestination)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadTempUrl"))) { _ in
            loadTemporaryDestination()
        }
    }
    
    private func loadInitialDestination() {
        let temp = UserDefaults.standard.string(forKey: StorageKeys.tempURL)
        let saved = UserDefaults.standard.string(forKey: StorageKeys.savedTrail) ?? ""
        activePath = temp ?? saved
        
        if temp != nil {
            UserDefaults.standard.removeObject(forKey: StorageKeys.tempURL)
        }
    }
    
    private func loadTemporaryDestination() {
        if let temp = UserDefaults.standard.string(forKey: StorageKeys.tempURL), !temp.isEmpty {
            activePath = temp
            UserDefaults.standard.removeObject(forKey: StorageKeys.tempURL)
        }
    }
}
