@testable import FloxBoxCore
import XCTest

final class FormattingClientTests: XCTestCase {
    func testFormattingClientSendsResponsesRequest() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: recorder.configuration)
        let client = OpenAIFormattingClient(apiKey: "sk-test", session: session)

        _ = try await client.format(
            text: "Hello world",
            model: .gpt5Nano,
            glossary: [],
        )

        XCTAssertEqual(recorder.lastRequest?.url?.path, "/v1/responses")
        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(recorder.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(recorder.lastBodyString?.contains("\"model\":\"gpt-5-nano\"") == true)
        XCTAssertTrue(recorder.lastBodyString?.contains("\"input\"") == true)
    }

    func testFormattingClientParsesOutputText() async throws {
        let recorder = RequestRecorder(responseBody: """
        {"output":[{"type":"message","content":[{"type":"output_text","text":"Formatted."}]}]}
        """)
        let session = URLSession(configuration: recorder.configuration)
        let client = OpenAIFormattingClient(apiKey: "sk-test", session: session)

        let text = try await client.format(text: "Raw", model: .gpt5Nano, glossary: [])

        XCTAssertEqual(text, "Formatted.")
    }

    func testFormattingClientSurfacesErrorMessage() async {
        let recorder = RequestRecorder(
            statusCode: 401,
            responseBody: "{\"error\":{\"message\":\"Invalid API key\"}}",
        )
        let session = URLSession(configuration: recorder.configuration)
        let client = OpenAIFormattingClient(apiKey: "sk-test", session: session)

        do {
            _ = try await client.format(text: "Raw", model: .gpt5Nano, glossary: [])
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertTrue(error.localizedDescription.contains("Invalid API key"))
        }
    }
}

private final class RequestRecorder {
    private let protocolType = RequestRecorderProtocol.self
    let configuration: URLSessionConfiguration

    init(
        statusCode: Int = 200,
        responseBody: String =
            "{\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"OK\"}]}]}",
    ) {
        configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolType]
        protocolType.reset(statusCode: statusCode, responseBody: responseBody)
    }

    var lastRequest: URLRequest? { protocolType.lastRequest }
    var lastBodyString: String? {
        guard let data = protocolType.lastBody else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private final class RequestRecorderProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var lastBody: Data?
    static var responseBody = "{}"
    static var statusCode: Int = 200

    static func reset(statusCode: Int, responseBody: String) {
        lastRequest = nil
        lastBody = nil
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? readBodyStream(request.httpBodyStream)

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
