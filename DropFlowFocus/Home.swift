import Foundation
import SwiftUI

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
//
//struct DropView: View {
//    @State private var offset = CGSize.zero
//    @State private var scale = 1.0
//    @State private var opacity = 1.0
//    @State private var burst = false
//
//    let color: Color
//    let size: CGFloat
//    let onTap: () -> Void
//
//    var body: some View {
//        ZStack {
//            if !burst {
//                Circle()
//                    .fill(color.opacity(0.6))
//                    .frame(width: size, height: size)
//                    .overlay(
//                        Circle()
//                            .stroke(color, lineWidth: 2)
//                            .blur(radius: 4)
//                    )
//                    .shadow(color: color, radius: 8)
//                    .scaleEffect(scale)
//                    .opacity(opacity)
//                    .offset(offset)
//                    .onAppear {
//                        withAnimation(.easeInOut(duration: 1.0)) {
//                            offset.height = 300
//                        }
//                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(1.0)) {
//                            offset.height = 0
//                            scale = 1.15
//                        }
//                        withAnimation(.easeOut.delay(1.4)) { scale = 1.0 }
//                    }
//            }
//
//            if burst {
//                ForEach(0..<8) { i in
//                    Circle()
//                        .fill(color)
//                        .frame(width: 6, height: 6)
//                        .offset(
//                            x: CGFloat.random(in: -30...30),
//                            y: CGFloat.random(in: -30...30)
//                        )
//                        .opacity(0.8)
//                        .scaleEffect(0.5)
//                        .animation(.easeOut(duration: 0.6), value: burst)
//                }
//            }
//        }
//        .onTapGesture {
//            SoundPlayer.shared.play("burst.wav")
//            withAnimation(.easeOut(duration: 0.3)) {
//                burst = true
//                scale = 1.5
//                opacity = 0
//            }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
//                onTap()
//                burst = false
//                opacity = 1.0
//                scale = 1.0
//            }
//        }
//    }
//}
