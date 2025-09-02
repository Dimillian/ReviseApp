import Foundation

// MARK: - Version Model
struct Version: Identifiable, Equatable {
  let id = UUID()
  let timestamp: Date
  let text: String
  let changeType: ChangeType
  let metadata: ChangeMetadata
  
  enum ChangeType: Equatable {
    case initial
    case manual
    case synonym(word: String, replacement: String)
    case ai(prompt: String)
    case undo
    case redo
  }
  
  struct ChangeMetadata: Equatable {
    let wordCount: Int
    let characterCount: Int
    let cursorPosition: Int?
    let selectedRange: NSRange?
    
    init(from text: String, cursorPosition: Int? = nil, selectedRange: NSRange? = nil) {
      self.characterCount = text.count
      self.wordCount = text.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }.count
      self.cursorPosition = cursorPosition
      self.selectedRange = selectedRange
    }
  }
  
  init(text: String, changeType: ChangeType, cursorPosition: Int? = nil, selectedRange: NSRange? = nil) {
    self.timestamp = Date()
    self.text = text
    self.changeType = changeType
    self.metadata = ChangeMetadata(from: text, cursorPosition: cursorPosition, selectedRange: selectedRange)
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