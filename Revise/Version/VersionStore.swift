import Foundation
import SwiftUI

@Observable
final class VersionStore {
  private(set) var versions: [Version] = []
  private(set) var currentIndex: Int = -1
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

  // MARK: - Initialization

  init(document: Document, documentStore: DocumentStore) {
    self.document = document
    self.documentStore = documentStore
    loadVersions()
  }

  private func loadVersions() {
    guard DocumentStore.fileManager.fileExists(atPath: versionsFile.path) else { return }

    do {
      let data = try Data(contentsOf: versionsFile)
      let savedData = try decoder.decode(SavedVersionData.self, from: data)
      self.versions = savedData.versions
      self.currentIndex = versions.isEmpty ? -1 : versions.count - 1
    } catch {
      print("Failed to load versions: \(error)")
    }
  }

  private func saveVersions() {
    let savedData = SavedVersionData(versions: versions, currentIndex: currentIndex)

    do {
      // Save versions
      let versionsData = try encoder.encode(savedData)
      try versionsData.write(to: versionsFile)

      // Save document metadata using DocumentStore
      documentStore.saveDocument(document)
    } catch {
      print("Failed to save versions: \(error)")
    }
  }

  private struct SavedVersionData: Codable {
    let versions: [Version]
    let currentIndex: Int
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
      highlightedRange: highlightedRange
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
