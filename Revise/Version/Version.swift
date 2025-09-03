import Foundation

// MARK: - Version Model
struct Version: Identifiable, Equatable, Codable {
  let id: String
  let timestamp: Date
  let text: String
  let changeType: ChangeType
  let metadata: ChangeMetadata

  enum ChangeType: Equatable, Codable {
    case manual
    case synonym(word: String, replacement: String)
    case ai(prompt: String)
    case undo
    case redo
  }

  struct ChangeMetadata: Equatable, Codable {
    let wordCount: Int
    let characterCount: Int
    let cursorPosition: Int?
    let selectedRange: NSRange?
    let highlightedRange: NSRange?  // Range to highlight for AI/synonym changes

    init(from text: String, cursorPosition: Int? = nil, selectedRange: NSRange? = nil, highlightedRange: NSRange? = nil) {
      self.characterCount = text.count
      self.wordCount =
        text.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }.count
      self.cursorPosition = cursorPosition
      self.selectedRange = selectedRange
      self.highlightedRange = highlightedRange
    }
  }

  init(
    text: String, changeType: ChangeType, cursorPosition: Int? = nil, selectedRange: NSRange? = nil, highlightedRange: NSRange? = nil
  ) {
    self.id = UUID().uuidString
    self.timestamp = Date()
    self.text = text
    self.changeType = changeType
    self.metadata = ChangeMetadata(
      from: text, cursorPosition: cursorPosition, selectedRange: selectedRange, highlightedRange: highlightedRange)
  }
}

// MARK: - Version Diff
struct VersionDiff {
  let from: Version
  let to: Version
  let changedRanges: [NSRange]

  static func compute(from: Version, to: Version) -> VersionDiff {
    // Simple diff for now - can be enhanced with proper text diffing algorithm
    VersionDiff(from: from, to: to, changedRanges: [])
  }
}
