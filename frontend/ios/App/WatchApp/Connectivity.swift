import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published var context: WatchContext?
    @Published var syncText = "Bereit"
    @Published var refreshing = false
    private var outbox: [WatchEvent] = []
    private var sequence = 0
    private let defaults = UserDefaults(suiteName: kraftplanGroup)!

    override init() {
        super.init()
        if let data = defaults.data(forKey: "context") { context = try? JSONDecoder().decode(WatchContext.self, from: data) }
        if let data = defaults.data(forKey: "outbox") { outbox = (try? JSONDecoder().decode([WatchEvent].self, from: data)) ?? [] }
        sequence = defaults.integer(forKey: "sequence")
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.flush()
            self.refresh()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let value = applicationContext["context"], let decoded = decodeContext(value) else { return }
        Task { @MainActor in self.accept(decoded) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.receive(userInfo) }
    }

    private func accept(_ value: WatchContext) {
        context = value
        defaults.set(try? JSONEncoder().encode(value), forKey: "context")
        refreshing = false
        syncText = "Aktualisiert"
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func receive(_ payload: [String: Any]) {
        if let value = payload["context"], let decoded = decodeContext(value) {
            accept(decoded)
            return
        }
        guard let ack = payload["ack"] as? [String: Any], let id = ack["operationId"] as? String else { return }
        outbox.removeAll { $0.operationId == id }
        saveOutbox()
        syncText = (ack["status"] as? String) == "synced" ? "Synchronisiert" : "Auf iPhone gesichert"
    }

    func send(_ make: (Int) -> WatchEvent) {
        sequence += 1
        defaults.set(sequence, forKey: "sequence")
        let event = make(sequence)
        outbox.append(event)
        saveOutbox()
        transmit(event)
        syncText = WCSession.default.isReachable ? "Wird synchronisiert …" : "Offline gespeichert"
    }

    /// Ask the phone for its current canonical context whenever the Watch UI opens. The
    /// application context remains the durable fallback, while this interactive round-trip
    /// avoids leaving the Watch on an old rest-day/workout snapshot until the next phone edit.
    func refresh() {
        guard WCSession.default.activationState == .activated else {
            syncText = "Verbindung wird vorbereitet …"
            return
        }
        guard WCSession.default.isReachable else {
            refreshing = false
            syncText = "iPhone nicht erreichbar"
            return
        }
        refreshing = true
        syncText = "Aktualisiere …"
        WCSession.default.sendMessage(["request": "context"], replyHandler: { reply in
            Task { @MainActor in
                if let value = reply["context"], let decoded = decodeContext(value) {
                    self.accept(decoded)
                } else {
                    self.refreshing = false
                    self.syncText = "Kraftplan auf dem iPhone öffnen"
                }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                self.refreshing = false
                self.syncText = "iPhone nicht erreichbar"
            }
        })
    }

    func markSet(exercise: Int, set: Int, done: Bool) {
        guard var next = context, var workout = next.workout,
              workout.exercises.indices.contains(exercise),
              workout.exercises[exercise].sets.indices.contains(set) else { return }
        workout.exercises[exercise].sets[set].done = done
        workout.currentExercise = exercise
        next.workout = workout
        accept(next)
    }

    func updateSet(exercise: Int, set: Int, reps: Int, weight: Double) {
        guard var next = context, var workout = next.workout,
              workout.exercises.indices.contains(exercise),
              workout.exercises[exercise].sets.indices.contains(set) else { return }
        workout.exercises[exercise].sets[set].reps = max(0, reps)
        workout.exercises[exercise].sets[set].weight = max(0, weight)
        workout.currentExercise = exercise
        next.workout = workout
        accept(next)
    }

    private func transmit(_ event: WatchEvent) {
        guard let dictionary = JSONEncoder().dictionary(event) else { return }
        let payload: [String: Any] = ["event": dictionary]
        if WCSession.default.isReachable { WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
        WCSession.default.transferUserInfo(payload)
    }

    private func flush() { outbox.forEach(transmit) }
    private func saveOutbox() { defaults.set(try? JSONEncoder().encode(outbox), forKey: "outbox") }
}
