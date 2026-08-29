import CoreData
import Foundation
import Observation

struct WatchSleepIntentEvent: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let kind: String
}

struct WatchSleepLatencySnapshot: Identifiable, Hashable {
    let id: UUID
    let nightDate: Date
    let latency: TimeInterval
    let appleLatency: TimeInterval
}

extension TimeInterval {
    var somnusShortDuration: String {
        let minutes = Int((self / 60).rounded())
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}

@MainActor
@Observable
final class WatchSomnusStore {
    private static let eventEntityName = "SleepIntentEventEntity"
    private static let latencySnapshotEntityName = "SleepLatencySnapshotEntity"
    private static let cloudKitContainerIdentifier = "iCloud.com.washere.somnus"

    private let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext
    private var hasLoadedPersistentStore = false

    private(set) var events: [WatchSleepIntentEvent] = []
    private(set) var latencySnapshots: [WatchSleepLatencySnapshot] = []
    private(set) var isLoading = false
    private(set) var error: Error?

    var latestIntent: WatchSleepIntentEvent? {
        events.first
    }

    var latestLatencySnapshot: WatchSleepLatencySnapshot? {
        latencySnapshots.first
    }

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
        context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func load() {
        if hasLoadedPersistentStore {
            do {
                try refresh()
            } catch {
                self.error = error
            }
            return
        }

        isLoading = true
        container.loadPersistentStores { _, error in
            Task { @MainActor in
                defer { self.isLoading = false }
                if let error {
                    self.error = error
                    return
                }

                do {
                    self.hasLoadedPersistentStore = true
                    try self.refresh()
                } catch {
                    self.error = error
                }
            }
        }
    }

    func addTryingToSleep() throws {
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            throw NSError(
                domain: "WatchSomnusStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Sleep intent store is still loading."]
            )
        }

        let object = NSManagedObject(
            entity: Self.entityDescription(named: Self.eventEntityName, in: context),
            insertInto: context
        )
        let now = Date()
        object.setValue(UUID(), forKey: "id")
        object.setValue(now, forKey: "timestamp")
        object.setValue("tryingToSleep", forKey: "kind")
        object.setValue(nil, forKey: "note")
        object.setValue(now, forKey: "createdAt")
        object.setValue(now, forKey: "updatedAt")

        try context.save()
        try refresh()
    }

    func refresh() throws {
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            return
        }

        events = try fetchEvents()
        latencySnapshots = try fetchLatencySnapshots()
    }

    private func fetchEvents() throws -> [WatchSleepIntentEvent] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.eventEntityName)
        request.predicate = NSPredicate(format: "kind == %@", "tryingToSleep")
        request.fetchLimit = 5
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        return try context.fetch(request).compactMap { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let timestamp = object.value(forKey: "timestamp") as? Date,
                  let kind = object.value(forKey: "kind") as? String else {
                return nil
            }
            return WatchSleepIntentEvent(id: id, timestamp: timestamp, kind: kind)
        }
    }

    private func fetchLatencySnapshots() throws -> [WatchSleepLatencySnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.latencySnapshotEntityName)
        request.fetchLimit = 5
        request.sortDescriptors = [NSSortDescriptor(key: "nightDate", ascending: false)]

        return try context.fetch(request).compactMap { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let nightDate = object.value(forKey: "nightDate") as? Date else {
                return nil
            }
            return WatchSleepLatencySnapshot(
                id: id,
                nightDate: nightDate,
                latency: object.value(forKey: "latency") as? TimeInterval ?? 0,
                appleLatency: object.value(forKey: "appleLatency") as? TimeInterval ?? 0
            )
        }
    }

    private static func entityDescription(named name: String, in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: name, in: context)!
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
