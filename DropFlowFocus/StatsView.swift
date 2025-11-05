import Foundation
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var vm: StatsVM = StatsVM()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                HeatmapView(data: vm.heatmapData)
                    .frame(height: 300)
                
                // Charts
                BarChartView(data: vm.dailyFocus)
                    .frame(height: 200)
                
                // Achievements
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: 16) {
                    ForEach(vm.achievements, id: \.self) { ach in
                        AchievementBadge(achievement: ach)
                    }
                }
            }
            .padding()
            .onAppear {
                vm.setState(state)
            }
        }
        .navigationTitle("Stats")
    }
}

final class StatsVM: ObservableObject {
    @Published var heatmapData: [Date: Double] = [:]
    @Published var dailyFocus: [(day: String, minutes: Int)] = []
    @Published var achievements: [Achievement] = []

    private var state: AppState!
    
    func setState(_ s: AppState) {
        self.state = s
        self.computeAll()
    }

    func computeAll() {
        computeHeatmap()
        computeDailyFocus()
        computeAchievements()
    }

    private func computeHeatmap() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [Date: Double] = [:]
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let completed = state.tasks.filter { $0.isCompleted && calendar.isDate($0.deadline ?? Date(), inSameDayAs: date) }.count
                let total = state.tasks.filter { calendar.isDate($0.deadline ?? Date(), inSameDayAs: date) }.count
                data[date] = total > 0 ? Double(completed) / Double(total) : 0
            }
        }
        heatmapData = data
    }

    private func computeDailyFocus() {
        let calendar = Calendar.current
        let today = Date()
        var result: [(String, Int)] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                let start = calendar.startOfDay(for: date)
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                let minutes = state.sessions.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + Int($1.duration / 60) }
                let day = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
                result.append((day, minutes))
            }
        }
        dailyFocus = result.reversed()
    }

    private func computeAchievements() {
        let total = state.sessions.reduce(0) { $0 + Int($1.duration / 60) }
        let streak = computeStreak()
        var list: [Achievement] = []
        if streak >= 3 { list.append(.flowStreak) }
        if total >= 100 { list.append(.hundredMinutes) }
        if perfectDay() { list.append(.perfectDay) }
        achievements = list
    }

    private func computeStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var date = calendar.startOfDay(for: Date())
        while !state.sessions.filter { calendar.isDate($0.start, inSameDayAs: date) }.isEmpty {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    private func perfectDay() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let completed = state.tasks.filter { $0.isCompleted && calendar.isDate($0.deadline ?? Date(), inSameDayAs: today) }.count
        let total = state.tasks.filter { calendar.isDate($0.deadline ?? Date(), inSameDayAs: today) }.count
        return completed == total && total > 0
    }
}

enum Achievement: String, CaseIterable, Hashable {
    case flowStreak = "3 Flow Sessions"
    case hundredMinutes = "100 Focus Minutes"
    case perfectDay = "Perfect Day"

    var icon: String {
        switch self {
        case .flowStreak: return "flame.fill"
        case .hundredMinutes: return "timer"
        case .perfectDay: return "checkmark.seal.fill"
        }
    }
}


struct HeatmapView: View {
    let data: [Date: Double]               // date → 0…1
    
    private let columns = 7
    private let rows = 5
    
    var body: some View {
        GeometryReader { proxy in
            let cellSize = proxy.size.width / CGFloat(columns)
            let dates = sortedDates()
            
            LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    let intensity = data[date] ?? 0
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.neonPurple.opacity(0.2 + 0.6 * intensity))
                        .frame(width: cellSize, height: cellSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
            .padding(8)
        }
    }
    
    // last 35 days (5 weeks)
    private func sortedDates() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dates: [Date] = []
        for i in 0..<rows * columns {
            if let d = calendar.date(byAdding: .day, value: -i, to: today) {
                dates.append(d)
            }
        }
        return dates.reversed()
    }
}

struct BarChartView: View {
    let data: [(day: String, minutes: Int)]
    
    var body: some View {
        GeometryReader { proxy in
            let maxValue = CGFloat(data.map(\.minutes).max() ?? 1)
            let barWidth = (proxy.size.width - CGFloat(data.count - 1) * 8) / CGFloat(data.count)
            
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data, id: \.day) { item in
                    VStack {
                        Rectangle()
                            .fill(LinearGradient(gradient: Gradient(colors: [.neonCyan, .neonPurple]), startPoint: .top, endPoint: .bottom))
                            .frame(width: barWidth, height: proxy.size.height * CGFloat(item.minutes) / maxValue)
                            .cornerRadius(4)
                        Text(item.day)
                            .font(.caption2).bold()
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(item.minutes)m")
                            .font(.caption2)
                            .foregroundColor(.neonCyan)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct AchievementBadge: View {
    let achievement: Achievement
    
    var body: some View {
        GlassPanel {
            VStack(spacing: 8) {
                Image(systemName: achievement.icon)
                    .font(.system(size: 32))
                    .foregroundColor(.neonCyan)
                Text(achievement.rawValue)
                    .font(.caption).bold()
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
        }
        .frame(height: 110)
    }
}
