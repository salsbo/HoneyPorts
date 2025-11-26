import Foundation

final class HoneypotLogWriter {
    static let shared = HoneypotLogWriter()

    private let logFileURL: URL
    private let legacyLogURL: URL?
    private let queue = DispatchQueue(label: "com.honeyports.logwriter")
    private let formatter: ISO8601DateFormatter
    private let formatterLock = NSLock()

    private init() {
        let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logFileURL = containerURL.appendingPathComponent("honeypot_logs.json")
        if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            legacyLogURL = supportURL
                .appendingPathComponent("HoneyPorts")
                .appendingPathComponent("logs")
                .appendingPathComponent("honeypot.jsonl")
        } else {
            legacyLogURL = nil
        }
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func timestamp() -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return formatter.string(from: Date())
    }

    func append(entry: [String: Any]) {
        queue.async { [logFileURL] in
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
                guard var jsonString = String(data: jsonData, encoding: .utf8) else { return }
                jsonString.append("\n")
                let data = Data(jsonString.utf8)

                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try data.write(to: logFileURL, options: .atomic)
                }
            } catch {
            }
        }
    }

    func clear(completion: ((Bool) -> Void)? = nil) {
        var success = true
        queue.sync { [logFileURL, legacyLogURL] in
            do {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    try FileManager.default.removeItem(at: logFileURL)
                }

                if let legacy = legacyLogURL, FileManager.default.fileExists(atPath: legacy.path) {
                    try FileManager.default.removeItem(at: legacy)
                }
            } catch {
                success = false
            }
        }

        completion?(success)
    }
}
