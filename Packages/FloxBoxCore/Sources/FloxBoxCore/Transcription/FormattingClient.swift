import Foundation

public protocol FormattingClientProtocol {
    func format(text: String, model: FormattingModel, glossary: [PersonalGlossaryEntry]) async throws -> String
}

public final class OpenAIFormattingClient: FormattingClientProtocol {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let promptBuilder: FormattingPromptBuilder

    public init(
        apiKey: String,
        session: URLSession = .shared,
        promptBuilder: FormattingPromptBuilder = FormattingPromptBuilder(),
    ) {
        self.apiKey = apiKey
        self.session = session
        self.promptBuilder = promptBuilder
    }

    public func format(text: String, model: FormattingModel, glossary: [PersonalGlossaryEntry]) async throws -> String {
        let prompt = promptBuilder.makePrompt(text: text, glossary: glossary)
        let payload = ResponseRequest(model: model.rawValue, input: prompt, temperature: 0.1)
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw FormattingClientError.badResponse
        }
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let text = decoded.outputText
        guard !text.isEmpty else { throw FormattingClientError.emptyOutput }
        return text
    }
}

private struct ResponseRequest: Encodable {
    let model: String
    let input: String
    let temperature: Double
}

private struct ResponseEnvelope: Decodable {
    let output: [ResponseOutputItem]

    var outputText: String {
        output
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .map { $0.text ?? "" }
            .joined()
    }
}

private struct ResponseOutputItem: Decodable {
    let type: String
    let content: [ResponseContent]?
}

private struct ResponseContent: Decodable {
    let type: String
    let text: String?
}

enum FormattingClientError: Error {
    case badResponse
    case emptyOutput
}
