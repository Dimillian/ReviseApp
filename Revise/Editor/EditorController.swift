import SwiftUI
import UIKit

@Observable
@MainActor
final class EditorController: NSObject {
  public var wordsCount: Int = 0

  var versionController: VersionController?
  private let highlightManager = HighlightManager()
  private let synonymManager = SynonymManager()
  private let thesaurus = Thesaurus()

  weak var textView: UITextView? {
    didSet {
      setupTextView()
    }
  }

  private var editMenuInteraction: UIEditMenuInteraction?
  private var suppressSystemMenu = false
  private var isRestoringVersion = false
  private var isApplyingSynonym = false
  private var versionDebounceTask: Task<Void, Never>?

  init(versionController: VersionController? = nil) {
    self.versionController = versionController
    super.init()
    synonymManager.delegate = self
  }

  // MARK: - Setup

  private func setupTextView() {
    guard let textView else { return }

    let interaction = UIEditMenuInteraction(delegate: self)
    self.editMenuInteraction = interaction
    textView.addInteraction(interaction)

    wordsCount = TextDiffManager.calculateWordCount(for: textView.text)

    // Setup highlight manager with default attributes
    highlightManager.setDefaultAttributes(
      font: textView.font ?? UIFont.systemFont(ofSize: 17),
      textColor: UIColor(Color.textPrimary)
    )
  }

  // MARK: - Public Methods

  func handleWordSelection(at range: UITextRange) {
    guard let textView else { return }
    textViewDidChangeSelection(textView)
  }

  func restoreVersion(_ version: Version) {
    guard let tv = textView else { return }
    isRestoringVersion = true

    // Set text with default attributes
    let attributedText = NSMutableAttributedString(string: version.text)
    let fullRange = NSRange(location: 0, length: attributedText.length)
    highlightManager.setDefaultAttributes(
      font: tv.font ?? UIFont.systemFont(ofSize: 17),
      textColor: UIColor(Color.textPrimary)
    )
    attributedText.addAttributes(
      [
        .font: tv.font ?? UIFont.systemFont(ofSize: 17),
        .foregroundColor: UIColor(Color.textPrimary),
      ], range: fullRange)
    tv.attributedText = attributedText

    wordsCount = version.wordCount

    // Restore cursor position if available
    if let cursorPos = version.cursorPosition,
      let position = tv.position(from: tv.beginningOfDocument, offset: cursorPos)
    {
      tv.selectedTextRange = tv.textRange(from: position, to: position)
    }

    // Apply highlight if this version has highlighted changes
    if let highlightedRange = version.highlightedRange {
      highlightManager.applyHighlight(
        at: highlightedRange,
        in: tv,
        changeType: version.changeType
      )
    }

    isRestoringVersion = false
  }

  func undo() {
    if let version = versionController?.undo() {
      restoreVersion(version)
    }
  }

  func redo() {
    if let version = versionController?.redo() {
      restoreVersion(version)
    }
  }

  func createNewBranch() async {
    let title = try? await thesaurus.branchTitle()
    if let title {
      versionController?.createBranch(named: title)
      versionController?.switchToBranch(named: title)
    }
  }

  func switchBranch(to branch: String) {
    versionController?.switchToBranch(named: branch)
    if let version = versionController?.currentVersion {
      restoreVersion(version)
    }
  }

  func updateDefaultAttributes(font: UIFont? = nil, textColor: UIColor? = nil) {
    highlightManager.updateDefaultAttributes(font: font, textColor: textColor)

    // Apply new attributes to current text if no highlight is active
    if !highlightManager.hasActiveHighlight(), let tv = textView {
      let attributedText = NSMutableAttributedString(string: tv.text)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font ?? tv.font ?? UIFont.systemFont(ofSize: 17),
        .foregroundColor: textColor ?? UIColor(Color.textPrimary),
      ]
      attributedText.addAttributes(
        attrs, range: NSRange(location: 0, length: attributedText.length))
      tv.attributedText = attributedText
    }
  }

  // MARK: - Private Methods

  @MainActor
  private func showEditMenu(for range: UITextRange) {
    guard let tv = textView else { return }
    tv.becomeFirstResponder()
    let rect = tv.firstRect(for: range)
    let anchor = CGPoint(x: rect.midX, y: rect.maxY)
    let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: anchor)
    editMenuInteraction?.presentEditMenu(with: config)
  }

  private func createVersion(text: String, cursorPosition: Int) async {
    let wordsCount = TextDiffManager.calculateWordCount(for: text)
    let title = try? await thesaurus.title(for: text)

    await MainActor.run { [weak self] in
      guard let self else { return }

      // Calculate changed range for manual edits
      let previousText = self.versionController?.currentVersion?.text ?? ""
      let changedRange = TextDiffManager.findChangedRange(
        oldText: previousText,
        newText: text
      )

      // Don't apply highlight when creating the version, only when restoring from timeline

      self.wordsCount = wordsCount
      self.versionController?.addVersion(
        text: text,
        changeType: .manual,
        cursorPosition: cursorPosition,
        highlightedRange: changedRange,
        updatedTitle: title
      )
    }
  }

  private func applySynonymReplacement(
    synonym: String,
    for range: UITextRange,
    originalWord: String
  ) {
    guard let tv = textView else { return }

    // Cancel any pending version task
    versionDebounceTask?.cancel()

    // Set flag to prevent duplicate version
    isApplyingSynonym = true

    // Calculate the new range for the replaced text
    let replacementLocation = tv.offset(from: tv.beginningOfDocument, to: range.start)
    let replacementRange = NSRange(location: replacementLocation, length: synonym.count)

    // Replace the text
    tv.replace(range, withText: synonym)

    // Don't apply highlight when creating the version, only when restoring from timeline

    // Create version for synonym replacement
    let cursorPosition = tv.selectedRange.location
    let newText = tv.text ?? ""
    versionController?.addVersion(
      text: newText,
      changeType: .synonym(word: originalWord, replacement: synonym),
      cursorPosition: cursorPosition,
      highlightedRange: replacementRange
    )

    // Reset flag after a small delay
    DispatchQueue.main.async { [weak self] in
      self?.isApplyingSynonym = false
    }
  }
}

extension EditorController: UITextViewDelegate {
  func textView(
    _ textView: UITextView,
    shouldChangeTextIn range: NSRange,
    replacementText text: String
  ) -> Bool {
    if highlightManager.hasActiveHighlight() {
      highlightManager.clearHighlight(in: textView)
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
      try? await Task.sleep(nanoseconds: 500_000_000)

      // Check if task was cancelled
      guard !Task.isCancelled else { return }

      await self?.createVersion(text: text, cursorPosition: cursorPosition)
    }
  }

  func textViewDidChangeSelection(_ textView: UITextView) {
    guard let range = textView.selectedTextRange,
      let word = textView.text(in: range),
      !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      synonymManager.clearSelection()
      suppressSystemMenu = false
      if let magneticTV = textView as? MagneticTextView {
        magneticTV.shouldSuppressMenu = false
      }
      return
    }

    synonymManager.setCurrentWord(word)
    suppressSystemMenu = true
    if let magneticTV = textView as? MagneticTextView {
      magneticTV.shouldSuppressMenu = true
    }

    // Get context and load synonyms
    let sentenceRange =
      textView.tokenizer.rangeEnclosingPosition(
        range.start,
        with: .sentence,
        inDirection: UITextDirection.storage(.forward)
      ) ?? range
    let context = textView.text(in: sentenceRange) ?? ""

    // Show menu immediately (will show loading state)
    showEditMenu(for: range)

    // Load synonyms asynchronously
    Task {
      await synonymManager.loadSynonyms(for: word, context: context)
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
      let word = synonymManager.currentWord
    else {
      return suppressSystemMenu ? UIMenu(children: []) : UIMenu(children: suggestedActions)
    }

    // Filter out standard actions if we're suppressing
    let filteredActions =
      suppressSystemMenu
      ? suggestedActions.filter { element in
        if let action = element as? UIAction {
          return ["Cut", "Copy", "Paste"].contains(action.title)
        }
        return false
      }
      : suggestedActions

    return synonymManager.buildSynonymMenu(
      for: word,
      suggestedActions: filteredActions
    ) { [weak self, weak tv] synonym in
      guard let self, let tv, let range = tv.selectedTextRange else { return }
      let originalWord = tv.text(in: range) ?? ""
      self.applySynonymReplacement(
        synonym: synonym,
        for: range,
        originalWord: originalWord
      )
    }
  }
}

// MARK: - SynonymManagerDelegate
extension EditorController: SynonymManagerDelegate {
  func synonymManagerDidStartLoading(for word: String) {
    // Refresh menu to show loading state
    guard let tv = textView,
      let range = tv.selectedTextRange
    else { return }
    editMenuInteraction?.dismissMenu()
    showEditMenu(for: range)
  }

  func synonymManagerDidLoadSynonyms(_ synonyms: [String], for word: String) {
    // Refresh menu with loaded synonyms
    guard let tv = textView,
      let range = tv.selectedTextRange
    else { return }
    editMenuInteraction?.dismissMenu()
    showEditMenu(for: range)
  }
}
