import Foundation
import SwiftUI

@Observable
final class VersionStore {
  private(set) var versions: [Version] = []
  private(set) var currentIndex: Int = -1
  private(set) var document: Document

  // Storage
  private let fileManager = FileManager.default
  private var documentsDirectory: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
  }
  private var versionsDirectory: URL {
    documentsDirectory.appendingPathComponent("Versions")
  }
  private var documentDirectory: URL {
    versionsDirectory.appendingPathComponent(document.id)
  }
  private var versionsFile: URL {
    documentDirectory.appendingPathComponent("versions.json")
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

  init(document: Document) {
    self.document = document
    setupStorage()
    loadVersions()
  }

  private func setupStorage() {
    // Create directories if they don't exist
    try? fileManager.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
  }

  private func loadVersions() {
    // Load document metadata if it exists
    let documentFile = documentDirectory.appendingPathComponent("document.json")
    if fileManager.fileExists(atPath: documentFile.path) {
      do {
        let data = try Data(contentsOf: documentFile)
        self.document = try decoder.decode(Document.self, from: data)
      } catch {
        print("Failed to load document metadata: \(error)")
      }
    }

    // Load versions
    guard fileManager.fileExists(atPath: versionsFile.path) else { return }

    do {
      let data = try Data(contentsOf: versionsFile)
      let savedData = try decoder.decode(SavedVersionData.self, from: data)
      self.versions = savedData.versions
      self.currentIndex = savedData.currentIndex
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

      // Save document metadata
      let documentFile = documentDirectory.appendingPathComponent("document.json")
      let documentData = try encoder.encode(document)
      try documentData.write(to: documentFile)
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
  }

  func createVersion(
    text: String, changeType: Version.ChangeType, cursorPosition: Int? = nil,
    selectedRange: NSRange? = nil, updatedTitle: String? = nil
  ) {
    if let updatedTitle {
      document.title = updatedTitle
    }
    let version = Version(
      text: text,
      changeType: changeType,
      cursorPosition: cursorPosition,
      selectedRange: selectedRange
    )
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

  // MARK: - Document Management

  func switchToDocument(_ newDocument: Document) {
    // Save current document's versions
    saveVersions()

    // Switch to new document
    self.document = newDocument
    setupStorage()

    // Clear current state
    versions.removeAll()
    currentIndex = -1
    lastEditTime = nil

    // Load new document's versions
    loadVersions()
  }

  static func listDocuments() -> [Document] {
    let fileManager = FileManager.default
    let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let versionsDirectory = documentsDirectory.appendingPathComponent("Versions")

    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: versionsDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
      )
    else {
      return []
    }

    return contents.compactMap { url in
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        // Try to load document metadata
        let documentFile = url.appendingPathComponent("document.json")
        if let data = try? Data(contentsOf: documentFile),
          let document = try? JSONDecoder().decode(Document.self, from: data)
        {
          return document
        } else {
          // Fallback for documents without metadata
          return Document(id: url.lastPathComponent)
        }
      }
      return nil
    }
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
