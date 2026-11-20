import Foundation
import Capacitor
import WatchConnectivity

private extension Notification.Name {
    static let kraftplanWatchEvent = Notification.Name("KraftplanWatchEvent")
}

/** Durable WatchConnectivity inbox owned by the native shell. Events are written to disk before
 * JavaScript is notified, so a suspended WebView or a terminated iPhone app cannot lose a set. */
final class WatchBridgeStore: NSObject, WCSessionDelegate {
    static let shared = WatchBridgeStore()
    private let queue = DispatchQueue(label: "com.kayloehmann.opengym.watch-bridge")
    private var events: [[String: Any]] = []
    private var latestContext: [String: Any]?
    private var activated = false

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kraftplan-watch-inbox.json")
    }

    override private init() {
        super.init()
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { events = decoded }
    }

    func activate() {
        guard WCSession.isSupported(), !activated else { return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func snapshot() -> [[String: Any]] { queue.sync { events } }

    func remove(_ ids: Set<String>) {
        queue.async {
            self.events.removeAll { ids.contains($0["operationId"] as? String ?? "") }
            self.save()
        }
    }

    func publish(_ context: [String: Any]) throws {
        // Capacitor represents JavaScript null as NSNull. WatchConnectivity only accepts
        // property-list values and rejects the complete application context if a single NSNull
        // is nested in it. Keep this native boundary defensive even though the JS producer now
        // omits optional workout fields.
        let safeContext = propertyListSafe(context)
        queue.sync { latestContext = safeContext }
        activate()
        // JavaScript can publish before WCSession finishes activating. Keep that newest context
        // instead of rejecting it; activationDidComplete sends it as soon as the channel is ready.
        guard WCSession.default.activationState == .activated else { return }
        try deliver(safeContext, through: WCSession.default)
    }

    private func deliver(_ context: [String: Any], through session: WCSession) throws {
        let payload: [String: Any] = ["context": context]
        try session.updateApplicationContext(payload)
        // updateApplicationContext is the durable latest-value channel, but delivery may be
        // deferred. When the Watch is open, send the exact same context interactively so an
        // iPhone-side Finish leaves the workout screen immediately.
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
    }

    private func propertyListSafe(_ dictionary: [String: Any]) -> [String: Any] {
        dictionary.compactMapValues { value in
            if value is NSNull { return nil }
            if let nested = value as? [String: Any] { return propertyListSafe(nested) }
            if let array = value as? [Any] {
                return array.compactMap { item -> Any? in
                    if item is NSNull { return nil }
                    if let nested = item as? [String: Any] { return propertyListSafe(nested) }
                    return item
                }
            }
            return value
        }
    }

    func acknowledge(_ ack: [String: Any]) {
        activate()
        let payload: [String: Any] = ["ack": ack]
        let session = WCSession.default
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: nil) }
        session.transferUserInfo(payload)
    }

    private func receive(_ event: [String: Any]) {
        guard let operationID = event["operationId"] as? String, !operationID.isEmpty else { return }
        queue.async {
            if !self.events.contains(where: { ($0["operationId"] as? String) == operationID }) {
                self.events.append(event)
                self.events.sort { ($0["sequence"] as? Int ?? 0) < ($1["sequence"] as? Int ?? 0) }
                self.save()
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .kraftplanWatchEvent, object: nil, userInfo: ["event": event])
            }
        }
    }

    private func save() {
        guard JSONSerialization.isValidJSONObject(events),
              let data = try? JSONSerialization.data(withJSONObject: events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard error == nil, activationState == .activated, let context = currentContext() else { return }
        try? deliver(context, through: session)
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "context" {
            guard let context = currentContext(), session.isReachable else { return }
            session.sendMessage(["context": context], replyHandler: nil, errorHandler: nil)
            return
        }
        if let event = message["event"] as? [String: Any] { receive(event) }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "context" {
            if let context = currentContext() { replyHandler(["context": context]) }
            else { replyHandler(["status": "empty"]) }
            return
        }
        if let event = message["event"] as? [String: Any] { receive(event) }
        replyHandler(["status": "received"])
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let event = userInfo["event"] as? [String: Any] { receive(event) }
    }

    private func currentContext() -> [String: Any]? {
        if let context = queue.sync(execute: { latestContext }) { return context }
        return WCSession.default.applicationContext["context"] as? [String: Any]
    }
}

@objc(KraftplanWatchPlugin)
public final class KraftplanWatchPlugin: CAPPlugin {
    private var observer: NSObjectProtocol?

    public override func load() {
        WatchBridgeStore.shared.activate()
        observer = NotificationCenter.default.addObserver(forName: .kraftplanWatchEvent, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?["event"] as? [String: Any] else { return }
            self?.notifyListeners("watchEvent", data: ["event": event], retainUntilConsumed: true)
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    @objc func publish(_ call: CAPPluginCall) {
        guard let context = call.getObject("context") else { call.reject("Missing context"); return }
        do { try WatchBridgeStore.shared.publish(context); call.resolve() }
        catch { call.reject(error.localizedDescription, "not_ready", error) }
    }

    @objc func pending(_ call: CAPPluginCall) { call.resolve(["events": WatchBridgeStore.shared.snapshot()]) }

    @objc func clear(_ call: CAPPluginCall) {
        let ids = Set(call.getArray("operationIds", String.self) ?? [])
        WatchBridgeStore.shared.remove(ids)
        call.resolve()
    }

    @objc func ack(_ call: CAPPluginCall) {
        var ack: [String: Any] = [:]
        for key in ["operationId", "sessionId", "status"] { if let value = call.getString(key) { ack[key] = value } }
        WatchBridgeStore.shared.acknowledge(ack)
        call.resolve()
    }
}
