import Foundation

// MARK: - Branch Model
struct Branch: Identifiable, Equatable, Codable {
  // Centralized default branch name
  static let main = "main"

  // Branch identifier (e.g. "main", "idea-1")
  let id: String
  // Reference branch this branch diverged from ("main" for root)
  let ref: String
  // The version ID in the reference branch where this branch started
  let baseVersionId: String?
  let createdAt: Date

  init(id: String, ref: String, baseVersionId: String?) {
    self.id = id
    self.ref = ref
    self.baseVersionId = baseVersionId
    self.createdAt = Date()
  }
}
