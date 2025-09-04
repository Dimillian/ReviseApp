import Foundation
import SwiftUI

@Observable
final class VersionStore {
  // Current branch state (kept in sync with maps below)
  private(set) var versions: [Version] = []
  private(set) var currentIndex: Int = -1
  private(set) var currentBranch: String = Branch.main

  // All branches data
  private struct BranchState: Codable, Equatable {
    var versions: [Version]
    var currentIndex: Int
  }

  private var branchStates: [String: BranchState] = [:]
  private(set) var branches: [String: Branch] = [:]
  private(set) var document: Document
  private let documentStore: DocumentStore

  // Storage
  private var documentDirectory: URL {
    DocumentStore.documentDirectory(for: document.id)
  }
  private var versionsFile: URL {
    DocumentStore.versionsFile(for: document.id)
  }

  var currentVersion: Version? {
    guard currentIndex >= 0 && currentIndex < versions.count else { return nil }
    return versions[currentIndex]
  }

  var canUndo: Bool {
    currentIndex > 0
  }

  var canRedo: Bool {
    currentIndex < versions.count - 1
  }

  // Configuration
  private let maxVersions = 100
  private let coalescingInterval: TimeInterval = 2.0  // Coalesce rapid edits
  private var lastEditTime: Date?
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  // Dedicated serial queue for atomic disk I/O
  private let ioQueue = DispatchQueue(label: "com.revise.versionstore.io", qos: .utility)

  // MARK: - Initialization

  init(document: Document, documentStore: DocumentStore) {
    self.document = document
    self.documentStore = documentStore
    loadVersions()
  }

  private func loadVersions() {
    // Start with a default empty structure
    func initializeEmptyMain() {
      self.currentBranch = Branch.main
      self.branches = [Branch.main: Branch(id: Branch.main, ref: Branch.main, baseVersionId: nil)]
      self.branchStates = [Branch.main: BranchState(versions: [], currentIndex: -1)]
      self.versions = []
      self.currentIndex = -1
    }

    guard DocumentStore.fileManager.fileExists(atPath: versionsFile.path) else {
      initializeEmptyMain()
      return
    }

    do {
      let data = try Data(contentsOf: versionsFile)
      let saved = try decoder.decode(SavedData.self, from: data)
      self.branches = saved.branches
      self.branchStates = saved.branchStates
      self.currentBranch = saved.currentBranch

      if branches[Branch.main] == nil {
        branches[Branch.main] = Branch(id: Branch.main, ref: Branch.main, baseVersionId: nil)
      }

      let state = branchStates[currentBranch] ?? BranchState(versions: [], currentIndex: -1)
      self.versions = state.versions
      self.currentIndex = state.currentIndex
      // Keep document metadata in sync
      self.document.branches = branches.count
    } catch {
      // Destructive migration: if decode fails, reinitialize to empty main.
      initializeEmptyMain()
      saveVersions()
    }
  }

  private func saveVersions() {
    // Keep state in sync with current branch view
    branchStates[currentBranch] = BranchState(versions: versions, currentIndex: currentIndex)

    // Keep document metadata in sync
    document.branches = branches.count

    let snapshot = SavedData(
      branches: branches,
      branchStates: branchStates,
      currentBranch: currentBranch
    )

    let versionsURL = versionsFile

    let data = try? encoder.encode(snapshot)

    ioQueue.async { [weak self] in
      guard let self, let data else { return }

      try? data.write(to: versionsURL, options: .atomic)

      self.documentStore.saveDocument(self.document)
    }
  }

  private struct SavedData: Codable, Sendable {
    let branches: [String: Branch]
    let branchStates: [String: BranchState]
    let currentBranch: String
  }

  // MARK: - Public Methods

  func addVersion(_ version: Version) {
    // Remove any versions after current index (branching)
    if currentIndex < versions.count - 1 {
      versions.removeSubrange((currentIndex + 1)..<versions.count)
    }

    // Check if we should coalesce with the last version
    if shouldCoalesce(with: version) {
      // Update the last version instead of adding new
      if currentIndex >= 0 {
        versions[currentIndex] = version
      }
    } else {
      // Add new version
      versions.append(version)
      currentIndex = versions.count - 1

      // Trim old versions if needed
      if versions.count > maxVersions {
        versions.removeFirst()
        currentIndex = max(0, currentIndex - 1)
      }
    }

    lastEditTime = Date()
    saveVersions()
    documentStore.saveDocument(document)
  }

  func createVersion(
    text: String, changeType: Version.ChangeType, cursorPosition: Int? = nil,
    selectedRange: NSRange? = nil, highlightedRange: NSRange? = nil, updatedTitle: String? = nil
  ) {
    if let updatedTitle {
      document.title = updatedTitle
    }
    let version = Version(
      text: text,
      changeType: changeType,
      cursorPosition: cursorPosition,
      selectedRange: selectedRange,
      highlightedRange: highlightedRange,
      branch: currentBranch
    )

    document.wordsCount = version.metadata.wordCount
    document.versions = versions.count + 1
    document.lastEdited = Date()

    addVersion(version)
  }

  func undo() -> Version? {
    guard canUndo else { return nil }
    currentIndex -= 1
    saveVersions()
    return currentVersion
  }

  func redo() -> Version? {
    guard canRedo else { return nil }
    currentIndex += 1
    saveVersions()
    return currentVersion
  }

  func navigateToVersion(at index: Int) -> Version? {
    guard index >= 0 && index < versions.count else { return nil }
    currentIndex = index
    saveVersions()
    return currentVersion
  }

  func navigateToVersion(_ version: Version) -> Version? {
    guard let index = versions.firstIndex(of: version) else { return nil }
    return navigateToVersion(at: index)
  }

  func clear() {
    versions.removeAll()
    currentIndex = -1
    lastEditTime = nil
    saveVersions()
  }

  // MARK: - Branch Management

  @discardableResult
  func createBranch(named name: String) -> Branch {
    // Normalize and ensure uniqueness
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let branchName = trimmed.isEmpty ? UUID().uuidString : trimmed

    if let existing = branches[branchName] { return existing }

    let baseVersionId = currentVersion?.id
    let branch = Branch(id: branchName, ref: currentBranch, baseVersionId: baseVersionId)
    branches[branchName] = branch

    // Seed new branch with current snapshot (if any)
    if let seed = currentVersion {
      // Create a fresh version on the new branch seeded with current text
      let seededVersion = Version(
        text: seed.text,
        changeType: .manual,
        cursorPosition: seed.metadata.cursorPosition,
        selectedRange: seed.metadata.selectedRange,
        highlightedRange: seed.metadata.highlightedRange,
        branch: branchName
      )
      branchStates[branchName] = BranchState(versions: [seededVersion], currentIndex: 0)
    } else {
      branchStates[branchName] = BranchState(versions: [], currentIndex: -1)
    }

    saveVersions()
    return branch
  }

  func switchBranch(to name: String) {
    guard name != currentBranch else { return }
    // Ensure branch exists
    if branches[name] == nil {
      // Auto-create empty branch that references current
      _ = createBranch(named: name)
    }

    // Persist current view into maps
    branchStates[currentBranch] = BranchState(versions: versions, currentIndex: currentIndex)

    // Switch current branch view
    currentBranch = name
    let state = branchStates[currentBranch] ?? BranchState(versions: [], currentIndex: -1)
    versions = state.versions
    currentIndex = state.currentIndex

    saveVersions()
  }

  // MARK: - Private Methods

  private func shouldCoalesce(with newVersion: Version) -> Bool {
    guard let lastEdit = lastEditTime,
      let current = currentVersion
    else { return false }

    // Don't coalesce different change types
    switch (current.changeType, newVersion.changeType) {
    case (.manual, .manual):
      // Coalesce rapid manual edits
      return Date().timeIntervalSince(lastEdit) < coalescingInterval
    case (.synonym, _), (_, .synonym):
      // Never coalesce synonym changes
      return false
    case (.ai, _), (_, .ai):
      // Never coalesce AI changes
      return false
    default:
      return false
    }
  }

  // MARK: - Timeline Helpers

  func getVersionsInRange(from: Int, to: Int) -> [Version] {
    let start = max(0, from)
    let end = min(versions.count - 1, to)
    guard start <= end else { return [] }
    return Array(versions[start...end])
  }

  func getRecentVersions(count: Int = 10) -> [Version] {
    guard !versions.isEmpty else { return [] }
    let start = max(0, versions.count - count)
    return Array(versions[start..<versions.count])
  }

  // MARK: - Branch Helpers (public read-only)

  /// Ordered list of branch identifiers, with main first
  var branchIds: [String] {
    let others = branches.keys.filter { $0 != Branch.main }.sorted()
    return [Branch.main] + others
  }

  /// Latest version in a specific branch without switching context
  func latestVersion(forBranch name: String) -> Version? {
    branchStates[name]?.versions.last
  }

  /// Generate a branch preview focusing on the most relevant changed text.
  /// Strategy:
  /// - Use latest version's highlightedRange if available (manual/synonym edits)
  /// - Else, diff against baseVersion in the reference branch and show around divergence
  /// - Else, show the tail of the text
  func preview(forBranch name: String, maxChars: Int = 140) -> String {
    guard let latest = latestVersion(forBranch: name) else { return "" }
    let text = latest.text as NSString
    let fullLen = text.length

    // 1) Prefer latest highlighted range (recent manual/synonym edits)
    if let hr = latest.metadata.highlightedRange, hr.length > 0, hr.location != NSNotFound {
      let context = max(20, maxChars / 3)
      let start = max(0, hr.location - context)
      let end = min(fullLen, hr.location + hr.length + context)
      var snippet = text.substring(with: NSRange(location: start, length: end - start))
      if start > 0 { snippet = "… " + snippet }
      if end < fullLen { snippet += " …" }
      return snippet
    }

    // 2) Compare against base in reference branch to find divergence
    if let branch = branches[name],
      let baseId = branch.baseVersionId,
      let refState = branchStates[branch.ref],
      let base = refState.versions.first(where: { $0.id == baseId })
    {
      let baseText = base.text as NSString
      let lcp = longestCommonPrefixLength(a: text, b: baseText)
      let pivot = min(max(0, lcp), fullLen)
      // Center window around pivot
      let half = maxChars / 2
      let start = max(0, pivot - half)
      let end = min(fullLen, start + maxChars)
      var snippet = text.substring(with: NSRange(location: start, length: end - start))
      if start > 0 { snippet = "… " + snippet }
      if end < fullLen { snippet += " …" }
      return snippet
    }

    // 3) Fallback to tail of the text
    if fullLen <= maxChars { return text as String }
    let start = max(0, fullLen - maxChars)
    let snippet = text.substring(with: NSRange(location: start, length: fullLen - start))
    return "… " + snippet
  }

  private func longestCommonPrefixLength(a: NSString, b: NSString) -> Int {
    let minLen = min(a.length, b.length)
    var i = 0
    while i < minLen {
      if a.character(at: i) != b.character(at: i) { break }
      i += 1
    }
    return i
  }

  // MARK: - Attributed Previews

  /// Like `preview(forBranch:)` but returns an AttributedString with emphasis color on the changed segment.
  func previewAttributed(forBranch name: String, maxChars: Int = 140) -> AttributedString {
    guard let latest = latestVersion(forBranch: name) else { return AttributedString("") }
    let text = latest.text as NSString
    let fullLen = text.length

    var snippetRange = NSRange(location: 0, length: min(fullLen, maxChars))
    var highlightRangeInSnippet: NSRange? = nil

    // 1) If we have a highlighted change in the latest version, window around it
    if let hr = latest.metadata.highlightedRange, hr.length > 0, hr.location != NSNotFound {
      let context = max(20, maxChars / 3)
      let start = max(0, hr.location - context)
      let end = min(fullLen, hr.location + hr.length + context)
      snippetRange = NSRange(location: start, length: end - start)
      highlightRangeInSnippet = NSRange(
        location: hr.location - start, length: min(hr.length, snippetRange.length))
    } else if let branch = branches[name],
      let baseId = branch.baseVersionId,
      let refState = branchStates[branch.ref],
      let base = refState.versions.first(where: { $0.id == baseId })
    {
      // 2) Otherwise, window around divergence pivot
      let baseText = base.text as NSString
      let lcp = longestCommonPrefixLength(a: text, b: baseText)
      let pivot = min(max(0, lcp), fullLen)
      let half = maxChars / 2
      let start = max(0, pivot - half)
      let end = min(fullLen, start + maxChars)
      snippetRange = NSRange(location: start, length: end - start)
      let hlStart = max(0, pivot - start)
      let hlLen = min(24, snippetRange.length - hlStart)
      if hlLen > 0 { highlightRangeInSnippet = NSRange(location: hlStart, length: hlLen) }
    } else {
      // 3) Fallback: tail
      if fullLen > maxChars {
        let start = max(0, fullLen - maxChars)
        snippetRange = NSRange(location: start, length: fullLen - start)
      }
    }

    var output = text.substring(with: snippetRange)
    if snippetRange.location > 0 { output = "… " + output }
    if snippetRange.location + snippetRange.length < fullLen { output += " …" }

    var attr = AttributedString(output)
    if let hr = highlightRangeInSnippet {
      // Adjust for leading ellipsis prefix
      let lead = snippetRange.location > 0 ? 2 : 0  // "… " length
      let start = hr.location + lead
      if start >= 0, start < attr.characters.count {
        let from = attr.index(attr.startIndex, offsetByCharacters: start)
        let to = attr.index(
          from, offsetByCharacters: min(hr.length, max(0, attr.characters.count - start)))
        let range = from..<to
        attr[range].foregroundColor = .accentBlue
      }
    }
    return attr
  }

  // MARK: - Branch Graph (nodes + edges)

  struct BranchNode: Identifiable, Equatable {
    let id: String
    let ref: String
    let baseVersionId: String?
    let createdAt: Date
    let level: Int
    let order: Int
  }

  struct BranchEdge: Hashable {
    let from: String  // parent branch id
    let to: String  // child branch id
  }

  /// Compute a simple hierarchical graph of branches starting from main.
  func branchGraph() -> (nodes: [BranchNode], edges: [BranchEdge]) {
    // Build adjacency from ref -> [child]
    var children: [String: [Branch]] = [:]
    for (_, br) in branches {
      children[br.ref, default: []].append(br)
    }

    // BFS from main to assign levels; sort children by createdAt for stability
    var nodes: [BranchNode] = []
    var edges: [BranchEdge] = []
    var queue: [(branchId: String, level: Int)] = [(Branch.main, 0)]
    var seen: Set<String> = []
    var levelOrders: [Int: Int] = [:]

    while !queue.isEmpty {
      let (bid, level) = queue.removeFirst()
      guard let b = branches[bid], !seen.contains(bid) else { continue }
      seen.insert(bid)

      let order = levelOrders[level, default: 0]
      levelOrders[level] = order + 1
      nodes.append(
        BranchNode(
          id: b.id,
          ref: b.ref,
          baseVersionId: b.baseVersionId,
          createdAt: b.createdAt,
          level: level,
          order: order
        ))

      // Enqueue children sorted by createdAt
      let kids = (children[b.id] ?? []).sorted { $0.createdAt < $1.createdAt }
      for child in kids {
        edges.append(BranchEdge(from: b.id, to: child.id))
        queue.append((child.id, level + 1))
      }
    }

    // Add any disconnected branches (defensive, should not happen)
    for (id, b) in branches where !seen.contains(id) {
      nodes.append(
        BranchNode(
          id: b.id,
          ref: b.ref,
          baseVersionId: b.baseVersionId,
          createdAt: b.createdAt,
          level: 0,
          order: levelOrders[0, default: 0]
        ))
      levelOrders[0, default: 0] += 1
      if branches[b.ref] != nil { edges.append(BranchEdge(from: b.ref, to: b.id)) }
    }

    // Ensure main exists in nodes
    if nodes.first(where: { $0.id == Branch.main }) == nil {
      nodes.append(
        BranchNode(
          id: Branch.main,
          ref: Branch.main,
          baseVersionId: nil,
          createdAt: Date(),
          level: 0,
          order: 0
        ))
    }

    return (nodes, edges)
  }
}
