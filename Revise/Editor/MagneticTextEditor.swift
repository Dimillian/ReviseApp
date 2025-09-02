import SwiftUI
import UIKit

// Custom UITextView that can suppress the default menu
class MagneticTextView: UITextView {
  var shouldSuppressMenu = false
  
  override var intrinsicContentSize: CGSize {
    guard !text.isEmpty else {
      // Return a minimum height for empty text
      return CGSize(width: UIView.noIntrinsicMetric, height: 100)
    }
    
    // Calculate the size that fits the content
    let size = sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
    return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    // Invalidate intrinsic content size when layout changes
    invalidateIntrinsicContentSize()
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if shouldSuppressMenu {
      // Only allow essential actions when suppressing
      let allowedActions: [Selector] = [
        #selector(UIResponderStandardEditActions.cut(_:)),
        #selector(UIResponderStandardEditActions.copy(_:)),
        #selector(UIResponderStandardEditActions.paste(_:)),
      ]
      return allowedActions.contains(action) && super.canPerformAction(action, withSender: sender)
    }
    return super.canPerformAction(action, withSender: sender)
  }
}

// SwiftUI height preference key for dynamic sizing
struct TextViewHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 100
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct MagneticTextEditor: UIViewRepresentable {
  @Binding var text: String
  let editorController: EditorController

  func makeCoordinator() -> Coordinator {
    Coordinator(self, editorController: editorController)
  }

  func makeUIView(context: Context) -> UITextView {
    let tv = MagneticTextView()
    tv.backgroundColor = .clear
    tv.isScrollEnabled = false  // Never scroll internally
    tv.alwaysBounceVertical = false
    tv.keyboardDismissMode = .interactive
    tv.showsVerticalScrollIndicator = false
    tv.delegate = context.coordinator
    
    // Set content compression resistance for proper sizing
    tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    tv.setContentCompressionResistancePriority(.required, for: .vertical)

    // Typography (match design system defaults)
    if let literata = UIFont(name: "Literata", size: 26) {
      tv.font = literata
    } else {
      tv.font = UIFont.preferredFont(forTextStyle: .title2)
    }
    tv.textColor = UIColor { trait in
      trait.userInterfaceStyle == .dark ? .white : .black
    }
    // Typewriter vibe: warm accent caret
    tv.tintColor = UIColor { _ in UIColor(hex: "F59E0B") }  // successGold

    // Seed initial text
    tv.text = text

    // Install single-tap word selection
    context.coordinator.attach(to: tv)

    return tv
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    if uiView.text != text {
      uiView.text = text
      // Always invalidate size when text changes
      uiView.invalidateIntrinsicContentSize()
    }
  }

  // MARK: - Coordinator
  class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var parent: MagneticTextEditor
    weak var textView: UITextView?
    let editorController: EditorController

    init(_ parent: MagneticTextEditor, editorController: EditorController) {
      self.parent = parent
      self.editorController = editorController
      super.init()
    }

    func attach(to textView: UITextView) {
      self.textView = textView
      editorController.textView = textView
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      tap.numberOfTapsRequired = 1
      tap.cancelsTouchesInView = true  // prevent default caret-only tap
      tap.delegate = self
      textView.addGestureRecognizer(tap)
    }

    // MARK: UITextViewDelegate
    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      editorController.textViewDidChange(textView)
      // Always invalidate size when text changes
      textView.invalidateIntrinsicContentSize()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      editorController.textViewDidChangeSelection(textView)
    }

    // Keep the system gestures (long-press, drag) working.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      true
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
      guard let tv = textView else { return }
      let point = gr.location(in: tv)

      // Convert tap point -> nearest text position
      guard let pos = tv.closestPosition(to: point) else { return }
      let tok = tv.tokenizer
      let dir = UITextDirection.storage(.forward)

      // Select enclosing word; fallback to single character
      if let wordRange = tok.rangeEnclosingPosition(pos, with: .word, inDirection: dir) {
        tv.becomeFirstResponder()
        tv.selectedTextRange = wordRange
        // Notify EditorController to handle the selection
        editorController.handleWordSelection(at: wordRange)
      } else if let charRange = tok.rangeEnclosingPosition(pos, with: .character, inDirection: dir)
      {
        tv.becomeFirstResponder()
        tv.selectedTextRange = charRange
      }
    }
  }

}
