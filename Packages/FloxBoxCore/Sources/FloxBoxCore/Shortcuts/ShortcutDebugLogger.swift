import Foundation

#if DEBUG
    enum ShortcutDebugLogger {
        private static let queue = DispatchQueue(label: "org.friendlyventures.FloxBox.shortcuts.logger")
        private static let url: URL = {
            let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return base
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("FloxBox", isDirectory: true)
                .appendingPathComponent("shortcuts.log")
        }()

        private static let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        static func log(_ message: String) {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            queue.async {
                let directory = url.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
        }
    }
#else
    enum ShortcutDebugLogger {
        static func log(_: String) {}
    }
#endif
