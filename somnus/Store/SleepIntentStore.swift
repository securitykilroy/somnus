import CoreData
import Foundation
import Observation

@MainActor
@Observable
final class SleepIntentStore {
    private static let eventEntityName = "SleepIntentEventEntity"
    private static let latencySnapshotEntityName = "SleepLatencySnapshotEntity"
    private static let cloudKitContainerIdentifier = "iCloud.com.washere.somnus"

    private let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext

    private(set) var events: [SleepIntentEvent] = []
    private(set) var latencySnapshots: [SleepLatencySnapshot] = []
    private(set) var error: Error?

    init(inMemory: Bool = false, useCloudKit: Bool = true) throws {
        container = NSPersistentCloudKitContainer(
            name: "SomnusIntentModel",
            managedObjectModel: Self.makeModel()
        )

        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
        } else {
            description.url = Self.storeURL()
        }
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if useCloudKit && !inMemory {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
        }

        container.persistentStoreDescriptions = [description]
        context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        if inMemory {
            try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSInMemoryStoreType,
                configurationName: nil,
                at: nil
            )
            try load()
        }
    }

    convenience init() {
        do {
            let useInMemoryStore = Self.isRunningTests
            try self.init(inMemory: useInMemoryStore, useCloudKit: !useInMemoryStore)
        } catch {
            try! self.init(inMemory: true, useCloudKit: false)
            self.error = error
        }
    }

    func load() throws {
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            return
        }

        events = try fetchEvents()
        latencySnapshots = try fetchLatencySnapshots()
    }

    func loadAsync() async throws {
        if container.persistentStoreCoordinator.persistentStores.isEmpty {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                container.loadPersistentStores { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        try load()
    }

    func add(
        kind: SleepIntentKind,
        timestamp: Date = Date(),
        note: String? = nil
    ) throws {
        let object = NSManagedObject(entity: Self.entityDescription(named: Self.eventEntityName, in: context), insertInto: context)
        let now = Date()
        object.setValue(UUID(), forKey: "id")
        object.setValue(timestamp, forKey: "timestamp")
        object.setValue(kind.rawValue, forKey: "kind")
        object.setValue(note, forKey: "note")
        object.setValue(now, forKey: "createdAt")
        object.setValue(now, forKey: "updatedAt")

        try context.save()
        try load()
    }

    func saveLatencySnapshots(from records: [SleepLatencyRecord], limit: Int = 90) throws {
        let existingRequest = NSFetchRequest<NSManagedObject>(entityName: Self.latencySnapshotEntityName)
        let existingSnapshots = try context.fetch(existingRequest)
        for snapshot in existingSnapshots {
            context.delete(snapshot)
        }

        let now = Date()
        let snapshotRecords = records
            .sorted { $0.nightDate > $1.nightDate }
            .prefix(limit)

        for record in snapshotRecords {
            let object = NSManagedObject(
                entity: Self.entityDescription(named: Self.latencySnapshotEntityName, in: context),
                insertInto: context
            )
            object.setValue(UUID(), forKey: "id")
            object.setValue(record.nightDate, forKey: "nightDate")
            object.setValue(record.intentTime, forKey: "intentTime")
            object.setValue(record.firstSleepTime, forKey: "firstSleepTime")
            object.setValue(record.latency, forKey: "latency")
            object.setValue(record.appleLatency, forKey: "appleLatency")
            object.setValue(now, forKey: "createdAt")
            object.setValue(now, forKey: "updatedAt")
        }

        try context.save()
        try load()
    }

    private func fetchEvents() throws -> [SleepIntentEvent] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.eventEntityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: false)
        ]

        let objects = try context.fetch(request)
        return objects.compactMap(Self.event(from:))
    }

    private func fetchLatencySnapshots() throws -> [SleepLatencySnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.latencySnapshotEntityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "nightDate", ascending: false)
        ]

        let objects = try context.fetch(request)
        return objects.compactMap(Self.latencySnapshot(from:))
    }

    private static func event(from object: NSManagedObject) -> SleepIntentEvent? {
        guard let id = object.value(forKey: "id") as? UUID,
              let timestamp = object.value(forKey: "timestamp") as? Date,
              let kindValue = object.value(forKey: "kind") as? String,
              let kind = SleepIntentKind(rawValue: kindValue),
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let updatedAt = object.value(forKey: "updatedAt") as? Date else {
            return nil
        }

        return SleepIntentEvent(
            id: id,
            timestamp: timestamp,
            kind: kind,
            note: object.value(forKey: "note") as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func latencySnapshot(from object: NSManagedObject) -> SleepLatencySnapshot? {
        guard let id = object.value(forKey: "id") as? UUID,
              let nightDate = object.value(forKey: "nightDate") as? Date,
              let intentTime = object.value(forKey: "intentTime") as? Date,
              let firstSleepTime = object.value(forKey: "firstSleepTime") as? Date,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let updatedAt = object.value(forKey: "updatedAt") as? Date else {
            return nil
        }

        return SleepLatencySnapshot(
            id: id,
            nightDate: nightDate,
            intentTime: intentTime,
            firstSleepTime: firstSleepTime,
            latency: object.value(forKey: "latency") as? TimeInterval ?? 0,
            appleLatency: object.value(forKey: "appleLatency") as? TimeInterval ?? 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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

    private static func attribute(
        _ name: String,
        type: NSAttributeType
    ) -> NSAttributeDescription {
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

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
