import UIKit

@MainActor
final class SynonymManager: NSObject {
  private let thesaurus = Thesaurus()
  private var cached: [String: [String]] = [:]
  private var lastSelectedWord: String?
  private var lastSynonyms: [String] = []
  private var isLoadingSynonyms = false

  weak var delegate: SynonymManagerDelegate?

  func clearSelection() {
    isLoadingSynonyms = false
    lastSelectedWord = nil
    lastSynonyms = []
  }

  func loadSynonyms(for word: String, context: String) async {
    let key = word.lowercased()

    // Check cache first
    if let cachedList = cached[key] {
      lastSynonyms = cachedList
      isLoadingSynonyms = false
      delegate?.synonymManagerDidLoadSynonyms(cachedList, for: word)
      return
    }

    // Load from API
    isLoadingSynonyms = true
    lastSynonyms = []
    delegate?.synonymManagerDidStartLoading(for: word)

    if let list = try? await thesaurus.synonyms(for: word, sentenceContext: context) {
      cached[key] = list
      lastSynonyms = list
      isLoadingSynonyms = false
      delegate?.synonymManagerDidLoadSynonyms(list, for: word)
    }
  }

  func buildSynonymMenu(
    for word: String,
    suggestedActions: [UIMenuElement],
    onSelect: @escaping (String) -> Void
  ) -> UIMenu? {
    if isLoadingSynonyms {
      // Show loading state
      let loadingAction = UIAction(title: "Loading synonyms…", attributes: .disabled) { _ in }
      let loadingMenu = UIMenu(
        title: "Replace \"\(word)\"",
        options: .displayInline,
        children: [loadingAction]
      )
      return UIMenu(children: [loadingMenu] + suggestedActions)
    } else if !lastSynonyms.isEmpty {
      // Show synonyms
      let top = Array(lastSynonyms.prefix(3))
      let actions: [UIAction] = top.map { synonym in
        UIAction(title: synonym) { _ in
          onSelect(synonym)
        }
      }

      let more = UIAction(title: "More…") { _ in
        // TODO: Present a sheet with full list
      }

      let replaceMenu = UIMenu(
        title: "Replace \"\(word)\"",
        options: .displayInline,
        children: actions + [more]
      )
      return UIMenu(children: [replaceMenu] + suggestedActions)
    } else {
      // No synonyms available
      return UIMenu(children: suggestedActions)
    }
  }

  var hasCachedSynonyms: Bool {
    !lastSynonyms.isEmpty
  }

  var currentWord: String? {
    lastSelectedWord
  }

  func setCurrentWord(_ word: String) {
    lastSelectedWord = word
  }
}

protocol SynonymManagerDelegate: AnyObject {
  func synonymManagerDidStartLoading(for word: String)
  func synonymManagerDidLoadSynonyms(_ synonyms: [String], for word: String)
}
