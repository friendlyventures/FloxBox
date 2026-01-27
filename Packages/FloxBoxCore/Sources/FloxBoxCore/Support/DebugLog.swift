import Foundation

#if DEBUG
    enum DebugLog {
        private static let queue = DispatchQueue(label: "com.floxbox.debuglog", qos: .utility)
        private static let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        static func recording(_ message: String) {
            log(fileName: "recording.log", message: message)
        }

        private static func log(fileName: String, message: String) {
            queue.async {
                let timestamp = formatter.string(from: Date())
                let line = "\(timestamp) \(message)\n"
                guard let data = line.data(using: .utf8) else { return }

                let fileManager = FileManager.default
                guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                    return
                }
                let logDir = libraryURL.appendingPathComponent("Logs", isDirectory: true)
                    .appendingPathComponent("FloxBox", isDirectory: true)
                do {
                    try fileManager.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
                    let fileURL = logDir.appendingPathComponent(fileName)
                    if fileManager.fileExists(atPath: fileURL.path) {
                        let handle = try FileHandle(forWritingTo: fileURL)
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                        try handle.close()
                    } else {
                        try data.write(to: fileURL, options: .atomic)
                    }
                } catch {
                    return
                }
            }
        }
    }
#else
    enum DebugLog {
        static func recording(_: String) {}
    }
#endif
