import SwiftUI

struct EditorView: View {
  @State private var text = "Hello World"
  @State private var editorController = EditorController()

  var body: some View {
    NavigationStack {
      MagneticTextEditor(text: $text, editorController: editorController)
        .background(Color.background)
        .toolbar {
          ToolbarItem(placement: .title) {
            Text("\(editorController.wordsCount) words")
              .font(.inter(size: 12, relativeTo: .caption))
              .foregroundStyle(.textSecondary)
          }
        }
        .scrollEdgeEffectStyle(.hard, for: .top)
    }
  }
}
