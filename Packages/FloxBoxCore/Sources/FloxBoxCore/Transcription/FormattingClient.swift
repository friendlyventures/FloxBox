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
        let payload = ResponseRequest(
            model: model.rawValue,
            input: prompt,
            reasoning: ReasoningOptions(effort: model.reasoningEffort),
        )
        let body = try JSONEncoder().encode(payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FormattingClientError.badResponse(statusCode: -1, message: "No HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = Self.extractErrorMessage(from: data)
            throw FormattingClientError.badResponse(statusCode: http.statusCode, message: message)
        }
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let text = decoded.outputText
        guard !text.isEmpty else { throw FormattingClientError.emptyOutput }
        return text
    }
}

private extension OpenAIFormattingClient {
    static func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            var parts: [String] = []
            if let message = decoded.error.message, !message.isEmpty {
                parts.append(message)
            }
            if let type = decoded.error.type, !type.isEmpty {
                parts.append("type=\(type)")
            }
            if let code = decoded.error.code, !code.isEmpty {
                parts.append("code=\(code)")
            }
            if let param = decoded.error.param, !param.isEmpty {
                parts.append("param=\(param)")
            }
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }

        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw.count > 200 ? "\(raw.prefix(200))…" : raw
    }
}

private struct ResponseRequest: Encodable {
    let model: String
    let input: String
    let reasoning: ReasoningOptions
}

private struct ReasoningOptions: Encodable {
    let effort: String
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

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Decodable {
    let message: String?
    let type: String?
    let code: String?
    let param: String?
}

enum FormattingClientError: LocalizedError {
    case badResponse(statusCode: Int, message: String?)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case let .badResponse(statusCode, message):
            if let message, !message.isEmpty {
                return "Formatting failed (HTTP \(statusCode)): \(message)"
            }
            return "Formatting failed (HTTP \(statusCode))"
        case .emptyOutput:
            return "Formatting failed: empty output"
        }
    }
}
