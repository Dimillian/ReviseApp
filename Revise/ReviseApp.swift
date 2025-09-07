import SwiftUI
import SwiftData

@main
struct ReviseApp: App {
  @State private var path: NavigationPath = NavigationPath()
  
  var body: some Scene {
    WindowGroup {
      NavigationStack(path: $path) {
        DocumentsListView(path: $path)
          .navigationDestination(for: Document.self) { document in
            EditorView(document: document)
          }
      }
    }
    .modelContainer(for: [Document.self, Branch.self, Version.self])
  }
}