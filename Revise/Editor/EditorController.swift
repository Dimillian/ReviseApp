import SwiftUI
import UIKit

@Observable
@MainActor
final class EditorController: NSObject {
  public var wordsCount: Int = 0

  private let versionStore: VersionStore
  private let thesaurus = Thesaurus()

  // Store default text attributes
  private var defaultTextAttributes: [NSAttributedString.Key: Any] = [:]

  weak var textView: UITextView? {
    didSet {
      if let textView {
        let interaction = UIEditMenuInteraction(delegate: self)
        self.editMenuInteraction = interaction
        textView.addInteraction(interaction)

        wordsCount =
          textView.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
          .count

        // Capture default text attributes
        defaultTextAttributes = [
          .font: textView.font ?? UIFont.systemFont(ofSize: 17),
          .foregroundColor: UIColor(Color.textPrimary),
        ]
      }
    }
  }
  private var cached: [String: [String]] = [:]  // word → synonyms
  private var lastSelectedWord: String?
  private var lastSynonyms: [String] = []
  private var editMenuInteraction: UIEditMenuInteraction?
  private var isLoadingSynonyms = false
  private var suppressSystemMenu = false
  private var isRestoringVersion = false
  private var isApplyingSynonym = false
  private var versionDebounceTask: Task<Void, Never>?
  private var highlightTask: Task<Void, Never>?

  init(versionStore: VersionStore) {
    self.versionStore = versionStore

    super.init()
  }

  func handleWordSelection(at range: UITextRange) {
    guard let textView else { return }
    textViewDidChangeSelection(textView)
  }

  func restoreVersion(_ version: Version) {
    guard let tv = textView else { return }
    isRestoringVersion = true

    // Set text with default attributes
    let attributedText = NSMutableAttributedString(string: version.text)
    attributedText.addAttributes(
      defaultTextAttributes, range: NSRange(location: 0, length: attributedText.length))
    tv.attributedText = attributedText

    wordsCount = version.metadata.wordCount

    // Restore cursor position if available
    if let cursorPos = version.metadata.cursorPosition,
      let position = tv.position(from: tv.beginningOfDocument, offset: cursorPos)
    {
      tv.selectedTextRange = tv.textRange(from: position, to: position)
    }

    // Apply highlight if this version has highlighted changes
    if let highlightedRange = version.metadata.highlightedRange {
      applyHighlight(at: highlightedRange, in: tv, changeType: version.changeType)
    }

    isRestoringVersion = false
  }

  func undo() {
    if let version = versionStore.undo() {
      restoreVersion(version)
    }
  }

  func redo() {
    if let version = versionStore.redo() {
      restoreVersion(version)
    }
  }

  @MainActor
  private func showEditMenu(for range: UITextRange) {
    guard let tv = textView else { return }
    tv.becomeFirstResponder()
    let rect = tv.firstRect(for: range)
    let anchor = CGPoint(x: rect.midX, y: rect.maxY)
    let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: anchor)
    editMenuInteraction?.presentEditMenu(with: config)
  }

  private func findChangedRange(oldText: String, newText: String) -> NSRange? {
    // Simple diff: find first difference and last difference
    let old = Array(oldText)
    let new = Array(newText)

    let minLen = min(old.count, new.count)
    var firstDiff = minLen
    var lastDiffNew = new.count

    // Find first difference from start
    for i in 0..<minLen {
      if old[i] != new[i] {
        firstDiff = i
        break
      }
    }

    // Find last difference from end
    var oldIdx = old.count - 1
    var newIdx = new.count - 1
    while oldIdx >= firstDiff && newIdx >= firstDiff {
      if old[oldIdx] != new[newIdx] {
        break
      }
      oldIdx -= 1
      newIdx -= 1
    }
    lastDiffNew = newIdx + 1

    // If no changes found
    if firstDiff >= lastDiffNew {
      // Check if only length changed
      if old.count != new.count {
        return NSRange(location: minLen, length: abs(new.count - old.count))
      }
      return nil
    }

    return NSRange(location: firstDiff, length: lastDiffNew - firstDiff)
  }

  @MainActor
  private func clearHighlight() {
    // Cancel any pending highlight removal
    highlightTask?.cancel()
    highlightTask = nil

    // Immediately restore default attributes
    guard let tv = textView else { return }
    let cleanAttributedString = NSMutableAttributedString(string: tv.text)
    let fullRange = NSRange(location: 0, length: cleanAttributedString.length)
    cleanAttributedString.addAttributes(defaultTextAttributes, range: fullRange)
    tv.attributedText = cleanAttributedString
  }

  @MainActor
  private func applyHighlight(
    at range: NSRange, in textView: UITextView, changeType: Version.ChangeType
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

    // Schedule removal of highlight after 2 seconds
    highlightTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

      guard !Task.isCancelled else { return }

      // Remove highlight - restore default attributes
      let cleanAttributedString = NSMutableAttributedString(string: textView.text)
      let cleanFullRange = NSRange(location: 0, length: cleanAttributedString.length)
      cleanAttributedString.addAttributes(self.defaultTextAttributes, range: cleanFullRange)
      textView.attributedText = cleanAttributedString
    }
  }
}

// MARK: - UITextViewDelegate
extension EditorController: UITextViewDelegate {
  func textView(
    _ textView: UITextView, shouldChangeTextInRanges ranges: [NSValue], replacementText text: String
  ) -> Bool {
    if highlightTask != nil {
      clearHighlight()
    }

    return true
  }

  func textViewDidChange(_ textView: UITextView) {
    editMenuInteraction?.dismissMenu()

    guard !isRestoringVersion && !isApplyingSynonym else { return }

    versionDebounceTask?.cancel()

    let text = textView.text ?? ""
    let cursorPosition = textView.selectedRange.location

    versionDebounceTask = Task { [weak self] in
      // Wait for 0.5 seconds
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

      // Check if task was cancelled during sleep
      guard !Task.isCancelled else { return }

      let wordsCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        .count

      let title = try? await self?.thesaurus.title(for: text)

      // Create the version
      await MainActor.run { [weak self] in
        guard let self else { return }

        // Calculate changed range for manual edits using previous version
        let previousText = self.versionStore.currentVersion?.text ?? ""
        let changedRange = self.findChangedRange(oldText: previousText, newText: text)

        // Don't apply highlight when creating the version, only when restoring from timeline

        self.wordsCount = wordsCount
        self.versionStore.createVersion(
          text: text,
          changeType: .manual,
          cursorPosition: cursorPosition,
          highlightedRange: changedRange,
          updatedTitle: title
        )
      }
    }
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    guard let range = textView.selectedTextRange,
      let word = textView.text(in: range),
      !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      isLoadingSynonyms = false
      suppressSystemMenu = false
      if let magneticTV = textView as? MagneticTextView {
        magneticTV.shouldSuppressMenu = false
      }
      return
    }

    lastSelectedWord = word
    suppressSystemMenu = true
    if let magneticTV = textView as? MagneticTextView {
      magneticTV.shouldSuppressMenu = true
    }

    // Show menu immediately with loading state
    let key = word.lowercased()
    if let cachedList = cached[key] {
      lastSynonyms = cachedList
      isLoadingSynonyms = false
      showEditMenu(for: range)
    } else {
      lastSynonyms = []
      isLoadingSynonyms = true
      showEditMenu(for: range)

      Task { [weak self] in
        guard let self else { return }
        let sentenceRange =
          textView.tokenizer.rangeEnclosingPosition(
            range.start,
            with: .sentence,
            inDirection: UITextDirection.storage(.forward)
          ) ?? range
        let context = textView.text(in: sentenceRange) ?? ""
        if let list = try? await thesaurus.synonyms(for: word, sentenceContext: context) {
          self.cached[key] = list
          await MainActor.run {
            self.lastSynonyms = list
            self.isLoadingSynonyms = false
            // Refresh menu with loaded synonyms
            self.editMenuInteraction?.dismissMenu()
            self.showEditMenu(for: range)
          }
        }
      }
    }
  }
}

// MARK: - UIEditMenuInteractionDelegate
extension EditorController: UIEditMenuInteractionDelegate {
  func editMenuInteraction(
    _ interaction: UIEditMenuInteraction,
    menuFor configuration: UIEditMenuConfiguration,
    suggestedActions: [UIMenuElement]
  ) -> UIMenu? {
    guard let tv = textView,
      let word = lastSelectedWord
    else {
      return suppressSystemMenu ? UIMenu(children: []) : UIMenu(children: suggestedActions)
    }

    // Filter out standard actions if we're suppressing
    let filteredActions =
      suppressSystemMenu
      ? suggestedActions.filter { element in
        // Keep only essential actions like Cut, Copy, Paste
        if let action = element as? UIAction {
          return ["Cut", "Copy", "Paste"].contains(action.title)
        }
        return false
      } : suggestedActions

    if isLoadingSynonyms {
      // Show loading state
      let loadingAction = UIAction(title: "Loading synonyms…", attributes: .disabled) { _ in }
      let loadingMenu = UIMenu(
        title: "Replace \"\(word)\"", options: .displayInline, children: [loadingAction])
      return UIMenu(children: [loadingMenu] + filteredActions)
    } else if !lastSynonyms.isEmpty {
      // Show synonyms
      let top = Array(lastSynonyms.prefix(3))
      let actions: [UIAction] = top.map { synonym in
        UIAction(title: synonym) { [weak self, weak tv] _ in
          guard let self, let tv, let range = tv.selectedTextRange else { return }

          // Cancel any pending version task
          self.versionDebounceTask?.cancel()

          // Set flag to prevent duplicate version from textViewDidChange
          self.isApplyingSynonym = true

          // Create version before replacement
          let originalWord = tv.text(in: range) ?? ""

          // Calculate the new range for the replaced text
          let replacementLocation = tv.offset(from: tv.beginningOfDocument, to: range.start)
          let replacementRange = NSRange(location: replacementLocation, length: synonym.count)

          // Replace the text
          tv.replace(range, withText: synonym)

          // Don't apply highlight when creating the version, only when restoring from timeline

          // Create version for synonym replacement with highlighted range
          let cursorPosition = tv.selectedRange.location
          let newText = tv.text ?? ""
          self.versionStore.createVersion(
            text: newText,
            changeType: .synonym(word: originalWord, replacement: synonym),
            cursorPosition: cursorPosition,
            highlightedRange: replacementRange
          )

          // Reset flag after a small delay to ensure textViewDidChange has been called
          DispatchQueue.main.async {
            self.isApplyingSynonym = false
          }
        }
      }
      let more = UIAction(title: "More…") { [weak self] _ in
        // Present a sheet with full list
        _ = self  // placeholder to keep self captured
      }

      let replaceMenu = UIMenu(
        title: "Replace \"\(word)\"", options: .displayInline, children: actions + [more])
      return UIMenu(children: [replaceMenu] + filteredActions)
    } else {
      // No synonyms available yet
      return UIMenu(children: filteredActions)
    }
  }
}
