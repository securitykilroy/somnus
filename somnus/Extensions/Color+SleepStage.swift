import SwiftUI

extension Color {
    static let sleepCore  = Color.blue
    static let sleepDeep  = Color.indigo
    static let sleepREM   = Color.orange
    static let sleepAwake = Color.red.opacity(0.7)
    static let sleepInBed = Color.gray.opacity(0.4)
    static let sleepUnspecified = Color.teal.opacity(0.75)
}

extension SleepStageType {
    var color: Color {
        switch self {
        case .core:  return .sleepCore
        case .deep:  return .sleepDeep
        case .rem:   return .sleepREM
        case .awake: return .sleepAwake
        case .inBed: return .sleepInBed
        case .asleepUnspecified: return .sleepUnspecified
        }
    }
}
