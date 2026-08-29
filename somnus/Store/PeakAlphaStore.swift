import CoreData
import Foundation
import Observation

/// Core Data + CloudKit backed store for manually logged Peak Alpha readings,
/// mirroring `SleepIntentStore` so this data syncs across devices via iCloud
/// just like sleep intents do.
@MainActor
@Observable
final class PeakAlphaStore {
    struct StoreUnavailableError: LocalizedError {
        var errorDescription: String? {
            "Peak Alpha storage is still starting. Please try again in a moment."
        }
    }

    private static let entryEntityName = "PeakAlphaEntryEntity"
    private static let cloudKitContainerIdentifier = "iCloud.com.washere.somnus"

    private let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext
    private let legacyJSONFileURLs: [URL]
    private let backupJSONFileURL: URL

    private(set) var entries: [PeakAlphaEntry] = []
    private(set) var error: Error?
    var isReady: Bool {
        !container.persistentStoreCoordinator.persistentStores.isEmpty
    }

    init(
        inMemory: Bool = false,
        useCloudKit: Bool = true,
        storeURL: URL? = nil,
        legacyJSONFileURLs: [URL]? = nil,
        backupJSONFileURL: URL? = nil
    ) throws {
        container = NSPersistentCloudKitContainer(
            name: "SomnusPeakAlphaModel",
            managedObjectModel: Self.makeModel()
        )
        self.backupJSONFileURL = backupJSONFileURL ?? Self.defaultBackupJSONFileURL()
        self.legacyJSONFileURLs = legacyJSONFileURLs ?? Self.defaultLegacyJSONFileURLs(
            backupJSONFileURL: self.backupJSONFileURL
        )

        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
        } else {
            description.url = storeURL ?? Self.storeURL()
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
        } else {
            try migrateFromLegacyJSONStoreIfNeeded()
        }
    }

    convenience init() {
        do {
            let useInMemoryStore = Self.isRunningTests
            try self.init(inMemory: useInMemoryStore, useCloudKit: !useInMemoryStore)
        } catch {
            let originalError = error
            do {
                try self.init(inMemory: false, useCloudKit: false)
            } catch {
                try! self.init(inMemory: true, useCloudKit: false)
            }
            self.error = originalError
        }
    }

    func load() throws {
        guard !container.persistentStoreCoordinator.persistentStores.isEmpty else {
            return
        }

        entries = try fetchEntries()
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
            try migrateFromLegacyJSONStoreIfNeeded()
        }

        try load()
    }

    /// Adds a reading, replacing any existing entry for the same calendar day
    /// so re-logging a correction doesn't create duplicates.
    @discardableResult
    func add(date: Date, value: Double, note: String? = nil) throws -> PeakAlphaEntry {
        try requireLoadedStore()

        let day = Calendar.current.startOfDay(for: date)
        try deleteEntries(forDay: day)

        let now = Date()
        let object = NSManagedObject(
            entity: Self.entityDescription(named: Self.entryEntityName, in: context),
            insertInto: context
        )
        let id = UUID()
        object.setValue(id, forKey: "id")
        object.setValue(day, forKey: "date")
        object.setValue(value, forKey: "value")
        object.setValue(note, forKey: "note")
        object.setValue(now, forKey: "createdAt")
        object.setValue(now, forKey: "updatedAt")

        try context.save()
        try load()
        try? writeBackupJSONStore()

        return PeakAlphaEntry(id: id, date: day, value: value, note: note, createdAt: now, updatedAt: now)
    }

    func remove(_ entry: PeakAlphaEntry) throws {
        try requireLoadedStore()

        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entryEntityName)
        request.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
        let objects = try context.fetch(request)
        for object in objects {
            context.delete(object)
        }
        try context.save()
        try load()
        try? writeBackupJSONStore()
    }

    private func deleteEntries(forDay day: Date) throws {
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entryEntityName)
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", day as NSDate, nextDay as NSDate)
        let objects = try context.fetch(request)
        for object in objects {
            context.delete(object)
        }
    }

    private func requireLoadedStore() throws {
        guard isReady else {
            throw StoreUnavailableError()
        }
    }

    private func fetchEntries() throws -> [PeakAlphaEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entryEntityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false)
        ]

        let objects = try context.fetch(request)
        return objects.compactMap(Self.entry(from:))
    }

    private static func entry(from object: NSManagedObject) -> PeakAlphaEntry? {
        guard let id = object.value(forKey: "id") as? UUID,
              let date = object.value(forKey: "date") as? Date,
              let value = object.value(forKey: "value") as? Double,
              let createdAt = object.value(forKey: "createdAt") as? Date,
              let updatedAt = object.value(forKey: "updatedAt") as? Date else {
            return nil
        }

        return PeakAlphaEntry(
            id: id,
            date: date,
            value: value,
            note: object.value(forKey: "note") as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func entityDescription(named name: String, in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: name, in: context)!
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entryEntity = NSEntityDescription()
        entryEntity.name = entryEntityName
        entryEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        entryEntity.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("date", type: .dateAttributeType),
            attribute("value", type: .doubleAttributeType),
            attribute("note", type: .stringAttributeType),
            attribute("createdAt", type: .dateAttributeType),
            attribute("updatedAt", type: .dateAttributeType),
        ]

        model.entities = [entryEntity]
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
        return directory.appendingPathComponent("SomnusPeakAlphaModel.sqlite")
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // MARK: - Legacy JSON migration

    /// Earlier builds stored Peak Alpha readings in a local JSON file
    /// (`Application Support/PeakAlphaEntries.json`) rather than Core Data.
    /// On first launch after upgrading, import anything still sitting in that
    /// file into CloudKit-backed storage so nothing gets lost, then archive
    /// the old file so this only runs once.
    private func migrateFromLegacyJSONStoreIfNeeded() throws {
        guard container.persistentStoreCoordinator.persistentStores.isEmpty == false else {
            // Stores haven't loaded yet (async path); the caller will retry
            // migration once `loadPersistentStores` completes.
            return
        }

        for legacyURL in legacyJSONFileURLs where FileManager.default.fileExists(atPath: legacyURL.path) {
            try migrateLegacyJSONStore(at: legacyURL)
        }
    }

    private func migrateLegacyJSONStore(at legacyURL: URL) throws {
        let data = try Data(contentsOf: legacyURL)
        let legacyEntries = try Self.decodeLegacyEntries(from: data)
        guard !legacyEntries.isEmpty else { return }

        let existingDays = Set(try fetchEntries().map(\.day))
        var importedCount = 0

        for legacyEntry in legacyEntries where !existingDays.contains(legacyEntry.day) {
            let object = NSManagedObject(
                entity: Self.entityDescription(named: Self.entryEntityName, in: context),
                insertInto: context
            )
            object.setValue(legacyEntry.id, forKey: "id")
            object.setValue(legacyEntry.date, forKey: "date")
            object.setValue(legacyEntry.value, forKey: "value")
            object.setValue(legacyEntry.note, forKey: "note")
            object.setValue(legacyEntry.createdAt, forKey: "createdAt")
            object.setValue(legacyEntry.updatedAt, forKey: "updatedAt")
            importedCount += 1
        }

        if importedCount > 0 {
            try context.save()
            try load()
            try? writeBackupJSONStore()
        }

        if legacyURL.lastPathComponent != Self.migratedLegacyJSONFileName {
            let archivedURL = legacyURL.deletingLastPathComponent()
                .appendingPathComponent(Self.migratedLegacyJSONFileName)
            try? FileManager.default.removeItem(at: archivedURL)
            try? FileManager.default.copyItem(at: legacyURL, to: archivedURL)
        }
    }

    private static func decodeLegacyEntries(from data: Data) throws -> [PeakAlphaEntry] {
        var errors: [Error] = []
        for strategy in legacyDateDecodingStrategies {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = strategy
            do {
                return try decoder.decode([PeakAlphaEntry].self, from: data)
            } catch {
                errors.append(error)
            }
        }

        throw errors.first ?? DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Unable to decode legacy Peak Alpha JSON.")
        )
    }

    private static var legacyDateDecodingStrategies: [JSONDecoder.DateDecodingStrategy] {
        [
            .iso8601,
            .deferredToDate,
            .secondsSince1970,
            .millisecondsSince1970
        ]
    }

    private static let migratedLegacyJSONFileName = "PeakAlphaEntries.migrated.json"
    private static let backupJSONFileName = "PeakAlphaEntries.backup.json"

    private static func defaultBackupJSONFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(backupJSONFileName)
    }

    private static func defaultLegacyJSONFileURLs(backupJSONFileURL: URL) -> [URL] {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            directory.appendingPathComponent("PeakAlphaEntries.json"),
            directory.appendingPathComponent(migratedLegacyJSONFileName),
            backupJSONFileURL
        ]
    }

    private func writeBackupJSONStore() throws {
        let directory = backupJSONFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: backupJSONFileURL, options: .atomic)
    }
}
