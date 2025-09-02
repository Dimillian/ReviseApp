import Foundation

@Observable
class Document: Codable, Identifiable {
  let id: String
  var title: String

  init(id: String) {
    self.id = id
    self.title = ""
  }
}
