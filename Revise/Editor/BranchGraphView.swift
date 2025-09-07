import SwiftUI
import UIKit

struct BranchGraphView: View {
  let branches: [Branch]
  let currentBranchId: String
  let versionController: VersionController
  let onSelectBranch: (String) -> Void
  
  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var didHapticZoom = false
  
  private let nodeSize = CGSize(width: 180, height: 110)
  private let levelSpacing: CGFloat = 260
  private let rowSpacing: CGFloat = 150
  private let portGap: CGFloat = 10
  
  var body: some View {
    let graph = versionController.branchGraph()
    let positions = computePositions(graph.nodes)
    
    ScrollView([.horizontal, .vertical]) {
      ZStack {
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
        
        ForEach(graph.nodes) { node in
          let pos = positions[node.id] ?? .zero
          let branch = branches.first { $0.id == node.id }
          let previewAttr = branch != nil ? 
            versionController.previewAttributedString(for: branch!, withDiff: true) :
            AttributedString(node.preview)
          
          BranchNodeTile(
            title: node.id == Branch.main ? "Main" : node.name,
            preview: previewAttr,
            isCurrentBranch: node.isCurrentBranch,
            hasAI: node.hasAI,
            hasSynonym: node.hasSynonym
          ) {
            onSelectBranch(node.id)
          }
          .position(pos)
        }
        
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
            if !didHapticZoom {
              UIImpactFeedbackGenerator(style: .soft).impactOccurred()
              didHapticZoom = true
            }
            scale = (lastScale * value).clamped(to: 0.5...2.0)
          }
          .onEnded { value in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            lastScale = (lastScale * value).clamped(to: 0.5...2.0)
            didHapticZoom = false
          }
      )
      .padding(40)
    }
  }
  
  private func computePositions(_ nodes: [VersionController.BranchNode]) -> [String: CGPoint] {
    var levelMap: [String: Int] = [:]
    var childrenMap: [String: [String]] = [:]
    
    for node in nodes {
      if let parentId = node.parentId {
        childrenMap[parentId, default: []].append(node.id)
      }
    }
    
    func assignLevel(_ nodeId: String, level: Int) {
      levelMap[nodeId] = level
      for child in childrenMap[nodeId] ?? [] {
        assignLevel(child, level: level + 1)
      }
    }
    
    if let mainNode = nodes.first(where: { $0.parentId == nil || $0.id == Branch.main }) {
      assignLevel(mainNode.id, level: 0)
    }
    
    var columns: [Int: [String]] = [:]
    for node in nodes {
      let level = levelMap[node.id] ?? 0
      columns[level, default: []].append(node.id)
    }
    
    var positions: [String: CGPoint] = [:]
    for (level, nodeIds) in columns {
      for (idx, nodeId) in nodeIds.enumerated() {
        let x = CGFloat(level) * levelSpacing + nodeSize.width / 2
        let y = CGFloat(idx) * rowSpacing + nodeSize.height / 2
        positions[nodeId] = CGPoint(x: x, y: y)
      }
    }
    return positions
  }
  
  private func contentSize(for nodes: [VersionController.BranchNode]) -> CGSize {
    var maxLevel = 0
    var rowsPerLevel: [Int: Int] = [:]
    
    var levelMap: [String: Int] = [:]
    var childrenMap: [String: [String]] = [:]
    
    for node in nodes {
      if let parentId = node.parentId {
        childrenMap[parentId, default: []].append(node.id)
      }
    }
    
    func assignLevel(_ nodeId: String, level: Int) {
      levelMap[nodeId] = level
      maxLevel = max(maxLevel, level)
      rowsPerLevel[level, default: 0] += 1
      for child in childrenMap[nodeId] ?? [] {
        assignLevel(child, level: level + 1)
      }
    }
    
    if let mainNode = nodes.first(where: { $0.parentId == nil || $0.id == Branch.main }) {
      assignLevel(mainNode.id, level: 0)
    }
    
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
  let isCurrentBranch: Bool
  let hasAI: Bool
  let hasSynonym: Bool
  let onTap: () -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.inter(size: 10, relativeTo: .caption))
          .foregroundStyle(isCurrentBranch ? .textPrimary : .textSecondary)
        
        Spacer()
        
        if hasAI {
          Image(systemName: "sparkles")
            .font(.system(size: 8))
            .foregroundColor(.aiPurple)
        }
        if hasSynonym {
          Image(systemName: "text.badge.star")
            .font(.system(size: 8))
            .foregroundColor(.aiPurple)
        }
      }
      
      Text(preview)
        .font(.literata(size: 12, relativeTo: .body))
        .foregroundStyle(.textPrimary)
        .lineLimit(5)
        .multilineTextAlignment(.leading)
    }
    .frame(width: 180, height: 110, alignment: .topLeading)
    .padding(12)
    .glassEffect(
      .regular,
      in: .rect(cornerRadius: 12)
    )
    .border(
      isCurrentBranch ? Color.successGold.opacity(0.5) : Color.clear,
      width: 2
    )
    .contentShape(Rectangle())
    .onTapGesture {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      onTap()
    }
  }
}

extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    return min(max(self, limits.lowerBound), limits.upperBound)
  }
}