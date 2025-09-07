import Foundation

struct TextDiffManager {
  struct DiffInfo {
    let ranges: [NSRange]
    let addedWords: Int
    let removedWords: Int
    let totalChangedChars: Int
    
    var hasDifferences: Bool {
      !ranges.isEmpty || addedWords != 0 || removedWords != 0
    }
  }
  
  static func findChangedRange(oldText: String, newText: String) -> NSRange? {
    // Simple diff: find first difference and last difference
    let old = Array(oldText)
    let new = Array(newText)

    let minLen = min(old.count, new.count)
    var firstDiff = minLen
    var lastDiffNew = new.count

    // Find first difference from start
    for i in 0..<minLen {
      if old[i] != new[i] {
        firstDiff = i
        break
      }
    }

    // Find last difference from end
    var oldIdx = old.count - 1
    var newIdx = new.count - 1
    while oldIdx >= firstDiff && newIdx >= firstDiff {
      if old[oldIdx] != new[newIdx] {
        break
      }
      oldIdx -= 1
      newIdx -= 1
    }
    lastDiffNew = newIdx + 1

    // If no changes found
    if firstDiff >= lastDiffNew {
      // Check if only length changed
      if old.count != new.count {
        return NSRange(location: minLen, length: abs(new.count - old.count))
      }
      return nil
    }

    return NSRange(location: firstDiff, length: lastDiffNew - firstDiff)
  }
  
  static func findAllChangedRanges(oldText: String, newText: String) -> [NSRange] {
    // For now, return single range - can be enhanced with proper diff algorithm later
    if let range = findChangedRange(oldText: oldText, newText: newText) {
      return [range]
    }
    return []
  }
  
  static func computeDiffInfo(oldText: String, newText: String) -> DiffInfo {
    let ranges = findAllChangedRanges(oldText: oldText, newText: newText)
    let oldWordCount = calculateWordCount(for: oldText)
    let newWordCount = calculateWordCount(for: newText)
    
    let addedWords = max(0, newWordCount - oldWordCount)
    let removedWords = max(0, oldWordCount - newWordCount)
    let totalChangedChars = ranges.reduce(0) { $0 + $1.length }
    
    return DiffInfo(
      ranges: ranges,
      addedWords: addedWords,
      removedWords: removedWords,
      totalChangedChars: totalChangedChars
    )
  }

  static func calculateWordCount(for text: String) -> Int {
    text.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .count
  }
}
