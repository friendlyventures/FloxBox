import Foundation

public final class RestTranscriptionClient {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func transcribe(fileURL: URL, model: String, language: String?,
                           prompt: String? = nil) async throws -> String
    {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try buildBody(
            fileURL: fileURL,
            model: model,
            language: language,
            prompt: prompt,
            boundary: boundary,
        )
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw RestTranscriptionError.badResponse
        }
        let decoded = try JSONDecoder().decode(RestTranscriptionResponse.self, from: data)
        return decoded.text
    }

    private func buildBody(
        fileURL: URL,
        model: String,
        language: String?,
        prompt: String?,
        boundary: String,
    ) throws -> Data {
        var body = Data()
        body.append(formField(name: "model", value: model, boundary: boundary))
        if let language {
            body.append(formField(name: "language", value: language, boundary: boundary))
        }
        if let prompt, !prompt.isEmpty {
            body.append(formField(name: "prompt", value: prompt, boundary: boundary))
        }
        let fileData = try Data(contentsOf: fileURL)
        body.append(fileField(
            name: "file",
            filename: fileURL.lastPathComponent,
            contentType: "audio/wav",
            data: fileData,
            boundary: boundary,
        ))
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private func formField(name: String, value: String, boundary: String) -> Data {
        var field = Data()
        field.append(Data("--\(boundary)\r\n".utf8))
        field.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        field.append(Data("\(value)\r\n".utf8))
        return field
    }

    private func fileField(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String,
    ) -> Data {
        var field = Data()
        field.append(Data("--\(boundary)\r\n".utf8))
        field.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        field.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        field.append(data)
        field.append(Data("\r\n".utf8))
        return field
    }
}

private struct RestTranscriptionResponse: Decodable {
    let text: String
}

enum RestTranscriptionError: Error {
    case badResponse
}
