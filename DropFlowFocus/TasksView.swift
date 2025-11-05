
import Foundation
import SwiftUI

struct TasksView: View {
    @EnvironmentObject var state: AppState
    @State private var showingAdd = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Task.Category.allCases, id: \.self) { cat in
                    Section(header: Text(cat.rawValue.capitalized).foregroundColor(.neonCyan)) {
                        ForEach(state.tasks.filter { $0.category == cat && !$0.isCompleted }) { task in
                            TaskRow(task: task)
                                .listRowBackground(Color.clear)
                                .environmentObject(state)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("Tasks")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundColor(.neonPink) }
            }
            .sheet(isPresented: $showingAdd) {
                AddTaskView()
            }
        }
    }
}

struct TaskRow: View {
    let task: Task
    @State private var fall = false
    @EnvironmentObject var state: AppState
    
    var body: some View {
        HStack {
            DropView(color: task.priority == 2 ? .neonPink : .neonCyan, size: 44) {
                if let idx = state.tasks.firstIndex(of: task) {
                    state.tasks[idx].isCompleted = true
                    state.saveAll()
                }
            }
            VStack(alignment: .leading) {
                Text(task.title).font(.headline).foregroundColor(.white)
                if let deadline = task.deadline {
                    Text(deadline, style: .relative).font(.caption).foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .offset(y: fall ? 0 : -600)
        .onAppear {
            withAnimation(.easeOut.delay(Double.random(in: 0..<0.3))) {
                fall = true
            }
        }
    }
}

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    
    @State private var title = ""
    @State private var deadline: Date = Date()
    @State private var selectedCategory: Task.Category = .work
    @State private var priority: Int = 0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Title") {
                    TextField("What needs to be done?", text: $title)
                }
                
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(Task.Category.allCases, id: \.self) { cat in
                            Text(cat.rawValue.capitalized).tag(cat)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(0)
                        Text("Medium").tag(1)
                        Text("High").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section {
                    DatePicker("Deadline (optional)", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(CompactDatePickerStyle())
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let new = Task(title: title,
                                       deadline: deadline,
                                       priority: priority,
                                       category: selectedCategory)
                        state.tasks.append(new)
                        state.saveAll()
                        SoundPlayer.shared.play("drop.wav")
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
