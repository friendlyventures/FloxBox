import Foundation

public struct FormatValidator {
    public var minimumSimilarity: Double

    public init(minimumSimilarity: Double = 0.78) {
        self.minimumSimilarity = minimumSimilarity
    }

    public func isAcceptable(original: String, formatted: String) -> Bool {
        let a = normalize(original)
        let b = normalize(formatted)
        guard a.count > 1, b.count > 1 else { return a == b }
        let score = diceCoefficient(a, b)
        return score >= minimumSimilarity
    }

    private func normalize(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func diceCoefficient(_ a: String, _ b: String) -> Double {
        let aBigrams = bigrams(a)
        let bBigrams = bigrams(b)
        guard !aBigrams.isEmpty, !bBigrams.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for gram in aBigrams {
            counts[gram, default: 0] += 1
        }
        var intersection = 0
        for gram in bBigrams {
            if let count = counts[gram], count > 0 {
                intersection += 1
                counts[gram] = count - 1
            }
        }
        return (2.0 * Double(intersection)) / Double(aBigrams.count + bBigrams.count)
    }

    private func bigrams(_ text: String) -> [String] {
        guard text.count >= 2 else { return [] }
        let chars = Array(text)
        return (0 ..< (chars.count - 1)).map { String([chars[$0], chars[$0 + 1]]) }
    }
}
