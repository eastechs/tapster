import CoreData
import SwiftData
import XCTest

@testable import TextendCore

final class PersistenceIdentityTests: XCTestCase {
  @MainActor func testRenamedModelsRetainReleasedEntityHashes() throws {
    // Captured from 0.2.1's original module before renaming the module and schema types.
    let released: [(any VersionedSchema.Type, [String: String])] = [
      (
        TextendSchemaV1.self,
        [
          "SavedCollection": "DnvGNOsHvalBWyXEVnvVcGsIzff71xXsEP32C3wd5Ms=",
          "SavedSnippet": "GxKFZTph5yPqhg8lknGYTLPrx/z22gGiJx1FxqrRycg=",
        ]
      ),
      (
        TextendSchemaV2.self,
        [
          "SavedCollection": "5YPuLu7SNfGXxqm90dIHFJ/o6sVXZEdZ6WU7vf9x0NA=",
          "SavedSnippet": "dUfhMQ+1WRPxAVpajpK93n39jbKOJ2tBnW9lGOp9WGk=",
        ]
      ),
    ]
    for (schema, expected) in released {
      let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: schema.models))
      XCTAssertEqual(
        model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, expected)
    }
  }
}
