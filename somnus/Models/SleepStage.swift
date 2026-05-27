import Foundation
import HealthKit

enum SleepStageType: String, CaseIterable, Identifiable {
    case core = "Core"
    case deep = "Deep"
    case rem = "REM"
    case awake = "Awake"
    case inBed = "In Bed"
    case asleepUnspecified = "Unspecified Sleep"

    var id: String { rawValue }

    var isSleep: Bool {
        switch self {
        case .core, .deep, .rem, .asleepUnspecified: return true
        case .awake, .inBed: return false
        }
    }

    var analysisPriority: Int {
        switch self {
        case .awake: return 5
        case .deep: return 4
        case .rem: return 3
        case .core: return 2
        case .asleepUnspecified: return 1
        case .inBed: return 0
        }
    }

    static func from(_ value: Int) -> SleepStageType? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .awake: return .awake
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleepUnspecified
        default: return nil
        }
    }
}

struct SleepStage: Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let type: SleepStageType
    let sourceName: String?
    let healthKitUUID: UUID?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        type: SleepStageType,
        sourceName: String? = nil,
        healthKitUUID: UUID? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.type = type
        self.sourceName = sourceName
        self.healthKitUUID = healthKitUUID
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}
