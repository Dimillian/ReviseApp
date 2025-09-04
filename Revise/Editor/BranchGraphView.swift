import SwiftUI

struct BranchGraphView: View {
  let versionStore: VersionStore
  let onSelectBranch: (String) -> Void

  // Zoom state
  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0

  // Layout constants (scaled down for denser map)
  private let nodeSize = CGSize(width: 180, height: 110)
  private let levelSpacing: CGFloat = 260
  private let rowSpacing: CGFloat = 150
  private let portGap: CGFloat = 10

  var body: some View {
    let graph = versionStore.branchGraph()
    let positions = computePositions(graph.nodes)

    ScrollView([.horizontal, .vertical]) {
      ZStack {
        // Edge curves (under nodes)
        Canvas { ctx, size in
          let strokeColor = Color.textSecondary.opacity(0.7)
          let arrowLength: CGFloat = 16
          for edge in graph.edges {
            if let from = positions[edge.from], let to = positions[edge.to] {
              let path = edgePath(from: from, to: to, shorten: arrowLength)
              ctx.stroke(path, with: .color(strokeColor), lineWidth: 1.5)
            }
          }
        }
        .allowsHitTesting(false)

        // Nodes
        ForEach(graph.nodes) { node in
          let pos = positions[node.id] ?? .zero
          BranchNodeTile(
            title: node.id == Branch.main ? "Main" : node.id,
            preview: versionStore.previewAttributed(forBranch: node.id)
          ) {
            onSelectBranch(node.id)
          }
          .position(pos)
        }

        // Arrowheads (over nodes for visibility)
        Canvas { ctx, size in
          let strokeColor = Color.successGold.opacity(0.5)
          let arrowLength: CGFloat = 16
          let arrowWidth: CGFloat = 10
          for edge in graph.edges {
            if let to = positions[edge.to] {
              let tip = CGPoint(x: to.x - nodeSize.width / 2 - portGap, y: to.y)
              var arrow = Path()
              let baseX = tip.x - arrowLength
              arrow.move(to: tip)
              arrow.addLine(to: CGPoint(x: baseX, y: tip.y - arrowWidth / 2))
              arrow.addLine(to: CGPoint(x: baseX, y: tip.y + arrowWidth / 2))
              arrow.closeSubpath()
              ctx.fill(arrow, with: .color(strokeColor))
            }
          }
        }
        .allowsHitTesting(false)
      }
      .frame(
        width: contentSize(for: graph.nodes).width, height: contentSize(for: graph.nodes).height
      )
      .scaleEffect(scale)
      .gesture(
        MagnificationGesture()
          .onChanged { value in
            scale = (lastScale * value).clamped(to: 0.5...2.0)
          }
          .onEnded { value in
            lastScale = (lastScale * value).clamped(to: 0.5...2.0)
          }
      )
      .padding(40)
    }
  }

  private func computePositions(_ nodes: [VersionStore.BranchNode]) -> [String: CGPoint] {
    var columns: [Int: [VersionStore.BranchNode]] = [:]
    for n in nodes { columns[n.level, default: []].append(n) }
    for level in columns.keys { columns[level]?.sort { $0.order < $1.order } }

    var positions: [String: CGPoint] = [:]
    for (level, list) in columns {
      for (idx, node) in list.enumerated() {
        let x = CGFloat(level) * levelSpacing + nodeSize.width / 2
        let y = CGFloat(idx) * rowSpacing + nodeSize.height / 2
        positions[node.id] = CGPoint(x: x, y: y)
      }
    }
    return positions
  }

  private func contentSize(for nodes: [VersionStore.BranchNode]) -> CGSize {
    let maxLevel = nodes.map { $0.level }.max() ?? 0
    var rowsPerLevel: [Int: Int] = [:]
    for n in nodes { rowsPerLevel[n.level, default: 0] += 1 }
    let maxRows = rowsPerLevel.values.max() ?? 1
    let width = CGFloat(maxLevel + 1) * levelSpacing + nodeSize.width
    let height = CGFloat(maxRows) * rowSpacing + nodeSize.height
    return CGSize(width: width, height: height)
  }

  private func edgePath(from: CGPoint, to: CGPoint, shorten: CGFloat = 0) -> Path {
    var p = Path()
    let start = CGPoint(x: from.x + nodeSize.width / 2 + portGap, y: from.y)
    let end = CGPoint(x: to.x - nodeSize.width / 2 - portGap, y: to.y)
    let endMinus = CGPoint(x: end.x - shorten, y: end.y)
    let midX = (start.x + end.x) / 2
    p.move(to: start)
    p.addCurve(
      to: endMinus,
      control1: CGPoint(x: midX, y: start.y),
      control2: CGPoint(x: midX, y: end.y))
    return p
  }
}

private struct BranchNodeTile: View {
  let title: String
  let preview: AttributedString
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.inter(size: 10, relativeTo: .caption))
          .foregroundStyle(.textSecondary)
        Text(preview)
          .font(.literata(size: 12, relativeTo: .body))
          .foregroundStyle(.textPrimary)
          .lineLimit(5)
          .multilineTextAlignment(.leading)
      }
      .frame(width: 180, height: 110, alignment: .topLeading)
      .padding(12)
      .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }
}

extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
