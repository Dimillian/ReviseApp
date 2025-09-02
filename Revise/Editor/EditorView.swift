import SwiftUI

struct EditorView: View {
  @State private var text = "Hello World"

  @State private var editorController: EditorController
  @State private var versionStore: VersionStore

  init() {
    let versionStore = VersionStore()
    self.versionStore = versionStore
    self.editorController = EditorController(versionStore: versionStore)
  }

  var body: some View {
    NavigationStack {
      HStack(spacing: 24) {
        VersionTimelineView(
          versionStore: versionStore,
          onVersionSelected: { version in
            editorController.restoreVersion(version)
          }
        )
        .frame(width: 44)
        MagneticTextEditor(text: $text, editorController: editorController)
          .padding(.trailing, 24)
      }
      .background(Color.background)
      .toolbar {
        ToolbarItem(placement: .title) {
          Text("\(editorController.wordsCount) words | \(versionStore.versions.count) versions")
            .font(.inter(size: 12, relativeTo: .caption))
            .foregroundStyle(.textSecondary)
        }
      }
      .scrollEdgeEffectStyle(.hard, for: .top)
    }
  }
}
