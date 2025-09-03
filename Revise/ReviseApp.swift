import SwiftUI

@main
struct ReviseApp: App {
  @State private var documentStore = DocumentStore()

  @State private var path: NavigationPath = NavigationPath()

  var body: some Scene {
    WindowGroup {
      NavigationStack(path: $path) {
        DocumentsListView(path: $path)
          .navigationDestination(for: Document.self) { document in
            EditorView(document: document, documentStore: documentStore)
          }
      }
      .environment(documentStore)
    }
  }
}
