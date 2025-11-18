import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        ZStack {
            // AppBackground()
            ParallaxBackground()
            
            TabView {
                HomeView()
                    .environmentObject(state).tabItem { Label("Home", systemImage: "house") }
                TasksView()
                    .environmentObject(state).tabItem { Label("Tasks", systemImage: "checklist") }
                FocusView()
                    .environmentObject(state).tabItem { Label("Focus", systemImage: "timer") }
                StatsView()
                    .environmentObject(state).tabItem { Label("Stats", systemImage: "chart.bar") }
                ProfileView()
                    .environmentObject(state)
                    .tabItem { Label("Profile", systemImage: "person") }
            }
            .accentColor(.neonCyan)
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - DropView (the glowing ball)
struct DropView: View {
    @State private var offset = CGSize.zero
    @State private var scale  = 1.0
    @State private var opacity = 1.0
    let color: Color
    let size: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Circle()
            .fill(color.opacity(0.6))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .blur(radius: 4)
            )
            .shadow(color: color, radius: 8)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(offset)
            .onAppear {
                // gentle fall & bounce
                withAnimation(.easeInOut(duration: 1.2).repeatCount(1)) {
                    offset.height = UIScreen.main.bounds.height * 0.6
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(1.2)) {
                    offset.height = UIScreen.main.bounds.height * 0.4
                    scale = 1.15
                }
                withAnimation(.easeOut.delay(1.6)) { scale = 1.0 }
            }
            .onTapGesture { onTap() }
    }
}
