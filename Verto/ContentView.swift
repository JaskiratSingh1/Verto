import SwiftUI

// MARK: - DATA + VIEW-MODEL (all in one)

@MainActor
final class VertoViewModel: ObservableObject {
    // MARK: Task model
    struct Task: Identifiable, Codable {
        let id: UUID
        var title: String
        var isDone: Bool
        var day: Date               // midnight of owning date

        init(title: String, day: Date) {
            self.id = UUID()
            self.title = title
            self.isDone = false
            self.day = day
        }
    }

    // MARK: Theme model
    enum Theme: String, CaseIterable, Codable, Identifiable {
        case indigo, green, orange, pink
        var id: String { rawValue }
        var accent: Color {
            switch self { case .indigo: .indigo; case .green: .green; case .orange: .orange; case .pink: .pink }
        }
        var colorScheme: ColorScheme? { nil }
    }

    // MARK: Published state
    @Published private(set) var tasksByDay: [Date:[Task]] = [:]
    @AppStorage("vertoTheme") private var savedTheme = Theme.indigo.rawValue

    var theme: Theme {
        get { Theme(rawValue: savedTheme) ?? .indigo }
        set { savedTheme = newValue.rawValue }
    }

    // MARK: File persistence (JSON)
    private let url: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: folder,
                                                 withIntermediateDirectories: true)
        return folder.appendingPathComponent("tasks.json")
    }()

    init() { load() }

    // MARK: CRUD helpers
    func tasks(for day: Date) -> [Task] { tasksByDay[day.startOfDay, default: []] }

    func addTask(_ text: String, to day: Date) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let key = day.startOfDay
        guard tasksByDay[key, default: []].count < 7 else { return }
        tasksByDay[key, default: []].append(Task(title: title, day: key))
        save()
    }

    func toggle(_ task: Task) {
        mutate(task) { $0.isDone.toggle() }
    }
    func delete(_ task: Task) {
        mutate(task) { _ in } remove: { $0.id == task.id }
    }

    // MARK: private helpers
    private func mutate(_ task: Task,
                        update: (inout Task)->Void,
                        remove: ((Task)->Bool)? = nil) {
        let key = task.day
        guard var list = tasksByDay[key] else { return }
        if let idx = list.firstIndex(where: { $0.id == task.id }) {
            if let remove, remove(list[idx]) {
                list.remove(at: idx)
            } else { update(&list[idx]) }
            tasksByDay[key] = list
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        tasksByDay = (try? dec.decode([Date:[Task]].self, from: data)) ?? [:]
    }

    private func save() {
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted; enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(tasksByDay) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - VIEW HIERARCHY (Today + Settings)

struct ContentView: View {
    @EnvironmentObject private var vm: VertoViewModel
    @State private var newTitle = ""

    var body: some View {
        TabView {
            todayTab
                .tabItem { Label("Today", systemImage: "checklist") }

            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }

    // MARK: Today

    private var todayTab: some View {
        let today = Date.now.startOfDay
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                Text(Date.now.formatted(.dateTime.weekday().day().month().year()))
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(vm.tasks(for: today)) { task in
                    TaskRow(task: task)
                }

                if vm.tasks(for: today).count < 7 {
                    HStack {
                        TextField("New task", text: $newTitle)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            vm.addTask(newTitle, to: today)
                            newTitle = ""
                        } label: { Image(systemName:"plus") }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Settings

    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 32) {
                CalendarHeatmap(stats: monthlyStats)

                // Theme picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme").font(.headline)
                    HStack {
                        ForEach(VertoViewModel.Theme.allCases) { th in
                            Circle()
                                .fill(th.accent)
                                .frame(width:34,height:34)
                                .overlay { if th == vm.theme { Image(systemName:"checkmark").foregroundStyle(.white) } }
                                .onTapGesture { vm.theme = th }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Settings")
        }
    }

    // MARK: Stats helper for calendar

    private var monthlyStats: [DayStat] {
        Calendar.current.generateDates(
            inside: Calendar.current.dateInterval(of: .month, for: .now)!,
            matching: DateComponents(hour:0,minute:0,second:0)
        )
        .map { date in
            let tasks = vm.tasks(for: date)
            let rate = tasks.isEmpty ? 0 : Double(tasks.filter(\.isDone).count)/Double(tasks.count)
            return DayStat(date: date, rate: rate)
        }
    }

    // MARK: Subviews

    struct TaskRow: View {
        @EnvironmentObject private var vm: VertoViewModel
        let task: VertoViewModel.Task
        var body: some View {
            HStack {
                Button { vm.toggle(task) } label: {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                }.buttonStyle(.plain)

                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .frame(maxWidth:.infinity,alignment:.leading)

                Button(role: .destructive) { vm.delete(task) } label: {
                    Image(systemName:"trash")
                }.buttonStyle(.plain)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    struct DayStat: Identifiable { let id = UUID(); let date:Date; let rate:Double }

    struct CalendarHeatmap: View {
        let stats: [DayStat]
        private let cols = Array(repeating: GridItem(.flexible()), count: 7)
        var body: some View {
            VStack(alignment: .leading) {
                Text("Completion History").font(.headline)
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(stats) { s in
                        Rectangle()
                            .fill(color(for:s.rate))
                            .aspectRatio(1,contentMode:.fit)
                            .cornerRadius(3)
                            .opacity(s.rate == 0 ? 0.15 : 1)
                            .overlay {
                                if Calendar.current.isDateInToday(s.date) {
                                    RoundedRectangle(cornerRadius:3).stroke(.primary,lineWidth:2)
                                }
                            }
                    }
                }
            }
        }
        private func color(for rate:Double)->Color {
            switch rate { case 1: .green; case 0..<1 where rate>0: .orange; default: .gray.opacity(0.3) }
        }
    }
}

// MARK: - Date helpers (inline)

fileprivate extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

// MARK: - Calendar helper

fileprivate extension Calendar {
    func generateDates(inside interval: DateInterval,
                       matching comps: DateComponents) -> [Date] {
        var dates: [Date] = [interval.start]
        enumerateDates(startingAfter: interval.start,
                       matching: comps,
                       matchingPolicy: .nextTime) { date, _, stop in
            guard let d = date, d < interval.end else { stop = true; return }
            dates.append(d)
        }
        return dates
    }
}
