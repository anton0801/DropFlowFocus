import Foundation
import SwiftUI
import CoreMotion

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var timerRingProgress: Double = 0
    @State private var showFocus = false
    
    var body: some View {
        ZStack {
            // animated wave background
            WaveBackground()
            
            VStack(spacing: 24) {
                // Focus Ring
                NeonRingTimer(progress: 0, mode: .pomodoro)
                    .frame(width: 180, height: 180)
                    .onTapGesture { showFocus = true }
                
                GlassPanel {
                    Text(state.quotes.randomElement()?.text ?? "Stay in flow.")
                        .font(.title3).bold()
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // Today’s tasks (drops)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(state.tasks.filter { !$0.isCompleted }) { task in
                            DropView(color: task.priority == 2 ? .neonPink : .neonCyan, size: 60) {
                                if let idx = state.tasks.firstIndex(of: task) {
                                    state.tasks[idx].isCompleted = true
                                    state.saveAll()
                                }
                            }
                            .overlay(Text(task.title.prefix(6) + "...").font(.caption2).bold().foregroundColor(.white))
                        }
                    }
                    .padding(.horizontal)
                }
                
                EnergyFlowView(completed: state.tasks.filter { $0.isCompleted }.count, total: state.tasks.count)
            }
            .padding()
        }
        .sheet(isPresented: $showFocus) { FocusView() }
    }
}

struct WaveBackground: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        GeometryReader { proxy in
            Path { p in
                let h = proxy.size.height
                let w = proxy.size.width
                p.move(to: CGPoint(x: 0, y: h * 0.6))
                for x in stride(from: 0, to: w, by: 2) {
                    let relativeX = x / w
                    let y = h * 0.6 + sin(relativeX * .pi * 4 + phase) * 30
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [.neonPurple.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
        }
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

struct NeonRingTimer: View {
    var progress: Double
    var mode: TimerMode
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 12)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.neonPink, .neonPurple, .neonCyan]), center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
    }
}

struct EnergyFlowView: View {
    let completed: Int
    let total: Int
    
    private var ratio: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    private var dropCount: Int { Int(12 + 28 * ratio) }               // 12 … 40 drops
    private var brightness: Double { 0.3 + 0.7 * ratio }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<dropCount, id: \.self) { i in
                    let angle = Double(i) * .pi * 2 / Double(dropCount)
                    let radius = proxy.size.width * 0.35 * (1 + 0.3 * Double(i % 3))
                    let x = cos(angle) * radius
                    let y = sin(angle) * radius - proxy.size.height * 0.1
                    
                    DropView(
                        color: Color.neonCyan.opacity(brightness),
                        size: 8 + 12 * Double(i % 4) / 3.0
                    ) {
                        // no action – just visual
                    }
                    .offset(x: x, y: y)
                    .animation(
                        .easeInOut(duration: 1.2 + Double(i) * 0.03)
                            .repeatForever(autoreverses: false),
                        value: UUID()
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 120)
        .overlay(
            Text("\(completed)/\(total) • \(Int(ratio*100))%")
                .font(.caption).bold()
                .foregroundColor(.white.opacity(0.8))
                .padding(8)
                .background(Color.glassBG)
                .cornerRadius(12),
            alignment: .bottom
        )
    }
}

struct LiquidDropPhysicsView: View {
    @State private var drops: [Drop] = []
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(drops) { drop in
                    LiquidDrop(drop: drop)
                        .onAppear {
                            withAnimation(.linear(duration: drop.duration)) {
                                if let idx = drops.firstIndex(where: { $0.id == drop.id }) {
                                    drops[idx].position.y = proxy.size.height + 50
                                }
                            }
                        }
                }
            }
            .onAppear {
                startRain(proxy: proxy)
            }
        }
        .ignoresSafeArea()
    }
    
    private func startRain(proxy: GeometryProxy) {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
            let drop = Drop(
                id: UUID(),
                position: CGPoint(x: .random(in: 50...UIScreen.main.bounds.height - 50), y: -50),
                size: .random(in: 20...40),
                color: [.neonPink, .neonPurple, .neonCyan].randomElement()!,
                duration: .random(in: 2...4)
            )
            drops.append(drop)
            
            // Удаляем старые
            drops.removeAll { $0.position.y > proxy.size.height + 100 }
        }
    }
}

struct Drop: Identifiable {
    let id: UUID
    var position: CGPoint
    let size: CGFloat
    let color: Color
    let duration: TimeInterval
}

struct LiquidDrop: View {
    let drop: Drop
    
    var body: some View {
        Circle()
            .fill(drop.color.opacity(0.6))
            .frame(width: drop.size, height: drop.size)
            .overlay(Circle().stroke(drop.color, lineWidth: 2).blur(radius: 4))
            .shadow(color: drop.color, radius: 8)
            .position(drop.position)
    }
}

struct ParallaxBackground: View {
    @StateObject private var motion = MotionManager()
    
    var body: some View {
        ZStack {
            // Layer 1: Deep background
            AppBackground()
                .offset(x: motion.roll * 30, y: motion.pitch * 30)
            
            // Layer 2: Wave
            WaveBackground()
                .offset(x: motion.roll * 15, y: motion.pitch * 15)
                .opacity(0.7)
            
            // Layer 3: Drops
            LiquidDropPhysicsView()
                .offset(x: motion.roll * 8, y: motion.pitch * 8)
        }
        .ignoresSafeArea()
    }
}

class MotionManager: ObservableObject {
    @Published var roll: CGFloat = 0
    @Published var pitch: CGFloat = 0
    
    private let motionManager = CMMotionManager()
    
    init() {
        motionManager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let attitude = data?.attitude else { return }
            self.roll = CGFloat(attitude.roll)
            self.pitch = CGFloat(attitude.pitch)
        }
    }
}
