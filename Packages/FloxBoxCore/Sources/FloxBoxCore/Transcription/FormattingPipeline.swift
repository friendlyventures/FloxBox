import Foundation

public final class FormattingPipeline {
    private let client: FormattingClientProtocol
    private let validator: FormatValidator
    private let maxAttempts: Int
    private let retryDelayNanos: UInt64

    public init(
        client: FormattingClientProtocol,
        validator: FormatValidator = FormatValidator(),
        maxAttempts: Int = 2,
        retryDelayNanos: UInt64 = 300_000_000,
    ) {
        self.client = client
        self.validator = validator
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelayNanos = retryDelayNanos
    }

    public func format(
        text: String,
        model: FormattingModel,
        glossary: [PersonalGlossaryEntry],
    ) async throws -> String {
        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                let formatted = try await client.format(text: text, model: model, glossary: glossary)
                guard validator.isAcceptable(original: text, formatted: formatted) else {
                    throw FormattingPipelineError.validationFailed
                }
                return formatted
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: retryDelayNanos)
                }
            }
        }
        throw lastError ?? FormattingPipelineError.unknown
    }
}

enum FormattingPipelineError: Error {
    case validationFailed
    case unknown
}
