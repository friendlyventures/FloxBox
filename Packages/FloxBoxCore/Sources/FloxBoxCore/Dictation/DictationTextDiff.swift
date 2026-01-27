import Foundation

public struct DictationTextDiff: Equatable {
    public let backspaceCount: Int
    public let insertText: String

    public static func diff(from oldValue: String, to newValue: String) -> DictationTextDiff {
        let prefixCount = zip(oldValue, newValue)
            .prefix { $0 == $1 }
            .count
        let deleteCount = max(0, oldValue.count - prefixCount)
        let insert = String(newValue.dropFirst(prefixCount))
        return DictationTextDiff(backspaceCount: deleteCount, insertText: insert)
    }
}
