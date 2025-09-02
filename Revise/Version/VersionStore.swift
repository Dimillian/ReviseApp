import SwiftUI

@Observable
final class VersionStore {
  // MARK: - Properties
  private(set) var versions: [Version] = []
  private(set) var currentIndex: Int = -1
  
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
  private let coalescingInterval: TimeInterval = 2.0 // Coalesce rapid edits
  private var lastEditTime: Date?
  
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
  }
  
  func createVersion(text: String, changeType: Version.ChangeType, cursorPosition: Int? = nil, selectedRange: NSRange? = nil) {
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
    return currentVersion
  }
  
  func redo() -> Version? {
    guard canRedo else { return nil }
    currentIndex += 1
    return currentVersion
  }
  
  func navigateToVersion(at index: Int) -> Version? {
    guard index >= 0 && index < versions.count else { return nil }
    currentIndex = index
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
  }
  
  // MARK: - Private Methods
  
  private func shouldCoalesce(with newVersion: Version) -> Bool {
    guard let lastEdit = lastEditTime,
          let current = currentVersion else { return false }
    
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