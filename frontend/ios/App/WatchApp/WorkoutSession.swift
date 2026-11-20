import Foundation
import HealthKit
import WatchKit

@MainActor
final class LiveWorkout: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    @Published var running = false
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start(at start: Date = Date()) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workout = HKObjectType.workoutType()
        do {
            try await healthStore.requestAuthorization(toShare: [workout], read: [])
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self; builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            self.session = session; self.builder = builder
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            running = true
        } catch { running = false }
    }

    func finish(at end: Date = Date()) async {
        guard let session, let builder else { return }
        session.end()
        do { try await builder.endCollection(at: end); _ = try await builder.finishWorkout() } catch {}
        self.session = nil; self.builder = nil; running = false
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) { Task { @MainActor in self.running = false } }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}

@MainActor
final class RestClock: ObservableObject {
    @Published var remaining = 0
    private var timer: Timer?
    func start(_ seconds: Int) {
        remaining = seconds; timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.remaining -= 1
                if self.remaining == 10 { WKInterfaceDevice.current().play(.notification) }
                if self.remaining <= 0 { timer.invalidate(); WKInterfaceDevice.current().play(.success) }
            }
        }
    }
    func add(_ seconds: Int) { remaining += seconds }
    func stop() { timer?.invalidate(); remaining = 0 }
}
