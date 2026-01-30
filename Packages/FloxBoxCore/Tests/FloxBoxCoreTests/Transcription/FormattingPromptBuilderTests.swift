@testable import FloxBoxCore
import XCTest

final class FormattingPromptBuilderTests: XCTestCase {
    func testPromptIncludesRulesAndGlossary() {
        let builder = FormattingPromptBuilder()
        let glossary = [
            PersonalGlossaryEntry(term: "OpenAI", aliases: ["Open AI"], notes: nil, isEnabled: true),
        ]

        let prompt = builder.makePrompt(text: "Open AI makes models.", glossary: glossary)

        XCTAssertTrue(prompt.contains("Do not paraphrase"))
        XCTAssertTrue(prompt.contains("OpenAI"))
        XCTAssertTrue(prompt.contains("Open AI"))
        XCTAssertTrue(prompt.contains("Transcript:"))
    }
}
