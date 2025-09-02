import SwiftUI

struct EditorView: View {
  private let document: Document

  @State private var text = ""

  @State private var editorController: EditorController
  @State private var versionStore: VersionStore
  @State private var isTimelineVisible = true
  @State private var isFirstLaunch = true

  private let timelineWidth: CGFloat = 44
  private let textPadding: CGFloat = 24

  init(document: Document) {
    self.document = document
    let versionStore = VersionStore(document: document)
    let editorController = EditorController(versionStore: versionStore)
    _versionStore = State(initialValue: versionStore)
    _editorController = State(initialValue: editorController)
  }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .leading) {
        ScrollView(.vertical) {
          ZStack(alignment: .topLeading) {
            if text.isEmpty {
              welcomeView
            }
            textEditor
          }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)

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
        ToolbarItem(placement: .subtitle) {
          subtitleView
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(document.title, item: text)
        }
      }
      .onAppear {
        if text.isEmpty {
          editorController.generateInitialTitle()
        }
      }
      .scrollEdgeEffectStyle(.soft, for: .top)
      .onChange(of: text) {
        if !text.isEmpty {
          isFirstLaunch = false
        }
      }
    }
  }

  private var textEditor: some View {
    MagneticTextEditor(text: $text, editorController: editorController)
      .padding(.trailing, textPadding)
      .padding(.leading, (isTimelineVisible ? timelineWidth : 0) + textPadding)
      .animation(.bouncy, value: isTimelineVisible)
  }

  private var titleView: some View {
    Text(document.title)
      .font(.inter(size: 18, relativeTo: .body))
      .foregroundStyle(.textPrimary)
      .contentTransition(.interpolate)
      .animation(.bouncy, value: document.title)
      .onTapGesture {
        isTimelineVisible.toggle()
      }
  }

  private var subtitleView: some View {
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
    .onTapGesture {
      isTimelineVisible.toggle()
    }
  }

  @ViewBuilder
  private var welcomeView: some View {
    if text.isEmpty && isFirstLaunch {
      Text(
        "  Welcome to Redraft\n\nEvery edit creates a new version you can instantly revisit.\n\nType anything to get started."
      )
      .font(.literata(size: 26, relativeTo: .body))
      .foregroundStyle(.textSecondary)
      .padding(.leading, (isTimelineVisible ? timelineWidth : 0) + textPadding)
      .padding(.trailing, textPadding)
    }
  }
}
