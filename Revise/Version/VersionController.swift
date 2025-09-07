import Foundation
import SwiftData
import SwiftUI

@Observable
final class VersionController {
  let document: Document
  var modelContext: ModelContext?

  private let maxVersions = 100
  private let coalescingInterval: TimeInterval = 2.0
  private var lastEditTime: Date?

  var shouldUpdateEditor: Bool = false

  init(document: Document) {
    self.document = document
  }

  var currentBranch: Branch? {
    document.currentBranch
  }

  var currentVersion: Version? {
    currentBranch?.currentVersion
  }

  var versions: [Version] {
    currentBranch?.versions ?? []
  }

  var currentIndex: Int {
    guard let current = currentVersion else { return -1 }
    return versions.firstIndex(where: { $0.id == current.id }) ?? -1
  }

  var canUndo: Bool {
    currentIndex > 0
  }

  var canRedo: Bool {
    currentIndex < versions.count - 1
  }

  func addVersion(
    text: String,
    changeType: Version.ChangeType,
    cursorPosition: Int? = nil,
    selectedRange: NSRange? = nil,
    highlightedRange: NSRange? = nil,
    updatedTitle: String? = nil
  ) {
    guard let branch = currentBranch else { return }

    if let updatedTitle = updatedTitle {
      document.title = updatedTitle
    }

    let wordCount = text.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.count
    let characterCount = text.count

    if shouldCoalesce(changeType: changeType, wordCount: wordCount) {
      if let lastVersion = branch.currentVersion,
        lastVersion.changeKind == "manual"
      {
        lastVersion.text = text
        lastVersion.wordCount = wordCount
        lastVersion.characterCount = characterCount
        lastVersion.cursorPosition = cursorPosition

        if let selectedRange = selectedRange {
          lastVersion.selectedLocation = selectedRange.location
          lastVersion.selectedLength = selectedRange.length
        }

        if let highlightedRange = highlightedRange {
          lastVersion.highlightedLocation = highlightedRange.location
          lastVersion.highlightedLength = highlightedRange.length
        }

      }
    } else {
      lastEditTime = Date()
      let branchVersions = versions
      if let currentVersion = branch.currentVersion,
        let currentIdx = branchVersions.firstIndex(where: { $0.id == currentVersion.id }),
        currentIdx < branchVersions.count - 1
      {
        let toRemove = Array(branchVersions[(currentIdx + 1)...])
        for version in toRemove {
          if let idx = branch.versions.firstIndex(where: { $0.id == version.id }) {
            branch.versions.remove(at: idx)
            modelContext?.delete(version)
          }
        }
      }

      let newVersion = Version(
        text: text,
        branch: branch,
        changeType: changeType,
        cursorPosition: cursorPosition,
        selectedRange: selectedRange,
        highlightedRange: highlightedRange
      )
      branch.versions.append(newVersion)
      branch.currentVersion = newVersion

      if branch.versions.count > maxVersions {
        if let firstVersion = branch.versions.first {
          branch.versions.removeFirst()
          modelContext?.delete(firstVersion)
        }
      }
    }

    document.lastEdited = Date()

    try? modelContext?.save()
  }

  func undo() -> Version? {
    guard canUndo else { return nil }
    let versionList = versions
    guard currentIndex > 0 && currentIndex - 1 < versionList.count else { return nil }

    let targetVersion = versionList[currentIndex - 1]
    currentBranch?.currentVersion = targetVersion
    try? modelContext?.save()
    return targetVersion
  }

  func redo() -> Version? {
    guard canRedo else { return nil }
    let versionList = versions
    guard currentIndex + 1 < versionList.count else { return nil }

    let targetVersion = versionList[currentIndex + 1]
    currentBranch?.currentVersion = targetVersion
    try? modelContext?.save()
    return targetVersion
  }

  func navigateToVersion(at index: Int, shouldUpdateEditor: Bool = false) -> Version? {
    let versionList = versions
    guard index >= 0 && index < versionList.count else { return nil }

    let targetVersion = versionList[index]
    self.shouldUpdateEditor = shouldUpdateEditor
    currentBranch?.currentVersion = targetVersion
    return targetVersion
  }

  func navigateToVersion(_ version: Version, shouldUpdateEditor: Bool = false) -> Version? {
    guard version.branch.id == currentBranch?.id else { return nil }
    self.shouldUpdateEditor = shouldUpdateEditor
    currentBranch?.currentVersion = version
    return version
  }

  @discardableResult
  func createBranch(named name: String) -> Branch {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let branchName = trimmed.isEmpty ? UUID().uuidString : trimmed

    if let existing = document.branches.first(where: { $0.id == branchName }) {
      return existing
    }

    let newBranch = Branch(name: branchName, document: document)
    newBranch.parent = currentBranch
    newBranch.baseVersion = currentBranch?.currentVersion

    if let currentVersion = currentBranch?.currentVersion {
      let seedVersion = Version(
        text: currentVersion.text,
        branch: newBranch,
        changeType: .manual,
        cursorPosition: currentVersion.cursorPosition,
        selectedRange: currentVersion.selectedRange,
        highlightedRange: currentVersion.highlightedRange
      )
      newBranch.versions.append(seedVersion)
      newBranch.currentVersion = seedVersion
    }

    document.branches.append(newBranch)
    document.currentBranch = newBranch

    try? modelContext?.save()
    return newBranch
  }

  func switchToBranch(named name: String) {
    guard let branch = document.branches.first(where: { $0.id == name }) else { return }
    document.currentBranch = branch
    try? modelContext?.save()
  }

  func deleteBranch(named name: String) {
    guard name != Branch.main,
      let branch = document.branches.first(where: { $0.id == name })
    else { return }

    if document.currentBranch?.id == name {
      document.currentBranch = document.branches.first(where: { $0.id == Branch.main })
    }

    if let index = document.branches.firstIndex(where: { $0.id == name }) {
      document.branches.remove(at: index)
    }
    modelContext?.delete(branch)

    try? modelContext?.save()
  }

  func renameBranch(from oldName: String, to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      trimmed != oldName,
      let branch = document.branches.first(where: { $0.id == oldName }),
      !document.branches.contains(where: { $0.id == trimmed })
    else { return }

    branch.id = trimmed
    try? modelContext?.save()
  }

  func latestVersion(for branch: Branch) -> Version? {
    branch.currentVersion ?? branch.versions.sorted { $0.timestamp < $1.timestamp }.last
  }

  func previewText(for branch: Branch, maxLength: Int = 50) -> String {
    let text = latestVersion(for: branch)?.text ?? ""
    if text.count <= maxLength {
      return text
    }
    // Show the end of the document with ellipsis at the beginning
    return "..." + String(text.suffix(maxLength))
  }

  func previewTextSmartly(
    for branch: Branch, withDiffInfo diffInfo: TextDiffManager.DiffInfo?, maxLength: Int = 50
  ) -> String {
    let text = latestVersion(for: branch)?.text ?? ""

    // If text fits, show all
    if text.count <= maxLength {
      return text
    }

    // If there's a diff, try to show the changed region
    if let diffInfo = diffInfo,
      let firstRange = diffInfo.ranges.first
    {

      // Calculate context around the change
      let contextBefore = 15
      let contextAfter = maxLength - contextBefore - 10  // Leave room for change

      let changeStart = firstRange.location
      let changeEnd = firstRange.location + firstRange.length

      // Determine preview window
      let previewStart = max(0, changeStart - contextBefore)
      let previewEnd = min(text.count, changeEnd + contextAfter)

      // Extract preview
      let startIdx = text.index(text.startIndex, offsetBy: previewStart)
      let endIdx = text.index(text.startIndex, offsetBy: min(previewEnd, text.count))

      var preview = String(text[startIdx..<endIdx])

      // Add ellipsis if needed
      if previewStart > 0 {
        preview = "..." + preview
      }
      if previewEnd < text.count && preview.count < maxLength {
        preview = preview + "..."
      }

      // Truncate if still too long
      if preview.count > maxLength + 6 {  // Allow for ellipsis
        preview = String(preview.prefix(maxLength)) + "..."
      }

      return preview
    }

    // Default: show the end
    return "..." + String(text.suffix(maxLength))
  }

  func previewAttributedString(for branch: Branch, withDiff: Bool = false) -> AttributedString {
    let preview = previewText(for: branch)
    var attributed = AttributedString(preview)

    // Highlight diff if requested and available
    if withDiff,
      let parentBranch = branch.parent,
      let branchText = latestVersion(for: branch)?.text,
      let parentText = latestVersion(for: parentBranch)?.text,
      let diffRange = TextDiffManager.findChangedRange(oldText: parentText, newText: branchText)
    {

      // Check if we're showing the end (starts with "...")
      let isEndPreview = preview.hasPrefix("...")

      if isEndPreview {
        // For end preview, calculate if diff is in the visible part
        let textLength = branchText.count
        let previewStartInOriginal = textLength - 50  // Where our preview starts in the original text

        // Check if diff overlaps with our preview window
        if diffRange.location + diffRange.length > previewStartInOriginal {
          // Calculate the range within our preview string
          let diffStartInPreview = max(0, diffRange.location - previewStartInOriginal) + 3  // +3 for "..."
          let diffEndInPreview = min(
            preview.count, diffRange.location + diffRange.length - previewStartInOriginal + 3)

          if diffStartInPreview < preview.count && diffEndInPreview > diffStartInPreview {
            let startIdx = preview.index(preview.startIndex, offsetBy: diffStartInPreview)
            let endIdx = preview.index(preview.startIndex, offsetBy: diffEndInPreview)
            if let attrRange = attributed.range(of: preview[startIdx..<endIdx]) {
              attributed[attrRange].backgroundColor = Color.aiPurple.opacity(0.2)
              attributed[attrRange].underlineStyle = Text.LineStyle(
                pattern: .solid,
                color: Color.successGold.opacity(0.5)
              )
            }
          }
        }
      } else {
        // For beginning preview or full text, use original logic
        if diffRange.location < preview.count {
          let diffStart = preview.index(preview.startIndex, offsetBy: diffRange.location)
          let diffEnd = preview.index(
            diffStart, offsetBy: min(diffRange.length, preview.count - diffRange.location))
          if let attrRange = attributed.range(of: preview[diffStart..<diffEnd]) {
            attributed[attrRange].backgroundColor = Color.aiPurple.opacity(0.2)
            attributed[attrRange].underlineStyle = Text.LineStyle(
              pattern: .solid,
              color: Color.successGold.opacity(0.5)
            )
          }
        }
      }
    }

    if let range = attributed.range(of: "...") {
      attributed[range].foregroundColor = .secondary
    }
    return attributed
  }

  struct BranchNode: Identifiable {
    let id: String
    let name: String
    let parentId: String?
    let preview: String
    let isCurrentBranch: Bool
    let hasAI: Bool
    let hasSynonym: Bool
    let diffRange: NSRange?  // Range of text that differs from parent branch
    let diffInfo: TextDiffManager.DiffInfo?  // Detailed diff information
  }

  struct BranchEdge: Identifiable {
    let id = UUID()
    let from: String
    let to: String
  }

  func branchGraph() -> (nodes: [BranchNode], edges: [BranchEdge]) {
    var nodes: [BranchNode] = []
    var edges: [BranchEdge] = []

    for branch in document.branches {
      let hasAI = branch.versions.contains { $0.changeKind == "ai" }
      let hasSynonym = branch.versions.contains { $0.changeKind == "synonym" }

      // Compute diff from parent branch
      var diffRange: NSRange? = nil
      var diffInfo: TextDiffManager.DiffInfo? = nil
      if let parentBranch = branch.parent,
        let branchText = latestVersion(for: branch)?.text,
        let parentText = latestVersion(for: parentBranch)?.text
      {
        diffRange = TextDiffManager.findChangedRange(
          oldText: parentText,
          newText: branchText
        )
        diffInfo = TextDiffManager.computeDiffInfo(
          oldText: parentText,
          newText: branchText
        )
      }

      let node = BranchNode(
        id: branch.id,
        name: branch.name,
        parentId: branch.parent?.id,
        preview: previewTextSmartly(for: branch, withDiffInfo: diffInfo),
        isCurrentBranch: branch.id == document.currentBranch?.id,
        hasAI: hasAI,
        hasSynonym: hasSynonym,
        diffRange: diffRange,
        diffInfo: diffInfo
      )
      nodes.append(node)

      if let parentId = branch.parent?.id {
        edges.append(BranchEdge(from: parentId, to: branch.id))
      }
    }

    return (nodes, edges)
  }

  private func shouldCoalesce(changeType: Version.ChangeType, wordCount: Int) -> Bool {
    guard case .manual = changeType,
      let lastEdit = lastEditTime,
      Date().timeIntervalSince(lastEdit) < coalescingInterval
    else {
      return false
    }
    return true
  }
}
