import Foundation

public struct FormattingPromptBuilder {
    public init() {}

    public func makePrompt(text: String, glossary: [PersonalGlossaryEntry]) -> String {
        let glossaryLines = glossary
            .filter(\.isEnabled)
            .map { entry in
                let aliases = entry.aliases.joined(separator: ", ")
                return "- Preferred: \(entry.term). Variants: \(aliases)"
            }
            .joined(separator: "\n")

        let glossaryBlock = glossaryLines.isEmpty
            ? "(no glossary entries)"
            : glossaryLines

        return """
        You are a transcript post-processor. Return only the corrected transcript.
        Rules:
        - Do not paraphrase, summarize, or change meaning.
        - Preserve words except for obvious transcription corrections.
        - Fix punctuation, casing, spacing, and paragraphing only.
        - Use paragraph breaks for topic shifts, not pauses.
        - Apply glossary: replace variants with the preferred term.
        - Output only the final transcript with no commentary.

        Glossary:
        \(glossaryBlock)

        Transcript:
        \(text)
        """
    }
}
