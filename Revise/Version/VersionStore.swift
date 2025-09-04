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
}
