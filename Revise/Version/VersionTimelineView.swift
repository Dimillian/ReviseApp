import SwiftUI

struct VersionTimelineView: View {
  let versionStore: VersionStore
  let onVersionSelected: (Version) -> Void

  @State private var hoveredIndex: Int?
  @State private var isDragging = false

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .trailing) {
        // Version nodes
        ForEach(Array(versionStore.versions.enumerated()), id: \.element.id) { index, version in
          VersionNode(
            version: version,
            isActive: index == versionStore.currentIndex,
            isHovered: hoveredIndex == index,
            position: nodePosition(for: index, in: geometry.size.height)
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
      .glassEffect(.regular.tint(Color.surface).interactive())
      .frame(width: 44)
      .padding(.horizontal, 8)
      .padding(.vertical, 8)
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

  var nodeColor: Color {
    switch version.changeType {
    case .synonym:
      return Color.successGold
    case .ai:
      return Color.aiPurple
    case .initial:
      return Color.gray
    default:
      return Color.treeLines
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
    Circle()
      .fill(nodeColor)
      .frame(width: nodeSize, height: nodeSize)
      .overlay(
        Circle()
          .stroke(Color.surface, lineWidth: isActive ? 1 : 0)
      )
      .scaleEffect(isActive ? 1.2 : (isHovered ? 1.1 : 1.0))
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
      .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
      .position(x: 22, y: position)
  }
}

// Helper color extension
extension Color {
  init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a: UInt64
    let r: UInt64
    let g: UInt64
    let b: UInt64
    switch hex.count {
    case 3:  // RGB (12-bit)
      (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6:  // RGB (24-bit)
      (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:  // ARGB (32-bit)
      (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
      (a, r, g, b) = (255, 0, 0, 0)
    }
    self.init(
      .sRGB,
      red: Double(r) / 255,
      green: Double(g) / 255,
      blue: Double(b) / 255,
      opacity: Double(a) / 255
    )
  }
}
