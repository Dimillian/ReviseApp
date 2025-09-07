import SwiftData
import SwiftUI
import UIKit

struct EditorView: View {
  let document: Document

  @Environment(\.modelContext) private var modelContext
  @Query private var versions: [Version]
  @Query private var branches: [Branch]

  @State private var text = ""
  @State private var timelineState: TimelineViewState = .visible
  @State private var editorScale: CGFloat = 1.0
  @State private var baseScale: CGFloat = 1.0
  @State private var isGraphVisible: Bool = false
  @State private var didHapticReveal: Bool = false

  @State private var editorController = EditorController()
  @State private var versionController: VersionController?
  @State private var isFirstLaunch = true

  @State private var isMenuLoading = false

  private let textPadding: CGFloat = 24

  init(document: Document) {
    self.document = document

    let documentId = document.id
    let currentBranchId = document.currentBranch?.id ?? Branch.main

    _versions = Query(
      filter: #Predicate<Version> { version in
        version.branch.document.id == documentId && version.branch.id == currentBranchId
      },
      sort: \Version.timestamp
    )

    _branches = Query(
      filter: #Predicate<Branch> { branch in
        branch.document.id == documentId
      },
      sort: \Branch.createdAt
    )

  }

  var body: some View {
    ZStack(alignment: .leading) {
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
          versions: versions,
          currentIndex: versionController?.currentIndex ?? -1,
          onVersionSelected: { version in
            if let restoredVersion = versionController?.navigateToVersion(version) {
              editorController.restoreVersion(restoredVersion)
            }
          },
          timelineState: $timelineState
        )
        .opacity(editorScale)
      }
      .scaleEffect(editorScale)
      .animation(.smooth(duration: 0.2), value: editorScale)
      .opacity(isGraphVisible ? 0 : 1)
      .allowsHitTesting(!isGraphVisible)

      if isGraphVisible, let controller = versionController {
        BranchGraphView(
          branches: branches,
          currentBranchId: document.currentBranch?.id ?? Branch.main,
          versionController: controller,
          onSelectBranch: { branchId in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            controller.switchToBranch(named: branchId)
            if let latest = controller.currentVersion {
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
      let controller = VersionController(document: document, modelContext: modelContext)
      versionController = controller
      editorController.versionController = controller
      if let latestVersion = versions.last {
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
      Text("\(versions.count)")
        .contentTransition(.numericText(value: Double(versions.count)))
        .animation(.bouncy, value: versions.count)
      Text(versions.count == 1 ? " version" : " versions")
      Text("  •  ")
      Text("\(document.currentBranch?.name ?? Branch.main)")
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
        ForEach(branches, id: \.id) { branch in
          Button(branch.id, systemImage: "branch") {
            editorController.switchBranch(to: branch.id)
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
        let target = (baseScale * scale).clamped(to: 0.6...1.0)
        editorScale = target
        let revealThreshold: CGFloat = 0.92
        let willReveal = target < revealThreshold
        withAnimation(.smooth(duration: 0.15)) { isGraphVisible = willReveal }
        if willReveal && !didHapticReveal {
          UIImpactFeedbackGenerator(style: .soft).impactOccurred()
          didHapticReveal = true
        }
      }
      .onEnded { scale in
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
