import SwiftUI
import Combine

struct NativeWorkoutContext: Codable {
    let version: Int
    let generatedAt: Double
    let state: String
    let unit: String
    let restSeconds: Int
    let workout: NativeWorkoutPayload?

    static func decode(_ object: [String: Any]) -> NativeWorkoutContext? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct NativeWorkoutPayload: Codable {
    let id: String?
    let date: String
    let start: Double?
    let name: String
    var currentExercise: Int
    var exercises: [NativeWorkoutExercise]
}

struct NativeWorkoutExercise: Codable, Identifiable {
    let id: String
    let index: Int
    let name: String
    var sets: [NativeWorkoutSet]
}

struct NativeWorkoutSet: Codable {
    let reps: Double
    let weight: Double
    let duration: Double
    var done: Bool
}

@MainActor
final class NativeWorkoutViewModel: ObservableObject {
    @Published private(set) var context: NativeWorkoutContext
    @Published var exerciseIndex: Int
    @Published var restEndsAt: Date?
    @Published var showFinishConfirmation = false
    private let emit: ([String: Any]) -> Void

    init(context: NativeWorkoutContext, emit: @escaping ([String: Any]) -> Void) {
        self.context = context
        self.exerciseIndex = context.workout?.currentExercise ?? 0
        self.emit = emit
    }

    var workout: NativeWorkoutPayload? { context.workout }
    var exercise: NativeWorkoutExercise? {
        guard let workout, workout.exercises.indices.contains(exerciseIndex) else { return nil }
        return workout.exercises[exerciseIndex]
    }
    var completedSets: Int { workout?.exercises.flatMap(\.sets).filter(\.done).count ?? 0 }
    var totalSets: Int { workout?.exercises.flatMap(\.sets).count ?? 0 }

    func apply(_ next: NativeWorkoutContext) {
        context = next
        guard let workout = next.workout, !workout.exercises.isEmpty else { exerciseIndex = 0; return }
        exerciseIndex = min(max(workout.currentExercise, 0), workout.exercises.count - 1)
    }

    func move(_ delta: Int) {
        guard let workout else { return }
        exerciseIndex = min(max(exerciseIndex + delta, 0), max(workout.exercises.count - 1, 0))
    }

    func toggleSet(_ setIndex: Int) {
        guard var workout = context.workout,
              let sessionID = workout.id,
              workout.exercises.indices.contains(exerciseIndex),
              workout.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        let done = !workout.exercises[exerciseIndex].sets[setIndex].done
        workout.exercises[exerciseIndex].sets[setIndex].done = done
        workout.currentExercise = exerciseIndex
        context = NativeWorkoutContext(version: context.version, generatedAt: Date().timeIntervalSince1970 * 1000,
            state: context.state, unit: context.unit, restSeconds: context.restSeconds, workout: workout)
        if done { restEndsAt = Date().addingTimeInterval(TimeInterval(context.restSeconds)) }
        UIImpactFeedbackGenerator(style: done ? .medium : .light).impactOccurred()
        emit([
            "type": "set", "operationId": UUID().uuidString, "sessionId": sessionID,
            "exerciseIndex": exerciseIndex, "setIndex": setIndex, "done": done,
            "at": Date().timeIntervalSince1970 * 1000,
        ])
    }

    func finish() {
        guard let sessionID = workout?.id else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        emit([
            "type": "finish", "operationId": UUID().uuidString, "sessionId": sessionID,
            "end": Date().timeIntervalSince1970 * 1000,
        ])
    }
}

struct NativeWorkoutView: View {
    @ObservedObject var model: NativeWorkoutViewModel
    let close: () -> Void
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let exercise = model.exercise { exerciseView(exercise) }
                else { Spacer(); Text("Kein aktives Training").foregroundColor(.secondary); Spacer() }
                footer
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) { now = $0 }
        .confirmationDialog("Training beenden?", isPresented: $model.showFinishConfirmation, titleVisibility: .visible) {
            Button("Beenden und speichern") { model.finish() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            let open = max(model.totalSets - model.completedSets, 0)
            Text(open > 0 ? "Noch \(open) Sätze sind nicht abgehakt." : "Alle Sätze sind erledigt.")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: close) { Image(systemName: "chevron.down").font(.title3.weight(.semibold)) }
                Spacer()
                VStack(spacing: 2) {
                    Text(model.workout?.name ?? "Kraftplan").font(.headline).lineLimit(1)
                    Text("\(model.completedSets) von \(model.totalSets) Sätzen").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { model.showFinishConfirmation = true } label: { Text("Fertig").fontWeight(.semibold) }
            }
            ProgressView(value: Double(model.completedSets), total: Double(max(model.totalSets, 1))).tint(.green)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func exerciseView(_ exercise: NativeWorkoutExercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ÜBUNG \(model.exerciseIndex + 1) VON \(model.workout?.exercises.count ?? 0)")
                            .font(.caption2.weight(.bold)).foregroundColor(.secondary)
                        Text(exercise.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                restCard
                VStack(spacing: 10) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                        Button { model.toggleSet(index) } label: { setRow(index: index, set: set) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder private var restCard: some View {
        if let end = model.restEndsAt, end > now {
            HStack {
                Image(systemName: "timer").foregroundColor(.orange)
                Text("Pause").fontWeight(.semibold)
                Spacer()
                Text(clock(max(Int(end.timeIntervalSince(now).rounded(.up)), 0))).font(.title2.monospacedDigit().bold())
                Button("Überspringen") { model.restEndsAt = nil }.font(.caption)
            }
            .padding().background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func setRow(index: Int, set: NativeWorkoutSet) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(set.done ? Color.green : Color(.tertiarySystemFill)).frame(width: 42, height: 42)
                if set.done { Image(systemName: "checkmark").font(.headline.bold()).foregroundColor(.black) }
                else { Text("\(index + 1)").font(.headline).foregroundColor(.primary) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(setSummary(set)).font(.title3.weight(.semibold)).foregroundColor(.primary)
                Text(set.done ? "Erledigt" : "Zum Abhaken tippen").font(.caption).foregroundColor(set.done ? .green : .secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(set.done ? Color.green.opacity(0.65) : Color.clear, lineWidth: 1.5))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { model.move(-1) } label: { Label("Zurück", systemImage: "chevron.left") }
                .disabled(model.exerciseIndex <= 0)
            Spacer()
            Button { model.move(1) } label: { Label("Weiter", systemImage: "chevron.right") }
                .disabled(model.exerciseIndex + 1 >= (model.workout?.exercises.count ?? 0))
        }
        .font(.headline).padding().background(Color(.secondarySystemGroupedBackground))
    }

    private func setSummary(_ set: NativeWorkoutSet) -> String {
        if set.duration > 0 { return clock(Int(set.duration)) }
        let reps = number(set.reps)
        if set.weight > 0 { return "\(number(set.weight)) \(model.context.unit) × \(reps)" }
        return "\(reps) Wiederholungen"
    }
    private func number(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
    private func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
