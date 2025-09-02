import UIKit

@Observable
@MainActor
final class EditorController: NSObject {
  public var wordsCount: Int = 0

  private let versionStore: VersionStore
  private let thesaurus = Thesaurus()

  weak var textView: UITextView? {
    didSet {
      if let textView {
        let interaction = UIEditMenuInteraction(delegate: self)
        self.editMenuInteraction = interaction
        textView.addInteraction(interaction)

        wordsCount =
          textView.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
          .count
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

  init(versionStore: VersionStore) {
    self.versionStore = versionStore

    super.init()
  }

  func generateInitialTitle() {
    if versionStore.document.title.isEmpty {
      Task {
        let title = try? await thesaurus.initialTitle()
        versionStore.document.title = title ?? ""
      }
    }
  }

  func handleWordSelection(at range: UITextRange) {
    guard let textView else { return }
    textViewDidChangeSelection(textView)
  }

  func restoreVersion(_ version: Version) {
    guard let tv = textView else { return }
    isRestoringVersion = true
    tv.text = version.text
    wordsCount = version.metadata.wordCount

    // Restore cursor position if available
    if let cursorPos = version.metadata.cursorPosition,
      let position = tv.position(from: tv.beginningOfDocument, offset: cursorPos)
    {
      tv.selectedTextRange = tv.textRange(from: position, to: position)
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
}

// MARK: - UITextViewDelegate
extension EditorController: UITextViewDelegate {
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
        self.wordsCount = wordsCount
        self.versionStore.createVersion(
          text: text,
          changeType: .manual,
          cursorPosition: cursorPosition,
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

          // Replace the text
          tv.replace(range, withText: synonym)

          // Create version for synonym replacement
          let cursorPosition = tv.selectedRange.location
          self.versionStore.createVersion(
            text: tv.text,
            changeType: .synonym(word: originalWord, replacement: synonym),
            cursorPosition: cursorPosition
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
