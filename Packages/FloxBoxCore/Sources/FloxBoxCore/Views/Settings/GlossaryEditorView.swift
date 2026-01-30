import AppKit
import SwiftUI

public struct GlossaryEditorView: View {
    @Bindable var store: PersonalGlossaryStore

    public init(store: PersonalGlossaryStore) {
        self.store = store
    }

    public var body: some View {
        GroupBox("Personal Glossary") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Normalize names, products, or phrases after transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Term") {
                        addEntry()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if store.entries.isEmpty {
                    Text("No glossary entries yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach($store.entries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $entry.isEnabled)
                                .labelsHidden()
                            TextField("Preferred term", text: $entry.term)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                removeEntry(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        TextField("Aliases (comma-separated)", text: aliasesBinding(for: $entry))
                            .textFieldStyle(.roundedBorder)

                        TextField("Notes (optional)", text: notesBinding(for: $entry))
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor)),
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addEntry() {
        store.entries.append(
            PersonalGlossaryEntry(term: "", aliases: [], notes: nil, isEnabled: true),
        )
    }

    private func removeEntry(_ entry: PersonalGlossaryEntry) {
        store.entries.removeAll { $0.id == entry.id }
    }

    private func aliasesBinding(for entry: Binding<PersonalGlossaryEntry>) -> Binding<String> {
        Binding(
            get: {
                entry.wrappedValue.aliases.joined(separator: ", ")
            },
            set: { value in
                entry.wrappedValue.aliases = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            },
        )
    }

    private func notesBinding(for entry: Binding<PersonalGlossaryEntry>) -> Binding<String> {
        Binding(
            get: {
                entry.wrappedValue.notes ?? ""
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.wrappedValue.notes = trimmed.isEmpty ? nil : value
            },
        )
    }
}
