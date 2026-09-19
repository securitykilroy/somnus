import CoreData
import Foundation

struct WidgetSleepLatencySnapshot: Hashable {
    let nightDate: Date
    let latency: TimeInterval
    let appleLatency: TimeInterval
}

extension TimeInterval {
    var somnusWidgetDuration: String {
        let minutes = Int((self / 60).rounded())
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}

final class WidgetSomnusStore {
    private static let eventEntityName = "SleepIntentEventEntity"
    private static let latencySnapshotEntityName = "SleepLatencySnapshotEntity"
    private static let cloudKitContainerIdentifier = "iCloud.com.washere.somnus"

    /// One stack for the extension process.
    ///
    /// Each timeline request used to build its own
    /// `NSPersistentCloudKitContainer` and call `loadPersistentStores` again —
    /// standing up a CloudKit sync engine from scratch, twice per refresh
    /// (snapshot and timeline), inside a watchOS widget's memory and time
    /// budget. The container is designed to be loaded once and kept.
    static let shared = WidgetSomnusStore()

    private let container: NSPersistentCloudKitContainer

    init(useCloudKit: Bool? = nil) {
        let useCloudKit = useCloudKit ?? Self.defaultUseCloudKit
        container = NSPersistentCloudKitContainer(
            name: "SomnusIntentModel",
            managedObjectModel: Self.makeModel()
        )

        let description = NSPersistentStoreDescription(url: Self.storeURL())
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        if useCloudKit {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
        }
        container.persistentStoreDescriptions = [description]
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func latestLatencySnapshot() async -> WidgetSleepLatencySnapshot? {
        guard await loadStoresIfNeeded() else { return nil }

        let context = container.viewContext
        let entityName = Self.latencySnapshotEntityName

        return await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.fetchLimit = 1
            request.sortDescriptors = [NSSortDescriptor(key: "nightDate", ascending: false)]

            guard let object = try? context.fetch(request).first,
                  let nightDate = object.value(forKey: "nightDate") as? Date else {
                return nil
            }

            return WidgetSleepLatencySnapshot(
                nightDate: nightDate,
                latency: object.value(forKey: "latency") as? TimeInterval ?? 0,
                appleLatency: object.value(forKey: "appleLatency") as? TimeInterval ?? 0
            )
        }
    }

    /// Loads the stores only the first time. `loadPersistentStores` is not
    /// meant to be called repeatedly on the same container — a second call adds
    /// another store to the coordinator — so the coordinator's own state is the
    /// check, matching `WatchSomnusStore` and `SleepIntentStore`.
    private func loadStoresIfNeeded() async -> Bool {
        guard container.persistentStoreCoordinator.persistentStores.isEmpty else { return true }

        return await withCheckedContinuation { continuation in
            container.loadPersistentStores { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let eventEntity = NSEntityDescription()
        eventEntity.name = eventEntityName
        eventEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        eventEntity.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("timestamp", type: .dateAttributeType),
            attribute("kind", type: .stringAttributeType),
            attribute("note", type: .stringAttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("updatedAt", type: .dateAttributeType),
        ]

        let latencySnapshotEntity = NSEntityDescription()
        latencySnapshotEntity.name = latencySnapshotEntityName
        latencySnapshotEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        latencySnapshotEntity.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("nightDate", type: .dateAttributeType),
            attribute("intentTime", type: .dateAttributeType),
            attribute("firstSleepTime", type: .dateAttributeType),
            attribute("latency", type: .doubleAttributeType),
            attribute("appleLatency", type: .doubleAttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("updatedAt", type: .dateAttributeType),
        ]

        model.entities = [eventEntity, latencySnapshotEntity]
        return model
    }

    private static func attribute(_ name: String, type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }

    private static func storeURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("SomnusIntentModel.sqlite")
    }

    private static var defaultUseCloudKit: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}
