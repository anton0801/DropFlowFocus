
import Foundation
import SwiftUI

struct TasksView: View {
    @EnvironmentObject var state: AppState
    @State private var showingAdd = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(TaskItem.Category.allCases, id: \.self) { cat in
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
    let task: TaskItem
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
    @State private var selectedCategory: TaskItem.Category = .work
    @State private var priority: Int = 0
    
    @State private var recurrenceFreq: Recurrence.Frequency? = nil
    @State private var recurrenceInterval = 1
    @State private var tagsInput = ""
    @State private var tags: [String] = []
    
    var body: some View {
        NavigationView {
            Form {
                Section("Title") {
                    TextField("What needs to be done?", text: $title)
                }
                
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(TaskItem.Category.allCases, id: \.self) { cat in
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
                
                Section("Recurrence") {
                    Picker("Repeat", selection: $recurrenceFreq) {
                        Text("Never").tag(Optional<Recurrence.Frequency>.none)
                        ForEach(["daily", "weekly", "monthly"], id: \.self) { f in
                            Text(f).tag(f.toFrequency())
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    if recurrenceFreq != nil {
                        Stepper("Every \(recurrenceInterval) \(recurrenceFreq!.rawValue)", value: $recurrenceInterval, in: 1...30)
                    }
                }
                
                Section("Tags") {
                    TextField("work, gym, urgent", text: $tagsInput)
                        .onSubmit {
                            let newTags = tagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                            tags.append(contentsOf: newTags.filter { !tags.contains($0) && !$0.isEmpty })
                            tagsInput = ""
                        }
                    FlowLayout {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .padding(8)
                                .background(Color.neonPurple.opacity(0.3))
                                .cornerRadius(12)
                                .onTapGesture { tags.removeAll { $0 == tag } }
                        }
                    }
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
//                        let new = Task(title: title,
//                                       deadline: deadline,
//                                       priority: priority,
//                                       category: selectedCategory)
//                        state.tasks.append(new)
//                        state.saveAll()
//                        SoundPlayer.shared.play("drop.wav")
//                        dismiss()
                        let recurrence: Recurrence? = recurrenceFreq.map {
                            Recurrence(frequency: $0, interval: recurrenceInterval)
                        }
                        
                        let newTask = TaskItem(
                            title: title,
                            deadline: deadline,
                            tags: tags,
                            priority: priority,
                            category: selectedCategory,
                            recurrence: recurrence
                        )
                        state.tasks.append(newTask)
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

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for size in sizes {
            if lineWidth + size.width > proposal.width ?? 0 {
                height += lineHeight
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += size.width + 8
                lineHeight = max(lineHeight, size.height)
            }
            width = max(width, lineWidth)
        }
        height += lineHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX {
                point.x = bounds.minX
                point.y += lineHeight + 8
                lineHeight = 0
            }
            subview.place(at: point, proposal: .unspecified)
            point.x += size.width + 8
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    AddTaskView().environmentObject(AppState())
}
