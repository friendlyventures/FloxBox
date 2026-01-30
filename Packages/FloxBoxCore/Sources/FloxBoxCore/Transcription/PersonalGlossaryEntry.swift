import Foundation

public struct PersonalGlossaryEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var term: String
    public var aliases: [String]
    public var notes: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        term: String,
        aliases: [String],
        notes: String?,
        isEnabled: Bool,
    ) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.notes = notes
        self.isEnabled = isEnabled
    }
}
