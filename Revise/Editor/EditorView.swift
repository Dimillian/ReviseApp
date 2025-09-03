import SwiftUI

struct EditorView: View {
  private let documentStore: DocumentStore
  private let document: Document

  @State private var text = ""
  @State private var timelineState: TimelineViewState = .visible

  @State private var editorController: EditorController
  @State private var versionStore: VersionStore
  @State private var isFirstLaunch = true

  private let textPadding: CGFloat = 24

  init(document: Document, documentStore: DocumentStore) {
    self.document = document
    self.documentStore = documentStore
    let versionStore = VersionStore(document: document, documentStore: documentStore)
    let editorController = EditorController(versionStore: versionStore)
    _versionStore = State(initialValue: versionStore)
    _editorController = State(initialValue: editorController)
  }

  var body: some View {
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
        },
        timelineState: $timelineState
      )
    }
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 2)
        .onEnded { value in
          let horizontalTranslation = value.translation.width
          let isDraggingRight = horizontalTranslation > 0
          if isDraggingRight {
            if timelineState == .visible {
              timelineState = .expanded
            } else {
              timelineState = .visible
            }
          } else {
            timelineState = .hidden
          }
        }
    )
    .background(Color.background.edgesIgnoringSafeArea(.all))
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
    .scrollEdgeEffectStyle(.soft, for: .top)
    .onChange(of: text) {
      if !text.isEmpty {
        isFirstLaunch = false
      }
    }
    .onAppear {
      if let latestVersion = versionStore.versions.last {
        editorController.restoreVersion(latestVersion)
        isFirstLaunch = false
      }
    }
  }

  private var textEditor: some View {
    MagneticTextEditor(text: $text, editorController: editorController)
      .padding(.trailing, textPadding)
      .padding(.leading, timelineState == .hidden ? textPadding : timelineState.width + textPadding)
      .animation(.bouncy, value: timelineState)
  }

  private var titleView: some View {
    Text(document.title)
      .font(.inter(size: 18, relativeTo: .body))
      .foregroundStyle(.textPrimary)
      .contentTransition(.interpolate)
      .animation(.bouncy, value: document.title)
      .onTapGesture {
        timelineState = timelineState.toggle()
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
      timelineState = timelineState.toggle()
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
      .padding(.leading, timelineState == .hidden ? textPadding : timelineState.width + textPadding)
      .padding(.trailing, textPadding)
    }
  }
}
