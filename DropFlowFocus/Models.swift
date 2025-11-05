import Foundation

// MARK: - Task
struct Task: Identifiable, Codable, Equatable {
    let id = UUID()
    var title: String
    var deadline: Date?
    var tags: [String] = []
    var priority: Int = 0
    var category: Category = .work
    var subtasks: [Subtask] = []
    var isCompleted = false

    enum Category: String, CaseIterable, Codable {
        case work, personal, health, focus, learning
    }
    
    static func ==(l: Task, r: Task) -> Bool {
        return l.id == r.id
    }
}

struct Subtask: Identifiable, Codable {
    let id = UUID()
    var title: String
    var isDone = false
}

struct Habit: Identifiable, Codable {
    let id = UUID()
    var name: String
    var streak: Int = 0
    var history: [Date: Bool] = [:]
}

// MARK: - Quote
struct Quote: Identifiable, Codable {
    let id = UUID()
    var text: String
    var category: QuoteCategory
    
    enum QuoteCategory: String, CaseIterable, Codable {
        case focus, balance, calm, power, custom
    }
}

// MARK: - FocusSession
struct FocusSession: Identifiable, Codable {
    let id = UUID()
    var start: Date
    var duration: TimeInterval
    var mode: TimerMode
}

enum TimerMode: String, CaseIterable, Codable {
    case pomodoro, deepWork, custom
}
