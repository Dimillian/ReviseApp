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

  @Attribute(.externalStorage)
  private var attributedTextArchive: Data?

  init(
    id: String = UUID().uuidString,
    title: String = "Untitled",
    lastEdited: Date = .now
  ) {
    self.id = id
    self.title = title
    self.lastEdited = lastEdited
  }

  private var attributedTextMap: [String: Data] {
    get {
      guard
        let attributedTextArchive,
        let decoded = try? JSONDecoder().decode([String: Data].self, from: attributedTextArchive)
      else {
        return [:]
      }
      return decoded
    }
    set {
      attributedTextArchive = try? JSONEncoder().encode(newValue)
    }
  }

  func attributedText(for versionID: String) -> NSAttributedString? {
    guard let data = attributedTextMap[versionID] else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data)
  }

  func setAttributedText(_ attributedText: NSAttributedString, for versionID: String) {
    let archived = try? NSKeyedArchiver.archivedData(
      withRootObject: NSAttributedString(attributedString: attributedText),
      requiringSecureCoding: true
    )

    var map = attributedTextMap
    if let archived {
      map[versionID] = archived
    } else {
      map.removeValue(forKey: versionID)
    }
    attributedTextMap = map
  }

  func removeAttributedText(for versionID: String) {
    var map = attributedTextMap
    map.removeValue(forKey: versionID)
    attributedTextMap = map
  }
}
