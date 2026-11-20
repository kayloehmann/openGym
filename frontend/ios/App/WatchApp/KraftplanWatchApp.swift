import SwiftUI
import WatchKit

@main
struct KraftplanWatchApp: App {
    @StateObject private var link = PhoneLink()
    @StateObject private var live = LiveWorkout()
    var body: some Scene { WindowGroup { RootView().environmentObject(link).environmentObject(live) } }
}

struct RootView: View {
    @EnvironmentObject var link: PhoneLink
    @EnvironmentObject var live: LiveWorkout
    @State private var sessionID: String?
    @State private var exercise = 0
    @State private var confirmFinish = false

    var body: some View {
        NavigationStack {
            if let workout = link.context?.workout, sessionID != nil || link.context?.state == "active" {
                ActiveView(workout: workout, sessionID: sessionID ?? workout.id ?? UUID().uuidString, exercise: $exercise, confirmFinish: $confirmFinish)
            } else { home }
        }
        .confirmationDialog("Workout beenden?", isPresented: $confirmFinish) {
            Button("Beenden") { finish() }
            Button("Abbrechen", role: .cancel) {}
        }
        .onAppear {
            reconcilePhoneState()
            link.refresh()
        }
        .onChange(of: link.context?.generatedAt) { _ in
            reconcilePhoneState()
        }
    }

    private var home: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional").font(.title).foregroundStyle(.orange)
                if let workout = link.context?.workout {
                    Text(workout.name).font(.headline).watchText()
                    Text("\(workout.exercises.count) Übungen").font(.caption).foregroundStyle(.secondary).watchText()
                    Button { start(workout) } label: {
                        Text(link.context?.state == "active" ? "Fortsetzen" : "Workout starten").watchButtonText()
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                } else {
                    Text(link.context?.state == "completed" ? "Training heute abgeschlossen" : "Heute ist kein Workout geplant")
                        .watchText()
                    if link.context?.state != "completed" {
                        Button { link.refresh() } label: {
                            if link.refreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label {
                                    Text("Aktualisieren").watchButtonText()
                                } icon: {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        Text(link.syncText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .watchText()
                    }
                }
                if let week = link.context?.week, week.target > 0 {
                    Text("Diese Woche \(week.completed)/\(week.target)").font(.caption2).watchText()
                }
                NavigationLink {
                    WorkoutHistoryListView()
                } label: {
                    Label {
                        Text("Letzte Trainings").watchButtonText()
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .watchActionButton()
            }
            .padding(.horizontal, 6)
        }
    }

    private func start(_ workout: WatchWorkout) {
        let id = workout.id ?? UUID().uuidString
        sessionID = id; exercise = workout.currentExercise
        let now = Date().timeIntervalSince1970 * 1000
        link.send { seq in WatchEvent(operationId: UUID().uuidString, sessionId: id, sequence: seq, type: "start", start: now, end: nil, date: workout.date, name: workout.name, routineIds: workout.routineIds, exerciseIndex: nil, setIndex: nil, done: nil, at: nil, reps: nil, weight: nil) }
        Task { await live.start() }
    }

    private func finish() {
        guard let id = sessionID else { return }
        let now = Date().timeIntervalSince1970 * 1000
        link.send { seq in WatchEvent(operationId: UUID().uuidString, sessionId: id, sequence: seq, type: "finish", start: nil, end: now, date: nil, name: nil, routineIds: nil, exerciseIndex: nil, setIndex: nil, done: nil, at: nil, reps: nil, weight: nil) }
        Task { await live.finish(); sessionID = nil }
    }

    private func reconcilePhoneState() {
        guard let context = link.context else { return }
        if context.state == "active", let id = context.workout?.id {
            sessionID = id
            exercise = context.workout?.currentExercise ?? 0
            return
        }
        // The phone is canonical. Once it reports this exact session in history, leave the
        // Watch workout even when Finish was tapped on the iPhone rather than on the Watch.
        if let local = sessionID, context.lastCompletedSessionId == local {
            sessionID = nil
            exercise = 0
            Task { await live.finish() }
        }
    }
}

struct ActiveView: View {
    @EnvironmentObject var link: PhoneLink
    let workout: WatchWorkout
    let sessionID: String
    @Binding var exercise: Int
    @Binding var confirmFinish: Bool
    @StateObject private var rest = RestClock()
    @State private var selectedValue: SetValue = .weight
    @State private var crownValue = 0.0
    @State private var draftWeight = 0.0
    @State private var draftReps = 0
    @State private var lastCompletedExercise: Int?
    @State private var lastCompletedSet: Int?

    private enum SetValue { case weight, reps }

    var current: WatchExercise? { workout.exercises.indices.contains(exercise) ? workout.exercises[exercise] : nil }
    var focusedSetIndex: Int? { current?.sets.firstIndex(where: { !$0.done }) }
    var focusedSet: WatchSet? {
        guard let current, let focusedSetIndex else { return nil }
        return current.sets[focusedSetIndex]
    }
    var completedSets: Int { workout.exercises.flatMap(\.sets).filter(\.done).count }
    var totalSets: Int { workout.exercises.flatMap(\.sets).count }

    var body: some View {
        if rest.remaining > 0 { restView }
        else if let current, let setIndex = focusedSetIndex, let set = focusedSet {
            ScrollView {
                VStack(spacing: 8) {
                    workoutHeader
                    Text(current.name).font(.headline).watchText()
                    Text("Satz \(setIndex + 1) von \(current.sets.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .watchText()

                    HStack(spacing: 6) {
                        valueButton(
                            title: "Gewicht",
                            value: "\(draftWeight.formatted()) \(link.context?.unit ?? "kg")",
                            field: .weight
                        )
                        valueButton(
                            title: "Wdh.",
                            value: "\(draftReps)",
                            field: .reps
                        )
                    }

                    Button { completeSet(setIndex, original: set) } label: {
                        Label("Satz erledigt", systemImage: "checkmark")
                            .watchButtonText()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .watchActionButton()

                    Text(link.syncText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .watchText()
                }
                .focusable(true)
                .digitalCrownRotation(
                    $crownValue,
                    from: 0,
                    through: 999,
                    by: selectedValue == .weight ? 0.5 : 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            }
            .onAppear { loadDraft(from: set) }
            .onChange(of: focusSignature) { _ in loadDraftFromFocus() }
            .onChange(of: crownValue) { value in applyCrown(value) }
        } else if current != nil {
            completedExerciseView
        }
    }

    private var workoutHeader: some View {
        HStack {
            NavigationLink {
                ExercisePickerView(workout: workout, exercise: $exercise)
            } label: {
                HStack(spacing: 5) {
                    ExerciseProgressRings(workout: workout, currentExercise: exercise)
                    Text("\(completedSets)/\(totalSets)").font(.caption2).monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            Spacer()
            NavigationLink {
                WorkoutHistoryListView()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Letzte Trainings")
            Button { confirmFinish = true } label: { Image(systemName: "flag.checkered") }
                .buttonStyle(.plain)
        }
    }

    private func valueButton(title: String, value: String, field: SetValue) -> some View {
        Button {
            selectedValue = field
            crownValue = field == .weight ? draftWeight : Double(draftReps)
            WKInterfaceDevice.current().play(.click)
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary).watchText()
                Text(value).font(.headline).monospacedDigit().watchText()
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(selectedValue == field ? .orange : .gray)
        .accessibilityAddTraits(selectedValue == field ? .isSelected : [])
    }

    private var restView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Pause").font(.caption).foregroundStyle(.secondary).watchText()
                Text(rest.remaining.formatted(.number.precision(.integerLength(2))))
                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().watchText()
                if let current, let setIndex = focusedSetIndex {
                    Text("Danach: \(current.name), Satz \(setIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .watchText()
                } else {
                    Text("Alle Sätze geschafft")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .watchText()
                }
                Button { proceedAfterRest() } label: {
                    Text(focusedSetIndex == nil ? "Training abschließen" : "Nächsten Satz starten")
                        .watchButtonText()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .watchActionButton()
                Button { undoLastSet() } label: {
                    Text("Letzten Satz zurücknehmen").watchButtonText()
                }
                .buttonStyle(.bordered)
                .watchActionButton()
            }
        }
    }

    private var completedExerciseView: some View {
        ScrollView {
            VStack(spacing: 8) {
                workoutHeader
                Image(systemName: allSetsCompleted ? "trophy.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(allSetsCompleted ? .orange : .green)
                Text(allSetsCompleted ? "Training geschafft" : "Übung geschafft")
                    .font(.headline)
                    .watchText()
                if allSetsCompleted {
                    Button { confirmFinish = true } label: {
                        Text("Training abschließen").watchButtonText()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .watchActionButton()
                } else if let next = nextUnfinishedExercise(after: exercise) {
                    Button { exercise = next } label: {
                        Text("Nächste offene Übung").watchButtonText()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .watchActionButton()
                }
            }
        }
    }

    private var allSetsCompleted: Bool {
        workout.exercises.flatMap(\.sets).allSatisfy(\.done)
    }

    private var focusSignature: String {
        guard let set = focusedSet, let setIndex = focusedSetIndex else { return "\(exercise)-done" }
        return "\(exercise)-\(setIndex)-\(set.reps)-\(set.weight)-\(set.done)"
    }

    private func loadDraftFromFocus() {
        guard let set = focusedSet else { return }
        loadDraft(from: set)
    }

    private func loadDraft(from set: WatchSet) {
        draftWeight = set.weight
        draftReps = set.reps
        crownValue = selectedValue == .weight ? set.weight : Double(set.reps)
    }

    private func applyCrown(_ value: Double) {
        if selectedValue == .weight { draftWeight = value }
        else { draftReps = Int(value.rounded()) }
    }

    private func completeSet(_ setIndex: Int, original: WatchSet) {
        if draftReps != original.reps || draftWeight != original.weight {
            update(setIndex, reps: draftReps, weight: draftWeight, haptic: false)
        }
        setDone(exerciseIndex: exercise, setIndex: setIndex, done: true)
        lastCompletedExercise = exercise
        lastCompletedSet = setIndex
        if current?.sets.indices.last == setIndex, let next = nextUnfinishedExercise(after: exercise) {
            exercise = next
        }
        rest.start(link.context?.restSeconds ?? 90)
    }

    private func undoLastSet() {
        guard let exerciseIndex = lastCompletedExercise, let setIndex = lastCompletedSet else { return }
        exercise = exerciseIndex
        setDone(exerciseIndex: exerciseIndex, setIndex: setIndex, done: false)
        lastCompletedExercise = nil
        lastCompletedSet = nil
        rest.stop()
    }

    private func proceedAfterRest() {
        rest.stop()
        if focusedSetIndex == nil && allSetsCompleted {
            confirmFinish = true
        }
    }

    private func setDone(exerciseIndex: Int, setIndex: Int, done: Bool) {
        let now = Date().timeIntervalSince1970 * 1000
        link.markSet(exercise: exerciseIndex, set: setIndex, done: done)
        link.send { seq in WatchEvent(operationId: UUID().uuidString, sessionId: sessionID, sequence: seq, type: "set", start: nil, end: nil, date: nil, name: nil, routineIds: nil, exerciseIndex: exerciseIndex, setIndex: setIndex, done: done, at: now, reps: nil, weight: nil) }
        WKInterfaceDevice.current().play(done ? .click : .directionDown)
    }

    private func update(_ setIndex: Int, reps: Int, weight: Double, haptic: Bool = true) {
        link.updateSet(exercise: exercise, set: setIndex, reps: reps, weight: weight)
        link.send { seq in WatchEvent(operationId: UUID().uuidString, sessionId: sessionID, sequence: seq, type: "set", start: nil, end: nil, date: nil, name: nil, routineIds: nil, exerciseIndex: exercise, setIndex: setIndex, done: nil, at: nil, reps: reps, weight: weight) }
        if haptic { WKInterfaceDevice.current().play(.click) }
    }

    private func nextUnfinishedExercise(after index: Int) -> Int? {
        guard !workout.exercises.isEmpty else { return nil }
        let indices = Array((index + 1)..<workout.exercises.count) + Array(0..<index)
        return indices.first { workout.exercises[$0].sets.contains(where: { !$0.done }) }
    }
}

struct WorkoutHistoryListView: View {
    @EnvironmentObject private var link: PhoneLink
    private var workouts: [WatchHistoryWorkout] { link.context?.recentWorkouts ?? [] }
    private var unit: String { link.context?.unit ?? "kg" }

    var body: some View {
        Group {
            if workouts.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Noch keine Trainings empfangen")
                            .watchText()
                        Button { link.refresh() } label: {
                            if link.refreshing { ProgressView().controlSize(.small) }
                            else { Text("Jetzt aktualisieren").watchButtonText() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .watchActionButton()
                        Text(link.syncText).font(.caption2).foregroundStyle(.secondary).watchText()
                    }
                }
            } else {
                List(workouts) { workout in
                    NavigationLink {
                        WorkoutHistoryDetailView(workout: workout, unit: unit)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.name).font(.headline).watchText(alignment: .leading)
                            Text(historySummary(workout))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .watchText(alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("Letzte Trainings")
    }

    private func historySummary(_ workout: WatchHistoryWorkout) -> String {
        [watchHistoryDate(workout.date), watchHistoryDuration(workout), "\(workout.exercises.count) Übungen"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct WorkoutHistoryDetailView: View {
    let workout: WatchHistoryWorkout
    let unit: String

    var body: some View {
        List {
            Section {
                Text([watchHistoryDate(workout.date), watchHistoryDuration(workout)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .watchText(alignment: .leading)
            }
            ForEach(workout.exercises) { exercise in
                Section(exercise.name) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(set.done ? .green : .secondary)
                            Text(historySetLabel(set, number: index + 1, unit: unit))
                                .font(.caption)
                                .watchText(alignment: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
    }
}

private func watchHistoryDate(_ iso: String) -> String? {
    let parts = iso.split(separator: "-")
    guard parts.count == 3 else { return iso }
    return "\(parts[2]).\(parts[1]).\(parts[0])"
}

private func watchHistoryDuration(_ workout: WatchHistoryWorkout) -> String? {
    guard let start = workout.start, let end = workout.end, end > start else { return nil }
    return "\(max(1, Int(((end - start) / 60_000).rounded()))) Min."
}

private func historySetLabel(_ set: WatchSet, number: Int, unit: String) -> String {
    if set.duration > 0 { return "Satz \(number) · \(set.duration) Sek." }
    if set.weight > 0 { return "Satz \(number) · \(set.reps) × \(set.weight.formatted()) \(unit)" }
    return "Satz \(number) · \(set.reps) Wdh."
}

struct ExerciseProgressRings: View {
    let workout: WatchWorkout
    let currentExercise: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                let total = max(exercise.sets.count, 1)
                let done = exercise.sets.filter(\.done).count
                ZStack {
                    Circle().stroke(.secondary.opacity(0.28), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: Double(done) / Double(total))
                        .stroke(done == total ? .green : .orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if index == currentExercise { Circle().fill(.orange).frame(width: 4, height: 4) }
                }
                .frame(width: 14, height: 14)
            }
        }
    }
}

struct ExercisePickerView: View {
    let workout: WatchWorkout
    @Binding var exercise: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(Array(workout.exercises.enumerated()), id: \.element.id) { index, item in
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    ExerciseRing(exercise: item, current: index == exercise)
                    Text(item.name).font(.caption).watchText(alignment: .leading)
                }
                Button {
                    exercise = index
                    dismiss()
                } label: {
                    Text(index == exercise ? "Aktuell" : "Aktuell setzen").watchButtonText()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(index == exercise)
            }
        }
        .navigationTitle("Übungen")
    }
}

struct ExerciseRing: View {
    let exercise: WatchExercise
    let current: Bool

    var body: some View {
        let total = max(exercise.sets.count, 1)
        let done = exercise.sets.filter(\.done).count
        ZStack {
            Circle().stroke(.secondary.opacity(0.28), lineWidth: 3)
            Circle()
                .trim(from: 0, to: Double(done) / Double(total))
                .stroke(done == total ? .green : .orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if current { Circle().fill(.orange).frame(width: 6, height: 6) }
        }
        .frame(width: 22, height: 22)
    }
}

struct SetEditorView: View {
    let unit: String
    let onSave: (Int, Double) -> Void
    @State private var reps: Int
    @State private var weight: Double
    @Environment(\.dismiss) private var dismiss

    init(set: WatchSet, unit: String, onSave: @escaping (Int, Double) -> Void) {
        self.unit = unit
        self.onSave = onSave
        _reps = State(initialValue: set.reps)
        _weight = State(initialValue: set.weight)
    }

    var body: some View {
        Form {
            Section("Gewicht") {
                Stepper(value: $weight, in: 0...999, step: 0.5) {
                    Text("\(weight.formatted()) \(unit)").monospacedDigit().watchText(alignment: .leading)
                }
            }
            Section("Wiederholungen") {
                Stepper(value: $reps, in: 0...999) {
                    Text("\(reps) Wdh.").monospacedDigit().watchText(alignment: .leading)
                }
            }
            Button {
                onSave(reps, weight)
                dismiss()
            } label: {
                Text("Übernehmen").watchButtonText()
            }
            .tint(.orange)
        }
        .navigationTitle("Satz ändern")
    }
}

private extension View {
    func watchText(alignment: TextAlignment = .center) -> some View {
        multilineTextAlignment(alignment)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    func watchButtonText() -> some View {
        multilineTextAlignment(.center)
            .lineLimit(nil)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: false, vertical: true)
    }

    func watchActionButton() -> some View {
        frame(maxWidth: .infinity, minHeight: 44)
    }
}
