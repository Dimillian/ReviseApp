import Foundation
import FoundationModels
import NaturalLanguage

@Generable
struct SynonymResult: Equatable {
  // Keep it simple: just words back, no extra prose.
  @Guide(
    description: """
      3–8 single-word synonyms for the input word, closest meaning first.
      Use the SAME language and part-of-speech as the input.
      No duplicates, no multi-word phrases, no profanity.
      """,
    .maximumCount(8)
  )
  var words: [String]
}

struct Thesaurus {
  private let session: LanguageModelSession

  init() {
    // Session-level “system prompt” keeps the model focused across calls.
    self.session = LanguageModelSession(
      instructions: """
        You generate synonyms. Output MUST be only structured data as requested.
        If the word is ambiguous, infer meaning from the provided sentence.
        """)
    session.prewarm()
  }

  /// Ask for synonyms, optionally using surrounding text to disambiguate.
  func synonyms(
    for word: String,
    sentenceContext: String? = nil,
  ) async throws -> [String] {

    // Build a precise user prompt (short and bounded).
    let prompt: String = """
      Input word: \(word)
      Context sentence: \(sentenceContext ?? "none")
      Return only synonyms as specified by the schema.
      """

    let response = try await session.respond(
      to: prompt,
      generating: SynonymResult.self
    )

    return response.content.words
  }
}
