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
  let versions: [Version]
  let currentIndex: Int
  let onVersionSelected: (Version) -> Void

  @State private var hoveredIndex: Int?
  @State private var isDragging = false

  @Binding var timelineState: TimelineViewState

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .trailing) {
        ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
          VersionNode(
            version: version,
            isActive: index == currentIndex,
            isHovered: hoveredIndex == index,
            position: nodePosition(for: index, in: geometry.size.height),
            timelineState: $timelineState
          )
          .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              onVersionSelected(version)
            }
          }
          .onHover { isHovered in
            hoveredIndex = isHovered ? index : nil
          }
        }

        Color.clear
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                isDragging = true
                let index = indexForPosition(value.location.y, in: geometry.size.height)
                if index != currentIndex && index < versions.count {
                  let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                  impactFeedback.impactOccurred()
                  onVersionSelected(versions[index])
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
    guard !versions.isEmpty else { return 0 }
    let usableHeight = height - 60
    let step = usableHeight / max(1, CGFloat(versions.count - 1))
    return 20 + (CGFloat(index) * step)
  }

  private func indexForPosition(_ position: CGFloat, in height: CGFloat) -> Int {
    guard !versions.isEmpty else { return 0 }
    let usableHeight = height - 60
    let step = usableHeight / max(1, CGFloat(versions.count - 1))
    let index = Int((position - 20) / step)
    return max(0, min(versions.count - 1, index))
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
    ZStack {
      Circle()
        .fill(nodeColor)
        .frame(width: nodeSize, height: nodeSize)
        .shadow(color: Color.successGold.opacity(0.5), radius: isActive ? 2 : 0, x: 0, y: 0)
        .scaleEffect(isActive ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .position(
          x: timelineState == .expanded ? timelineState.width / 4 : timelineState.width / 2,
          y: position)

      if timelineState == .expanded {
        VStack(alignment: .leading, spacing: 2) {
          Text(version.timestamp, style: .time)
            .font(.inter(size: 10, relativeTo: .caption2))
          Text("\(version.wordCount) words")
            .font(.inter(size: 10, relativeTo: .caption2))
        }
        .foregroundColor(.textSecondary)
        .padding(.horizontal, 4)
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
        .position(x: timelineState.width / 2 + 8, y: position)
      }
    }
  }
}
