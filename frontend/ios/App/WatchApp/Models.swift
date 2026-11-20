import Foundation

let kraftplanGroup = "group.com.kayloehmann.opengym.kraftplanwatch"

struct WatchSet: Codable, Identifiable {
    var id: Int { index }
    var index: Int = 0
    var reps: Int
    var weight: Double
    let duration: Int
    var done: Bool

    enum CodingKeys: String, CodingKey { case reps, weight, duration, done }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 0
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
    init(index: Int, reps: Int, weight: Double, duration: Int, done: Bool) {
        self.index = index; self.reps = reps; self.weight = weight; self.duration = duration; self.done = done
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reps, forKey: .reps); try c.encode(weight, forKey: .weight)
        try c.encode(duration, forKey: .duration); try c.encode(done, forKey: .done)
    }
}

struct WatchExercise: Codable, Identifiable {
    let id: String
    let index: Int
    let name: String
    var sets: [WatchSet]
}

struct WatchWorkout: Codable {
    let id: String?
    let date: String
    let start: Double?
    let name: String
    let routineIds: [String]
    var currentExercise: Int
    var exercises: [WatchExercise]
}

struct WatchHistoryWorkout: Codable, Identifiable {
    let id: String
    let date: String
    let start: Double?
    let end: Double?
    let name: String
    let exercises: [WatchExercise]
}

struct WeekProgress: Codable { let completed: Int; let target: Int }

struct WatchContext: Codable {
    let version: Int
    let generatedAt: Double
    let state: String
    let lastCompletedSessionId: String?
    let unit: String
    let restSeconds: Int
    let week: WeekProgress
    let recentWorkouts: [WatchHistoryWorkout]?
    var workout: WatchWorkout?
}

struct WatchEvent: Codable {
    let operationId: String
    let sessionId: String
    let sequence: Int
    let type: String
    let start: Double?
    let end: Double?
    let date: String?
    let name: String?
    let routineIds: [String]?
    let exerciseIndex: Int?
    let setIndex: Int?
    let done: Bool?
    let at: Double?
    let reps: Int?
    let weight: Double?
}

extension JSONEncoder {
    func dictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

func decodeContext(_ object: Any) -> WatchContext? {
    guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return try? JSONDecoder().decode(WatchContext.self, from: data)
}
