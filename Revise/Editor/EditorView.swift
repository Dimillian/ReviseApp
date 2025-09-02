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
      ZStack(alignment: .leading) {
        VersionTimelineView(
          versionStore: versionStore,
          onVersionSelected: { version in
            editorController.restoreVersion(version)
          }
        )
        .frame(width: 44)

        ScrollView(.vertical) {
          MagneticTextEditor(text: $text, editorController: editorController)
            .padding(.trailing, 24)
            .padding(.leading, 62)
        }
        .scrollContentBackground(.hidden)
      }
      .background(Color.background)
      .toolbar {
        ToolbarItem(placement: .title) {
          titleView
        }
      }
      .scrollEdgeEffectStyle(.soft, for: .top)
    }
  }

  private var titleView: some View {
    HStack(spacing: 0) {
      Text("\(editorController.wordsCount)")
        .contentTransition(.numericText(value: Double(editorController.wordsCount)))
        .animation(.bouncy, value: editorController.wordsCount)
      Text(editorController.wordsCount == 1 ? " word" : " words")
      Text("  •  ")
      Text("\(versionStore.versions.count)")
        .contentTransition(.numericText(value: Double(versionStore.versions.count)))
        .animation(.bouncy, value: versionStore.versions.count)
      Text(versionStore.versions.count == 1 ? " version" : " versions")
    }
    .font(.inter(size: 12, relativeTo: .caption))
    .foregroundStyle(.textSecondary)
  }
}
