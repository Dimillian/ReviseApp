import SwiftUI

struct EditorView: View {
  @State private var text = "Hello World"

  @State private var editorController: EditorController
  @State private var versionStore: VersionStore
  @State private var isTimelineVisible = true

  private let timelineWidth: CGFloat = 44
  private let textPadding: CGFloat = 24

  init() {
    let versionStore = VersionStore()
    self.versionStore = versionStore
    self.editorController = EditorController(versionStore: versionStore)
  }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .leading) {
        ScrollView(.vertical) {
          MagneticTextEditor(text: $text, editorController: editorController)
            .padding(.trailing, textPadding)
            .padding(.leading, (isTimelineVisible ? timelineWidth : 0) + textPadding)
            .animation(.bouncy, value: isTimelineVisible)
        }
        .scrollContentBackground(.hidden)

        VersionTimelineView(
          versionStore: versionStore,
          onVersionSelected: { version in
            editorController.restoreVersion(version)
          }
        )
        .frame(width: timelineWidth)
        .opacity(isTimelineVisible ? 1 : 0)
        .offset(x: isTimelineVisible ? 0 : -timelineWidth)
        .animation(.bouncy, value: isTimelineVisible)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 2)
          .onEnded { value in
            let horizontalTranslation = value.translation.width
            let isDraggingRight = horizontalTranslation > 0
            let newTimelineVisibility = isDraggingRight
            isTimelineVisible = newTimelineVisibility
          }
      )
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
