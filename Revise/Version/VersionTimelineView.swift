import SwiftUI

enum TimelineViewState {
  case hidden, visible, expanded

  var width: CGFloat {
    switch self {
    case .hidden, .visible:
      return 44
    case .expanded:
      return 100
    }
  }

  func toggle() -> TimelineViewState {
    switch self {
    case .hidden:
      return .visible
    case .visible:
      return .expanded
    case .expanded:
      return .hidden
    }
  }
}

struct VersionTimelineView: View {
  let versionStore: VersionStore
  let onVersionSelected: (Version) -> Void

  @State private var hoveredIndex: Int?
  @State private var isDragging = false

  @Binding var timelineState: TimelineViewState

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .trailing) {
        // Version nodes
        ForEach(Array(versionStore.versions.enumerated()), id: \.element.id) { index, version in
          VersionNode(
            version: version,
            isActive: index == versionStore.currentIndex,
            isHovered: hoveredIndex == index,
            position: nodePosition(for: index, in: geometry.size.height),
            timelineState: $timelineState
          )
          .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              _ = versionStore.navigateToVersion(at: index)
              if let version = versionStore.currentVersion {
                onVersionSelected(version)
              }
            }
          }
          .onHover { isHovered in
            hoveredIndex = isHovered ? index : nil
          }
        }

        // Drag gesture for scrubbing
        Color.clear
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                isDragging = true
                let index = indexForPosition(value.location.y, in: geometry.size.height)
                if index != versionStore.currentIndex {
                  // Haptic feedback
                  let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                  impactFeedback.impactOccurred()

                  _ = versionStore.navigateToVersion(at: index)
                  if let version = versionStore.currentVersion {
                    onVersionSelected(version)
                  }
                }
              }
              .onEnded { _ in
                isDragging = false
              }
          )
      }
      .glassEffect(
        .regular.tint(Color.surface).interactive(),
        in: .rect(cornerRadius: 22)
      )
      .frame(width: timelineState.width)
      .padding(.leading, 16)
      .padding(.vertical, 8)
      .opacity(timelineState == .hidden ? 0 : 1)
      .offset(x: timelineState == .hidden ? -timelineState.width : 0)
      .animation(.bouncy, value: timelineState)
    }
  }

  private func nodePosition(for index: Int, in height: CGFloat) -> CGFloat {
    guard !versionStore.versions.isEmpty else { return 0 }
    let usableHeight = height - 60  // Account for padding
    let step = usableHeight / max(1, CGFloat(versionStore.versions.count - 1))
    return 20 + (CGFloat(index) * step)
  }

  private func indexForPosition(_ position: CGFloat, in height: CGFloat) -> Int {
    guard !versionStore.versions.isEmpty else { return 0 }
    let usableHeight = height - 60
    let step = usableHeight / max(1, CGFloat(versionStore.versions.count - 1))
    let index = Int((position - 20) / step)
    return max(0, min(versionStore.versions.count - 1, index))
  }
}

struct VersionNode: View {
  let version: Version
  let isActive: Bool
  let isHovered: Bool
  let position: CGFloat

  @Binding var timelineState: TimelineViewState

  var nodeColor: Color {
    switch version.changeType {
    case .synonym:
      return Color.aiPurple
    case .ai:
      return Color.aiPurple
    default:
      return Color.gray
    }
  }

  var nodeSize: CGFloat {
    if isActive { return 12 }
    if isHovered { return 10 }

    switch version.changeType {
    case .synonym, .ai:
      return 8
    default:
      return 6
    }
  }

  var body: some View {
    HStack {
      Circle()
        .fill(nodeColor)
        .frame(width: nodeSize, height: nodeSize)
        .shadow(color: Color.successGold.opacity(0.5), radius: isActive ? 2 : 0, x: 0, y: 0)

      if timelineState == .expanded {
        Text(version.timestamp, format: .relative(presentation: .numeric, unitsStyle: .narrow))
          .font(.inter(size: 12, relativeTo: .callout))
          .foregroundColor(.textSecondary)
          .lineLimit(1)

        Spacer()
      }
    }
    .scaleEffect(isActive ? 1.2 : (isHovered ? 1.1 : 1.0))
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
    .position(x: timelineState == .expanded ? 70 : 22, y: position)
  }
}
