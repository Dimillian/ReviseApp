import Foundation

@Observable
class Document: Codable, Identifiable, Hashable {
  let id: String
  var title: String

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: Document, rhs: Document) -> Bool {
    lhs.id == rhs.id
  }

  init(id: String) {
    self.id = id
    self.title = ""
  }
}
