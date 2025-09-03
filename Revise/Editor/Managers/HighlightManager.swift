import SwiftUI
import UIKit

@MainActor
final class HighlightManager {
  private var highlightTask: Task<Void, Never>?
  private var defaultTextAttributes: [NSAttributedString.Key: Any] = [:]

  func setDefaultAttributes(font: UIFont, textColor: UIColor) {
    defaultTextAttributes = [
      .font: font,
      .foregroundColor: textColor,
    ]
  }

  func updateDefaultAttributes(font: UIFont? = nil, textColor: UIColor? = nil) {
    if let font = font {
      defaultTextAttributes[.font] = font
    }
    if let textColor = textColor {
      defaultTextAttributes[.foregroundColor] = textColor
    }
  }

  func clearHighlight(in textView: UITextView) {
    // Cancel any pending highlight removal
    highlightTask?.cancel()
    highlightTask = nil

    // Immediately restore default attributes
    let cleanAttributedString = NSMutableAttributedString(string: textView.text)
    let fullRange = NSRange(location: 0, length: cleanAttributedString.length)
    cleanAttributedString.addAttributes(defaultTextAttributes, range: fullRange)
    textView.attributedText = cleanAttributedString
  }

  func applyHighlight(
    at range: NSRange,
    in textView: UITextView,
    changeType: Version.ChangeType,
    duration: TimeInterval = 2.0
  ) {
    // Cancel any existing highlight task
    highlightTask?.cancel()

    let mutableAttributedString = NSMutableAttributedString(string: textView.text)
    let textLength = mutableAttributedString.length
    let fullRange = NSRange(location: 0, length: textLength)

    // Validate and adjust the highlight range to be within bounds
    let validRange: NSRange
    if range.location >= 0 && range.location < textLength {
      // Clamp the range to valid bounds
      let maxLength = textLength - range.location
      let clampedLength = min(range.length, maxLength)
      validRange = NSRange(location: range.location, length: clampedLength)
    } else {
      // Range is completely out of bounds, skip highlighting
      return
    }

    // Apply default attributes to entire text
    mutableAttributedString.addAttributes(defaultTextAttributes, range: fullRange)

    switch changeType {
    case .synonym, .ai:
      // For AI/synonym edits: purple text at the changed range
      mutableAttributedString.addAttribute(
        .foregroundColor,
        value: UIColor(Color.aiPurple),
        range: validRange
      )
    case .manual, .undo, .redo:
      // For manual edits: gray text everywhere except the changed range
      mutableAttributedString.addAttribute(
        .foregroundColor,
        value: UIColor(Color.textSecondary),
        range: fullRange
      )
      // Normal color for the changed part
      mutableAttributedString.addAttribute(
        .foregroundColor,
        value: defaultTextAttributes[.foregroundColor] ?? UIColor(Color.textPrimary),
        range: validRange
      )
    }

    // Update text view
    textView.attributedText = mutableAttributedString

    // Schedule removal of highlight after specified duration
    highlightTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

      guard !Task.isCancelled else { return }

      // Remove highlight - restore default attributes
      let cleanAttributedString = NSMutableAttributedString(string: textView.text)
      let cleanFullRange = NSRange(location: 0, length: cleanAttributedString.length)
      cleanAttributedString.addAttributes(self.defaultTextAttributes, range: cleanFullRange)
      textView.attributedText = cleanAttributedString
    }
  }

  func hasActiveHighlight() -> Bool {
    highlightTask != nil
  }

  func cancelHighlight() {
    highlightTask?.cancel()
    highlightTask = nil
  }
}
