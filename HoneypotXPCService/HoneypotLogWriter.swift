import Foundation

final class HoneypotLogWriter {
    static let shared = HoneypotLogWriter()

    // MARK: - Configuration limites
    private static let maxLogSize: Int = 50 * 1024 * 1024  // 50 MB max
    private static let maxArchivedFiles: Int = 5           // Garder 5 archives max
    private static let rotationCheckInterval: Int = 100    // Vérifier tous les 100 appends

    private let logFileURL: URL
    private let logDirectory: URL
    private let legacyLogURL: URL?
    private let queue = DispatchQueue(label: "com.honeyports.logwriter")
    private let formatter: ISO8601DateFormatter
    private let formatterLock = NSLock()
    private var appendCount = 0

    private init() {
        let containerURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = containerURL
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
        queue.async { [weak self] in
            guard let self = self else { return }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
                guard var jsonString = String(data: jsonData, encoding: .utf8) else { return }
                jsonString.append("\n")
                let data = Data(jsonString.utf8)

                // Vérifier la rotation périodiquement
                self.appendCount += 1
                if self.appendCount >= HoneypotLogWriter.rotationCheckInterval {
                    self.appendCount = 0
                    self.rotateIfNeeded()
                }

                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try data.write(to: self.logFileURL, options: .atomic)
                }
            } catch {
            }
        }
    }

    // MARK: - Rotation des logs

    private func rotateIfNeeded() {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0

            if fileSize > HoneypotLogWriter.maxLogSize {
                rotateLog()
            }
        } catch {
            // Ignorer les erreurs de lecture d'attributs
        }
    }

    private func rotateLog() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let archivedName = "honeypot_logs_\(timestamp).json"
        let archivedURL = logDirectory.appendingPathComponent(archivedName)

        do {
            // Renommer le fichier actuel
            try FileManager.default.moveItem(at: logFileURL, to: archivedURL)

            // Nettoyer les anciennes archives
            cleanOldArchives()
        } catch {
            // En cas d'erreur, tenter de tronquer le fichier
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.truncateFile(atOffset: 0)
                handle.closeFile()
            }
        }
    }

    private func cleanOldArchives() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey])
            let archives = files.filter { $0.lastPathComponent.hasPrefix("honeypot_logs_") && $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2  // Plus récent en premier
                }

            // Supprimer les archives excédentaires
            if archives.count > HoneypotLogWriter.maxArchivedFiles {
                for archive in archives.dropFirst(HoneypotLogWriter.maxArchivedFiles) {
                    try? FileManager.default.removeItem(at: archive)
                }
            }
        } catch {
            // Ignorer les erreurs de nettoyage
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
