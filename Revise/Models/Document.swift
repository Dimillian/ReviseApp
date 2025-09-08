import Foundation
import SwiftData

@Model
final class Document {
  @Attribute(.unique) var id: String
  var title: String
  var lastEdited: Date

  var currentBranch: Branch?

  @Relationship(deleteRule: .cascade)
  var branches: [Branch] = []

  init(
    id: String = UUID().uuidString,
    title: String = "Untitled",
    lastEdited: Date = .now
  ) {
    self.id = id
    self.title = title
    self.lastEdited = lastEdited
  }
}
