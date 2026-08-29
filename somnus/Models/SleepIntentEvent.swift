import Foundation

enum SleepIntentKind: String, CaseIterable, Identifiable, Codable {
    case tryingToSleep
    case awake

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tryingToSleep: return "Trying to Sleep"
        case .awake: return "Awake"
        }
    }

    var systemImage: String {
        switch self {
        case .tryingToSleep: return "bed.double.fill"
        case .awake: return "sun.max.fill"
        }
    }
}

struct SleepIntentEvent: Identifiable, Hashable, Codable {
    let id: UUID
    let timestamp: Date
    let kind: SleepIntentKind
    let note: String?
    let createdAt: Date
    let updatedAt: Date
}
