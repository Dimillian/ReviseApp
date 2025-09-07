import Foundation
import SwiftData

@Model
final class Version {
  @Attribute(.unique) var id: String
  var timestamp: Date
  var text: String
  var changeKind: String
  
  var synonymWord: String?
  var synonymReplacement: String?
  var aiPrompt: String?
  
  var wordCount: Int
  var characterCount: Int
  var cursorPosition: Int?
  
  var selectedLocation: Int?
  var selectedLength: Int?
  var highlightedLocation: Int?
  var highlightedLength: Int?
  
  var branch: Branch
  
  init(
    id: String = UUID().uuidString,
    timestamp: Date = Date(),
    text: String,
    branch: Branch,
    changeKind: String = "manual",
    wordCount: Int = 0,
    characterCount: Int = 0
  ) {
    self.id = id
    self.timestamp = timestamp
    self.text = text
    self.branch = branch
    self.changeKind = changeKind
    self.wordCount = wordCount
    self.characterCount = characterCount
  }
  
  convenience init(
    text: String,
    branch: Branch,
    changeType: ChangeType,
    cursorPosition: Int? = nil,
    selectedRange: NSRange? = nil,
    highlightedRange: NSRange? = nil
  ) {
    let wordCount = text.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.count
    let characterCount = text.count
    
    self.init(
      text: text,
      branch: branch,
      changeKind: changeType.stringValue,
      wordCount: wordCount,
      characterCount: characterCount
    )
    
    self.cursorPosition = cursorPosition
    
    if let selectedRange = selectedRange {
      self.selectedLocation = selectedRange.location
      self.selectedLength = selectedRange.length
    }
    
    if let highlightedRange = highlightedRange {
      self.highlightedLocation = highlightedRange.location
      self.highlightedLength = highlightedRange.length
    }
    
    switch changeType {
    case .synonym(let word, let replacement):
      self.synonymWord = word
      self.synonymReplacement = replacement
    case .ai(let prompt):
      self.aiPrompt = prompt
    default:
      break
    }
  }
  
  var selectedRange: NSRange? {
    guard let location = selectedLocation, let length = selectedLength else { return nil }
    return NSRange(location: location, length: length)
  }
  
  var highlightedRange: NSRange? {
    guard let location = highlightedLocation, let length = highlightedLength else { return nil }
    return NSRange(location: location, length: length)
  }
  
  enum ChangeType: Equatable {
    case manual
    case synonym(word: String, replacement: String)
    case ai(prompt: String)
    case undo
    case redo
    
    var stringValue: String {
      switch self {
      case .manual: return "manual"
      case .synonym: return "synonym"
      case .ai: return "ai"
      case .undo: return "undo"
      case .redo: return "redo"
      }
    }
    
    init(from string: String, synonymWord: String? = nil, synonymReplacement: String? = nil, aiPrompt: String? = nil) {
      switch string {
      case "synonym":
        if let word = synonymWord, let replacement = synonymReplacement {
          self = .synonym(word: word, replacement: replacement)
        } else {
          self = .manual
        }
      case "ai":
        if let prompt = aiPrompt {
          self = .ai(prompt: prompt)
        } else {
          self = .manual
        }
      case "undo":
        self = .undo
      case "redo":
        self = .redo
      default:
        self = .manual
      }
    }
  }
  
  var changeType: ChangeType {
    ChangeType(from: changeKind, synonymWord: synonymWord, synonymReplacement: synonymReplacement, aiPrompt: aiPrompt)
  }
}

struct VersionDiff {
  let from: Version
  let to: Version
  let changedRanges: [NSRange]
  
  static func compute(from: Version, to: Version) -> VersionDiff {
    VersionDiff(from: from, to: to, changedRanges: [])
  }
}