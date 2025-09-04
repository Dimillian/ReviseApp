import SwiftUI
import UIKit

struct EditorView: View {
  private let documentStore: DocumentStore
  private let document: Document

  @State private var text = ""
  @State private var timelineState: TimelineViewState = .visible
  // Editor zoom state (1.0 = normal). Pinch-out reduces this to reveal the graph behind.
  @State private var editorScale: CGFloat = 1.0
  @State private var baseScale: CGFloat = 1.0
  @State private var isGraphVisible: Bool = false
  @State private var didHapticReveal: Bool = false

  @State private var editorController: EditorController
  @State private var versionStore: VersionStore
  @State private var isFirstLaunch = true

  @State private var isMenuLoading = false

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
      // Foreground: editor content scaled with pinch
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
        .opacity(editorScale)  // fade out timeline slightly as we zoom out
      }
      .scaleEffect(editorScale)
      .animation(.smooth(duration: 0.2), value: editorScale)
      .opacity(isGraphVisible ? 0 : 1)
      .allowsHitTesting(!isGraphVisible)

      // Overlay: Branch graph (only when visible) above editor to ensure interactions
      if isGraphVisible {
        BranchGraphView(
          versionStore: versionStore,
          onSelectBranch: { name in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            versionStore.switchBranch(to: name)
            if let latest = versionStore.currentVersion
              ?? versionStore.latestVersion(forBranch: name)
            {
              editorController.restoreVersion(latest)
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
              editorScale = 1.0
              baseScale = 1.0
              isGraphVisible = false
            }
          }
        )
        .padding(.top, 32)
        .transition(.opacity.combined(with: .scale))
        .zIndex(1)
      }
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
    .simultaneousGesture(magnificationGesture)
    .background(Color.background.edgesIgnoringSafeArea(.all))
    .toolbar {
      ToolbarItem(placement: .title) {
        titleView
      }
      ToolbarItem(placement: .subtitle) {
        subtitleView
      }
      ToolbarItem(placement: .topBarTrailing) {
        menuButton
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
      .allowsHitTesting(true)
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
      Text("  •  ")
      Text("\(versionStore.currentBranch)")
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

  private var menuButton: some View {
    Menu {
      Button("New Branch", systemImage: "plus") {
        Task {
          isMenuLoading = true
          await editorController.createNewBranch()
          isMenuLoading = false
        }
      }
      Menu {
        ForEach(versionStore.branches.map { $0.key }, id: \.self) { branch in
          Button(branch, systemImage: "branch") {
            editorController.switchBranch(to: branch)
          }
        }
      } label: {
        Label("Branches", systemImage: "branch")
      }
      Button("Undo", systemImage: "arrow.uturn.left") {
        editorController.undo()
      }
      Button("Redo", systemImage: "arrow.uturn.right") {
        editorController.redo()
      }
      Divider()
      ShareLink("Share", item: text)
    } label: {
      if isMenuLoading {
        ProgressView()
      } else {
        Image(systemName: "ellipsis")
      }
    }
  }
}

extension EditorView {
  private var magnificationGesture: some Gesture {
    MagnificationGesture()
      .onChanged { scale in
        // Inverse: pinch-in (scale < 1) reveals graph by shrinking editor
        let target = (baseScale * scale).clamped(to: 0.6...1.0)
        editorScale = target
        // Reveal the graph once we pass a threshold
        let revealThreshold: CGFloat = 0.92
        let willReveal = target < revealThreshold
        withAnimation(.smooth(duration: 0.15)) { isGraphVisible = willReveal }
        // Haptic on reveal threshold cross
        if willReveal && !didHapticReveal {
          UIImpactFeedbackGenerator(style: .soft).impactOccurred()
          didHapticReveal = true
        }
      }
      .onEnded { scale in
        // Snap to either fully open or closed for a clean end state
        let openThreshold: CGFloat = 0.85
        if editorScale < openThreshold {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            editorScale = 0.75
            isGraphVisible = true
          }
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          baseScale = editorScale
        } else {
          withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            editorScale = 1.0
            isGraphVisible = false
          }
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          baseScale = 1.0
        }
        didHapticReveal = false
      }
  }
}
