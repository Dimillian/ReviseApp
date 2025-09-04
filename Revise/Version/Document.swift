import Foundation

@Observable
class Document: Codable, Identifiable, Hashable {
  let id: String
  var title: String
  var versions: Int
  var wordsCount: Int
  var branches: Int
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
    self.branches = 1
    self.lastEdited = Date()
  }

  // MARK: - Codable

  private enum CodingKeys: String, CodingKey {
    case id, title, versions, wordsCount, branches, lastEdited
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.title = try container.decode(String.self, forKey: .title)
    self.versions = try container.decode(Int.self, forKey: .versions)
    self.wordsCount = try container.decode(Int.self, forKey: .wordsCount)
    // Default to 1 (main) if absent
    self.branches = (try? container.decode(Int.self, forKey: .branches)) ?? 1
    self.lastEdited = try container.decode(Date.self, forKey: .lastEdited)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(versions, forKey: .versions)
    try container.encode(wordsCount, forKey: .wordsCount)
    try container.encode(branches, forKey: .branches)
    try container.encode(lastEdited, forKey: .lastEdited)
  }
}
