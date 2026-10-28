import CoreData
import Foundation
import SwiftData

enum CloudSchemaInitializer {
  #if DEBUG
    @MainActor static func initialize(at url: URL) async throws {
      guard let model = NSManagedObjectModel.makeManagedObjectModel(for: TextendSchemaV3.models)
      else {
        throw TemplateError.invalid("Couldn’t create the CloudKit development schema.")
      }
      let container = NSPersistentCloudKitContainer(
        name: "TextendSchema", managedObjectModel: model)
      let description = NSPersistentStoreDescription(url: url)
      description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
        containerIdentifier: SyncConfiguration.containerIdentifier)
      container.persistentStoreDescriptions = [description]
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        container.loadPersistentStores { _, error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
      }
      defer {
        for store in container.persistentStoreCoordinator.persistentStores {
          try? container.persistentStoreCoordinator.remove(store)
        }
      }
      try container.initializeCloudKitSchema(options: [])
    }
  #endif
}
