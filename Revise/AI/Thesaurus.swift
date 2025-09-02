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
    self.session = LanguageModelSession()
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

  func title(for text: String) async throws -> String {
    let prompt: String = """
      Input text: \(text)
      Return a simple title that fit for the text.
      Don't wrap it in any JSON, simply return the title as a string, without any quotation marks.
      """

    let response = try await session.respond(to: prompt)

    return response.content
  }

  func initialTitle() async throws -> String {
    let prompt: String = """
      Return a simple to world title for a new document. 
      Like "Sigma Alpha". 
      Two random words.
      Don't wrap it in any JSON, simply return the title as a string, without any quotation marks.
      """

    let response = try await session.respond(to: prompt)

    return response.content
  }
}
