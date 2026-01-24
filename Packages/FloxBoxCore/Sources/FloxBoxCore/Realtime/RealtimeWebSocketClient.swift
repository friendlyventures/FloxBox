import Foundation

public enum RealtimeAPI {
    public static let baseURL = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime")!
}

public struct InputAudioBufferAppendEvent: Encodable {
    public let type: String = "input_audio_buffer.append"
    public let audio: String
}

public struct InputAudioBufferCommitEvent: Encodable {
    public let type: String = "input_audio_buffer.commit"
}

public final class RealtimeWebSocketClient {
    private let apiKey: String
    private let urlSession: URLSession
    private var socket: URLSessionWebSocketTask?

    private let stream: AsyncStream<RealtimeServerEvent>
    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation

    public init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
        var continuation: AsyncStream<RealtimeServerEvent>.Continuation!
        self.stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public var events: AsyncStream<RealtimeServerEvent> {
        stream
    }

    public func connect() {
        var request = URLRequest(url: RealtimeAPI.baseURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let socket = urlSession.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        receiveLoop()
    }

    public func sendSessionUpdate(_ update: RealtimeTranscriptionSessionUpdate) async throws {
        try await send(update)
    }

    public func sendAudio(_ data: Data) async throws {
        try await send(InputAudioBufferAppendEvent(audio: data.base64EncodedString()))
    }

    public func commitAudio() async throws {
        try await send(InputAudioBufferCommitEvent())
    }

    public func close() {
        socket?.cancel(with: .goingAway, reason: nil)
        continuation.finish()
    }

    private func send<Event: Encodable>(_ event: Event) async throws {
        guard let socket else { return }
        let payload = try JSONEncoder().encode(event)
        try await socket.send(.data(payload))
    }

    private func receiveLoop() {
        guard let socket else { return }
        Task.detached { [weak self] in
            while true {
                do {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let payload):
                        data = payload
                    case .string(let text):
                        data = Data(text.utf8)
                    @unknown default:
                        continue
                    }

                    if let event = try? RealtimeEventDecoder.decode(data) {
                        self?.continuation.yield(event)
                    }
                } catch {
                    self?.continuation.yield(.error(error.localizedDescription))
                    break
                }
            }
        }
    }
}
