import Foundation
import SwiftData

enum TextendSchemaV1: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 0, 0)
  static var models: [any PersistentModel.Type] { [SavedSnippet.self, SavedCollection.self] }

  @Model final class SavedSnippet {
    @Attribute(.unique) var id: UUID
    var name: String
    var keyword: String
    var template: String
    var collectionID: UUID?
    var isFavorite: Bool
    var isEnabled: Bool
    var placeholderData: Data
    var createdAt: Date
    var updatedAt: Date

    init(_ record: SnippetRecord) throws {
      id = record.id
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      placeholderData = try JSONEncoder().encode(record.placeholders)
      createdAt = record.createdAt
      updatedAt = record.updatedAt
    }

    func record() throws -> SnippetRecord {
      SnippetRecord(
        id: id, name: name, keyword: keyword, template: template,
        collectionID: collectionID, isFavorite: isFavorite, isEnabled: isEnabled,
        placeholders: try JSONDecoder().decode([PlaceholderDefinition].self, from: placeholderData),
        createdAt: createdAt, updatedAt: updatedAt)
    }

    func apply(_ record: SnippetRecord) throws {
      let data = try JSONEncoder().encode(record.placeholders)
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      placeholderData = data
      updatedAt = record.updatedAt
    }
  }

  @Model final class SavedCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    init(_ record: CollectionRecord) {
      id = record.id
      name = record.name
      sortOrder = record.sortOrder
    }
    var record: CollectionRecord { CollectionRecord(id: id, name: name, sortOrder: sortOrder) }
  }
}

enum TextendSchemaV2: VersionedSchema {
  static var versionIdentifier = Schema.Version(2, 0, 0)
  static var models: [any PersistentModel.Type] { [SavedSnippet.self, SavedCollection.self] }

  @Model final class SavedSnippet {
    var id: UUID = UUID()
    var rowID: String = ""
    var name: String = ""
    var keyword: String = ""
    var template: String = ""
    var collectionID: UUID?
    var isFavorite: Bool = false
    var isEnabled: Bool = true
    var placeholderData: Data = Data()
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    init(_ record: SnippetRecord) throws {
      id = record.id
      rowID = UUID().uuidString
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      placeholderData = try JSONEncoder().encode(record.placeholders)
      createdAt = record.createdAt
      updatedAt = record.updatedAt
    }

    func record() throws -> SnippetRecord {
      SnippetRecord(
        id: id, name: name, keyword: keyword, template: template,
        collectionID: collectionID, isFavorite: isFavorite, isEnabled: isEnabled,
        placeholders: try JSONDecoder().decode([PlaceholderDefinition].self, from: placeholderData),
        createdAt: createdAt, updatedAt: updatedAt)
    }

    func apply(_ record: SnippetRecord) throws {
      let data = try JSONEncoder().encode(record.placeholders)
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      placeholderData = data
      updatedAt = record.updatedAt
    }
  }

  @Model final class SavedCollection {
    var id: UUID = UUID()
    var rowID: String = ""
    var name: String = ""
    var sortOrder: Int = 0
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    init(_ record: CollectionRecord) {
      id = record.id
      rowID = UUID().uuidString
      name = record.name
      sortOrder = record.sortOrder
    }
    var record: CollectionRecord { CollectionRecord(id: id, name: name, sortOrder: sortOrder) }
  }
}

enum TextendSchemaV3: VersionedSchema {
  static var versionIdentifier = Schema.Version(3, 0, 0)
  static var models: [any PersistentModel.Type] {
    [SavedSnippet.self, SavedCollection.self, SavedComposition.self]
  }

  @Model final class SavedSnippet {
    var id: UUID = UUID()
    var rowID: String = ""
    var name: String = ""
    var keyword: String = ""
    var template: String = ""
    var collectionID: UUID?
    var isFavorite: Bool = false
    var isEnabled: Bool = true
    var placeholderData: Data = Data()
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    init(_ record: SnippetRecord) throws {
      id = record.id
      rowID = UUID().uuidString
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      placeholderData = try JSONEncoder().encode(record.placeholders)
      createdAt = record.createdAt
      updatedAt = record.updatedAt
    }

    func record() throws -> SnippetRecord {
      SnippetRecord(
        id: id, name: name, keyword: keyword, template: template,
        collectionID: collectionID, isFavorite: isFavorite, isEnabled: isEnabled,
        placeholders: try JSONDecoder().decode([PlaceholderDefinition].self, from: placeholderData),
        createdAt: createdAt, updatedAt: updatedAt)
    }

    func apply(_ record: SnippetRecord) throws {
      let data = try JSONEncoder().encode(record.placeholders)
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      placeholderData = data
      updatedAt = record.updatedAt
    }
  }

  @Model final class SavedComposition {
    var id: UUID = UUID()
    var rowID: String = ""
    var name: String = ""
    var keyword: String = ""
    var template: String = ""
    var collectionID: UUID?
    var isFavorite: Bool = false
    var isEnabled: Bool = true
    var blockData: Data = Data()
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    init(_ record: SnippetRecord) throws {
      id = record.id
      rowID = UUID().uuidString
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      blockData = try JSONEncoder().encode(record.blocks ?? [])
      createdAt = record.createdAt
      updatedAt = record.updatedAt
    }

    func record() throws -> SnippetRecord {
      SnippetRecord(
        id: id, name: name, keyword: keyword, template: template,
        collectionID: collectionID, isFavorite: isFavorite, isEnabled: isEnabled,
        createdAt: createdAt, updatedAt: updatedAt,
        blocks: try JSONDecoder().decode([CompositionBlock].self, from: blockData))
    }

    func apply(_ record: SnippetRecord) throws {
      let data = try JSONEncoder().encode(record.blocks ?? [])
      name = record.name
      keyword = record.keyword
      template = record.template
      collectionID = record.collectionID
      isFavorite = record.isFavorite
      isEnabled = record.isEnabled
      blockData = data
      updatedAt = record.updatedAt
    }
  }

  @Model final class SavedCollection {
    var id: UUID = UUID()
    var rowID: String = ""
    var name: String = ""
    var sortOrder: Int = 0
    var appBundleIDs: [String]? = nil
    var updatedAt: Date = Date(timeIntervalSince1970: 0)
    init(_ record: CollectionRecord) {
      id = record.id
      rowID = UUID().uuidString
      name = record.name
      sortOrder = record.sortOrder
      appBundleIDs = record.appBundleIDs
    }
    var record: CollectionRecord {
      CollectionRecord(id: id, name: name, sortOrder: sortOrder, appBundleIDs: appBundleIDs)
    }
  }
}

enum TextendMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [TextendSchemaV1.self, TextendSchemaV2.self, TextendSchemaV3.self]
  }
  static var stages: [MigrationStage] {
    [
      .custom(
        fromVersion: TextendSchemaV1.self, toVersion: TextendSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
          for item in try context.fetch(FetchDescriptor<TextendSchemaV2.SavedSnippet>()) {
            item.rowID = UUID().uuidString
          }
          for item in try context.fetch(FetchDescriptor<TextendSchemaV2.SavedCollection>()) {
            item.rowID = UUID().uuidString
          }
          try context.save()
        }),
      .lightweight(fromVersion: TextendSchemaV2.self, toVersion: TextendSchemaV3.self),
    ]
  }
}

typealias SavedSnippet = TextendSchemaV3.SavedSnippet
typealias SavedCollection = TextendSchemaV3.SavedCollection

typealias SavedComposition = TextendSchemaV3.SavedComposition
