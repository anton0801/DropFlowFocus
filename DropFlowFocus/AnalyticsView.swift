// Views/Analytics/AnalyticsView.swift
import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
            }
            .padding()
        }
        .navigationTitle("Insights")
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    
    var body: some View {
        GlassPanel {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
                Text(value).font(.title2).bold().foregroundColor(.neonCyan)
            }
        }
    }
}

class AnalyticsVM: ObservableObject {
    var bestTime = "9:00 – 11:00"
    var killers = "Instagram, YouTube"
    var score = 87
    
    func analyze(_ state: AppState) {
        // Реальная аналитика (упрощённо)
        let sessions = state.sessions
        let hour = Calendar.current.component(.hour, from: sessions.max(by: { $0.duration < $1.duration })?.start ?? Date())
        bestTime = "\(hour):00 – \(hour+2):00"
        
        if sessions.count > 0 && state.tasks.count > 0 {
            score = Int((Double(sessions.count) / Double(state.tasks.count) * 100))
        } else {
            score = 0
        }
    }
}

#Preview {
    AnalyticsView()
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
