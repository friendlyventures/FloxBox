@testable import FloxBoxCore
import XCTest

final class FormattingPipelineTests: XCTestCase {
    func testPipelineRetriesOnFailure() async {
        let client = TestFormattingClient(results: [.failure, .success("Hi.")])
        let pipeline = FormattingPipeline(client: client, validator: FormatValidator(), maxAttempts: 2)

        let result = try? await pipeline.format(text: "Hi", model: .gpt5Nano, glossary: [])

        XCTAssertEqual(result, "Hi.")
        XCTAssertEqual(client.callCount, 2)
    }

    func testPipelineFailsWhenValidationRejects() async {
        let client = TestFormattingClient(results: [.success("Bad")])
        let validator = FormatValidator(minimumSimilarity: 0.99)
        let pipeline = FormattingPipeline(client: client, validator: validator, maxAttempts: 1)

        do {
            _ = try await pipeline.format(text: "Good", model: .gpt5Nano, glossary: [])
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(client.callCount, 1)
        }
    }
}
