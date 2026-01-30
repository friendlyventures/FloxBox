import Foundation

public struct TranscriptSegment: Equatable, Identifiable {
    public let id: String
    public var text: String
    public var isFinal: Bool
}

public final class TranscriptStore {
    private var order: [String] = []
    private var segments: [String: TranscriptSegment] = [:]

    public init() {}

    public func reset() {
        order.removeAll()
        segments.removeAll()
        ShortcutDebugLogger.log("transcript.reset")
    }

    public func appendFinalText(_ text: String, id: String = UUID().uuidString) {
        applyCompleted(.init(itemId: id, contentIndex: 0, transcript: text))
    }

    public func applyCommitted(_ event: InputAudioCommittedEvent) {
        guard !order.contains(event.itemId) else { return }
        if let previousId = event.previousItemId, let index = order.firstIndex(of: previousId) {
            order.insert(event.itemId, at: index + 1)
        } else if event.previousItemId == nil {
            order.append(event.itemId)
        } else {
            order.append(event.itemId)
        }
        ShortcutDebugLogger.log(
            "transcript.committed item=\(event.itemId) prev=\(event.previousItemId ?? "nil") orderCount=\(order.count)",
        )
    }

    public func applyDelta(_ event: TranscriptionDeltaEvent) {
        var segment = segments[event.itemId] ?? TranscriptSegment(id: event.itemId, text: "", isFinal: false)
        if !segment.isFinal {
            segment.text += event.delta
        }
        segments[event.itemId] = segment
        if !order.contains(event.itemId) {
            order.append(event.itemId)
        }
    }

    public func applyCompleted(_ event: TranscriptionCompletedEvent) {
        segments[event.itemId] = TranscriptSegment(id: event.itemId, text: event.transcript, isFinal: true)
        if !order.contains(event.itemId) {
            order.append(event.itemId)
        }
        ShortcutDebugLogger.log(
            "transcript.completed item=\(event.itemId) len=\(event.transcript.count) orderCount=\(order.count)",
        )
    }

    public var displayText: String {
        var output = ""
        for itemId in order {
            guard let text = segments[itemId]?.text, !text.isEmpty else { continue }
            if output.isEmpty {
                output = text
                continue
            }
            if shouldInsertSpace(between: output, and: text) {
                output.append(" ")
            }
            output.append(text)
        }
        return output
    }

    private func shouldInsertSpace(between existing: String, and next: String) -> Bool {
        guard let lastChar = existing.last, let firstChar = next.first else { return false }
        if lastChar.isWhitespace || firstChar.isWhitespace {
            return false
        }
        if isClosingPunctuation(firstChar) || isOpeningPunctuation(lastChar) {
            return false
        }
        return true
    }

    private func isClosingPunctuation(_ char: Character) -> Bool {
        ".,!?;:)]}".contains(char)
    }

    private func isOpeningPunctuation(_ char: Character) -> Bool {
        "([{".contains(char)
    }
}
