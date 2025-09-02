import UIKit

@Observable
final class EditorController: NSObject {
  public var wordsCount: Int = 0

  private let thesaurus = Thesaurus()
  weak var textView: UITextView? {
    didSet {
      if let textView {
        let interaction = UIEditMenuInteraction(delegate: self)
        self.editMenuInteraction = interaction
        textView.addInteraction(interaction)
      }
    }
  }
  private var cached: [String: [String]] = [:]  // word → synonyms
  private var lastSelectedWord: String?
  private var lastSynonyms: [String] = []
  private var editMenuInteraction: UIEditMenuInteraction?
  private var isLoadingSynonyms = false
  private var suppressSystemMenu = false

  func handleWordSelection(at range: UITextRange) {
    guard let textView else { return }
    textViewDidChangeSelection(textView)
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
    wordsCount =
      textView.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
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
        UIAction(title: synonym) { [weak tv] _ in
          guard let tv, let range = tv.selectedTextRange else { return }
          tv.replace(range, withText: synonym)
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
