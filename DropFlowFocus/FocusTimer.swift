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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("pomodoro_finished"))) { _ in
            let session = FocusSession(
                start: Date().addingTimeInterval(-Double(vm.totalSeconds)),
                duration: TimeInterval(vm.totalSeconds),
                mode: vm.mode
            )
            state.sessions.append(session)
            state.saveAll()
        }
    }
}

class FocusVM: ObservableObject {
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var mode: TimerMode = .pomodoro
    @Published var music: Settings.Music = .cosmicWaves
    @Published var timeString = "25:00"
    
    // MARK: - Private
    var totalSeconds: Int = 25 * 60
    private var remainingSeconds: Int = 25 * 60
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    
    init() {
        setupTimer()
    }
    
    // MARK: - Public API
    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer?.cancel()
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }
    
    func pause() {
        isRunning = false
        timer?.cancel()
    }
    
    func toggle() {
        isRunning ? pause() : start()
    }
    
    func reset() {
        pause()
        remainingSeconds = totalSeconds
        updateDisplay()
        progress = 0
    }
    
    func changeMode(_ newMode: TimerMode) {
        let wasRunning = isRunning
        pause()
        mode = newMode
        totalSeconds = mode.duration
        remainingSeconds = totalSeconds
        updateDisplay()
        progress = 0
        if wasRunning { start() }
    }
    
    // MARK: - Private
    private func setupTimer() {
        totalSeconds = mode.duration
        remainingSeconds = totalSeconds
        updateDisplay()
    }
    
    private func tick() {
        guard remainingSeconds > 0 else {
            finishSession()
            return
        }
        remainingSeconds -= 1
        updateDisplay()
    }
    
    private func updateDisplay() {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        timeString = String(format: "%02d:%02d", minutes, seconds)
        progress = 1.0 - Double(remainingSeconds) / Double(totalSeconds)
    }
    
    private func finishSession() {
        pause()
        progress = 1.0
        timeString = "00:00"
        
        NotificationCenter.default.post(name: Notification.Name("pomodoro_finished"), object: nil)
    }
    
}

extension TimerMode {
    var duration: Int {
        switch self {
        case .pomodoro: return 25 * 60
        case .deepWork: return 90 * 60
        case .custom:   return 60 * 60
        }
    }
    
}

final class FlowGuardian: NSObject, WKNavigationDelegate, WKUIDelegate {
    
    private weak var colony: ColonyController?
    private var redirectStreak = 0
    private let maxAllowedRedirects = 70
    private var lastKnownGoodURL: URL?
    
    init(colony: ColonyController) {
        self.colony = colony
        super.init()
    }
    
    // SSL Pinning Bypass
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
    
    // Открытие попапов
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        guard navigationAction.targetFrame == nil else { return nil }
        
        let popup = PortalFactory.createStandardWebView(with: configuration)
        setupPopupAppearance(popup)
        attachPopupToHierarchy(popup)
        
        colony?.overlayPortals.append(popup)
        
        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeDrag))
        edgeSwipe.edges = .left
        popup.addGestureRecognizer(edgeSwipe)
        
        if shouldLoadRequest(navigationAction.request) {
            popup.load(navigationAction.request)
        }
        
        return popup
    }
    
    @objc private func handleEdgeDrag(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended,
              let webView = gesture.view as? WKWebView else { return }
        
        if webView.canGoBack {
            webView.goBack()
        } else if colony?.overlayPortals.last === webView {
            colony?.dismissAllOverlays(returnTo: nil)
        }
    }
    
    // Блокировка зума и жестов
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let lockdownJS = """
        (function() {
            const vp = document.createElement('meta');
            vp.name = 'viewport';
            vp.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            document.head.appendChild(vp);
            
            const style = document.createElement('style');
            style.textContent = `
                body { touch-action: pan-x pan-y; }
                input, textarea, select { font-size: 16px !important; }
            `;
            document.head.appendChild(style);
            
            document.addEventListener('gesturestart', e => e.preventDefault(), false);
            document.addEventListener('gesturechange', e => e.preventDefault(), false);
        })();
        """
        
        webView.evaluateJavaScript(lockdownJS) { _, error in
            if let error = error { print("Viewport lock failed: \(error)") }
        }
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    // Защита от редирект-лупов
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectStreak += 1
        
        if redirectStreak > maxAllowedRedirects {
            webView.stopLoading()
            if let safe = lastKnownGoodURL {
                webView.load(URLRequest(url: safe))
            }
            return
        }
        
        lastKnownGoodURL = webView.url
        persistCookiesIfNeeded(from: webView)
    }
    
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorHTTPTooManyRedirects,
           let fallback = lastKnownGoodURL {
            webView.load(URLRequest(url: fallback))
        }
    }
    
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if let url = navigationAction.request.url {
            lastKnownGoodURL = url
            
            if url.scheme?.hasPrefix("http") != true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    private func setupPopupAppearance(_ webView: WKWebView) {
        webView
            .disableTranslates()
            .enableScrolling()
            .lockZoomScale(min: 1.0, max: 1.0)
            .disableBouncing()
            .enableSwipeNavigation()
            .assignDelegates(self)
            .embedInto(colony!.rootContainer)
    }
    
    private func attachPopupToHierarchy(_ webView: WKWebView) {
        webView.pinToEdges(of: colony!.rootContainer)
    }
    
    private func shouldLoadRequest(_ request: URLRequest) -> Bool {
        guard let urlString = request.url?.absoluteString,
              !urlString.isEmpty,
              urlString != "about:blank" else { return false }
        return true
    }
    
    private func persistCookiesIfNeeded(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var groupedByDomain: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            
            for cookie in cookies {
                var domainDict = groupedByDomain[cookie.domain] ?? [:]
                if let props = cookie.properties as? [HTTPCookiePropertyKey: Any] {
                    domainDict[cookie.name] = props
                }
                groupedByDomain[cookie.domain] = domainDict
            }
            
            UserDefaults.standard.set(groupedByDomain, forKey: "preserved_grains")
        }
    }
}

// MARK: - Расширения для удобной цепочки настройки WKWebView
private extension WKWebView {
    func disableTranslates() -> Self { translatesAutoresizingMaskIntoConstraints = false; return self }
    func enableScrolling() -> Self { scrollView.isScrollEnabled = true; return self }
    func lockZoomScale(min: CGFloat, max: CGFloat) -> Self { scrollView.minimumZoomScale = min; scrollView.maximumZoomScale = max; return self }
    func disableBouncing() -> Self { scrollView.bounces = false; scrollView.bouncesZoom = false; return self }
    func enableSwipeNavigation() -> Self { allowsBackForwardNavigationGestures = true; return self }
    func assignDelegates(_ delegate: Any) -> Self {
        navigationDelegate = delegate as? WKNavigationDelegate
        uiDelegate = delegate as? WKUIDelegate
        return self
    }
    func embedInto(_ parent: UIView) -> Self { parent.addSubview(self); return self }
    func pinToEdges(of view: UIView, insets: UIEdgeInsets = .zero) -> Self {
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
        ])
        return self
    }
}

// MARK: - Фабрика веб-вью
enum PortalFactory {
    static func createStandardWebView(with config: WKWebViewConfiguration? = nil) -> WKWebView {
        let configuration = config ?? baseConfiguration()
        return WKWebView(frame: .zero, configuration: configuration)
    }
    
    private static func baseConfiguration() -> WKWebViewConfiguration {
        WKWebViewConfiguration()
            .allowInlineVideo()
            .removeAutoplayBlocks()
            .applyPreferences(jsPreferences())
            .applyPagePreferences(contentPreferences())
    }
    
    private static func jsPreferences() -> WKPreferences {
        WKPreferences()
            .jsEnabled()
            .allowPopups()
    }
    
    private static func contentPreferences() -> WKWebpagePreferences {
        WKWebpagePreferences().contentJSEnabled()
    }
}

private extension WKWebViewConfiguration {
    func allowInlineVideo() -> Self { allowsInlineMediaPlayback = true; return self }
    func removeAutoplayBlocks() -> Self { mediaTypesRequiringUserActionForPlayback = []; return self }
    func applyPreferences(_ prefs: WKPreferences) -> Self { preferences = prefs; return self }
    func applyPagePreferences(_ prefs: WKWebpagePreferences) -> Self { defaultWebpagePreferences = prefs; return self }
}

private extension WKPreferences {
    func jsEnabled() -> Self { javaScriptEnabled = true; return self }
    func allowPopups() -> Self { javaScriptCanOpenWindowsAutomatically = true; return self }
}

private extension WKWebpagePreferences {
    func contentJSEnabled() -> Self { allowsContentJavaScript = true; return self }
}

// MARK: - Контроллер колонии (бывший HenNestManager)
final class ColonyController: ObservableObject {
    @Published var rootContainer: WKWebView!
    @Published var overlayPortals: [WKWebView] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    func initializePrimaryPortal() {
        rootContainer = PortalFactory.createStandardWebView()
            .configureScroll(minZoom: 1.0, maxZoom: 1.0, bounce: false)
            .enableSwipeNavigation()
    }
    
    func restoreSavedGrains() {
        guard let raw = UserDefaults.standard.object(forKey: "preserved_grains") as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else {
            return
        }
        
        let store = rootContainer.configuration.websiteDataStore.httpCookieStore
        let allProps = raw.values.flatMap { $0.values }
        
        for props in allProps {
            if let cookie = HTTPCookie(properties: props as [HTTPCookiePropertyKey: Any]) {
                store.setCookie(cookie)
            }
        }
    }
    
    func refreshPrimary() {
        rootContainer.reload()
    }
    
    func dismissAllOverlays(returnTo url: URL? = nil) {
        if !overlayPortals.isEmpty {
            if let topExtra = overlayPortals.last {
                topExtra.removeFromSuperview()
                overlayPortals.removeLast()
            }
            if let trail = url {
                rootContainer.load(URLRequest(url: trail))
            }
        } else if rootContainer.canGoBack {
            rootContainer.goBack()
        }
    }
}

private extension WKWebView {
    func configureScroll(minZoom: CGFloat, maxZoom: CGFloat, bounce: Bool) -> Self {
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.bounces = bounce
        scrollView.bouncesZoom = bounce
        return self
    }
}

struct CoreFlowView: UIViewRepresentable {
    let initialURL: URL
    
    @StateObject private var colony = ColonyController()
    
    func makeCoordinator() -> FlowGuardian {
        FlowGuardian(colony: colony)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        colony.initializePrimaryPortal()
        colony.rootContainer.uiDelegate = context.coordinator
        colony.rootContainer.navigationDelegate = context.coordinator
        
        colony.restoreSavedGrains()
        colony.rootContainer.load(URLRequest(url: initialURL))
        
        return colony.rootContainer
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

// MARK: - Главный экран
struct DropFlowFocus: View {
    @State private var currentURLString = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = URL(string: currentURLString) {
                CoreFlowView(initialURL: url)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: applyInitialURL)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadTempUrl"))) { _ in
            applyTemporaryURLIfNeeded()
        }
    }
    
    private func applyInitialURL() {
        let temp = UserDefaults.standard.string(forKey: "temp_url")
        let saved = UserDefaults.standard.string(forKey: "saved_trail") ?? ""
        currentURLString = temp ?? saved
        
        if temp != nil {
            UserDefaults.standard.removeObject(forKey: "temp_url")
        }
    }
    
    private func applyTemporaryURLIfNeeded() {
        if let temp = UserDefaults.standard.string(forKey: "temp_url"), !temp.isEmpty {
            currentURLString = temp
            UserDefaults.standard.removeObject(forKey: "temp_url")
        }
    }
}
