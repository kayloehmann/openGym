import Foundation
import Capacitor
import HealthKit
import UIKit

/**
 * Write-only Apple Health bridge. The shared JavaScript sync planner decides which finished
 * workouts and weigh-ins changed; this plugin turns those plain records into HealthKit samples.
 * Every sample carries a stable sync identifier so edits replace the previous value and deletes
 * remove only data written by openGym.
 */
@objc(AppleHealthPlugin)
public class AppleHealthPlugin: CAPPlugin {
    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()
    private let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
    private static var lastSyncVersion = 0

    private var shareTypes: Set<HKSampleType> { [workoutType, weightType] }

    @objc func status(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.resolve(["status": "unsupported", "granted": false])
            return
        }
        call.resolve(["status": "available", "granted": isGranted])
    }

    @objc public override func requestPermissions(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("Apple Health is not available", "unavailable")
            return
        }
        store.requestAuthorization(toShare: shareTypes, read: []) { [weak self] _, error in
            if let error = error {
                call.reject(error.localizedDescription, "failed", error)
                return
            }
            call.resolve(["granted": self?.isGranted ?? false])
        }
    }

    @objc func write(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("Apple Health is not available", "unavailable")
            return
        }
        guard isGranted else {
            call.reject("Apple Health permission was not granted", "permission")
            return
        }

        let sessions = call.getArray("sessions", JSObject.self) ?? []
        let weights = call.getArray("weights", JSObject.self) ?? []
        let version = Self.nextSyncVersion()

        do {
            var samples: [HKSample] = try sessions.map { try workout(from: $0, version: version) }
            samples.append(contentsOf: try weights.map { try weight(from: $0, version: version) })
            guard !samples.isEmpty else { call.resolve(); return }
            store.save(samples) { [weak self] ok, error in
                if ok { call.resolve(); return }
                self?.reject(call, error: error)
            }
        } catch {
            call.reject(error.localizedDescription, "failed", error)
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("Apple Health is not available", "unavailable")
            return
        }
        guard isGranted else {
            call.reject("Apple Health permission was not granted", "permission")
            return
        }

        let sessionIDs = call.getArray("sessions", String.self) ?? []
        let weightIDs = call.getArray("weights", String.self) ?? []
        delete(workoutType, ids: sessionIDs) { error in
            if let error = error { self.reject(call, error: error); return }
            self.delete(self.weightType, ids: weightIDs) { error in
                if let error = error { self.reject(call, error: error); return }
                call.resolve()
            }
        }
    }

    @objc func openSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let url = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(url) else {
                call.reject("Settings are not available", "failed")
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in
                opened ? call.resolve() : call.reject("Could not open Settings", "failed")
            }
        }
    }

    private var isGranted: Bool {
        shareTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingAuthorized }
    }

    private func workout(from item: JSObject, version: Int) throws -> HKWorkout {
        let id = try string(item, "id")
        let start = Date(timeIntervalSince1970: try number(item, "start") / 1000)
        let end = Date(timeIntervalSince1970: try number(item, "end") / 1000)
        let metadata = baseMetadata(id: id, version: version).merging([
            HKMetadataKeyWorkoutBrandName: "openGym",
            HKMetadataKeyIndoorWorkout: true,
            "ch.duartesantos.opengym.title": item["title"] as? String ?? "",
            "ch.duartesantos.opengym.notes": item["notes"] as? String ?? "",
        ]) { _, new in new }
        return HKWorkout(
            activityType: activityType(item["type"] as? String),
            start: start,
            end: end,
            duration: max(0, end.timeIntervalSince(start)),
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: metadata
        )
    }

    private func weight(from item: JSObject, version: Int) throws -> HKQuantitySample {
        let id = try string(item, "id")
        let time = Date(timeIntervalSince1970: try number(item, "time") / 1000)
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: try number(item, "kg"))
        return HKQuantitySample(
            type: weightType,
            quantity: quantity,
            start: time,
            end: time,
            metadata: baseMetadata(id: id, version: version)
        )
    }

    private func delete(_ type: HKSampleType, ids: [String], completion: @escaping (Error?) -> Void) {
        guard !ids.isEmpty else { completion(nil); return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: ids
        )
        store.deleteObjects(of: type, predicate: predicate) { _, _, error in completion(error) }
    }

    private func baseMetadata(id: String, version: Int) -> [String: Any] {
        [
            HKMetadataKeySyncIdentifier: id,
            HKMetadataKeySyncVersion: version,
            HKMetadataKeyWasUserEntered: true,
        ]
    }

    private func activityType(_ type: String?) -> HKWorkoutActivityType {
        switch type {
        case "strength_training": return .traditionalStrengthTraining
        case "walking": return .walking
        case "running": return .running
        case "biking_stationary": return .cycling
        case "elliptical": return .elliptical
        case "stair_climbing_machine": return .stairClimbing
        default: return .other
        }
    }

    private func string(_ item: JSObject, _ key: String) throws -> String {
        if let value = item[key] as? String, !value.isEmpty { return value }
        throw PluginError.invalid(key)
    }

    private func number(_ item: JSObject, _ key: String) throws -> Double {
        if let value = item[key] as? NSNumber { return value.doubleValue }
        if let value = item[key] as? Double { return value }
        if let value = item[key] as? Int { return Double(value) }
        throw PluginError.invalid(key)
    }

    private func reject(_ call: CAPPluginCall, error: Error?) {
        let message = error?.localizedDescription ?? "Apple Health operation failed"
        call.reject(message, isGranted ? "failed" : "permission", error)
    }

    private static func nextSyncVersion() -> Int {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        lastSyncVersion = max(now, lastSyncVersion + 1)
        return lastSyncVersion
    }

    private enum PluginError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let field): return "Invalid or missing \(field)" }
        }
    }
}
