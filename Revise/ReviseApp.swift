import FoundationModels
import SwiftData
import SwiftUI

@main
struct ReviseApp: App {
  @State private var path: NavigationPath = NavigationPath()

  var body: some Scene {
    WindowGroup {
      if !SystemLanguageModel.default.isAvailable {
        UnavailableView()
      } else {
        NavigationStack(path: $path) {
          DocumentsListView(path: $path)
            .navigationDestination(for: Document.self) { document in
              EditorView(document: document)
            }
        }
      }
    }
    .modelContainer(for: [Document.self, Branch.self, Version.self])
  }
}
