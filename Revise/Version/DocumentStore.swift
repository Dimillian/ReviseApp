import Foundation
import SwiftUI

@Observable
final class DocumentStore {
  private(set) var documents: [Document] = []

  // Shared directory utilities
  static let fileManager = FileManager.default

  static var documentsDirectory: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
  }

  static var versionsDirectory: URL {
    documentsDirectory.appendingPathComponent("Versions")
  }

  static func documentDirectory(for documentId: String) -> URL {
    versionsDirectory.appendingPathComponent(documentId)
  }

  static func documentMetadataFile(for documentId: String) -> URL {
    documentDirectory(for: documentId).appendingPathComponent("document.json")
  }

  static func versionsFile(for documentId: String) -> URL {
    documentDirectory(for: documentId).appendingPathComponent("versions.json")
  }

  // JSON coding
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init() {
    setupStorage()
    loadDocuments()
  }

  private func setupStorage() {
    // Create base directories if they don't exist
    try? Self.fileManager.createDirectory(
      at: Self.versionsDirectory, withIntermediateDirectories: true)
  }

  func loadDocuments() {
    guard
      let contents = try? Self.fileManager.contentsOfDirectory(
        at: Self.versionsDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
      )
    else {
      documents = []
      return
    }

    documents = contents.compactMap { url in
      var isDirectory: ObjCBool = false
      if Self.fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        // Try to load document metadata
        let documentFile = Self.documentMetadataFile(for: url.lastPathComponent)
        if let data = try? Data(contentsOf: documentFile),
          let document = try? decoder.decode(Document.self, from: data)
        {
          return document
        }
      }
      return nil
    }
    .sorted { $0.lastEdited > $1.lastEdited }
  }

  func createDocument(withTitle title: String? = nil) -> Document {
    let document = Document(id: UUID().uuidString)
    document.title = title ?? "Untitled"

    // Create directory for this document
    let documentDir = Self.documentDirectory(for: document.id)
    try? Self.fileManager.createDirectory(at: documentDir, withIntermediateDirectories: true)

    // Save initial metadata
    saveDocument(document)

    // Add to list
    documents.append(document)
    documents.sort { $0.lastEdited > $1.lastEdited }

    return document
  }

  func deleteDocument(_ document: Document) {
    // Remove from list
    documents.removeAll { $0.id == document.id }

    // Delete directory
    let documentDir = Self.documentDirectory(for: document.id)
    try? Self.fileManager.removeItem(at: documentDir)
  }

  func renameDocument(_ document: Document, to newTitle: String) {
    document.title = newTitle
    saveDocument(document)

    // Re-sort documents
    documents.sort { $0.title < $1.title }
  }

  func saveDocument(_ document: Document) {
    let documentFile = Self.documentMetadataFile(for: document.id)

    do {
      let data = try encoder.encode(document)
      try data.write(to: documentFile)
    } catch {
      print("Failed to save document metadata: \(error)")
    }

    Task { @MainActor in
      documents.sort { $0.lastEdited > $1.lastEdited }
    }
  }

  func documentExists(withId id: String) -> Bool {
    let documentDir = Self.documentDirectory(for: id)
    var isDirectory: ObjCBool = false
    return Self.fileManager.fileExists(atPath: documentDir.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  func getDocument(withId id: String) -> Document? {
    documents.first { $0.id == id }
  }
}
