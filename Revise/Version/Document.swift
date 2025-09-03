import Foundation

@Observable
class Document: Codable, Identifiable, Hashable {
  let id: String
  var title: String
  var versions: Int
  var wordsCount: Int
  var lastEdited: Date

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Document, rhs: Document) -> Bool {
    lhs.id == rhs.id
  }

  init(id: String) {
    self.id = id
    self.title = ""
    self.versions = 0
    self.wordsCount = 0
    self.lastEdited = Date()
  }
}
