import SwiftUI

struct PomodoroHistoryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Фон с параллаксом
            ParallaxBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2.bold())
                            .foregroundColor(.neonCyan)
                            .frame(width: 44, height: 44)
                            .background(Color.glassBG)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    
                    Spacer()
                    
                    Text("Pomodoro History")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Пустой, чтобы выровнять
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .glassPanelBackground()
                
                // Список
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(groupedSessions(), id: \.date) { group in
                            HistorySection(group: group)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarHidden(true)
    }
    
    // Группировка по дням
    private func groupedSessions() -> [(date: Date, sessions: [FocusSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: state.sessions) { session in
            calendar.startOfDay(for: session.start)
        }
        return grouped
            .map { (date: $0.key, sessions: $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Секция дня
struct HistorySection: View {
    let group: (date: Date, sessions: [FocusSession])
    @State private var isExpanded = true
    
    var body: some View {
        GlassPanel {
            VStack(spacing: 12) {
                // Заголовок дня
                HStack {
                    Text(group.date, style: .date)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.neonCyan)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { isExpanded.toggle() } }
                
                // Сессии
                if isExpanded {
                    ForEach(group.sessions) { session in
                        HistoryRow(session: session)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                // Итог дня
                if isExpanded {
                    HStack {
                        Text("Total: \(Int(group.sessions.reduce(0) { $0 + $1.duration } / 60)) min")
                            .font(.caption.bold())
                            .foregroundColor(.neonCyan)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(4)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - Строка сессии
struct HistoryRow: View {
    let session: FocusSession
    @State private var dropFall = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Иконка режима + капля
            ZStack {
                DropView(color: modeColor(session.mode), size: 40, onTap: {})
                    .offset(y: dropFall ? 0 : -100)
                    .opacity(dropFall ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeOut.delay(0.1)) {
                            dropFall = true
                        }
                    }
                
                Image(systemName: session.mode.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.mode.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                
                Text("\(Int(session.duration/60)) min")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Text(session.start, style: .time)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func modeColor(_ mode: TimerMode) -> Color {
        switch mode {
        case .pomodoro: return .neonPink
        case .deepWork: return .neonPurple
        case .custom: return .neonCyan
        }
    }
}

// MARK: - Расширения
extension TimerMode {
    var title: String {
        switch self {
        case .pomodoro: return "Pomodoro"
        case .deepWork: return "Deep Work"
        case .custom: return "Custom"
        }
    }
    
    var icon: String {
        switch self {
        case .pomodoro: return "timer"
        case .deepWork: return "brain"
        case .custom: return "gearshape"
        }
    }
}

extension View {
    func glassPanelBackground() -> some View {
        self
            .background(Color.glassBG)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10)
    }
}

#Preview {
    PomodoroHistoryView()
}
