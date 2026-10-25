import Foundation

extension SnippetRecord {
  func mergingChanges(from baseline: SnippetRecord, into remote: SnippetRecord) -> SnippetRecord {
    var result = remote
    if name != baseline.name { result.name = name }
    if keyword != baseline.keyword { result.keyword = keyword }
    if template != baseline.template { result.template = template }
    if collectionID != baseline.collectionID { result.collectionID = collectionID }
    if isFavorite != baseline.isFavorite { result.isFavorite = isFavorite }
    if isEnabled != baseline.isEnabled { result.isEnabled = isEnabled }
    if placeholders != baseline.placeholders { result.placeholders = placeholders }
    return result
  }
}
