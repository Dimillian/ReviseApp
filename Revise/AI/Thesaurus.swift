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
    languageHint: String? = nil,  // "en", "fr", etc.
    partOfSpeech: String? = nil  // "noun", "verb", "adjective", ...
  ) async throws -> [String] {

    // Lightweight language guess from context if caller doesn't pass one.
    let lang =
      languageHint
      ?? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sentenceContext ?? word)
        return recognizer.dominantLanguage?.rawValue
      }()

    // Build a precise user prompt (short and bounded).
    let prompt: String = """
      Input word: \(word)
      Language (BCP-47 code if known): \(lang ?? "unknown")
      Part of speech (if known): \(partOfSpeech ?? "unknown")
      Context sentence (optional): \(sentenceContext ?? "none")
      Return only synonyms as specified by the schema.
      """

    let response = try await session.respond(
      to: prompt,
      generating: SynonymResult.self
    )

    return response.content.words
  }
}
