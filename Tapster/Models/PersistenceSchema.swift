import Foundation
import SwiftData

enum TapsterSchemaV1: VersionedSchema {
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

enum TapsterMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [TapsterSchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}

typealias SavedSnippet = TapsterSchemaV1.SavedSnippet
typealias SavedCollection = TapsterSchemaV1.SavedCollection
