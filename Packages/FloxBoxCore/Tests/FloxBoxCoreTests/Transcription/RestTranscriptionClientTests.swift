@testable import FloxBoxCore
import XCTest

final class RestTranscriptionClientTests: XCTestCase {
    func testRestTranscriptionSendsMultipartRequest() async throws {
        let recorder = RequestRecorder()
        let session = URLSession(configuration: recorder.configuration)
        let client = RestTranscriptionClient(apiKey: "sk-test", session: session)

        let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("ptt.wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        try Data([0x00]).write(to: wavURL)

        _ = try await client.transcribe(fileURL: wavURL, model: "gpt-4o-mini-transcribe", language: "en")

        XCTAssertEqual(recorder.lastRequest?.url?.path, "/v1/audio/transcriptions")
        XCTAssertEqual(recorder.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(recorder.lastBodyString?.contains("gpt-4o-mini-transcribe") == true)
        XCTAssertTrue(recorder.lastBodyString?.contains("filename=\"ptt.wav\"") == true)
    }
}

private final class RequestRecorder {
    private let protocolType = RequestRecorderProtocol.self
    let configuration: URLSessionConfiguration

    init() {
        configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolType]
        protocolType.reset()
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

    static func reset() {
        lastRequest = nil
        lastBody = nil
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
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"text\":\"OK\"}".utf8))
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
