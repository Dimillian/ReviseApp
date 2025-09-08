import Foundation
import SwiftData

@Model
final class Branch: Identifiable {
  static let main = "main"

  @Attribute(.unique)
  var id: String

  var name: String
  var createdAt: Date

  var document: Document

  var parent: Branch?
  var baseVersion: Version?

  @Relationship(deleteRule: .cascade, inverse: \Version.branch)
  var versions: [Version] = []

  var currentVersion: Version?

  init(name: String, document: Document) {
    self.id = UUID().uuidString
    self.name = name
    self.document = document
    self.createdAt = .now
  }
}
